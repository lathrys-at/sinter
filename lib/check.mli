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
    tier [Block], or when [strict] is [true] and [entries] is not empty.
    Otherwise it is {!Exit_code.clean}. *)

(** {1 Output} *)

val text : entry -> string list
(** [text entry] is the text form of the finding, in lines without line feeds.
    The first line is [<path>:<line>:<column>: ], then the tier and a space when
    the entry has one, then the class, a space, and the subject id, and then a
    space and the detail when the finding has one. A finding with no place gives
    [-:-:-:] for its place. A subject id that holds a space or a tab stands in
    double quotes, with a backslash before each double quote and each backslash
    in it. The path and the subject id then take the form that {!Finding.escape}
    gives, and no control character but the tab stands in a line. A second line,
    [  fix: ] and the fix, follows when the finding has a fix. *)

val record : mode:Mode.t -> entry -> Jsonl.record
(** [record ~mode entry] is the finding record of [entry] in a run of [mode]. It
    holds the fields [v], [kind], [id], [class], [subject], [ack_subject],
    [ackable], and [mode] (the {!Mode.name} of [mode]); [detail] and [fix] when
    the finding has them; [path], [line], [col], [eline], and [ecol] when it has
    a place; and [gate] and [tier] when the entry has a tier. *)

(** {1 The check} *)

(** The form of the output. *)
type format =
  | Text  (** the text form of each finding *)
  | Json  (** the index record, and then the record of each finding *)

type report = {
  messages : string list;
      (** the lines for the person who runs the tool, without line feeds: in the
          format [Text], the line that names the base first; then the warnings
          of the tree *)
  lines : string list;
      (** the output, in lines without line feeds: the findings in the order of
          {!Finding.compare}, in the form that the format names *)
  code : int;  (** the exit code, as {!exit_code} gives it *)
}
(** What a check gives. *)

val run :
  ?phases:Allocation.t ->
  env:string array ->
  dir:string ->
  manifest:string option ->
  base:string option ->
  mode:Mode.t ->
  gate:Finding_class.gate option ->
  strict:bool ->
  format:format ->
  tool:string ->
  unit ->
  (report, Scan.error) result
(** [run ~env ~dir ~manifest ~base ~mode ~gate ~strict ~format ~tool ()] checks
    the working tree that {!Scan.load_with_base} reads with [env], [dir],
    [manifest], and [base]. [gate] is the gate of the check, [strict] says
    whether every finding counts for the exit code, and [tool] is the version of
    the tool, for the index record.

    In the mode [Tree], the findings are those of the working tree. In the mode
    [Diff], they are the findings of the working tree less the findings of the
    base ({!Baseline.subtract}). The findings of the base come from the base
    tree that {!Scan.load_with_base} reads, with the manifest of the working
    tree and no evidence. In both modes, the findings also hold the classes that
    compare the working tree with the base ({!Adjudicator.classes}).

    With [phases], it counts the phases of {!Scan.load_with_base}, [facts]
    ({!Facts.make}) and [findings] (the findings, their subtraction, the classes
    that compare with the base, and their selection), [base-facts],
    [base-findings] in the mode [Diff], the index record in [repository], and
    the phase [output], the lines of the report.

    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)
