(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

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
        with Parse.Error { fault; _ } -> fault)
  in
  (file, message)

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

let reports_a_file_whose_last_byte_is_not_utf_8 () =
  let file, message = source_failure "{}\xff" in
  Alcotest.(check string)
    "the message names the last byte"
    (file ^ ": the file is not UTF-8 text, at byte 2")
    message

let reports_a_file_that_does_not_exist () =
  let message =
    try
      ignore (output ~query:(Some query) ~paths:[ "no-such-file.json" ]);
      "no failure"
    with Parse.Error { fault; _ } -> fault
  in
  Alcotest.(check string)
    "the message is the message of the system"
    "no-such-file.json: No such file or directory" message

let an_error_carries_the_help_of_its_kind () =
  let help paths =
    try
      ignore (output ~query:(Some query) ~paths);
      "no failure"
    with Parse.Error { help; place; _ } ->
      if place = None then help else "a place"
  in
  Alcotest.(check (list string))
    "a missing file, and a name that is not UTF-8"
    [
      Query_file.help (Query_file.Unreadable Text_file.Is_a_directory);
      Parse_record.help Parse_record.Path_not_utf_8;
    ]
    [ help [ "no-such-file.json" ]; help [ "\xff.json" ] ]

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
        with Parse.Error { fault; _ } -> fault)
  in
  Alcotest.(check bool)
    "the message names the query file, not the source file" true
    (String.starts_with ~prefix:file message)

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
        with Parse.Error { fault; _ } -> fault)
  in
  Alcotest.(check string)
    "the message names the query file"
    (file ^ ": the query file is empty")
    message

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
        with Parse.Error { fault; _ } -> fault)
  in
  Alcotest.(check string)
    "the run writes no line and gives no failure" "" written

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
        with Parse.Error { fault; _ } -> fault)
  in
  Alcotest.(check bool)
    "the message says the output cannot be written" true
    (contains "cannot write the output" message)

let name_failure path =
  try
    ignore (output ~query:(Some query) ~paths:[ path ]);
    "no failure"
  with Parse.Error { fault; _ } -> fault

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

let loads_a_grammar_file_under_another_name () =
  let renamed = Filename.temp_file "grammar" ".wasm" in
  let wasm = In_channel.with_open_bin grammar In_channel.input_all in
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
    with Parse.Error { fault; _ } -> fault
  in
  Alcotest.(check string)
    "the message names the directory and says what is wrong" ".: is a directory"
    message

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

let language =
  lazy
    (match Grammar.load (Sinter_bridge.create ()) ~path:grammar with
    | Ok language -> language
    | Error error -> Alcotest.fail (Grammar.message ~path:grammar error))

let spanning_query =
  "(document) @d\n\
   (object) @o\n\
   (array) @a\n\
   (pair) @p\n\
   (string) @s\n\
   (string_content) @c\n\
   (number) @n\n"

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

let items_of ~query path =
  let seen = ref [] in
  Parse.fold (Lazy.force language) ~query ~paths:[ path ] ~f:(fun item ->
      seen := item :: !seen);
  List.rev !seen

let records_of source =
  in_a_file spanning_query (fun query ->
      in_a_file source (fun path ->
          ( path,
            List.filter_map
              (function
                | Parse.Capture record -> Some record | Parse.Tree _ -> None)
              (items_of ~query:(Some query) path) )))

let the_tree_of_a_file_is_the_tree_of_its_text document =
  let source = document ^ "\n" in
  let expected =
    match Sinter_bridge.Tree.parse (Lazy.force language) source with
    | Ok tree -> Sinter_bridge.Tree.sexp tree
    | Error error -> Alcotest.fail (Sinter_bridge.Tree.message error)
  in
  match in_a_file source (items_of ~query:None) with
  | [ Parse.Tree { sexp; _ } ] -> String.equal sexp expected
  | _ -> false

let the_records_of_a_file_agree_with_the_source document =
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

let refuses_a_module_that_names_itself_with_a_nul_byte () =
  let wasm = Generators.wasm_module Generators.One_export ~name:"a\000b" in
  Alcotest.(check (option string))
    "a name with a NUL byte is no name" None
    (Grammar_name.of_wasm wasm);
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
        with Parse.Error { fault; _ } -> fault)
  in
  Alcotest.(check bool)
    "the message names the grammar file" true
    (String.starts_with ~prefix:path message)

let properties =
  [
    property ~count:200 ~name:"the records of a file agree with the source"
      ~print:Fun.id Generators.json_source
      the_records_of_a_file_agree_with_the_source;
    property ~count:200 ~name:"the tree of a file is the tree of its text"
      ~print:Fun.id Generators.json_source
      the_tree_of_a_file_is_the_tree_of_its_text;
  ]

let with_language f =
  let engine = Sinter_bridge.create () in
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.close engine)
    (fun () ->
      match Grammar.load engine ~path:grammar with
      | Ok language -> f language
      | Error error -> Alcotest.fail (Grammar.message ~path:grammar error))

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

