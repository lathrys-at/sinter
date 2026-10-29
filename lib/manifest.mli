(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The manifest: the settings of one repository for Sinter, read from the TOML
    text of [sinter.toml].

    The reader checks the text in four steps, in this order: the TOML syntax;
    the key [sinter-spec]; the names of the keys and the types of the values;
    and each value against the rules of its key. It stops at the first step that
    finds an error, and gives every error of that step. *)

(** {1 Versions, kinds, and names} *)

val specification : Major_minor.t
(** The version of the specifications that this reader implements: [1.0]. *)

val since : string list -> Major_minor.t option
(** [since path] is the version of the specifications that added the setting at
    the key path [path], such as [["check"; "warn-only"]]. A name that varies,
    such as the name of a pack, can be any name except a fixed name of the same
    table: [["scan"; "packs"; "ocaml"; "files"; "x"]] names no setting. It is
    [None] when [path] names no setting. *)

(** A kind of item, as the keys [paths.<kind>] and [proof.<kind>] name it. *)
type kind = Req | Design | Decision | Plan

val kind_name : kind -> string
(** [kind_name kind] is ["req"], ["design"], ["decision"], or ["plan"]. *)

val is_name : string -> bool
(** [is_name name] is [true] when [name] matches [[a-z][a-z0-9]*(-[a-z0-9]+)*],
    the pattern of the name of a pack, a namespace, and a runner. *)

(** What settles that an item of a kind is approved: the value of
    [proof.<kind>]. *)
type approval =
  | Declaration  (** the item counts as approved *)
  | Approval
      (** the item is approved only when the ledger holds an approval of it *)

val approval_name : approval -> string
(** [approval_name approval] is the word that [proof.<kind>] writes for
    [approval]: ["declaration"] or ["approval"]. *)

(** Which rungs of an edge of the kind [verifies] meet a promise: the value of
    [proof.verifies]. *)
type verifies =
  | Whole_run
      (** the rungs [passing] and [unmeasured]: the coverage of the whole run is
          enough *)
  | Each_test  (** the rung [passing] alone: the coverage of each test *)

val verifies_name : verifies -> string
(** [verifies_name verifies] is the word that [proof.verifies] writes for
    [verifies]: ["whole-run"] or ["each-test"]. *)

(** When a step without promises is done: the value of [proof.step]. *)
type step =
  | Change
      (** when a hunk of the diff changes a file inside the scope of the step:
          ["change"] *)
  | Step_approval
      (** when the ledger holds an approval of the step that matches its step
          hash: ["approval"] *)
  | Promises
      (** never; each step needs promises, and a step without promises is a
          finding: ["promises"] *)

val step_name : step -> string
(** [step_name step] is the word that [proof.step] writes for [step]:
    ["change"], ["approval"], or ["promises"]. *)

(** {1 Errors} *)

(** The type of value that a key takes. *)
type expected =
  | A_string
  | A_version  (** a string of the form MAJOR.MINOR *)
  | True_or_false
  | Strings  (** an array of strings *)
  | A_table

(** What is wrong at one place of the manifest. A key is named by its key path,
    the names from the top of the file down to the key. *)
