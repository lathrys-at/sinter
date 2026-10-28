(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

type op = Keep | Delete | Insert

let diff_against t rev =
  Result.bind (Git.read_base t rev) (fun base ->
      Result.bind (Git.files t) (fun files -> Git.diff t ~files ~base))

let run ~old_line ~line ~added ~removed : Git.hunk =
  {
    line;
    eline = (if added = 0 then line else line + added - 1);
    ecol = 1;
    old_line;
    added;
    removed;
  }

let runs_of ops =
  let rec walk old_line line runs kept = function
    | [] -> (List.rev runs, List.rev kept)
    | Keep :: rest ->
        walk (old_line + 1) (line + 1) runs ((old_line, line) :: kept) rest
    | (Delete | Insert) :: _ as ops ->
        let rec group removed added = function
          | Delete :: rest -> group (removed + 1) added rest
          | Insert :: rest -> group removed (added + 1) rest
          | rest -> (removed, added, rest)
        in
        let removed, added, rest = group 0 0 ops in
        walk (old_line + removed) (line + added)
          (run ~old_line ~line ~added ~removed :: runs)
          kept rest
  in
  walk 1 1 [] [] ops

let deleted ops =
  let rec walk old_line found = function
    | [] -> List.rev found
    | Keep :: rest -> walk (old_line + 1) found rest
    | Delete :: rest -> walk (old_line + 1) (old_line :: found) rest
    | Insert :: rest -> walk old_line found rest
  in
  walk 1 [] ops

let ops =
  Gen.(list_size (int_bound 40) (oneof_list [ Keep; Keep; Delete; Insert ]))

let print_ops ops =
  String.concat ""
    (List.map (function Keep -> "=" | Delete -> "-" | Insert -> "+") ops)

let moves ops =
  let runs, _ = runs_of ops in
  Baseline.of_diff [ ("f.md", Git.Modified (Git.Text runs)) ]

let an_unchanged_line_moves_to_its_line_in_the_working_tree =
  property ~name:"an unchanged line moves to the line that holds it now"
    ~print:print_ops ops (fun ops ->
      let moves = moves ops and _, kept = runs_of ops in
      List.for_all
        (fun (base, now) -> Baseline.line moves ~path:"f.md" base = Some now)
        kept)

let a_removed_line_has_no_place =
  property ~name:"a line that a run removes has no line in the working tree"
    ~print:print_ops ops (fun ops ->
      let moves = moves ops in
      List.for_all
        (fun base -> Baseline.line moves ~path:"f.md" base = None)
        (deleted ops))

let hunk = run

let lines_move_around_the_runs () =
  let moves =
    Baseline.of_diff
      [
        ( "f.md",
          Git.Modified
            (Git.Text
               [
                 hunk ~old_line:1 ~line:1 ~added:2 ~removed:0;
                 hunk ~old_line:4 ~line:6 ~added:0 ~removed:1;
                 hunk ~old_line:7 ~line:8 ~added:1 ~removed:1;
               ]) );
      ]
  in
  Alcotest.(check (list (option int)))
    "the lines 1 to 9 of the base"
    [ Some 3; Some 4; Some 5; None; Some 6; Some 7; None; Some 9; Some 10 ]
    (List.init 9 (fun index -> Baseline.line moves ~path:"f.md" (index + 1)))

let an_insertion_after_a_line_leaves_it () =
  let moves =
    Baseline.of_diff
      [
        ( "f.md",
          Git.Modified
            (Git.Text [ hunk ~old_line:3 ~line:3 ~added:1 ~removed:0 ]) );
      ]
  in
  Alcotest.(check (list (option int)))
    "the lines 2 and 3" [ Some 2; Some 4 ]
    [ Baseline.line moves ~path:"f.md" 2; Baseline.line moves ~path:"f.md" 3 ]

let a_file_that_the_diff_does_not_list_keeps_its_lines () =
  Alcotest.(check (option int))
    "line 7" (Some 7)
    (Baseline.line (Baseline.of_diff []) ~path:"f.md" 7)

let a_deleted_or_binary_file_has_no_lines () =
  let moves =
    Baseline.of_diff
      [
        ("bin.md", Git.Modified Git.Binary);
        ("gone.md", Git.Deleted (Git.Text []));
        ("new.md", Git.Added Git.Binary);
      ]
  in
  Alcotest.(check (list (option int)))
    "line 1 of each" [ None; None; None ]
    (List.map
       (fun path -> Baseline.line moves ~path 1)
       [ "bin.md"; "gone.md"; "new.md" ])

let position line column = { Markdown.line; column }

let subjects_move_and_keep_their_columns () =
  let moves =
    Baseline.of_diff
      [
        ( "f.md",
          Git.Modified
            (Git.Text
               [
                 hunk ~old_line:1 ~line:1 ~added:1 ~removed:0;
                 hunk ~old_line:5 ~line:6 ~added:0 ~removed:1;
               ]) );
      ]
  in
  let moved subject =
    Option.map Finding.subject_id (Baseline.subject moves subject)
  in
  Alcotest.(check (list (option string)))
    "each subject"
    [
      Some "line:f.md@L3";
      Some "tag:f.md@L4C7";
      Some "file:f.md@L2C2";
      None;
      Some "file:f.md";
      Some "req:a";
    ]
    (List.map moved
       [
         Finding.Line { path = "f.md"; line = 2 };
         Finding.Tag { path = "f.md"; position = position 3 7 };
         Finding.Error_node { path = "f.md"; position = position 1 2 };
         Finding.Tag { path = "f.md"; position = position 5 1 };
         Finding.File "f.md";
         Finding.Fact { id = "req:a"; ack_name = "a" };
       ])

let finding ?(finding_class = Finding_class.Typo_tag) subject =
  Finding.make finding_class subject ()

let line path line = Finding.Line { path; line }

let subtract_removes_each_finding_of_the_base_after_the_move () =
  let moves =
    Baseline.of_diff
      [
        ( "f.md",
          Git.Modified
            (Git.Text [ hunk ~old_line:1 ~line:1 ~added:2 ~removed:1 ]) );
      ]
  in
  let tree =
    [
      finding (line "f.md" 4);
      finding (line "f.md" 4);
      finding (line "f.md" 1);
      finding (line "f.md" 3);
      finding ~finding_class:Finding_class.Ignored_tag (line "f.md" 5);
      finding (line "g.md" 2);
    ]
  in
  let base =
    [
      finding (line "f.md" 3);
      finding (line "f.md" 1);
      finding (line "f.md" 4);
      finding (line "g.md" 2);
    ]
  in
  Alcotest.(check (list string))
    "the findings that the working tree adds"
    [
      "finding:typo-tag:line:f.md@L1";
      "finding:typo-tag:line:f.md@L3";
      "finding:ignored-tag:line:f.md@L5";
    ]
    (List.map Finding.id (Baseline.subtract moves ~base tree))

let subject_gen =
  let open Gen in
  let path = oneof_list [ "a.md"; "b.md" ] in
  oneof
    [
      map2 (fun path line -> Finding.Line { path; line }) path (int_range 1 6);
      map2
        (fun path (line, column) ->
          Finding.Tag { path; position = position line column })
        path
        (pair (int_range 1 6) (int_range 1 3));
      map (fun path -> Finding.File path) path;
    ]

let findings_gen =
  let open Gen in
  list_size (int_bound 8)
    (map2
       (fun finding_class subject -> finding ~finding_class subject)
       (oneof_list [ Finding_class.Typo_tag; Finding_class.Invalid_target ])
       subject_gen)

let print_findings findings = String.concat ", " (List.map Finding.id findings)

let subtract_is_a_filter_by_moved_ids =
  property
    ~name:
      "subtract keeps exactly the findings whose ids no moved base finding has"
    ~print:(fun (ops, base, tree) ->
      Printf.sprintf "%s | %s | %s" (print_ops ops) (print_findings base)
        (print_findings tree))
    Gen.(triple ops findings_gen findings_gen)
    (fun (ops, base, tree) ->
      let runs, _ = runs_of ops in
      let moves = Baseline.of_diff [ ("a.md", Git.Modified (Git.Text runs)) ] in
      let moved =
        List.filter_map
          (fun (f : Finding.t) ->
            Option.map
              (Finding.id_of f.finding_class)
              (Baseline.subject moves f.subject))
          base
      in
      Baseline.subtract moves ~base tree
      = List.filter (fun f -> not (List.mem (Finding.id f) moved)) tree)

let subtract_of_no_base_keeps_everything =
  property ~name:"subtract with no finding of the base keeps every finding"
    ~print:print_findings findings_gen (fun tree ->
      Baseline.subtract (Baseline.of_diff []) ~base:[] tree = tree)

let edited_text =
  let open Gen in
  let piece = oneof_list [ "a"; "b"; "c"; ""; "  x"; "}"; "{" ] in
  let* base = list_size (int_range 1 25) piece in
  let* edits =
    list_size
      (pure (List.length base + 1))
      (pair (oneof_list [ Keep; Keep; Delete ]) (list_size (int_bound 2) piece))
  in
  let rec apply base edits =
    match (base, edits) with
    | line :: rest, (op, inserted) :: more ->
        inserted @ (if op = Delete then [] else [ line ]) @ apply rest more
    | [], (_, inserted) :: _ -> inserted
    | _, [] -> []
  in
  pure (base, apply base edits)

let shared_repo = lazy (Git_fixture.init ())
let lines_of text = String.concat "" (List.map (fun line -> line ^ "\n") text)

let a_line_that_git_keeps_moves_to_its_text =
  property ~count:30
    ~name:"each line that git's diff keeps moves to a line with its text"
    ~print:(fun (base, now) ->
      Printf.sprintf "%S -> %S" (lines_of base) (lines_of now))
    edited_text
    (fun (base, now) ->
      let repo = Lazy.force shared_repo in
      Git_fixture.write repo "f.md" (lines_of base);
      ignore (Git_fixture.git repo [ "add"; "-A" ]);
      ignore
        (Git_fixture.git repo [ "commit"; "-q"; "--allow-empty"; "-m"; "base" ]);
      Git_fixture.write repo "f.md" (lines_of now);
      match
        Git.open_repo ~env:(Git_fixture.env repo) (Git_fixture.root repo)
      with
      | Error _ -> false
      | Ok t -> (
          match diff_against t "HEAD" with
          | Error _ -> false
          | Ok changes ->
              let moves = Baseline.of_diff changes in
              let base_lines = Array.of_list base
              and now_lines = Array.of_list now in
              let removed =
                List.fold_left
                  (fun sum (_, change) ->
                    match change with
                    | Git.Modified (Git.Text runs) ->
                        List.fold_left
                          (fun sum (run : Git.hunk) -> sum + run.removed)
                          sum runs
                    | _ -> sum)
                  0 changes
              in
              let moved =
                List.init (Array.length base_lines) (fun index ->
                    (index, Baseline.line moves ~path:"f.md" (index + 1)))
              in
              List.for_all
                (fun (index, found) ->
                  match found with
                  | Some line ->
                      line >= 1
                      && line <= Array.length now_lines
                      && String.equal now_lines.(line - 1) base_lines.(index)
                  | None -> true)
                moved
              && List.length (List.filter (fun (_, f) -> f = None) moved)
                 = removed))

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    an_unchanged_line_moves_to_its_line_in_the_working_tree;
    a_removed_line_has_no_place;
    a_line_that_git_keeps_moves_to_its_text;
    case "lines move around the runs" lines_move_around_the_runs;
    case "an insertion after a line leaves it"
      an_insertion_after_a_line_leaves_it;
    case "a file that the diff does not list keeps its lines"
      a_file_that_the_diff_does_not_list_keeps_its_lines;
    case "a deleted or binary file has no lines"
      a_deleted_or_binary_file_has_no_lines;
    case "subjects move and keep their columns"
      subjects_move_and_keep_their_columns;
    case "subtract removes each finding of the base after the move"
      subtract_removes_each_finding_of_the_base_after_the_move;
    subtract_is_a_filter_by_moved_ids;
    subtract_of_no_base_keeps_everything;
  ]
