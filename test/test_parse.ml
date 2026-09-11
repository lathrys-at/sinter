(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

(* Dune runs the test in the build copy of test/, so the paths below
   are relative to that directory. *)
let grammar = "fixtures/tree-sitter-json/tree-sitter-json.wasm"
let sample = "fixtures/sample.json"
let query = "fixtures/sample.scm"

let contains needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec search index =
    index + n <= h
    && (String.equal (String.sub haystack index n) needle || search (index + 1))
  in
  search 0

(* Everything that one run writes to its channel. *)
let output ~query ~paths =
  let file = Filename.temp_file "sinter-parse" ".out" in
  let channel = open_out_bin file in
  Fun.protect
    ~finally:(fun () ->
      close_out_noerr channel;
      Sys.remove file)
    (fun () ->
      Parse.run ~grammar ~query ~paths channel;
      close_out channel;
      let channel = open_in_bin file in
      Fun.protect
        ~finally:(fun () -> close_in_noerr channel)
        (fun () -> really_input_string channel (in_channel_length channel)))

(* Pattern 0 of the query captures the key and the value of a pair
   whose value is a string. Pattern 1 captures a number. Two pairs of
   the sample match pattern 0: the value of one other pair is an
   array, and the value of the last is a keyword. *)
let expected_captures =
  String.concat ""
    (List.map
       (fun line -> line ^ "\n")
       [
         {|{"cap":"key","col":4,"eb":9,"ecol":8,"eline":2,"line":2,"node":"string_content","pat":0,"path":"fixtures/sample.json","sb":5,"text":"name"}|};
         {|{"cap":"value","col":12,"eb":19,"ecol":18,"eline":2,"line":2,"node":"string_content","pat":0,"path":"fixtures/sample.json","sb":13,"text":"sinter"}|};
         {|{"cap":"key","col":4,"eb":32,"ecol":11,"eline":3,"line":3,"node":"string_content","pat":0,"path":"fixtures/sample.json","sb":25,"text":"version"}|};
         {|{"cap":"value","col":15,"eb":41,"ecol":20,"eline":3,"line":3,"node":"string_content","pat":0,"path":"fixtures/sample.json","sb":36,"text":"0.1.0"}|};
         {|{"cap":"number","col":13,"eb":60,"ecol":17,"eline":4,"line":4,"node":"number","pat":1,"path":"fixtures/sample.json","sb":56,"text":"8080"}|};
         {|{"cap":"number","col":19,"eb":66,"ecol":23,"eline":4,"line":4,"node":"number","pat":1,"path":"fixtures/sample.json","sb":62,"text":"9090"}|};
       ])

let prints_the_captures_of_the_fixture () =
  Alcotest.(check string)
    "six captures, as canonical JSONL" expected_captures
    (output ~query:(Some query) ~paths:[ sample ])

let prints_the_parse_tree () =
  Alcotest.(check string)
    "the parse tree as an S-expression"
    "(document (object (pair key: (string (string_content)) value: (string \
     (string_content))) (pair key: (string (string_content)) value: (string \
     (string_content))) (pair key: (string (string_content)) value: (array \
     (number) (number))) (pair key: (string (string_content)) value: (false))))\n"
    (output ~query:None ~paths:[ sample ])

let handles_every_file_in_order () =
  let both = output ~query:(Some query) ~paths:[ sample; sample ] in
  Alcotest.(check string)
    "the same file twice gives its captures twice"
    (expected_captures ^ expected_captures)
    both

(* The name of a source file that holds [text], and the message of the
   failure that the file causes. The message is "no failure" when the
   run gives none. *)
let source_failure text =
  let file = Filename.temp_file "sinter-parse" ".json" in
  let channel = open_out_bin file in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel text);
  let message =
    Fun.protect
      ~finally:(fun () -> Sys.remove file)
      (fun () ->
        try
          ignore (output ~query:(Some query) ~paths:[ file ]);
          "no failure"
        with Parse.Error message -> message)
  in
  (file, message)

(* The bridge refuses text that is not UTF-8 as well, and its message
   ends in the same words. Only the check of this library names the
   byte that starts no code point, so the two tests below state the
   whole message. *)
let reports_a_file_that_is_not_utf_8 () =
  let file, message = source_failure "{\"a\": \"\xff\"}" in
  Alcotest.(check string)
    "the message names the file and the byte"
    (file ^ ": the file is not UTF-8 text, at byte 7")
    message

