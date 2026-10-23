(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let read text =
  match Major_minor.of_string text with
  | Some version -> version
  | None -> Alcotest.failf "%S is not a version" text

let of_string_reads_major_and_minor () =
  List.iter
    (fun text ->
      Alcotest.(check string)
        (text ^ " reads back") text
        (Major_minor.to_string (read text)))
    [ "1.0"; "0.0"; "2.13"; "10.200"; "123456789012345678901234567890.7" ]

let of_string_refuses_other_forms () =
  List.iter
    (fun text ->
      Alcotest.(check bool)
        (Printf.sprintf "%S is refused" text)
        true
        (Major_minor.of_string text = None))
    [
      "";
      "1";
      "1.";
      ".1";
      "1.0.0";
      "01.0";
      "1.00";
      "1.01";
      "+1.0";
      "-1.0";
      "1.a";
      " 1.0";
      "1.0 ";
      "1..0";
      "v1.0";
    ]

let make_writes_the_two_numbers () =
  Alcotest.(check string)
    "make 1 0" "1.0"
    (Major_minor.to_string (Major_minor.make 1 0));
  Alcotest.(check string)
    "make 0 12" "0.12"
    (Major_minor.to_string (Major_minor.make 0 12))

let make_refuses_a_number_below_zero () =
  Alcotest.check_raises "a major number below 0"
    (Invalid_argument "Major_minor.make: a number is below 0") (fun () ->
      ignore (Major_minor.make (-1) 0));
  Alcotest.check_raises "a minor number below 0"
    (Invalid_argument "Major_minor.make: a number is below 0") (fun () ->
      ignore (Major_minor.make 0 (-1)))

let order = Alcotest.(check int)

let compare_orders_by_major_then_minor () =
  let compare a b = Int.compare (Major_minor.compare (read a) (read b)) 0 in
  order "1.0 = 1.0" 0 (compare "1.0" "1.0");
  order "1.0 < 1.1" (-1) (compare "1.0" "1.1");
  order "1.9 < 1.10" (-1) (compare "1.9" "1.10");
  order "2.0 > 1.10" 1 (compare "2.0" "1.10");
  order "10.0 > 9.99" 1 (compare "10.0" "9.99");
  order "1.2 > 1.1" 1 (compare "1.2" "1.1")

let newer_and_older_major () =
  let check name expected found = Alcotest.(check bool) name expected found in
  check "1.1 is newer than 1.0" true
    (Major_minor.newer (read "1.1") ~than:(read "1.0"));
  check "1.0 is not newer than 1.0" false
    (Major_minor.newer (read "1.0") ~than:(read "1.0"));
  check "1.0 is not newer than 1.1" false
    (Major_minor.newer (read "1.0") ~than:(read "1.1"));
  check "0.9 has an older major than 1.0" true
    (Major_minor.older_major (read "0.9") ~than:(read "1.0"));
  check "1.0 has no older major than 1.5" false
    (Major_minor.older_major (read "1.0") ~than:(read "1.5"));
  check "2.0 has no older major than 1.5" false
    (Major_minor.older_major (read "2.0") ~than:(read "1.5"))

let number = Gen.(map string_of_int (0 -- 30))
let version = Gen.(map2 (fun a b -> a ^ "." ^ b) number number)

let property ?(count = 300) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let compare_agrees_with_the_numbers =
  property ~name:"compare agrees with the order of the pairs of numbers"
    ~print:QCheck2.Print.(pair string string)
    Gen.(pair version version)
    (fun (a, b) ->
      let pair text =
        match String.split_on_char '.' text with
        | [ x; y ] -> (int_of_string x, int_of_string y)
        | _ -> assert false
      in
      Int.compare (Major_minor.compare (read a) (read b)) 0
      = compare (pair a) (pair b))

let of_string_answers_any_text =
  property ~name:"of_string answers any text, and reads back what it accepts"
    ~print:QCheck2.Print.string
    Gen.(string_size ~gen:(oneof_list [ '0'; '1'; '.'; 'a' ]) (0 -- 6))
    (fun text ->
      match Major_minor.of_string text with
      | None -> true
      | Some version -> Major_minor.to_string version = text)

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "of_string reads major and minor" of_string_reads_major_and_minor;
    case "of_string refuses other forms" of_string_refuses_other_forms;
    case "make writes the two numbers" make_writes_the_two_numbers;
    case "make refuses a number below zero" make_refuses_a_number_below_zero;
    case "compare orders by major then minor" compare_orders_by_major_then_minor;
    case "newer and older major" newer_and_older_major;
    compare_agrees_with_the_numbers;
    of_string_answers_any_text;
  ]
