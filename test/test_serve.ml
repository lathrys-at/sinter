(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

(* Dune runs the test in the build copy of test/, so the paths below
   are relative to that directory. *)
let grammar = "fixtures/tree-sitter-json/tree-sitter-json.wasm"
let sample = "fixtures/sample.json"
let query = "fixtures/sample.scm"
let missing = "no-such-file.json"
let line_of fields = Yojson.Safe.to_string (`Assoc fields)

let request ?(id = `String "r1") ?query ?(tree = false) ?(grammar = grammar)
    files =
  let named name = function None -> [] | Some value -> [ (name, value) ] in
  line_of
    ([ ("id", id); ("op", `String "parse"); ("grammar", `String grammar) ]
    @ named "query" (Option.map (fun path -> `String path) query)
    @ (if tree then [ ("tree", `Bool true) ] else [])
    @ [ ("files", `List (List.map (fun file -> `String file) files)) ])

(* One state for every test that only reads the fixtures. The state
   holds one engine, so the grammar loads once for all of them. *)
let shared = lazy (Serve.create ())

let answer line =
  let state = Lazy.force shared in
  Serve.respond state line

let holds name condition = Alcotest.(check bool) name true condition
let is_control record = List.mem_assoc "event" record
let field name record = List.assoc_opt name record

let last records =
  match List.rev records with [] -> None | record :: _ -> Some record

(* Every record of a canonical line, in the order the writer sorts
   them, read back with yojson. *)