let reports_a_file_whose_first_byte_is_not_utf_8 () =
  let file, message = source_failure "\xff{}" in
  Alcotest.(check string)
    "the message names byte 0"
    (file ^ ": the file is not UTF-8 text, at byte 0")
    message

let reports_a_file_that_does_not_exist () =
  let message =
    try
      ignore (output ~query:(Some query) ~paths:[ "no-such-file.json" ]);
      "no failure"
    with Parse.Error message -> message
  in
  Alcotest.(check string)
    "the message is the message of the system"
    "no-such-file.json: No such file or directory" message

let names_the_query_file_when_the_query_fails () =
  let file = Filename.temp_file "sinter-parse" ".scm" in
  let channel = open_out_bin file in
  output_string channel "(no_such_node) @x\n";
  close_out channel;
  let message =
    Fun.protect
      ~finally:(fun () -> Sys.remove file)
      (fun () ->
        try
          ignore (output ~query:(Some file) ~paths:[ sample ]);
          "no failure"
        with Parse.Error message -> message)
  in
  Alcotest.(check bool)
    "the message names the query file, not the source file" true
    (String.starts_with ~prefix:file message)

(* A query file that holds nothing runs no pattern, so the tool
   refuses it before it loads the query. *)
let reports_an_empty_query_file () =
  let file = Filename.temp_file "sinter-parse" ".scm" in
  close_out (open_out_bin file);
  let message =
    Fun.protect
      ~finally:(fun () -> Sys.remove file)
      (fun () ->
        try
          ignore (output ~query:(Some file) ~paths:[ sample ]);
          "no failure"
        with Parse.Error message -> message)
  in
  Alcotest.(check string)
    "the message names the query file"
    (file ^ ": the query file is empty")
    message

(* A semicolon starts a comment in the query language, so a query file
   of that one character holds no pattern. It is still not the empty
   query file: the run gives no failure. *)
let a_query_file_of_one_character_is_not_empty () =
  let file = Filename.temp_file "sinter-parse" ".scm" in
  let channel = open_out_bin file in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel ";");
  let written =
    Fun.protect
      ~finally:(fun () -> Sys.remove file)
      (fun () ->
        try output ~query:(Some file) ~paths:[ sample ]
        with Parse.Error message -> message)
  in
  Alcotest.(check string) "the run writes no line and fails not" "" written

(* A record ends on the line that holds its last byte. The document
   node of this file ends after the last line feed, and tree-sitter
   puts that end point on a fourth row that the file does not have. *)
let ends_a_span_on_the_line_of_its_last_byte () =
  let source = Filename.temp_file "sinter-parse" ".json" in
  let channel = open_out_bin source in
  output_string channel "{\n  \"a\": \"b\"\n}\n";
  close_out channel;
  let scm = Filename.temp_file "sinter-parse" ".scm" in
  let channel = open_out_bin scm in
  output_string channel "(document) @d\n";
  close_out channel;
  let line =
    Fun.protect
      ~finally:(fun () ->
        Sys.remove source;
        Sys.remove scm)
      (fun () -> output ~query:(Some scm) ~paths:[ source ])
  in
  Alcotest.(check bool)
    "the document of a file of three lines ends on line 3" true
    (contains {|"ecol":3,"eline":3|} line)

let reports_a_channel_that_cannot_be_written () =
  let file = Filename.temp_file "sinter-parse" ".out" in
  let channel = open_out_bin file in
  close_out channel;
  let message =
    Fun.protect
      ~finally:(fun () -> Sys.remove file)
      (fun () ->
        try
          Parse.run ~grammar ~query:(Some query) ~paths:[ sample ] channel;
          "no failure"
        with Parse.Error message -> message)
  in
  Alcotest.(check bool)
    "the message says the output cannot be written" true
    (contains "cannot write the output" message)

(* The message gives the name as bytes, because a name that is not
   UTF-8 text cannot go into a record. *)
let name_failure path =
  try
    ignore (output ~query:(Some query) ~paths:[ path ]);
    "no failure"
  with Parse.Error message -> message

let rejects_a_file_name_that_is_not_utf_8 () =
  Alcotest.(check string)
    "the message gives the file name as bytes"
    "the file name is not UTF-8 text: bad\\255name.json"
    (name_failure "bad\xffname.json")

let rejects_a_file_name_whose_first_byte_is_not_utf_8 () =
  Alcotest.(check string)
    "the message gives the file name as bytes"
    "the file name is not UTF-8 text: \\255name.json"
    (name_failure "\xffname.json")

