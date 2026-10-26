(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* Dune runs the test in the build copy of test/, so the path below is
   relative to that directory. *)
let grammar = "fixtures/tree-sitter-json/tree-sitter-json.wasm"

(* One pattern with one capture. The query gives one capture per match,
   so the captures come in the order of the nodes. *)
let one_capture_query = "(string_content) @s"

let two_pattern_query =
  "(pair key: (string (string_content) @key) value: (_) @value)\n\
   (number) @number\n"

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

(* The digest needs no engine. *)
let sha256_gives_the_32_bytes_of_the_digest () =
  Alcotest.(check string)
    "the digest of the empty string"
    "\xe3\xb0\xc4\x42\x98\xfc\x1c\x14\x9a\xfb\xf4\xc8\x99\x6f\xb9\x24\x27\xae\x41\xe4\x64\x9b\x93\x4c\xa4\x95\x99\x1b\x78\x52\xb8\x55"
    (Sinter_bridge.sha256 "")

(* The handles of bridge version 2. *)

module B = Sinter_bridge

let wasm = lazy (In_channel.with_open_bin grammar In_channel.input_all)

let loaded engine =
  match B.Language.load engine ~name:"json" ~wasm:(Lazy.force wasm) with
  | Ok language -> language
  | Error error -> Alcotest.fail (B.Language.message error)

(* One engine and one grammar for the properties below. The grammar
   keeps its engine alive. *)
let language = lazy (loaded (B.create ()))

let parsed ?(language = language) text =
  match B.Tree.parse (Lazy.force language) text with
  | Ok tree -> tree
  | Error error -> Alcotest.fail (B.Tree.message error)

let compiled ?(language = language) text =
  match B.Query.compile (Lazy.force language) text with
  | Ok query -> query
  | Error error -> Alcotest.fail (B.Query.message error)

let captures_of query tree =
  match B.Query.run query tree with
  | Ok captures -> captures
  | Error error -> Alcotest.fail (B.Query.run_message error)

let two_patterns = lazy (compiled two_pattern_query)

let run_over source =
  let tree = parsed source in
  Fun.protect
    ~finally:(fun () -> B.Tree.close tree)
    (fun () -> captures_of (Lazy.force two_patterns) tree)

let inside source (range : B.range) =
  0 <= range.start_byte
  && range.start_byte <= range.end_byte
  && range.end_byte <= String.length source

let a_range_agrees_with_the_source source (range : B.range) =
  inside source range
  && range.start_row = Generators.rows_before source range.start_byte
  && range.start_column
     = range.start_byte - Generators.start_of_line source range.start_byte
  && range.end_row = Generators.rows_before source range.end_byte
  && range.end_column
     = range.end_byte - Generators.start_of_line source range.end_byte

let a_capture_holds_the_bytes_of_its_range source =
  List.for_all
    (fun (capture : B.Query.capture) ->
      a_range_agrees_with_the_source source capture.range
      && String.equal capture.text
           (String.sub source capture.range.start_byte
              (capture.range.end_byte - capture.range.start_byte)))
    (run_over source)

(* The first match is number 0, and each capture has the number of the
   capture before it or the next number. *)
let match_numbers_have_no_gap source =
  let rec walk expected = function
    | [] -> true
    | (capture : B.Query.capture) :: rest ->
        (capture.match_number = expected || capture.match_number = expected + 1)
        && walk capture.match_number rest
  in
  match run_over source with
  | [] -> true
  | first :: rest -> first.match_number = 0 && walk 0 rest

(* The captures of one match come from one pattern, and the capture
   names belong to that pattern. *)
let the_captures_of_a_match_share_a_pattern source =
  let rec walk = function
    | (a : B.Query.capture) :: (b :: _ as rest) ->
        (a.match_number <> b.match_number || a.pattern = b.pattern) && walk rest
    | _ -> true
  in
  let found = run_over source in
  walk found
  && List.for_all
       (fun (capture : B.Query.capture) ->
         match capture.name with
         | "key" | "value" -> capture.pattern = 0
         | "number" -> capture.pattern = 1
         | _ -> false)
       found

let report_of source =
  let tree = parsed source in
  Fun.protect
    ~finally:(fun () -> B.Tree.close tree)
    (fun () -> B.Tree.errors tree)

