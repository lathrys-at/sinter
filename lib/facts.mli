(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The facts of the markdown files of one tree, as JSON Lines records.

    A file is a plan file when its path starts with [.plans/] and its first tag
    block holds a tag of the word [plan]. A plan file whose tag target of [plan]
    {!Plan_target.parse} reads gives a [plan] record, a [step] record for each
    step, and a [promise] record for each promise; any other plan file gives no
    record. Every other file gives a record for each declaration of the kinds
    [req], [design], and [decision], each edge, each site, and each ack. Each
    distinct external id that an edge names and that resolves gives one
    [external] record.

    The records take the values that hold when the evidence and the session are
    absent, and as if the ledger held no entry: every plan is open, no plan and
    no step is active, nothing is declined, an item of a kind that needs
    approval is not approved, and a step without promises is not approved while
    [proof.step] is ["approval"]. Every other step is approved when its plan is.
*)

type t
(** The facts of one tree. *)

val may_hold_plan : string -> bool
(** [may_hold_plan path] is [true] when [path] starts with [.plans/]: only a
    file at such a path can be a plan file. *)

val make :
  Manifest.t -> ledger:Ledger.entry list -> (string * Markdown.t) list -> t
(** [make manifest ~ledger files] is the facts of [files] with the entries
    [ledger] of the ledger, in the order of their [seq] ({!Ledger.compare}).
    Each pair is the path of one file, relative to the repository root, and the
    document that {!Markdown.read} gave for the file. No path occurs twice. The
    manifest gives the namespaces, the kinds that need approval, and the default
    locations of the kinds. No fact and no record depends on [ledger].

    @raise Invalid_argument
      if the document of a plan file that gives a plan holds no text of a
      section ({!Markdown.section.text}). *)

val manifest : t -> Manifest.t
(** [manifest facts] is the manifest that {!make} took. *)

val ledger : t -> Ledger.entry list
(** [ledger facts] is the entries of the ledger that {!make} took, in their
    order. *)

val files : t -> (string * Markdown.t) list
(** [files facts] is the files that {!make} took, in their order. *)

type identity = private {
  kind : string;  (** the kind of the fact, as its record names it *)
  id : string;  (** the id of the fact *)
  place : (string * Markdown.span) option;
      (** the path and the span of the record of the fact; [None] for a fact
          that has no place, an [external] *)
}
(** The identity of one fact. *)

val identities : t -> identity list
(** [identities facts] is the identity of each fact that {!records} gives a
    record for: each declaration, edge, site, ack, plan, step, promise, and
    external id, in this order of kinds. An external id that several edges name
    comes once. *)

val iter_identities :
  ?within:(string -> bool) -> t -> (identity -> unit) -> unit
(** [iter_identities ~within facts f] calls [f] on each identity of
    {!identities} [facts], in its order, whose place has a path for which
    [within] is [true], and on each external id that an edge of such a path
    names. [within] is [true] for every path when absent. *)

val records : ?deliveries:Delivery_line.found list -> t -> Jsonl.record list
(** [records ~deliveries facts] is every record of [facts], in the order of
    [(kind, path, line, col, id)], with each record that has no path after the
    others, in the order of their ids. [deliveries] is the delivery lines of the
    change; it is empty when absent.

    A step is delivered when a line of [deliveries] counts for it: the line
    matches the pattern, {!named} gives the step for it, and {!counts} holds.
    The record of each step holds [delivered]; its step hash, [csh], as
    {!step.hash} gives it; and [delivery], the text of {!delivery} of the step,
    when there is one. A step with no promise is done only when [proof.step] is
    ["delivered"] and the step is delivered: under ["approval"] no step is
    approved while the ledger is absent, and under ["promises"] such a step is
    never done.

    Every string of the result is valid UTF-8 when every path of [make] is. *)

(** {1 The facts as values}

    A read-only view of the facts of {!make}, for the checks that read them. *)

type declaration = private {
  kind : string;  (** [req], [design], [decision], or [rule] *)
  slug : string;
  rev : int;  (** the revision; [1] when the tag gives none *)
  path : string;
  span : Markdown.span;  (** the tag line *)
  extent : Markdown.extent;
  title : string option;
      (** the heading text of the section, for a declaration in the first
          paragraph of a section *)
  desc : string;  (** the description; [""] when there is none *)
  status : string option;
      (** the status word that applies: [deprecated], [rejected], or [deferred]
      *)
  tag : Markdown.tag;  (** the tag line, as the document of the file holds it *)
}
(** One declaration of a file that is not a plan file. *)

(** What the tag target of an edge resolves to. *)
type target = private
  | Declaration of int
      (** the declaration at this index of {!declarations}: the first of the
          declarations of the kinds [req], [design], and [decision] that have
          the slug, in the order of the records *)
  | External of { ns : string; id : string }
      (** an external id whose namespace the manifest declares and whose id
          matches the pattern of the namespace *)
  | Unresolved of { dangling : bool }
      (** nothing; [dangling] is [true] when the tag target is a valid slug *)

