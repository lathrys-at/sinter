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

let escaped_writes_each_byte_that_is_not_utf_8 () =
  Alcotest.(check string)
    "the text" "Delivers: caf\\xe9/s \\xff\\xfe \xc3\xa9"
    (Utf_8.escaped "Delivers: caf\xe9/s \xff\xfe \xc3\xa9");
  Alcotest.(check string)
    "a sequence that is cut short gives each of its bytes" "a\\xe2\\x82b"
    (Utf_8.escaped "a\xe2\x82b");
  Alcotest.(check string) "the empty text" "" (Utf_8.escaped "");
  Alcotest.(check (list string))
    "the paths"
    [ "docs/caf\\xe9.md"; "caf\xc3\xa9.md"; "\\xff\\xfe" ]
    (List.map Utf_8.escaped [ "docs/caf\xe9.md"; "caf\xc3\xa9.md"; "\xff\xfe" ])

let escaped_gives_valid_text_back =
  property ~name:"escaped gives valid text back" ~print:String.escaped
    Generators.utf_8_string (fun text -> String.equal (Utf_8.escaped text) text)

let rec escaped_one_piece_at_a_time rest =
  match Utf_8.first_invalid rest with
  | None -> rest
  | Some offset ->
      String.sub rest 0 offset
      ^ Printf.sprintf "\\x%02x" (Char.code rest.[offset])
      ^ escaped_one_piece_at_a_time
          (String.sub rest (offset + 1) (String.length rest - offset - 1))

let escaped_is_each_piece_up_to_the_next_bad_byte =
  property
    ~name:"escaped writes one byte at each first offset that is not UTF-8"
    ~print:String.escaped
    QCheck2.Gen.(string_size ~gen:char (int_bound 64))
    (fun text ->
      String.equal (Utf_8.escaped text) (escaped_one_piece_at_a_time text))

let escaped_gives_valid_text_for_any_bytes =
  property ~name:"escaped gives valid text for any bytes" ~print:String.escaped
    QCheck2.Gen.(string_size ~gen:char (int_bound 64))
    (fun text -> Utf_8.is_valid (Utf_8.escaped text))

let allocated_by_escaped text =
  let before = Gc.allocated_bytes () in
  let result = Utf_8.escaped text in
  (Gc.allocated_bytes () -. before, String.length result)

let escaped_allocates_in_proportion_to_the_length_of_its_text () =
  let length = 20_000 in
  let text = "Delivers: " ^ String.make length '\xff' in
  let allocated, size = allocated_by_escaped text in
  Alcotest.(check int) "the length of the result" (10 + (4 * length)) size;
  Alcotest.(check bool)
    (Printf.sprintf
       "%d bytes that are not UTF-8 shown with %.0f bytes allocated, under %d"
       length allocated (500 * length))
    true
    (allocated < float_of_int (500 * length))

let doubling_the_text_about_doubles_the_allocation () =
  let measured length =
    fst (allocated_by_escaped (String.make length '\xff'))
  in
  let one = measured 20_000 and two = measured 40_000 in
  Alcotest.(check bool)
    (Printf.sprintf "%.0f bytes, then %.0f bytes" one two)
    true
    (two < 2.5 *. one)

let tests =
  [
    Alcotest.test_case "escaped writes each byte that is not UTF-8" `Quick
      escaped_writes_each_byte_that_is_not_utf_8;
    escaped_gives_valid_text_back;
    escaped_is_each_piece_up_to_the_next_bad_byte;
    escaped_gives_valid_text_for_any_bytes;
    Alcotest.test_case
      "escaped allocates in proportion to the length of its text" `Quick
      escaped_allocates_in_proportion_to_the_length_of_its_text;
    Alcotest.test_case "doubling the text about doubles the allocation" `Quick
      doubling_the_text_about_doubles_the_allocation;
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