let fold_checks_every_file_name_first () =
  let outcome query =
    with_language (fun language ->
        let items = ref 0 in
        let message =
          try
            Parse.fold language ~query ~paths:[ sample; "\xffnope.json" ]
              ~f:(fun _ -> incr items);
            "no failure"
          with Parse.Error { fault; _ } -> fault
        in
        (!items, message))
  in
  let failure = (0, "the file name is not UTF-8 text: \\255nope.json") in
  let outcome_t = Alcotest.(pair int string) in
  Alcotest.check outcome_t "no tree of the good file, then the name fails"
    failure (outcome None);
  Alcotest.check outcome_t "no capture of the good file, then the name fails"
    failure (outcome (Some query))

let output_lines text =
  let pieces = String.split_on_char '\n' text in
  match List.rev pieces with "" :: rest -> List.rev rest | _ -> pieces

let command_output ~query ~paths =
  let file = Filename.temp_file "sinter-parse" ".out" in
  let channel = open_out_bin file in
  Fun.protect
    ~finally:(fun () -> Sys.remove file)
    (fun () ->
      let outcome =
        match Parse.run ~grammar ~query ~paths channel with
        | () -> Ok ()
        | exception Parse.Error { fault; _ } -> Error fault
      in
      close_out_noerr channel;
      let channel = open_in_bin file in
      let text =
        Fun.protect
          ~finally:(fun () -> close_in_noerr channel)
          (fun () -> really_input_string channel (in_channel_length channel))
      in
      (output_lines text, outcome))

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

let same_capture ~tag record line =
  List.assoc_opt "rid" record = Some (value_of_tag tag)
  && String.equal (Jsonl.to_string (List.remove_assoc "rid" record)) line

let same_tree ~tag ~path record line =
  List.length record = 3
  && List.assoc_opt "rid" record = Some (value_of_tag tag)
  && List.assoc_opt "path" record = Some (Jsonl.string path)
  && List.assoc_opt "tree" record = Some (Jsonl.string line)

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

let names_the_grammar_before_a_bad_file_name () =
  let file = Filename.temp_file "sinter-parse" ".out" in
  let channel = open_out_bin file in
  let message =
    Fun.protect
      ~finally:(fun () ->
        close_out_noerr channel;
        Sys.remove file)
      (fun () ->
        try
          Parse.run ~grammar:"no-such-grammar.wasm" ~query:None
            ~paths:[ "\xffname.json" ] channel;
          "no failure"
        with Parse.Error { fault; _ } -> fault)
  in
  Alcotest.(check bool)
    "the message names the grammar file" true
    (String.starts_with ~prefix:"no-such-grammar.wasm:" message)

let tests =
  [
    Alcotest.test_case "an error carries the help of its kind" `Quick
      an_error_carries_the_help_of_its_kind;
    Alcotest.test_case "prints the captures of the fixture" `Quick
      prints_the_captures_of_the_fixture;
    Alcotest.test_case "prints the parse tree" `Quick prints_the_parse_tree;
    Alcotest.test_case "handles every file in order" `Quick
      handles_every_file_in_order;
    Alcotest.test_case "reports a file that is not UTF-8" `Quick
      reports_a_file_that_is_not_utf_8;
    Alcotest.test_case "reports a file whose first byte is not UTF-8" `Quick
      reports_a_file_whose_first_byte_is_not_utf_8;
    Alcotest.test_case "reports a file whose last byte is not UTF-8" `Quick
      reports_a_file_whose_last_byte_is_not_utf_8;
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
    Alcotest.test_case "names the grammar before a bad file name" `Quick
      names_the_grammar_before_a_bad_file_name;
    Alcotest.test_case "rejects a file name whose first byte is not UTF-8"
      `Quick rejects_a_file_name_whose_first_byte_is_not_utf_8;
    Alcotest.test_case "loads a grammar file under another name" `Quick
      loads_a_grammar_file_under_another_name;
    Alcotest.test_case "names a source that cannot be read" `Quick
      names_a_source_that_cannot_be_read;
    Alcotest.test_case "writes a tree that nests deeply" `Quick
      writes_a_tree_that_nests_deeply;
    Alcotest.test_case "refuses a module that names itself with a NUL byte"
      `Quick refuses_a_module_that_names_itself_with_a_nul_byte;
    Alcotest.test_case "folds one tree over each file" `Quick
      folds_one_tree_over_each_file;
    Alcotest.test_case "folds the captures of the query" `Quick
      folds_the_captures_of_the_query;
    Alcotest.test_case "fold checks every file name first" `Quick
      fold_checks_every_file_name_first;
    QCheck_alcotest.to_alcotest ~speed_level:`Quick
      the_op_answers_with_the_lines_of_the_command;
  ]
  @ properties
