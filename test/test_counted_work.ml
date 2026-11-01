(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let case name f = Alcotest.test_case name `Quick f
let array size = Array.make size 0
let square size = Array.make (size * size) 0

let words_counts_the_words_that_a_function_allocates () =
  Alcotest.(check int) "nothing" 0 (Counted_work.words (fun () -> ()));
  Alcotest.(check int)
    "an array of 100 on the minor heap, with its header" 101
    (Counted_work.words (fun () -> array 100));
  Alcotest.(check int)
    "an array of 10,000 on the major heap, with its header" 10_001
    (Counted_work.words (fun () -> array 10_000))

let words_is_the_same_on_every_run () =
  let work () = List.init 1000 string_of_int in
  let first = Counted_work.words work in
  Alcotest.(check (list int))
    "the counts" [ first; first; first ]
    (List.init 3 (fun _ -> Counted_work.words work))

let words_does_not_count_the_move_of_an_older_value () =
  let work () = List.init 100_000 Fun.id in
  let alone = Counted_work.words work in
  let older = List.init 20_000 Fun.id in
  let with_older = Counted_work.words work in
  ignore (Sys.opaque_identity older);
  Alcotest.(check int) "the count" alone with_older

let words_passes_an_exception_through () =
  match Counted_work.words (fun () -> raise Exit) with
  | _ -> Alcotest.fail "the call gave a value"
  | exception Exit -> ()

let growth_passes_a_linear_cost () =
  Alcotest.(check (result unit string))
    "the growth" (Ok ())
    (Counted_work.growth ~margin:1.1 ~sizes:(1000, 16_000) ~input:Fun.id array)

let growth_fails_a_quadratic_cost_under_a_linear_bound () =
  Alcotest.(check (result unit string))
    "the growth"
    (Error
       "the work grows from 10001 words at the size 100 to 160001 words at the \
        size 400, over the limit of 80008 words")
    (Counted_work.growth ~margin:2. ~sizes:(100, 400) ~input:Fun.id square)

let growth_passes_a_quadratic_cost_under_a_quadratic_bound () =
  Alcotest.(check (result unit string))
    "the growth" (Ok ())
    (Counted_work.growth ~exponent:2. ~margin:1.1 ~sizes:(100, 400)
       ~input:Fun.id square)

let growth_does_not_count_the_input () =
  Alcotest.(check (result unit string))
    "the growth" (Ok ())
    (Counted_work.growth ~margin:1.1 ~sizes:(100, 1600)
       ~input:(fun size -> (size, square size))
       (fun (size, _) -> array size))

let growth_does_not_count_the_first_call () =
  let table = Hashtbl.create 1 in
  let work size =
    if not (Hashtbl.mem table ()) then Hashtbl.add table () (array 1_000_000);
    array size
  in
  Alcotest.(check (result unit string))
    "the growth" (Ok ())
    (Counted_work.growth ~margin:1.1 ~sizes:(1000, 16_000) ~input:Fun.id work)

let a_cost_one_exponent_above_the_bound_fails =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:50
       ~name:
         "a cost whose exponent is one above the bound fails, and a cost at \
          the bound passes"
       ~print:QCheck2.Print.(quad int int float int)
       QCheck2.Gen.(
         quad (int_range 8 40) (int_range 0 1) (float_range 1. 3.5)
           (int_range 0 3))
       (fun (small, exponent, margin, extra) ->
         let large =
           int_of_float (Float.ceil (float_of_int small *. margin *. 2.))
           + extra
         in
         let cost exponent size =
           Array.make (int_of_float (float_of_int size ** exponent) * 64) 0
         in
         let bound = float_of_int exponent in
         Counted_work.growth ~exponent:bound ~margin ~sizes:(small, large)
           ~input:Fun.id (cost bound)
         = Ok ()
         && Result.is_error
              (Counted_work.growth ~exponent:bound ~margin ~sizes:(small, large)
                 ~input:Fun.id
                 (cost (bound +. 1.)))))

let growth_refuses_sizes_that_cannot_tell_the_bound () =
  List.iter
    (fun (name, exponent, margin, sizes) ->
      match
        Counted_work.growth ~exponent ~margin ~sizes ~input:Fun.id array
      with
      | _ -> Alcotest.failf "%s: the call gave a value" name
      | exception Invalid_argument _ -> ())
    [
      ("a size below 1", 1., 1.5, (0, 10));
      ("a margin below 1", 1., 0.5, (10, 100));
      ("an exponent below 0", -1., 1.5, (10, 100));
      ("a ratio equal to the margin", 1., 2., (10, 20));
      ("a ratio below the margin", 1., 2., (10, 15));
      ("a large size below the small size", 1., 1., (20, 10));
    ]

let check_growth_fails_the_test_on_an_error () =
  match
    Counted_work.check_growth ~margin:2. ~sizes:(100, 400) ~input:Fun.id square
  with
  | () -> Alcotest.fail "check_growth passed a quadratic cost"
  | exception Invalid_argument message -> Alcotest.fail message
  | exception _ -> ()

let check_growth_passes_a_linear_cost () =
  Counted_work.check_growth ~margin:1.1 ~sizes:(1000, 16_000) ~input:Fun.id
    array

let tests =
  [
    case "words counts the words that a function allocates"
      words_counts_the_words_that_a_function_allocates;
    case "words is the same on every run" words_is_the_same_on_every_run;
    case "words does not count the move of an older value"
      words_does_not_count_the_move_of_an_older_value;
    case "words passes an exception through" words_passes_an_exception_through;
    case "growth passes a linear cost" growth_passes_a_linear_cost;
    case "growth fails a quadratic cost under a linear bound"
      growth_fails_a_quadratic_cost_under_a_linear_bound;
    case "growth passes a quadratic cost under a quadratic bound"
      growth_passes_a_quadratic_cost_under_a_quadratic_bound;
    case "growth does not count the input" growth_does_not_count_the_input;
    case "growth does not count the first call"
      growth_does_not_count_the_first_call;
    a_cost_one_exponent_above_the_bound_fails;
    case "growth refuses sizes that cannot tell the bound"
      growth_refuses_sizes_that_cannot_tell_the_bound;
    case "check_growth passes a linear cost" check_growth_passes_a_linear_cost;
    case "check_growth fails the test on an error"
      check_growth_fails_the_test_on_an_error;
  ]
