(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Repo = Git_fixture

let manifest = "[scan]\npacks.markdown.files = [\"**/*.md\"]\n"

let plan =
  "# Work\n\n\
   @plan work\n\
   @scope docs/**, lib/**\n\n\
   ## Edit\n\n\
   @scope lib/edit.ml\n\n\
   ## Gone\n\n\
   @scope lib/gone.ml\n\n\
   ## New\n\n\
   @scope lib/new.ml\n\n\
   ## Back\n\n\
   @scope lib/back.ml\n\n\
   ## Parent\n\n\
   @scope lib/parent.ml\n\n\
   ## Late\n\n\
   @scope docs/late.md\n\n\
   ## Same\n\n\
   @scope lib/same.ml\n"

let trunk_files =
  [
    Repo.File ("sinter.toml", manifest);
    Repo.File ("docs/reqs.md", "# Reqs\n\n@req login\nUsers log in.\n");
    Repo.File (".plans/work.md", plan);
    Repo.File ("lib/edit.ml", "let a = 1\nlet b = 2\n");
    Repo.File ("lib/gone.ml", "let gone = ()\n");
    Repo.File ("lib/back.ml", "let back = 1\n");
    Repo.File ("lib/same.ml", "let same = ()\n");
  ]

let parent_changes =
  [
    Repo.File
      ( "docs/reqs.md",
        "# Reqs\n\n@req login\nUsers log in.\n\n## Out\n\n@req out\n" );
    Repo.File ("lib/parent.ml", "let parent = ()\n");
    Repo.Delete "lib/back.ml";
  ]

let remote_config =
  "[remote \"origin\"]\n\
   \turl = /dev/null\n\
   \tfetch = +refs/heads/*:refs/remotes/origin/*\n"

let upstream_config =
  "[branch \"main\"]\n\tremote = origin\n\tmerge = refs/heads/main\n"

let head repo = String.trim (Repo.git repo [ "rev-parse"; "HEAD" ])

let change_working_copy repo =
  Repo.write repo "lib/edit.ml" "let a = 1\nlet b = 3\n";
  Repo.remove repo "lib/gone.ml";
  Repo.write repo "lib/new.ml" "let fresh = ()\n";
  Repo.write repo "lib/back.ml" "let back = 2\n";
  Repo.write repo "docs/new.md" "# New\n\n@cites missing\n"

let late_files = [ "docs/late.md" ]
let add_late_files repo = Repo.write repo "docs/late.md" "# Late\n\n@req late\n"

let plain_repository ?(trunk_ahead = false) () =
  let repo = Repo.init () in
  Repo.import repo
    ([ Repo.commit ~ref:"refs/heads/main" ~mark:1 ~message:"trunk" trunk_files ]
    @ (if trunk_ahead then
         [
           Repo.commit ~parents:[ 1 ] ~ref:"refs/remotes/origin/main" ~mark:3
             ~message:"ahead"
             [ Repo.File ("lib/ahead.ml", "let ahead = ()\n") ];
         ]
       else [ Repo.reset ~ref:"refs/remotes/origin/main" ~mark:1 ])
    @ [
        Repo.commit
          ~parents:[ (if trunk_ahead then 3 else 1) ]
          ~ref:"refs/heads/work" ~mark:2 ~message:"parent" parent_changes;
      ]);
  Repo.append_config repo (remote_config ^ upstream_config);
  ignore (Repo.git repo [ "symbolic-ref"; "HEAD"; "refs/heads/work" ]);
  Repo.checkout repo;
  repo

let jj_state ?(late = late_files) plain =
  let repo = Repo.copy plain in
  List.iter (fun path -> Repo.remove repo path) late;
  let parent = head repo in
  Repo.write repo ".jj/.gitignore" "/*\n";
  Repo.write repo ".jj/repo/store/type" "git";
  Repo.write repo ".jj/repo/store/git_target" "../../../.git";
  Repo.write repo ".jj/working_copy/checkout" "\000";
  ignore (Repo.git repo [ "add"; "-A" ]);
  let tree = String.trim (Repo.git repo [ "write-tree" ]) in
  let working_copy =
    String.trim (Repo.git repo [ "commit-tree"; tree; "-p"; parent; "-m"; "" ])
  in
  ignore
    (Repo.git repo
       [ "update-ref"; "refs/jj/keep/" ^ working_copy; working_copy ]);
  ignore (Repo.git repo [ "update-ref"; "refs/jj/keep/" ^ parent; parent ]);
  ignore (Repo.git repo [ "checkout"; "-q"; "--detach" ]);
  ignore (Repo.git repo [ "update-ref"; "-d"; "refs/heads/work" ]);
  ignore (Repo.git repo [ "read-tree"; parent ]);
  let added =
    Repo.git repo
      [
        "diff-tree";
        "-r";
        "-z";
        "--name-only";
        "--diff-filter=A";
        parent;
        working_copy;
      ]
    |> String.split_on_char '\000'
    |> List.filter (fun path -> path <> "")
  in
  if added <> [] then ignore (Repo.git repo ([ "add"; "-N"; "--" ] @ added));
  ignore (Repo.git repo [ "config"; "--remove-section"; "branch.main" ]);
  List.iter
    (fun path ->
      Repo.write repo path
        (In_channel.with_open_bin
           (Filename.concat (Repo.root plain) path)
           In_channel.input_all))
    late;
  repo

let pair =
  lazy
    (let plain = plain_repository () in
     change_working_copy plain;
     add_late_files plain;
     (plain, jj_state plain))

let opened repo =
  match Git.open_repo ~env:(Repo.env repo) (Repo.root repo) with
  | Ok t -> t
  | Error _ -> Alcotest.fail "the repository does not open"

let ok = function
  | Ok value -> value
  | Error _ -> Alcotest.fail "the call gives an error"

let strings = Alcotest.(list string)
let lines text = List.filter (( <> ) "") (String.split_on_char '\n' text)

let a_jj_state_has_a_detached_head_at_the_parent_of_the_working_copy () =
  let plain, jj = Lazy.force pair in
  Alcotest.(check (pair int string))
    "the status of git symbolic-ref HEAD, and the commit of HEAD"
    (1, head plain)
    (Repo.git_status jj [ "symbolic-ref"; "-q"; "HEAD" ], head jj)

let a_jj_state_marks_new_files_as_intent_to_add () =
  let _, jj = Lazy.force pair in
  Alcotest.check strings "the short status of each changed path"
    [
      " A docs/new.md";
      " A lib/back.ml";
      " M lib/edit.ml";
      " D lib/gone.ml";
      " A lib/new.ml";
      "?? docs/late.md";
    ]
    (lines
       (Repo.git jj [ "--no-optional-locks"; "status"; "--porcelain"; "-uall" ]))

let a_jj_state_has_no_upstream () =
  let _, jj = Lazy.force pair in
  Alcotest.(check int)
    "the status of git config for the keys of branches" 1
    (Repo.git_status jj [ "config"; "--get-regexp"; "^branch\\." ])

let a_jj_state_keeps_refs_under_refs_jj () =
  let _, jj = Lazy.force pair in
  Alcotest.check strings "the refs"
    [
      "refs/heads/main";
      "refs/jj/keep/";
      "refs/jj/keep/";
      "refs/remotes/origin/main";
    ]
    (List.map
       (fun name ->
         if String.starts_with ~prefix:"refs/jj/keep/" name then "refs/jj/keep/"
         else name)
       (lines (Repo.git jj [ "for-each-ref"; "--format=%(refname)" ])))

let both f =
  let plain, jj = Lazy.force pair in
  (f plain, f jj)

let same name testable f =
  let plain, jj = both f in
  Alcotest.check testable name plain jj

let a_jj_state_gives_the_same_files () =
  let plain, jj = both (fun repo -> ok (Git.files (opened repo))) in
  Alcotest.check strings "the files of the jj state" plain jj;
  Alcotest.(check bool)
    "the new files are in the set" true
    (List.for_all
       (fun path -> List.mem path jj)
       [ "docs/late.md"; "docs/new.md"; "lib/back.ml"; "lib/new.ml" ])

let load repo =
  match
    Scan.load ~env:(Repo.env repo) ~dir:(Repo.root repo) ~manifest:None
      ~base:None ()
  with
  | Ok tree -> tree
  | Error error ->
      Alcotest.failf "the load fails: %s"
        (String.concat "; " (Scan.messages error))

let trunk repo = String.trim (Repo.git repo [ "rev-parse"; "main" ])

let a_jj_state_gives_the_same_base () =
  let plain, jj = Lazy.force pair in
  let plain_tree = load plain and jj_tree = load jj in
  Alcotest.(check (pair string string))
    "the base commits"
    (trunk plain, trunk plain)
    (Scan.base_commit plain_tree.base, Scan.base_commit jj_tree.base)

let a_jj_state_takes_the_local_branch_as_the_target () =
  let plain, jj = Lazy.force pair in
  Alcotest.(check (pair string string))
    "the target ref of each"
    ("refs/remotes/origin/main", "refs/heads/main")
    ( (ok (Git.resolve_target (opened plain) "main")).refname,
      (ok (Git.resolve_target (opened jj) "main")).refname )

let print_change = function
  | Git.Added -> "added"
  | Git.Deleted -> "deleted"
  | Git.Binary -> "binary"
  | Git.Modified hunks ->
      "modified"
      ^ String.concat ""
          (List.map
             (fun (hunk : Git.hunk) ->
               Printf.sprintf " %d-%d+%d-%d" hunk.line hunk.eline hunk.added
                 hunk.removed)
             hunks)

let diff repo =
  List.map
    (fun (path, change) -> path ^ " " ^ print_change change)
    (ok (Git.diff (opened repo) ~base:(trunk repo)))

let brought_back = "lib/back.ml"

let a_jj_state_gives_the_same_diff () =
  same "the diff against the trunk, without the file brought back" strings
    (fun repo ->
      List.filter
        (fun line -> not (String.starts_with ~prefix:(brought_back ^ " ") line))
        (diff repo))

let a_file_brought_back_is_modified_in_jj_and_added_in_plain_git () =
  let changes repo =
    List.filter
      (fun line -> String.starts_with ~prefix:(brought_back ^ " ") line)
      (diff repo)
  in
  Alcotest.(check (pair strings strings))
    "the change of the file in plain git and in the jj state"
    ([ "lib/back.ml added" ], [ "lib/back.ml modified 1-1+1-1" ])
    (both changes)

let a_jj_state_gives_the_same_tree_key () =
  same "the tree key" Alcotest.string (fun repo ->
      ok (Git.tree_key (opened repo)))

let a_tree_key_leaves_the_intent_to_add_entries_in_the_index () =
  let _, jj = Lazy.force pair in
  let before = Repo.index_state jj in
  ignore (ok (Git.tree_key (opened jj)));
  Alcotest.(check string) "the index" before (Repo.index_state jj)

let sinter = Filename.concat (Sys.getcwd ()) "../bin/main.exe"
let coverage_file = "BISECT_FILE=" ^ Filename.concat (Sys.getcwd ()) "bisect"

let environment repo =
  let env = Repo.env repo in
  if Array.exists (String.starts_with ~prefix:"BISECT_FILE=") env then env
  else Array.append env [| coverage_file |]

let run_sinter repo args =
  let output = Filename.temp_file "sinter-jj" ".out" in
  let errors = Filename.temp_file "sinter-jj" ".err" in
  Fun.protect
    ~finally:(fun () ->
      Sys.remove output;
      Sys.remove errors)
    (fun () ->
      let open_out path =
        Unix.openfile path [ Unix.O_WRONLY; Unix.O_TRUNC; Unix.O_CLOEXEC ] 0
      in
      let to_output = open_out output and to_errors = open_out errors in
      let pid =
        Fun.protect
          ~finally:(fun () ->
            Unix.close to_output;
            Unix.close to_errors)
          (fun () ->
            Unix.create_process_env "/bin/sh"
              (Array.of_list
                 ([ "/bin/sh"; "-c"; "cd \"$1\" && shift && exec \"$@\""; "sh" ]
                 @ (Repo.root repo :: sinter :: args)))
              (environment repo) Unix.stdin to_output to_errors)
      in
      let status =
        match Unix.waitpid [] pid with
        | _, Unix.WEXITED code -> code
        | _, (Unix.WSIGNALED signal | Unix.WSTOPPED signal) -> -signal
      in
      let read path = In_channel.with_open_bin path In_channel.input_all in
      (status, read output, read errors))

let output repo args =
  let status, output, _ = run_sinter repo args in
  (status, output)

let scans = lazy (both (fun repo -> output repo [ "scan" ]))

let a_jj_state_gives_the_same_scan_records () =
  let plain, jj = Lazy.force scans in
  Alcotest.(check (pair int string))
    "the exit code and the records of sinter scan" plain jj

let done_of_steps text =
  List.filter_map
    (fun line ->
      match Yojson.Safe.from_string line with
      | `Assoc fields -> (
          match
            ( List.assoc_opt "kind" fields,
              List.assoc_opt "id" fields,
              List.assoc_opt "done" fields )
          with
          | Some (`String "step"), Some (`String id), Some (`Bool finished) ->
              Some (id, finished)
          | _ -> None)
      | _ -> None)
    (lines text)

