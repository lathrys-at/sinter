(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites performance-budgets *)

(** The words of memory that the OCaml runtime allocates in each phase of a run.

    A word is 8 bytes on a 64-bit machine. The count of a phase is the growth of
    [minor_words + major_words - promoted_words] of {!Gc.counters} over the
    phase, for the domain that runs it. It counts the memory of the OCaml heap
    only: the Rust parser bridge and the git processes add nothing. For one
    executable, one input, and one path of the working tree, the count is the
    same on every run. *)

type t
(** The counts of the phases of one run. The value is mutable: each {!measure}
    adds to it. *)

val variable : string
(** The environment variable [SINTER_PHASE_WORDS]. When it is set and not empty,
    [sinter scan] and [sinter check] count the words of each phase and write
    {!to_string} of the counts to the file that it names, at the end of the
    command. *)

val create : unit -> t
(** [create ()] is a value with no phase. *)

val measure : t option -> string -> (unit -> 'a) -> 'a
(** [measure phases name f] is [f ()]. When [phases] is [Some counts], it adds
    the words that the domain allocates while [f] runs to the phase [name] of
    [counts], and makes the phase when [counts] has none of that name. A call
    inside [f] counts its words in its own phase and in the phase [name]. When
    [f] raises, the words are not added, and the exception passes through. *)

val phases : t -> (string * int) list
(** [phases counts] is each phase, by its name, with its words, in the order of
    the first {!measure} of each name. *)

val to_string : t -> string
(** [to_string counts] is one line for each phase of {!phases}, in its order:
    the name, a space, the words in decimal, and a line feed. *)
