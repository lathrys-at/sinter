(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let sh = "/bin/sh"

let error =
  Alcotest.testable
    (fun formatter error ->
      Format.pp_print_string formatter (Fixture.message ~case:"case" error))
    ( = )

let outcome = Alcotest.(result (list string) error)

(* Writes each file of [files] under [root], with its folders. A path
   that ends with a slash names an empty folder. *)
let write_files root files =
  let rec make_folder path =
    if not (Sys.file_exists path) then (
      make_folder (Filename.dirname path);
      Sys.mkdir path 0o755)
  in
  List.iter
    (fun (path, text) ->
      let full = Filename.concat root path in
      if String.ends_with ~suffix:"/" path then make_folder full
      else (
        make_folder (Filename.dirname full);
        Out_channel.with_open_bin full (fun channel ->
            Out_channel.output_string channel text)))
    files

let read path = In_channel.with_open_bin path In_channel.input_all

(* The args of a run of sh that runs [script], which is one line. *)
let script text = "-c\n" ^ text ^ "\n"

(* The entries of a case that runs [script] in an empty tree and
   expects [stdout], [stderr], and [exit]. *)
let case_files ?(stdout = "") ?(stderr = "") ?(exit = "0\n") text =
  [
    ("args", script text);
    ("tree/", "");
    ("expected/stdout", stdout);
    ("expected/stderr", stderr);
    ("expected/exit", exit);
  ]

(* Calls [f] with the path of a case folder named "case" that holds
   [files]. *)
let with_case files f =
  Fixture.with_temporary_folder (fun folder ->
      let case = Filename.concat folder "case" in
      write_files case files;
      f case)

let run ?bound ?(mode = Fixture.Compare) case =
  Fixture.run ?bound ~binary:sh mode case

let check_run name expected files =
  with_case files (fun case -> Alcotest.check outcome name expected (run case))

(* Runs. *)

let a_case_whose_output_matches_passes () =
  check_run "the case passes" (Ok [])
    (case_files ~stdout:"one\ntwo\n" ~stderr:"oops" ~exit:"3\n"
       "printf 'one\\ntwo\\n'; printf oops >&2; exit 3")

let a_different_exit_code_fails_the_case () =
  check_run "the exit file differs"
    (Error
       (Fixture.Differs
          [
            {
              file = "exit";
              line = 1;
              expected = Some "0\n";
              actual = Some "3\n";
            };
          ]))
    (case_files "exit 3")

let a_difference_names_the_first_line_that_differs () =
  check_run "line 2 of stdout differs"
    (Error
       (Fixture.Differs
          [
            {
              file = "stdout";
              line = 2;
              expected = Some "b\n";
              actual = Some "x\n";
            };
          ]))
    (case_files ~stdout:"a\nb\nc\n" "printf 'a\\nx\\nc\\n'")

let standard_error_is_compared () =
  check_run "line 1 of stderr differs"
    (Error
       (Fixture.Differs
          [
            {
              file = "stderr";
              line = 1;
              expected = Some "warn\n";
              actual = Some "fail\n";
            };
          ]))
    (case_files ~stderr:"warn\n" "echo fail >&2")

let a_missing_last_line_feed_is_a_difference () =
  check_run "line 1 differs in its line feed"
    (Error
       (Fixture.Differs
          [
            {
              file = "stdout";
              line = 1;
              expected = Some "a\n";
              actual = Some "a";
            };
          ]))
    (case_files ~stdout:"a\n" "printf a")

let a_shorter_output_has_no_line_where_the_expected_file_has_one () =
  check_run "line 2 is missing from the output"
    (Error
       (Fixture.Differs
          [
            { file = "stdout"; line = 2; expected = Some "b\n"; actual = None };
          ]))
    (case_files ~stdout:"a\nb\n" "echo a")

let every_file_that_differs_is_named () =
  with_case (case_files ~stdout:"a\n" ~stderr:"b\n" ~exit:"0\n" "exit 1")
    (fun case ->
      match run case with
      | Error (Fixture.Differs differences) ->
          Alcotest.(check (list string))
            "the three files differ, in order"
            [ "stdout"; "stderr"; "exit" ]
            (List.map (fun { Fixture.file; _ } -> file) differences)
      | _ -> Alcotest.fail "the run gave no difference")

let a_difference_shows_the_case_the_file_and_both_lines () =
  Alcotest.(check string)
    "the message"
    "case parse-tree: the output differs from the expected files.\n\
     expected/stdout, line 2:\n\
    \  expected: \"b\\n\"\n\
    \  actual:   (no such line)\n\
     To accept the output, run the suite with SINTER_PROMOTE=1."
    (Fixture.message ~case:"parse-tree"
       (Fixture.Differs
          [
            { file = "stdout"; line = 2; expected = Some "b\n"; actual = None };
          ]))

let standard_input_reaches_the_run () =
  check_run "the run reads the stdin file" (Ok [])
    (("stdin", "in\n") :: case_files ~stdout:"in\n" "cat")

let without_a_stdin_file_standard_input_is_empty () =
  check_run "the run reads nothing" (Ok [])
    (case_files ~stdout:"end\n" "cat; echo end")

let each_line_of_args_is_one_argument () =
  check_run "the run gets three arguments, one of them empty" (Ok [])
    (("args", "-c\nprintf '[%s]' \"$@\"\nsh\na b\n\nc\n")
    :: List.remove_assoc "args" (case_files ~stdout:"[a b][][c]" ""))

let the_run_starts_in_a_copy_of_the_tree () =
  check_run "the run reads the files of the tree" (Ok [])
    ([ ("tree/f", "one\n"); ("tree/sub/g", "two\n") ]
    @ case_files ~stdout:"one\ntwo\n" "cat f sub/g")

let the_copy_leaves_out_gitkeep_and_keeps_its_folder () =
  check_run "the copy holds the folder and no .gitkeep" (Ok [])
    ([ ("tree/.gitkeep", ""); ("tree/empty/.gitkeep", "") ]
    @ case_files ~stdout:"empty\n" "ls -A; ls -A empty")

let the_working_folder_shows_as_root () =
  check_run "the working folder prints as <root>" (Ok [])
    (case_files ~stdout:"<root>\n" ~stderr:"<root>/f\n"
       "pwd; echo \"$PWD/f\" >&2")

let the_run_gets_the_fixed_variables () =
  let names =
    [ "NO_COLOR"; "GIT_CONFIG_GLOBAL"; "GIT_CONFIG_NOSYSTEM"; "PWD" ]
  in
  let program =
    "BEGIN { "
    ^ String.concat "; "
        (List.map (Printf.sprintf "print ENVIRON[\"%s\"]") names)
    ^ " }"
  in
  with_case
    (("args", program ^ "\n")
    :: List.remove_assoc "args"
         (case_files ~stdout:"1\n/dev/null\n1\n<root>\n" ""))
    (fun case ->
      Alcotest.check outcome "awk prints the fixed values" (Ok [])
        (Fixture.run ~binary:"/usr/bin/awk" Fixture.Compare case))

let the_run_writes_coverage_beside_the_suite () =
  let expected =
    match Sys.getenv_opt "BISECT_FILE" with
    | Some place -> place
    | None -> Filename.concat (Sys.getcwd ()) "bisect"
  in
  with_case
    (("args", "BEGIN { print ENVIRON[\"BISECT_FILE\"] }\n")
    :: List.remove_assoc "args" (case_files ~stdout:(expected ^ "\n") ""))
    (fun case ->
      Alcotest.check outcome "awk prints the place of the coverage counts"
        (Ok [])
        (Fixture.run ~binary:"/usr/bin/awk" Fixture.Compare case))

let a_run_leaves_the_case_unchanged () =
  with_case (("tree/f", "x") :: case_files "rm f; echo y > g") (fun case ->
      Alcotest.check outcome "the run passes" (Ok []) (run case);
      Alcotest.(check (list string))
        "the tree of the case holds what it held" [ "f" ]
        (Array.to_list (Sys.readdir (Filename.concat case "tree"))))

let a_run_removes_its_temporary_folder () =
  Fixture.with_temporary_folder (fun folder ->
      let temporary = Filename.concat folder "tmp" in
      let case = Filename.concat folder "case" in
      write_files case (case_files "echo x > f");
      Sys.mkdir temporary 0o755;
      let previous = Filename.get_temp_dir_name () in
      Fun.protect
        ~finally:(fun () -> Filename.set_temp_dir_name previous)
        (fun () ->
          Filename.set_temp_dir_name temporary;
          Alcotest.check outcome "the run passes" (Ok []) (run case));
      Alcotest.(check (array string))
        "the temporary folder is empty" [||] (Sys.readdir temporary))

let a_run_past_its_bound_is_killed () =
  with_case (case_files "exec sleep 5") (fun case ->
      Alcotest.check outcome "the run did not end"
        (Error (Fixture.Did_not_end 0.02)) (run ~bound:0.02 case))

let a_run_that_a_signal_ends_fails_the_case () =
  check_run "a signal ended the run"
    (Error (Fixture.Ended_by_signal Sys.sigkill)) (case_files "kill -9 $$")

(* Entries. *)

let an_unknown_entry_fails_the_case () =
  check_run "argz is unknown" (Error (Fixture.Unknown_entry "argz"))
    (("argz", "") :: case_files "true")

let an_unknown_entry_in_expected_fails_the_case () =
  check_run "expected/out is unknown"
    (Error (Fixture.Unknown_entry "expected/out"))
    (("expected/out", "") :: case_files "true")

let a_missing_entry_fails_the_case () =
  List.iter
    (fun entry ->
      let files =
        List.filter
          (fun (path, _) ->
            not
              (String.equal path entry
              || String.starts_with ~prefix:(entry ^ "/") path))
          (case_files "true")
      in
      let entry =
        if String.ends_with ~suffix:"/" entry then
          String.sub entry 0 (String.length entry - 1)
        else entry
      in
      check_run
        (Printf.sprintf "%s is missing" entry)
        (Error (Fixture.Missing_entry entry)) files)
    [ "args"; "tree/"; "expected/stdout"; "expected/stderr"; "expected/exit" ]

let a_missing_expected_folder_fails_the_case () =
  check_run "expected/stdout is missing"
    (Error (Fixture.Missing_entry "expected/stdout"))
    [ ("args", script "true"); ("tree/", "") ]

let a_reserved_entry_fails_the_case () =
  List.iter
    (fun (entry, files) ->
      check_run
        (Printf.sprintf "%s is reserved" entry)
        (Error (Fixture.Reserved_entry entry))
        (files @ case_files "true"))
    [
      ("ledger.jsonl", [ ("ledger.jsonl", "") ]);
      ("evidence", [ ("evidence/", "") ]);
    ]

let a_reserved_entry_says_the_harness_does_not_read_it_yet () =
  Alcotest.(check string)
    "the message"
    "case scan: ledger.jsonl is a reserved name. The harness does not read it \
     yet, so the case cannot use it. Remove it."
    (Fixture.message ~case:"scan" (Fixture.Reserved_entry "ledger.jsonl"))

let an_entry_of_the_wrong_kind_fails_the_case () =
  check_run "tree must be a folder"
    (Error (Fixture.Wrong_kind { entry = "tree"; folder = true }))
    (("tree", "")
    :: List.filter (fun (path, _) -> path <> "tree/") (case_files "true"));
  check_run "args must be a file"
    (Error (Fixture.Wrong_kind { entry = "args"; folder = false }))
    (("args/", "")
    :: List.filter (fun (path, _) -> path <> "args") (case_files "true"))

let a_relative_binary_is_refused () =
  with_case (case_files "true") (fun case ->
      Alcotest.check_raises "the run refuses the binary"
        (Invalid_argument "Fixture.run: the binary is not an absolute path")
        (fun () -> ignore (Fixture.run ~binary:"sh" Fixture.Compare case)))

let a_case_that_is_not_a_folder_fails () =
  Fixture.with_temporary_folder (fun folder ->
      let case = Filename.concat folder "case" in
      write_files folder [ ("case", "") ];
      Alcotest.check outcome "the case is not a folder"
        (Error Fixture.Not_a_folder) (run case))

(* Promotion. *)

let promoted = script "echo out; echo err >&2; exit 4"

let promotion_writes_the_output_into_the_expected_files () =
  Fixture.with_temporary_folder (fun folder ->
      let case = Filename.concat folder "case" in
      write_files case [ ("args", promoted); ("tree/", "") ];
      let file name = Filename.concat case ("expected/" ^ name) in
      Alcotest.check outcome "the promotion writes the three files"
        (Ok [ file "stdout"; file "stderr"; file "exit" ])
        (run ~mode:(Fixture.Promote_into folder) case);
      Alcotest.(check (list string))
        "the files hold the output"
        [ "out\n"; "err\n"; "4\n" ]
        (List.map (fun name -> read (file name)) [ "stdout"; "stderr"; "exit" ]);
      Alcotest.check outcome "a comparison then passes" (Ok []) (run case))

let a_second_promotion_writes_nothing () =
  Fixture.with_temporary_folder (fun folder ->
      let case = Filename.concat folder "case" in
      write_files case [ ("args", promoted); ("tree/", "") ];
      let mode = Fixture.Promote_into folder in
      ignore (run ~mode case);
      Alcotest.check outcome "the second promotion writes no file" (Ok [])
        (run ~mode case))

let promotion_writes_only_the_files_that_differ () =
  Fixture.with_temporary_folder (fun folder ->
      let case = Filename.concat folder "case" in
      write_files case
        [
          ("args", promoted);
          ("tree/", "");
          ("expected/stdout", "out\n");
          ("expected/stderr", "err\n");
          ("expected/exit", "0\n");
        ];
      Alcotest.check outcome "the promotion writes the exit file"
        (Ok [ Filename.concat case "expected/exit" ])
        (run ~mode:(Fixture.Promote_into folder) case))

let promotion_writes_into_the_source_folder_and_not_into_the_case () =
  Fixture.with_temporary_folder (fun folder ->
      let build = Filename.concat folder "build" in
      let source = Filename.concat folder "source" in
      let files = [ ("args", promoted); ("tree/", "") ] in
      write_files (Filename.concat build "case") files;
      write_files (Filename.concat source "case") files;
      let written = Filename.concat source "case/expected/stdout" in
      ignore
        (run ~mode:(Fixture.Promote_into source) (Filename.concat build "case"));
      Alcotest.(check string)
        "the source folder holds the output" "out\n" (read written);
      Alcotest.(check bool)
        "the case holds no expected folder" false
        (Sys.file_exists (Filename.concat build "case/expected")))

let promotion_still_fails_an_unknown_entry () =
  Fixture.with_temporary_folder (fun folder ->
      let case = Filename.concat folder "case" in
      write_files case [ ("args", promoted); ("tree/", ""); ("argz", "") ];
      Alcotest.check outcome "argz is unknown"
        (Error (Fixture.Unknown_entry "argz"))
        (run ~mode:(Fixture.Promote_into folder) case))

let a_failed_run_is_never_promoted () =
  Fixture.with_temporary_folder (fun folder ->
      let case = Filename.concat folder "case" in
      write_files case [ ("args", script "kill -9 $$"); ("tree/", "") ];
      ignore (run ~mode:(Fixture.Promote_into folder) case);
      Alcotest.(check bool)
        "the case holds no expected folder" false
        (Sys.file_exists (Filename.concat case "expected")))

let promotion_needs_the_variable_set_to_1 () =
  let mode =
    Alcotest.testable
      (fun formatter -> function
        | Fixture.Compare -> Format.pp_print_string formatter "Compare"
        | Fixture.Promote_into folder ->
            Format.fprintf formatter "Promote_into %S" folder)
      ( = )
  in
  let check name expected promote source_root =
    Alcotest.(check (result mode string))
      name expected
      (Fixture.mode_of_environment ~promote ~source_root)
  in
  check "1 promotes into the cases of the source tree"
    (Ok (Fixture.Promote_into "/source/test/cases")) (Some "1") (Some "/source");
  check "no value compares" (Ok Fixture.Compare) None (Some "/source");
  check "0 compares" (Ok Fixture.Compare) (Some "0") (Some "/source");
  match Fixture.mode_of_environment ~promote:(Some "1") ~source_root:None with
  | Ok _ -> Alcotest.fail "1 without a source tree is not an error"
  | Error _ -> ()

(* Discovery. *)

let each_entry_of_the_folder_of_cases_is_one_test () =
  Fixture.with_temporary_folder (fun folder ->
      write_files folder [ ("b-case/", ""); ("a-case/", ""); ("stray", "") ];
      Alcotest.(check (list string))
        "one test for each entry, in the order of the names"
        [ "a-case"; "b-case"; "stray" ]
        (List.map
           (fun (name, _, _) -> name)
           (Fixture.tests ~binary:sh Fixture.Compare
              ~on_write:(fun _ -> ())
              folder)))

let a_folder_of_cases_that_cannot_be_read_is_one_failing_test () =
  Fixture.with_temporary_folder (fun folder ->
      match
        Fixture.tests ~binary:sh Fixture.Compare
          ~on_write:(fun _ -> ())
          (Filename.concat folder "missing")
      with
      | [ (name, _, test) ] -> (
          Alcotest.(check string) "the test is named cases" "cases" name;
          match test () with
          | () -> Alcotest.fail "the test passed"
          | exception _ -> ())
      | tests -> Alcotest.failf "%d tests instead of one" (List.length tests))

let a_failed_git_command_shows_its_arguments_and_output () =
  Alcotest.(check string)
    "the message" "case diff: git log --oneline failed:\nfatal: no commit\n"
    (Fixture.message ~case:"diff"
       (Fixture.Git_failed
          { arguments = [ "log"; "--oneline" ]; output = "fatal: no commit\n" }))

(* Diff cases. *)

let base =
  [ ("base/gone", "gone\n"); ("base/kept", "old\n"); ("base/same", "same\n") ]

let tree =
  [ ("tree/kept", "new\n"); ("tree/same", "same\n"); ("tree/added", "added\n") ]

(* Calls [f] with a repository built from [base] and [tree]. *)
let with_diff_repository f =
  Fixture.with_temporary_folder (fun folder ->
      write_files folder (base @ tree);
      match
        Fixture.with_repository
          ~base:(Filename.concat folder "base")
          ~tree:(Filename.concat folder "tree")
          f
      with
      | Ok () -> ()
      | Error error -> Alcotest.fail (Fixture.message ~case:"diff" error))

let git repository arguments =
  match Fixture.git repository arguments with
  | Ok output -> output
  | Error error -> Alcotest.fail (Fixture.message ~case:"diff" error)

let a_diff_case_commits_base_and_leaves_tree_uncommitted () =
  with_diff_repository (fun repository ->
      Alcotest.(check string)
        "the commit holds the files of base" "gone\nkept\nsame\n"
        (git repository [ "ls-tree"; "-r"; "--name-only"; "HEAD" ]);
      Alcotest.(check string)
        "the commit holds the text of base" "old\n"
        (git repository [ "show"; "HEAD:kept" ]);
      Alcotest.(check string)
        "the working tree holds a deleted, a changed, and an untracked file"
        " D gone\n M kept\n?? added\n"
        (git repository [ "status"; "--porcelain" ]);
      Alcotest.(check string)
        "the working tree holds the text of tree" "new\n"
        (read (Filename.concat (Fixture.root repository) "kept"));
      Alcotest.(check string)
        "the branch is main" "refs/heads/main\n"
        (git repository [ "symbolic-ref"; "HEAD" ]);
      (match Fixture.git repository [ "no-such-command" ] with
      | Error (Fixture.Git_failed { arguments; _ }) ->
          Alcotest.(check (list string))
            "a failed git command gives its arguments" [ "no-such-command" ]
            arguments
      | _ -> Alcotest.fail "a failed git command gave no Git_failed");
      (* The id covers the files, the parents, the author, the
         committer, the dates, and the message, and nothing of the
         machine. *)
      Alcotest.(check string)
        "the commit has a fixed id" "b56f0ae3aaed63f1debb346e4a8955635c4d2aa4\n"
        (git repository [ "rev-parse"; "HEAD" ]))

let a_diff_case_runs_at_the_root_of_the_repository () =
  check_run "the run starts beside .git, in the files of tree" (Ok [])
    (base @ tree
    @ List.remove_assoc "tree/"
        (case_files ~stdout:"<root>\n.git\nadded\nkept\nsame\n"
           "pwd; LC_ALL=C ls -A"))

let tests =
  [
    Alcotest.test_case "a case whose output matches passes" `Quick
      a_case_whose_output_matches_passes;
    Alcotest.test_case "a different exit code fails the case" `Quick
      a_different_exit_code_fails_the_case;
    Alcotest.test_case "a difference names the first line that differs" `Quick
      a_difference_names_the_first_line_that_differs;
    Alcotest.test_case "standard error is compared" `Quick
      standard_error_is_compared;
    Alcotest.test_case "a missing last line feed is a difference" `Quick
      a_missing_last_line_feed_is_a_difference;
    Alcotest.test_case
      "a shorter output has no line where the expected file has one" `Quick
      a_shorter_output_has_no_line_where_the_expected_file_has_one;
    Alcotest.test_case "every file that differs is named" `Quick
      every_file_that_differs_is_named;
    Alcotest.test_case "a difference shows the case, the file, and both lines"
      `Quick a_difference_shows_the_case_the_file_and_both_lines;
    Alcotest.test_case "standard input reaches the run" `Quick
      standard_input_reaches_the_run;
    Alcotest.test_case "without a stdin file, standard input is empty" `Quick
      without_a_stdin_file_standard_input_is_empty;
    Alcotest.test_case "each line of args is one argument" `Quick
      each_line_of_args_is_one_argument;
    Alcotest.test_case "the run starts in a copy of the tree" `Quick
      the_run_starts_in_a_copy_of_the_tree;
    Alcotest.test_case "the copy leaves out .gitkeep and keeps its folder"
      `Quick the_copy_leaves_out_gitkeep_and_keeps_its_folder;
    Alcotest.test_case "the working folder shows as <root>" `Quick
      the_working_folder_shows_as_root;
    Alcotest.test_case "the run gets the fixed variables" `Quick
      the_run_gets_the_fixed_variables;
    Alcotest.test_case "the run writes coverage beside the suite" `Quick
      the_run_writes_coverage_beside_the_suite;
    Alcotest.test_case "a run leaves the case unchanged" `Quick
      a_run_leaves_the_case_unchanged;
    Alcotest.test_case "a run removes its temporary folder" `Quick
      a_run_removes_its_temporary_folder;
    Alcotest.test_case "a run past its bound is killed" `Quick
      a_run_past_its_bound_is_killed;
    Alcotest.test_case "a run that a signal ends fails the case" `Quick
      a_run_that_a_signal_ends_fails_the_case;
    Alcotest.test_case "an unknown entry fails the case" `Quick
      an_unknown_entry_fails_the_case;
    Alcotest.test_case "an unknown entry in expected fails the case" `Quick
      an_unknown_entry_in_expected_fails_the_case;
    Alcotest.test_case "a missing entry fails the case" `Quick
      a_missing_entry_fails_the_case;
    Alcotest.test_case "a missing expected folder fails the case" `Quick
      a_missing_expected_folder_fails_the_case;
    Alcotest.test_case "a reserved entry fails the case" `Quick
      a_reserved_entry_fails_the_case;
    Alcotest.test_case "a reserved entry says the harness does not read it yet"
      `Quick a_reserved_entry_says_the_harness_does_not_read_it_yet;
    Alcotest.test_case "an entry of the wrong kind fails the case" `Quick
      an_entry_of_the_wrong_kind_fails_the_case;
    Alcotest.test_case "a relative binary is refused" `Quick
      a_relative_binary_is_refused;
    Alcotest.test_case "a case that is not a folder fails" `Quick
      a_case_that_is_not_a_folder_fails;
    Alcotest.test_case "promotion writes the output into the expected files"
      `Quick promotion_writes_the_output_into_the_expected_files;
    Alcotest.test_case "a second promotion writes nothing" `Quick
      a_second_promotion_writes_nothing;
    Alcotest.test_case "promotion writes only the files that differ" `Quick
      promotion_writes_only_the_files_that_differ;
    Alcotest.test_case
      "promotion writes into the source folder and not into the case" `Quick
      promotion_writes_into_the_source_folder_and_not_into_the_case;
    Alcotest.test_case "promotion still fails an unknown entry" `Quick
      promotion_still_fails_an_unknown_entry;
    Alcotest.test_case "a failed run is never promoted" `Quick
      a_failed_run_is_never_promoted;
    Alcotest.test_case "promotion needs the variable set to 1" `Quick
      promotion_needs_the_variable_set_to_1;
    Alcotest.test_case "each entry of the folder of cases is one test" `Quick
      each_entry_of_the_folder_of_cases_is_one_test;
    Alcotest.test_case
      "a folder of cases that cannot be read is one failing test" `Quick
      a_folder_of_cases_that_cannot_be_read_is_one_failing_test;
    Alcotest.test_case "a failed git command shows its arguments and output"
      `Quick a_failed_git_command_shows_its_arguments_and_output;
    Alcotest.test_case "a diff case commits base and leaves tree uncommitted"
      `Quick a_diff_case_commits_base_and_leaves_tree_uncommitted;
    Alcotest.test_case "a diff case runs at the root of the repository" `Quick
      a_diff_case_runs_at_the_root_of_the_repository;
  ]
