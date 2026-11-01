(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The growth of the processor time of a function between two sizes of input.

    The time is that of [Sys.time]: the processor time of the process, which a
    load on other processes changes little. The time of one run still varies
    from run to run, so the function takes the shortest of several runs, and a
    bound needs a wide margin. This measure is for work that allocates little or
    nothing, such as a search of a list with [List.mem], which
    {!Counted_work.words} does not see. *)

val growth :
  ?exponent:float ->
  margin:float ->
  runs:int ->
  sizes:int * int ->
  input:(int -> 'a) ->
  ('a -> 'b) ->
  (unit, string) result
(** [growth ~exponent ~margin ~runs ~sizes:(small, large) ~input f] compares the
    time of [f] on an input of size [small] with its time on an input of size
    [large]. [input n] makes the input of size [n], outside the time. The
    function first calls [f] once on the input of size [small], with no time.
    Then [t1] is the shortest time of [runs] runs of [f] on the input of size
    [small]. The limit is [margin * t1 * (large / small) ** exponent]. The
    function then runs [f] on the input of size [large] up to [runs] times. The
    result is [Ok ()] at the first run whose time is at most the limit, and
    otherwise [Error] with a message that gives both sizes, both times, and the
    limit. A full collection of the heap comes before each run, outside the
    time. The default [exponent] is [1.], a linear growth.

    Choose [small] so that one run on it takes some milliseconds: a time near
    the resolution of the clock makes [t1], and so the limit, too small.

    @raise Invalid_argument
      when [small] is below 1, [margin] is below 1, [exponent] is below 0,
      [runs] is below 1, or [large / small] is not larger than [margin]. *)

val check_growth :
  ?exponent:float ->
  margin:float ->
  runs:int ->
  sizes:int * int ->
  input:(int -> 'a) ->
  ('a -> 'b) ->
  unit
(** [check_growth] is {!growth}, and it fails the current test with the message
    of the [Error], through [Alcotest.fail]. *)