let reads_the_grammar_name_from_the_module () =
  let wasm = Parse.read_file grammar in
  Alcotest.(check (option string))
    "the module of the fixture names the grammar json" (Some "json")
    (Parse.name_of_wasm wasm);
  Alcotest.(check (option string))
    "a file that is not wasm has no name" None
    (Parse.name_of_wasm "not a wasm module");
  Alcotest.(check (option string))
    "a header without sections has no name" None
    (Parse.name_of_wasm "\000asm\001\000\000\000")

(* A wasm module of a header and one export section. The section
   holds one export of the given name, of kind 0 and index 0. Every
   count and every length in the format is one byte here, because the
   test keeps them below 128. *)
let module_that_exports name =
  let section =
    Printf.sprintf "\001%c%s\000\000" (Char.chr (String.length name)) name
  in
  Printf.sprintf "\000asm\001\000\000\000\007%c%s"
    (Char.chr (String.length section))
    section

let gives_no_name_that_holds_a_nul_byte () =
  Alcotest.(check (option string))
    "a name without a NUL byte is a name" (Some "json")
    (Parse.name_of_wasm (module_that_exports "tree_sitter_json"));
  Alcotest.(check (option string))
    "a name with a NUL byte is no name" None
    (Parse.name_of_wasm (module_that_exports "tree_sitter_js\000n"))

(* A module of a header and one export section whose body is [body].
   The size of the section is one byte, so [body] stays below 128
   bytes. *)
let module_with_export_section body =
  Printf.sprintf "\000asm\001\000\000\000\007%c%s"
    (Char.chr (String.length body))
    body

(* Each module below fails the reader in one place. The reader gives
   no name for every one of them, and it raises on none of them. *)
let gives_no_name_for_a_module_the_reader_cannot_follow () =
  let check what body =
    Alcotest.(check (option string))
      what None
      (Parse.name_of_wasm (module_with_export_section body))
  in
  check "a number that runs off the end of the module" "\128";
  check "a number that runs past 28 bits of shift" "\128\128\128\128\128\001";
  check "an export name that runs past the end of the module" "\001\010ab";
  check "an export list with no export at all" "\000";
  check "an export list whose one export is not a grammar" "\001\003foo\000\000";
  check "an export whose kind byte is missing" "\001\003foo"

(* A capture that holds the one line feed of a one-byte file ends at
   row 1, column 0: the start of a line that the file does not hold.
   The record then names line 1, the line that holds the last byte,
   and column 2, one past that byte. *)
let places_the_end_of_a_capture_that_ends_before_byte_two () =
  let capture : Sinter_bridge.capture =
    {
      pattern = 0;
      name = "d";
      node_type = "document";
      start_byte = 0;
      end_byte = 1;
      start_row = 0;
      start_column = 0;
      end_row = 1;
      end_column = 0;
      text = "\n";
    }
  in
  let record = Parse.record_of_capture ~path:"f.json" ~source:"\n" capture in
  Alcotest.(check (option bool))
    "eline is the line that holds the last byte" (Some true)
    (Option.map (fun v -> v = Jsonl.int 1) (List.assoc_opt "eline" record));
  Alcotest.(check (option bool))
    "ecol is one past the last byte" (Some true)
    (Option.map (fun v -> v = Jsonl.int 2) (List.assoc_opt "ecol" record))

(* The name that the bridge needs comes from the module, so a file
   that a user renamed still loads. *)
let loads_a_grammar_file_under_another_name () =
  let renamed = Filename.temp_file "grammar" ".wasm" in
  let wasm = Parse.read_file grammar in
  let channel = open_out_bin renamed in
  output_string channel wasm;
  close_out channel;
  let tree =
    Fun.protect
      ~finally:(fun () -> Sys.remove renamed)
      (fun () ->
        let file = Filename.temp_file "sinter-parse" ".out" in
        let channel = open_out_bin file in
        Fun.protect
          ~finally:(fun () ->
            close_out_noerr channel;
            Sys.remove file)
          (fun () ->
            Parse.run ~grammar:renamed ~query:None ~paths:[ sample ] channel;
            close_out channel;
            let channel = open_in_bin file in
            Fun.protect
              ~finally:(fun () -> close_in_noerr channel)
              (fun () ->
                really_input_string channel (in_channel_length channel))))
  in
  Alcotest.(check bool)
    "the renamed grammar parses the sample" true
    (String.starts_with ~prefix:"(document" tree)

let names_a_source_that_cannot_be_read () =
  let message =
    try
      ignore (output ~query:(Some query) ~paths:[ "." ]);
      "no failure"
    with Parse.Error message -> message
  in
  (* An open of a directory fails as well, and its message also names
     the directory. Only the guard of this library gives these words,
     so the test states the whole message. *)
  Alcotest.(check string)
    "the message names the directory and says what is wrong"
    ".: is a directory" message

