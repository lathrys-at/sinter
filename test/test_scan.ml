(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let manifest = "[scan]\npacks.markdown.files = [\"**/*.md\"]\n"

let repository files =
  let repo = Git_fixture.init () in
  List.iter (fun (path, content) -> Git_fixture.write repo path content) files;
  ignore (Git_fixture.git repo [ "add"; "-A" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "--allow-empty"; "-m"; "c" ]);
  repo

let scan ?(dir = "") ?manifest ?base repo =
  Scan.run ~env:(Git_fixture.env repo)
    ~dir:(Filename.concat (Git_fixture.root repo) dir)
    ~manifest ~base ~tool:"v1" ()

let messages error =
  List.map
    (fun { Error_text.fault; help; _ } -> fault ^ "; " ^ help)
    (Scan.explain error)

let outcome = function
  | Ok outcome -> outcome
  | Error error ->
      Alcotest.failf "the scan fails: %s" (String.concat "; " (messages error))

let failure = function
  | Ok _ -> Alcotest.fail "the scan gives an outcome"
  | Error error -> String.concat "\n" (messages error)

let field name record =
  match List.assoc_opt name record with
  | Some (Jsonl.Scalar (Jsonl.String text)) -> text
  | _ -> Alcotest.failf "the record has no string field %s" name

let ids records =
  List.map
    (fun record ->
      match List.assoc_opt "id" record with
      | Some (Jsonl.Scalar (Jsonl.String id)) -> id
      | _ -> "(no id)")
    records

let ledger = "no ledger found, so every plan counts as open"

let shared =
  lazy
    (let repo =
       repository
         [
           ("sinter.toml", manifest);
           ("docs/a.md", "# A\n\n@req a\n");
           ("lib/gone.ml", "x\n");
           ("lib/mode.sh", "y\n");
           ( ".plans/p.md",
             "# P\n\n\
              @plan p\n\n\
              ## Gone\n\n\
              @scope lib/gone.ml\n\n\
              ## Mode\n\n\
              @scope lib/mode.sh\n" );
         ]
     in
     Sys.remove (Filename.concat (Git_fixture.root repo) "lib/gone.ml");
     Git_fixture.make_executable repo "lib/mode.sh";
     let odd_name =
       match Git_fixture.write repo "caf\xe9.md" "# C\n\n@req cafe\n" with
       | () -> true
       | exception Sys_error _ -> false
     in
     Git_fixture.write repo "binary.md" "# B\n\n@req \xff\n";
     (repo, odd_name, outcome (scan repo)))

let a_scan_starts_with_the_index_of_the_tree_and_the_base () =
  let repo, _, { Scan.records; _ } = Lazy.force shared in
  let t =
    match Git.open_repo ~env:(Git_fixture.env repo) (Git_fixture.root repo) with
    | Ok t -> t
    | Error _ -> Alcotest.fail "the repository does not open"
  in
  match records with
  | index :: _ ->
      Alcotest.(check (list string))
        "the kind, the tree, the base, the manifest, and the tool"
        [
          "index";
          (match Git.tree_key t with Ok key -> key | Error _ -> "");
          String.trim (Git_fixture.git repo [ "rev-parse"; "HEAD" ]);
          "sinter.toml";
          "v1";
        ]
        (List.map
           (fun name -> field name index)
           [ "kind"; "tree"; "base"; "manifest"; "tool" ])
  | [] -> Alcotest.fail "the scan gives no record"

let a_path_that_is_not_utf_8_gives_a_warning_and_no_fact () =
  let _, odd_name, { Scan.warnings; records } = Lazy.force shared in
  if not odd_name then Alcotest.skip ();
  Alcotest.(check (list string))
    "the warnings"
    [
      "the path caf\\xe9.md is not UTF-8, so sinter does not read the file";
      ledger;
    ]
    warnings;
  Alcotest.(check bool)
    "no record of the file" false
    (List.mem "req:cafe" (ids records))

let a_file_that_is_not_utf_8_text_gives_no_fact () =
  let _, _, { Scan.records; _ } = Lazy.force shared in
  Alcotest.(check (list string))
    "the declaration of docs/a.md alone" [ "req:a" ]
    (List.filter (fun id -> String.starts_with ~prefix:"req:" id) (ids records))

let load ?base repo =
  match
    Scan.load ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
      ~manifest:None ~base ()
  with
  | Ok tree -> tree
  | Error error ->
      Alcotest.failf "the load fails: %s" (String.concat "; " (messages error))

let shared_tree =
  lazy
    (let repo, _, _ = Lazy.force shared in
     (repo, load repo))

let head repo = String.trim (Git_fixture.git repo [ "rev-parse"; "HEAD" ])

let a_tree_holds_the_files_that_are_not_utf_8_text_apart () =
  let _, (tree : Scan.tree) = Lazy.force shared_tree in
  Alcotest.(check (pair (list string) (list (pair string int))))
    "the documents and the files that are not text"
    ([ ".plans/p.md"; "docs/a.md" ], [ ("binary.md", 10) ])
    (List.map fst tree.documents, tree.not_text)

let a_tree_with_no_base_takes_the_merge_base_with_the_default_branch () =
  let repo, tree = Lazy.force shared_tree in
  Alcotest.(check (pair string string))
    "the commit and the message"
    ( head repo,
      "base " ^ String.sub (head repo) 0 7 ^ ", the merge base of HEAD and main"
    )
    (Scan.base_commit tree.base, Scan.base_note tree.base)

let a_tree_with_a_base_names_its_revision () =
  let repo, _ = Lazy.force shared_tree in
  let tree = load ~base:"HEAD" repo in
  Alcotest.(check (pair string string))
    "the commit and the message"
    (head repo, "base " ^ String.sub (head repo) 0 7 ^ ", from --base HEAD")
    (Scan.base_commit tree.base, Scan.base_note tree.base)

let a_base_note_names_the_short_ref_and_the_short_commit () =
  let commit = "0123456789abcdef0123456789abcdef01234567" in
  Alcotest.(check (list string))
    "a remote branch, a local branch, another ref, a ref with a bidirectional \
     character, and a revision with a control character"
    [
      "base 0123456, the merge base of HEAD and origin/main";
      "base 0123456, the merge base of HEAD and main";
      "base 0123456, the merge base of HEAD and refs/other/main";
      "base 0123456, the merge base of HEAD and ma\xef\xbf\xbdin";
      "base 0123456, from --base x\xef\xbf\xbd[31m";
    ]
    (List.map Scan.base_note
       [
         Scan.Merge_base { refname = "refs/remotes/origin/main"; commit };
         Scan.Merge_base { refname = "refs/heads/main"; commit };
         Scan.Merge_base { refname = "refs/other/main"; commit };
         Scan.Merge_base { refname = "refs/heads/ma\xe2\x80\xaein"; commit };
         Scan.Given { revision = "x\x1b[31m"; commit };
       ])

let the_index_of_a_tree_is_the_first_record_of_its_scan () =
  let _, _, { Scan.records; _ } = Lazy.force shared in
  let _, tree = Lazy.force shared_tree in
  match (Scan.index tree ~tool:"v1", records) with
  | Ok index, first :: _ ->
      Alcotest.(check string)
        "the index" (Jsonl.to_string first) (Jsonl.to_string index)
  | Error _, _ -> Alcotest.fail "the index fails"
  | Ok _, [] -> Alcotest.fail "the scan gives no record"

let a_deleted_file_changes_the_tree_and_a_new_mode_does_not () =
  let _, _, { Scan.records; _ } = Lazy.force shared in
  let done_ id =
    match
      List.find_opt
        (fun record -> List.assoc_opt "id" record = Some (Jsonl.string id))
        records
    with
    | Some record -> List.assoc_opt "done" record
    | None -> None
  in
  Alcotest.(check (list (option bool)))
    "the done of the two steps" [ Some true; Some false ]
    (List.map
       (fun id -> Option.map (fun value -> value = Jsonl.bool true) (done_ id))
       [ "step:p/gone"; "step:p/mode" ])

let edited () =
  let repo =
    repository
      [
        ("sinter.toml", manifest);
        ("docs/a.md", "# A\n\n@req a\n");
        ("lib/old.ml", "old\n");
        (".plans/p.md", "# P\n\n@plan p\n\n## Old\n\n@scope lib/old.ml\n");
      ]
  in
  ignore (Git_fixture.git repo [ "repack"; "-q"; "-a"; "-d" ]);
  Git_fixture.write repo "docs/a.md" "# A\n\n@req b\n";
  Git_fixture.write repo "lib/old.ml" "new\n";
  Git_fixture.write repo "docs/new.md" "# N\n";
  repo

let a_scan_writes_no_file_under_the_git_directory () =
  let repo = edited () in
  let before = Git_fixture.git_dir_state repo in
  ignore (outcome (scan repo));
  Alcotest.(check (list string))
    "the files under .git" before
    (Git_fixture.git_dir_state repo)

let contains part text =
  let length = String.length part in
  let rec from index =
    index + length <= String.length text
    && (String.sub text index length = part || from (index + 1))
  in
  from 0

let repeated commands =
  List.filter
    (fun command ->
      List.length (List.filter (String.equal command) commands) > 1)
    (List.sort_uniq String.compare commands)

let a_scan_runs_no_git_command_twice () =
  let repo = edited () in
  let commands =
    Git_fixture.git_commands repo (fun env ->
        ignore
          (outcome
             (Scan.run ~env ~dir:(Git_fixture.root repo) ~manifest:None
                ~base:None ~tool:"v1" ())))
  in
  Alcotest.(check bool)
    "the scan ran the tree key and the diff" true
    (List.exists (contains "write-tree") commands
    && List.exists (contains "--no-ext-diff") commands);
  Alcotest.(check (list string)) "the repeated commands" [] (repeated commands)

let a_check_runs_no_git_command_twice () =
  let repo = edited () in
  let commands =
    Git_fixture.git_commands repo (fun env ->
        match
          Check.run ~env ~dir:(Git_fixture.root repo) ~manifest:None ~base:None
            ~mode:Mode.Tree ~gate:None ~strict:false ~form:Check.Json
            ~verbose:false ~quiet:false ~tool:"v1" ()
        with
        | Ok _ -> ()
        | Error error ->
            Alcotest.failf "the check fails: %s"
              (String.concat "; " (messages error)))
  in
  Alcotest.(check bool)
    "the check ran the tree key, the diff, and the read of blobs" true
    (List.exists (contains "write-tree") commands
    && List.exists (contains "--no-ext-diff") commands
    && List.exists (contains "cat-file") commands);
  Alcotest.(check (list string)) "the repeated commands" [] (repeated commands)

let outside =
  lazy
    (let repo = repository [ ("a.md", "# A\n") ] in
     let first = String.trim (Git_fixture.git repo [ "rev-parse"; "HEAD" ]) in
     ignore
       (Git_fixture.git repo [ "commit"; "-q"; "--allow-empty"; "-m"; "d" ]);
     let folder = Unix.realpath (Git_fixture.temp_dir ()) in
     let path = Filename.concat folder "outside.toml" in
     Out_channel.with_open_bin path (fun channel ->
         Out_channel.output_string channel manifest);
     (path, first, outcome (scan ~manifest:path ~base:"HEAD~1" repo)))

let index_field name { Scan.records; _ } =
  match records with
  | index :: _ -> field name index
  | [] -> Alcotest.fail "the scan gives no record"

let a_manifest_outside_the_repository_is_named_by_its_absolute_path () =
  let path, _, outcome = Lazy.force outside in
  Alcotest.(check string) "the manifest" path (index_field "manifest" outcome)

let a_base_is_the_commit_of_its_revision () =
  let _, first, outcome = Lazy.force outside in
  Alcotest.(check string) "the base" first (index_field "base" outcome)

let a_relative_manifest_is_relative_to_the_folder () =
  let repo, _, _ = Lazy.force shared in
  Alcotest.(check (list string))
    "the manifest of each scan from docs/"
    [ "sinter.toml"; "sinter.toml" ]
    (List.map
       (fun manifest ->
         index_field "manifest"
           (outcome (scan ~dir:"docs" ?manifest ~base:"HEAD" repo)))
       [ Some "../sinter.toml"; None ])

let a_head_with_no_commit_is_an_error () =
  let repo = repository [ ("sinter.toml", manifest) ] in
  ignore (Git_fixture.git repo [ "checkout"; "-q"; "--orphan"; "fresh" ]);
  Alcotest.(check string)
    "the message"
    "HEAD names no commit; make a commit, or name a base with --base"
    (failure (scan repo))

let a_head_with_no_common_ancestor_is_an_error () =
  let repo = repository [ ("sinter.toml", manifest) ] in
  ignore (Git_fixture.git repo [ "checkout"; "-q"; "--orphan"; "other" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "-m"; "o" ]);
  Alcotest.(check string)
    "the message"
    "HEAD and the branch 'main' have no common ancestor; name a base with \
     --base"
    (failure (scan repo))

let shallow repo revisions =
  Git_fixture.write repo ".git/shallow"
    (Git_fixture.git repo ("rev-parse" :: revisions))

let a_shallow_clone_with_no_default_branch_is_an_error () =
  let repo =
    repository [ ("sinter.toml", "default-branch = \"trunk\"\n\n" ^ manifest) ]
  in
  shallow repo [ "HEAD" ];
  Alcotest.(check string)
    "the message"
    "this clone is shallow, so the merge base of HEAD and the branch 'trunk' \
     is not here; fetch the whole history with git fetch --unshallow origin \
     trunk:refs/remotes/origin/trunk"
    (failure (scan repo))

let a_shallow_clone_with_no_merge_base_is_an_error () =
  let repo = repository [ ("sinter.toml", manifest) ] in
  ignore (Git_fixture.git repo [ "checkout"; "-q"; "-b"; "work" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "--allow-empty"; "-m"; "w" ]);
  ignore (Git_fixture.git repo [ "checkout"; "-q"; "main" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "--allow-empty"; "-m"; "m" ]);
  ignore (Git_fixture.git repo [ "checkout"; "-q"; "work" ]);
  shallow repo [ "main"; "work" ];
  Alcotest.(check string)
    "the message"
    "this clone is shallow, so the merge base of HEAD and the branch 'main' is \
     not here; fetch the whole history with git fetch --unshallow origin \
     main:refs/remotes/origin/main"
    (failure (scan repo))

let a_file_that_does_not_read_is_an_error () =
  let repo = repository [ ("sinter.toml", manifest); ("a.md", "# A\n") ] in
  let path = Filename.concat (Git_fixture.root repo) "a.md" in
  Unix.chmod path 0o000;
  Fun.protect
    ~finally:(fun () -> Unix.chmod path 0o644)
    (fun () ->
      match scan ~base:"HEAD" repo with
      | Error (Scan.Unreadable_file { file; _ }) ->
          Alcotest.(check string) "the file" "a.md" file
      | Ok _ | Error _ -> Alcotest.fail "the scan does not fail on the file")

let a_byte_outside_utf_8_shows_as_hex () =
  Alcotest.(check (list string))
    "the shown paths"
    [ "docs/caf\\xe9.md"; "a\\xe2\\x82b"; "caf\xc3\xa9.md"; "\\xff\\xfe"; "" ]
    (List.map Scan.escape_path
       [ "docs/caf\xe9.md"; "a\xe2\x82b"; "caf\xc3\xa9.md"; "\xff\xfe"; "" ])

let a_shown_path_is_utf_8 =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:500 ~name:"a shown path is valid UTF-8"
       ~print:QCheck2.Print.string
       QCheck2.Gen.(
         oneof [ Generators.not_utf_8_string; Generators.utf_8_string ])
       (fun path ->
         let shown = Scan.escape_path path in
         Sinter_bridge.Utf_8.is_valid shown
         && ((not (Sinter_bridge.Utf_8.is_valid path))
            || String.equal shown path)))

