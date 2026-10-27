(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_bench

let make seed = Generated_tree.make ~seed ~declarations:120
let files = Alcotest.(list (pair string string))

let one_seed_gives_one_tree () =
  let a = make 7 and b = make 7 in
  Alcotest.check files "main" (Generated_tree.main a) (Generated_tree.main b);
  Alcotest.check files "work" (Generated_tree.work a) (Generated_tree.work b);
  Alcotest.check files "uncommitted"
    (Generated_tree.uncommitted a)
    (Generated_tree.uncommitted b)

let two_seeds_give_two_trees () =
  Alcotest.(check bool)
    "the files differ" false
    (Generated_tree.main (make 1) = Generated_tree.main (make 2))

let lines_starting prefix files =
  List.concat_map
    (fun (_, text) ->
      List.filter (String.starts_with ~prefix) (String.split_on_char '\n' text))
    files

let the_tree_declares_n_declarations () =
  let tree = Generated_tree.make ~seed:3 ~declarations:2500 in
  let main =
    List.filter
      (fun (path, _) -> not (String.starts_with ~prefix:".plans/" path))
      (Generated_tree.main tree)
  in
  List.iter
    (fun (kind, expected) ->
      Alcotest.(check int)
        ("count of " ^ kind) expected
        (Generated_tree.count tree kind);
      Alcotest.(check int)
        ("tags of " ^ kind) expected
        (List.length (lines_starting ("@" ^ kind ^ " ") main)))
    [ ("req", 1250); ("design", 750); ("decision", 500) ];
  Alcotest.(check int) "count of plan" 2 (Generated_tree.count tree "plan");
  Alcotest.(check int)
    "tags of plan" 2
    (List.length (lines_starting "@plan " (Generated_tree.main tree)));
  Alcotest.(check int) "another word" 0 (Generated_tree.count tree "cites")

let reader =
  lazy
    (match Sinter_core.Markdown.create (Sinter_bridge.create ()) with
    | Ok reader -> reader
    | Error _ -> failwith "the reader does not start")

let the_tree_retires_decisions_and_acks_their_citations () =
  let tree = Generated_tree.make ~seed:3 ~declarations:2500 in
  let main = Generated_tree.main tree in
  Alcotest.(check (list int))
    "@deprecated, @rejected, @deferred" [ 10; 10; 10 ]
    (List.map
       (fun word -> List.length (lines_starting word main))
       [ "@deprecated"; "@rejected"; "@deferred" ]);
  let acks =
    List.filter
      (fun (path, _) -> String.starts_with ~prefix:"docs/acks/" path)
      main
  in
  Alcotest.(check int)
    "citations" 125
    (List.length (lines_starting "@cites dec-" acks));
  let matching = ref 0 and wrong = ref 0 in
  List.iter
    (fun (path, text) ->
      match Sinter_core.Markdown.read (Lazy.force reader) text with
      | Error _ -> Alcotest.failf "%s does not parse" path
      | Ok (document : Sinter_core.Markdown.t) ->
          Array.iter
            (fun (tag : Sinter_core.Markdown.tag) ->
              if String.equal tag.word "ack" then
                let hash = document.blocks.(tag.block).hash in
                let given =
                  List.nth (String.split_on_char ' ' (String.trim tag.rest)) 2
                in
                if String.equal given (String.sub hash 0 8) then incr matching
                else if
                  String.equal (String.sub given 1 7) (String.sub hash 1 7)
                  && given.[0] <> hash.[0]
                then incr wrong
                else Alcotest.failf "%s: the ack %s fits no form" path given)
            document.tags)
    acks;
  Alcotest.(check bool)
    "matching and wrong acks" true
    (!matching > 0 && !wrong > 0)

let one_file_in_100_changes_on_work_and_one_in_1000_stays_uncommitted () =
  let tree = Generated_tree.make ~seed:5 ~declarations:2500 in
  let main = Generated_tree.main tree in
  let markdown = List.length main - 1 in
  let paths files = List.map fst files in
  let check name expected changed =
    Alcotest.(check int) (name ^ ": count") expected (List.length changed);
    Alcotest.(check bool)
      (name ^ ": every path is a markdown file of main")
      true
      (List.for_all
         (fun path ->
           List.mem_assoc path main && not (String.equal path "sinter.toml"))
         (paths changed));
    Alcotest.(check (list string))
      (name ^ ": in byte order")
      (List.sort String.compare (paths changed))
      (paths changed)
  in
  check "work" (markdown / 100) (Generated_tree.work tree);
  check "uncommitted"
    (max 1 (markdown / 1000))
    (Generated_tree.uncommitted tree)

let a_small_tree_changes_one_file () =
  let tree = Generated_tree.make ~seed:1 ~declarations:2 in
  Alcotest.(check int) "work" 1 (List.length (Generated_tree.work tree));
  Alcotest.(check int)
    "uncommitted" 1
    (List.length (Generated_tree.uncommitted tree))

let fewer_than_2_declarations_are_refused () =
  match Generated_tree.make ~seed:1 ~declarations:1 with
  | (_ : Generated_tree.t) -> Alcotest.fail "no exception"
  | exception Invalid_argument _ -> ()

let write tree = Generated_tree.write tree (Git_fixture.temp_dir ())

let overlay tree =
  List.fold_left
    (fun files (path, text) -> (path, text) :: List.remove_assoc path files)
    (Generated_tree.main tree)
    (Generated_tree.work tree @ Generated_tree.uncommitted tree)

let the_repository_holds_the_tree () =
  let tree = make 11 in
  let repo = write tree in
  Alcotest.(check string)
    "HEAD" "refs/heads/work\n"
    (Git_fixture.git repo [ "symbolic-ref"; "HEAD" ]);
  Alcotest.(check (list string))
    "the files of main"
    (List.map fst (Generated_tree.main tree))
    (String.split_on_char '\n'
       (String.trim
          (Git_fixture.git repo [ "ls-tree"; "-r"; "--name-only"; "main" ])));
  Alcotest.(check (list string))
    "the files that work changes"
    (List.map fst (Generated_tree.work tree))
    (String.split_on_char '\n'
       (String.trim
          (Git_fixture.git repo [ "diff"; "--name-only"; "main"; "work" ])));
  Alcotest.(check (list string))
    "the files changed in the working tree"
    (List.map fst (Generated_tree.uncommitted tree))
    (String.split_on_char '\n'
       (String.trim (Git_fixture.git repo [ "diff"; "--name-only" ])));
  List.iter
    (fun (path, text) ->
      let full = Filename.concat (Git_fixture.root repo) path in
      Alcotest.(check string)
        ("the content of " ^ path) text
        (In_channel.with_open_bin full In_channel.input_all);
      Alcotest.(check (float 0.))
        ("the time of " ^ path) 1700000000. (Unix.stat full).Unix.st_mtime)
    (overlay tree)

let two_writes_give_the_same_commits () =
  let tree = make 13 in
  let ids repo = Git_fixture.git repo [ "rev-parse"; "main"; "work" ] in
  Alcotest.(check string) "main and work" (ids (write tree)) (ids (write tree))

let the_index_needs_no_refresh () =
  let tree = make 17 in
  let repo = write tree in
  let before = Git_fixture.index_state repo in
  ignore (Git_fixture.git repo [ "status"; "--porcelain" ]);
  Alcotest.(check string) "the index" before (Git_fixture.index_state repo)

let init_in_refuses_a_folder_that_holds_a_repository () =
  let dir = Git_fixture.temp_dir () in
  ignore (Git_fixture.init_in dir);
  match Git_fixture.init_in dir with
  | (_ : Git_fixture.t) -> Alcotest.fail "no exception"
  | exception Invalid_argument _ -> ()

let init_in_refuses_a_missing_folder () =
  match
    Git_fixture.init_in (Filename.concat (Git_fixture.temp_dir ()) "missing")
  with
  | (_ : Git_fixture.t) -> Alcotest.fail "no exception"
  | exception Invalid_argument _ -> ()

let generate arguments =
  let output = Filename.temp_file "sinter-generate" ".out" in
  let errors = Filename.temp_file "sinter-generate" ".err" in
  let code =
    Sys.command
      (Printf.sprintf "../bench/generate.exe %s >%s 2>%s"
         (String.concat " " (List.map Filename.quote arguments))
         (Filename.quote output) (Filename.quote errors))
  in
  let read path = In_channel.with_open_bin path In_channel.input_all in
  Fun.protect
    ~finally:(fun () -> List.iter Sys.remove [ output; errors ])
    (fun () -> (code, read output, read errors))

let check_run name (code, output, errors)
    (expected_code, expected_output, expected_errors) =
  Alcotest.(check int) (name ^ ": exit") expected_code code;
  Alcotest.(check string) (name ^ ": output") expected_output output;
  Alcotest.(check string) (name ^ ": errors") expected_errors errors

let generate_prints_the_tree_it_made () =
  let dir = Filename.concat (Git_fixture.temp_dir ()) "tree" in
  let code, output, errors = generate [ "--seed"; "4"; "20"; dir ] in
  let root = Unix.realpath (Filename.concat dir "repo") in
  check_run "generate" (code, output, errors)
    (0, root ^ ": files 10, req 10, design 6, decision 4, plans 1, seed 4\n", "")

let generate_refuses_fewer_than_2_declarations () =
  let dir = Filename.concat (Git_fixture.temp_dir ()) "tree" in
  check_run "generate"
    (generate [ "1"; dir ])
    (1, "", "generate: N is 1, and it must be 2 or more\n");
  Alcotest.(check bool) "no folder" false (Sys.file_exists dir)

let generate_refuses_a_folder_that_exists () =
  let dir = Git_fixture.temp_dir () in
  check_run "generate"
    (generate [ "20"; dir ])
    (1, "", Printf.sprintf "generate: %s exists\n" dir)

let generate_names_a_folder_it_cannot_make () =
  let dir = Filename.concat (Git_fixture.temp_dir ()) "missing/tree" in
  check_run "generate"
    (generate [ "20"; dir ])
    (1, "", Printf.sprintf "generate: mkdir %s: No such file or directory\n" dir)

let generate_without_a_folder_is_a_usage_error () =
  let code, output, _ = generate [ "20" ] in
  Alcotest.(check int) "exit" 124 code;
  Alcotest.(check string) "output" "" output

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "one seed gives one tree" one_seed_gives_one_tree;
    case "two seeds give two trees" two_seeds_give_two_trees;
    case "the tree declares n declarations" the_tree_declares_n_declarations;
    case "one file in 100 changes on work and one in 1000 stays uncommitted"
      one_file_in_100_changes_on_work_and_one_in_1000_stays_uncommitted;
    case "a small tree changes one file" a_small_tree_changes_one_file;
    case "the tree retires decisions and acks their citations"
      the_tree_retires_decisions_and_acks_their_citations;
    case "fewer than 2 declarations are refused"
      fewer_than_2_declarations_are_refused;
    case "the repository holds the tree" the_repository_holds_the_tree;
    case "two writes give the same commits" two_writes_give_the_same_commits;
    case "the index needs no refresh" the_index_needs_no_refresh;
    case "init_in refuses a folder that holds a repository"
      init_in_refuses_a_folder_that_holds_a_repository;
    case "init_in refuses a missing folder" init_in_refuses_a_missing_folder;
    case "generate prints the tree it made" generate_prints_the_tree_it_made;
    case "generate refuses fewer than 2 declarations"
      generate_refuses_fewer_than_2_declarations;
    case "generate refuses a folder that exists"
      generate_refuses_a_folder_that_exists;
    case "generate names a folder it cannot make"
      generate_names_a_folder_it_cannot_make;
    case "generate without a folder is a usage error"
      generate_without_a_folder_is_a_usage_error;
  ]
