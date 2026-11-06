(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites performance-budgets *)

(** The growth budgets of [sinter scan], [sinter check], [sinter check --diff],
    [sinter ledger log], and [sinter ledger verify], and their check against the
    measures of a benchmark run.

    The budgets file is TOML. It holds the tables [scan] and [check]; the tables
    [check-diff], [ledger-log], and [ledger-verify] when those commands have a
    budget; and nothing else. Each table holds the key [allocation-growth], and
    may hold the table [phases], and nothing else. [allocation-growth] is a
    positive integer or float, the limit, for each phase of the command, of the
    words that the phase allocates on the larger tree, divided by the words on
    the smaller tree. The trees are those of 10,000 and of 1,000 declarations
    for [scan], [check], and [check-diff], and the ledgers of 100,000 and of
    1,000 entries for [ledger-log] and [ledger-verify]. Each key of [phases]
    names a phase, and its value, a positive integer or float, is the limit of
    that phase in place of [allocation-growth]. {!check} refuses a key of
    [phases] that names no phase of the run. *)

type t
(** The budgets of the commands. *)

val of_string : string -> (t, string) result
(** [of_string text] is the budgets that [text] holds. The error names the first
    table or key that is missing, unknown, or of the wrong kind, or the place of
    the first TOML error.

    @raise Sinter_bridge.Error as {!Sinter_core.Toml.parse} raises it. *)

val growth : t -> string -> float option
(** [growth budgets command] is the growth limit [allocation-growth] of
    [command], [scan], [check], [check-diff], [ledger-log], or [ledger-verify];
    [None] for any other command, and for a command whose table the budgets do
    not have. *)

(** The outcome of one growth limit. *)
type verdict =
  | Pass of float  (** the growth, at or under the limit *)
  | Fail of float  (** the growth, over the limit *)
  | Skipped of string  (** why the run cannot check the limit *)

type outcome = {
  command : string;
      (** [scan], [check], [check-diff], [ledger-log], or [ledger-verify] *)
  phase : string option;  (** the phase; [None] when the run counted no phase *)
  limit : float;
  verdict : verdict;
}
(** The check of the growth limit of one phase of one command. *)

val check :
  t ->
  words:(tree:string -> command:string -> (string * float) list) ->
  (outcome list, string) result
(** [check budgets ~words] checks the growth limits of [scan], then of [check],
    then of [check-diff], [ledger-log], and [ledger-verify], each when the
    budgets have its table. [words ~tree ~command] is the words of each phase of
    [command] on [tree], in the order of the phases, or [[]] when the run did
    not count them. The trees are [n1000] and [n10000], and [l1000] and
    [l100000] for the commands of the ledger.

    A command gives one outcome for each phase of the larger tree, in its order,
    skipped when the smaller tree has no such phase or counts [0.] words in it.
    The limit of an outcome is the limit of its phase in [phases], or
    [allocation-growth]. When the larger tree has no phase, the command gives
    one outcome with no phase, skipped, with the limit [allocation-growth].

    The result is [Error] when a key of [phases] names no phase that the larger
    tree has for its command, with a message that names the key and those
    phases. A command with no phase on the larger tree gives no such error. *)
