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

let outcome = function
  | Ok outcome -> outcome
  | Error error ->
      Alcotest.failf "the scan fails: %s"
        (String.concat "; " (Scan.messages error))

let failure = function
  | Ok _ -> Alcotest.fail "the scan gives an outcome"
  | Error error -> String.concat "\n" (Scan.messages error)

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

let ledger =
  "warning: the ledger ref refs/sinter/ledger is absent, so every plan counts \
   as open; fetch it with git fetch origin \
   refs/sinter/ledger:refs/sinter/ledger"

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
      "warning: the path caf\\xe9.md is not UTF-8, so sinter does not read the \
       file";
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
      Alcotest.failf "the load fails: %s"
        (String.concat "; " (Scan.messages error))

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

let a_tree_with_no_base_takes_the_merge_base_with_the_target () =
  let repo, tree = Lazy.force shared_tree in
  Alcotest.(check (pair string string))
    "the commit and the message"
    ( head repo,
      "the base is the merge base of HEAD and refs/heads/main, " ^ head repo )
    (Scan.base_commit tree.base, Scan.base_message tree.base)

let a_tree_with_a_base_names_its_revision () =
  let repo, _ = Lazy.force shared_tree in
  let tree = load ~base:"HEAD" repo in
  Alcotest.(check (pair string string))
    "the commit and the message"
    (head repo, "the base is HEAD, " ^ head repo)
    (Scan.base_commit tree.base, Scan.base_message tree.base)

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

let a_shallow_clone_with_no_target_branch_is_an_error () =
  let repo =
    repository [ ("sinter.toml", "target = \"trunk\"\n\n" ^ manifest) ]
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
     \".plans/\" to its files"
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

let a_scan_that_cannot_write_its_output_says_so () =
  let _, _, { Scan.warnings; _ } = Lazy.force shared in
  let status, errors = into_a_closed_pipe "scan" in
  Alcotest.(check (pair int (list string)))
    "the exit code and the lines of standard error"
    ( 3,
      List.map (fun warning -> "sinter: " ^ warning) warnings
      @ [ "sinter: cannot write the output: Broken pipe" ] )
    ( status,
      List.filter (fun line -> line <> "") (String.split_on_char '\n' errors) )

let a_check_that_cannot_write_its_output_says_so () =
  let _, (tree : Scan.tree) = Lazy.force shared_tree in
  let status, errors = into_a_closed_pipe "check" in
  Alcotest.(check (pair int (list string)))
    "the exit code and the lines of standard error"
    ( 3,
      List.map
        (fun line -> "sinter: " ^ line)
        ((Scan.base_message tree.base :: tree.warnings)
        @ [ "cannot write the output: Broken pipe" ]) )
    ( status,
      List.filter (fun line -> line <> "") (String.split_on_char '\n' errors) )

