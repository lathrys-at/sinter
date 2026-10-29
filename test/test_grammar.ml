(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let grammar = "fixtures/tree-sitter-json/tree-sitter-json.wasm"

let with_engine use =
  let engine = Sinter_bridge.create () in
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.close engine)
    (fun () -> use engine)

let in_a_file content use =
  let path = Filename.temp_file "sinter-grammar" ".wasm" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      Out_channel.with_open_bin path (fun channel ->
          output_string channel content);
      use path)

let loads_the_fixture_grammar () =
  with_engine (fun engine ->
      match Grammar.load engine ~path:grammar with
      | Ok language -> (
          match Sinter_bridge.Tree.parse language "[1]" with
          | Ok tree ->
              Alcotest.(check string)
                "the grammar parses" "(document (array (number)))"
                (Sinter_bridge.Tree.sexp tree)
          | Error _ -> Alcotest.fail "the grammar gave no tree")
      | Error error -> Alcotest.fail (Grammar.message ~path:grammar error))

let takes_the_name_from_the_module () =
  let wasm = In_channel.with_open_bin grammar In_channel.input_all in
  with_engine (fun engine ->
      in_a_file wasm (fun path ->
          Alcotest.(check bool)
            "the renamed file loads" true
            (Result.is_ok (Grammar.load engine ~path))))

let reports_a_file_that_does_not_read () =
  with_engine (fun engine ->
      match Grammar.load engine ~path:"no-such-grammar.wasm" with
      | Error (Grammar.Unreadable (Text_file.Cannot_open _) as error) ->
          Alcotest.(check string)
            "the message of the system"
            "no-such-grammar.wasm: No such file or directory"
            (Grammar.message ~path:"no-such-grammar.wasm" error)
      | _ -> Alcotest.fail "a file that does not exist gave a grammar")

let reports_a_grammar_that_does_not_load () =
  with_engine (fun engine ->
      in_a_file "not a module" (fun path ->
          match Grammar.load engine ~path with
          | Error
              (Grammar.Not_loaded
                 (Sinter_bridge.Language.Wasm
                    { kind = Sinter_bridge.Language.Parse; message }) as error)
            ->
              Alcotest.(check string)
                "the message names the file and the cause"
                (path ^ ": the grammar does not load: Failed to parse wasm: "
               ^ message)
                (Grammar.message ~path error)
          | _ -> Alcotest.fail "bytes that are not a module gave a grammar"))

let every_error_has_a_help () =
  List.iter
    (fun (name, error) ->
      Alcotest.(check bool)
        (name ^ " has a help") true
        (Grammar.help error <> ""))
    (List.map
       (fun (error : Grammar.error) ->
         ( (match error with
           | Grammar.Unreadable _ -> "Unreadable"
           | Grammar.Not_loaded _ -> "Not_loaded"),
           error ))
       [
         Grammar.Unreadable Text_file.Is_a_directory;
         Grammar.Not_loaded Sinter_bridge.Language.Name_not_utf_8;
       ])

let tests =
  [
    Alcotest.test_case "every error has a help" `Quick every_error_has_a_help;
    Alcotest.test_case "loads the fixture grammar" `Quick
      loads_the_fixture_grammar;
    Alcotest.test_case "takes the name from the module" `Quick
      takes_the_name_from_the_module;
    Alcotest.test_case "reports a file that does not read" `Quick
      reports_a_file_that_does_not_read;
    Alcotest.test_case "reports a grammar that does not load" `Quick
      reports_a_grammar_that_does_not_load;
  ]
