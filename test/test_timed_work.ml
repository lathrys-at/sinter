(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let case name f = Alcotest.test_case name `Quick f

let spin rounds =
  let count = ref 0 in
  for _ = 1 to rounds do
    count := Sys.opaque_identity (!count + 1)
  done;
  !count

let linear size = spin (size * 5_000)
let quadratic size = spin (size * size * 5)

let growth_passes_a_linear_cost () =
  Alcotest.(check (result unit string))
    "the growth" (Ok ())
    (Timed_work.growth ~margin:3. ~runs:3 ~sizes:(1_000, 8_000) ~input:Fun.id
       linear)

let growth_fails_a_quadratic_cost_under_a_linear_bound () =
  match
    Timed_work.growth ~margin:3. ~runs:1 ~sizes:(1_000, 8_000) ~input:Fun.id
      quadratic
  with
  | Ok () -> Alcotest.fail "the growth passed a quadratic cost"
  | Error message ->
      let words = String.split_on_char ' ' message in
      Alcotest.(check (list string))
        "the words of the message, without the times"
        [
          "the";
          "time";
          "grows";
          "from";
          "s";
          "at";
          "the";
          "size";
          "1000";
          "to";
          "s";
          "at";
          "the";
          "size";
          "8000,";
          "over";
          "the";
          "limit";
          "of";
          "s";
        ]
        (List.filter (fun word -> not (String.contains word '.')) words)

let growth_passes_a_quadratic_cost_under_a_quadratic_bound () =
  Alcotest.(check (result unit string))
    "the growth" (Ok ())
    (Timed_work.growth ~exponent:2. ~margin:3. ~runs:3 ~sizes:(1_000, 8_000)
       ~input:Fun.id quadratic)

let growth_does_not_time_the_input () =
  Alcotest.(check (result unit string))
    "the growth" (Ok ())
    (Timed_work.growth ~margin:3. ~runs:3 ~sizes:(100, 800)
       ~input:(fun size -> (size, quadratic (size * 10)))
       (fun (size, _) -> linear (size * 10)))

let growth_refuses_sizes_that_cannot_tell_the_bound () =
  List.iter
    (fun (name, exponent, margin, runs, sizes) ->
      match
        Timed_work.growth ~exponent ~margin ~runs ~sizes ~input:Fun.id linear
      with
      | _ -> Alcotest.failf "%s: the call gave a value" name
      | exception Invalid_argument _ -> ())
    [
      ("a size below 1", 1., 1.5, 1, (0, 10));
      ("a margin below 1", 1., 0.5, 1, (10, 100));
      ("an exponent below 0", -1., 1.5, 1, (10, 100));
      ("no run", 1., 1.5, 0, (10, 100));
      ("a ratio equal to the margin", 1., 2., 1, (10, 20));
      ("a ratio below the margin", 1., 2., 1, (10, 15));
    ]

let check_growth_fails_the_test_on_an_error () =
  match
    Timed_work.check_growth ~margin:3. ~runs:1 ~sizes:(1_000, 8_000)
      ~input:Fun.id quadratic
  with
  | () -> Alcotest.fail "check_growth passed a quadratic cost"
  | exception Invalid_argument message -> Alcotest.fail message
  | exception _ -> ()

let check_growth_passes_a_linear_cost () =
  Timed_work.check_growth ~margin:3. ~runs:3 ~sizes:(1_000, 8_000) ~input:Fun.id
    linear

let tests =
  [
    case "growth passes a linear cost" growth_passes_a_linear_cost;
    case "growth fails a quadratic cost under a linear bound"
      growth_fails_a_quadratic_cost_under_a_linear_bound;
    case "growth passes a quadratic cost under a quadratic bound"
      growth_passes_a_quadratic_cost_under_a_quadratic_bound;
    case "growth does not time the input" growth_does_not_time_the_input;
    case "growth refuses sizes that cannot tell the bound"
      growth_refuses_sizes_that_cannot_tell_the_bound;
    case "check_growth passes a linear cost" check_growth_passes_a_linear_cost;
    case "check_growth fails the test on an error"
      check_growth_fails_the_test_on_an_error;
  ]