let a_plan_file_needs_the_pack_markdown_when_it_names_none () =
  let repo, _, _ = Lazy.force shared in
  let path = Filename.concat (Git_fixture.temp_dir ()) "only-ocaml.toml" in
  Out_channel.with_open_bin path (fun channel ->
      Out_channel.output_string channel
        "[scan]\n\
         packs.ocaml.files = [\"**/*.ml\"]\n\
         packs.ocaml.version = \"1.0\"\n");
  Alcotest.(check string)
    "the message"
    ".plans/p.md is under .plans/, and the pack markdown does not read it; add \
     \".plans/\" to the files of the pack markdown"
    (failure (scan ~manifest:path repo))

let sinter = Filename.concat (Sys.getcwd ()) "../bin/main.exe"

let into_a_closed_pipe command =
  let repo, _, _ = Lazy.force shared in
  let environment =
    Array.map
      (fun binding ->
        match Sys.getenv_opt "HOME" with
        | Some home when String.starts_with ~prefix:"HOME=" binding ->
            "HOME=" ^ home
        | Some _ | None -> binding)
      (Git_fixture.env repo)
  in
  let errors = Filename.temp_file "sinter-scan" ".err" in
  let reading, writing = Unix.pipe ~cloexec:true () in
  Unix.close reading;
  let previous = Sys.signal Sys.sigpipe Sys.Signal_ignore in
  Fun.protect
    ~finally:(fun () ->
      Sys.set_signal Sys.sigpipe previous;
      Sys.remove errors)
    (fun () ->
      let to_errors =
        Unix.openfile errors [ Unix.O_WRONLY; Unix.O_TRUNC; Unix.O_CLOEXEC ] 0
      in
      let pid =
        Fun.protect
          ~finally:(fun () ->
            Unix.close writing;
            Unix.close to_errors)
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
              environment Unix.stdin writing to_errors)
      in
      let status =
        match Unix.waitpid [] pid with
        | _, Unix.WEXITED code -> code
        | _, (Unix.WSIGNALED signal | Unix.WSTOPPED signal) -> -signal
      in
      (status, In_channel.with_open_bin errors In_channel.input_all))