(* tree-sitter writes an S-expression by recursion in C, and a tree
   that nests deeply exhausts the stack of the thread. The bridge
   writes its own, so this file must give a tree and not a signal. *)
let writes_a_tree_that_nests_deeply () =
  let depth = 40000 in
  let file = Filename.temp_file "sinter-parse" ".json" in
  let channel = open_out_bin file in
  for _ = 1 to depth do
    output_char channel '['
  done;
  output_char channel '1';
  for _ = 1 to depth do
    output_char channel ']'
  done;
  close_out channel;
  let tree =
    Fun.protect
      ~finally:(fun () -> Sys.remove file)
      (fun () -> output ~query:None ~paths:[ file ])
  in
  Alcotest.(check bool)
    "the tree of a file that nests 40000 deep is written" true
    (String.starts_with ~prefix:"(document" tree && String.length tree > depth)

let names_the_grammar () =
  let check expected path =
    Alcotest.(check string) path expected (Parse.grammar_name path)
  in
  check "json" "test/fixtures/tree-sitter-json/tree-sitter-json.wasm";
  check "json" "tree-sitter-json.wasm";
  check "json" "json.wasm";
  check "type_script" "packs/tree-sitter-type-script.wasm"

(* The properties below check the pure functions of Parse against a
   reference that reads the source text and nothing else. *)

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

(* The line that holds the byte at [offset], from 1, and the column of
   that byte in its line, from 1. *)
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

let record_of source (capture : Sinter_bridge.capture) =
  Parse.record_of_capture ~path:"f.json" ~source capture

let the_span_of_a_record_agrees_with_the_source
    (source, (capture : Sinter_bridge.capture)) =
  let record = record_of source capture in
  let line, col = position source capture.start_byte in
  let eline, ecol =
    if capture.end_byte > capture.start_byte then
      let last_line, last_col = position source (capture.end_byte - 1) in
      (last_line, last_col + 1)
    else (line, col)
  in
  int_field record "line" = line
  && int_field record "col" = col
  && int_field record "eline" = eline
  && int_field record "ecol" = ecol

(* The generator builds the text of the capture as the byte range of
   the source, so the last clause below states that record_of_capture
   copies the field, and nothing more. That the bridge gives that
   range is "a capture is a byte range inside the source", in
   test_bridge.ml. *)
let a_record_holds_the_bytes_of_the_capture
    (source, (capture : Sinter_bridge.capture)) =
  let record = record_of source capture in
  int_field record "sb" = capture.start_byte
  && int_field record "eb" = capture.end_byte
  && String.equal
       (string_field record "text")
       (String.sub source capture.start_byte
          (capture.end_byte - capture.start_byte))

let a_record_holds_the_named_fields (source, capture) =
  let record = record_of source capture in
  List.equal String.equal (List.sort compare (List.map fst record)) field_names

(* Jsonl.to_string refuses a string that is not UTF-8 and an integer
   outside the range that a record allows. A record of a capture
   breaks neither, so the call gives a line. *)
let to_string_accepts_a_record_of_a_capture (source, capture) =
  let line = Jsonl.to_string (record_of source capture) in
  String.length line > 1
  && line.[0] = '{'
  && line.[String.length line - 1] = '}'

(* One engine and one grammar for the property below. The language
   keeps its engine alive, and alcotest runs one test at a time. *)
let language =
  lazy
    (let wasm = Parse.read_file grammar in
     Sinter_bridge.load (Sinter_bridge.create ()) ~name:"json" ~wasm)

(* The document node ends after the last line feed of the file, so a
   query that captures it tests the end of a span that no byte of the
   last line holds. *)
let spanning_query =
  "(document) @d\n\
   (object) @o\n\
   (array) @a\n\
   (pair) @p\n\
   (string) @s\n\
   (string_content) @c\n\
   (number) @n\n"

(* Put [source] in a file of its own, and run [use] on the path of
   that file. The file is gone when [use] returns. *)
let in_a_file source use =
  let path = Filename.temp_file "sinter-parse" ".json" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      let channel = open_out_bin path in
      Fun.protect
        ~finally:(fun () -> close_out_noerr channel)
        (fun () -> output_string channel source);
      use path)

let records_of source =
  in_a_file source (fun path ->
      (path, Parse.captures (Lazy.force language) ~query:spanning_query ~path))

