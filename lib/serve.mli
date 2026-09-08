(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites exit-codes *)

(** The loop of the serve mode. The loop answers one request at a time. It reads
    no channel and writes none: the caller gives it one line and writes the
    lines it gives back. *)

exception Error of string
(** The loop cannot start. The string says why, and it is fit to show to the
    person who ran the command. *)

type t
(** The state of one loop: a parser engine, and every grammar the loop has
    loaded. The caller owns the state. A state is not safe to use from two
    threads at the same time. *)

type control =
  | Done of int  (** the operation ran; the integer is its exit code *)
  | Failed of int * string
      (** the operation did not run to its end. The integer is the exit code
          that the one-shot command would return, and the string is the message
          that it would print. *)

type response
(** The whole answer to one request: the lines of the operation, and then one
    line that closes the answer. *)

val create : unit -> t
(** [create ()] makes the state of one loop. The caller must call {!close} when
    the loop ends.

    @raise Error if the parser engine does not start. *)

val close : t -> unit
(** [close state] frees the parser engine and every grammar in it. A second call
    on the same state does nothing. The garbage collector frees a state that no
    value refers to, so a program does not have to call this function. *)

val respond : t -> string -> response
(** [respond state line] does the work that the request in [line] asks for.
    [line] is one line of JSON; it may end with a line feed or not. This
    function answers every string, and it raises nothing for the content of
    [line].

    @raise Invalid_argument if [state] is closed. *)

val control : response -> control
(** [control response] says how the operation ended. *)

val lines : response -> Jsonl.record list
(** [lines response] is every record of the answer, in the order to write them.
    The last record is the control line. Each record carries the field [req]
    with the request's tag, and no record carries it when the line held no tag
    that the reader could read back. *)