let broken_pipe =
  [
    "error: cannot write the output: Broken pipe";
    "  = help: check that the output stays open and that the disk has space";
  ]

let a_scan_that_cannot_write_its_output_says_so () =
  let _, _, { Scan.warnings; _ } = Lazy.force shared in
  let status, errors = into_a_closed_pipe "scan" in
  Alcotest.(check (pair int (list string)))
    "the exit code and the lines of standard error"
    (3, List.map (fun warning -> "warning: " ^ warning) warnings @ broken_pipe)
    ( status,
      List.filter (fun line -> line <> "") (String.split_on_char '\n' errors) )

let a_check_that_cannot_write_its_output_says_so () =
  let status, errors = into_a_closed_pipe "check" in
  Alcotest.(check (pair int (list string)))
    "the exit code and the lines of standard error" (3, broken_pipe)
    ( status,
      List.filter (fun line -> line <> "") (String.split_on_char '\n' errors) )

let text { Error_text.fault; help; _ } = (fault, help)
let tree_errors = Sinter_bridge.Tree.[ Did_not_finish; Too_long ]

let text_file_errors =
  Text_file.
    [
      Is_a_directory;
      Cannot_open "a.md: the file does not open";
      Cannot_read "no read";
      Shorter_than_its_length;
      Not_utf_8 3;
    ]