(* Parse.tree reads the file and gives what the bridge gives for its
   text. *)
let the_tree_of_a_file_is_the_tree_of_its_text document =
  let source = document ^ "\n" in
  String.equal
    (in_a_file source (fun path -> Parse.tree (Lazy.force language) ~path))
    (Sinter_bridge.tree (Lazy.force language) ~source)

let the_records_of_a_file_agree_with_the_source document =
  (* A file ends with a line feed, and the end of the document node
     then falls on a row that the file does not hold. *)
  let source = document ^ "\n" in
  let path, records = records_of source in
  List.for_all
    (fun record ->
      let start_byte = int_field record "sb"
      and end_byte = int_field record "eb" in
      let line, col = position source start_byte in
      let eline, ecol =
        if end_byte > start_byte then
          let last_line, last_col = position source (end_byte - 1) in
          (last_line, last_col + 1)
        else (line, col)
      in
      int_field record "line" = line
      && int_field record "col" = col
      && int_field record "eline" = eline
      && int_field record "ecol" = ecol
      && String.equal
           (string_field record "text")
           (String.sub source start_byte (end_byte - start_byte))
      && String.equal (string_field record "path") path)
    records

let a_record_of_a_capture_outside_the_source_is_refused (source, capture) =
  match record_of source capture with
  | _ -> false
  | exception Invalid_argument message ->
      contains "not inside the source" message

(* The capture below runs two bytes past a source of no bytes, and its
   end column is 0, so the reader of the span looks for the line feed
   that ends the line before it. The property
   "a record of a capture outside the source is refused" found this
   case, and the reader raised
   Invalid_argument "String.rindex_from_opt / Bytes.rindex_from_opt".
   The interface named no such failure. *)
let refuses_a_capture_that_runs_past_the_source () =
  let capture =
    {
      Sinter_bridge.pattern = 0;
      name = "d";
      node_type = "document";
      start_byte = 0;
      end_byte = 2;
      start_row = 0;
      start_column = 0;
      end_row = 1;
      end_column = 0;
      text = "";
    }
  in
  Alcotest.check_raises "a capture of two bytes in a source of none"
    (Invalid_argument
       "Sinter_core.Parse: the byte range of the capture is not inside the \
        source") (fun () ->
      ignore (Parse.record_of_capture ~path:"f.json" ~source:"" capture))

(* One byte that starts no code point, so a string that holds it is
   not valid UTF-8. *)
let not_utf_8 = "\xff"

(* A capture of the one byte of the source "a". Each argument replaces
   one string of it; the byte range does not change, so the only thing
   that can be wrong with the capture is the string the caller
   replaced. *)
let one_capture ?(name = "d") ?(node_type = "document") ?(text = "a") () =
  {
    Sinter_bridge.pattern = 0;
    name;
    node_type;
    start_byte = 0;
    end_byte = 1;
    start_row = 0;
    start_column = 0;
    end_row = 0;
    end_column = 1;
    text;
  }

(* The message of the failure that [capture] causes. The test fails
   when the call builds a record instead. *)
let refusal ?(path = "f.json") capture =
  match Parse.record_of_capture ~path ~source:"a" capture with
  | _ -> Alcotest.fail "the call built a record"
  | exception Parse.Error message -> message

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

(* Which string of a capture the generator below made bad. *)
type bad_string = Capture_name | Node_type | Node_text

(* A source, and a capture inside it whose one bad string is not valid
   UTF-8. The integer fields do not change, so the byte range stays
   inside the source and the string is the only thing that is wrong. *)
let source_and_capture_with_a_bad_string =
  let open QCheck2.Gen in
  let* source, (capture : Sinter_bridge.capture) =
    Generators.source_and_capture
  in
  let* text = Generators.not_utf_8_string in
  let* which = oneof_list [ Capture_name; Node_type; Node_text ] in
  let capture =
    match which with
    | Capture_name -> { capture with Sinter_bridge.name = text }
    | Node_type -> { capture with Sinter_bridge.node_type = text }
    | Node_text -> { capture with Sinter_bridge.text }
  in
  return (source, capture)

(* A bad string gives Parse.Error and never Invalid_argument, which is
   the whole of the change: a string the tool was given is a fault of
   the environment, and only a fault of the tool leaves the command.
   An Invalid_argument here would leave this check and fail the
   property. *)
let a_record_of_a_capture_with_a_bad_string_is_refused (source, capture) =
  match Parse.record_of_capture ~path:"f.json" ~source capture with
  | _ -> false
  | exception Parse.Error message ->
      String.starts_with ~prefix:"f.json: " message
      && contains "is not UTF-8 text" message