let a_document_has_no_parse_failure source =
  report_of source = { B.Tree.has_error = false; errors = []; lowest = None }

(* The error nodes come in the order of the text, no node holds the
   node after it, and each lies inside the text. The lowest node is
   there exactly when the flag is set, and the flag is set when an
   error node shows. *)
let a_report_agrees_with_its_text source =
  let report = report_of source in
  let rec ordered = function
    | (_, (a : B.Tree.node)) :: ((_, (b : B.Tree.node)) :: _ as rest) ->
        a.range.end_byte <= b.range.start_byte && ordered rest
    | _ -> true
  in
  ordered report.errors
  && List.for_all
       (fun (kind, (node : B.Tree.node)) ->
         a_range_agrees_with_the_source source node.range
         && (kind = B.Tree.Missing_node || String.equal node.node_type "ERROR"))
       report.errors
  && Option.is_some report.lowest = report.has_error
  && (report.errors = [] || report.has_error)
  && Option.fold ~none:true
       ~some:(fun (node : B.Tree.node) ->
         a_range_agrees_with_the_source source node.range)
       report.lowest

let a_sexp_comes_back_for_any_bytes source =
  let tree = parsed source in
  Fun.protect
    ~finally:(fun () -> B.Tree.close tree)
    (fun () ->
      let written = B.Tree.sexp tree in
      String.length written > 0 && written.[0] = '(')

let range start_byte end_byte =
  {
    B.start_byte;
    end_byte;
    start_row = 0;
    start_column = start_byte;
    end_row = 0;
    end_column = end_byte;
  }

let report_t =
  Alcotest.testable
    (fun formatter (report : B.Tree.report) ->
      Format.fprintf formatter "{has_error=%b; %d errors; lowest=%s}"
        report.has_error
        (List.length report.errors)
        (match report.lowest with None -> "None" | Some n -> n.node_type))
    ( = )

let reports_a_missing_node () =
  let node = { B.Tree.node_type = "]"; range = range 2 2 } in
  Alcotest.check report_t "the missing bracket at byte 2"
    {
      has_error = true;
      errors = [ (B.Tree.Missing_node, node) ];
      lowest = Some node;
    }
    (report_of "[1")

let reports_an_error_node () =
  let node = { B.Tree.node_type = "ERROR"; range = range 2 3 } in
  Alcotest.check report_t "the extra comma at byte 2"
    {
      has_error = true;
      errors = [ (B.Tree.Error_node, node) ];
      lowest = Some node;
    }
    (report_of "[1,,2]")

let reports_a_clean_tree () =
  Alcotest.check report_t "no failure"
    { has_error = false; errors = []; lowest = None }
    (report_of "[1]")

let error_t =
  Alcotest.testable
    (fun formatter error ->
      Format.pp_print_string formatter (B.Query.message error))
    ( = )

let compile_error text =
  match B.Query.compile (Lazy.force language) text with
  | Ok _ -> Alcotest.fail "the query compiled"
  | Error error -> error

let gives_the_kind_and_the_place_of_a_query_error () =
  let error = compile_error "(no_such_node) @x" in
  Alcotest.check error_t "a node type that the grammar has not"
    (B.Query.Invalid
       {
         kind = B.Query.Node_type;
         row = 0;
         column = 1;
         offset = 1;
         message = "\"no_such_node\"";
       })
    error;
  Alcotest.(check string)
    "the message of tree-sitter"
    "Query error at 1:2. Invalid node type \"no_such_node\""
    (B.Query.message error)

let refuses_a_directive () =
  let error =
    compile_error "(number) @n\n\n  ((string) @s (#set! kind \"x\"))"
  in
  Alcotest.check error_t "the directive and the start of its pattern"
    (B.Query.Not_allowed
       { operator = "set!"; pattern = 1; offset = 15; row = 2; column = 2 })
    error;
  Alcotest.(check string)
    "the message names the place and the operator"
    "Query error at 3:3. A query cannot use #set!. It can use only the \
     predicates #eq?, #not-eq?, #any-eq?, #any-not-eq?, #match?, #not-match?, \
     #any-match?, #any-not-match?, #any-of?, and #not-any-of?"
    (B.Query.message error)