let every_error =
  [
    Scan.Repository (Git.Git_not_found "no PATH");
    Scan.Repository (Git.Not_a_repository { dir = "/x"; detail = "d" });
    Scan.Repository (Git.Bad_revision "r");
    Scan.Repository (Git.Default_branch_not_found "m");
    Scan.Repository (Git.No_merge_base ("a", "b"));
    Scan.Repository
      (Git.Command_failed
         {
           args = [ "log"; "-1" ];
           status = Unix.WEXITED 128;
           stderr = "fatal: bad\nmore";
         });
    Scan.Repository
      (Git.Malformed_output { args = [ "log"; "-1" ]; detail = "no NUL" });
    Scan.Repository (Git.File_error "the index does not read");
    Scan.No_manifest;
    Scan.Missing_manifest "m.toml";
    Scan.Unreadable_manifest { path = "m.toml"; reason = "Is a directory" };
    Scan.Invalid_manifest
      { path = "m.toml"; text = "[scan]\n"; errors = [ Manifest.No_pack ] };
    Scan.Two_packs { file = "a.md"; pack = "markdown"; other = "ocaml" };
    Scan.Plan_not_read ".plans/p.md";
    Scan.Pack_not_available "ocaml";
    Scan.Bad_base "nope";
    Scan.Default_branch_not_found "trunk";
    Scan.No_merge_base "main";
    Scan.Shallow_clone "trunk";
    Scan.No_head;
  ]
  @ List.map
      (fun error -> Scan.Unreadable_file { file = "a.md"; error })
      text_file_errors
  @ List.map
      (fun error -> Scan.Unparsed_file { file = "a.md"; error })
      tree_errors
  @ List.map
      (fun error -> Scan.Unparsed_base_file { file = "b.md"; error })
      tree_errors
  @ [
      Scan.Reader (Markdown.Grammar (Sinter_bridge.Language.Version 9));
      Scan.Reader (Markdown.Query (Sinter_bridge.Query.Not_utf_8 3));
    ]

let constructor = function
  | Scan.Repository error -> (
      match error with
      | Git.Git_not_found _ -> "Git_not_found"
      | Git.Not_a_repository _ -> "Not_a_repository"
      | Git.Bad_revision _ -> "Bad_revision"
      | Git.Default_branch_not_found _ -> "Git.Default_branch_not_found"
      | Git.No_merge_base _ -> "Git.No_merge_base"
      | Git.Command_failed _ -> "Command_failed"
      | Git.Malformed_output _ -> "Malformed_output"
      | Git.File_error _ -> "File_error")
  | Scan.No_manifest -> "No_manifest"
  | Scan.Missing_manifest _ -> "Missing_manifest"
  | Scan.Unreadable_manifest _ -> "Unreadable_manifest"
  | Scan.Invalid_manifest _ -> "Invalid_manifest"
  | Scan.Two_packs _ -> "Two_packs"
  | Scan.Plan_not_read _ -> "Plan_not_read"
  | Scan.Pack_not_available _ -> "Pack_not_available"
  | Scan.Bad_base _ -> "Bad_base"
  | Scan.Default_branch_not_found _ -> "Default_branch_not_found"
  | Scan.No_merge_base _ -> "No_merge_base"
  | Scan.Shallow_clone _ -> "Shallow_clone"
  | Scan.No_head -> "No_head"
  | Scan.Unreadable_file { error; _ } -> (
      match error with
      | Text_file.Is_a_directory -> "Unreadable_file Is_a_directory"
      | Text_file.Cannot_open _ -> "Unreadable_file Cannot_open"
      | Text_file.Cannot_read _ -> "Unreadable_file Cannot_read"
      | Text_file.Shorter_than_its_length ->
          "Unreadable_file Shorter_than_its_length"
      | Text_file.Not_utf_8 _ -> "Unreadable_file Not_utf_8")
  | Scan.Unparsed_file { error; _ } -> (
      match error with
      | Sinter_bridge.Tree.Did_not_finish -> "Unparsed_file Did_not_finish"
      | Sinter_bridge.Tree.Too_long -> "Unparsed_file Too_long")
  | Scan.Unparsed_base_file { error; _ } -> (
      match error with
      | Sinter_bridge.Tree.Did_not_finish -> "Unparsed_base_file Did_not_finish"
      | Sinter_bridge.Tree.Too_long -> "Unparsed_base_file Too_long")
  | Scan.Reader (Markdown.Grammar _) -> "Reader Grammar"
  | Scan.Reader (Markdown.Query _) -> "Reader Query"

