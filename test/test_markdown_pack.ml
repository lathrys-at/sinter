(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let with_engine use =
  let engine = Sinter_bridge.create () in
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.close engine)
    (fun () -> use engine)

let with_grammar use =
  with_engine (fun engine ->
      match
        Sinter_bridge.Language.load engine ~name:"markdown"
          ~wasm:Markdown_pack.grammar
      with
      | Ok language -> use language
      | Error error -> Alcotest.fail (Sinter_bridge.Language.message error))

let grammar_is_the_release_file () =
  Alcotest.(check string)
    "the SHA-256 of the grammar"
    "dd9fc12ac2804d7c7da787e4774125b32e4fb3c244e5e7031a77cb7dd8036020"
    (Sha256.hex Markdown_pack.grammar)

let grammar_parses_markdown () =
  with_grammar (fun language ->
      match Sinter_bridge.Tree.parse language "# Title\n\nText.\n" with
      | Ok tree ->
          Alcotest.(check string)
            "the tree"
            "(document (section (atx_heading (atx_h1_marker) heading_content: \
             (inline)) (paragraph (inline))))"
            (Sinter_bridge.Tree.sexp tree)
      | Error error -> Alcotest.fail (Sinter_bridge.Tree.message error))

let query_captures_each_block () =
  with_grammar (fun language ->
      match Sinter_bridge.Query.compile language Markdown_pack.query with
      | Error error -> Alcotest.fail (Sinter_bridge.Query.message error)
      | Ok query -> (
          match
            Sinter_bridge.Tree.parse language
              "# Title\n\n- item\n\n> quote\n\n```\ncode\n```\n"
          with
          | Error error -> Alcotest.fail (Sinter_bridge.Tree.message error)
          | Ok tree -> (
              match Sinter_bridge.Query.run query tree with
              | Error error ->
                  Alcotest.fail (Sinter_bridge.Query.run_message error)
              | Ok captures ->
                  Alcotest.(check (list (pair string string)))
                    "the captures"
                    [
                      ("block", "section");
                      ("block", "atx_heading");
                      ("block", "list_item");
                      ("block", "paragraph");
                      ("block", "block_quote");
                      ("block", "paragraph");
                      ("block", "fenced_code_block");
                    ]
                    (List.map
                       (fun (capture : Sinter_bridge.Query.capture) ->
                         (capture.name, capture.node_type))
                       captures))))

let tests =
  [
    Alcotest.test_case "the grammar is the file of the release" `Quick
      grammar_is_the_release_file;
    Alcotest.test_case "the grammar parses markdown" `Quick
      grammar_parses_markdown;
    Alcotest.test_case "the query captures each block" `Quick
      query_captures_each_block;
  ]
