(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

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

let lines text =
  let pieces = String.split_on_char '\n' text in
  match List.rev pieces with "" :: rest -> List.rev rest | _ -> pieces

let outcome_within ?errors command ~input ~bound =
  let request = Filename.temp_file "sinter-serve" ".in" in
  write request input;
  let from_file = Unix.openfile request [ Unix.O_RDONLY ] 0 in
  let to_nowhere = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
  let to_errors =
    match errors with
    | None -> None
    | Some path ->
        Some
          (Unix.openfile path
             [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ]
             0o600)
  in
  Fun.protect
    ~finally:(fun () ->
      Unix.close from_file;
      Unix.close to_nowhere;
      Option.iter Unix.close to_errors;
      Sys.remove request)
    (fun () ->
      let pid =
        Unix.create_process "/bin/sh"
          [| "/bin/sh"; "-c"; command |]
          from_file to_nowhere
          (Option.value to_errors ~default:to_nowhere)
      in
      let rec wait waited pause =
        match Unix.waitpid [ Unix.WNOHANG ] pid with
        | 0, _ when waited >= bound ->
            Unix.kill pid Sys.sigkill;
            ignore (Unix.waitpid [] pid);
            Printf.sprintf "still running after %g seconds" bound
        | 0, _ ->
            Unix.sleepf pause;
            wait (waited +. pause) (Float.min (2. *. pause) 0.05)
        | _, Unix.WEXITED code -> Printf.sprintf "exited %d" code
        | _, Unix.WSIGNALED signal ->
            Printf.sprintf "killed by signal %d" signal
        | _, Unix.WSTOPPED signal ->
            Printf.sprintf "stopped by signal %d" signal
      in
      wait 0. 0.001)

let code = Alcotest.(check int)

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

let the_help_lists_the_exit_codes_that_a_command_returns () =
  let status, text = run "--help=plain" in
  code "the exit code is 0" 0 status;
  List.iter
    (fun line ->
      Alcotest.(check bool)
        (Printf.sprintf "the help holds %S" line)
        true (contains line text))
    [ "EXIT STATUS"; "0   on"; "1   when"; "2   when"; "3   when" ];
  Alcotest.(check bool)
    "the help does not hold \"4   when\"" false (contains "4   when" text)

let the_help_lists_scan_parse_and_serve_as_plumbing () =
  let status, text = run "--help=plain" in
  code "the exit code is 0" 0 status;
  let index line =
    let n = String.length line and h = String.length text in
    let rec search i =
      if i + n > h then None
      else if String.equal (String.sub text i n) line then Some i
      else search (i + 1)
    in
    search 0
  in
  match index "PLUMBING COMMANDS" with
  | None -> Alcotest.fail "the help holds no PLUMBING COMMANDS section"
  | Some plumbing ->
      List.iter
        (fun command ->
          match index ("       " ^ command ^ " ") with
          | None -> Alcotest.failf "the help does not list %s" command
          | Some at ->
              Alcotest.(check bool)
                (Printf.sprintf "%s is under PLUMBING COMMANDS" command)
                true (at > plumbing))
        [ "parse"; "scan"; "serve" ];
      Alcotest.(check bool)
        "check is above PLUMBING COMMANDS" true
        (match index "       check " with
        | Some at -> at < plumbing
        | None -> false)

let the_version_names_the_checkout () =
  let status, text = run "--version" in
  code "the exit code is 0" 0 status;
  let describe = Sinter_core.Git_version.describe in
  if String.equal describe "unknown" then
    Alcotest.(check string)
      "the version of a build without a checkout"
      ("v" ^ Sinter_core.Version.base ^ "-dev\n")
      text
  else
    Alcotest.(check bool)
      "the version holds the description of the checkout" true
      (contains describe text)

let the_version_starts_with_the_release_version () =
  let status, text = run "--version" in
  code "the exit code is 0" 0 status;
  let prefix = "v" ^ Sinter_core.Version.base in
  Alcotest.(check bool)
    (Printf.sprintf "the version starts with %S" prefix)
    true
    (String.starts_with ~prefix text)

let parse_request rid rest =
  Printf.sprintf {|{"rid":%s,"op":"parse","grammar":"%s",%s}|} rid grammar rest

let tree_request rid =
  parse_request rid (Printf.sprintf {|"tree":true,"files":["%s"]|} sample)

let first_line_while_open request ~bound =
  let request_in, request_out = Unix.pipe ~cloexec:true () in
  let answer_in, answer_out = Unix.pipe ~cloexec:true () in
  let to_nowhere =
    Unix.openfile "/dev/null" [ Unix.O_WRONLY; Unix.O_CLOEXEC ] 0
  in
  let pid =
    Fun.protect
      ~finally:(fun () ->
        Unix.close request_in;
        Unix.close answer_out;
        Unix.close to_nowhere)
      (fun () ->
        try
          Unix.create_process sinter [| sinter; "serve" |] request_in answer_out
            to_nowhere
        with error ->
          Unix.close request_out;
          Unix.close answer_in;
          raise error)
  in
  Fun.protect
    ~finally:(fun () ->
      Unix.kill pid Sys.sigkill;
      ignore (Unix.waitpid [] pid);
      Unix.close request_out;
      Unix.close answer_in)
    (fun () ->
      let previous = Sys.signal Sys.sigpipe Sys.Signal_ignore in
      Fun.protect
        ~finally:(fun () -> Sys.set_signal Sys.sigpipe previous)
        (fun () ->
          let text = request ^ "\n" in
          ignore (Unix.write_substring request_out text 0 (String.length text)));
      let deadline = Unix.gettimeofday () +. bound in
      let buffer = Buffer.create 256 in
      let chunk = Bytes.create 4096 in
      let rec read () =
        match String.index_opt (Buffer.contents buffer) '\n' with
        | Some stop -> Some (Buffer.sub buffer 0 stop)
        | None -> (
            let left = deadline -. Unix.gettimeofday () in
            if left <= 0. then None
            else
              match Unix.select [ answer_in ] [] [] left with
              | [], _, _ -> None
              | _ -> (
                  match Unix.read answer_in chunk 0 (Bytes.length chunk) with
                  | 0 -> None
                  | count ->
                      Buffer.add_subbytes buffer chunk 0 count;
                      read ()))
      in
      read ())

let an_answer_arrives_before_the_input_ends () =
  match first_line_while_open "not a request" ~bound:5. with
  | None -> Alcotest.fail "no answer arrived while the input stayed open"
  | Some line ->
      Alcotest.(check bool)
        "the answer is the error line of the request" true
        (String.starts_with ~prefix:{|{"code":2,"event":"error","message":"|}
           line)

let a_closed_standard_output_ends_the_run () =
  Alcotest.(check string)
    "the run ends with the environment code" "exited 3"
    (outcome_within
       (Printf.sprintf "exec %s serve >&-" (Filename.quote sinter))
       ~input:(tree_request "1" ^ "\n")
       ~bound:10.)

let a_closed_standard_output_names_the_failure () =
  let errors = Filename.temp_file "sinter-serve" ".err" in
  let text =
    Fun.protect
      ~finally:(fun () -> Sys.remove errors)
      (fun () ->
        ignore
          (outcome_within ~errors
             (Printf.sprintf "exec %s serve >&-" (Filename.quote sinter))
             ~input:(tree_request "1" ^ "\n")
             ~bound:10.);
        contents errors)
  in
  Alcotest.(check (list string))
    "standard error holds the error and its help"
    [
      "error: cannot write the output: standard output is closed";
      "  = help: run the command with its standard output open";
    ]
    (lines text)

let outcome_and_errors command ~input =
  let errors = Filename.temp_file "sinter-run" ".err" in
  Fun.protect
    ~finally:(fun () -> Sys.remove errors)
    (fun () ->
      let outcome = outcome_within ~errors command ~input ~bound:10. in
      (outcome, contents errors))

let a_closed_standard_output_ends_a_run_that_writes_nothing () =
  Alcotest.(check string)
    "the run ends with the environment code" "exited 3"
    (outcome_within
       (Printf.sprintf "exec %s serve >&-" (Filename.quote sinter))
       ~input:"" ~bound:10.)

let a_closed_standard_output_ends_any_command () =
  Alcotest.(check string)
    "the run ends with the environment code" "exited 3"
    (outcome_within
       (Printf.sprintf "exec %s --help=plain >&-" (Filename.quote sinter))
       ~input:"" ~bound:10.)

let a_closed_standard_input_reads_as_no_request () =
  Alcotest.(check (pair string string))
    "the run ends clean and writes no error" ("exited 0", "")
    (outcome_and_errors
       (Printf.sprintf "exec %s serve <&-" (Filename.quote sinter))
       ~input:"")

let a_failed_read_names_the_input () =
  let outcome, text =
    outcome_and_errors
      (Printf.sprintf "exec %s serve < /" (Filename.quote sinter))
      ~input:""
  in
  Alcotest.(check string)
    "the run ends with the environment code" "exited 3" outcome;
  Alcotest.(check bool)
    "standard error names the read" true
    (String.starts_with ~prefix:"error: cannot read the input: " text
    && List.mem "  = help: give the command an input that it can read"
         (lines text))

let a_closed_standard_error_keeps_the_exit_code () =
  Alcotest.(check string)
    "the run ends with the environment code" "exited 3"
    (outcome_within
       (Printf.sprintf "exec %s parse --grammar missing.wasm --query %s %s 2>&-"
          (Filename.quote sinter) query sample)
       ~input:"" ~bound:10.)

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

let unwrapped text =
  let buffer = Buffer.create (String.length text) in
  let blank character =
    character = ' ' || character = '\n' || character = '\t' || character = '\r'
  in
  let ends_with_space () =
    Buffer.length buffer > 0
    && Buffer.nth buffer (Buffer.length buffer - 1) = ' '
  in
  String.iter
    (fun character ->
      if blank character then (
        if Buffer.length buffer > 0 && not (ends_with_space ()) then
          Buffer.add_char buffer ' ')
      else Buffer.add_char buffer character)
    text;
  Buffer.contents buffer

let the_help_of_serve_names_the_request_id () =
  let status, text = run "serve --help=plain" in
  code "the exit code is 0" 0 status;
  let text = unwrapped text in
  List.iter
    (fun phrase ->
      Alcotest.(check bool)
        (Printf.sprintf "the help of serve holds %S" phrase)
        true (contains phrase text))
    [ "in the field rid"; "code 2 and no rid" ];
  Alcotest.(check bool)
    "the help of serve does not name the old field" false
    (contains "the field req" text)

let a_parse_run_that_fails_names_no_module_of_the_library () =
  List.iter
    (fun (what, arguments) ->
      let status, text = run arguments in
      code (Printf.sprintf "%s exits 3" what) 3 status;
      Alcotest.(check bool)
        (Printf.sprintf "%s names no module of the library" what)
        false (contains "Sinter_" text))
    [
      ( "a grammar that is not wasm",
        Printf.sprintf "parse --grammar %s --tree %s" sample sample );
      ( "a source file that does not exist",
        Printf.sprintf "parse --grammar %s --tree no-such-file.json" grammar );
      ( "a query file that does not exist",
        Printf.sprintf "parse --grammar %s --query no-such-file.scm %s" grammar
          sample );
      ( "a directory as the grammar",
        Printf.sprintf "parse --grammar fixtures --tree %s" sample );
      ( "a directory as the source file",
        Printf.sprintf "parse --grammar %s --tree fixtures" grammar );
    ]

let tests =
  [
    Alcotest.test_case "the version names the checkout" `Quick
      the_version_names_the_checkout;
    Alcotest.test_case "the version starts with the release version" `Quick
      the_version_starts_with_the_release_version;
    Alcotest.test_case "a parse run that fails names no module of the library"
      `Quick a_parse_run_that_fails_names_no_module_of_the_library;
    Alcotest.test_case "the help lists the exit codes that a command returns"
      `Quick the_help_lists_the_exit_codes_that_a_command_returns;
    Alcotest.test_case "the help lists scan, parse, and serve as plumbing"
      `Quick the_help_lists_scan_parse_and_serve_as_plumbing;
    Alcotest.test_case "the help of parse names only the codes it returns"
      `Quick the_help_of_parse_names_only_the_codes_it_returns;
    Alcotest.test_case "an answer arrives before the input ends" `Quick
      an_answer_arrives_before_the_input_ends;
    Alcotest.test_case "a closed standard output ends the run" `Quick
      a_closed_standard_output_ends_the_run;
    Alcotest.test_case "a closed standard output names the failure" `Quick
      a_closed_standard_output_names_the_failure;
    Alcotest.test_case "a closed standard output ends a run that writes nothing"
      `Quick a_closed_standard_output_ends_a_run_that_writes_nothing;
    Alcotest.test_case "a closed standard output ends any command" `Quick
      a_closed_standard_output_ends_any_command;
    Alcotest.test_case "a closed standard input reads as no request" `Quick
      a_closed_standard_input_reads_as_no_request;
    Alcotest.test_case "a failed read names the input" `Quick
      a_failed_read_names_the_input;
    Alcotest.test_case "a closed standard error keeps the exit code" `Quick
      a_closed_standard_error_keeps_the_exit_code;
    Alcotest.test_case "the help of serve names only the codes it returns"
      `Quick the_help_of_serve_names_only_the_codes_it_returns;
    Alcotest.test_case "the help of serve names the request id" `Quick
      the_help_of_serve_names_the_request_id;
  ]
