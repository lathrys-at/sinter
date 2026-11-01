(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The work of a function, counted as the words of memory that it allocates.

    A word is 8 bytes on a 64-bit machine. The count is that of
    {!Sinter_core.Allocation.measure}: the words that the OCaml runtime
    allocates on the heap of the domain that runs the function. For one function
    and one input, the count is the same on every run, whatever the load of the
    machine. The count does not see work that allocates nothing, such as a
    search of a list with [List.mem], or work in the Rust parser bridge or in
    another process. *)

val words : (unit -> 'a) -> int
(** [words f] calls [f ()] once and is the words that the domain allocates while
    [f] runs, less the words that the count itself allocates. A function that
    allocates nothing gives [0]. The move of an older value to the major heap
    while [f] runs does not change the count. An exception that [f] raises
    passes through. *)

val growth :
  ?exponent:float ->
  margin:float ->
  sizes:int * int ->
  input:(int -> 'a) ->
  ('a -> 'b) ->
  (unit, string) result
(** [growth ~exponent ~margin ~sizes:(small, large) ~input f] compares the work
    of [f] on an input of size [small] with its work on an input of size
    [large]. [input n] makes the input of size [n], outside the count. The
    function first calls [f] once on the input of size [small], with no count. A
    value that this call computes and keeps is not in the counts. The function
    then counts [w1], the words of [f] on the input of size [small], and [w2],
    the words of [f] on the input of size [large]. The result is [Ok ()] when
    [w2 <= margin * w1 * (large / small) ** exponent], and otherwise [Error]
    with a message that gives both sizes, both counts, and the limit. The
    default [exponent] is [1.], a linear growth.

    When [large / small] is larger than [margin], a cost
    [c * n ** (exponent + 1)] gives [Error]. A part of the cost that is the same
    at each size lowers the growth, so a cost with such a part can give [Ok].

    @raise Invalid_argument
      when [small] is below 1, [margin] is below 1, [exponent] is below 0, or
      [large / small] is not larger than [margin]. *)

val check_growth :
  ?exponent:float ->
  margin:float ->
  sizes:int * int ->
  input:(int -> 'a) ->
  ('a -> 'b) ->
  unit
(** [check_growth] is {!growth}, and it fails the current test with the message
    of the [Error], through [Alcotest.fail]. *)