(* The two properties below state that the function is total: it
   answers for every value of its argument type, and raises nothing.
   Each one adds the cheapest clause that can fail, so that neither
   passes because the call did nothing. *)
let the_reader_of_a_module_answers_for_any_bytes wasm =
  match Parse.name_of_wasm wasm with
  | None -> true
  | Some found -> contains ("tree_sitter_" ^ found) wasm

(* The bridge refuses a grammar name that holds a NUL byte, so the
   reader gives no such name and the caller falls back to the file
   name. *)
let a_name_from_a_module_can_name_a_grammar wasm =
  match Parse.name_of_wasm wasm with
  | None -> true
  | Some name -> not (String.contains name '\000')

let the_reader_of_a_module_finds_a_generated_export (name, wasm) =
  Option.equal String.equal (Parse.name_of_wasm wasm) (Some name)

(* A grammar name is the base name of the path without its extension,
   so it is never longer than that base name. It can still hold a
   slash: the base name of "/" is "/". *)
let a_grammar_name_comes_back_for_any_file_name path =
  String.length (Parse.grammar_name path)
  <= String.length (Filename.basename path)

let a_grammar_name_holds_no_hyphen path =
  not (String.contains (Parse.grammar_name path) '-')

let a_grammar_name_drops_the_prefix_and_the_extension name =
  String.equal (Parse.grammar_name ("packs/tree-sitter-" ^ name ^ ".wasm")) name

(* The module below exports "tree_sitter_a\000b". Before the reader
   refused such a name, "sinter parse" gave the person who ran it the
   message of the bridge, which names a function of the library. The
   property "a name from a wasm module can name a grammar" found it.
   The reader now gives None, the caller falls back to the file name,
   and the failure is one that names the file. *)
let refuses_a_module_that_names_itself_with_a_nul_byte () =
  let wasm = Generators.wasm_module ~before:false ~name:"a\000b" in
  Alcotest.(check (option string))
    "a name with a NUL byte is no name" None (Parse.name_of_wasm wasm);
  let path = Filename.temp_file "sinter-parse" ".wasm" in
  let message =
    Fun.protect
      ~finally:(fun () -> Sys.remove path)
      (fun () ->
        let channel = open_out_bin path in
        Fun.protect
          ~finally:(fun () -> close_out_noerr channel)
          (fun () -> output_string channel wasm);
        try
          Parse.run ~grammar:path ~query:None ~paths:[ sample ] stdout;
          "no failure"
        with Parse.Error message -> message)
  in
  Alcotest.(check bool)
    "the message names the grammar file" true
    (String.starts_with ~prefix:path message)

let properties =
  [
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
      ~print:Generators.print_source_and_capture
      source_and_capture_with_a_bad_string
      a_record_of_a_capture_with_a_bad_string_is_refused;
    property ~count:200 ~name:"the records of a file agree with the source"
      ~print:Fun.id Generators.json_source
      the_records_of_a_file_agree_with_the_source;
    property ~count:200 ~name:"the tree of a file is the tree of its text"
      ~print:Fun.id Generators.json_source
      the_tree_of_a_file_is_the_tree_of_its_text;
    property ~name:"the reader of a wasm module answers for any bytes"
      ~print:String.escaped Generators.wasm_bytes
      the_reader_of_a_module_answers_for_any_bytes;
    property ~name:"the reader of a wasm module finds a generated export"
      ~print:(fun (name, wasm) -> name ^ " " ^ String.escaped wasm)
      Generators.wasm_module_with_a_name
      the_reader_of_a_module_finds_a_generated_export;
    property ~name:"a name from a wasm module can name a grammar"
      ~print:String.escaped Generators.wasm_bytes
      a_name_from_a_module_can_name_a_grammar;
    property ~name:"a module that names itself with a NUL byte has no name"
      ~print:String.escaped Generators.wasm_module_whose_name_holds_a_nul
      a_name_from_a_module_can_name_a_grammar;
    property ~name:"a grammar name comes back for any file name"
      ~print:String.escaped Generators.grammar_file_path
      a_grammar_name_comes_back_for_any_file_name;
    property ~name:"a grammar name holds no hyphen" ~print:String.escaped
      Generators.grammar_file_path a_grammar_name_holds_no_hyphen;
    property ~name:"a grammar name drops the prefix and the extension"
      ~print:Fun.id Generators.grammar_export_name
      a_grammar_name_drops_the_prefix_and_the_extension;
  ]