let refuses_each_predicate_outside_the_ten () =
  List.iter
    (fun operator ->
      match
        compile_error (Printf.sprintf "((string) @s (#%s @s \"x\"))" operator)
      with
      | B.Query.Not_allowed found ->
          Alcotest.(check string) operator operator found.operator
      | other -> Alcotest.fail (B.Query.message other))
    [ "is?"; "is-not?"; "lua-match?"; "foo?"; "select-adjacent!"; "strip!" ]

let refuses_a_predicate_whose_name_ends_in_neither_mark () =
  Alcotest.check error_t "a syntax error at the name"
    (B.Query.Invalid
       {
         kind = B.Query.Syntax;
         row = 0;
         column = 17;
         offset = 17;
         message = "((string) @s (#eq @s \"x\"))\n                 ^";
       })
    (compile_error "((string) @s (#eq @s \"x\"))")

let compiles_each_of_the_ten_predicates () =
  List.iter
    (fun predicate ->
      let text = Printf.sprintf "((string) @s (#%s @s \"a\"))" predicate in
      B.Query.close (compiled text))
    [
      "eq?";
      "not-eq?";
      "any-eq?";
      "any-not-eq?";
      "match?";
      "not-match?";
      "any-match?";
      "any-not-match?";
      "any-of?";
      "not-any-of?";
    ]

let refuses_a_query_that_is_not_utf_8 () =
  Alcotest.check error_t "the offset of the bad byte" (B.Query.Not_utf_8 3)
    (compile_error "(a)\xff")

let an_empty_query_captures_nothing () =
  let query = compiled "" in
  Alcotest.(check int)
    "no capture" 0
    (List.length (captures_of query (parsed "[1, 2]")))

let numbers_the_matches_of_a_query () =
  let query =
    compiled "(pair key: (string) @k value: (_) @v)\n(number) @n\n(array)\n"
  in
  let found = captures_of query (parsed "{\"a\": 1, \"b\": [2, 3]}") in
  Alcotest.(check (list (triple int int string)))
    "the match, the pattern, and the name of each capture"
    [
      (0, 0, "k");
      (0, 0, "v");
      (1, 1, "n");
      (2, 0, "k");
      (2, 0, "v");
      (3, 1, "n");
      (4, 1, "n");
    ]
    (List.map
       (fun (c : B.Query.capture) -> (c.match_number, c.pattern, c.name))
       found)

let a_supertype_with_a_subtype_captures_the_subtype () =
  let query = compiled "(_value/object) @o" in
  let found = captures_of query (parsed "[{}, 1, {\"a\": {}}, \"b\"]") in
  Alcotest.(check (list (pair string string)))
    "the type and the text of each object"
    [ ("object", "{}"); ("object", "{\"a\": {}}"); ("object", "{}") ]
    (List.map (fun (c : B.Query.capture) -> (c.node_type, c.text)) found)

let refuses_a_query_over_a_tree_of_another_grammar () =
  let other = lazy (loaded (B.create ())) in
  let tree = parsed ~language:other "[1]" in
  Alcotest.(check bool)
    "the query and the tree come from two loads" true
    (B.Query.run (Lazy.force two_patterns) tree
    = Error B.Query.Language_mismatch)

let names_each_grammar_error () =
  let engine = B.create () in
  Fun.protect
    ~finally:(fun () -> B.close engine)
    (fun () ->
      (match B.Language.load engine ~name:"json" ~wasm:"not a module" with
      | Error (B.Language.Wasm { kind = B.Language.Parse; message }) ->
          Alcotest.(check string)
            "the message of tree-sitter"
            ("Failed to parse wasm: " ^ message)
            (B.Language.message
               (B.Language.Wasm { kind = B.Language.Parse; message }))
      | _ -> Alcotest.fail "bytes that are not a module loaded");
      (match B.Language.load engine ~name:"nojson" ~wasm:(Lazy.force wasm) with
      | Error (B.Language.Wasm { kind = B.Language.Instantiate; _ }) -> ()
      | _ -> Alcotest.fail "a grammar loaded under a name it does not export");
      Alcotest.(check bool)
        "a name that is not UTF-8" true
        (B.Language.load engine ~name:"\xff" ~wasm:(Lazy.force wasm)
        = Error B.Language.Name_not_utf_8);
      Alcotest.check_raises "a name that holds a NUL byte"
        (Invalid_argument
           "Sinter_bridge.Language.load: the grammar name holds a NUL byte")
        (fun () -> ignore (B.Language.load engine ~name:"js\000on" ~wasm:"")))

