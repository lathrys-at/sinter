(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let property_of ~print name gen f =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:500 ~name ~print gen f)

let property name gen f = property_of ~print:String.escaped name gen f
let case name f = Alcotest.test_case name `Quick f

let is_bad code =
  code < 0x20
  || (code >= 0x7f && code <= 0x9f)
  || (code >= 0x202a && code <= 0x202e)
  || (code >= 0x2066 && code <= 0x2069)

let rec printable text offset =
  offset >= String.length text
  ||
  let decoded = String.get_utf_8_uchar text offset in
  Uchar.utf_decode_is_valid decoded
  && (not (is_bad (Uchar.to_int (Uchar.utf_decode_uchar decoded))))
  && printable text (offset + Uchar.utf_decode_length decoded)

let a_clean_text_is_utf_8_with_no_control_character =
  property "a clean text is UTF-8 with no control or bidirectional character"
    Generators.terminal_text (fun text -> printable (Display.clean text) 0)

let clean_changes_a_clean_text_in_no_way =
  property "clean changes a clean text in no way" Generators.terminal_text
    (fun text ->
      let once = Display.clean text in
      Display.clean once == once)

let clean_keeps_a_printable_text_itself =
  property "clean gives a printable text back as itself" Generators.utf_8_string
    (fun text ->
      QCheck2.assume (printable text 0 && not (String.contains text '\t'));
      Display.clean text == text)

let clean_replaces_each_character_that_a_terminal_reads () =
  Alcotest.(check (list string))
    "the printed forms"
    [
      "a    b";
      "\xef\xbf\xbd[31m";
      "\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd";
      "x\xef\xbf\xbdy\xef\xbf\xbdz";
      "\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd";
      "\xef\xbf\xbd\xef\xbf\xbd";
      "\xe6\x97\xa5\xf0\x9f\xa6\x80e\xcc\x81\xe2\x80\xa9\xe2\x81\xaa";
    ]
    (List.map Display.clean
       [
         "a\tb";
         "\x1b[31m";
         "\x00\r\n";
         "x\x7fy\xc2\x85z";
         "\xe2\x80\xaa\xe2\x80\xae\xe2\x81\xa6\xe2\x81\xa9";
         "\xff\xfe";
         "\xe6\x97\xa5\xf0\x9f\xa6\x80e\xcc\x81\xe2\x80\xa9\xe2\x81\xaa";
       ])

let clean_replaces_exactly_the_characters_of_each_range () =
  let encode code =
    let buffer = Buffer.create 4 in
    Buffer.add_utf_8_uchar buffer (Uchar.of_int code);
    Buffer.contents buffer
  in
  Alcotest.(check (list (pair int bool)))
    "each code point at the edge of a range, and whether it is replaced"
    [
      (0x1f, true);
      (0x20, false);
      (0x7e, false);
      (0x7f, true);
      (0x9f, true);
      (0xa0, false);
      (0x2029, false);
      (0x202a, true);
      (0x202e, true);
      (0x202f, false);
      (0x2065, false);
      (0x2066, true);
      (0x2069, true);
      (0x206a, false);
    ]
    (List.map
       (fun code -> (code, Display.clean (encode code) = "\xef\xbf\xbd"))
       [
         0x1f;
         0x20;
         0x7e;
         0x7f;
         0x9f;
         0xa0;
         0x2029;
         0x202a;
         0x202e;
         0x202f;
         0x2065;
         0x2066;
         0x2069;
         0x206a;
       ])

let a_part_of_a_sequence_is_one_character () =
  Alcotest.(check (list (pair string int)))
    "the printed forms and the lengths"
    [
      ("\xef\xbf\xbdx", 2);
      ("\xef\xbf\xbdx", 2);
      ("\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd", 3);
    ]
    (List.map
       (fun text -> (Display.clean text, Display.length text))
       [ "\xe2\x80x"; "\xf0\x9f\xa6x"; "\xed\xa0\x80" ])

let the_width_counts_terminal_columns () =
  Alcotest.(check (list int))
    "the widths"
    [ 0; 3; 6; 2; 1; 4; 1; 3; 1 ]
    (List.map Display.width
       [
         "";
         "abc";
         "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e";
         "\xf0\x9f\xa6\x80";
         "e\xcc\x81";
         "\t";
         "\x1b";
         "\xe2\x80\xaea\xc2\x9b";
         "\xff";
       ])

let a_column_width_is_the_width_before_the_column () =
  let line = "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e \xf0\x9f\xa6\x80\t@x" in
  Alcotest.(check (list int))
    "the widths before the columns 0 to 9"
    [ 0; 0; 2; 4; 6; 7; 9; 13; 14; 15; 15 ]
    (List.map (Display.column_width line) [ 0; 1; 2; 3; 4; 5; 6; 7; 8; 9; 10 ])

let the_width_of_a_text_is_its_width_after_its_last_column =
  property "the width of a text is the column width after its last character"
    Generators.terminal_text (fun text ->
      Display.width text = Display.column_width text (Display.length text + 1)
      && Display.width text = Display.width (Display.clean text))

let a_column_width_grows_with_the_column =
  property_of "a column width grows with the column"
    ~print:QCheck2.Print.(pair String.escaped int)
    QCheck2.Gen.(pair Generators.terminal_text (int_range 0 30))
    (fun (text, column) ->
      Display.column_width text column <= Display.column_width text (column + 1))

let the_length_counts_characters () =
  Alcotest.(check (list int))
    "the lengths" [ 0; 3; 3; 2; 2 ]
    (List.map Display.length
       [
         "";
         "abc";
         "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e";
         "e\xcc\x81";
         "\xff\xfe";
       ])

let tests =
  [
    a_clean_text_is_utf_8_with_no_control_character;
    clean_changes_a_clean_text_in_no_way;
    clean_keeps_a_printable_text_itself;
    case "clean replaces each character that a terminal reads"
      clean_replaces_each_character_that_a_terminal_reads;
    case "clean replaces exactly the characters of each range"
      clean_replaces_exactly_the_characters_of_each_range;
    case "a part of a sequence is one character"
      a_part_of_a_sequence_is_one_character;
    case "the width counts terminal columns" the_width_counts_terminal_columns;
    case "a column width is the width before the column"
      a_column_width_is_the_width_before_the_column;
    the_width_of_a_text_is_its_width_after_its_last_column;
    a_column_width_grows_with_the_column;
    case "the length counts characters" the_length_counts_characters;
  ]
