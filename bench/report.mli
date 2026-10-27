(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The report of a benchmark run: the summaries of its measures, as JSON and as
    a markdown table, with the outcomes of the budgets. *)

type row = {
  tree : string;  (** [self], or [n] and the number of declarations *)
  declarations : int option;  (** [None] for [self] *)
  command : string;  (** [scan] or [check] *)
  exit_code : int;  (** the exit status of sinter *)
  peak_kib : Measurement.summary;
  instructions : Measurement.summary option;
      (** [None] when no run of the row has an instruction count *)
  footprint_kib : Measurement.summary option;
      (** [None] when no run of the row has a peak footprint *)
  phase_words : (string * float) list;
      (** the median words of each phase, in the order of the phases; [[]] when
          the run counted no phase *)
}
(** The measures of one command on one tree. *)

type t = {
  platform : string;  (** [linux] or [macos] *)
  instruction_counter : string option;
      (** [perf] or [time]; [None] when nothing counts the instructions *)
  no_count_reason : string option;
      (** why nothing counts the instructions; [None] when something does *)
  runs : int;  (** the measured runs of each row *)
  seed : int;  (** the seed of the generated trees *)
  rows : row list;
}
(** One run of the benchmark. *)

val peak : t -> tree:string -> command:string -> float option
(** [peak report ~tree ~command] is the median peak memory in the first row of
    [tree] and [command], or [None] when no row is of [tree] and [command]. *)

val instructions : t -> tree:string -> command:string -> float option
(** [instructions report ~tree ~command] is the median instruction count in the
    first row of [tree] and [command], or [None] when no row is of [tree] and
    [command] or the row has no count. *)

val words : t -> tree:string -> command:string -> (string * float) list
(** [words report ~tree ~command] is the words of each phase in the first row of
    [tree] and [command], or [[]] when no row is of [tree] and [command]. *)

val to_json : t -> Budgets.outcome list -> Yojson.Basic.t
(** [to_json report outcomes] is [report] and [outcomes] as one JSON object, in
    the form that the help text of the runner states. *)

val of_string : string -> (t, string) result
(** [of_string text] is the report of [text], the JSON object of {!to_json}. The
    key [budgets] is not read. Any other key that {!to_json} does not write is
    ignored. [of_string (Yojson.Basic.to_string (to_json report outcomes))] is
    [Ok report] for every report whose floats are finite. The error names the
    first key that is missing or of the wrong kind. *)

val to_markdown : t -> Budgets.outcome list -> string
(** [to_markdown report outcomes] is a markdown section, headed
    [## Performance]: one line on the instruction count, a table of the medians
    and spreads of the rows, in MiB and in billions of instructions, and a table
    of the outcomes, with the phase of each growth limit, when there are any. It
    ends with a line feed. *)