(* An engine that the caller owns, with the grammar of the fixture
   loaded into it. This is the way the serve mode uses Parse. *)
let with_language f =
  let engine = Sinter_bridge.create () in
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.close engine)
    (fun () -> f (Parse.load engine ~grammar))

let folds_one_tree_over_each_file () =
  let items =
    with_language (fun language ->
        let seen = ref [] in
        Parse.fold language ~query:None ~paths:[ sample; sample ]
          ~f:(fun item -> seen := item :: !seen);
        List.rev !seen)
  in
  Alcotest.(check int) "one item for each file" 2 (List.length items);
  List.iter
    (function
      | Parse.Tree { path; sexp } ->
          Alcotest.(check string) "the item names its file" sample path;
          Alcotest.(check bool)
            "the item holds the parse tree" true
            (String.starts_with ~prefix:"(document" sexp)
      | Parse.Capture _ -> Alcotest.fail "a fold with no query gave a capture")
    items

let folds_the_captures_of_the_query () =
  let items =
    with_language (fun language ->
        let seen = ref [] in
        Parse.fold language ~query:(Some query) ~paths:[ sample ]
          ~f:(fun item -> seen := item :: !seen);
        List.rev !seen)
  in
  Alcotest.(check int) "six captures of the fixture" 6 (List.length items);
  List.iter
    (function
      | Parse.Capture record ->
          Alcotest.(check bool)
            "the record names the file it comes from" true
            (List.assoc_opt "path" record = Some (Jsonl.string sample))
      | Parse.Tree _ -> Alcotest.fail "a fold with a query gave a tree")
    items

(* The lines of an output, without the empty piece that follows the
   last line feed. *)
let output_lines text =
  let pieces = String.split_on_char '\n' text in
  match List.rev pieces with "" :: rest -> List.rev rest | _ -> pieces

(* The lines that one run of the one-shot command wrote, and its
   outcome. A run that fails keeps the lines it wrote first. *)
let command_output ~query ~paths =
  let file = Filename.temp_file "sinter-parse" ".out" in
  let channel = open_out_bin file in
  Fun.protect
    ~finally:(fun () -> Sys.remove file)
    (fun () ->
      let outcome =
        match Parse.run ~grammar ~query ~paths channel with
        | () -> Ok ()
        | exception Parse.Error message -> Error message
      in
      close_out_noerr channel;
      let channel = open_in_bin file in
      let text =
        Fun.protect
          ~finally:(fun () -> close_in_noerr channel)
          (fun () -> really_input_string channel (in_channel_length channel))
      in
      (output_lines text, outcome))

(* One state for the whole property. It holds the engine and the
   grammar, so the property also exercises the cache. The collector
   frees the engine when the test binary ends. *)
let state = lazy (Serve.create ())

let request ~query ~paths ~tag =
  let files = String.concat "," (List.map (Printf.sprintf "%S") paths) in
  let selection =
    match query with
    | None -> {|"tree":true|}
    | Some path -> Printf.sprintf {|"query":%S|} path
  in
  Printf.sprintf {|{"rid":%s,"op":"parse","grammar":%S,%s,"files":[%s]}|} tag
    grammar selection files

(* The value that the rid field of every answer line must hold. The
   tag is the JSON text of the rid of the request. *)
let value_of_tag tag =
  if String.length tag > 0 && tag.[0] = '"' then
    Jsonl.string (String.sub tag 1 (String.length tag - 2))
  else Jsonl.int (int_of_string tag)

let sources =
  [
    sample;
    "fixtures/sample.scm";
    "no-such-file.json";
    "fixtures/tree-sitter-json/tree-sitter-json.wasm";
  ]

let arguments =
  QCheck2.Gen.(
    triple
      (list_size (int_range 1 3) (oneof_list sources))
      bool
      (oneof_list [ "0"; "17"; {|"a"|}; {|"a tag"|} ]))

let print_arguments (paths, with_query, tag) =
  Printf.sprintf "%s, %s, rid %s" (String.concat " " paths)
    (if with_query then "a query" else "a tree")
    tag

(* One answer line of the op against one line of the command. In the
   query case the two records are the same, apart from the tag. In the
   tree case the command writes the S-expression alone and the op
   writes it in a field beside the path of the file. *)
let same_capture ~tag record line =
  List.assoc_opt "rid" record = Some (value_of_tag tag)
  && String.equal (Jsonl.to_string (List.remove_assoc "rid" record)) line