let gives_a_message_for_each_error () =
  let check expected message =
    Alcotest.(check string) expected expected message
  in
  let wasm kind =
    B.Language.message (B.Language.Wasm { kind; message = "m" })
  in
  check "Failed to compile wasm: m" (wasm B.Language.Compile);
  check "Failed to instantiate wasm module: m" (wasm B.Language.Instantiate);
  check "Unknown error: m" (wasm B.Language.Other);
  check "Incompatible language version 12. Expected minimum 13, maximum 15"
    (B.Language.message (B.Language.Version 12));
  check "the grammar name is not valid UTF-8"
    (B.Language.message B.Language.Name_not_utf_8);
  check "the grammar produced no parse tree"
    (B.Tree.message B.Tree.Did_not_finish);
  check
    "the source text is 4 GiB or more, and the result buffer holds no offset \
     that large"
    (B.Tree.message B.Tree.Too_long);
  let query kind =
    B.Query.message
      (B.Query.Invalid { kind; row = 1; column = 2; offset = 9; message = "m" })
  in
  check "Query error at 2:3. Invalid syntax:\nm" (query B.Query.Syntax);
  check "Query error at 2:3. Invalid field name m" (query B.Query.Field);
  check "Query error at 2:3. Invalid capture name m" (query B.Query.Capture);
  check "Query error at 2:3. Invalid predicate: m" (query B.Query.Predicate);
  check "Query error at 2:3. Impossible pattern:\nm" (query B.Query.Structure);
  check "m" (query B.Query.Language);
  check "the query is not UTF-8 text, at byte 4"
    (B.Query.message (B.Query.Not_utf_8 4));
  check "the query and the parse tree come from different grammars"
    (B.Query.run_message B.Query.Language_mismatch)

(* Each handle owns what it needs: a tree and a query outlive their
   grammar and their engine. *)
let a_tree_and_a_query_outlive_their_grammar () =
  let engine = B.create () in
  let language = loaded engine in
  let query = compiled ~language:(lazy language) "(number) @n" in
  let tree = parsed ~language:(lazy language) "[1, 2]" in
  B.Language.close language;
  B.close engine;
  Alcotest.(check int) "two numbers" 2 (List.length (captures_of query tree));
  Alcotest.(check string)
    "the tree" "(document (array (number) (number)))" (B.Tree.sexp tree)

let every_handle_refuses_a_call_after_close () =
  let engine = B.create () in
  let language = loaded engine in
  let query = compiled ~language:(lazy language) "(number) @n" in
  let tree = parsed ~language:(lazy language) "[1]" in
  B.Tree.close tree;
  B.Query.close query;
  let closed what =
    Invalid_argument ("Sinter_bridge: the " ^ what ^ " is closed")
  in
  Alcotest.check_raises "sexp" (closed "tree") (fun () ->
      ignore (B.Tree.sexp tree));
  Alcotest.check_raises "errors" (closed "tree") (fun () ->
      ignore (B.Tree.errors tree));
  Alcotest.check_raises "run" (closed "query") (fun () ->
      ignore (B.Query.run query tree));
  let open_query = compiled ~language:(lazy language) "(number) @n" in
  Alcotest.check_raises "run over a closed tree" (closed "tree") (fun () ->
      ignore (B.Query.run open_query tree));
  B.close engine;
  Alcotest.check_raises "load with a closed engine" (closed "engine") (fun () ->
      ignore (B.Language.load engine ~name:"json" ~wasm:(Lazy.force wasm)));
  Alcotest.check_raises "parse with a closed engine" (closed "engine")
    (fun () -> ignore (B.Tree.parse language "[1]"));
  B.Language.close language;
  Alcotest.check_raises "compile with a closed grammar" (closed "language")
    (fun () -> ignore (B.Query.compile language "(number) @n"));
  (* A second close of each handle does nothing. *)
  B.Tree.close tree;
  B.Query.close query;
  B.Language.close language;
  B.close engine

(* The collector frees each handle that no value refers to, and a
   handle that was closed is not freed again. *)
