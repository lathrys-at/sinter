(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Repo = Git_fixture

let sinter = Filename.concat (Sys.getcwd ()) "../bin/main.exe"
let contents path = In_channel.with_open_bin path In_channel.input_all

type ran = { code : int; out : string; err : string }

let run ?(dir = "") repo arguments =
  let out = Filename.temp_file "sinter-ledger" ".out" in
  let err = Filename.temp_file "sinter-ledger" ".err" in
  let command =
    Printf.sprintf "cd %s && env -i %s NO_COLOR=1 %s %s %s >%s 2>%s"
      (Filename.quote (Filename.concat (Repo.root repo) dir))
      (String.concat " "
         (List.map Filename.quote
            (List.filter
               (fun variable ->
                 not (String.starts_with ~prefix:"NO_COLOR=" variable))
               (Array.to_list (Repo.env repo)))))
      (Filename.quote
         ("BISECT_FILE=" ^ Filename.concat (Sys.getcwd ()) "bisect"))
      (Filename.quote sinter) arguments (Filename.quote out)
      (Filename.quote err)
  in
  let code = Sys.command command in
  Fun.protect
    ~finally:(fun () ->
      Sys.remove out;
      Sys.remove err)
    (fun () -> { code; out = contents out; err = contents err })

let lines text =
  match List.rev (String.split_on_char '\n' text) with
  | "" :: rest -> List.rev rest
  | all -> List.rev all

let ledger_repo ?(entries = 3) () =
  let repo = Repo.init () in
  Sinter_bench.Generated_ledger.write repo ~entries ~per_commit:1;
  repo

let tip repo = String.trim (Repo.git repo [ "rev-parse"; Ledger.ref_name ])

let drop_the_last_entry repo =
  let parent = tip repo in
  let tree =
    String.trim (Repo.git repo [ "rev-parse"; parent ^ "~1^{tree}" ])
  in
  let commit =
    String.trim (Repo.git repo [ "commit-tree"; tree; "-p"; parent; "-m"; "d" ])
  in
  ignore (Repo.git repo [ "update-ref"; Ledger.ref_name; commit ]);
  (parent, commit)

let ran = Alcotest.(triple int (list string) (list string))
let seen { code; out; err } = (code, lines out, lines err)

let verify_passes_a_sound_ledger () =
  let repo = ledger_repo () in
  Alcotest.(check (triple int string string))
    "brief"
    (0, "", "the ledger passes verification: 3 entries in 4 commits\n")
    (let { code; out; err } = run repo "ledger verify" in
     (code, out, err));
  Alcotest.check ran "json" (0, [], [])
    (seen (run repo "ledger verify -o json"))

let verify_stops_on_a_broken_ledger () =
  let repo = ledger_repo () in
  let parent, commit = drop_the_last_entry repo in
  let entry =
    match Ledger.read_line Git.Sha1 (Sinter_bench.Generated_ledger.entry 2) with
    | Ok (Ledger.Known { entry; _ }) -> entry.id
    | _ -> Alcotest.fail "the entry does not read"
  in
  let path =
    fst
      (List.hd
         (Sinter_bench.Generated_ledger.chunks
            [ Sinter_bench.Generated_ledger.entry 0 ]))
  in
  let error =
    [
      Printf.sprintf
        "error: the ledger is broken: the commit %s drops the entry %s that \
         the line 3 of %s in the commit %s holds"
        commit entry path parent;
      "  = help: repair the ledger with sinter ledger repair";
    ]
  in
  Alcotest.check ran "brief" (3, [], error) (seen (run repo "ledger verify"));
  let json = run repo "ledger verify -o json" in
  Alcotest.(check (pair int (list string)))
    "json, the code and the error" (3, error)
    (json.code, lines json.err);
  match lines json.out with
  | [ record ] -> (
      match Yojson.Safe.from_string record with
      | `Assoc fields ->
          Alcotest.(check (list (pair string string)))
            "the record"
            [
              ("class", "ledger-broken");
              ("kind", "finding");
              ("subject", "ledger:" ^ commit);
            ]
            (List.filter_map
               (fun key ->
                 match List.assoc_opt key fields with
                 | Some (`String value) -> Some (key, value)
                 | _ -> None)
               [ "class"; "kind"; "subject" ])
      | _ -> Alcotest.fail "the record is no object")
  | _ -> Alcotest.fail "json gives no single record"

let a_check_of_the_tip_passes_where_the_history_fails () =
  let repo = ledger_repo () in
  ignore (drop_the_last_entry repo);
  Alcotest.(check (pair int int))
    "the log, the verification" (0, 3)
    ((run repo "ledger log").code, (run repo "ledger verify").code)