let every_error_has_a_fault_and_a_help () =
  Alcotest.(check int)
    "the examples are of 31 distinct cases, the cases that [constructor] names"
    31
    (List.length
       (List.sort_uniq String.compare (List.map constructor every_error)));
  List.iter
    (fun error ->
      List.iter
        (fun { Error_text.fault; help; place = _ } ->
          Alcotest.(check bool)
            (constructor error ^ " has a fault and a help")
            true
            (fault <> "" && help <> ""))
        (Scan.explain error))
    every_error

let each_error_says_what_is_wrong_and_what_to_do () =
  let manifest_error =
    match Manifest.of_string "[scan]\n" with
    | Error errors -> errors
    | Ok _ -> Alcotest.fail "the manifest has no error"
  in
  Alcotest.(check (list (list (pair string string))))
    "the faults and the helps"
    [
      [
        ( "cannot start git: no PATH",
          "install git 2.43.7 or later, and put it on PATH" );
      ];
      [
        ( "the folder /x is in no git repository",
          "run sinter inside the working tree of a git repository" );
      ];
      [ ("'r' names no commit", "name a revision that names a commit") ];
      [
        ( "no branch 'm' exists",
          "set 'default-branch' in sinter.toml to the name of the default \
           branch" );
      ];
      [ ("a and b have no common ancestor", "name a base with --base") ];
      [
        ( "git log -1 failed: fatal: bad",
          "run the same git command in the repository to see the whole message"
        );
      ];
      [
        ( "git log -1 gave output that sinter cannot read: no NUL",
          "use git 2.43.7 or later; with such a git, report this as a fault of \
           sinter" );
      ];
      [
        ( "the index does not read",
          "check that you can read and write the file, and that the disk has \
           space" );
      ];
      [
        ( "no sinter.toml at the repository root",
          "create one, or name one with --manifest" );
      ];
      [
        ("no manifest at m.toml", "name a manifest that exists with --manifest");
      ];
      [
        ( "cannot read the manifest m.toml: Is a directory",
          "name a manifest that is a file that you can read" );
      ];
      List.map text (List.map (Manifest.explain ~path:"m.toml") manifest_error);
      [
        ( "a.md is in the files of two packs, markdown and ocaml",
          "add a '!' glob to one of them" );
      ];
      [
        ( ".plans/p.md is under .plans/, and the pack markdown does not read it",
          "add \".plans/\" to the files of the pack markdown" );
      ];
      [
        ( "the pack ocaml is not in the cache of packs",
          "run sinter pack add ocaml" );
      ];
      [
        ( "the base 'nope' names no commit",
          "give --base a revision that names a commit" );
      ];
      [
        ( "no branch 'trunk' exists here or on origin",
          "fetch it with git fetch origin trunk:refs/remotes/origin/trunk, or \
           set 'default-branch' in sinter.toml to the name of the default \
           branch" );
      ];
      [
        ( "HEAD and the branch 'main' have no common ancestor",
          "name a base with --base" );
      ];
      [
        ( "this clone is shallow, so the merge base of HEAD and the branch \
           'trunk' is not here",
          "fetch the whole history with git fetch --unshallow origin \
           trunk:refs/remotes/origin/trunk" );
      ];
      [ ("HEAD names no commit", "make a commit, or name a base with --base") ];
      [
        ( "a.md: the file does not open",
          "make the file readable, or leave it out of the files of the pack \
           markdown with a '!' glob" );
      ];
      [
        ( "a.md: " ^ Sinter_bridge.Tree.message Sinter_bridge.Tree.Did_not_finish,
          "leave the file out of the files of the pack markdown with a '!' glob"
        );
      ];
      [
        ( "b.md at the base: "
          ^ Sinter_bridge.Tree.message Sinter_bridge.Tree.Too_long,
          "name another base with --base" );
      ];
      [
        ( "the built-in grammar of markdown does not load: "
          ^ Sinter_bridge.Language.message (Sinter_bridge.Language.Version 9),
          "report this as a fault of sinter" );
      ];
      [
        ( "the built-in query of markdown does not compile: "
          ^ Sinter_bridge.Query.message (Sinter_bridge.Query.Not_utf_8 3),
          "report this as a fault of sinter" );
      ];
    ]
    (List.map
       (fun error -> List.map text (Scan.explain error))
       [
         Scan.Repository (Git.Git_not_found "no PATH");
         Scan.Repository (Git.Not_a_repository { dir = "/x"; detail = "d" });
         Scan.Repository (Git.Bad_revision "r");
         Scan.Repository (Git.Default_branch_not_found "m");
         Scan.Repository (Git.No_merge_base ("a", "b"));
         Scan.Repository
           (Git.Command_failed
              {
                args = [ "log"; "-1" ];
                status = Unix.WEXITED 128;
                stderr = "fatal: bad\nmore";
              });
         Scan.Repository
           (Git.Malformed_output { args = [ "log"; "-1" ]; detail = "no NUL" });
         Scan.Repository (Git.File_error "the index does not read");
         Scan.No_manifest;
         Scan.Missing_manifest "m.toml";
         Scan.Unreadable_manifest { path = "m.toml"; reason = "Is a directory" };
         Scan.Invalid_manifest
           { path = "m.toml"; text = "[scan]\n"; errors = manifest_error };
         Scan.Two_packs { file = "a.md"; pack = "markdown"; other = "ocaml" };
         Scan.Plan_not_read ".plans/p.md";
         Scan.Pack_not_available "ocaml";
         Scan.Bad_base "nope";
         Scan.Default_branch_not_found "trunk";
         Scan.No_merge_base "main";
         Scan.Shallow_clone "trunk";
         Scan.No_head;
         Scan.Unreadable_file
           {
             file = "a.md";
             error = Text_file.Cannot_open "a.md: the file does not open";
           };
         Scan.Unparsed_file
           { file = "a.md"; error = Sinter_bridge.Tree.Did_not_finish };
         Scan.Unparsed_base_file
           { file = "b.md"; error = Sinter_bridge.Tree.Too_long };
         Scan.Reader (Markdown.Grammar (Sinter_bridge.Language.Version 9));
         Scan.Reader (Markdown.Query (Sinter_bridge.Query.Not_utf_8 3));
       ])

