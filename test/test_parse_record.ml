(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let contains needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec search index =
    index + n <= h
    && (String.equal (String.sub haystack index n) needle || search (index + 1))
  in
  search 0

let record_or_fail ~path ~source capture =
  match Parse_record.of_capture ~path ~source capture with
  | Ok record -> record
  | Error error -> Alcotest.fail (Parse_record.message ~path error)

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let position source offset =
  ( Generators.rows_before source offset + 1,
    offset - Generators.start_of_line source offset + 1 )

let int_field record name =
  match List.assoc_opt name record with
  | Some (Jsonl.Scalar (Jsonl.Int found)) -> found
  | _ -> Alcotest.failf "the record holds no integer field %s" name

let string_field record name =
  match List.assoc_opt name record with
  | Some (Jsonl.Scalar (Jsonl.String found)) -> found
  | _ -> Alcotest.failf "the record holds no string field %s" name

let places_the_end_of_a_capture_that_ends_before_byte_two () =
  let capture =
    {
      Sinter_bridge.Query.match_number = 0;
      pattern = 0;
      name = "d";
      node_type = "document";
      range =
        {
          start_byte = 0;
          end_byte = 1;
          start_row = 0;
          start_column = 0;
          end_row = 1;
          end_column = 0;
        };
      text = "\n";
    }
  in
  let record = record_or_fail ~path:"f.json" ~source:"\n" capture in
  Alcotest.(check (option bool))
    "eline is the line that holds the last byte" (Some true)
    (Option.map (fun v -> v = Jsonl.int 1) (List.assoc_opt "eline" record));
  Alcotest.(check (option bool))
    "ecol is one past the last byte" (Some true)
    (Option.map (fun v -> v = Jsonl.int 2) (List.assoc_opt "ecol" record))

let places_the_end_of_a_capture_that_ends_at_byte_two () =
  let capture =
    {
      Sinter_bridge.Query.match_number = 0;
      pattern = 0;
      name = "d";
      node_type = "document";
      range =
        {
          start_byte = 0;
          end_byte = 2;
          start_row = 0;
          start_column = 0;
          end_row = 2;
          end_column = 0;
        };
      text = "\n\n";
    }
  in
  let record = record_or_fail ~path:"f.json" ~source:"\n\n" capture in
  Alcotest.(check (option bool))
    "eline is the line that holds the last byte" (Some true)
    (Option.map (fun v -> v = Jsonl.int 2) (List.assoc_opt "eline" record));
  Alcotest.(check (option bool))
    "ecol is one past the last byte on that line" (Some true)
    (Option.map (fun v -> v = Jsonl.int 2) (List.assoc_opt "ecol" record))

let field_names =
  [
    "cap";
    "col";
    "eb";
    "ecol";
    "eline";
    "line";
    "node";
    "pat";
    "path";
    "sb";
    "text";
  ]

let record_of source (capture : Sinter_bridge.Query.capture) =
  record_or_fail ~path:"f.json" ~source capture

let the_span_of_a_record_agrees_with_the_source
    (source, (capture : Sinter_bridge.Query.capture)) =
  let record = record_of source capture in
  let range = capture.range in
  let line, col = position source range.start_byte in
  let eline, ecol =
    if range.end_byte > range.start_byte then
      let last_line, last_col = position source (range.end_byte - 1) in
      (last_line, last_col + 1)
    else (line, col)
  in
  int_field record "line" = line
  && int_field record "col" = col
  && int_field record "eline" = eline
  && int_field record "ecol" = ecol

let a_record_holds_the_bytes_of_the_capture
    (source, (capture : Sinter_bridge.Query.capture)) =
  let record = record_of source capture in
  int_field record "sb" = capture.range.start_byte
  && int_field record "eb" = capture.range.end_byte
  && String.equal
       (string_field record "text")
       (String.sub source capture.range.start_byte
          (capture.range.end_byte - capture.range.start_byte))

let a_record_holds_the_named_fields (source, capture) =
  let record = record_of source capture in
  List.equal String.equal (List.sort compare (List.map fst record)) field_names

let to_string_accepts_a_record_of_a_capture (source, capture) =
  let line = Jsonl.to_string (record_of source capture) in
  String.length line > 1
  && line.[0] = '{'
  && line.[String.length line - 1] = '}'

let a_record_of_a_capture_outside_the_source_is_refused (source, capture) =
  match record_of source capture with
  | _ -> false
  | exception Invalid_argument message ->
      contains "not inside the source" message

let refuses_a_capture_that_runs_past_the_source () =
  let capture =
    {
      Sinter_bridge.Query.match_number = 0;
      pattern = 0;
      name = "d";
      node_type = "document";
      range =
        {
          start_byte = 0;
          end_byte = 2;
          start_row = 0;
          start_column = 0;
          end_row = 1;
          end_column = 0;
        };
      text = "";
    }
  in
  Alcotest.check_raises "a capture of two bytes in a source of none"
    (Invalid_argument
       "Sinter_core.Parse_record: the byte range of the capture is not inside \
        the source") (fun () ->
      ignore (Parse_record.of_capture ~path:"f.json" ~source:"" capture))

let not_utf_8 = "\xff"

let one_capture ?(name = "d") ?(node_type = "document") ?(text = "a") () =
  {
    Sinter_bridge.Query.match_number = 0;
    pattern = 0;
    name;
    node_type;
    range =
      {
        start_byte = 0;
        end_byte = 1;
        start_row = 0;
        start_column = 0;
        end_row = 0;
        end_column = 1;
      };
    text;
  }

let refusal ?(path = "f.json") capture =
  match Parse_record.of_capture ~path ~source:"a" capture with
  | Ok _ -> Alcotest.fail "the call built a record"
  | Error error -> Parse_record.message ~path error

let a_capture_name_that_is_not_utf_8_is_refused () =
  Alcotest.(check string)
    "the message names the file and the string"
    "f.json: the name of a capture is not UTF-8 text"
    (refusal (one_capture ~name:not_utf_8 ()))

let a_node_type_that_is_not_utf_8_is_refused () =
  Alcotest.(check string)
    "the message names the file and the string"
    "f.json: the type of a node is not UTF-8 text"
    (refusal (one_capture ~node_type:not_utf_8 ()))

let a_text_that_is_not_utf_8_is_refused () =
  Alcotest.(check string)
    "the message names the file and the string"
    "f.json: the text of a node is not UTF-8 text"
    (refusal (one_capture ~text:not_utf_8 ()))

let a_path_that_is_not_utf_8_is_refused () =
  Alcotest.(check string)
    "the message gives the file name as bytes"
    "the file name is not UTF-8 text: \\255"
    (refusal ~path:not_utf_8 (one_capture ()))

let source_and_capture_with_a_bad_string =
  let open QCheck2.Gen in
  let* source, (capture : Sinter_bridge.Query.capture) =
    Generators.source_and_capture
  in
  let* text = Generators.not_utf_8_string in
  let+ field =
    oneof_list
      [
        Parse_record.Capture_name;
        Parse_record.Node_type;
        Parse_record.Node_text;
      ]
  in
  let capture =
    match field with
    | Parse_record.Capture_name ->
        { capture with Sinter_bridge.Query.name = text }
    | Parse_record.Node_type ->
        { capture with Sinter_bridge.Query.node_type = text }
    | Parse_record.Node_text -> { capture with Sinter_bridge.Query.text }
  in
  (source, capture, field)

let print_source_capture_and_field (source, capture, _) =
  Generators.print_source_and_capture (source, capture)

let a_record_of_a_capture_with_a_bad_string_is_refused (source, capture, field)
    =
  match Parse_record.of_capture ~path:"f.json" ~source capture with
  | Ok _ -> false
  | Error error ->
      error = Parse_record.Not_utf_8 field
      && contains "is not UTF-8 text"
           (Parse_record.message ~path:"f.json" error)

let every_error_has_a_help () =
  List.iter
    (fun (error : Parse_record.error) ->
      let name =
        match error with
        | Parse_record.Path_not_utf_8 -> "Path_not_utf_8"
        | Parse_record.Not_utf_8 Parse_record.Capture_name -> "Capture_name"
        | Parse_record.Not_utf_8 Parse_record.Node_type -> "Node_type"
        | Parse_record.Not_utf_8 Parse_record.Node_text -> "Node_text"
      in
      Alcotest.(check bool)
        (name ^ " has a help") true
        (Parse_record.help error <> ""))
    Parse_record.
      [
        Path_not_utf_8;
        Not_utf_8 Capture_name;
        Not_utf_8 Node_type;
        Not_utf_8 Node_text;
      ]

let tests =
  [
    Alcotest.test_case "every error has a help" `Quick every_error_has_a_help;
    Alcotest.test_case "places the end of a capture that ends before byte two"
      `Quick places_the_end_of_a_capture_that_ends_before_byte_two;
    Alcotest.test_case "places the end of a capture that ends at byte two"
      `Quick places_the_end_of_a_capture_that_ends_at_byte_two;
    Alcotest.test_case "refuses a capture that runs past the source" `Quick
      refuses_a_capture_that_runs_past_the_source;
    Alcotest.test_case "a capture name that is not UTF-8 is refused" `Quick
      a_capture_name_that_is_not_utf_8_is_refused;
    Alcotest.test_case "a node type that is not UTF-8 is refused" `Quick
      a_node_type_that_is_not_utf_8_is_refused;
    Alcotest.test_case "a text that is not UTF-8 is refused" `Quick
      a_text_that_is_not_utf_8_is_refused;
    Alcotest.test_case "a path that is not UTF-8 is refused" `Quick
      a_path_that_is_not_utf_8_is_refused;
    property ~name:"the span of a record agrees with the source"
      ~print:Generators.print_source_and_capture Generators.source_and_capture
      the_span_of_a_record_agrees_with_the_source;
    property ~name:"a record holds the bytes of the capture"
      ~print:Generators.print_source_and_capture Generators.source_and_capture
      a_record_holds_the_bytes_of_the_capture;
    property ~name:"a record holds the eleven named fields"
      ~print:Generators.print_source_and_capture Generators.source_and_capture
      a_record_holds_the_named_fields;
    property ~name:"to_string accepts a record of a capture"
      ~print:Generators.print_source_and_capture Generators.source_and_capture
      to_string_accepts_a_record_of_a_capture;
    property ~name:"a record of a capture outside the source is refused"
      ~print:Generators.print_source_and_capture
      Generators.source_and_capture_outside
      a_record_of_a_capture_outside_the_source_is_refused;
    property ~name:"a record of a capture with a bad string is refused"
      ~print:print_source_capture_and_field source_and_capture_with_a_bad_string
      a_record_of_a_capture_with_a_bad_string_is_refused;
  ]
