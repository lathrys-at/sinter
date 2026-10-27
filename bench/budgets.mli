(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites performance-budgets *)

(** The performance budgets of [sinter scan] and [sinter check], and their check
    against the measures of a benchmark run.

    The budgets file is TOML. It holds the table [scan] and the table [check],
    and nothing else. Each table holds two keys, and nothing else:

    - [peak-memory-kib], a positive integer: the limit of the median peak
      resident memory of the command on the tree of 10,000 declarations, on
      Linux, in KiB
    - [allocation-growth], a positive integer or float: the limit, for each
      phase of the command, of the words that the phase allocates on the tree of
      10,000 declarations, divided by the words on the tree of 1,000
      declarations *)

type t
(** The budgets of both commands. *)

val of_string : string -> (t, string) result
(** [of_string text] is the budgets that [text] holds. The error names the first
    table or key that is missing, unknown, or of the wrong kind, or the place of
    the first TOML error.

    @raise Sinter_bridge.Error as {!Sinter_core.Toml.parse} raises it. *)

val peak_kib : t -> string -> int option
(** [peak_kib budgets command] is the memory budget of [command], [scan] or
    [check]; [None] for any other command. *)

val growth : t -> string -> float option
(** [growth budgets command] is the growth limit of the phases of [command],
    [scan] or [check]; [None] for any other command. *)

(** The outcome of one budget. *)
type verdict =
  | Pass of float  (** the measure, at or under the limit *)
  | Fail of float  (** the measure, over the limit *)
  | Skipped of string  (** why the run cannot check the budget *)

type outcome = {
  command : string;  (** [scan] or [check] *)
  budget : string;  (** [peak-memory-kib] or [allocation-growth] *)
  phase : string option;  (** the phase of a growth limit *)
  limit : float;
  verdict : verdict;
}
(** The check of one budget. *)

val check :
  t ->
  linux:bool ->
  peak:(tree:string -> command:string -> float option) ->
  words:(tree:string -> command:string -> (string * float) list) ->
  outcome list
(** [check budgets ~linux ~peak ~words] checks the budgets of [scan], then of
    [check]: the memory budget, and then the growth limit of each phase.
    [peak ~tree ~command] is the median peak memory of [command] on [tree] in
    KiB, or [None] when the run did not measure it. [words ~tree ~command] is
    the words of each phase of [command] on [tree], in the order of the phases,
    or [[]] when the run did not count them. The trees are [n1000] and [n10000].

    The memory budget is skipped when [linux] is [false], or when the run has no
    peak on [n10000]. The growth limit gives one outcome for each phase of
    [n10000], in its order, skipped when [n1000] has no such phase or counts
    [0.] words in it. When [n10000] has no phase, the growth limit gives one
    outcome with no phase, skipped. *)