let sorted record =
  match Yojson.Safe.from_string (Jsonl.to_string record) with
  | `Assoc fields ->
      let names = List.map fst fields in
      List.equal String.equal names (List.sort Jsonl.compare_keys names)
  | _ | (exception Yojson.Json_error _) -> false

(* Generators. *)

(* One tag, as the request writes it and as the answer carries it. *)
let tag : (Yojson.Safe.t * Jsonl.value) Gen.t =
  Gen.oneof
    [
      Gen.map
        (fun text -> (`String text, Jsonl.string text))
        Gen.string_printable;
      Gen.map
        (fun number -> (`Int number, Jsonl.int number))
        (Gen.int_range (-1000) 1000);
    ]

(* A request that the loop can read. Some of these run to their end and
   some fail, and the shape of the answer is the same either way. *)
let well_formed =
  let open Gen in
  let* id, expected = tag in
  let* shape =
    oneof
      [
        return (fun id -> request ~id ~query [ sample ]);
        return (fun id -> request ~id ~tree:true [ sample ]);
        return (fun id -> request ~id ~query [ sample; sample ]);
        return (fun id -> request ~id ~query [ sample; missing ]);
        return (fun id -> request ~id ~query [ missing ]);
        return (fun id -> request ~id ~tree:true ~grammar:missing [ sample ]);
        return (fun id -> request ~id ~query:missing [ sample ]);
        return (fun id -> request ~id ~query:sample [ sample ]);
        return (fun id -> request ~id ~tree:true ~grammar:sample [ sample ]);
      ]
  in
  return (expected, shape id)

(* A line that is not a request: random bytes, or a request with one
   byte cut, changed, or added. *)
let ill_formed =
  let open Gen in
  let* _, line = well_formed in
  let length = String.length line in
  oneof
    [
      string;
      map (fun cut -> String.sub line 0 cut) (int_range 0 (length - 1));
      map2
        (fun at byte ->
          let bytes = Bytes.of_string line in
          Bytes.set bytes (at mod length) byte;
          Bytes.to_string bytes)
        (int_range 0 length) char;
    ]

(* Property tests. *)

let answers_a_well_formed_request =
  QCheck2.Test.make ~count:200
    ~name:
      "a well-formed request gets one control line, last, and a tag on every \
       line"
    ~print:(fun (_, line) -> String.escaped line)
    well_formed
    (fun (expected, line) ->
      let records = Serve.lines (answer line) in
      let expected = Some expected in
      List.length (List.filter is_control records) = 1
      && (match last records with
        | Some record -> is_control record
        | None -> false)
      && List.for_all (fun record -> field "req" record = expected) records
      && List.for_all sorted records)

let answers_a_line_that_is_not_a_request =
  QCheck2.Test.make ~count:1000
    ~name:"a line that is not a request gets one error line with code 2"
    ~print:String.escaped ill_formed (fun line ->
      match Request.of_line line with
      | Ok _ -> true
      | Error _ -> (
          let records = Serve.lines (answer line) in
          match records with
          | [ record ] ->
              field "event" record = Some (Jsonl.string "error")
              && field "code" record = Some (Jsonl.int 2)
              && sorted record
          | _ -> false))

(* Tests of one fact each. *)

let a_query_request_ends_with_a_done_line () =
  let records = Serve.lines (answer (request ~query [ sample ])) in
  holds "the answer holds captures and one done line" (List.length records > 1);
  holds "the last line says done"
    (match last records with
    | Some record ->
        field "event" record = Some (Jsonl.string "done")
        && field "code" record = Some (Jsonl.int 0)
    | None -> false)

let a_query_request_tags_every_capture () =
  let records = Serve.lines (answer (request ~query [ sample ])) in
  holds "every capture carries the tag"
    (List.for_all
       (fun record -> field "req" record = Some (Jsonl.string "r1"))
       records)

let a_tree_request_gives_one_object_for_each_file () =
  let records = Serve.lines (answer (request ~tree:true [ sample; sample ])) in
  holds "two trees and one done line" (List.length records = 3);
  holds "each tree names its file and its S-expression"
    (List.for_all
       (fun record ->
         is_control record
         || field "path" record = Some (Jsonl.string sample)
            &&
            match field "tree" record with
            | Some (Jsonl.Scalar (Jsonl.String sexp)) ->
                String.starts_with ~prefix:"(document" sexp
            | _ -> false)
       records)

let a_file_that_does_not_exist_ends_with_an_error_line () =
  let records = Serve.lines (answer (request ~query [ missing ])) in
  holds "one error line only" (List.length records = 1);
  holds "the line names the environment code"
    (match last records with
    | Some record ->
        field "event" record = Some (Jsonl.string "error")
        && field "code" record = Some (Jsonl.int 3)
    | None -> false)

let an_error_line_carries_the_message_of_the_one_shot_command () =
  let records = Serve.lines (answer (request ~query [ missing ])) in
  holds "the message names the file the caller gave"
    (match last records with
    | Some record -> (
        match field "message" record with
        | Some (Jsonl.Scalar (Jsonl.String message)) ->
            String.starts_with ~prefix:(missing ^ ":") message
        | _ -> false)
    | None -> false)

let the_lines_before_a_failure_are_kept () =
  let records = Serve.lines (answer (request ~query [ sample; missing ])) in
  holds "the captures of the first file come first" (List.length records > 1);
  holds "the answer ends with an error line"
    (match last records with
    | Some record -> field "event" record = Some (Jsonl.string "error")
    | None -> false)

let control_says_done_for_an_operation_that_ran () =
  holds "the control is Done 0"
    (Serve.control (answer (request ~tree:true [ sample ])) = Serve.Done 0)

let control_says_failed_for_an_operation_that_did_not_run () =
  holds "the control is Failed with the environment code"
    (match Serve.control (answer (request ~query [ missing ])) with
    | Serve.Failed (code, _) -> code = 3
    | Serve.Done _ -> false)

let control_says_failed_for_a_line_that_is_not_a_request () =
  holds "the control is Failed with the usage code"
    (match Serve.control (answer "{") with
    | Serve.Failed (code, _) -> code = 2
    | Serve.Done _ -> false)

let a_line_that_holds_no_tag_gets_an_answer_without_one () =
  let records = Serve.lines (answer "{") in
  holds "one line only" (List.length records = 1);
  holds "the line carries no tag"
    (match last records with
    | Some record -> field "req" record = None
    | None -> false)

let a_number_tag_comes_back_as_a_number () =
  let records =
    Serve.lines (answer (request ~id:(`Int 7) ~tree:true [ sample ]))
  in
  holds "every line carries the number"
    (List.for_all
       (fun record -> field "req" record = Some (Jsonl.int 7))
       records)

(* The grammar cache. Each test below owns a copy of the grammar file,
   so that it can change the file without touching another test. *)

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let write_file path text =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel text)

(* The same bytes as the grammar, with the magic number of a wasm
   module broken. The size does not change. *)
let broken text = "\000asX" ^ String.sub text 4 (String.length text - 4)
let fixed_time = 1000000000.0

