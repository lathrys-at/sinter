(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

(* Dune runs the test in the build copy of test/, so the path below is
   relative to that directory. *)
let grammar = "fixtures/tree-sitter-json/tree-sitter-json.wasm"

(* One engine and one grammar for every test below. The language keeps
   its engine alive, and alcotest runs one test at a time. *)
let json =
  lazy
    (let wasm = Parse.read_file grammar in
     Sinter_bridge.load (Sinter_bridge.create ()) ~name:"json" ~wasm)

(* One pattern with one capture. The query cursor gives one capture
   per match, so the captures come in the order of the nodes. *)
let one_capture_query = "(string_content) @s"

let two_pattern_query =
  "(pair key: (string (string_content) @key) value: (_) @value)\n\
   (number) @number\n"

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let a_capture_is_a_byte_range_inside_the_source source =
  let found =
    Sinter_bridge.captures (Lazy.force json) ~source ~query:two_pattern_query
  in
  List.for_all
    (fun (capture : Sinter_bridge.capture) ->
      0 <= capture.start_byte
      && capture.start_byte <= capture.end_byte
      && capture.end_byte <= String.length source
      && String.equal capture.text
           (String.sub source capture.start_byte
              (capture.end_byte - capture.start_byte)))
    found

let a_row_and_a_column_agree_with_the_source source =
  let found =
    Sinter_bridge.captures (Lazy.force json) ~source ~query:two_pattern_query
  in
  List.for_all
    (fun (capture : Sinter_bridge.capture) ->
      capture.start_row = Generators.rows_before source capture.start_byte
      && capture.start_column
         = capture.start_byte
           - Generators.start_of_line source capture.start_byte
      && capture.end_row = Generators.rows_before source capture.end_byte
      && capture.end_column
         = capture.end_byte - Generators.start_of_line source capture.end_byte)
    found

let captures_come_in_the_order_of_the_cursor source =
  let found =
    Sinter_bridge.captures (Lazy.force json) ~source ~query:one_capture_query
  in
  let rec in_order = function
    | (first : Sinter_bridge.capture) :: (next :: _ as rest) ->
        first.start_byte <= next.start_byte && in_order rest
    | _ -> true
  in
  in_order found

let a_capture_name_belongs_to_the_query source =
  let found =
    Sinter_bridge.captures (Lazy.force json) ~source ~query:two_pattern_query
  in
  List.for_all
    (fun (capture : Sinter_bridge.capture) ->
      match capture.name with
      | "key" | "value" -> capture.pattern = 0
      | "number" -> capture.pattern = 1
      | _ -> false)
    found

let a_tree_comes_back_for_any_text source =
  let written = Sinter_bridge.tree (Lazy.force json) ~source in
  String.length written > 0 && written.[0] = '('

let rejects_an_empty_query () =
  Alcotest.check_raises "an empty query"
    (Invalid_argument "Sinter_bridge.captures: the query is empty") (fun () ->
      ignore (Sinter_bridge.captures (Lazy.force json) ~source:"[]" ~query:""))

let rejects_a_grammar_name_that_holds_a_nul_byte () =
  let engine = Sinter_bridge.create () in
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.close engine)
    (fun () ->
      Alcotest.check_raises "a NUL byte in the grammar name"
        (Invalid_argument
           "Sinter_bridge.load: the grammar name holds a NUL byte") (fun () ->
          ignore (Sinter_bridge.load engine ~name:"js\000on" ~wasm:"")))

let reports_a_query_that_does_not_compile () =
  let message =
    try
      ignore
        (Sinter_bridge.captures (Lazy.force json) ~source:"[]"
           ~query:"(no_such_node) @x");
      "no failure"
    with Sinter_bridge.Error message -> message
  in
  Alcotest.(check bool)
    "the message names the query" true
    (String.length message > 0 && message <> "no failure")

let reports_a_grammar_that_does_not_load () =
  let engine = Sinter_bridge.create () in
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.close engine)
    (fun () ->
      let failed =
        try
          ignore (Sinter_bridge.load engine ~name:"json" ~wasm:"not a module");
          false
        with Sinter_bridge.Error _ -> true
      in
      Alcotest.(check bool)
        "a grammar that is not wasm does not load" true failed)

(* The interface says that a call after {!Sinter_bridge.close} raises
   [Invalid_argument]. *)
let a_closed_engine_refuses_every_call () =
  let wasm = Parse.read_file grammar in
  let engine = Sinter_bridge.create () in
  let language = Sinter_bridge.load engine ~name:"json" ~wasm in
  Sinter_bridge.close engine;
  let closed = Invalid_argument "Sinter_bridge: the engine is closed" in
  Alcotest.check_raises "captures after close" closed (fun () ->
      ignore
        (Sinter_bridge.captures language ~source:"[1]" ~query:"(number) @n"));
  Alcotest.check_raises "tree after close" closed (fun () ->
      ignore (Sinter_bridge.tree language ~source:"[1]"));
  Alcotest.check_raises "load after close" closed (fun () ->
      ignore (Sinter_bridge.load engine ~name:"json" ~wasm));
  (* The interface says a program does not have to call close, so
     closing twice must not fault. *)
  Sinter_bridge.close engine

let tests =
  [
    property ~name:"a capture is a byte range inside the source" ~print:Fun.id
      Generators.json_source a_capture_is_a_byte_range_inside_the_source;
    property ~name:"a row and a column agree with the source" ~print:Fun.id
      Generators.json_source a_row_and_a_column_agree_with_the_source;
    property ~name:"a row and a column agree with any text" ~print:Fun.id
      Generators.any_text a_row_and_a_column_agree_with_the_source;
    property ~name:"captures come in the order of the cursor" ~print:Fun.id
      Generators.json_source captures_come_in_the_order_of_the_cursor;
    property ~name:"a capture name belongs to the query" ~print:Fun.id
      Generators.json_source a_capture_name_belongs_to_the_query;
    property ~name:"a tree comes back for a document" ~print:Fun.id
      Generators.json_source a_tree_comes_back_for_any_text;
    property ~name:"a tree comes back for any text" ~print:Fun.id
      Generators.any_text a_tree_comes_back_for_any_text;
    property ~name:"a capture is a byte range inside any text" ~print:Fun.id
      Generators.any_text a_capture_is_a_byte_range_inside_the_source;
    Alcotest.test_case "rejects an empty query" `Quick rejects_an_empty_query;
    Alcotest.test_case "rejects a grammar name that holds a NUL byte" `Quick
      rejects_a_grammar_name_that_holds_a_nul_byte;
    Alcotest.test_case "reports a query that does not compile" `Quick
      reports_a_query_that_does_not_compile;
    Alcotest.test_case "reports a grammar that does not load" `Quick
      reports_a_grammar_that_does_not_load;
    Alcotest.test_case "a closed engine refuses every call" `Quick
      a_closed_engine_refuses_every_call;
  ]