type edge = private {
  word : string;
      (** [satisfies], [verifies], [refines], [cites], or [supersedes] *)
  path : string;
  span : Markdown.span;  (** the tag line *)
  src : string;  (** the id of the source *)
  source : int option;
      (** the index in {!declarations} of the source, when the source is a
          declaration; [None] when it is a site *)
  target_text : string;  (** the tag target as the text writes it *)
  rev : int option;
  desc : string;  (** the inline description; [""] when there is none *)
  block_index : int;
      (** the index of the block of the tag line in the blocks of its document
      *)
  tag : Markdown.tag;  (** the tag line, as the document of the file holds it *)
}
(** One edge. *)

type ack = private {
  path : string;
  span : Markdown.span;  (** the tag line *)
  block : string;  (** the id of the declaration or the site of the block *)
  target : string;
      (** the text between the tag word and the hash, without the spaces and
          tabs at its ends; never empty *)
  hash : string;  (** the last token of the line *)
  block_index : int;
      (** the index of the block of the tag line in the blocks of its document
      *)
}
(** One [@ack] tag line whose block has a declaration or a site. *)

type promise = private {
  word : string;
  target : string;
  span : Markdown.span;
  tag : Markdown.tag;
}
(** One promise: the word and the tag target of its first tag line, the span of
    that line, and that line as the document of the plan file holds it. *)

type step = private {
  slug : string;
  title : string;
  span : Markdown.span;  (** the heading line *)
  own_scope : string list option;  (** the globs of the [@scope] of the step *)
  promises : promise list;
      (** in the order of the file, each word and tag target once *)
  hash : string;
      (** the step hash, as 64 lowercase hexadecimal digits: the SHA-256 of the
          canonical JSON object with the keys [promises], [prose], and [scope].
          [promises] holds an object with the keys [target] and [word] for each
          promise, sorted by the word and then by the tag target, in byte order.
          [prose] is the {!Markdown.section.text} of the section of the step.
          [scope] holds the globs of the effective scope, each once, in byte
          order. *)
}
(** One step of a plan. *)

type plan = private {
  slug : string;
  id : Plan_target.id option;  (** the plan id, when the tag target has one *)
  path : string;
  span : Markdown.span;  (** the tag line of [@plan] *)
  title : string option;
  scope : string list;  (** the globs of the [@scope] of the plan *)
  steps : step list;  (** in the order of the file *)
  tag : Markdown.tag;
      (** the tag line of [@plan], as the document of the file holds it *)
}
(** One plan file. *)

val declaration_id : declaration -> string
(** [declaration_id declaration] is [<kind>:<slug>]. *)

val edge_id : edge -> string
(** [edge_id edge] is [<word>:<src>-><tag target>]. *)

val ack_id : ack -> string
(** [ack_id ack] is [ack:<block>:<target>], with {!ack.block} and {!ack.target}.
*)

val short_hash : step -> string
(** [short_hash step] is the first six digits of {!step.hash}. *)

val delivery : plan -> step -> Delivery_line.t option
(** [delivery plan step] is the delivery line of [step] of [plan]: the
    {!full_form} of [plan], the slug of [step], and {!short_hash} [step]. It is
    [None] when the slug of [step] is not a slug, as for a heading with no
    letter and no digit. *)

val named : t -> Delivery_line.t -> (plan * step) option
(** [named facts line] is the step that [line] names: the first plan of {!plans}
    whose {!full_form} is the plan of [line], and its first step whose slug is
    the step of [line]. It is [None] when [facts] hold no such step.
    [named facts] builds its table once, and gives a function that each line can
    share. *)

val counts : step -> Delivery_line.t -> bool
(** [counts step line] is [true] when the hash of [line] is {!short_hash}
    [step]. *)

val full_form : plan -> string
(** [full_form plan] is the full form of [plan]: its slug, then [@] and its plan
    id when it has one. *)

val plan_fact_id : plan -> string
(** [plan_fact_id plan] is [plan:<full form>]. *)

val step_id : plan -> step -> string
(** [step_id plan step] is [step:<full form of the plan>/<step slug>]. *)

val promise_id : plan -> step -> promise -> string
(** [promise_id plan step promise] is [promise:<step id>:<word>:<tag target>].
*)

val declarations : t -> declaration list
(** [declarations facts] is every declaration, in the order of the files of
    {!make} and then of the lines. The index of a declaration in this list is
    its index for {!Declaration}, {!edge.source}, {!is_in_force}, and
    {!successors}. *)

val is_in_force : t -> int -> bool
(** [is_in_force facts index] is [true] when the declaration at [index] is in
    force: it carries no status and no effective [supersedes] edge points at it.
    A [supersedes] edge is effective when its source is a declaration that
    carries no status and whose kind needs no approval. A declaration with no
    status on a cycle of [supersedes] edges is in force.

    @raise Invalid_argument if [index] is not an index of {!declarations}. *)

