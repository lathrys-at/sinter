(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let line = Alcotest.(check string)

let sorts_keys () =
  line "keys are sorted" {|{"a":1,"b":2,"c":3}|}
    (Jsonl.to_string
       [ ("c", Jsonl.int 3); ("a", Jsonl.int 1); ("b", Jsonl.int 2) ])

(* spec/jsonl.md section 2 orders keys by UTF-16 code units. A code
   point at U+10000 or above starts with a high surrogate, and a high
   surrogate is below U+E000. In UTF-8 byte order the same code point
   sorts after U+E000. The two orders therefore differ for this
   pair. *)
let sorts_keys_by_utf16_code_units () =
  (* "\xf0\x90\x80\x80" is U+10000; "\xee\x80\x80" is U+E000. *)
  let astral = "\xf0\x90\x80\x80" in
  let private_use = "\xee\x80\x80" in
  Alcotest.(check bool)
    "U+10000 sorts before U+E000" true
    (Jsonl.compare_keys astral private_use < 0)

let writes_every_value_type () =
  line "all four value types"
    {|{"empty":[],"flag":false,"n":-7,"names":["x","y"],"s":"t","sizes":[1,2]}|}
    (Jsonl.to_string
       [
         ("s", Jsonl.string "t");
         ("n", Jsonl.int (-7));
         ("flag", Jsonl.bool false);
         ("names", Jsonl.strings [ "x"; "y" ]);
         ("sizes", Jsonl.ints [ 1; 2 ]);
         ("empty", Jsonl.strings []);
       ])

let escapes_as_rfc_8785_requires () =
  line "the seven short escapes and the \\u00xx form"
    {|{"s":"\"\\\b\f\n\r\t\u0000\u001f"}|}
    (Jsonl.to_string [ ("s", Jsonl.string "\"\\\b\012\n\r\t\000\031") ])

(* RFC 8785 escapes no code point at U+0020 or above, except the
   quotation mark and the reverse solidus. *)
let keeps_text_above_the_ascii_range () =
  let text = "\xc3\xa9 \xe2\x82\xac \xf0\x9f\x94\xa5 / \x7f" in
  line "text passes through unescaped"
    ("{\"s\":\"" ^ text ^ "\"}")
    (Jsonl.to_string [ ("s", Jsonl.string text) ])

let rejects_a_repeated_field () =
  Alcotest.check_raises "the same field twice"
    (Invalid_argument
       "Sinter_core.Jsonl: the record holds the field \"a\" twice") (fun () ->
      ignore (Jsonl.to_string [ ("a", Jsonl.int 1); ("a", Jsonl.int 2) ]))

let rejects_an_integer_that_is_too_large () =
  let too_large = 9007199254740992 in
  Alcotest.check_raises "2^53 is out of range"
    (Invalid_argument
       "Sinter_core.Jsonl: an integer value is outside the range that \
        spec/jsonl.md section 2 allows") (fun () ->
      ignore (Jsonl.to_string [ ("n", Jsonl.int too_large) ]))

let accepts_the_largest_integer () =
  line "2^53-1 is in range" {|{"n":9007199254740991}|}
    (Jsonl.to_string [ ("n", Jsonl.int 9007199254740991) ]);
  line "-(2^53-1) is in range" {|{"n":-9007199254740991}|}
    (Jsonl.to_string [ ("n", Jsonl.int (-9007199254740991)) ])

let rejects_text_that_is_not_utf_8 () =
  Alcotest.check_raises "a lone continuation byte"
    (Invalid_argument "Sinter_core.Jsonl: a string value is not valid UTF-8")
    (fun () -> ignore (Jsonl.to_string [ ("s", Jsonl.string "\xff") ]))

let writes_one_line_with_lf () =
  let file = Filename.temp_file "sinter-jsonl" ".jsonl" in
  let channel = open_out_bin file in
  Jsonl.output channel [ ("a", Jsonl.int 1) ];
  close_out channel;
  let channel = open_in_bin file in
  let contents = really_input_string channel (in_channel_length channel) in
  close_in channel;
  Sys.remove file;
  line "the line ends with LF" "{\"a\":1}\n" contents

let tests =
  [
    Alcotest.test_case "sorts keys" `Quick sorts_keys;
    Alcotest.test_case "sorts keys by UTF-16 code units" `Quick
      sorts_keys_by_utf16_code_units;
    Alcotest.test_case "writes every value type" `Quick writes_every_value_type;
    Alcotest.test_case "escapes as RFC 8785 requires" `Quick
      escapes_as_rfc_8785_requires;
    Alcotest.test_case "keeps text above the ASCII range" `Quick
      keeps_text_above_the_ascii_range;
    Alcotest.test_case "rejects a repeated field" `Quick
      rejects_a_repeated_field;
    Alcotest.test_case "rejects an integer that is too large" `Quick
      rejects_an_integer_that_is_too_large;
    Alcotest.test_case "accepts the largest integer" `Quick
      accepts_the_largest_integer;
    Alcotest.test_case "rejects text that is not UTF-8" `Quick
      rejects_text_that_is_not_utf_8;
    Alcotest.test_case "writes one line with LF" `Quick writes_one_line_with_lf;
  ]
