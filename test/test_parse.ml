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

let reports_a_file_that_is_not_utf_8 () =
  let file = Filename.temp_file "sinter-parse" ".json" in
  let channel = open_out_bin file in
  output_string channel "{\"a\": \"\xff\"}";
  close_out channel;
  let message =
    Fun.protect
      ~finally:(fun () -> Sys.remove file)
      (fun () ->
        try
          ignore (output ~query:(Some query) ~paths:[ file ]);
          "no failure"
        with Parse.Error message -> message)
  in
  Alcotest.(check bool)
    "the message says the file is not UTF-8" true
    (contains "is not UTF-8 text" message)

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

let rejects_a_file_name_that_is_not_utf_8 () =
  let message =
    try
      ignore (output ~query:(Some query) ~paths:[ "bad\xffname.json" ]);
      "no failure"
    with Parse.Error message -> message
  in
  Alcotest.(check bool)
    "the message says the file name is not UTF-8" true
    (contains "the file name is not UTF-8 text" message)

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
  Alcotest.(check bool)
    "the message names the directory and says what is wrong" true
    (String.starts_with ~prefix:".:" message && contains "directory" message)

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

let a_record_is_a_canonical_line (source, capture) =
  let line = Jsonl.to_string (record_of source capture) in
  String.length line > 1
  && line.[0] = '{'
  && line.[String.length line - 1] = '}'

(* The two properties below state that the function is total: it
   answers for every value of its argument type, and raises nothing. *)
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

let the_reader_of_a_module_answers_for_any_bytes wasm =
  ignore (Parse.name_of_wasm wasm);
  true

let the_reader_of_a_module_finds_a_generated_export (name, wasm) =
  Option.equal String.equal (Parse.name_of_wasm wasm) (Some name)

let a_grammar_name_comes_back_for_any_file_name path =
  ignore (Parse.grammar_name path);
  true

let a_grammar_name_holds_no_hyphen path =
  not (String.contains (Parse.grammar_name path) '-')

let a_grammar_name_drops_the_prefix_and_the_extension name =
  String.equal (Parse.grammar_name ("packs/tree-sitter-" ^ name ^ ".wasm")) name

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
    property ~name:"a record of a capture is a canonical line"
      ~print:Generators.print_source_and_capture Generators.source_and_capture
      a_record_is_a_canonical_line;
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
    property ~name:"a grammar name comes back for any file name"
      ~print:String.escaped Generators.grammar_file_path
      a_grammar_name_comes_back_for_any_file_name;
    property ~name:"a grammar name holds no hyphen" ~print:String.escaped
      Generators.grammar_file_path a_grammar_name_holds_no_hyphen;
    property ~name:"a grammar name drops the prefix and the extension"
      ~print:Fun.id Generators.grammar_export_name
      a_grammar_name_drops_the_prefix_and_the_extension;
  ]

let tests =
  [
    Alcotest.test_case "prints the captures of the fixture" `Quick
      prints_the_captures_of_the_fixture;
    Alcotest.test_case "prints the parse tree" `Quick prints_the_parse_tree;
    Alcotest.test_case "handles every file in order" `Quick
      handles_every_file_in_order;
    Alcotest.test_case "reports a file that is not UTF-8" `Quick
      reports_a_file_that_is_not_utf_8;
    Alcotest.test_case "reports a file that does not exist" `Quick
      reports_a_file_that_does_not_exist;
    Alcotest.test_case "names the query file when the query fails" `Quick
      names_the_query_file_when_the_query_fails;
    Alcotest.test_case "ends a span on the line of its last byte" `Quick
      ends_a_span_on_the_line_of_its_last_byte;
    Alcotest.test_case "reports a channel that cannot be written" `Quick
      reports_a_channel_that_cannot_be_written;
    Alcotest.test_case "rejects a file name that is not UTF-8" `Quick
      rejects_a_file_name_that_is_not_utf_8;
    Alcotest.test_case "reads the grammar name from the module" `Quick
      reads_the_grammar_name_from_the_module;
    Alcotest.test_case "loads a grammar file under another name" `Quick
      loads_a_grammar_file_under_another_name;
    Alcotest.test_case "names a source that cannot be read" `Quick
      names_a_source_that_cannot_be_read;
    Alcotest.test_case "writes a tree that nests deeply" `Quick
      writes_a_tree_that_nests_deeply;
    Alcotest.test_case "names the grammar" `Quick names_the_grammar;
  ]
  @ properties
