(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Repo = Git_fixture

let opened repo =
  match Git.open_repo ~env:(Repo.env repo) (Repo.root repo) with
  | Ok t -> t
  | Error _ -> Alcotest.fail "the repository does not open"

let hunk line eline ecol old_line added removed : Git.hunk =
  { line; eline; ecol; old_line; added; removed }

let with_base files =
  let repo = Repo.init () in
  List.iter (fun (path, content) -> Repo.write repo path content) files;
  ignore (Repo.git repo [ "add"; "-A" ]);
  ignore (Repo.git repo [ "commit"; "-q"; "-m"; "base" ]);
  repo

let diff_against t rev =
  Result.bind (Git.read_base t rev) (fun base ->
      Result.bind (Git.files t) (fun files -> Git.diff t ~files ~base))

let diff repo =
  match diff_against (opened repo) "HEAD" with
  | Ok changes -> changes
  | Error _ -> Alcotest.fail "the diff fails"

let shown repo =
  List.map
    (fun (path, change) -> path ^ " " ^ Generators.print_change change)
    (diff repo)

let strings = Alcotest.(list string)
let show path change = path ^ " " ^ Generators.print_change change

let a_flagged_entry_is_compared_by_its_content () =
  let repo = with_base [ ("au.txt", "1\n2\n"); ("sw.txt", "1\n2\n") ] in
  ignore (Repo.git repo [ "update-index"; "--assume-unchanged"; "au.txt" ]);
  ignore (Repo.git repo [ "update-index"; "--skip-worktree"; "sw.txt" ]);
  Repo.write repo "au.txt" "1\nA\n";
  Repo.write repo "sw.txt" "1\nS\n";
  Alcotest.check strings "both changes"
    [
      show "au.txt" (Git.Modified (Git.Text [ hunk 2 2 2 2 1 1 ]));
      show "sw.txt" (Git.Modified (Git.Text [ hunk 2 2 2 2 1 1 ]));
    ]
    (shown repo);
  Alcotest.check strings "the flags stay in the index"
    [ "h au.txt"; "S sw.txt" ]
    (List.filter
       (fun line -> line <> "")
       (String.split_on_char '\n' (Repo.git repo [ "ls-files"; "-v" ])))

let an_entry_with_both_flags_is_compared_by_its_content () =
  let repo = with_base [ ("both.txt", "1\n") ] in
  ignore
    (Repo.git repo
       [ "update-index"; "--assume-unchanged"; "--skip-worktree"; "both.txt" ]);
  Repo.write repo "both.txt" "2\n";
  Alcotest.check strings "the change"
    [ show "both.txt" (Git.Modified (Git.Text [ hunk 1 1 2 1 1 1 ])) ]
    (shown repo)

let an_untracked_file_of_the_base_is_compared_with_its_blob () =
  let repo = with_base [ ("same.txt", "a\nb\n"); ("edit.txt", "a\nb\n") ] in
  ignore (Repo.git repo [ "rm"; "-q"; "--cached"; "same.txt"; "edit.txt" ]);
  Repo.write repo "edit.txt" "a\nB\n";
  Alcotest.check strings "only the edit"
    [ show "edit.txt" (Git.Modified (Git.Text [ hunk 2 2 2 2 1 1 ])) ]
    (shown repo)

let an_intent_to_add_entry_is_compared_like_any_file () =
  let repo = with_base [ ("kept.txt", "a\n") ] in
  ignore (Repo.git repo [ "rm"; "-q"; "--cached"; "kept.txt" ]);
  ignore (Repo.git repo [ "add"; "-N"; "kept.txt" ]);
  Repo.write repo "new.txt" "x\ny\n";
  ignore (Repo.git repo [ "add"; "-N"; "new.txt" ]);
  Alcotest.check strings "the new file only"
    [ show "new.txt" (Git.Added (Git.Text [ hunk 1 2 2 1 2 0 ])) ]
    (shown repo)

let a_glob_character_in_an_untracked_name_is_literal () =
  let repo = with_base [ (".gitignore", "*.log\n") ] in
  Repo.write repo "*.log.txt" "star\n";
  Repo.write repo "a.log" "ignored\n";
  Alcotest.check strings "the file named with a star"
    [ show "*.log.txt" (Git.Added (Git.Text [ hunk 1 1 5 1 1 0 ])) ]
    (shown repo)

let a_conversion_alone_is_no_change () =
  let repo =
    with_base
      [
        (".gitattributes", "*.flt filter=strip\n");
        ("f.flt", "a\nb\n");
        ("crlf.txt", "l1\nl2\nl3\n");
        ("edit.txt", "l1\nl2\n");
      ]
  in
  Repo.append_config repo
    "[filter \"strip\"]\n\
     \tclean = \"sed '/^#strip/d'\"\n\
     \tsmudge = cat\n\
     [core]\n\
     \tautocrlf = true\n";
  Repo.write repo "f.flt" "a\n#strip x\nb\n";
  Repo.write repo "crlf.txt" "l1\r\nl2\r\nl3\r\n";
  Repo.write repo "edit.txt" "l1\r\nnew\r\nl2\r\n";
  Alcotest.check strings "only the real edit, at the lines of the disk"
    [ show "edit.txt" (Git.Modified (Git.Text [ hunk 2 2 4 2 1 0 ])) ]
    (shown repo)

let a_type_change_follows_the_file_sets () =
  let repo = Repo.init () in
  Repo.write repo "README.md" "r\n";
  Repo.write repo "file-then-link" "f\n";
  Repo.symlink repo ~target:"README.md" "link-then-file";
  ignore (Repo.git repo [ "add"; "-A" ]);
  ignore (Repo.git repo [ "commit"; "-q"; "-m"; "base" ]);
  Repo.remove repo "file-then-link";
  Repo.symlink repo ~target:"README.md" "file-then-link";
  Repo.remove repo "link-then-file";
  Repo.write repo "link-then-file" "now\na file\n";
  ignore (Repo.git repo [ "add"; "-A" ]);
  Alcotest.check strings "a deletion and an addition"
    [
      show "file-then-link" (Git.Deleted (Git.Text [ hunk 1 1 1 1 0 1 ]));
      show "link-then-file" (Git.Added (Git.Text [ hunk 1 2 7 1 2 0 ]));
    ]
    (shown repo)

let a_path_that_is_not_utf_8_is_left_out () =
  let repo = Repo.init () in
  Repo.import repo
    [
      Repo.commit ~ref:"refs/heads/main" ~mark:1 ~message:"base"
        [ Repo.File ("a.txt", "a\n"); Repo.File ("gone\xff.txt", "g\n") ];
    ];
  Repo.write repo "a.txt" "a\n";
  Alcotest.check strings "the base path is left out" [] (shown repo);
  match Repo.write repo "new\xfe.txt" "n\n" with
  | exception Sys_error _ -> ()
  | () ->
      Alcotest.check strings "the path of the working tree is left out" []
        (shown repo)

let binary_and_empty_files_give_one_hunk () =
  let repo =
    with_base
      [
        ("changed.bin", "a\000b\n");
        ("deleted.bin", "\000\n");
        ("deleted-empty.txt", "");
        ("deleted.txt", "1\n2\n3\n");
      ]
  in
  Repo.write repo "changed.bin" "a\000c\n";
  Repo.remove repo "deleted.bin";
  Repo.remove repo "deleted-empty.txt";
  Repo.remove repo "deleted.txt";
  Repo.write repo "added.bin" "\000";
  Repo.write repo "added-empty.txt" "";
  let whole = hunk 1 1 1 1 0 0 in
  Alcotest.check strings "the hunks of each path"
    [
      "added-empty.txt " ^ Generators.print_content (Git.Text [ whole ]);
      "added.bin " ^ Generators.print_content (Git.Text [ whole ]);
      "changed.bin " ^ Generators.print_content (Git.Text [ whole ]);
      "deleted-empty.txt " ^ Generators.print_content (Git.Text [ whole ]);
      "deleted.bin " ^ Generators.print_content (Git.Text [ whole ]);
      "deleted.txt " ^ Generators.print_content (Git.Text [ hunk 1 1 1 1 0 3 ]);
    ]
    (List.map
       (fun (path, change) ->
         path ^ " " ^ Generators.print_content (Git.Text (Git.hunks change)))
       (diff repo));
  Alcotest.(check (list (pair string string)))
    "the changes"
    [
      ("added-empty.txt", "Added Text []");
      ("added.bin", "Added Binary");
      ("changed.bin", "Modified Binary");
      ("deleted-empty.txt", "Deleted Text []");
      ("deleted.bin", "Deleted Binary");
      ("deleted.txt", "Deleted Text [1-1:1 old 1 +0 -3]");
    ]
    (List.map
       (fun (path, change) -> (path, Generators.print_change change))
       (diff repo))

let a_mode_change_gives_no_hunk () =
  Alcotest.(check int)
    "no hunk" 0
    (List.length (Git.hunks (Git.Modified (Git.Text []))));
  Alcotest.(check int)
    "the runs of a modified text" 2
    (List.length
       (Git.hunks
          (Git.Modified (Git.Text [ hunk 1 1 2 1 1 1; hunk 5 5 1 5 0 1 ]))))

let configuration_does_not_change_the_hunks () =
  let repo =
    with_base [ ("a.txt", String.make 40 'x' ^ "\n"); ("b.txt", "1\n") ]
  in
  Repo.append_config repo
    "[core]\n\
     \tbigFileThreshold = 10\n\
     \tquotePath = false\n\
     [diff]\n\
     \torderFile = order\n";
  Repo.write repo "order" "b.txt\na.txt\n";
  Repo.write repo "a.txt" (String.make 40 'y' ^ "\n");
  Repo.write repo "b.txt" "2\n";
  Alcotest.check strings "text hunks"
    [
      show "a.txt" (Git.Modified (Git.Text [ hunk 1 1 41 1 1 1 ]));
      show "b.txt" (Git.Modified (Git.Text [ hunk 1 1 2 1 1 1 ]));
      show "order" (Git.Added (Git.Text [ hunk 1 2 6 1 2 0 ]));
    ]
    (shown repo)

let an_unmerged_path_is_compared_by_its_content () =
  let repo = with_base [ ("f", "1\n2\n") ] in
  let commit message =
    ignore (Repo.git repo [ "commit"; "-q"; "-a"; "-m"; message ])
  in
  ignore (Repo.git repo [ "checkout"; "-q"; "-b"; "other" ]);
  Repo.write repo "f" "1\nO\n";
  commit "other";
  ignore (Repo.git repo [ "checkout"; "-q"; "main" ]);
  Repo.write repo "f" "1\nM\n";
  commit "main";
  ignore (Repo.git_status repo [ "merge"; "-q"; "other" ]);
  match diff_against (opened repo) "main~1" with
  | Ok
      [
        ( "f",
          Git.Modified (Git.Text [ { line = 2; added = 5; removed = 1; _ } ]) );
      ] ->
      ()
  | Ok changes ->
      Alcotest.failf "the changes are %s" (Generators.print_changes changes)
  | Error _ -> Alcotest.fail "the diff fails"

let objects_in_an_alternate_of_the_environment_are_read () =
  let repo = with_base [ ("a.txt", "1\n") ] in
  ignore (Repo.git repo [ "repack"; "-q"; "-a"; "-d" ]);
  let elsewhere = Filename.concat (Repo.temp_dir ()) "objects" in
  Sys.mkdir elsewhere 0o700;
  Sys.rename
    (Filename.concat (Repo.root repo) ".git/objects/pack")
    (Filename.concat elsewhere "pack");
  Sys.mkdir (Filename.concat (Repo.root repo) ".git/objects/pack") 0o700;
  Repo.write repo "a.txt" "2\n";
  let env =
    Array.append (Repo.env repo)
      [| "GIT_ALTERNATE_OBJECT_DIRECTORIES=" ^ elsewhere |]
  in
  match Git.open_repo ~env (Repo.root repo) with
  | Error _ -> Alcotest.fail "the repository does not open"
  | Ok t -> (
      match diff_against t "HEAD" with
      | Ok changes ->
          Alcotest.check strings "the change"
            [ show "a.txt" (Git.Modified (Git.Text [ hunk 1 1 2 1 1 1 ])) ]
            (List.map (fun (path, change) -> show path change) changes)
      | Error _ -> Alcotest.fail "the diff fails")

let partial_clone () =
  let origin = with_base [ ("a.txt", "hello\n") ] in
  ignore (Repo.git origin [ "config"; "uploadpack.allowFilter"; "true" ]);
  let clone = Filename.concat (Filename.dirname (Repo.root origin)) "clone" in
  ignore
    (Repo.git origin
       [
         "clone";
         "-q";
         "--filter=blob:none";
         "--no-checkout";
         "file://" ^ Repo.root origin;
         clone;
       ]);
  Out_channel.with_open_bin (Filename.concat clone "a.txt") (fun channel ->
      Out_channel.output_string channel "hello\n");
  let blob = String.trim (Repo.git origin [ "rev-parse"; "HEAD:a.txt" ]) in
  (origin, clone, blob)

let missing origin clone blob =
  List.mem ("?" ^ blob)
    (String.split_on_char '\n'
       (Repo.git origin
          [ "-C"; clone; "rev-list"; "--objects"; "--missing=print"; "HEAD" ]))

let a_missing_object_of_a_partial_clone_is_an_error () =
  let origin, clone, blob = partial_clone () in
  let env = Array.append (Repo.env origin) [| "GIT_NO_LAZY_FETCH=0" |] in
  match Git.open_repo ~env clone with
  | Error _ -> Alcotest.fail "the clone does not open"
  | Ok t ->
      Alcotest.(check bool)
        "the diff fails" true
        (match diff_against t "HEAD" with
        | Error (Git.Command_failed _) -> true
        | Ok _ | Error _ -> false);
      Alcotest.(check bool)
        "the read of the blob fails" true
        (match Git.fold_blobs t [ blob ] ~init:() ~f:(fun () _ _ -> ()) with
        | Error _ -> true
        | Ok () -> false);
      Alcotest.(check bool)
        "the clone still lacks the blob" true
        (missing origin clone blob)

let a_missing_tree_gives_the_error_of_ls_tree_on_the_commit () =
  let origin = with_base [ ("d/a.txt", "a\n") ] in
  ignore (Repo.git origin [ "config"; "uploadpack.allowFilter"; "true" ]);
  let clone = Filename.concat (Filename.dirname (Repo.root origin)) "trees" in
  ignore
    (Repo.git origin
       [
         "clone";
         "-q";
         "--filter=tree:0";
         "--no-checkout";
         "file://" ^ Repo.root origin;
         clone;
       ]);
  let commit = String.trim (Repo.git origin [ "rev-parse"; "HEAD" ]) in
  match Git.open_repo ~env:(Repo.env origin) clone with
  | Error _ -> Alcotest.fail "the clone does not open"
  | Ok t -> (
      match Git.read_base t commit with
      | Error (Git.Command_failed { args; _ }) ->
          Alcotest.(check (list string))
            "the arguments"
            [ "-C"; Git.root t; "ls-tree"; "-r"; "-z"; "--full-tree"; commit ]
            args
      | Ok _ | Error _ -> Alcotest.fail "the read of the base does not fail")

let rec snapshot root relative =
  let path = Filename.concat root relative in
  match Unix.lstat path with
  | { Unix.st_kind = Unix.S_DIR; _ } ->
      (relative ^ "/")
      :: List.concat_map
           (fun name ->
             snapshot root
               (if relative = "" then name else Filename.concat relative name))
           (List.sort String.compare (Array.to_list (Sys.readdir path)))
  | stat ->
      let time =
        if String.starts_with ~prefix:"sharedindex." relative then 0.
        else stat.st_mtime
      in
      [
        Printf.sprintf "%s %d %d %h" relative stat.Unix.st_ino stat.st_size time;
      ]

let the_diff_writes_nothing_under_the_git_directory () =
  let repo =
    with_base
      [ ("tracked.txt", "a\n"); ("flag.txt", "f\n"); ("old.txt", "o\n") ]
  in
  ignore (Repo.git repo [ "update-index"; "--assume-unchanged"; "flag.txt" ]);
  ignore (Repo.git repo [ "rm"; "-q"; "--cached"; "old.txt" ]);
  Repo.append_config repo
    "[core]\n\
     \tsplitIndex = true\n\
     \tfsmonitor = true\n\
     \tuntrackedCache = true\n\
     [splitIndex]\n\
     \tmaxPercentChange = 1\n";
  ignore
    (Repo.git repo
       [ "-c"; "core.fsmonitor=false"; "update-index"; "--split-index" ]);
  Repo.write repo "flag.txt" "changed\n";
  Repo.write repo "tracked.txt" "b\n";
  for index = 1 to 20 do
    Repo.write repo (Printf.sprintf "new%02d.txt" index) "\n"
  done;
  Repo.write repo "empty.txt" "";
  let git_dir = Filename.concat (Repo.root repo) ".git" in
  let before = snapshot git_dir "" in
  Unix.sleepf 1.1;
  let changes = diff repo in
  Alcotest.(check int) "the changed paths" 23 (List.length changes);
  Alcotest.check strings "the files under .git" before (snapshot git_dir "")

let the_tree_key_starts_no_file_system_monitor () =
  let repo = with_base [ ("a.txt", "a\n") ] in
  Repo.append_config repo "[core]\n\tfsmonitor = true\n";
  Repo.write repo "b.txt" "b\n";
  match Git.tree_key (opened repo) with
  | Error _ -> Alcotest.fail "the tree key fails"
  | Ok _ ->
      Alcotest.(check bool)
        "no file of the daemon under .git" false
        (Sys.file_exists
           (Filename.concat (Repo.root repo) ".git/fsmonitor--daemon.ipc"))

let key repo =
  match Git.tree_key (opened repo) with
  | Ok key -> key
  | Error _ -> Alcotest.fail "the tree key fails"

let tree_of_git_add_all repo =
  let copy = Repo.copy repo in
  ignore (Repo.git copy [ "add"; "-A" ]);
  String.trim (Repo.git copy [ "write-tree" ])

let the_tree_key_writes_no_file_under_the_git_directory () =
  let repo =
    with_base
      [
        ("old.txt", "old\n");
        ("touched.txt", "same\n");
        ("gone.txt", "gone\n");
        ("d/e.txt", "e\n");
      ]
  in
  ignore (Repo.git repo [ "repack"; "-q"; "-a"; "-d" ]);
  Repo.write repo "old.txt" "next\n";
  ignore (Repo.git repo [ "commit"; "-q"; "-a"; "-m"; "next" ]);
  Repo.write repo "old.txt" "old\n";
  let touched = Filename.concat (Repo.root repo) "touched.txt" in
  Unix.utimes touched 1_000_000_000. 1_000_000_000.;
  Repo.remove repo "gone.txt";
  Repo.write repo "d/e.txt" "changed\n";
  Repo.write repo "new.txt" "new\n";
  Repo.write repo "empty.txt" "";
  let before = Repo.git_dir_state repo in
  let expected = tree_of_git_add_all repo in
  Alcotest.(check string) "the key" expected (key repo);
  Alcotest.check strings "the files under .git" before (Repo.git_dir_state repo)

type step =
  | Write of int * int
  | Delete of int
  | Touch of int
  | Executable of int
  | Stage of int

let names = [| "a.txt"; "d/b.txt"; "d/e/c.txt"; "f"; "x.log"; "d/x.log" |]
let contents = [| ""; "1\n"; "2\n"; "1\n2\n" |]

let print_step = function
  | Write (name, content) ->
      Printf.sprintf "write %s %S" names.(name) contents.(content)
  | Delete name -> "delete " ^ names.(name)
  | Touch name -> "touch " ^ names.(name)
  | Executable name -> "chmod +x " ^ names.(name)
  | Stage name -> "git add -f " ^ names.(name)

let print_scenario (base, steps) =
  String.concat "; "
    (List.map
       (fun (name, content) ->
         Printf.sprintf "base %s %S" names.(name) contents.(content))
       base
    @ List.map print_step steps)

let scenario =
  let module Gen = QCheck2.Gen in
  let name = Gen.int_range 0 (Array.length names - 1)
  and content = Gen.int_range 0 (Array.length contents - 1) in
  let step =
    Gen.oneof
      [
        Gen.map2 (fun name content -> Write (name, content)) name content;
        Gen.map (fun name -> Delete name) name;
        Gen.map (fun name -> Touch name) name;
        Gen.map (fun name -> Executable name) name;
        Gen.map (fun name -> Stage name) name;
      ]
  in
  Gen.pair
    (Gen.list_size (Gen.int_range 0 4) (Gen.pair name content))
    (Gen.list_size (Gen.int_range 1 6) step)

let exists repo name = Sys.file_exists (Filename.concat (Repo.root repo) name)

let apply repo index = function
  | Write (name, content) -> Repo.write repo names.(name) contents.(content)
  | Delete name ->
      if exists repo names.(name) then Repo.remove repo names.(name)
  | Touch name ->
      if exists repo names.(name) then
        let time = 1_000_000_000. +. float_of_int index in
        Unix.utimes (Filename.concat (Repo.root repo) names.(name)) time time
  | Executable name ->
      if exists repo names.(name) then Repo.make_executable repo names.(name)
  | Stage name ->
      if exists repo names.(name) then
        ignore (Repo.git repo [ "add"; "-f"; "--"; names.(name) ])

let the_tree_key_is_the_tree_of_git_add_all =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:25
       ~name:"the tree key is the tree of git add -A on a generated tree"
       ~print:print_scenario scenario (fun (base, steps) ->
         let repo =
           with_base
             ((".gitignore", "*.log\n")
             :: List.map
                  (fun (name, content) -> (names.(name), contents.(content)))
                  base)
         in
         List.iteri (apply repo) steps;
         String.equal (tree_of_git_add_all repo) (key repo)))

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "a flagged entry is compared by its content"
      a_flagged_entry_is_compared_by_its_content;
    case "an entry with both flags is compared by its content"
      an_entry_with_both_flags_is_compared_by_its_content;
    case "an untracked file of the base is compared with its blob"
      an_untracked_file_of_the_base_is_compared_with_its_blob;
    case "an intent-to-add entry is compared like any file"
      an_intent_to_add_entry_is_compared_like_any_file;
    case "a glob character in an untracked name is literal"
      a_glob_character_in_an_untracked_name_is_literal;
    case "a conversion alone is no change" a_conversion_alone_is_no_change;
    case "a type change follows the file sets"
      a_type_change_follows_the_file_sets;
    case "a path that is not UTF-8 is left out"
      a_path_that_is_not_utf_8_is_left_out;
    case "binary and empty files give one hunk"
      binary_and_empty_files_give_one_hunk;
    case "a mode change gives no hunk" a_mode_change_gives_no_hunk;
    case "an unmerged path is compared by its content"
      an_unmerged_path_is_compared_by_its_content;
    case "objects in an alternate of the environment are read"
      objects_in_an_alternate_of_the_environment_are_read;
    case "the configuration does not change the hunks"
      configuration_does_not_change_the_hunks;
    case "a missing object of a partial clone is an error"
      a_missing_object_of_a_partial_clone_is_an_error;
    case "a missing tree gives the error of ls-tree on the commit"
      a_missing_tree_gives_the_error_of_ls_tree_on_the_commit;
    case "the tree key starts no file system monitor"
      the_tree_key_starts_no_file_system_monitor;
    case "the diff writes nothing under the git directory"
      the_diff_writes_nothing_under_the_git_directory;
    case "the tree key writes no file under the git directory"
      the_tree_key_writes_no_file_under_the_git_directory;
    the_tree_key_is_the_tree_of_git_add_all;
  ]