let the_collector_frees_every_handle () =
  for index = 1 to 6 do
    let engine = B.create () in
    let language = loaded engine in
    let query = compiled ~language:(lazy language) "(number) @n" in
    let tree = parsed ~language:(lazy language) "[1]" in
    if index mod 2 = 0 then (
      B.Tree.close tree;
      B.Query.close query;
      B.Language.close language;
      B.close engine)
  done;
  Gc.full_major ();
  Gc.full_major ();
  Alcotest.(check int)
    "the shared grammar still parses" 1
    (List.length (captures_of (compiled "(number) @n") (parsed "[1]")))

let handle_tests =
  [
    Alcotest.test_case "reports a missing node" `Quick reports_a_missing_node;
    Alcotest.test_case "reports an error node" `Quick reports_an_error_node;
    Alcotest.test_case "reports a clean tree" `Quick reports_a_clean_tree;
    Alcotest.test_case "gives the kind and the place of a query error" `Quick
      gives_the_kind_and_the_place_of_a_query_error;
    Alcotest.test_case "refuses a directive" `Quick refuses_a_directive;
    Alcotest.test_case "refuses each predicate outside the ten" `Quick
      refuses_each_predicate_outside_the_ten;
    Alcotest.test_case "refuses a predicate whose name ends in neither mark"
      `Quick refuses_a_predicate_whose_name_ends_in_neither_mark;
    Alcotest.test_case "compiles each of the ten predicates" `Quick
      compiles_each_of_the_ten_predicates;
    Alcotest.test_case "refuses a query that is not UTF-8" `Quick
      refuses_a_query_that_is_not_utf_8;
    Alcotest.test_case "an empty query captures nothing" `Quick
      an_empty_query_captures_nothing;
    Alcotest.test_case "numbers the matches of a query" `Quick
      numbers_the_matches_of_a_query;
    Alcotest.test_case "a supertype with a subtype captures the subtype" `Quick
      a_supertype_with_a_subtype_captures_the_subtype;
    Alcotest.test_case "refuses a query over a tree of another grammar" `Quick
      refuses_a_query_over_a_tree_of_another_grammar;
    Alcotest.test_case "names each grammar error" `Quick
      names_each_grammar_error;
    Alcotest.test_case "gives a message for each error" `Quick
      gives_a_message_for_each_error;
    Alcotest.test_case "a tree and a query outlive their grammar" `Quick
      a_tree_and_a_query_outlive_their_grammar;
    Alcotest.test_case "every handle refuses a call after close" `Quick
      every_handle_refuses_a_call_after_close;
    Alcotest.test_case "the collector frees every handle" `Quick
      the_collector_frees_every_handle;
    property ~count:200 ~name:"a capture holds the bytes of its range"
      ~print:String.escaped Generators.any_text
      a_capture_holds_the_bytes_of_its_range;
    property ~count:200 ~name:"match numbers start at 0 and have no gap"
      ~print:Fun.id Generators.json_source match_numbers_have_no_gap;
    property ~count:200 ~name:"the captures of a match share a pattern"
      ~print:Fun.id Generators.json_source
      the_captures_of_a_match_share_a_pattern;
    property ~count:200 ~name:"a document has no parse failure" ~print:Fun.id
      Generators.json_source a_document_has_no_parse_failure;
    property ~count:300 ~name:"a report agrees with its text"
      ~print:String.escaped Generators.any_text a_report_agrees_with_its_text;
    property ~count:200 ~name:"a sexp comes back for any bytes"
      ~print:String.escaped Generators.any_text a_sexp_comes_back_for_any_bytes;
  ]

let one_capture = lazy (compiled one_capture_query)

let captures_come_in_the_order_of_the_nodes source =
  let tree = parsed source in
  let found =
    Fun.protect
      ~finally:(fun () -> B.Tree.close tree)
      (fun () -> captures_of (Lazy.force one_capture) tree)
  in
  let rec in_order = function
    | (first : B.Query.capture) :: (next :: _ as rest) ->
        first.range.start_byte <= next.range.start_byte
        && first.match_number + 1 = next.match_number
        && in_order rest
    | _ -> true
  in
  in_order found

let tests =
  [
    Alcotest.test_case "sha256 gives the 32 bytes of the digest" `Quick
      sha256_gives_the_32_bytes_of_the_digest;
    property ~count:200 ~name:"captures come in the order of the nodes"
      ~print:Fun.id Generators.json_source
      captures_come_in_the_order_of_the_nodes;
  ]
  @ handle_tests