let same_tree ~tag ~path record line =
  List.length record = 3
  && List.assoc_opt "rid" record = Some (value_of_tag tag)
  && List.assoc_opt "path" record = Some (Jsonl.string path)
  && List.assoc_opt "tree" record = Some (Jsonl.string line)

(* The op writes one tree for each file, in the order of the files, so
   a tree answer is a prefix of the files. *)
let rec same_trees ~tag records lines paths =
  match (records, lines, paths) with
  | [], [], _ -> true
  | record :: records, line :: lines, path :: paths ->
      same_tree ~tag ~path record line && same_trees ~tag records lines paths
  | _ -> false

let the_op_answers_with_the_lines_of_the_command =
  QCheck2.Test.make ~count:50 ~print:print_arguments
    ~name:"the parse op answers with the lines of the one-shot command"
    arguments (fun (paths, with_query, tag) ->
      let query = if with_query then Some query else None in
      let lines, outcome = command_output ~query ~paths in
      let response =
        Serve.respond (Lazy.force state) (request ~query ~paths ~tag)
      in
      let records = Serve.lines response in
      let last = List.length records - 1 in
      let items = List.filteri (fun index _ -> index < last) records in
      let same_control =
        match (outcome, Serve.control response) with
        | Ok (), Serve.Done 0 -> true
        | Error message, Serve.Failed (3, said) -> String.equal said message
        | _ -> false
      in
      let same_items =
        List.length items = List.length lines
        &&
        match query with
        | Some _ -> List.for_all2 (same_capture ~tag) items lines
        | None -> same_trees ~tag items lines paths
      in
      same_control && same_items)

let tests =
  [
    Alcotest.test_case "prints the captures of the fixture" `Quick
      prints_the_captures_of_the_fixture;
    Alcotest.test_case "prints the parse tree" `Quick prints_the_parse_tree;
    Alcotest.test_case "handles every file in order" `Quick
      handles_every_file_in_order;
    Alcotest.test_case "reports a file that is not UTF-8" `Quick
      reports_a_file_that_is_not_utf_8;
    Alcotest.test_case "reports a file whose first byte is not UTF-8" `Quick
      reports_a_file_whose_first_byte_is_not_utf_8;
    Alcotest.test_case "reports a file that does not exist" `Quick
      reports_a_file_that_does_not_exist;
    Alcotest.test_case "names the query file when the query fails" `Quick
      names_the_query_file_when_the_query_fails;
    Alcotest.test_case "reports an empty query file" `Quick
      reports_an_empty_query_file;
    Alcotest.test_case "a query file of one character is not empty" `Quick
      a_query_file_of_one_character_is_not_empty;
    Alcotest.test_case "ends a span on the line of its last byte" `Quick
      ends_a_span_on_the_line_of_its_last_byte;
    Alcotest.test_case "reports a channel that cannot be written" `Quick
      reports_a_channel_that_cannot_be_written;
    Alcotest.test_case "rejects a file name that is not UTF-8" `Quick
      rejects_a_file_name_that_is_not_utf_8;
    Alcotest.test_case "rejects a file name whose first byte is not UTF-8"
      `Quick rejects_a_file_name_whose_first_byte_is_not_utf_8;
    Alcotest.test_case "reads the grammar name from the module" `Quick
      reads_the_grammar_name_from_the_module;
    Alcotest.test_case "loads a grammar file under another name" `Quick
      loads_a_grammar_file_under_another_name;
    Alcotest.test_case "names a source that cannot be read" `Quick
      names_a_source_that_cannot_be_read;
    Alcotest.test_case "writes a tree that nests deeply" `Quick
      writes_a_tree_that_nests_deeply;
    Alcotest.test_case "names the grammar" `Quick names_the_grammar;
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
    Alcotest.test_case "refuses a module that names itself with a NUL byte"
      `Quick refuses_a_module_that_names_itself_with_a_nul_byte;
    Alcotest.test_case "gives no name that holds a NUL byte" `Quick
      gives_no_name_that_holds_a_nul_byte;
    Alcotest.test_case "gives no name for a module the reader cannot follow"
      `Quick gives_no_name_for_a_module_the_reader_cannot_follow;
    Alcotest.test_case "places the end of a capture that ends before byte two"
      `Quick places_the_end_of_a_capture_that_ends_before_byte_two;
    Alcotest.test_case "folds one tree over each file" `Quick
      folds_one_tree_over_each_file;
    Alcotest.test_case "folds the captures of the query" `Quick
      folds_the_captures_of_the_query;
    QCheck_alcotest.to_alcotest ~speed_level:`Quick
      the_op_answers_with_the_lines_of_the_command;
  ]
  @ properties
