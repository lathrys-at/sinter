(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* Dune runs the test in the build copy of test/, and the executable
   sits beside it in the build copy of bin/. *)
let sinter = "../bin/main.exe"
let grammar = "fixtures/tree-sitter-json/tree-sitter-json.wasm"
let sample = "fixtures/sample.json"
let query = "fixtures/sample.scm"

(* The exit code of one run, and everything it wrote to its two
   output channels. *)
let run arguments =
  let output = Filename.temp_file "sinter-cli" ".out" in
  let command =
    Printf.sprintf "%s %s >%s 2>&1" (Filename.quote sinter) arguments
      (Filename.quote output)
  in
  let code = Sys.command command in
  Fun.protect
    ~finally:(fun () -> Sys.remove output)
    (fun () ->
      let channel = open_in_bin output in
      Fun.protect
        ~finally:(fun () -> close_in_noerr channel)
        (fun () ->
          (code, really_input_string channel (in_channel_length channel))))

let code = Alcotest.(check int)

let a_run_that_prints_captures_is_clean () =
  let status, text =
    run (Printf.sprintf "parse --grammar %s --query %s %s" grammar query sample)
  in
  code "the exit code is 0" 0 status;
  Alcotest.(check bool)
    "the first line is a record" true
    (String.starts_with ~prefix:{|{"cap":|} text)

let a_run_that_prints_a_tree_is_clean () =
  let status, text =
    run (Printf.sprintf "parse --grammar %s --tree %s" grammar sample)
  in
  code "the exit code is 0" 0 status;
  Alcotest.(check bool)
    "the line is an S-expression" true
    (String.starts_with ~prefix:"(document" text)

let two_options_that_exclude_each_other_are_a_usage_error () =
  let status, _ =
    run
      (Printf.sprintf "parse --grammar %s --query %s --tree %s" grammar query
         sample)
  in
  code "the exit code is 2" 2 status

let neither_option_is_a_usage_error () =
  let status, _ = run (Printf.sprintf "parse --grammar %s %s" grammar sample) in
  code "the exit code is 2" 2 status

let an_unknown_option_is_a_usage_error () =
  let status, _ = run "parse --no-such-option" in
  code "the exit code is 2" 2 status

let a_file_that_does_not_exist_is_an_environment_error () =
  let status, _ =
    run
      (Printf.sprintf "parse --grammar %s --query %s no-such-file.json" grammar
         query)
  in
  code "the exit code is 3" 3 status

let a_grammar_that_is_not_wasm_is_an_environment_error () =
  let status, text =
    run (Printf.sprintf "parse --grammar %s --tree %s" sample sample)
  in
  code "the exit code is 3" 3 status;
  Alcotest.(check bool)
    "the message starts with the name of the tool" true
    (String.starts_with ~prefix:"sinter: " text)

let the_help_lists_the_five_exit_codes () =
  let status, text = run "--help=plain" in
  code "the exit code is 0" 0 status;
  List.iter
    (fun line ->
      Alcotest.(check bool)
        (Printf.sprintf "the help holds %S" line)
        true
        (String.length text > 0
        &&
        let n = String.length line and h = String.length text in
        let rec search index =
          index + n <= h
          && (String.equal (String.sub text index n) line || search (index + 1))
        in
        search 0))
    [ "EXIT STATUS"; "0   on"; "1   when"; "2   when"; "3   when"; "4   when" ]

let tests =
  [
    Alcotest.test_case "a run that prints captures is clean" `Quick
      a_run_that_prints_captures_is_clean;
    Alcotest.test_case "a run that prints a tree is clean" `Quick
      a_run_that_prints_a_tree_is_clean;
    Alcotest.test_case "two options that exclude each other are a usage error"
      `Quick two_options_that_exclude_each_other_are_a_usage_error;
    Alcotest.test_case "neither option is a usage error" `Quick
      neither_option_is_a_usage_error;
    Alcotest.test_case "an unknown option is a usage error" `Quick
      an_unknown_option_is_a_usage_error;
    Alcotest.test_case "a file that does not exist is an environment error"
      `Quick a_file_that_does_not_exist_is_an_environment_error;
    Alcotest.test_case "a grammar that is not wasm is an environment error"
      `Quick a_grammar_that_is_not_wasm_is_an_environment_error;
    Alcotest.test_case "the help lists the five exit codes" `Quick
      the_help_lists_the_five_exit_codes;
  ]
