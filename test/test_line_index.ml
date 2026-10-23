(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 300) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let position =
  Alcotest.testable
    (fun formatter (place : Line_index.position) ->
      Format.fprintf formatter "%d:%d" place.line place.column)
    ( = )

let at line column = { Line_index.line; column }

(* A text of pieces that each hold one character or one line ending:
   ASCII, characters of two, three, and four bytes, blanks, and the
   three line endings. Some texts start with a byte order mark. *)
let text =
  Gen.map2
    (fun mark pieces ->
      (if mark then "\xEF\xBB\xBF" else "") ^ String.concat "" pieces)
    Gen.bool
    (Gen.list_size (Gen.int_range 0 24)
       (Gen.oneof_list
          [
            "a";
            "@";
            " ";
            "\t";
            "\xC3\xA9";
            "\xE2\x82\xAC";
            "\xF0\x9F\x98\x80";
            "\n";
            "\r\n";
            "\r";
          ]))

let mark_length text =
  if String.starts_with ~prefix:"\xEF\xBB\xBF" text then 3 else 0

(* The number of characters in the bytes from [start] to [stop]. *)
let characters text start stop =
  let total = ref 0 in
  for offset = start to stop - 1 do
    if Char.code text.[offset] land 0xC0 <> 0x80 then incr total
  done;
  !total

let lines_of_a_plain_text () =
  let index = Line_index.make "one\ntwo\n" in
  Alcotest.(check int) "the count" 2 (Line_index.count index);
  Alcotest.(check (list int))
    "the first bytes" [ 0; 4 ]
    [ Line_index.first index 1; Line_index.first index 2 ];
  Alcotest.(check (list string))
    "the contents" [ "one"; "two" ]
    [ Line_index.content index 1; Line_index.content index 2 ]

let last_line_without_a_line_feed_counts () =
  let index = Line_index.make "one\ntwo" in
  Alcotest.(check int) "the count" 2 (Line_index.count index);
  Alcotest.(check string) "the last line" "two" (Line_index.content index 2);
  Alcotest.(check int) "its end" 7 (Line_index.content_end index 2)

let empty_text_has_no_line () =
  Alcotest.(check int) "the count" 0 (Line_index.count (Line_index.make ""))

let carriage_return_before_a_line_feed_ends_the_line () =
  let index = Line_index.make "a\r\nb\r\n" in
  Alcotest.(check (list string))
    "the contents" [ "a"; "b" ]
    [ Line_index.content index 1; Line_index.content index 2 ];
  Alcotest.(check int) "the end of line 1" 1 (Line_index.content_end index 1)

let lone_carriage_return_is_a_character () =
  let index = Line_index.make "a\rb\nc\r" in
  Alcotest.(check int) "the count" 2 (Line_index.count index);
  Alcotest.(check (list string))
    "the contents" [ "a\rb"; "c\r" ]
    [ Line_index.content index 1; Line_index.content index 2 ];
  Alcotest.check position "the place of b" (at 1 3)
    (Line_index.position index 2)

let byte_order_mark_is_in_no_line () =
  let index = Line_index.make "\xEF\xBB\xBFab\n" in
  Alcotest.(check int) "the first byte of line 1" 3 (Line_index.first index 1);
  Alcotest.(check string) "line 1" "ab" (Line_index.content index 1);
  Alcotest.check position "a byte of the mark" (at 1 1)
    (Line_index.position index 1);
  Alcotest.check position "the a" (at 1 1) (Line_index.position index 3);
  Alcotest.check position "the b" (at 1 2) (Line_index.position index 4)

let byte_order_mark_alone_makes_an_empty_line () =
  let index = Line_index.make "\xEF\xBB\xBF" in
  Alcotest.(check int) "the count" 1 (Line_index.count index);
  Alcotest.(check string) "line 1" "" (Line_index.content index 1);
  Alcotest.(check int) "its line" 1 (Line_index.line_of index 2)

let columns_count_characters () =
  (* "é" has two bytes and "😀" four. *)
  let index = Line_index.make "\xC3\xA9\xF0\x9F\x98\x80x\n" in
  Alcotest.check position "the x" (at 1 3) (Line_index.position index 6);
  Alcotest.check position "a byte inside the emoji" (at 1 2)
    (Line_index.position index 4);
  Alcotest.check position "after the x" (at 1 4) (Line_index.after index 7);
  Alcotest.check position "after the emoji" (at 1 3) (Line_index.after index 6)

let line_ending_is_after_the_last_character () =
  let index = Line_index.make "ab\r\nc\n" in
  Alcotest.check position "the carriage return" (at 1 3)
    (Line_index.position index 2);
  Alcotest.check position "the line feed" (at 1 3) (Line_index.position index 3);
  Alcotest.check position "the c" (at 2 1) (Line_index.position index 4);
  Alcotest.(check (list int))
    "the lines of each byte" [ 1; 1; 1; 1; 2; 2 ]
    (List.init 6 (Line_index.line_of index))

let refuses name message f =
  Alcotest.check_raises name (Invalid_argument message) (fun () ->
      ignore (f ()))

let refuses_a_line_out_of_range () =
  let index = Line_index.make "a\n" in
  refuses "line 0" "Line_index: no line 0" (fun () -> Line_index.first index 0);
  refuses "line 2" "Line_index: no line 2" (fun () ->
      Line_index.content_end index 2);
  refuses "line 2 of content" "Line_index: no line 2" (fun () ->
      Line_index.content index 2)