let with_copy work =
  let path = Filename.temp_file "sinter-grammar" ".wasm" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with Sys_error _ -> ())
    (fun () ->
      let text = read_file grammar in
      write_file path text;
      let state = Serve.create () in
      Fun.protect
        ~finally:(fun () -> Serve.close state)
        (fun () -> work state path text))

let ran response =
  match Serve.control response with
  | Serve.Done _ -> true
  | Serve.Failed _ -> false

let ask state path =
  Serve.respond state (request ~tree:true ~grammar:path [ sample ])

let the_loop_reads_a_grammar_once () =
  with_copy (fun state path text ->
      Unix.utimes path fixed_time fixed_time;
      holds "the first request loads the grammar" (ran (ask state path));
      (* The file is no longer a grammar, and its size and its
         modification time did not change. *)
      write_file path (broken text);
      Unix.utimes path fixed_time fixed_time;
      holds "the second request uses the grammar it kept" (ran (ask state path)))

let the_loop_reads_a_grammar_again_when_its_size_changes () =
  with_copy (fun state path text ->
      holds "the first request loads the grammar" (ran (ask state path));
      write_file path (broken text ^ "\000");
      holds "the second request loads the file again"
        (not (ran (ask state path))))

let the_loop_reads_a_grammar_again_when_its_time_changes () =
  with_copy (fun state path text ->
      Unix.utimes path fixed_time fixed_time;
      holds "the first request loads the grammar" (ran (ask state path));
      write_file path (broken text);
      Unix.utimes path (fixed_time +. 10.) (fixed_time +. 10.);
      holds "the second request loads the file again"
        (not (ran (ask state path))))

let a_grammar_that_does_not_load_is_not_kept () =
  with_copy (fun state path text ->
      write_file path (broken text);
      Unix.utimes path fixed_time fixed_time;
      holds "the first request fails" (not (ran (ask state path)));
      (* The same size and the same modification time as the file that
         failed, and this time the bytes are a grammar. *)
      write_file path text;
      Unix.utimes path fixed_time fixed_time;
      holds "the second request loads the grammar" (ran (ask state path)))

let a_closed_state_refuses_to_answer () =
  let state = Serve.create () in
  Serve.close state;
  Alcotest.check_raises "the state is closed"
    (Invalid_argument "Sinter_core.Serve: the state of the loop is closed")
    (fun () -> ignore (Serve.respond state (request ~tree:true [ sample ])))

let case name test = Alcotest.test_case name `Quick test

let tests =
  List.map
    (QCheck_alcotest.to_alcotest ~speed_level:`Quick)
    [ answers_a_well_formed_request; answers_a_line_that_is_not_a_request ]
  @ [
      case "a query request ends with a done line"
        a_query_request_ends_with_a_done_line;
      case "a query request tags every capture"
        a_query_request_tags_every_capture;
      case "a tree request gives one object for each file"
        a_tree_request_gives_one_object_for_each_file;
      case "a file that does not exist ends with an error line"
        a_file_that_does_not_exist_ends_with_an_error_line;
      case "an error line carries the message of the one-shot command"
        an_error_line_carries_the_message_of_the_one_shot_command;
      case "the lines before a failure are kept"
        the_lines_before_a_failure_are_kept;
      case "control says done for an operation that ran"
        control_says_done_for_an_operation_that_ran;
      case "control says failed for an operation that did not run"
        control_says_failed_for_an_operation_that_did_not_run;
      case "control says failed for a line that is not a request"
        control_says_failed_for_a_line_that_is_not_a_request;
      case "a line that holds no tag gets an answer without one"
        a_line_that_holds_no_tag_gets_an_answer_without_one;
      case "a number tag comes back as a number"
        a_number_tag_comes_back_as_a_number;
      case "the loop reads a grammar once" the_loop_reads_a_grammar_once;
      case "the loop reads a grammar again when its size changes"
        the_loop_reads_a_grammar_again_when_its_size_changes;
      case "the loop reads a grammar again when its time changes"
        the_loop_reads_a_grammar_again_when_its_time_changes;
      case "a grammar that does not load is not kept"
        a_grammar_that_does_not_load_is_not_kept;
      case "a closed state refuses to answer" a_closed_state_refuses_to_answer;
    ]
