(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module B = Sinter_bridge

(* Dune runs the test in the build copy of test/, so the path below is
   relative to that directory. *)
let grammar = "fixtures/tree-sitter-json/tree-sitter-json.wasm"

let loaded () =
  match Grammar.load (B.create ()) ~path:grammar with
  | Ok language -> language
  | Error error -> Alcotest.fail (Grammar.message ~path:grammar error)

(* One grammar for every test below. The grammar keeps its engine
   alive. *)
let language = lazy (loaded ())

let in_a_file content use =
  let path = Filename.temp_file "sinter-query-file" ".txt" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      Out_channel.with_open_bin path (fun channel ->
          output_string channel content);
      use path)

let compile text =
  in_a_file text (fun path ->
      (path, Query_file.compile (Lazy.force language) ~path))

let message_of path = function
  | Ok _ -> "no failure"
  | Error error -> Query_file.message ~path error

let compiles_a_query_file () =
  let _, compiled = compile "(number) @n\n" in
  Alcotest.(check bool) "the query compiles" true (Result.is_ok compiled)

let refuses_a_query_file_of_white_space () =
  let path, compiled = compile " \n\t\n" in
  Alcotest.(check bool) "the error" true (compiled = Error Query_file.Empty);
  Alcotest.(check string)
    "the message"
    (path ^ ": the query file is empty")
    (message_of path compiled)

let refuses_a_query_file_that_is_not_utf_8 () =
  let path, compiled = compile "(number) @n\xff" in
  Alcotest.(check string)
    "the message names the byte"
    (path ^ ": the file is not UTF-8 text, at byte 11")
    (message_of path compiled)

let names_the_query_error () =
  let path, compiled = compile "(no_such_node) @x" in
  Alcotest.(check string)
    "the message of tree-sitter after the file"
    (path
   ^ ": cannot read the query: Query error at 1:2. Invalid node type \
      \"no_such_node\"")
    (message_of path compiled)

let query text =
  match compile text with
  | _, Ok query -> query
  | path, error -> Alcotest.fail (message_of path error)

let gives_the_text_and_the_captures_of_a_file () =
  let numbers = query "(number) @n" in
  in_a_file "[1, 22]" (fun path ->
      match Query_file.captures (Lazy.force language) numbers ~path with
      | Ok (source, found) ->
          Alcotest.(check string) "the text of the file" "[1, 22]" source;
          Alcotest.(check (list string))
            "the text of each capture" [ "1"; "22" ]
            (List.map (fun (c : B.Query.capture) -> c.text) found)
      | Error error -> Alcotest.fail (Query_file.message ~path error))

let refuses_a_source_that_is_not_utf_8 () =
  let numbers = query "(number) @n" in
  in_a_file "[\xff]" (fun path ->
      Alcotest.(check string)
        "the message names the byte"
        (path ^ ": the file is not UTF-8 text, at byte 1")
        (message_of path
           (Query_file.captures (Lazy.force language) numbers ~path)))

let refuses_a_query_of_another_grammar () =
  let numbers = query "(number) @n" in
  let other = loaded () in
  in_a_file "[1]" (fun path ->
      Alcotest.(check string)
        "the message names the file"
        (path ^ ": the query and the parse tree come from different grammars")
        (message_of path (Query_file.captures other numbers ~path)))

let gives_the_tree_of_a_file () =
  in_a_file "[1]" (fun path ->
      Alcotest.(check string)
        "the S-expression" "(document (array (number)))"
        (match Query_file.tree (Lazy.force language) ~path with
        | Ok sexp -> sexp
        | Error error -> Query_file.message ~path error))

let names_a_parse_that_gives_no_tree () =
  Alcotest.(check string)
    "the message names the file" "f.json: the grammar produced no parse tree"
    (Query_file.message ~path:"f.json"
       (Query_file.Not_parsed B.Tree.Did_not_finish))

let tests =
  [
    Alcotest.test_case "compiles a query file" `Quick compiles_a_query_file;
    Alcotest.test_case "refuses a query file of white space" `Quick
      refuses_a_query_file_of_white_space;
    Alcotest.test_case "refuses a query file that is not UTF-8" `Quick
      refuses_a_query_file_that_is_not_utf_8;
    Alcotest.test_case "names the query error" `Quick names_the_query_error;
    Alcotest.test_case "gives the text and the captures of a file" `Quick
      gives_the_text_and_the_captures_of_a_file;
    Alcotest.test_case "refuses a source that is not UTF-8" `Quick
      refuses_a_source_that_is_not_utf_8;
    Alcotest.test_case "refuses a query of another grammar" `Quick
      refuses_a_query_of_another_grammar;
    Alcotest.test_case "gives the tree of a file" `Quick
      gives_the_tree_of_a_file;
    Alcotest.test_case "names a parse that gives no tree" `Quick
      names_a_parse_that_gives_no_tree;
  ]