type problem =
  | Syntax of Toml.error  (** the text is not a TOML 1.1.0 document *)
  | Not_a_version of { key : string list; text : string }
      (** the string of [sinter-spec] or of a pack version is not of the form
          MAJOR.MINOR *)
  | Sinter_spec_too_new of Major_minor.t
      (** [sinter-spec] states a version newer than {!specification} *)
  | Sinter_spec_major_too_old of Major_minor.t
      (** [sinter-spec] states a version with a major number below that of
          {!specification} *)
  | Key_too_new of {
      key : string list;
      since : Major_minor.t;
      sinter_spec : Major_minor.t;
    }
      (** the manifest writes a key that a version newer than its [sinter-spec]
          added *)
  | Unknown_key of {
      name : string;
      table : string list;
      nearest : string option;
    }
      (** a key that the table [table] does not hold; [nearest] is the nearest
          valid name within two edits *)
  | Misplaced_key of { name : string; place : string list }
      (** a key that belongs in another table: [place] is the key path of that
          table, with a name that varies written in angle brackets, such as
          ["<name>"]; [[]] is the top level *)
  | Bad_pack_name of string
  | Bad_namespace of string
  | Unknown_gate of { name : string; nearest : string option }
  | Unknown_class of {
      name : string;
      gate : Finding_class.gate;
      nearest : string option;
    }
      (** a name under [check.tiers.<gate>] that is not a built-in finding class
      *)
  | No_tier_at_gate of {
      finding_class : Finding_class.t;
      gate : Finding_class.gate;
    }  (** the class takes no tier at the gate *)
  | Never_blocks  (** a tier for [config-changed] *)
  | No_tier_at_any_gate  (** a tier for [pack-mismatch] *)
  | Plan_location  (** [paths.plan] *)
  | Markdown_version  (** a version for the built-in pack [markdown] *)
  | Markdown_runners  (** runners for the built-in pack [markdown] *)
  | Bad_runner_name of string
      (** a key under the runners of a pack that is not a runner name: a name
          that does not match the pattern of a pack name *)
  | Runner_in_two_packs of { runner : string; pack : string; other : string }
      (** the runners of [pack] and of [other] both hold [runner]; [other] is
          the first pack in byte order that holds it *)
  | Wrong_type of {
      key : string list;
      expected : expected;
      found : Toml.Kind.t;
    }
  | Wrong_member_type of { key : string list; found : Toml.Kind.t }
      (** a member of an array of strings that is not a string *)
  | Not_a_branch of { name : string; error : Branch_name.error }
      (** the value of [default-branch] *)
  | Bad_glob of { member : string; error : Glob.error }
      (** a member of a path set that is not a glob, or not [!] and a glob *)
  | Repeated_member of { key : string list; member : string }
      (** a member of an array that an earlier member equals *)
  | No_plain_glob of string list
      (** a path set whose every member is a [!] glob *)
  | Missing_files of string  (** a pack with no files, or an empty array *)
  | Missing_version of string  (** a fetched pack with no version *)
  | Bad_id_pattern of { namespace : string; error : Id_pattern.error }
  | Unknown_value of {
      key : string list;
      value : string;
      choices : string list;
      nearest : string option;
    }  (** a string that is not one of the words that the key takes *)
  | Bad_marker of string
      (** an agent marker that is not a name of an environment variable *)

(** One error of a manifest. *)
type error =
  | At of Toml.span * problem
      (** a problem at a place: the span of the text that is in error. For a
          key, the span is the part of the key that is in error; for a dotted
          key, the first part that is in error. For a value, the span is the
          span of the value. For a place inside a string, and for a TOML syntax
          error, the span is one character. *)
  | No_pack  (** the manifest names no pack *)

val newer_keys : sinter_spec:Major_minor.t -> Toml.table -> error list
(** [newer_keys ~sinter_spec document] is a [Key_too_new] error at each key of
    [document] whose setting a version newer than [sinter-spec] added, in the
    order of their places. {!of_string} gives these errors when the manifest
    states [sinter-spec]. *)

val message : error -> string
(** [message error] says what is wrong and, when it can, what to write instead.
    It is one line, without the place and without a full stop at the end. *)

val render : path:string -> error -> string
(** [render ~path error] is the line that reports [error] in the manifest at
    [path]: [path], the line, and the column, joined by [:], and then the
    message. For [No_pack], it is the message with [path] as its subject. *)

(** {1 Reading} *)

type runner = {
  name : string;
  at : Toml.span;
      (** the span of the part [<runner>] of the first key of the file that
          names the table [scan.packs.<name>.runners.<runner>] *)
  settings : (Toml.key * Toml.node) list;
      (** each runner setting [scan.packs.<name>.runners.<runner>.<key>] that
          the manifest writes, in the order of the file: the part [<key>] of the
          key path, with its span, and the value as the text writes it. The
          reader checks no name, type, or value of a setting. *)
}
(** One runner of a pack. *)

type pack = {
  name : string;
  files : Path_set.t;  (** the files that the pack reads; never empty *)
  version : Major_minor.t option;
      (** the release of a fetched pack; [None] for [markdown] alone *)
  runners : runner list;
      (** the runners, one for each table under [scan.packs.<name>.runners], in
          the order of the file; [[]] when the manifest gives none *)
}
(** One pack that the manifest names. *)

