(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let manifest_of text =
  match Manifest.of_string text with
  | Ok manifest -> manifest
  | Error _ -> Alcotest.fail "the manifest has an error"

let packs = "[scan]\npacks.markdown.files = [\"**/*.md\"]\n"
let plain = manifest_of packs

(* Under the rollout cap, with a tier that passes it, and a class that the
   manifest turns off. *)
let capped =
  manifest_of
    (packs
   ^ "[check]\n\
      rollout-cap = true\n\
      tiers.merge.parse-error = \"block\"\n\
      tiers.merge.dangling = \"block\"\n\
      tiers.merge.suspect = \"off\"\n")

let at line column = { Markdown.line; column }

let place ?(path = "docs/a.md") ?(line = 3) ?(column = 2) ?(stop = 9) () =
  {
    Finding.path;
    span = { Markdown.start = at line column; stop = at (line + 1) stop };
  }

let error_node = Finding.Error_node { path = "docs/a.md"; position = at 5 1 }
let file = Finding.File "docs/b.md"
let edge = Finding.Fact { id = "cites:site:docs/a.md->x"; ack_name = "x" }

let finding ?place ?detail ?fix c subject =
  Finding.make c subject ?place ?detail ?fix ()

let tier = Alcotest.testable (Fmt.of_to_string Finding_class.tier_name) ( = )

(* Generators. *)

let word =
  Gen.(
    string_size
      ~gen:(oneof_list [ 'a'; 'b'; '/'; '.'; ' '; '\t'; '"'; '\\' ])
      (int_range 1 6))

let position = Gen.(map2 at (int_range 1 99) (int_range 1 99))

let subject =
  Gen.(
    oneof
      [
        map2 (fun id ack_name -> Finding.Fact { id; ack_name }) word word;
        map (fun path -> Finding.File path) word;
        map2
          (fun path position -> Finding.Error_node { path; position })
          word position;
        map2
          (fun path line -> Finding.Line { path; line })
          word (int_range 1 99);
        map2 (fun path position -> Finding.Tag { path; position }) word position;
      ])

let place_gen =
  Gen.(
    map3
      (fun path start stop -> { Finding.path; span = { Markdown.start; stop } })
      word position position)

let finding_gen =
  Gen.(
    map
      (fun (c, subject, place, (detail, fix)) ->
        Finding.make c subject ?place ?detail ?fix ())
      (quad
         (oneof_list Finding_class.all)
         subject (option place_gen)
         (pair (option word) (option word))))

let print_finding (finding : Finding.t) =
  String.concat "\n" (Check.text { Check.finding; tier = None })

let gate_gen = Gen.oneof_list Finding_class.gates
let manifest_gen = Gen.oneof_list [ plain; capped ]

let property ?(count = 300) name gen print f =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print gen f)

(* Tiers. *)

let a_parse_error_at_an_error_node_warns_where_its_class_blocks () =
  let tiers manifest gate =
    List.map
      (fun subject ->
        Check.tier manifest gate (finding Finding_class.Parse_error subject))
      [ error_node; file ]
  in
  Alcotest.(check (list (option tier)))
    "an error node and a file that is not text, at merge"
    [ Some Finding_class.Warn; Some Finding_class.Block ]
    (tiers plain Finding_class.Merge);
  Alcotest.(check (list (option tier)))
    "the same under the cap, where the manifest writes block"
    [ Some Finding_class.Warn; Some Finding_class.Block ]
    (tiers capped Finding_class.Merge);
  Alcotest.(check (list (option tier)))
    "the same at turn, where the class warns"
    [ Some Finding_class.Warn; Some Finding_class.Warn ]
    (tiers plain Finding_class.Turn)

let a_finding_takes_the_tier_of_its_class () =
  Alcotest.(check (list (option tier)))
    "dangling under the cap, suspect turned off, bad-scope at target"
    [ Some Finding_class.Block; Some Finding_class.Off; None ]
    [
      Check.tier capped Finding_class.Merge
        (finding Finding_class.Dangling edge);
      Check.tier capped Finding_class.Merge (finding Finding_class.Suspect edge);
      Check.tier plain Finding_class.Target
        (finding Finding_class.Bad_scope edge);
    ]

