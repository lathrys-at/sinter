(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The check of a working tree in tree mode: the findings that a gate reports,
    their text form and their records, and the exit code. *)

(** {1 Tiers} *)

val tier :
  Manifest.t -> Finding_class.gate -> Finding.t -> Finding_class.tier option
(** [tier manifest gate finding] is the tier of [finding] at [gate]: the tier
    that applies to its class, as {!Manifest.tier} gives it, with one change. A
    [parse-error] finding at an error node of a markdown file takes [Warn] where
    that tier is [Block]. It is [None] when the class takes no tier at [gate].
*)

type entry = {
  finding : Finding.t;
  tier : (Finding_class.gate * Finding_class.tier) option;
      (** the gate of the check and the tier of the finding at that gate; [None]
          when the check runs at no gate *)
}
(** One finding that the check reports. *)

val select :
  Manifest.t -> Finding_class.gate option -> Finding.t list -> entry list
(** [select manifest gate findings] is the findings that a check at [gate]
    reports, in the order of [findings]. With [None], it is every finding, with
    no tier. With [Some gate], it is each finding whose {!tier} at [gate] is
    [Warn] or [Block], with that tier: a class whose tier is [Off], or that
    takes no tier at the gate, reports nothing. *)

val exit_code : strict:bool -> entry list -> int
(** [exit_code ~strict entries] is {!Exit_code.findings} when an entry has the
    tier [Block], or when [strict] is [true] and an entry has a class other than
    [config-changed]. Otherwise it is {!Exit_code.clean}. *)

(** {1 Output} *)

val record : mode:Mode.t -> entry -> Jsonl.record
(** [record ~mode entry] is the finding record of [entry] in a run of [mode]. It
    holds the fields [v], [kind], [id], [class], [subject], [ack_subject],
    [ackable], and [mode] (the {!Mode.name} of [mode]); [detail] when the
    finding has one; [help] and [edits] when it has a fix; [path], [line],
    [col], [eline], and [ecol] when it has a place; [mcol], [mecol], and [label]
    when it has a mark; [related] when it has one related place or more, an
    array of objects in the order of {!Finding.t.related}, each with [label],
    and with [path], [line], [col], [eline], and [ecol] when the place is in a
    file; and [gate] and [tier] when the entry has a tier.

    [help] is {!Fix.help} of the fix. [edits] is an array of objects, one for
    each edit of each alternative of {!Fix.alternatives}, in their order. Each
    object holds [alt], the number of its alternative from 1, and [path], the
    path of the place of the finding; [line], [col], [eline], [ecol], and [text]
    are those of the edit. The objects are sorted by
    [(alt, path, line, col, eline, ecol, text)], and no two are equal. *)

(** {1 The check} *)

(** The form of the output. *)
type form =
  | Full  (** the full form of each finding, {!Render.full} *)
  | Brief  (** the brief form of each finding, {!Render.brief} *)
  | Json  (** the index record, and then the record of each finding *)

type report
(** What a check gives: the lines for standard error, the exit code, and the
    findings to write. The value holds the path of the root of the working tree,
    so that {!write} can read the files of the findings. *)

val messages : report -> string list
(** [messages report] is the lines for the person who runs the tool, without
    line feeds: in the forms [Full] and [Brief], the line that names the base
    first; then the warnings of the tree. *)

val code : report -> int
(** [code report] is the exit code, as {!exit_code} gives it. *)

val write : ?phases:Allocation.t -> Format.formatter -> report -> unit
(** [write ppf report] writes the findings of [report] to [ppf] in their form,
    in the order of {!Finding.compare}, and flushes [ppf]. In the form [Full],
    one empty line stands between two blocks of {!Render.full}, and each file of
    a finding or of a related place is read once. In the form [Json], each
    record is one line of {!Jsonl.to_string}. With [phases], it counts the words
    of the writing, the reading of the files included, in the phase [output].

    @raise Sys_error if [ppf] cannot write. *)

val run :
  ?phases:Allocation.t ->
  env:string array ->
  dir:string ->
  manifest:string option ->
  base:string option ->
  mode:Mode.t ->
  gate:Finding_class.gate option ->
  strict:bool ->
  form:form ->
  tool:string ->
  unit ->
  (report, Scan.error) result
(** [run ~env ~dir ~manifest ~base ~mode ~gate ~strict ~form ~tool ()] checks
    the working tree that {!Scan.load_with_base} reads with [env], [dir],
    [manifest], and [base]. [gate] is the gate of the check, [strict] says
    whether every finding counts for the exit code, and [tool] is the version of
    the tool, for the index record.

    In the mode [Tree], the findings are those of the working tree. In the mode
    [Diff], they are the findings of the working tree less the findings of the
    base ({!Baseline.subtract}). The findings of the base come from the base
    tree that {!Scan.load_with_base} reads, with the manifest of the working
    tree and no evidence. In both modes, the findings also hold the classes that
    compare the working tree with the base ({!Adjudicator.classes}), the class
    [unplanned-change] ({!Unplanned.findings}), and the findings of
    [config-changed] ({!Config_change.findings}) when the manifest is inside the
    repository and the diff changes it or the base tree does not hold it. The
    built-in members of the manifest come from the plan files of the working
    tree.

    With [phases], it counts the phases of {!Scan.load_with_base}, [facts]
    ({!Facts.make}) and [findings] (the findings, their subtraction, the classes
    that compare with the base, and their selection), and the index record in
    [repository]. In the mode [Diff], it counts the facts of the base in
    [base-facts] and their findings in [base-findings]. In the mode [Tree], the
    facts of the files of the base that differ from the working tree count in
    [findings].

    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)