type t
(** A manifest whose every key and value is valid. *)

val of_string : string -> (t, error list) result
(** [of_string text] reads the manifest whose text is [text]. The errors are
    those of the first step that finds any, sorted by their places, with no
    error twice. [No_pack] comes alone, when the four steps find nothing.

    @raise Sinter_bridge.Error
      if [text] is 4 GiB or more, or if the bridge stops on an internal fault.
*)

(** Why {!load} gives no manifest. *)
type load_error =
  | Missing  (** nothing is at the path *)
  | Unreadable of string
      (** the file did not open or read, for example a folder; the reason *)
  | Invalid of error list  (** the text holds errors, as {!of_string} gives *)

val load : string -> (t, load_error) result
(** [load path] reads the file at [path] and then its text, as {!of_string}
    does. The file is closed on every path.

    @raise Sinter_bridge.Error on the conditions of {!of_string}. *)

(** {1 Settings} *)

val document : t -> Toml.table
(** [document manifest] is the TOML document that [manifest] was read from, with
    the place of every key and value. *)

val sinter_spec : t -> Major_minor.t option
(** [sinter_spec manifest] is the version that [sinter-spec] states, or [None].
*)

val default_branch : t -> string
(** [default_branch manifest] is the default branch: the value of
    [default-branch], or ["main"]. *)

val packs : t -> pack list
(** [packs manifest] is the packs, sorted by name in byte order. The list is
    never empty. *)

val namespaces : t -> (string * Id_pattern.t) list
(** [namespaces manifest] is each declared namespace of external ids with its id
    pattern, sorted by namespace in byte order. *)

val warn_only : t -> bool
(** [warn_only manifest] is the value of [check.warn-only], or [false]. *)

val written_tiers :
  t -> (Finding_class.gate * Finding_class.t * Finding_class.tier) list
(** [written_tiers manifest] is each pair of a gate and a class that
    [check.tiers] writes, with its tier, sorted by gate in the order of
    {!Finding_class.gates}, and then by class in the order of
    {!Finding_class.all}. *)

val tier :
  t -> Finding_class.gate -> Finding_class.t -> Finding_class.tier option
(** [tier manifest gate finding_class] is the tier that applies to the class at
    the gate: the tier that [check.tiers] writes; else [Warn] when
    [check.warn-only] is [true] and the built-in tier is [Block]; else the
    built-in tier. It is [None] when the class takes no tier at the gate. *)

val historical : t -> Path_set.t
(** [historical manifest] is the path set that [paths.historical] writes. *)

val builtin_historical : string
(** The built-in member of the historical paths: [.plans/**/*.log.md]. *)

val is_historical : t -> string -> bool
(** [is_historical manifest path] is [true] when the built-in member matches
    [path], or when [path] is in {!historical}. *)

val exempt : t -> Path_set.t
(** [exempt manifest] is the path set that [paths.exempt] writes. *)

val lock_file : string
(** The path of the lock file, [sinter.lock], a built-in exempt path. *)

val is_exempt :
  t -> plan_file:(string -> bool) -> manifest:string option -> string -> bool
(** [is_exempt manifest ~plan_file ~manifest:location path] is [true] when
    [path] is a built-in exempt path, or in {!exempt}. The built-in exempt paths
    are each path for which [plan_file] is [true], [location] when it is
    [Some _], and {!lock_file}. [location] is the path of the manifest relative
    to the repository root, and [None] for a manifest outside the repository. *)

val location : t -> kind -> Path_set.t option
(** [location manifest kind] is the default location of [kind], the path set
    that [paths.<kind>] writes, or [None] when the kind has none. It is [None]
    for [Plan]. *)

val approval : t -> kind -> approval
(** [approval manifest kind] is the value of [proof.<kind>], or [Declaration].
    The kind needs approval when it is [Approval]. *)

val agent_markers : t -> string list
(** [agent_markers manifest] is the names that [proof.agent-markers] adds to the
    built-in list of agent markers, in the order it writes them. *)

val verifies : t -> verifies
(** [verifies manifest] is the value of [proof.verifies], or [Whole_run]. *)

val step : t -> step
(** [step manifest] is the value of [proof.step], or [Change]. *)
