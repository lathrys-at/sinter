(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Utf_8 = Sinter_bridge.Utf_8

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let accepts_one_code_point_of_each_length () =
  Alcotest.(check bool)
    "one code point of each length" true
    (Utf_8.is_valid "a\xc3\xa9\xe2\x82\xac\xf0\x9f\x92\xa1")

let refuses_a_lone_continuation_byte () =
  Alcotest.(check bool)
    "a lone continuation byte" false (Utf_8.is_valid "a\xff")

let accepts_the_empty_string () =
  Alcotest.(check (option int)) "no offset" None (Utf_8.first_invalid "")

let first_invalid_finds_a_last_byte_that_is_cut_short () =
  Alcotest.(check (option int))
    "the offset of the lead byte" (Some 2)
    (Utf_8.first_invalid "ab\xc3")

let valid_text_has_no_invalid_offset =
  property ~name:"valid text has no offset that is not UTF-8"
    ~print:String.escaped Generators.utf_8_string (fun text ->
      Utf_8.is_valid text && Option.is_none (Utf_8.first_invalid text))

let first_invalid_gives_the_offset_of_the_bad_run =
  property ~name:"first_invalid gives the offset of the first bad sequence"
    ~print:(fun (offset, text) -> Printf.sprintf "%d %S" offset text)
    Generators.not_utf_8_string_at
    (fun (offset, text) ->
      Utf_8.first_invalid text = Some offset && not (Utf_8.is_valid text))

let is_valid_agrees_with_first_invalid =
  property ~count:1000 ~name:"is_valid holds when first_invalid gives None"
    ~print:String.escaped
    QCheck2.Gen.(string_size ~gen:(char_range '\x7f' '\xf5') (int_bound 12))
    (fun text ->
      Utf_8.is_valid text = Option.is_none (Utf_8.first_invalid text))

let tests =
  [
    Alcotest.test_case "accepts one code point of each length" `Quick
      accepts_one_code_point_of_each_length;
    Alcotest.test_case "refuses a lone continuation byte" `Quick
      refuses_a_lone_continuation_byte;
    Alcotest.test_case "accepts the empty string" `Quick
      accepts_the_empty_string;
    Alcotest.test_case "first_invalid finds a last byte that is cut short"
      `Quick first_invalid_finds_a_last_byte_that_is_cut_short;
    valid_text_has_no_invalid_offset;
    first_invalid_gives_the_offset_of_the_bad_run;
    is_valid_agrees_with_first_invalid;
  ]