let no_ledger_is_a_warning () =
  let repo = Repo.init () in
  List.iter
    (fun command ->
      Alcotest.check ran command
        (0, [], [ "warning: no ledger found" ])
        (seen (run repo command)))
    [ "ledger verify"; "ledger log"; "ledger log -o json" ]

let log_prints_the_entries_in_order () =
  let repo = ledger_repo () in
  Alcotest.check ran "brief"
    ( 0,
      [
        "1 2026-01-01T00:00:00Z e-939f0d4459f6 approval req:r0 \
         approver@example.com";
        "2 2026-01-01T00:00:01Z e-90a9a4ead615 approval req:r1 \
         approver@example.com";
        "3 2026-01-01T00:00:02Z e-ac94b1e9d514 approval req:r2 \
         approver@example.com";
      ],
      [] )
    (seen (run repo "ledger log"));
  Alcotest.check ran "json"
    (0, List.init 3 Sinter_bench.Generated_ledger.entry, [])
    (seen (run repo "ledger log -o json"))

let log_stops_on_a_broken_tip () =
  let repo = Repo.init () in
  Repo.import repo
    [
      Repo.commit ~ref:Ledger.ref_name ~mark:1 ~message:"m"
        [ Repo.File ("README", "x\n") ];
    ];
  let result = run repo "ledger log" in
  Alcotest.(check (pair int (list string)))
    "the code and the output" (3, [])
    (result.code, lines result.out);
  Alcotest.(check bool)
    "the error names the repair" true
    (List.mem "  = help: repair the ledger with sinter ledger repair"
       (lines result.err))

let unknown_entries_give_a_warning () =
  let repo = Repo.init () in
  let fields =
    [
      ("v", Json.Int 1);
      ("seq", Json.Int 2);
      ("kind", Json.String "pin");
      ("by", Json.String "a");
    ]
  in
  let line =
    match Ledger.id_of (Json.Object fields) with
    | Ok id -> (
        match
          Json.to_string (Json.Object (("id", Json.String id) :: fields))
        with
        | Ok line -> line
        | Error _ -> Alcotest.fail "the line does not print")
    | Error _ -> Alcotest.fail "the line does not print"
  in
  Repo.import repo
    [
      Repo.commit ~ref:Ledger.ref_name ~mark:1 ~message:"m"
        (List.map
           (fun (path, content) -> Repo.File (path, content))
           (Sinter_bench.Generated_ledger.chunks
              [ Sinter_bench.Generated_ledger.entry 0; line ]));
    ];
  Alcotest.check ran "log"
    ( 0,
      [
        "1 2026-01-01T00:00:00Z e-939f0d4459f6 approval req:r0 \
         approver@example.com";
      ],
      [
        "warning: the ledger holds 1 entry of an unknown kind; sinter ignores \
         it";
      ] )
    (seen (run repo "ledger log"))

let generated = Sinter_bench.Generated_ledger.entry

let ledger_of states =
  let repo = Repo.init () in
  let _, commands =
    List.fold_left
      (fun (before, commands) chunks ->
        let files =
          List.concat_map Sinter_bench.Generated_ledger.chunks chunks
        in
        let mark = List.length commands + 1 in
        ( List.map fst files,
          Repo.commit ~ref:Ledger.ref_name ~mark
            ~message:(Printf.sprintf "write %d" mark)
            (List.filter_map
               (fun path ->
                 if List.mem_assoc path files then None
                 else Some (Repo.Delete path))
               before
            @ List.map (fun (path, content) -> Repo.File (path, content)) files
            )
          :: commands ))
      ([], []) states
  in
  Repo.import repo (List.rev commands);
  repo

let log_follows_seq_whatever_the_ts_says () =
  let late = generated ~seq:1 5 and early = generated ~seq:2 0 in
  let repo = ledger_of [ [ [ late ] ]; [ [ late ]; [ early ] ] ] in
  Alcotest.(check (pair int (list string)))
    "the order of the log"
    (0, [ "1 2026-01-01T00:00:05Z"; "2 2026-01-01T00:00:00Z" ])
    (let result = run repo "ledger log" in
     ( result.code,
       List.map
         (fun line ->
           String.concat " "
             (List.filteri (fun i _ -> i < 2) (String.split_on_char ' ' line)))
         (lines result.out) ));
  Alcotest.(check int) "the verification" 0 (run repo "ledger verify").code

let a_move_between_chunks_keeps_the_order () =
  let entries = List.init 4 (fun n -> generated ~seq:(4 - n) (10 + n)) in
  let repo =
    ledger_of
      [ [ entries ]; List.map (fun entry -> [ entry ]) (List.rev entries) ]
  in
  let before = ledger_of [ [ entries ] ] in
  Alcotest.(check (pair int int))
    "the verification of both" (0, 0)
    ((run repo "ledger verify").code, (run before "ledger verify").code);
  Alcotest.(check (list string))
    "the log"
    (lines (run before "ledger log").out)
    (lines (run repo "ledger log").out)

