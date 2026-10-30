(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let case name f = Alcotest.test_case name `Quick f
let phases = Alcotest.(list (pair string int))

let words_of f =
  let counts = Allocation.create () in
  ignore (Allocation.measure (Some counts) "f" f);
  match Allocation.phases counts with
  | [ ("f", words) ] -> words
  | _ -> Alcotest.fail "one phase"

let a_phase_counts_the_words_that_it_allocates () =
  let array size () = Sys.opaque_identity (Array.make size 0) in
  Alcotest.(check int)
    "100 more words on the minor heap" 100
    (words_of (array 200) - words_of (array 100));
  Alcotest.(check int)
    "1000 more words on the major heap" 1000
    (words_of (array 2000) - words_of (array 1000))

let measure_gives_the_result_of_the_function () =
  let counts = Allocation.create () in
  Alcotest.(check int)
    "with counts" 7
    (Allocation.measure (Some counts) "a" (fun () -> 7));
  Alcotest.(check int)
    "without counts" 8
    (Allocation.measure None "a" (fun () -> 8))

let phases_add_up_in_the_order_of_their_first_measure () =
  let counts = Allocation.create () in
  let block size () = ignore (Sys.opaque_identity (Array.make size 0)) in
  let base = words_of (block 0) in
  Allocation.measure (Some counts) "b" (block 10);
  Allocation.measure (Some counts) "a" (block 20);
  Allocation.measure (Some counts) "b" (block 30);
  Alcotest.check phases "the phases"
    [ ("b", (2 * base) + 42); ("a", base + 21) ]
    (Allocation.phases counts)

let an_inner_phase_counts_in_the_outer_phase_too () =
  let counts = Allocation.create () in
  let block size () = ignore (Sys.opaque_identity (Array.make size 0)) in
  let inner = words_of (block 50) in
  Allocation.measure (Some counts) "outer" (fun () ->
      Allocation.measure (Some counts) "inner" (block 50));
  match Allocation.phases counts with
  | [ ("inner", words); ("outer", outer) ] ->
      Alcotest.(check int) "inner" inner words;
      Alcotest.(check bool) "outer holds inner" true (outer >= inner)
  | _ -> Alcotest.fail "two phases, the inner one first"

let a_phase_that_raises_adds_nothing () =
  let counts = Allocation.create () in
  (match
     Allocation.measure (Some counts) "a" (fun () ->
         ignore (Sys.opaque_identity (Array.make 10 0));
         raise Exit)
   with
  | () -> Alcotest.fail "no exception"
  | exception Exit -> ());
  Alcotest.check phases "no phase" [] (Allocation.phases counts)

let to_string_gives_a_line_per_phase () =
  let counts = Allocation.create () in
  Alcotest.(check string) "no phase" "" (Allocation.to_string counts);
  Allocation.measure (Some counts) "read" ignore;
  Allocation.measure (Some counts) "parse" ignore;
  match Allocation.phases counts with
  | [ ("read", read); ("parse", parse) ] ->
      Alcotest.(check string)
        "the lines"
        (Printf.sprintf "read %d\nparse %d\n" read parse)
        (Allocation.to_string counts)
  | _ -> Alcotest.fail "two phases"

let the_variable_is_sinter_phase_words () =
  Alcotest.(check string) "the name" "SINTER_PHASE_WORDS" Allocation.variable

let sinter = Filename.concat (Sys.getcwd ()) "../bin/main.exe"

let repository () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml"
    "[scan]\npacks.markdown.files = [\"**/*.md\"]\n";
  Git_fixture.write repo "a.md" "# A\n\n@req a\n";
  Git_fixture.write repo "b.md" "# B\n\n@cites a\n";
  ignore (Git_fixture.git repo [ "add"; "-A" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "-m"; "c" ]);
  repo

let run repo ~words command =
  let errors = Filename.temp_file "sinter-phases" ".err" in
  let environment =
    Array.append (Git_fixture.env repo) [| Allocation.variable ^ "=" ^ words |]
  in
  Fun.protect
    ~finally:(fun () -> Sys.remove errors)
    (fun () ->
      let to_errors =
        Unix.openfile errors [ Unix.O_WRONLY; Unix.O_TRUNC; Unix.O_CLOEXEC ] 0
      in
      let to_nowhere = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
      let pid =
        Fun.protect
          ~finally:(fun () ->
            Unix.close to_errors;
            Unix.close to_nowhere)
          (fun () ->
            Unix.create_process_env "/bin/sh"
              [|
                "/bin/sh";
                "-c";
                "cd \"$1\" && exec \"$2\" \"$3\"";
                "sh";
                Git_fixture.root repo;
                sinter;
                command;
              |]
              environment Unix.stdin to_nowhere to_errors)
      in
      let status =
        match Unix.waitpid [] pid with
        | _, Unix.WEXITED code -> code
        | _, (Unix.WSIGNALED signal | Unix.WSTOPPED signal) -> -signal
      in
      (status, In_channel.with_open_bin errors In_channel.input_all))

let without_warnings text =
  String.concat ""
    (List.map
       (fun line -> line ^ "\n")
       (List.filter
          (fun line ->
            not
              (String.equal line ""
              || String.starts_with ~prefix:"warning:" line))
          (String.split_on_char '\n' text)))

let names text =
  List.filter_map
    (fun line ->
      match String.split_on_char ' ' line with
      | [ name; words ] when int_of_string_opt words <> None -> Some name
      | _ -> None)
    (String.split_on_char '\n' text)

let a_command_writes_the_words_of_its_phases () =
  let repo = repository () in
  List.iter
    (fun (command, expected) ->
      let words = Filename.temp_file "sinter-phases" ".txt" in
      let status, _ = run repo ~words command in
      Alcotest.(check int) (command ^ ": exit") 0 status;
      Alcotest.(check (list string))
        (command ^ ": the phases") expected
        (names (In_channel.with_open_bin words In_channel.input_all));
      Sys.remove words)
    [
      ("scan", [ "repository"; "read"; "parse"; "facts"; "records"; "output" ]);
      ( "check",
        [
          "repository";
          "base-read";
          "read";
          "parse";
          "facts";
          "findings";
          "output";
        ] );
    ]

let an_empty_variable_writes_nothing () =
  let repo = repository () in
  let status, errors = run repo ~words:"" "scan" in
  Alcotest.(check (pair int string))
    "exit and errors" (0, "")
    (status, without_warnings errors)

let a_file_that_cannot_be_written_is_an_environment_error () =
  let repo = repository () in
  let words = Filename.concat (Git_fixture.temp_dir ()) "missing/words.txt" in
  let status, errors = run repo ~words "scan" in
  Alcotest.(check (pair int string))
    "exit and errors"
    ( 3,
      Printf.sprintf
        "error: cannot write the words of the phases: %s: No such file or \
         directory\n\
        \  = help: name a file that you can write in SINTER_PHASE_WORDS\n"
        words )
    (status, without_warnings errors)

let tests =
  [
    case "a phase counts the words that it allocates"
      a_phase_counts_the_words_that_it_allocates;
    case "measure gives the result of the function"
      measure_gives_the_result_of_the_function;
    case "phases add up in the order of their first measure"
      phases_add_up_in_the_order_of_their_first_measure;
    case "an inner phase counts in the outer phase too"
      an_inner_phase_counts_in_the_outer_phase_too;
    case "a phase that raises adds nothing" a_phase_that_raises_adds_nothing;
    case "to_string gives a line per phase" to_string_gives_a_line_per_phase;
    case "the variable is SINTER_PHASE_WORDS" the_variable_is_sinter_phase_words;
    case "a command writes the words of its phases"
      a_command_writes_the_words_of_its_phases;
    case "an empty variable writes nothing" an_empty_variable_writes_nothing;
    case "a file that cannot be written is an environment error"
      a_file_that_cannot_be_written_is_an_environment_error;
  ]