let only_a_parse_error_at_an_error_node_changes_its_tier =
  property "only a parse error at an error node changes its tier"
    Gen.(triple manifest_gen gate_gen finding_gen)
    (fun (_, gate, finding) ->
      Finding_class.gate_name gate ^ " " ^ print_finding finding)
    (fun (manifest, gate, finding) ->
      let applies = Manifest.tier manifest gate finding.finding_class in
      let lowered =
        finding.finding_class = Finding_class.Parse_error
        && (match finding.subject with
          | Finding.Error_node _ -> true
          | _ -> false)
        && applies = Some Finding_class.Block
      in
      Check.tier manifest gate finding
      = if lowered then Some Finding_class.Warn else applies)

(* Selection. *)

let entries_of = List.map (fun (entry : Check.entry) -> entry.finding)

let with_no_gate_every_finding_counts_with_no_tier () =
  let findings =
    [
      finding Finding_class.Uncovered edge; finding Finding_class.Bad_scope edge;
    ]
  in
  let entries = Check.select plain None findings in
  Alcotest.(check bool) "the findings" true (entries_of entries = findings);
  Alcotest.(check bool)
    "no tier" true
    (List.for_all (fun (entry : Check.entry) -> entry.tier = None) entries)

(* Each class and the gate and tier of its entry. *)
let tiers_of entries =
  List.map
    (fun (entry : Check.entry) ->
      ( Finding_class.name entry.finding.finding_class,
        Option.map
          (fun (gate, tier) ->
            (Finding_class.gate_name gate, Finding_class.tier_name tier))
          entry.tier ))
    entries

let a_gate_leaves_out_a_class_that_is_off_or_has_no_tier () =
  let findings =
    [
      finding Finding_class.Uncovered edge;
      finding Finding_class.Dangling edge;
      finding Finding_class.Unverified_promise edge;
      finding Finding_class.Parse_error error_node;
    ]
  in
  let tiers = Alcotest.(list (pair string (option (pair string string)))) in
  Alcotest.check tiers "the entries at turn, where uncovered is off"
    [
      ("dangling", Some ("turn", "block"));
      ("unverified-promise", Some ("turn", "warn"));
      ("parse-error", Some ("turn", "warn"));
    ]
    (tiers_of (Check.select plain (Some Finding_class.Turn) findings));
  Alcotest.check tiers
    "the entries at target, where unverified-promise takes no tier"
    [
      ("uncovered", Some ("target", "warn"));
      ("dangling", Some ("target", "block"));
      ("parse-error", Some ("target", "warn"));
    ]
    (tiers_of (Check.select plain (Some Finding_class.Target) findings))

let a_gate_keeps_each_finding_that_warns_or_blocks_in_order =
  property "a gate keeps each finding that warns or blocks, in order"
    Gen.(triple manifest_gen gate_gen (list_size (int_range 0 8) finding_gen))
    (fun (_, gate, findings) ->
      Finding_class.gate_name gate
      ^ "\n"
      ^ String.concat "\n" (List.map print_finding findings))
    (fun (manifest, gate, findings) ->
      let expected =
        List.filter_map
          (fun finding ->
            match Check.tier manifest gate finding with
            | Some (Finding_class.Warn | Finding_class.Block) as tier ->
                Some (finding, Option.map (fun tier -> (gate, tier)) tier)
            | Some Finding_class.Off | None -> None)
          findings
      in
      List.map
        (fun (entry : Check.entry) -> (entry.finding, entry.tier))
        (Check.select manifest (Some gate) findings)
      = expected)

(* Exit codes. *)

let entry ?tier c = { Check.finding = finding c edge; tier }
let warn = (Finding_class.Turn, Finding_class.Warn)
let block = (Finding_class.Turn, Finding_class.Block)

let the_exit_code_follows_the_blocking_findings () =
  Alcotest.(check (list int))
    "nothing; a warning; a warning under --strict; a finding with no gate \
     under --strict; a finding that blocks"
    [ 0; 0; 1; 1; 1 ]
    [
      Check.exit_code ~strict:true [];
      Check.exit_code ~strict:false [ entry ~tier:warn Finding_class.Suspect ];
      Check.exit_code ~strict:true [ entry ~tier:warn Finding_class.Suspect ];
      Check.exit_code ~strict:true [ entry Finding_class.Suspect ];
      Check.exit_code ~strict:false
        [
          entry ~tier:warn Finding_class.Suspect;
          entry ~tier:block Finding_class.Dangling;
        ];
    ]

