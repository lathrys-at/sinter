(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let changes =
  Alcotest.testable
    (fun formatter value ->
      Format.pp_print_string formatter (Generators.print_changes value))
    ( = )

let header =
  Alcotest.testable
    (fun formatter (h : Git.Decode.header) ->
      Format.fprintf formatter "-%d,%d +%d,%d" h.old_start h.old_count
        h.new_start h.new_count)
    ( = )

let decoded what = Alcotest.(check (result what string))
let is_error = function Ok _ -> false | Error _ -> true
let refused name result = Alcotest.(check bool) name true (is_error result)

(* [fails_with message result] checks that [result] is the error
   [message]. A test of the message tells two errors apart that a test
   of the kind alone cannot. *)
let fails_with message result =
  Alcotest.(check (option string))
    "the error" (Some message)
    (match result with Ok _ -> None | Error text -> Some text)

(* Hunk headers. *)

let a_header_gives_both_ranges () =
  decoded header "the four numbers"
    (Ok { old_start = 12; old_count = 3; new_start = 14; new_count = 0 })
    (Git.Decode.hunk_header "@@ -12,3 +14,0 @@")

let an_omitted_count_is_one () =
  decoded header "both counts are 1"
    (Ok { old_start = 7; old_count = 1; new_start = 9; new_count = 1 })
    (Git.Decode.hunk_header "@@ -7 +9 @@")

let the_text_after_a_header_is_ignored () =
  decoded header "the function text does not count"
    (Ok { old_start = 1; old_count = 2; new_start = 1; new_count = 2 })
    (Git.Decode.hunk_header "@@ -1,2 +1,2 @@ let f x = 9")

let a_number_of_fifteen_digits_is_read () =
  decoded header "the largest number"
    (Ok
       {
         old_start = 999999999999999;
         old_count = 1;
         new_start = 9;
         new_count = 0;
       })
    (Git.Decode.hunk_header "@@ -999999999999999 +9,0 @@")

let a_number_of_sixteen_digits_is_refused () =
  refused "16 digits" (Git.Decode.hunk_header "@@ -1 +1000000000000000 @@")

let a_header_that_is_cut_short_is_refused () =
  List.iter
    (fun text -> refused text (Git.Decode.hunk_header text))
    [ ""; "@@"; "@@ -"; "@@ -1"; "@@ -1,"; "@@ -1 +"; "@@ -1 +2"; "@@ -1 +2 @" ]

let a_header_with_a_wrong_mark_is_refused () =
  List.iter
    (fun text -> refused text (Git.Decode.hunk_header text))
    [
      "@@ +1 -2 @@";
      "@@ -1 -2 @@";
      "@@ -a +2 @@";
      "@@ -1,b +2 @@";
      "@@ -1 +2,x @@";
      "@@ --1 +2 @@";
      "@@ -0x1 +2 @@";
      "@@ -1_0 +2 @@";
      "@@ -1 +2 @@@";
      "@@ -1  +2 @@";
    ]

let a_side_with_lines_that_starts_at_line_0_is_refused () =
  refused "old side" (Git.Decode.hunk_header "@@ -0,1 +1 @@");
  refused "new side" (Git.Decode.hunk_header "@@ -1 +0,2 @@");
  refused "new side of one line" (Git.Decode.hunk_header "@@ -1 +0 @@")

let a_header_names_what_is_missing () =
  fails_with "\"@@ -1\" has no \" +\" at offset 5"
    (Git.Decode.hunk_header "@@ -1")

let a_header_names_a_missing_count () =
  fails_with "\"@@ -1,\" has no number at offset 6"
    (Git.Decode.hunk_header "@@ -1,")

let a_side_with_no_lines_can_start_at_line_0 () =
  decoded header "both sides empty at line 0"
    (Ok { old_start = 0; old_count = 0; new_start = 0; new_count = 0 })
    (Git.Decode.hunk_header "@@ -0,0 +0,0 @@")

let hunk_header_reads_what_git_writes =
  property ~name:"hunk_header gives back the numbers of a header"
    ~print:Generators.print_hunk_header Generators.hunk_header
    (fun (text, expected) -> Git.Decode.hunk_header text = Ok expected)

let hunk_header_is_total =
  property ~count:1000
    ~name:"hunk_header gives a header or an error for a damaged header"
    ~print:(fun text -> Printf.sprintf "%S" text)
    Generators.damaged_hunk_header
    (fun text ->
      match Git.Decode.hunk_header text with Ok _ | Error _ -> true)

(* Refs. *)

let entries =
  Alcotest.testable
    (fun formatter value ->
      Format.pp_print_string formatter
        (Generators.print_refs_output ("", value)))
    ( = )

let commit_id_of digit = String.make 40 digit

let refs_reads_each_field () =
  decoded entries "two refs"
    (Ok
       [
         {
           refname = "refs/heads/main";
           kind = Git.Decode.Commit;
           id = commit_id_of 'a';
           upstream = "refs/remotes/origin/main";
         };
         {
           refname = "refs/remotes/origin/main";
           kind = Git.Decode.Tag;
           id = String.make 64 'b';
           upstream = "";
         };
       ])
    (Git.Decode.refs
       ("refs/heads/main\000commit\000" ^ commit_id_of 'a'
      ^ "\000refs/remotes/origin/main\nrefs/remotes/origin/main\000tag\000"
      ^ String.make 64 'b' ^ "\000\n"))

let refs_of_no_output_is_empty () =
  decoded entries "no ref" (Ok []) (Git.Decode.refs "")

let refs_refuses_a_bad_record () =
  List.iter
    (fun output -> refused output (Git.Decode.refs output))
    [
      "refs/heads/a\000commit\000" ^ commit_id_of 'a' ^ "\000";
      "refs/heads/a\000commit\000" ^ commit_id_of 'a' ^ "\n";
      "refs/heads/a\000commit\000" ^ commit_id_of 'a' ^ "\000\000\n";
      "\000commit\000" ^ commit_id_of 'a' ^ "\000\n";
      "refs/heads/a\000commit\000" ^ String.make 39 'a' ^ "\000\n";
      "refs/heads/a\000branch\000" ^ commit_id_of 'a' ^ "\000\n";
      "\n";
    ]

let refs_reads_what_git_writes =
  property ~name:"refs gives back the refs of an output of git for-each-ref"
    ~print:Generators.print_refs_output Generators.refs_output
    (fun (output, expected) -> Git.Decode.refs output = Ok expected)

let refs_is_total =
  property ~name:"refs gives refs or an error for a damaged output"
    ~print:(fun text -> Printf.sprintf "%S" text)
    Generators.damaged_refs_output
    (fun output -> match Git.Decode.refs output with Ok _ | Error _ -> true)

(* Diff output. *)

let lines texts = String.concat "" (List.map (fun line -> line ^ "\n") texts)
let section path rest = ("diff --git a/" ^ path ^ " b/" ^ path) :: rest
let hunk line eline added removed : Git.hunk = { line; eline; added; removed }

let empty_output_has_no_change () =
  decoded changes "no section" (Ok []) (Git.Decode.diff "")

let output_without_a_last_line_feed_is_refused () =
  refused "no line feed" (Git.Decode.diff "diff --git a/f b/f\nold mode 100644")

let a_changed_line_is_one_hunk () =
  decoded changes "line 3 changed"
    (Ok [ ("f", Git.Modified [ hunk 3 3 1 1 ]) ])
    (Git.Decode.diff (lines (section "f" [ "@@ -3 +3 @@"; "-a"; "+b" ])))

let added_lines_span_their_new_lines () =
  decoded changes "lines 4 to 6 added"
    (Ok [ ("f", Git.Modified [ hunk 4 6 3 0 ]) ])
    (Git.Decode.diff
       (lines (section "f" [ "@@ -3,0 +4,3 @@"; "+a"; "+b"; "+c" ])))

let a_pure_deletion_is_at_the_line_after_it () =
  decoded changes "lines 6 and 7 deleted after new line 5"
    (Ok [ ("f", Git.Modified [ hunk 6 6 0 2 ]) ])
    (Git.Decode.diff (lines (section "f" [ "@@ -6,2 +5,0 @@"; "-a"; "-b" ])))

let a_deletion_at_the_start_is_at_line_1 () =
  decoded changes "lines 1 and 2 deleted"
    (Ok [ ("f", Git.Modified [ hunk 1 1 0 2 ]) ])
    (Git.Decode.diff (lines (section "f" [ "@@ -1,2 +0,0 @@"; "-a"; "-b" ])))

let a_deletion_at_the_end_is_past_the_last_line () =
  decoded changes "the last two lines of a file of 3 deleted"
    (Ok [ ("f", Git.Modified [ hunk 2 2 0 2 ]) ])
    (Git.Decode.diff (lines (section "f" [ "@@ -2,2 +1,0 @@"; "-b"; "-c" ])))

let the_hunks_of_a_file_keep_their_order () =
  decoded changes "two hunks"
    (Ok [ ("f", Git.Modified [ hunk 2 2 1 1; hunk 9 10 2 0 ]) ])
    (Git.Decode.diff
       (lines
          (section "f"
             [ "@@ -2 +2 @@"; "-a"; "+b"; "@@ -8,0 +9,2 @@"; "+c"; "+d" ])))

let a_binary_file_is_binary () =
  decoded changes "binary"
    (Ok [ ("f", Git.Binary) ])
    (Git.Decode.diff
       (lines
          (section "f"
             [
               "index 1234567..89abcde 100644";
               "Binary files a/f and b/f differ";
             ])))

let a_mode_change_alone_has_no_hunk () =
  decoded changes "mode change"
    (Ok [ ("f", Git.Modified []) ])
    (Git.Decode.diff
       (lines (section "f" [ "old mode 100644"; "new mode 100755" ])))

let a_section_with_no_line_after_its_header_has_no_hunk () =
  decoded changes "two bare sections"
    (Ok [ ("e", Git.Modified []); ("f", Git.Modified []) ])
    (Git.Decode.diff (lines (section "f" [] @ section "e" [])))

let the_marker_of_a_missing_line_feed_is_skipped () =
  decoded changes "one run despite the markers"
    (Ok [ ("f", Git.Modified [ hunk 1 2 2 1 ]) ])
    (Git.Decode.diff
       (lines
          (section "f"
             [
               "@@ -1 +1,2 @@";
               "-a";
               "\\ No newline at end of file";
               "+a";
               "+b";
               "\\ No newline at end of file";
             ])))

let context_lines_end_a_run () =
  decoded changes "two runs in one hunk"
    (Ok [ ("f", Git.Modified [ hunk 2 2 1 1; hunk 4 4 0 1 ]) ])
    (Git.Decode.diff
       (lines (section "f" [ "@@ -1,4 +1,3 @@"; " a"; "-b"; "+B"; " c"; "-d" ])))

let an_empty_line_is_a_context_line () =
  decoded changes "the empty line ends the first run"
    (Ok [ ("f", Git.Modified [ hunk 1 1 0 1; hunk 2 2 1 0 ]) ])
    (Git.Decode.diff
       (lines (section "f" [ "@@ -1,2 +1,2 @@"; "-a"; ""; "+b" ])))

let two_sections_of_one_path_are_joined () =
  decoded changes "a type change"
    (Ok [ ("f", Git.Modified [ hunk 1 1 0 2; hunk 1 1 1 0 ]) ])
    (Git.Decode.diff
       (lines
          (section "f"
             [ "deleted file mode 100644"; "@@ -1,2 +0,0 @@"; "-a"; "-b" ]
          @ section "f" [ "new file mode 120000"; "@@ -0,0 +1 @@"; "+t" ])))

let a_binary_section_makes_a_joined_path_binary () =
  decoded changes "binary wins"
    (Ok [ ("f", Git.Binary) ])
    (Git.Decode.diff
       (lines
          (section "f" [ "@@ -1 +0,0 @@"; "-a" ]
          @ section "f" [ "Binary files /dev/null and b/f differ" ])))

let the_paths_are_sorted_by_byte_order () =
  decoded changes "sorted"
    (Ok
       [
         ("B", Git.Modified []);
         ("a", Git.Modified []);
         ("a b", Git.Modified []);
         ("\xc3\xa9", Git.Modified []);
       ])
    (Git.Decode.diff
       (lines
          (section "a b" [] @ section "\xc3\xa9" [] @ section "a" []
         @ section "B" [])))

let a_quoted_name_is_unquoted () =
  decoded changes "every escape"
    (Ok [ ("\007\b\t\n\011\012\r\"\\\xc3\xa9\x7f\x1b x", Git.Modified []) ])
    (Git.Decode.diff
       (lines
          [
            "diff --git \"a/\\a\\b\\t\\n\\v\\f\\r\\\"\\\\\\303\\251\\177\\033 \
             x\" \"b/\\a\\b\\t\\n\\v\\f\\r\\\"\\\\\\303\\251\\177\\033 x\"";
          ]))

let a_name_with_spaces_and_b_slash_is_read () =
  decoded changes "the path a b/a"
    (Ok [ ("a b/a", Git.Modified []) ])
    (Git.Decode.diff (lines (section "a b/a" [])))

let a_one_byte_name_is_read () =
  decoded changes "the path x"
    (Ok [ ("x", Git.Modified []) ])
    (Git.Decode.diff "diff --git a/x b/x\n")

let a_bad_git_line_is_refused () =
  List.iter
    (fun line -> refused line (Git.Decode.diff (line ^ "\n")))
    [
      "diff --git";
      "diff --git ";
      "diff --git a/ b/";
      "diff --git \"a/\" \"b/\"";
      "diff --git a/x b/y";
      "diff --git a/xy b/x";
      "diff --git x/x b/x";
      "diff --git a/x c/x";
      "diff --git \"a/x\" b/x";
      "diff --git \"a/x\" \"b/y\"";
      "diff --git \"a/x\" \"b/x\" ";
      "diff --git \"a/x\" ";
      "diff --git \"a/\\03";
      "diff --git \"a/\\0";
      "diff --git \"a/x\"\"b/x\"";
      "diff --git \"x\" \"b/x\"";
      "diff --git \"a/x\" \"x\"";
      "diff --git \"a/x";
      "diff --git \"a/x\\";
      "diff --git \"a/\\q\" \"b/\\q\"";
      "diff --git \"a/\\4\" \"b/\\4\"";
      "diff --git \"a/\\400\" \"b/\\400\"";
      "diff --git \"a/\\08\" \"b/\\08\"";
      "diff --git \"a/\\081\" \"b/\\081\"";
      "diff --git \"a/\\018\" \"b/\\018\"";
      "diff --git \"a/\\00/\" \"b/\\00/\"";
      "diff --git \"a/\\0\" \"b/\\0\"";
      "diff -git a/x b/x";
      "index 1234567..89abcde";
    ]

let a_hunk_that_ends_early_is_refused () =
  refused "one line missing"
    (Git.Decode.diff (lines (section "f" [ "@@ -1,2 +1 @@"; "-a"; "+b" ])));
  refused "a marker only"
    (Git.Decode.diff
       (lines
          (section "f" [ "@@ -1 +1 @@"; "-a"; "\\ No newline at end of file" ])))

let a_line_that_does_not_fit_its_hunk_is_refused () =
  List.iter
    (fun (body, message) ->
      fails_with message (Git.Decode.diff (lines (section "f" body))))
    [
      ( [ "@@ -1 +1 @@"; "-a"; "-b"; "+c" ],
        "the line \"-b\" does not fit the hunk -1,1 +1,1" );
      ( [ "@@ -1 +1,0 @@"; "+a" ],
        "the line \"+a\" does not fit the hunk -1,1 +1,0" );
      ( [ "@@ -1,0 +1 @@"; " a" ],
        "the line \" a\" does not fit the hunk -1,0 +1,1" );
      ( [ "@@ -1 +1,0 @@"; " a" ],
        "the line \" a\" does not fit the hunk -1,1 +1,0" );
      ( [ "@@ -1 +1 @@"; "a"; "+b" ],
        "the line \"a\" does not fit the hunk -1,1 +1,1" );
      ( [ "@@ -1 +1 @@"; "-a"; "+b"; "index 1..2" ],
        "the line \"index 1..2\" follows a hunk" );
      ([ "@@ -1 +1 @"; "-a"; "+b" ], "\"@@ -1 +1 @\" has no \" @@\" at offset 8");
    ]

let output_that_does_not_start_with_a_section_is_refused () =
  refused "a hunk first" (Git.Decode.diff (lines [ "@@ -1 +1 @@"; "-a"; "+b" ]))

let diff_reads_what_git_writes =
  property ~name:"diff gives back the changes of an output of git diff -U0"
    ~print:(fun (output, expected) ->
      Printf.sprintf "%S %s" output (Generators.print_changes expected))
    Generators.diff_output
    (fun (output, expected) -> Git.Decode.diff output = Ok expected)

let diff_reads_hunks_with_context =
  property ~name:"diff gives each run of changed lines of a hunk with context"
    ~print:(fun (output, runs) ->
      Printf.sprintf "%S %s" output
        (Generators.print_changes [ ("f", Git.Modified runs) ]))
    Generators.diff_output_with_context
    (fun (output, runs) ->
      Git.Decode.diff output = Ok [ ("f", Git.Modified runs) ])

let diff_is_total =
  property ~name:"diff gives changes or an error for a damaged output"
    ~print:(fun text -> Printf.sprintf "%S" text)
    Generators.damaged_diff_output
    (fun output -> match Git.Decode.diff output with Ok _ | Error _ -> true)

(* Repositories. *)

(* The shared repository, opened once. A [Git.t] holds no resource, so
   the tests share it. *)
let shared =
  lazy
    (let repo = Git_fixture.shared () in
     match
       Git.open_repo ~env:(Git_fixture.env repo) (Git_fixture.root repo)
     with
     | Ok t -> (repo, t)
     | Error _ -> failwith "the shared repository does not open")

let open_shared () = Lazy.force shared

let open_with env =
  let repo = Git_fixture.shared () in
  match Git.open_repo ~env (Git_fixture.root repo) with
  | Ok t -> t
  | Error _ -> Alcotest.fail "the shared repository does not open"

(* The commits of the refs that the tests of the target name, read with
   one process. *)
let refs =
  [
    "refs/remotes/origin/main";
    "refs/heads/both";
    "refs/remotes/origin/orig";
    "refs/heads/gone";
    "main~1";
  ]

let commits =
  lazy
    (let repo = Git_fixture.shared () in
     List.combine refs
       (String.split_on_char '\n'
          (String.trim (Git_fixture.git repo ("rev-parse" :: refs)))))

let commit_id rev = List.assoc rev (Lazy.force commits)

let error =
  Alcotest.testable
    (fun formatter (e : Git.error) ->
      Format.pp_print_string formatter
        (match e with
        | Git.Git_not_found s -> "Git_not_found " ^ s
        | Git.Not_a_repository { dir; _ } -> "Not_a_repository " ^ dir
        | Git.Bad_revision s -> "Bad_revision " ^ s
        | Git.Target_not_found s -> "Target_not_found " ^ s
        | Git.No_merge_base (a, b) -> "No_merge_base " ^ a ^ " " ^ b
        | Git.Command_failed { args; _ } ->
            "Command_failed " ^ String.concat " " args
        | Git.Malformed_output { detail; _ } -> "Malformed_output " ^ detail
        | Git.File_error s -> "File_error " ^ s))
    (fun a b ->
      match (a, b) with
      | Git.Command_failed _, Git.Command_failed _ -> true
      | a, b -> a = b)

(* The target branch. *)

let target =
  Alcotest.testable
    (fun formatter (target : Git.target) ->
      Format.fprintf formatter "{%s; %s; %s}"
        (match target.source with
        | Git.Upstream -> "Upstream"
        | Git.Local_branch -> "Local_branch"
        | Git.Origin_branch -> "Origin_branch")
        target.refname target.commit)
    ( = )

let resolves name expected_source expected_ref () =
  let _, t = open_shared () in
  Alcotest.(check (result target error))
    name
    (Ok
       {
         source = expected_source;
         refname = expected_ref;
         commit = commit_id expected_ref;
       })
    (Git.resolve_target t name)

let the_upstream_comes_first =
  resolves "main" Git.Upstream "refs/remotes/origin/main"

let a_local_branch_comes_before_origin =
  resolves "both" Git.Local_branch "refs/heads/both"

let a_branch_of_origin_alone_is_found =
  resolves "orig" Git.Origin_branch "refs/remotes/origin/orig"

(* The upstream of [gone] does not exist, and [origin] has no branch
   [gone]. *)
let a_local_branch_alone_is_found =
  resolves "gone" Git.Local_branch "refs/heads/gone"

(* The upstream of [loc] is the local branch [both]. *)
let an_upstream_that_is_a_local_branch_is_found =
  resolves "loc" Git.Upstream "refs/heads/both"

let not_found name () =
  let _, t = open_shared () in
  Alcotest.(check (result target error))
    name (Error (Git.Target_not_found name))
    (Git.resolve_target t name)

(* The merge base. *)

let merge_base_gives_the_common_ancestor () =
  let _, t = open_shared () in
  Alcotest.(check (result string error))
    "the root of main"
    (Ok (commit_id "main~1"))
    (Git.merge_base t "main" "origin/main")

let merge_base_of_unrelated_commits_is_an_error () =
  let _, t = open_shared () in
  Alcotest.(check (result string error))
    "no common ancestor"
    (Error (Git.No_merge_base ("main", "lonely")))
    (Git.merge_base t "main" "lonely")

let merge_base_names_a_revision_with_a_nul_byte () =
  let _, t = open_shared () in
  Alcotest.(check (result string error))
    "a NUL byte" (Error (Git.Bad_revision "ma\000in"))
    (Git.merge_base t "main" "ma\000in")

let diff_names_a_base_with_a_nul_byte () =
  let _, t = open_shared () in
  Alcotest.(check (result changes error))
    "a NUL byte" (Error (Git.Bad_revision "ma\000in"))
    (Git.diff t ~base:"ma\000in")

let merge_base_names_a_revision_that_starts_with_a_hyphen () =
  let _, t = open_shared () in
  Alcotest.(check (result string error))
    "an option" (Error (Git.Bad_revision "--all"))
    (Git.merge_base t "--all" "main")

let merge_base_names_a_bad_second_revision () =
  let _, t = open_shared () in
  Alcotest.(check (result string error))
    "the second" (Error (Git.Bad_revision "nope"))
    (Git.merge_base t "main" "nope")

(* The diff. *)

let quoted_name = "caf\xc3\xa9\tdoc one.txt"

(* The environment of the shared repository, with configuration that
   changes the form of git's diff output and the edges of its hunks.
   The environment carries it, so that the shared repository stays as
   it is. *)
let configured_env repo =
  let settings =
    [
      ("init.defaultBranch", "main");
      ("diff.noprefix", "true");
      ("diff.mnemonicPrefix", "true");
      ("diff.submodule", "log");
      ("diff.algorithm", "histogram");
      ("diff.indentHeuristic", "false");
      ("diff.interHunkContext", "10");
      ("diff.suppressBlankEmpty", "true");
      ("diff.renames", "copies");
      ("color.ui", "always");
      ("core.quotePath", "false");
      ("diff.context", "5");
      ("diff.external", "/bin/false");
      ("color.diff", "always");
    ]
  in
  let counted prefix entry = String.starts_with ~prefix entry in
  let kept =
    Array.to_list (Git_fixture.env repo)
    |> List.filter (fun entry ->
        not
          (counted "GIT_CONFIG_COUNT=" entry
          || counted "GIT_CONFIG_KEY_" entry
          || counted "GIT_CONFIG_VALUE_" entry))
  in
  Array.of_list
    (kept
    @ [
        Printf.sprintf "GIT_CONFIG_COUNT=%d" (List.length settings);
        "GIT_DIFF_OPTS=--unified=3";
        "GIT_EXTERNAL_DIFF=false";
      ]
    @ List.concat
        (List.mapi
           (fun index (key, value) ->
             [
               Printf.sprintf "GIT_CONFIG_KEY_%d=%s" index key;
               Printf.sprintf "GIT_CONFIG_VALUE_%d=%s" index value;
             ])
           settings))

(* The diff of the shared repository against [HEAD] under that
   configuration, and the state of the index before and after. Every
   test of the diff reads this one run, and expects what git gives
   with no configuration. *)
let shared_diff =
  lazy
    (let repo = Git_fixture.shared () in
     let t = open_with (configured_env repo) in
     let before = Git_fixture.index_state repo in
     let changes = Git.diff t ~base:"HEAD" in
     (before, changes, Git_fixture.index_state repo))

let shared_changes () =
  match Lazy.force shared_diff with
  | _, Ok changes, _ -> changes
  | _, Error _, _ -> Alcotest.fail "the diff of the shared repository fails"

let change_of path =
  match List.assoc_opt path (shared_changes ()) with
  | Some change -> Generators.print_change change
  | None -> "absent"

let hunk line eline added removed : Git.hunk = { line; eline; added; removed }

let is path expected () =
  Alcotest.(check string)
    path
    (Generators.print_change expected)
    (change_of path)

let is_absent path () = Alcotest.(check string) path "absent" (change_of path)

let a_modified_file_gives_its_hunks =
  is "mod.txt" (Git.Modified [ hunk 3 3 1 1; hunk 6 6 0 2; hunk 8 8 1 0 ])

let diff_puts_a_deletion_at_the_start_at_line_1 =
  is "head.txt" (Git.Modified [ hunk 1 1 0 2 ])

let diff_puts_a_deletion_at_the_end_past_the_last_line =
  is "tail.txt" (Git.Modified [ hunk 2 2 0 2 ])

let a_name_with_a_tab_a_space_and_a_non_ascii_byte_is_read =
  is quoted_name (Git.Modified [ hunk 1 1 1 1 ])

let diff_finds_a_binary_file = is "bin.dat" Git.Binary
let diff_gives_a_mode_change_no_hunk = is "mode.sh" (Git.Modified [])
let a_file_deleted_on_disk_is_deleted = is "gone.txt" Git.Deleted
let a_file_removed_from_the_index_is_deleted = is "removed.txt" Git.Deleted
let a_new_tracked_file_is_added = is "added.txt" Git.Added
let an_untracked_file_is_added = is "untracked.txt" Git.Added
let an_untracked_file_of_the_base_is_added = is "unstaged.txt" Git.Added
let a_file_that_became_a_link_is_deleted = is "typed.txt" Git.Deleted

let a_rename_is_a_deletion_and_an_addition () =
  Alcotest.(check (pair string string))
    "old and new name" ("Deleted", "Added")
    (change_of "old-name.txt", change_of "new-name.txt")

let an_unchanged_file_is_left_out = is_absent "README.md"
let an_ignored_file_is_left_out = is_absent "ignored.log"
let a_symbolic_link_is_left_out = is_absent "untracked-link"
let a_link_that_became_a_file_is_left_out = is_absent "link-as-file"
let a_submodule_that_became_a_file_is_left_out = is_absent "sub-as-file"

let diff_sorts_the_paths_by_byte_order () =
  Alcotest.(check (list string))
    "every changed path, in order"
    [
      "added.txt";
      "bin.dat";
      quoted_name;
      "gone.txt";
      "head.txt";
      "mod.txt";
      "mode.sh";
      "new-name.txt";
      "old-name.txt";
      "removed.txt";
      "tail.txt";
      "typed.txt";
      "unstaged.txt";
      "untracked.txt";
    ]
    (List.map fst (shared_changes ()))

let diff_leaves_the_index_untouched () =
  let before, _, after = Lazy.force shared_diff in
  Alcotest.(check string) "the state of the index" before after

let diff_of_a_bad_base_is_an_error () =
  let _, t = open_shared () in
  Alcotest.(check (result changes error))
    "no such revision" (Error (Git.Bad_revision "nope"))
    (Git.diff t ~base:"nope")

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "a header gives both ranges" a_header_gives_both_ranges;
    case "an omitted count is 1" an_omitted_count_is_one;
    case "the text after a header is ignored" the_text_after_a_header_is_ignored;
    case "a number of 15 digits is read" a_number_of_fifteen_digits_is_read;
    case "a number of 16 digits is refused"
      a_number_of_sixteen_digits_is_refused;
    case "a header that is cut short is refused"
      a_header_that_is_cut_short_is_refused;
    case "a header with a wrong mark is refused"
      a_header_with_a_wrong_mark_is_refused;
    case "a side with lines that starts at line 0 is refused"
      a_side_with_lines_that_starts_at_line_0_is_refused;
    case "a header names what is missing" a_header_names_what_is_missing;
    case "a header names a missing count" a_header_names_a_missing_count;
    case "a side with no lines can start at line 0"
      a_side_with_no_lines_can_start_at_line_0;
    hunk_header_reads_what_git_writes;
    hunk_header_is_total;
    case "refs reads each field" refs_reads_each_field;
    case "refs of no output is empty" refs_of_no_output_is_empty;
    case "refs refuses a bad record" refs_refuses_a_bad_record;
    refs_reads_what_git_writes;
    refs_is_total;
    case "an empty output has no change" empty_output_has_no_change;
    case "an output without a last line feed is refused"
      output_without_a_last_line_feed_is_refused;
    case "a changed line is one hunk" a_changed_line_is_one_hunk;
    case "added lines span their new lines" added_lines_span_their_new_lines;
    case "a pure deletion is at the line after it"
      a_pure_deletion_is_at_the_line_after_it;
    case "a deletion at the start is at line 1"
      a_deletion_at_the_start_is_at_line_1;
    case "a deletion at the end is past the last line"
      a_deletion_at_the_end_is_past_the_last_line;
    case "the hunks of a file keep their order"
      the_hunks_of_a_file_keep_their_order;
    case "a binary file is binary" a_binary_file_is_binary;
    case "a mode change alone has no hunk" a_mode_change_alone_has_no_hunk;
    case "a section with nothing after its header has no hunk"
      a_section_with_no_line_after_its_header_has_no_hunk;
    case "the marker of a missing line feed is skipped"
      the_marker_of_a_missing_line_feed_is_skipped;
    case "context lines end a run" context_lines_end_a_run;
    case "an empty line is a context line" an_empty_line_is_a_context_line;
    case "two sections of one path are joined"
      two_sections_of_one_path_are_joined;
    case "a binary section makes a joined path binary"
      a_binary_section_makes_a_joined_path_binary;
    case "the paths are sorted by byte order" the_paths_are_sorted_by_byte_order;
    case "a quoted name is unquoted" a_quoted_name_is_unquoted;
    case "a name with spaces and b/ is read"
      a_name_with_spaces_and_b_slash_is_read;
    case "a name of one byte is read" a_one_byte_name_is_read;
    case "a bad diff --git line is refused" a_bad_git_line_is_refused;
    case "a hunk that ends early is refused" a_hunk_that_ends_early_is_refused;
    case "a line that does not fit its hunk is refused"
      a_line_that_does_not_fit_its_hunk_is_refused;
    case "an output that does not start with a section is refused"
      output_that_does_not_start_with_a_section_is_refused;
    diff_reads_what_git_writes;
    diff_reads_hunks_with_context;
    diff_is_total;
    case "resolve_target takes the upstream first" the_upstream_comes_first;
    case "resolve_target takes a local branch before origin"
      a_local_branch_comes_before_origin;
    case "resolve_target finds a local branch alone"
      a_local_branch_alone_is_found;
    case "resolve_target finds a branch of origin alone"
      a_branch_of_origin_alone_is_found;
    case "resolve_target finds an upstream that is a local branch"
      an_upstream_that_is_a_local_branch_is_found;
    case "resolve_target finds no branch of an unknown name"
      (not_found "nothing");
    case "resolve_target reads no revision syntax in a name"
      (not_found "main~1");
    case "resolve_target reads no range in a name" (not_found "main..main");
    case "resolve_target reads no glob in a name" (not_found "m*");
    case "resolve_target finds no branch of a prefix of a branch name"
      (not_found "deep");
    case "resolve_target finds no branch of a name with a NUL byte"
      (not_found "ma\000in");
    case "merge_base gives the common ancestor"
      merge_base_gives_the_common_ancestor;
    case "merge_base of unrelated commits is an error"
      merge_base_of_unrelated_commits_is_an_error;
    case "merge_base names a revision with a NUL byte"
      merge_base_names_a_revision_with_a_nul_byte;
    case "diff names a base with a NUL byte" diff_names_a_base_with_a_nul_byte;
    case "merge_base names a revision that starts with a hyphen"
      merge_base_names_a_revision_that_starts_with_a_hyphen;
    case "merge_base names a bad revision"
      merge_base_names_a_bad_second_revision;
    case "diff gives the hunks of a modified file"
      a_modified_file_gives_its_hunks;
    case "diff puts a deletion at the start at line 1"
      diff_puts_a_deletion_at_the_start_at_line_1;
    case "diff puts a deletion at the end past the last line"
      diff_puts_a_deletion_at_the_end_past_the_last_line;
    case "diff reads a name with a tab, a space, and a non-ASCII byte"
      a_name_with_a_tab_a_space_and_a_non_ascii_byte_is_read;
    case "diff finds a binary file" diff_finds_a_binary_file;
    case "diff gives a mode change no hunk" diff_gives_a_mode_change_no_hunk;
    case "diff finds a file deleted on disk" a_file_deleted_on_disk_is_deleted;
    case "diff finds a file removed from the index"
      a_file_removed_from_the_index_is_deleted;
    case "diff finds a new tracked file" a_new_tracked_file_is_added;
    case "diff finds an untracked file" an_untracked_file_is_added;
    case "diff calls an untracked file of the base added"
      an_untracked_file_of_the_base_is_added;
    case "diff calls a file that became a link deleted"
      a_file_that_became_a_link_is_deleted;
    case "diff makes a rename a deletion and an addition"
      a_rename_is_a_deletion_and_an_addition;
    case "diff leaves out an unchanged file" an_unchanged_file_is_left_out;
    case "diff leaves out an ignored file" an_ignored_file_is_left_out;
    case "diff leaves out a symbolic link" a_symbolic_link_is_left_out;
    case "diff leaves out a link that became a file"
      a_link_that_became_a_file_is_left_out;
    case "diff leaves out a submodule that became a file"
      a_submodule_that_became_a_file_is_left_out;
    case "diff sorts the paths by byte order" diff_sorts_the_paths_by_byte_order;
    case "diff leaves the index untouched" diff_leaves_the_index_untouched;
    case "diff of a bad base is an error" diff_of_a_bad_base_is_an_error;
  ]
