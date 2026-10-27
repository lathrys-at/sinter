(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The facts of the markdown files of one tree, as JSON Lines records.

    A file is a plan file when its path starts with [.plans/] and its first tag
    block holds a tag of the word [plan]. A plan file gives a [plan] record, a
    [step] record for each step, and a [promise] record for each promise. Every
    other file gives a record for each declaration of the kinds [req], [design],
    and [decision], each edge, each site, and each ack. Each distinct ref that
    an edge names and that resolves gives one [ref] record.

    The records take the values that hold when the ledger, the evidence, and the
    session are absent: every plan is open, no plan and no step is active,
    nothing is declined, and an item of a kind that needs approval is not
    approved. *)

type t
(** The facts of one tree. *)

val make : Manifest.t -> (string * Markdown.t) list -> t
(** [make manifest files] is the facts of [files]. Each pair is the path of one
    file, relative to the repository root, and the document that
    {!Markdown.read} gave for the file. No path occurs twice. The manifest gives
    the ref namespaces, the kinds that need approval, and the default locations
    of the kinds. *)

val needs_changes : t -> bool
(** [needs_changes facts] is [true] when a step of a plan has no promise. Only
    then does {!records} read its argument [changed]. *)

val records : t -> changed:string list -> Jsonl.record list
(** [records facts ~changed] is every record of [facts], in the order of
    [(kind, path, line, col, id)], with each record that has no path after the
    others, in the order of their ids. [changed] is the paths of the files that
    the diff between the base and the working tree changes, of every pack and of
    no pack; a step with no promise is done only when a path of [changed] is in
    its scope.

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
}
(** One declaration of a file that is not a plan file. *)

(** What the tag target of an edge resolves to. *)
type target = private
  | Declaration of int
      (** the declaration at this index of {!declarations}: the first of the
          declarations of the kinds [req], [design], and [decision] that have
          the slug, in the order of the records *)
  | Ref of { ns : string; id : string }
      (** a ref whose namespace the manifest declares and whose id matches the
          pattern of the namespace *)
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

type promise = private { word : string; target : string; span : Markdown.span }
(** One promise: the word and the tag target of its first tag line, and the span
    of that line. *)

type step = private {
  slug : string;
  title : string;
  span : Markdown.span;  (** the heading line *)
  own_scope : string list option;  (** the globs of the [@scope] of the step *)
  promises : promise list;
      (** in the order of the file, each word and tag target once *)
}
(** One step of a plan. *)

type plan = private {
  slug : string;
  path : string;
  span : Markdown.span;  (** the tag line of [@plan] *)
  title : string option;
  scope : string list;  (** the globs of the [@scope] of the plan *)
  steps : step list;  (** in the order of the file *)
}
(** One plan file. *)

val declaration_id : declaration -> string
(** [declaration_id declaration] is [<kind>:<slug>]. *)

val edge_id : edge -> string
(** [edge_id edge] is [<word>:<src>-><tag target>]. *)

val step_id : plan -> step -> string
(** [step_id plan step] is [step:<plan slug>/<step slug>]. *)

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

val effective_scope : plan -> step -> string list
(** [effective_scope plan step] is the globs of the [@scope] of [step], or of
    [plan] when the step has none. *)

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

val index :
  tree:string ->
  base:string ->
  target_branch:string ->
  manifest:string ->
  tool:string ->
  Jsonl.record
(** [index ~tree ~base ~target_branch ~manifest ~tool] is the header record of a
    scan in tree mode, for a repository with no ledger ref, no evidence, and no
    fetched pack. [tree] is the tree key, [base] the object id of the base
    commit, [manifest] the path of the manifest, and [tool] the version of the
    tool. *)