let a_swap_of_two_entries_between_chunks_fails () =
  let first = generated ~seq:1 0 and second = generated ~seq:2 1 in
  let first' = generated ~seq:2 0 and second' = generated ~seq:1 1 in
  let repo =
    ledger_of [ [ [ first ]; [ second ] ]; [ [ second' ]; [ first' ] ] ]
  in
  let result = run repo "ledger verify" in
  Alcotest.(check int) "the code" 3 result.code;
  Alcotest.(check bool)
    "the error names a dropped entry" true
    (match lines result.err with
    | first_line :: _ ->
        String.starts_with
          ~prefix:("error: the ledger is broken: the commit " ^ tip repo)
          first_line
        && List.exists (String.equal "drops")
             (String.split_on_char ' ' first_line)
    | [] -> false)

let a_missing_object_says_how_to_fetch () =
  let repo = Repo.init () in
  let missing = String.make 40 'd' in
  Out_channel.with_open_bin
    (Filename.concat (Repo.root repo) ".git/packed-refs")
    (fun channel ->
      Out_channel.output_string channel
        (Printf.sprintf "%s %s\n" missing Ledger.ref_name));
  Alcotest.check ran "verify"
    ( 3,
      [],
      [
        Printf.sprintf
          "error: the clone does not hold the object %s of the ledger, in the \
           commit %s"
          missing missing;
        "  = help: fetch every object of the ledger with git fetch --refetch \
         --no-filter origin refs/sinter/ledger";
      ] )
    (seen (run repo "ledger verify"))

let outside_a_repository_is_an_error () =
  let dir = Repo.temp_dir () in
  let err = Filename.temp_file "sinter-ledger" ".err" in
  let code =
    Sys.command
      (Printf.sprintf
         "cd %s && GIT_CEILING_DIRECTORIES=%s NO_COLOR=1 %s ledger log \
          >/dev/null 2>%s"
         (Filename.quote dir)
         (Filename.quote (Filename.dirname dir))
         (Filename.quote sinter) (Filename.quote err))
  in
  let text = contents err in
  Sys.remove err;
  Alcotest.(check int) "the code" 3 code;
  Alcotest.(check bool)
    "the error names the folder" true
    (String.starts_with
       ~prefix:
         (Printf.sprintf "error: the folder %s is in no git repository\n"
            (Unix.realpath dir))
       text)

let a_wrong_form_is_a_usage_error () =
  let repo = Repo.init () in
  Alcotest.(check (pair int int))
    "verify and log" (2, 2)
    ( (run repo "ledger verify -o full").code,
      (run repo "ledger log -o sarif").code )

let the_help_names_the_exit_codes () =
  let repo = Repo.init () in
  let words text =
    String.concat " "
      (List.filter
         (fun word -> word <> "")
         (String.split_on_char ' '
            (String.map (fun c -> if c = '\n' then ' ' else c) text)))
  in
  let contains text part =
    let n = String.length part in
    let rec at i =
      i + n <= String.length text && (String.sub text i n = part || at (i + 1))
    in
    at 0
  in
  List.iter
    (fun command ->
      Alcotest.(check bool)
        (command ^ " says that a broken ledger exits with 3")
        true
        (contains
           (words (run repo (command ^ " --help=plain")).out)
           "3 when the command cannot run in this environment, when the ledger \
            is broken, and when the ledger does not read."))
    [ "ledger verify"; "ledger log" ]

let tests =
  List.map
    (fun (name, f) -> Alcotest.test_case name `Quick f)
    [
      ("verify passes a sound ledger", verify_passes_a_sound_ledger);
      ("verify stops on a broken ledger", verify_stops_on_a_broken_ledger);
      ( "a check of the tip passes where the history fails",
        a_check_of_the_tip_passes_where_the_history_fails );
      ("no ledger is a warning", no_ledger_is_a_warning);
      ("log prints the entries in order", log_prints_the_entries_in_order);
      ("log stops on a broken tip", log_stops_on_a_broken_tip);
      ("unknown entries give a warning", unknown_entries_give_a_warning);
      ( "log follows seq, whatever the ts says",
        log_follows_seq_whatever_the_ts_says );
      ( "a move between chunks keeps the order",
        a_move_between_chunks_keeps_the_order );
      ( "a swap of two entries between chunks fails",
        a_swap_of_two_entries_between_chunks_fails );
      ( "a missing object says how to fetch it",
        a_missing_object_says_how_to_fetch );
      ("outside a repository is an error", outside_a_repository_is_an_error);
      ("a wrong form is a usage error", a_wrong_form_is_a_usage_error);
      ("the help names the exit codes", the_help_names_the_exit_codes);
    ]