let each_error_says_what_is_wrong () =
  let manifest_error =
    match Manifest.of_string "[scan]\n" with
    | Error errors -> errors
    | Ok _ -> Alcotest.fail "the manifest has no error"
  in
  Alcotest.(check (list (list string)))
    "the messages"
    [
      [ "cannot start git: no PATH" ];
      [ "the folder /x is in no git repository" ];
      [ "'r' names no commit" ];
      [ "no branch 'm' exists" ];
      [ "a and b have no common ancestor" ];
      [ "git log -1 failed: fatal: bad" ];
      [ "git log -1 gave output that sinter cannot read: no NUL" ];
      [ "the index does not read" ];
      [
        "no sinter.toml at the repository root; create one, or name one with \
         --manifest";
      ];
      [ "no manifest at m.toml" ];
      [ "cannot read the manifest m.toml: Is a directory" ];
      List.map (Manifest.render ~path:"m.toml") manifest_error;
      [
        "a.md is in the files of two packs, markdown and ocaml; add a '!' glob \
         to one of them";
      ];
      [
        ".plans/p.md is under .plans/, and the pack markdown does not read it; \
         add \".plans/\" to its files";
      ];
      [
        "the pack ocaml is not in the cache of packs; run sinter pack add ocaml";
      ];
      [ "the base 'nope' names no commit" ];
      [
        "no branch 'trunk' exists here or on origin; fetch it with git fetch \
         origin trunk:refs/remotes/origin/trunk, or set 'target' in \
         sinter.toml to the name of the main branch";
      ];
      [
        "HEAD and the branch 'main' have no common ancestor; name a base with \
         --base";
      ];
      [
        "this clone is shallow, so the merge base of HEAD and the branch \
         'trunk' is not here; fetch the whole history with git fetch \
         --unshallow origin trunk:refs/remotes/origin/trunk";
      ];
      [ "HEAD names no commit; make a commit, or name a base with --base" ];
      [ "a.md: the file does not open" ];
      [
        "a.md: " ^ Sinter_bridge.Tree.message Sinter_bridge.Tree.Did_not_finish;
      ];
      [
        "the built-in grammar of markdown does not load: "
        ^ Sinter_bridge.Language.message (Sinter_bridge.Language.Version 9);
      ];
      [
        "the built-in query of markdown does not compile: "
        ^ Sinter_bridge.Query.message (Sinter_bridge.Query.Not_utf_8 3);
      ];
    ]
    (List.map Scan.messages
       [
         Scan.Repository (Git.Git_not_found "no PATH");
         Scan.Repository (Git.Not_a_repository { dir = "/x"; detail = "d" });
         Scan.Repository (Git.Bad_revision "r");
         Scan.Repository (Git.Target_not_found "m");
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
         Scan.Invalid_manifest { path = "m.toml"; errors = manifest_error };
         Scan.Two_packs { file = "a.md"; pack = "markdown"; other = "ocaml" };
         Scan.Plan_not_read ".plans/p.md";
         Scan.Pack_not_available "ocaml";
         Scan.Bad_base "nope";
         Scan.Target_not_found "trunk";
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
         Scan.Reader (Markdown.Grammar (Sinter_bridge.Language.Version 9));
         Scan.Reader (Markdown.Query (Sinter_bridge.Query.Not_utf_8 3));
       ])

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "a scan starts with the index of the tree and the base"
      a_scan_starts_with_the_index_of_the_tree_and_the_base;
    case "a path that is not UTF-8 gives a warning and no fact"
      a_path_that_is_not_utf_8_gives_a_warning_and_no_fact;
    case "a file that is not UTF-8 text gives no fact"
      a_file_that_is_not_utf_8_text_gives_no_fact;
    case "a tree holds the files that are not UTF-8 text apart"
      a_tree_holds_the_files_that_are_not_utf_8_text_apart;
    case "a tree with no base takes the merge base with the target"
      a_tree_with_no_base_takes_the_merge_base_with_the_target;
    case "a tree with a base names its revision"
      a_tree_with_a_base_names_its_revision;
    case "the index of a tree is the first record of its scan"
      the_index_of_a_tree_is_the_first_record_of_its_scan;
    case "a deleted file changes the tree, and a new mode does not"
      a_deleted_file_changes_the_tree_and_a_new_mode_does_not;
    case "a manifest outside the repository is named by its absolute path"
      a_manifest_outside_the_repository_is_named_by_its_absolute_path;
    case "a relative manifest is relative to the folder"
      a_relative_manifest_is_relative_to_the_folder;
    case "a base is the commit of its revision"
      a_base_is_the_commit_of_its_revision;
    case "a HEAD with no commit is an error" a_head_with_no_commit_is_an_error;
    case "a HEAD with no common ancestor is an error"
      a_head_with_no_common_ancestor_is_an_error;
    case "a shallow clone with no target branch is an error"
      a_shallow_clone_with_no_target_branch_is_an_error;
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
    case "a check that cannot write its output says so"
      a_check_that_cannot_write_its_output_says_so;
    case "each error says what is wrong" each_error_says_what_is_wrong;
  ]