let refuses_an_offset_out_of_range () =
  let index = Line_index.make "a\n" in
  refuses "offset -1" "Line_index: no place at offset -1" (fun () ->
      Line_index.line_of index (-1));
  refuses "offset 3" "Line_index: no place at offset 3" (fun () ->
      Line_index.position index 3);
  refuses "the empty text" "Line_index: no place at offset 0" (fun () ->
      Line_index.position (Line_index.make "") 0);
  refuses "stop 0" "Line_index: no byte before offset 0" (fun () ->
      Line_index.after index 0);
  refuses "stop 3" "Line_index: no byte before offset 3" (fun () ->
      Line_index.after index 3)

let end_of_the_text_follows_the_last_character () =
  let without = Line_index.make "a\n\xC3\xA9b"
  and with_feed = Line_index.make "ab\r\n" in
  Alcotest.(check int) "the line of the end" 2 (Line_index.line_of without 5);
  Alcotest.check position "without a final line feed" (at 2 3)
    (Line_index.position without 5);
  Alcotest.check position "after a final CRLF" (at 1 3)
    (Line_index.position with_feed 4)

let text_gives_the_text =
  property ~name:"text gives the text that make took" ~print:String.escaped text
    (fun text -> Line_index.text (Line_index.make text) == text)

(* The mark, then each line and its line ending, give the text back. *)
let lines_rebuild_the_text =
  property ~name:"the lines and their endings rebuild the text"
    ~print:String.escaped text (fun text ->
      let index = Line_index.make text in
      let count = Line_index.count index in
      let pieces =
        List.init count (fun offset ->
            let line = offset + 1 in
            let stop =
              if line = count then String.length text
              else Line_index.first index (line + 1)
            in
            let ending_start = Line_index.content_end index line in
            Line_index.content index line
            ^ String.sub text ending_start (stop - ending_start))
      in
      String.equal text
        (String.sub text 0 (mark_length text) ^ String.concat "" pieces))

let no_content_holds_a_line_ending =
  property ~name:"no content holds a line feed or ends with a CR before an LF"
    ~print:String.escaped text (fun text ->
      let index = Line_index.make text in
      List.for_all
        (fun line ->
          let content = Line_index.content index line in
          let stop = Line_index.content_end index line in
          (not (String.contains content '\n'))
          && not
               (String.ends_with ~suffix:"\r" content
               && stop < String.length text
               && text.[stop] = '\n'))
        (List.init (Line_index.count index) (fun offset -> offset + 1)))

(* A naive count: the line of a byte is one more than the number of line
   feeds before it. *)
let line_of_counts_the_line_feeds_before =
  property ~name:"line_of is one more than the line feeds before the byte"
    ~print:String.escaped text (fun text ->
      let index = Line_index.make text in
      List.for_all
        (fun offset ->
          let feeds = ref 0 in
          String.iteri
            (fun before byte ->
              if before < offset && byte = '\n' then incr feeds)
            text;
          Line_index.line_of index offset = !feeds + 1)
        (List.init (String.length text) Fun.id))

let position_of_a_character_counts_the_characters_before =
  property ~name:"the column of a character counts the characters before it"
    ~print:String.escaped text (fun text ->
      let index = Line_index.make text in
      List.for_all
        (fun offset ->
          let place = Line_index.position index offset in
          let first = Line_index.first index place.line in
          offset < first
          || offset >= Line_index.content_end index place.line
          || Char.code text.[offset] land 0xC0 = 0x80
          || place.column = 1 + characters text first offset)
        (List.init (String.length text) Fun.id))

let positions_stay_inside_their_lines =
  property ~name:"every place is on a line and at most one column past it"
    ~print:String.escaped text (fun text ->
      let index = Line_index.make text in
      List.for_all
        (fun offset ->
          let place = Line_index.position index offset in
          let after = Line_index.after index (offset + 1) in
          let width line =
            characters text
              (Line_index.first index line)
              (Line_index.content_end index line)
          in
          place.line >= 1
          && place.line <= Line_index.count index
          && place.column >= 1
          && place.column <= width place.line + 1
          && after.line = place.line
          && after.column = place.column + 1)
        (List.init (String.length text) Fun.id))

let tests =
  [
    Alcotest.test_case "finds the lines of a plain text" `Quick
      lines_of_a_plain_text;
    Alcotest.test_case "counts a last line without a line feed" `Quick
      last_line_without_a_line_feed_counts;
    Alcotest.test_case "finds no line in the empty text" `Quick
      empty_text_has_no_line;
    Alcotest.test_case "ends a line at a CR before an LF" `Quick
      carriage_return_before_a_line_feed_ends_the_line;
    Alcotest.test_case "takes a lone CR as a character" `Quick
      lone_carriage_return_is_a_character;
    Alcotest.test_case "puts the byte order mark in no line" `Quick
      byte_order_mark_is_in_no_line;
    Alcotest.test_case "makes an empty line of a lone byte order mark" `Quick
      byte_order_mark_alone_makes_an_empty_line;
    Alcotest.test_case "counts columns in characters" `Quick
      columns_count_characters;
    Alcotest.test_case "puts a line ending after the last character" `Quick
      line_ending_is_after_the_last_character;
    Alcotest.test_case "refuses a line out of range" `Quick
      refuses_a_line_out_of_range;
    Alcotest.test_case "refuses an offset out of range" `Quick
      refuses_an_offset_out_of_range;
    Alcotest.test_case "puts the end of the text after the last character"
      `Quick end_of_the_text_follows_the_last_character;
    text_gives_the_text;
    lines_rebuild_the_text;
    no_content_holds_a_line_ending;
    line_of_counts_the_line_feeds_before;
    position_of_a_character_counts_the_characters_before;
    positions_stay_inside_their_lines;
  ]