let the_scan_of_a_jj_state_counts_each_changed_scope () =
  let _, (status, text) = Lazy.force scans in
  Alcotest.(check (pair int (list (pair string bool))))
    "the exit code, and the done of each step"
    ( 0,
      [
        ("step:work/edit", true);
        ("step:work/gone", true);
        ("step:work/new", true);
        ("step:work/back", true);
        ("step:work/parent", true);
        ("step:work/late", true);
        ("step:work/same", false);
      ] )
    (status, done_of_steps text)

let checks =
  lazy
    (both (fun repo ->
         List.map (output repo)
           [ [ "check" ]; [ "check"; "--json"; "--gate"; "merge" ] ]))

let a_jj_state_gives_the_same_check_findings () =
  let plain, jj = Lazy.force checks in
  Alcotest.(check (list (pair int string)))
    "the exit code and the findings of sinter check, in text and in JSON at \
     merge"
    plain jj

let the_check_of_a_jj_state_reports_the_findings_of_new_files () =
  match Lazy.force checks with
  | _, [ (status, text); (json_status, _) ] ->
      Alcotest.(check (triple int int strings))
        "the exit codes of the text and of the JSON, and the text"
        ( 0,
          1,
          [
            "docs/late.md:3:1: uncovered req:late nothing satisfies it, and \
             nothing verifies it";
            "docs/new.md:3:1: dangling cites:site:docs/new.md#new->missing no \
             declaration has the slug missing";
            "docs/reqs.md:3:1: uncovered req:login nothing satisfies it, and \
             nothing verifies it";
            "docs/reqs.md:8:1: uncovered req:out nothing satisfies it, and \
             nothing verifies it";
          ] )
        (status, json_status, lines text)
  | _ -> Alcotest.fail "the check runs twice"