let a_finding_blocks_at_its_tier_or_under_strict =
  property "a finding blocks at the tier block, or any finding under --strict"
    Gen.(
      pair bool
        (list_size (int_range 0 5)
           (option
              (oneof_list
                 [ warn; block; (Finding_class.Merge, Finding_class.Off) ]))))
    (fun (strict, tiers) ->
      Printf.sprintf "strict %b, %d entries" strict (List.length tiers))
    (fun (strict, tiers) ->
      let entries =
        List.map (fun tier -> entry ?tier Finding_class.Orphan) tiers
      in
      Check.exit_code ~strict entries
      =
      if
        List.exists
          (fun tier -> Option.map snd tier = Some Finding_class.Block)
          tiers
        || (strict && tiers <> [])
      then Exit_code.findings
      else Exit_code.clean)

(* The text form. *)

let a_finding_prints_its_place_tier_class_subject_and_detail () =
  Alcotest.(check (list string))
    "the lines"
    [
      "docs/a.md:3:2: block suspect cites:site:docs/a.md->x pinned to v1; the \
       declaration is at v2";
      "  fix: @cites x v2";
    ]
    (Check.text
       {
         finding =
           finding ~place:(place ())
             ~detail:"pinned to v1; the declaration is at v2" ~fix:"@cites x v2"
             Finding_class.Suspect edge;
         tier = Some (Finding_class.Merge, Finding_class.Block);
       });
  Alcotest.(check (list string))
    "with no tier, no detail, and no fix"
    [ "docs/a.md:3:2: orphan cites:site:docs/a.md->x" ]
    (Check.text
       {
         finding = finding ~place:(place ()) Finding_class.Orphan edge;
         tier = None;
       })

let a_finding_with_no_place_prints_dashes () =
  Alcotest.(check (list string))
    "the line"
    [ "-:-:-: warn orphan cites:site:docs/a.md->x" ]
    (Check.text
       { finding = finding Finding_class.Orphan edge; tier = Some warn })

let a_subject_with_a_space_stands_in_quotes () =
  Alcotest.(check (list string))
    "the lines"
    [
      "my docs/a.md:1:1: typo-tag \"line:my docs/a\\\"b\\\\.md@L1\"";
      "-:-:-: typo-tag \"line:a\tb@L1\"";
    ]
    (List.concat_map Check.text
       [
         {
           Check.finding =
             finding
               ~place:(place ~path:"my docs/a.md" ~line:1 ~column:1 ())
               Finding_class.Typo_tag
               (Finding.Line { path = "my docs/a\"b\\.md"; line = 1 });
           tier = None;
         };
         {
           finding =
             finding Finding_class.Typo_tag
               (Finding.Line { path = "a\tb"; line = 1 });
           tier = None;
         };
       ])

let a_finding_gives_one_line_and_one_more_for_a_fix =
  property "a finding gives one line, and one more for a fix"
    Gen.(pair finding_gen (option (oneof_list [ warn; block ])))
    (fun (finding, _) -> print_finding finding)
    (fun (finding, tier) ->
      let lines = Check.text { finding; tier } in
      let place =
        match finding.place with
        | Some { path; span } ->
            Printf.sprintf "%s:%d:%d: " path span.start.line span.start.column
        | None -> "-:-:-: "
      in
      List.length lines = 1 + Option.fold ~none:0 ~some:(fun _ -> 1) finding.fix
      &&
      match lines with
      | first :: rest ->
          String.starts_with ~prefix:place first
          && List.for_all (String.starts_with ~prefix:"  fix: ") rest
      | [] -> false)

(* Records. *)

let a_record_holds_every_field_of_a_finding () =
  Alcotest.(check string)
    "the record"
    "{\"ack_subject\":\"x\",\"ackable\":true,\"class\":\"disendorsed\",\"col\":2,\"detail\":\"d\",\"ecol\":9,\"eline\":4,\"fix\":\"f\",\"gate\":\"merge\",\"id\":\"finding:disendorsed:cites:site:docs/a.md->x\",\"kind\":\"finding\",\"line\":3,\"mode\":\"tree\",\"path\":\"docs/a.md\",\"subject\":\"cites:site:docs/a.md->x\",\"tier\":\"block\",\"v\":1}"
    (Jsonl.to_string
       (Check.record
          {
            finding =
              finding ~place:(place ()) ~detail:"d" ~fix:"f"
                Finding_class.Disendorsed edge;
            tier = Some (Finding_class.Merge, Finding_class.Block);
          }))

