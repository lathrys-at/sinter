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

let names_the_grammar () =
  let check expected path =
    Alcotest.(check string) path expected (Parse.grammar_name path)
  in
  check "json" "test/fixtures/tree-sitter-json/tree-sitter-json.wasm";
  check "json" "tree-sitter-json.wasm";
  check "json" "json.wasm";
  check "type_script" "packs/tree-sitter-type-script.wasm"

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
    Alcotest.test_case "names the grammar" `Quick names_the_grammar;
  ]