let a_stale_local_main_with_no_upstream_is_the_target_over_origin_main () =
  let plain = plain_repository ~trunk_ahead:true () in
  change_working_copy plain;
  let jj = jj_state ~late:[] plain in
  let tree = load jj in
  Alcotest.(check (pair string string))
    "the target ref and the base: the local main, behind origin/main"
    ("refs/heads/main", trunk jj)
    ( (ok (Git.resolve_target (opened jj) "main")).refname,
      Scan.base_commit tree.base )

let empty =
  lazy
    (let plain = plain_repository () in
     (plain, jj_state ~late:[] plain))

let an_empty_working_copy_commit_gives_no_change_against_head () =
  let _, jj = Lazy.force empty in
  Alcotest.check strings "the diff against HEAD" []
    (ok (Git.diff (opened jj) ~base:"HEAD") |> List.map fst)

let an_empty_working_copy_commit_gives_the_tree_of_head_as_its_key () =
  let _, jj = Lazy.force empty in
  Alcotest.(check string)
    "the tree key"
    (String.trim (Repo.git jj [ "rev-parse"; "HEAD^{tree}" ]))
    (ok (Git.tree_key (opened jj)))

let an_empty_working_copy_commit_gives_the_same_scan_records () =
  let plain, jj = Lazy.force empty in
  let plain_status, plain_records = output plain [ "scan" ] in
  let jj_status, jj_records = output jj [ "scan" ] in
  Alcotest.(check (pair (pair int int) string))
    "the exit codes of both scans, and the records"
    ((0, 0), plain_records)
    ((plain_status, jj_status), jj_records)

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "a jj state has a detached HEAD at the parent of the working copy"
      a_jj_state_has_a_detached_head_at_the_parent_of_the_working_copy;
    case "a jj state marks new files as intent-to-add"
      a_jj_state_marks_new_files_as_intent_to_add;
    case "a jj state has no upstream" a_jj_state_has_no_upstream;
    case "a jj state keeps refs under refs/jj/"
      a_jj_state_keeps_refs_under_refs_jj;
    case "a jj state gives the same files" a_jj_state_gives_the_same_files;
    case "a jj state gives the same base" a_jj_state_gives_the_same_base;
    case "a jj state takes the local branch as the target"
      a_jj_state_takes_the_local_branch_as_the_target;
    case "a jj state gives the same diff" a_jj_state_gives_the_same_diff;
    case
      "a file that the parent deleted and the working copy brings back is \
       Modified in the jj state and Added in plain git"
      a_file_brought_back_is_modified_in_jj_and_added_in_plain_git;
    case "a jj state gives the same tree key" a_jj_state_gives_the_same_tree_key;
    case "a tree key leaves the intent-to-add entries in the index"
      a_tree_key_leaves_the_intent_to_add_entries_in_the_index;
    case "a jj state gives the same scan records"
      a_jj_state_gives_the_same_scan_records;
    case "the scan of a jj state counts each changed scope"
      the_scan_of_a_jj_state_counts_each_changed_scope;
    case "a jj state gives the same check findings"
      a_jj_state_gives_the_same_check_findings;
    case "the check of a jj state reports the findings of new files"
      the_check_of_a_jj_state_reports_the_findings_of_new_files;
    case "a stale local main with no upstream is the target over origin/main"
      a_stale_local_main_with_no_upstream_is_the_target_over_origin_main;
    case "an empty working-copy commit gives no change against HEAD"
      an_empty_working_copy_commit_gives_no_change_against_head;
    case "an empty working-copy commit gives the tree of HEAD as its key"
      an_empty_working_copy_commit_gives_the_tree_of_head_as_its_key;
    case "an empty working-copy commit gives the same scan records"
      an_empty_working_copy_commit_gives_the_same_scan_records;
  ]
