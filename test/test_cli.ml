(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* Dune runs the test in the build copy of test/, and the executable
   sits beside it in the build copy of bin/. *)
let sinter = "../bin/main.exe"
let grammar = "fixtures/tree-sitter-json/tree-sitter-json.wasm"
let sample = "fixtures/sample.json"
let query = "fixtures/sample.scm"

let contents path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let write path text =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel text)

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
    (fun () -> (code, contents output))

(* The exit code of one serve run that reads [input], what it wrote to
   standard output, and what it wrote to standard error. *)
let session input =
  let request = Filename.temp_file "sinter-serve" ".in" in
  let output = Filename.temp_file "sinter-serve" ".out" in
  let errors = Filename.temp_file "sinter-serve" ".err" in
  write request input;
  Fun.protect
    ~finally:(fun () ->
      Sys.remove request;
      Sys.remove output;
      Sys.remove errors)
    (fun () ->
      let code =
        Sys.command
          (Printf.sprintf "%s serve <%s >%s 2>%s" (Filename.quote sinter)
             (Filename.quote request) (Filename.quote output)
             (Filename.quote errors))
      in
      (code, contents output, contents errors))

(* The lines of an output, without the empty piece that follows the
   last line feed. *)
let lines text =
  let pieces = String.split_on_char '\n' text in
  match List.rev pieces with "" :: rest -> List.rev rest | _ -> pieces

(* Run [command] with [input] on its standard input, and wait [bound]
   seconds at most. The result names the outcome: a process that
   outlives the bound is killed, and the result says so. *)
let outcome_within command ~input ~bound =
  let request = Filename.temp_file "sinter-serve" ".in" in
  write request input;
  let from_file = Unix.openfile request [ Unix.O_RDONLY ] 0 in
  let to_nowhere = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
  Fun.protect
    ~finally:(fun () ->
      Unix.close from_file;
      Unix.close to_nowhere;
      Sys.remove request)
    (fun () ->
      let pid =
        Unix.create_process "/bin/sh"
          [| "/bin/sh"; "-c"; command |]
          from_file to_nowhere to_nowhere
      in
      let step = 0.05 in
      let rec wait waited =
        match Unix.waitpid [ Unix.WNOHANG ] pid with
        | 0, _ when waited >= bound ->
            Unix.kill pid Sys.sigkill;
            ignore (Unix.waitpid [] pid);
            Printf.sprintf "still running after %g seconds" bound
        | 0, _ ->
            Unix.sleepf step;
            wait (waited +. step)
        | _, Unix.WEXITED code -> Printf.sprintf "exited %d" code
        | _, Unix.WSIGNALED signal ->
            Printf.sprintf "killed by signal %d" signal
        | _, Unix.WSTOPPED signal ->
            Printf.sprintf "stopped by signal %d" signal
      in
      wait 0.)

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

let contains needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec search index =
    index + n <= h
    && (String.equal (String.sub haystack index n) needle || search (index + 1))
  in
  search 0

let the_help_of_parse_names_only_the_codes_it_returns () =
  let status, text = run "parse --help=plain" in
  code "the exit code is 0" 0 status;
  List.iter
    (fun line ->
      Alcotest.(check bool)
        (Printf.sprintf "the help of parse holds %S" line)
        true (contains line text))
    [ "EXIT STATUS"; "0   on"; "2   when"; "3   when" ];
  List.iter
    (fun line ->
      Alcotest.(check bool)
        (Printf.sprintf "the help of parse does not hold %S" line)
        false (contains line text))
    [ "1   when"; "4   when" ]

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

let parse_request tag rest =
  Printf.sprintf {|{"id":%s,"op":"parse","grammar":"%s",%s}|} tag grammar rest

let captures_request tag =
  parse_request tag
    (Printf.sprintf {|"query":"%s","files":["%s"]|} query sample)

let tree_request tag =
  parse_request tag (Printf.sprintf {|"tree":true,"files":["%s"]|} sample)

(* Three requests, and the second of them is not a request at all.
   The fixture gives six captures, so the first answer is seven lines,
   the second is one, and the third is two. *)
let a_session_answers_each_request_in_order () =
  let status, output, errors =
    session
      (String.concat "\n"
         [ captures_request "1"; "not a request"; tree_request {|"two"|} ]
      ^ "\n")
  in
  code "the exit code is 0" 0 status;
  Alcotest.(check string) "standard error stays empty" "" errors;
  let lines = lines output in
  Alcotest.(check int)
    "ten lines answer the three requests" 10 (List.length lines);
  let line index = List.nth lines index in
  List.iter
    (fun index ->
      Alcotest.(check bool)
        "a capture line carries the tag of its request" true
        (contains {|"req":1|} (line index)))
    [ 0; 1; 2; 3; 4; 5 ];
  Alcotest.(check string)
    "the first answer ends with a done line"
    {|{"code":0,"event":"done","req":1}|} (line 6);
  Alcotest.(check bool)
    "a line that is not a request gives an error with code 2" true
    (String.starts_with ~prefix:{|{"code":2,"event":"error","message":"|}
       (line 7));
  Alcotest.(check bool)
    "that error line carries no tag" false
    (contains {|"req"|} (line 7));
  Alcotest.(check bool)
    "the tree of the third request carries its path and its tag" true
    (String.starts_with
       ~prefix:{|{"path":"fixtures/sample.json","req":"two","tree":"(document|}
       (line 8));
  Alcotest.(check string)
    "the third answer ends with a done line"
    {|{"code":0,"event":"done","req":"two"}|} (line 9)

let end_of_file_ends_the_run () =
  let status, output, errors = session "" in
  code "the exit code is 0" 0 status;
  Alcotest.(check string) "nothing is written to standard output" "" output;
  Alcotest.(check string) "nothing is written to standard error" "" errors

let a_request_without_a_last_line_feed_is_answered () =
  let status, output, _ = session (tree_request "7") in
  code "the exit code is 0" 0 status;
  Alcotest.(check int)
    "two lines answer the request" 2
    (List.length (lines output))

let a_closed_standard_output_ends_the_run () =
  Alcotest.(check string)
    "the run ends with the environment code" "exited 3"
    (outcome_within
       (Printf.sprintf "exec %s serve >&-" (Filename.quote sinter))
       ~input:(tree_request "1" ^ "\n")
       ~bound:10.)

let the_help_of_serve_names_only_the_codes_it_returns () =
  let status, text = run "serve --help=plain" in
  code "the exit code is 0" 0 status;
  List.iter
    (fun line ->
      Alcotest.(check bool)
        (Printf.sprintf "the help of serve holds %S" line)
        true (contains line text))
    [ "EXIT STATUS"; "0   on"; "2   when"; "3   when" ];
  List.iter
    (fun line ->
      Alcotest.(check bool)
        (Printf.sprintf "the help of serve does not hold %S" line)
        false (contains line text))
    [ "1   when"; "4   when" ]

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
    Alcotest.test_case "the help of parse names only the codes it returns"
      `Quick the_help_of_parse_names_only_the_codes_it_returns;
    Alcotest.test_case "a session answers each request in order" `Quick
      a_session_answers_each_request_in_order;
    Alcotest.test_case "end of file ends the run" `Quick
      end_of_file_ends_the_run;
    Alcotest.test_case "a request without a last line feed is answered" `Quick
      a_request_without_a_last_line_feed_is_answered;
    Alcotest.test_case "a closed standard output ends the run" `Quick
      a_closed_standard_output_ends_the_run;
    Alcotest.test_case "the help of serve names only the codes it returns"
      `Quick the_help_of_serve_names_only_the_codes_it_returns;
  ]
