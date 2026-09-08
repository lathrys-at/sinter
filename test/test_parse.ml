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
  Printf.sprintf {|{"id":%s,"op":"parse","grammar":%S,%s,"files":[%s]}|} tag
    grammar selection files

(* The value that the req field of every answer line must hold. The
   tag is the JSON text of the id of the request. *)
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
  Printf.sprintf "%s, %s, id %s" (String.concat " " paths)
    (if with_query then "a query" else "a tree")
    tag

(* One answer line of the op against one line of the command. In the
   query case the two records are the same, apart from the tag. In the
   tree case the command writes the S-expression alone and the op
   writes it in a field beside the path of the file. *)
let same_capture ~tag record line =
  List.assoc_opt "req" record = Some (value_of_tag tag)
  && String.equal (Jsonl.to_string (List.remove_assoc "req" record)) line

let same_tree ~tag ~path record line =
  List.length record = 3
  && List.assoc_opt "req" record = Some (value_of_tag tag)
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
    Alcotest.test_case "gives no name that holds a NUL byte" `Quick
      gives_no_name_that_holds_a_nul_byte;
    Alcotest.test_case "folds one tree over each file" `Quick
      folds_one_tree_over_each_file;
    Alcotest.test_case "folds the captures of the query" `Quick
      folds_the_captures_of_the_query;
    QCheck_alcotest.to_alcotest ~speed_level:`Quick
      the_op_answers_with_the_lines_of_the_command;
  ]