let a_record_leaves_out_what_a_finding_does_not_have () =
  Alcotest.(check string)
    "the record"
    "{\"ack_subject\":\"file:docs/b.md\",\"ackable\":false,\"class\":\"parse-error\",\"id\":\"finding:parse-error:file:docs/b.md\",\"kind\":\"finding\",\"mode\":\"tree\",\"subject\":\"file:docs/b.md\",\"v\":1}"
    (Jsonl.to_string
       (Check.record
          { finding = finding Finding_class.Parse_error file; tier = None }))

let a_record_is_canonical_and_names_a_gate_only_with_a_tier =
  property "a record is canonical, and names a gate only with a tier"
    Gen.(pair finding_gen (option (oneof_list [ warn; block ])))
    (fun (finding, _) -> print_finding finding)
    (fun (finding, tier) ->
      let record = Check.record { finding; tier } in
      ignore (Jsonl.to_string record);
      List.mem_assoc "gate" record = Option.is_some tier
      && List.mem_assoc "tier" record = Option.is_some tier
      && List.mem_assoc "path" record = Option.is_some finding.place)

(* The check of a repository. *)

let a_check_reads_the_repository_and_reports_at_its_gate () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml" packs;
  Git_fixture.write repo "docs/table.md"
    "# T\n\n| Name | D |\n| ---- | - |\n| `x`  | y |\n|      |   |\n";
  Git_fixture.write repo "docs/b.md" "# B\n\n@req \xff\n";
  ignore (Git_fixture.git repo [ "add"; "-A" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "-m"; "c" ]);
  let head = String.trim (Git_fixture.git repo [ "rev-parse"; "HEAD" ]) in
  let run format gate =
    match
      Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
        ~manifest:None ~base:None ~gate ~strict:false ~format ~tool:"v1"
    with
    | Ok report -> report
    | Error error ->
        Alcotest.failf "the check fails: %s"
          (String.concat "; " (Scan.messages error))
  in
  let text = run Check.Text None in
  Alcotest.(check (list string))
    "the messages of the text"
    [
      "the base is the merge base of HEAD and refs/heads/main, " ^ head;
      "warning: the ledger ref refs/sinter/ledger is absent, so every plan \
       counts as open; fetch it with git fetch origin \
       refs/sinter/ledger:refs/sinter/ledger";
    ]
    text.messages;
  Alcotest.(check (pair int (list string)))
    "the code and the places of the text"
    (0, [ "docs/b.md:1:1:"; "docs/table.md:5:1:" ])
    ( text.code,
      List.map (fun line -> List.hd (String.split_on_char ' ' line)) text.lines
    );
  let json = run Check.Json (Some Finding_class.Merge) in
  Alcotest.(check (pair int int))
    "the code and the number of lines of the JSON" (1, 3)
    (json.code, List.length json.lines);
  Alcotest.(check bool)
    "the index first, and no line that names the base" true
    (String.starts_with ~prefix:"{\"base\":\"" (List.hd json.lines)
    && List.length json.messages = 1)

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "a parse error at an error node warns where its class blocks"
      a_parse_error_at_an_error_node_warns_where_its_class_blocks;
    case "a finding takes the tier of its class"
      a_finding_takes_the_tier_of_its_class;
    only_a_parse_error_at_an_error_node_changes_its_tier;
    case "with no gate, every finding counts with no tier"
      with_no_gate_every_finding_counts_with_no_tier;
    case "a gate leaves out a class that is off or has no tier"
      a_gate_leaves_out_a_class_that_is_off_or_has_no_tier;
    a_gate_keeps_each_finding_that_warns_or_blocks_in_order;
    case "the exit code follows the blocking findings"
      the_exit_code_follows_the_blocking_findings;
    a_finding_blocks_at_its_tier_or_under_strict;
    case "a finding prints its place, tier, class, subject, and detail"
      a_finding_prints_its_place_tier_class_subject_and_detail;
    case "a finding with no place prints dashes"
      a_finding_with_no_place_prints_dashes;
    case "a subject with a space stands in quotes"
      a_subject_with_a_space_stands_in_quotes;
    a_finding_gives_one_line_and_one_more_for_a_fix;
    case "a record holds every field of a finding"
      a_record_holds_every_field_of_a_finding;
    case "a record leaves out what a finding does not have"
      a_record_leaves_out_what_a_finding_does_not_have;
    a_record_is_canonical_and_names_a_gate_only_with_a_tier;
    case "a check reads the repository and reports at its gate"
      a_check_reads_the_repository_and_reports_at_its_gate;
  ]