let blocks text =
  match Manifest.of_string text with
  | Ok _ -> [ "no error" ]
  | Error errors ->
      let buffer = Buffer.create 256 in
      let ppf = Format.formatter_of_buffer buffer in
      Style.prepare ppf `None;
      Render.errors ppf
        (Scan.explain
           (Scan.Invalid_manifest { path = "sinter.toml"; text; errors }));
      Format.pp_print_flush ppf ();
      String.split_on_char '\n' (Buffer.contents buffer)

let markdown_pack = "[scan]\npacks.markdown.files = [\"**/*.md\"]\n"

let a_manifest_error_shows_its_source_line () =
  List.iter
    (fun (name, text, expected) ->
      Alcotest.(check (list string)) name expected (blocks text))
    [
      ( "a key",
        markdown_pack ^ "[paths]\nhistoric = []\n",
        [
          "error: unknown key 'historic' in [paths]";
          " --> sinter.toml:4:1";
          "  |";
          "4 | historic = []";
          "  | ^^^^^^^^";
          "  |";
          "  = help: did you mean 'historical'?";
          "";
        ] );
      ( "a value",
        markdown_pack ^ "[check]\nwarn-only = \"yes\"\n",
        [
          "error: 'warn-only' takes true or false, not a string";
          " --> sinter.toml:4:13";
          "  |";
          "4 | warn-only = \"yes\"";
          "  |             ^^^^^";
          "  |";
          "  = help: write true or false";
          "";
        ] );
      ( "the part of a dotted key",
        "paths.historic = []\n" ^ markdown_pack,
        [
          "error: unknown key 'historic' in [paths]";
          " --> sinter.toml:1:7";
          "  |";
          "1 | paths.historic = []";
          "  |       ^^^^^^^^";
          "  |";
          "  = help: did you mean 'historical'?";
          "";
        ] );
      ( "a syntax error at the end of its line",
        "[scan\n",
        [
          "error: the table header is not valid";
          " --> sinter.toml:1:6";
          "  |";
          "1 | [scan";
          "  |      ^";
          "  |";
          "  = help: write ']' here";
          "";
        ] );
      ( "a wide character and a tab before the span",
        "default-branch = \"\xe6\x97\xa5\t..b\"\n" ^ markdown_pack,
        [
          "error: \"\xe6\x97\xa5\\t..b\" is not a branch name; a branch name \
           cannot hold a control character";
          " --> sinter.toml:1:20";
          "  |";
          "1 | default-branch = \"\xe6\x97\xa5    ..b\"";
          "  |                     ^^^^";
          "  |";
          "  = help: write the name of the default branch";
          "";
        ] );
      ( "no pack",
        "[scan]\n",
        [
          "error: sinter.toml names no pack";
          "  = help: add a line such as packs.markdown.files = [\"**/*.md\"] \
           under [scan]";
          "";
        ] );
      ( "several errors, in the order of their places",
        markdown_pack ^ "[check]\nzz = 1\nwarn-only = 1\n",
        [
          "error: unknown key 'zz' in [check]";
          " --> sinter.toml:4:1";
          "  |";
          "4 | zz = 1";
          "  | ^^";
          "  |";
          "  = help: remove this key, or correct its name";
          "";
          "error: 'warn-only' takes true or false, not an integer";
          " --> sinter.toml:5:13";
          "  |";
          "5 | warn-only = 1";
          "  |             ^";
          "  |";
          "  = help: write true or false";
          "";
        ] );
    ]

let a_manifest_error_with_no_text_shows_no_source_line () =
  match Manifest.of_string (markdown_pack ^ "[paths]\nhistoric = []\n") with
  | Ok _ -> Alcotest.fail "the manifest has no error"
  | Error errors ->
      Alcotest.(check (list (option string)))
        "the line of each error, from an empty text" [ None ]
        (List.map
           (fun { Error_text.place; _ } ->
             Option.bind place (fun { Error_text.line; _ } -> line))
           (Scan.explain
              (Scan.Invalid_manifest { path = "sinter.toml"; text = ""; errors })))

let with_base ?(manifest = manifest) files =
  repository (("sinter.toml", manifest) :: files)

let load_with_base repo =
  match
    Scan.load_with_base ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
      ~manifest:None ~base:(Some "HEAD") ()
  with
  | Ok loaded -> loaded
  | Error error ->
      Alcotest.failf "the load fails: %s" (String.concat "; " (messages error))

let declared (document : Markdown.t) =
  List.filter_map
    (fun (tag : Markdown.tag) ->
      Option.map (fun target -> tag.word ^ " " ^ target) tag.target)
    (Array.to_list document.tags)

let the_base_reuses_each_document_that_the_diff_does_not_change () =
  let repo =
    with_base
      [
        ("same.md", "# S\n\n@req same\n");
        ("untracked.md", "# U\n\n@req untracked\n");
        ("mode.md", "# M\n\n@req mode\n");
      ]
  in
  ignore (Git_fixture.git repo [ "rm"; "-q"; "--cached"; "untracked.md" ]);
  Git_fixture.make_executable repo "mode.md";
  let tree, compared = load_with_base repo in
  Alcotest.(check (list string))
    "the paths of the base"
    [ "mode.md"; "same.md"; "untracked.md" ]
    (List.map fst compared.base_documents);
  List.iter
    (fun (path, document) ->
      Alcotest.(check bool)
        (path ^ " is the document of the working tree")
        true
        (List.assq_opt document (List.map (fun (p, d) -> (d, p)) tree.documents)
        = Some path))
    compared.base_documents

let the_base_reads_each_changed_file_from_its_blob () =
  let repo =
    with_base
      [
        ("changed.md", "# C\n\n@req old-slug\n");
        ("deleted.md", "# D\n\n@req deleted\n");
        ("notes.txt", "@req not-markdown\n");
      ]
  in
  Git_fixture.write repo "changed.md" "# C\n\n@req new-slug\n";
  Git_fixture.remove repo "deleted.md";
  Git_fixture.write repo "added.md" "# A\n\n@req added\n";
  let _, compared = load_with_base repo in
  Alcotest.(check (list (pair string (list string))))
    "the tags of the base"
    [ ("changed.md", [ "req old-slug" ]); ("deleted.md", [ "req deleted" ]) ]
    (List.map
       (fun (path, document) -> (path, declared document))
       compared.base_documents);
  Alcotest.(check (list string))
    "the paths of the diff"
    [ "added.md"; "changed.md"; "deleted.md" ]
    (List.map fst compared.diff)

let a_blob_that_is_not_utf_8_is_not_text_at_the_base () =
  let repo =
    with_base [ ("was-bad.md", "# B\n\xff\n"); ("still-bad.md", "# S\n\xfe\n") ]
  in
  Git_fixture.write repo "was-bad.md" "# B\n\n@req good\n";
  let tree, compared = load_with_base repo in
  Alcotest.(check (list (pair string int)))
    "the files of the base that are not text"
    [ ("still-bad.md", 4); ("was-bad.md", 4) ]
    compared.base_not_text;
  Alcotest.(check (list (pair string int)))
    "the files of the working tree that are not text"
    [ ("still-bad.md", 4) ]
    tree.not_text;
  Alcotest.(check (list string))
    "the documents of the base" []
    (List.map fst compared.base_documents)

let a_conversion_alone_reuses_the_document () =
  let repo = with_base [ ("crlf.md", "# C\n\n@req crlf\n") ] in
  Git_fixture.append_config repo "[core]\n\tautocrlf = true\n";
  Git_fixture.write repo "crlf.md" "# C\r\n\r\n@req crlf\r\n";
  let tree, compared = load_with_base repo in
  Alcotest.(check int) "no change" 0 (List.length compared.diff);
  Alcotest.(check bool)
    "the same document" true
    (match (tree.documents, compared.base_documents) with
    | [ (_, a) ], [ (_, b) ] -> a == b
    | _ -> false)

let a_path_warning_holds_no_control_character () =
  let repo = Git_fixture.init () in
  Git_fixture.import repo
    [
      Git_fixture.commit ~ref:"refs/heads/main" ~mark:1 ~message:"base"
        [
          Git_fixture.File ("sinter.toml", manifest);
          Git_fixture.File ("a\x1b[31m\xc2\x9b\xe2\x80\xae\xff.md", "# G\n");
        ];
    ];
  Git_fixture.write repo "sinter.toml" manifest;
  let tree, _ = load_with_base repo in
  Alcotest.(check (list string))
    "the warnings"
    [
      "the path a\xef\xbf\xbd[31m\xef\xbf\xbd\xef\xbf\xbd\\xff.md is not \
       UTF-8, so sinter does not read the file";
    ]
    tree.warnings

let a_base_path_that_is_not_utf_8_gives_one_warning () =
  let repo = Git_fixture.init () in
  Git_fixture.import repo
    [
      Git_fixture.commit ~ref:"refs/heads/main" ~mark:1 ~message:"base"
        [
          Git_fixture.File ("sinter.toml", manifest);
          Git_fixture.File ("gone\xff.md", "# G\n");
        ];
    ];
  Git_fixture.write repo "sinter.toml" manifest;
  let tree, _ = load_with_base repo in
  Alcotest.(check (list string))
    "the warnings"
    [ "the path gone\\xff.md is not UTF-8, so sinter does not read the file" ]
    tree.warnings

let the_ledger_warning_needs_a_plan_and_no_ledger () =
  let warning files ~ledger =
    let repo = repository (("sinter.toml", manifest) :: files) in
    if ledger then
      ignore
        (Git_fixture.git repo [ "update-ref"; "refs/sinter/ledger"; "HEAD" ]);
    let tree = load repo in
    Scan.ledger_warning tree (Facts.make tree.manifest tree.documents)
  in
  let plan = (".plans/p.md", "# P\n\n@plan p\n") in
  Alcotest.(check (list (option string)))
    "no ledger and a plan, no ledger and no plan, a ledger and a plan"
    [ Some ledger; None; None ]
    [
      warning [ plan ] ~ledger:false;
      warning [ ("docs/a.md", "# A\n\n@req a\n") ] ~ledger:false;
      warning [ plan ] ~ledger:true;
    ]

let base_manifest (compared : Scan.compared) =
  match compared.base_manifest with
  | Scan.Outside -> "outside"
  | Scan.Absent -> "absent"
  | Scan.Unchanged -> "unchanged"
  | Scan.Changed text -> "changed " ^ text

let warn_only = manifest ^ "[check]\nwarn-only = true\n"

let the_base_reads_the_manifest_only_when_the_diff_changes_it () =
  let unchanged = with_base [ ("a.md", "# A\n") ] in
  Git_fixture.make_executable unchanged "sinter.toml";
  Alcotest.(check string)
    "an unchanged manifest" "unchanged"
    (base_manifest (snd (load_with_base unchanged)));
  let changed =
    with_base ~manifest:warn_only
      [ ("a.md", "# A\n\n@req old\n"); ("b.md", "# B\n\n@req b\n") ]
  in
  Git_fixture.write changed "sinter.toml" manifest;
  Git_fixture.write changed "a.md" "# A\n\n@req new\n";
  let _, compared = load_with_base changed in
  Alcotest.(check string)
    "a changed manifest" ("changed " ^ warn_only) (base_manifest compared);
  Alcotest.(check (list (pair string (list string))))
    "the documents of the base beside it"
    [ ("a.md", [ "req old" ]); ("b.md", [ "req b" ]) ]
    (List.map
       (fun (path, document) -> (path, declared document))
       compared.base_documents)

let a_manifest_that_the_base_does_not_hold_is_absent () =
  let added = repository [ ("a.md", "# A\n") ] in
  Git_fixture.write added "sinter.toml" manifest;
  Alcotest.(check string)
    "an added manifest" "absent"
    (base_manifest (snd (load_with_base added)));
  let ignored =
    repository [ (".gitignore", "sinter.toml\n"); ("a.md", "# A\n") ]
  in
  Git_fixture.write ignored "sinter.toml" manifest;
  let _, compared = load_with_base ignored in
  Alcotest.(check string)
    "an ignored manifest" "absent" (base_manifest compared);
  Alcotest.(check (list string)) "the diff" [] (List.map fst compared.diff)

let a_manifest_outside_the_repository_has_no_base () =
  let repo = with_base [ ("a.md", "# A\n") ] in
  let path =
    Filename.concat (Unix.realpath (Git_fixture.temp_dir ())) "o.toml"
  in
  Out_channel.with_open_bin path (fun channel ->
      Out_channel.output_string channel manifest);
  match
    Scan.load_with_base ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
      ~manifest:(Some path) ~base:(Some "HEAD") ()
  with
  | Ok (_, compared) ->
      Alcotest.(check string) "the base" "outside" (base_manifest compared)
  | Error error ->
      Alcotest.failf "the load fails: %s" (String.concat "; " (messages error))

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "the base reads the manifest only when the diff changes it"
      the_base_reads_the_manifest_only_when_the_diff_changes_it;
    case "a manifest that the base does not hold is absent"
      a_manifest_that_the_base_does_not_hold_is_absent;
    case "a manifest outside the repository has no base"
      a_manifest_outside_the_repository_has_no_base;
    case "the base reuses each document that the diff does not change"
      the_base_reuses_each_document_that_the_diff_does_not_change;
    case "the base reads each changed file from its blob"
      the_base_reads_each_changed_file_from_its_blob;
    case "a blob that is not UTF-8 is not text at the base"
      a_blob_that_is_not_utf_8_is_not_text_at_the_base;
    case "a conversion alone reuses the document"
      a_conversion_alone_reuses_the_document;
    case "a base path that is not UTF-8 gives one warning"
      a_base_path_that_is_not_utf_8_gives_one_warning;
    case "a path warning holds no control character"
      a_path_warning_holds_no_control_character;
    case "a base note names the short ref and the short commit"
      a_base_note_names_the_short_ref_and_the_short_commit;
    case "a scan starts with the index of the tree and the base"
      a_scan_starts_with_the_index_of_the_tree_and_the_base;
    case "a path that is not UTF-8 gives a warning and no fact"
      a_path_that_is_not_utf_8_gives_a_warning_and_no_fact;
    case "a file that is not UTF-8 text gives no fact"
      a_file_that_is_not_utf_8_text_gives_no_fact;
    case "a tree holds the files that are not UTF-8 text apart"
      a_tree_holds_the_files_that_are_not_utf_8_text_apart;
    case "a tree with no base takes the merge base with the default branch"
      a_tree_with_no_base_takes_the_merge_base_with_the_default_branch;
    case "a tree with a base names its revision"
      a_tree_with_a_base_names_its_revision;
    case "the index of a tree is the first record of its scan"
      the_index_of_a_tree_is_the_first_record_of_its_scan;
    case "a deleted file changes the tree, and a new mode does not"
      a_deleted_file_changes_the_tree_and_a_new_mode_does_not;
    case "a scan writes no file under the git directory"
      a_scan_writes_no_file_under_the_git_directory;
    case "a scan runs no git command twice" a_scan_runs_no_git_command_twice;
    case "a check runs no git command twice" a_check_runs_no_git_command_twice;
    case "a manifest outside the repository is named by its absolute path"
      a_manifest_outside_the_repository_is_named_by_its_absolute_path;
    case "a relative manifest is relative to the folder"
      a_relative_manifest_is_relative_to_the_folder;
    case "a base is the commit of its revision"
      a_base_is_the_commit_of_its_revision;
    case "a HEAD with no commit is an error" a_head_with_no_commit_is_an_error;
    case "a HEAD with no common ancestor is an error"
      a_head_with_no_common_ancestor_is_an_error;
    case "a shallow clone with no default branch is an error"
      a_shallow_clone_with_no_default_branch_is_an_error;
    case "a shallow clone with no merge base is an error"
      a_shallow_clone_with_no_merge_base_is_an_error;
    case "a file that does not read is an error"
      a_file_that_does_not_read_is_an_error;
    case "a byte outside UTF-8 shows as hex" a_byte_outside_utf_8_shows_as_hex;
    a_shown_path_is_utf_8;
    case "a plan file needs the pack markdown when it names none"
      a_plan_file_needs_the_pack_markdown_when_it_names_none;
    case "a scan that cannot write its output says so"
      a_scan_that_cannot_write_its_output_says_so;
    Alcotest.test_case "the ledger warning needs a plan and no ledger" `Quick
      the_ledger_warning_needs_a_plan_and_no_ledger;
    case "a check that cannot write its output says so"
      a_check_that_cannot_write_its_output_says_so;
    case "every error has a fault and a help" every_error_has_a_fault_and_a_help;
    case "a manifest error shows its source line"
      a_manifest_error_shows_its_source_line;
    case "a manifest error with no text shows no source line"
      a_manifest_error_with_no_text_shows_no_source_line;
    case "each error says what is wrong and what to do"
      each_error_says_what_is_wrong_and_what_to_do;
  ]