val successors : t -> int -> int list
(** [successors facts index] is the indices in {!declarations} of the successors
    of the declaration at [index]. For each effective [supersedes] edge that
    points at the declaration, the source of the edge is a successor when it is
    in force; otherwise the successors of the source are. The list is in the
    byte order of the ids of the declarations, and holds each id once: of the
    declarations that share an id, the first in the order of the records. The
    list is empty if and only if the declaration is in force or no effective
    [supersedes] edge points at it. Each member is in force.

    @raise Invalid_argument if [index] is not an index of {!declarations}. *)

val edges : t -> (edge * target) list
(** [edges facts] is every edge, with what its tag target resolves to, in the
    order of the files of {!make} and then of the lines. *)

val resolve : t -> string -> target
(** [resolve facts text] is what an edge whose tag target is [text] resolves to
    in [facts], by the rule of {!target}. [resolve facts] builds the map of the
    slugs once, and gives a function that each tag target can share. *)

val block_hash : t -> string -> int -> string
(** [block_hash facts path index] is the hash of the block at [index] in the
    blocks of the document of [path] that {!make} took. When [path] occurs more
    than once, the first document counts.

    @raise Not_found if no file of {!make} has the path [path].
    @raise Invalid_argument
      if [index] is not an index of the blocks of that document. *)

val acks : t -> ack list
(** [acks facts] is every ack, in the order of the files and then of the lines.
*)

val block_acks : t -> string -> int -> ack list
(** [block_acks facts path index] is each ack of {!acks} whose path is [path]
    and whose block index is [index], in the order of {!acks}. *)

val plans : t -> plan list
(** [plans facts] is every plan, in the order of the files of {!make}. *)

val plan_files : t -> string list
(** [plan_files facts] is the path of each plan file of {!make}, in the order of
    the files: the path of each plan of {!plans}, and the path of each plan file
    that gives no plan because {!Plan_target.parse} refuses the tag target of
    its tag [plan], or because that tag has no target. *)

val effective_scope : plan -> step -> string list
(** [effective_scope plan step] is the globs of the [@scope] of [step], or of
    [plan] when the step has none. *)

val covering : t -> string -> string list
(** [covering facts path] is the id of each step of each plan of [facts] whose
    effective scope holds [path], in the order of {!plans} and then of the
    steps. The steps of every plan count. A glob of a scope that is not valid
    holds no path. [covering facts] builds one path set for each scope that one
    or more steps have, and an index of them ({!Path_index}), and gives a
    function that each path can share. *)

val covers : t -> string -> bool
(** [covers facts path] is [true] when {!covering} [facts path] is not empty.
    [covers facts] builds its index once, and gives a function that each path
    can share. *)

val covered : t -> string list -> string list
(** [covered facts paths] is the id of each step of each plan of [facts] whose
    effective scope holds one or more of [paths], in the order of {!plans} and
    then of the steps. It is the ids of {!covering} for each of [paths], each id
    once. *)

type meeting_fact = private { id : string; path : string; span : Markdown.span }
(** A fact that would meet a promise: its id, its path, and its span. *)

type standing = private {
  by : meeting_fact option;
      (** the first member of [meeting_facts] whose path is in the effective
          scope of the step or in the default location of the kind of the
          promise *)
  meeting_facts : meeting_fact list;
      (** every fact that would meet the promise if its place were right, in the
          order of the paths in byte order and then of the places *)
}
(** How a promise stands. *)

val standing : t -> plan -> step -> promise -> standing
(** [standing facts plan step promise] is how [promise], a promise of [step] of
    [plan], stands. A declaration would meet it when its kind is the word and
    its slug is the tag target of the promise. An edge would meet it when its
    word and its tag target are those of the promise, its tag target resolves,
    and it is not suspect. No edge of the word [verifies] would meet it.

    [standing facts plan step] reads the effective scope of [step] once, and
    gives a function that each promise of [step] can share.

    @raise Invalid_argument
      if [plan] is not one of {!plans} [facts] or [step] is not one of the steps
      of [plan], when it is applied to [step]; and if [promise] is not one of
      the promises of [step], when it is applied to [promise]. *)

val met_within : t -> scope:string list -> word:string -> target:string -> bool
(** [met_within facts ~scope ~word ~target] is [true] when a fact of [facts]
    meets a promise of the word [word] and the tag target [target] of a step
    whose effective scope is [scope], by the rule of {!standing}: a declaration
    of the kind [word] and the slug [target] in [scope] or in the default
    location of its kind, or an edge of the word [word] and the tag target
    [target] in [scope] whose tag target resolves and that is not suspect. No
    edge of the word [verifies] meets it. The step need not be a step of a plan
    of [facts]. *)

val index :
  tree:string ->
  base:string ->
  default_branch:string ->
  manifest:string ->
  ledger:string option ->
  tool:string ->
  mode:Mode.t ->
  Jsonl.record
(** [index ~tree ~base ~default_branch ~manifest ~ledger ~tool ~mode] is the
    header record of a run in [mode], for a repository with no evidence and no
    fetched pack. [tree] is the tree key, [base] the object id of the base
    commit, [manifest] the path of the manifest, [ledger] the object id of the
    commit at the ledger ref, and [tool] the version of the tool. The record has
    no field [ledger] when [ledger] is [None]. *)
