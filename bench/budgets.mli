(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites performance-budgets *)

(** The growth budgets of [sinter scan], [sinter check], and
    [sinter check --diff], and their check against the measures of a benchmark
    run.

    The budgets file is TOML. It holds the tables [scan] and [check], the table
    [check-diff] when [sinter check --diff] has a budget, and nothing else. Each
    table holds the key [allocation-growth], and may hold the table [phases],
    and nothing else. [allocation-growth] is a positive integer or float, the
    limit, for each phase of the command, of the words that the phase allocates
    on the tree of 10,000 declarations, divided by the words on the tree of
    1,000 declarations. Each key of [phases] names a phase, and its value, a
    positive integer or float, is the limit of that phase in place of
    [allocation-growth]. {!check} refuses a key of [phases] that names no phase
    of the run. *)

type t
(** The budgets of the commands. *)

val of_string : string -> (t, string) result
(** [of_string text] is the budgets that [text] holds. The error names the first
    table or key that is missing, unknown, or of the wrong kind, or the place of
    the first TOML error.

    @raise Sinter_bridge.Error as {!Sinter_core.Toml.parse} raises it. *)

val growth : t -> string -> float option
(** [growth budgets command] is the growth limit [allocation-growth] of
    [command], [scan], [check], or [check-diff]; [None] for any other command,
    and for [check-diff] when the budgets have no table [check-diff]. *)

(** The outcome of one growth limit. *)
type verdict =
  | Pass of float  (** the growth, at or under the limit *)
  | Fail of float  (** the growth, over the limit *)
  | Skipped of string  (** why the run cannot check the limit *)

type outcome = {
  command : string;  (** [scan], [check], or [check-diff] *)
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
    then of [check-diff] when the budgets have that table.
    [words ~tree ~command] is the words of each phase of [command] on [tree], in
    the order of the phases, or [[]] when the run did not count them. The trees
    are [n1000] and [n10000].

    A command gives one outcome for each phase of [n10000], in its order,
    skipped when [n1000] has no such phase or counts [0.] words in it. The limit
    of an outcome is the limit of its phase in [phases], or [allocation-growth].
    When [n10000] has no phase, the command gives one outcome with no phase,
    skipped, with the limit [allocation-growth].

    The result is [Error] when a key of [phases] names no phase that [n10000]
    has for its command, with a message that names the key and those phases. A
    command with no phase on [n10000] gives no such error. *)
