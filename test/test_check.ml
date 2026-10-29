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

let warn_only =
  manifest_of
    (packs
   ^ "[check]\n\
      warn-only = true\n\
      tiers.review.parse-error = \"block\"\n\
      tiers.review.dangling = \"block\"\n\
      tiers.review.suspect = \"off\"\n")

let at line column = { Markdown.line; column }

let place ?(path = "docs/a.md") ?(line = 3) ?(column = 2) ?(stop = 9) () =
  {
    Finding.path;
    span = { Markdown.start = at line column; stop = at (line + 1) stop };
  }

let error_node = Finding.Error_node { path = "docs/a.md"; position = at 5 1 }
let file = Finding.File "docs/b.md"
let edge = Finding.Fact { id = "cites:site:docs/a.md->x"; ack_name = "x" }

let finding ?place ?detail ?fix ?ackable c subject =
  Finding.make c subject ?place ?detail ?fix ?ackable ()

let tier = Alcotest.testable (Fmt.of_to_string Finding_class.tier_name) ( = )

let word =
  Gen.(
    string_size
      ~gen:(oneof_list [ 'a'; 'b'; '/'; '.'; ' '; '\t'; '"'; '\\'; '\n'; '\r' ])
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
        Finding.make c subject ?place ?detail
          ?fix:(Option.bind place (fun _ -> Option.map Edits.word_fix fix))
          ())
      (quad
         (oneof_list Finding_class.all)
         subject (option place_gen)
         (pair (option word) (option word))))

let print_finding (finding : Finding.t) =
  Printf.sprintf "%s %S"
    (Finding_class.name finding.finding_class)
    (Finding.subject_id finding.subject)

let gate_gen = Gen.oneof_list Finding_class.gates
let manifest_gen = Gen.oneof_list [ plain; warn_only ]

let property ?(count = 300) name gen print f =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print gen f)

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
    (tiers plain Finding_class.Review);
  Alcotest.(check (list (option tier)))
    "the same under warn-only, where the manifest writes block"
    [ Some Finding_class.Warn; Some Finding_class.Block ]
    (tiers warn_only Finding_class.Review);
  Alcotest.(check (list (option tier)))
    "the same at turn, where the class warns"
    [ Some Finding_class.Warn; Some Finding_class.Warn ]
    (tiers plain Finding_class.Turn)

let a_finding_takes_the_tier_of_its_class () =
  Alcotest.(check (list (option tier)))
    "dangling under warn-only, suspect turned off, scope-outside-plan at merged"
    [ Some Finding_class.Block; Some Finding_class.Off; None ]
    [
      Check.tier warn_only Finding_class.Review
        (finding Finding_class.Dangling edge);
      Check.tier warn_only Finding_class.Review
        (finding Finding_class.Suspect edge);
      Check.tier plain Finding_class.Merged
        (finding Finding_class.Scope_outside_plan edge);
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

let entries_of = List.map (fun (entry : Check.entry) -> entry.finding)

let with_no_gate_every_finding_counts_with_no_tier () =
  let findings =
    [
      finding Finding_class.Untraced edge;
      finding Finding_class.Scope_outside_plan edge;
    ]
  in
  let entries = Check.select plain None findings in
  Alcotest.(check bool) "the findings" true (entries_of entries = findings);
  Alcotest.(check bool)
    "no tier" true
    (List.for_all (fun (entry : Check.entry) -> entry.tier = None) entries)

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
      finding Finding_class.Untraced edge;
      finding Finding_class.Dangling edge;
      finding Finding_class.Unverified_promise edge;
      finding Finding_class.Parse_error error_node;
    ]
  in
  let tiers = Alcotest.(list (pair string (option (pair string string)))) in
  Alcotest.check tiers "the entries at turn, where untraced is off"
    [
      ("dangling", Some ("turn", "block"));
      ("unverified-promise", Some ("turn", "warn"));
      ("parse-error", Some ("turn", "warn"));
    ]
    (tiers_of (Check.select plain (Some Finding_class.Turn) findings));
  Alcotest.check tiers
    "the entries at merged, where unverified-promise takes no tier"
    [
      ("untraced", Some ("merged", "warn"));
      ("dangling", Some ("merged", "block"));
      ("parse-error", Some ("merged", "warn"));
    ]
    (tiers_of (Check.select plain (Some Finding_class.Merged) findings))

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

let entry ?tier c = { Check.finding = finding c edge; tier }
let warn = (Finding_class.Turn, Finding_class.Warn)
let block = (Finding_class.Turn, Finding_class.Block)

let the_exit_code_follows_the_blocking_findings () =
  Alcotest.(check (list int))
    "nothing; a warning; a warning under --strict; a finding with no gate \
     under --strict; a finding that blocks; config-changed under --strict; \
     config-changed and a warning under --strict"
    [ 0; 0; 1; 1; 1; 0; 1 ]
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
      Check.exit_code ~strict:true
        [
          entry ~tier:warn Finding_class.Config_changed;
          entry Finding_class.Config_changed;
        ];
      Check.exit_code ~strict:true
        [
          entry ~tier:warn Finding_class.Config_changed;
          entry ~tier:warn Finding_class.Suspect;
        ];
    ]

let a_finding_blocks_at_its_tier_or_under_strict =
  property
    "a finding blocks at the tier block, or any finding but config-changed \
     under --strict"
    Gen.(
      pair bool
        (list_size (int_range 0 5)
           (pair
              (oneof_list
                 [ Finding_class.Wrong_source; Finding_class.Config_changed ])
              (option
                 (oneof_list
                    [ warn; block; (Finding_class.Review, Finding_class.Off) ])))))
    (fun (strict, tiers) ->
      Printf.sprintf "strict %b, %d entries" strict (List.length tiers))
    (fun (strict, tiers) ->
      let entries = List.map (fun (c, tier) -> entry ?tier c) tiers in
      Check.exit_code ~strict entries
      =
      if
        List.exists
          (fun (_, tier) -> Option.map snd tier = Some Finding_class.Block)
          tiers
        || strict
           && List.exists
                (fun (c, _) -> c <> Finding_class.Config_changed)
                tiers
      then Exit_code.findings
      else Exit_code.clean)

let a_record_holds_every_field_of_a_finding () =
  Alcotest.(check string)
    "the record"
    "{\"ack_subject\":\"x\",\"ackable\":true,\"class\":\"retired\",\"col\":2,\"detail\":\"d\",\"ecol\":9,\"edits\":[{\"alt\":1,\"col\":1,\"ecol\":3,\"eline\":1,\"line\":1,\"path\":\"docs/a.md\",\"text\":\"@f\"}],\"eline\":4,\"gate\":\"review\",\"help\":\"replace \
     the tag word with the nearest tag word that Sinter \
     knows\",\"id\":\"finding:retired:cites:site:docs/a.md->x\",\"kind\":\"finding\",\"line\":3,\"mode\":\"tree\",\"path\":\"docs/a.md\",\"subject\":\"cites:site:docs/a.md->x\",\"tier\":\"block\",\"v\":1}"
    (Jsonl.to_string
       (Check.record ~mode:Mode.Tree
          {
            finding =
              finding ~place:(place ()) ~detail:"d" ~fix:(Edits.word_fix "f")
                ~ackable:true Finding_class.Retired edge;
            tier = Some (Finding_class.Review, Finding_class.Block);
          }))

let a_record_leaves_out_what_a_finding_does_not_have () =
  Alcotest.(check string)
    "the record"
    "{\"ack_subject\":\"file:docs/b.md\",\"ackable\":false,\"class\":\"parse-error\",\"id\":\"finding:parse-error:file:docs/b.md\",\"kind\":\"finding\",\"mode\":\"diff\",\"subject\":\"file:docs/b.md\",\"v\":1}"
    (Jsonl.to_string
       (Check.record ~mode:Mode.Diff
          { finding = finding Finding_class.Parse_error file; tier = None }))

let a_record_holds_the_mark_and_the_related_places () =
  let finding =
    Finding.make Finding_class.Suspect edge ~place:(place ())
      ~mark:{ Finding.start = 4; stop = 6; label = "names v1" }
      ~related:
        [
          { Finding.label = "on another branch"; place = None };
          { Finding.label = "now at v2"; place = Some (place ~path:"b.md" ()) };
        ]
      ()
  in
  Alcotest.(check string)
    "the record"
    "{\"ack_subject\":\"x\",\"ackable\":false,\"class\":\"suspect\",\"col\":2,\"ecol\":9,\"eline\":4,\"id\":\"finding:suspect:cites:site:docs/a.md->x\",\"kind\":\"finding\",\"label\":\"names \
     v1\",\"line\":3,\"mcol\":4,\"mecol\":6,\"mode\":\"tree\",\"path\":\"docs/a.md\",\"related\":[{\"col\":2,\"ecol\":9,\"eline\":4,\"label\":\"now \
     at v2\",\"line\":3,\"path\":\"b.md\"},{\"label\":\"on another \
     branch\"}],\"subject\":\"cites:site:docs/a.md->x\",\"v\":1}"
    (Jsonl.to_string (Check.record ~mode:Mode.Tree { finding; tier = None }))

let mark_gen =
  Gen.(
    map3
      (fun start length label ->
        { Finding.start; stop = start + length; label })
      (int_range 99 120) (int_range 1 3) word)

let related_gen =
  Gen.(
    map
      (fun related ->
        List.sort_uniq
          (fun (a : Finding.related) (b : Finding.related) ->
            compare
              (Finding.escape a.label, a.place)
              (Finding.escape b.label, b.place))
          related)
      (list_size (int_range 0 3)
         (map2
            (fun label place -> { Finding.label; place })
            word (option place_gen))))

let marked_finding_gen =
  Gen.(
    map
      (fun (c, subject, (place, mark), related) ->
        Finding.make c subject ?place ?mark ~related ())
      (quad
         (oneof_list Finding_class.all)
         subject
         (oneof
            [
              map (fun place -> (place, None)) (option place_gen);
              map2
                (fun place mark ->
                  ( Some
                      {
                        place with
                        Finding.span =
                          { Markdown.start = at 1 1; stop = at 2 1 };
                      },
                    Some mark ))
                place_gen mark_gen;
            ])
         related_gen))

let a_record_writes_the_mark_and_the_related_places_it_has =
  property "a record writes the mark and the related places that it has"
    marked_finding_gen print_finding (fun finding ->
      let record = Check.record ~mode:Mode.Tree { finding; tier = None } in
      ignore (Jsonl.to_string record);
      let has name = List.mem_assoc name record in
      let marked = Option.is_some finding.mark in
      has "mcol" = marked
      && has "mecol" = marked
      && has "label" = marked
      &&
      match (List.assoc_opt "related" record, finding.related) with
      | None, [] -> true
      | Some (Jsonl.Objects objects), (_ :: _ as related) ->
          List.length objects = List.length related
          && List.for_all2
               (fun fields (related : Finding.related) ->
                 List.assoc_opt "label" fields
                 = Some (Jsonl.String related.label)
                 && List.for_all
                      (fun name ->
                        List.mem_assoc name fields
                        = Option.is_some related.place)
                      [ "path"; "line"; "col"; "eline"; "ecol" ])
               objects related
      | _ -> false)

let a_record_is_canonical_and_names_a_gate_only_with_a_tier =
  property "a record is canonical, and names a gate only with a tier"
    Gen.(pair finding_gen (option (oneof_list [ warn; block ])))
    (fun (finding, _) -> print_finding finding)
    (fun (finding, tier) ->
      let record = Check.record ~mode:Mode.Tree { finding; tier } in
      ignore (Jsonl.to_string record);
      List.mem_assoc "gate" record = Option.is_some tier
      && List.mem_assoc "tier" record = Option.is_some tier
      && List.mem_assoc "path" record = Option.is_some finding.place)

let written report =
  let buffer = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buffer in
  Style.prepare ppf `None;
  Check.write ppf report;
  List.filter
    (fun line -> line <> "")
    (String.split_on_char '\n' (Buffer.contents buffer))

let a_check_reads_the_repository_and_reports_at_its_gate () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml" packs;
  Git_fixture.write repo "docs/table.md"
    "# T\n\n| Name | D |\n| ---- | - |\n| `x`  | y |\n|      |   |\n";
  Git_fixture.write repo "docs/b.md" "# B\n\n@req \xff\n";
  let line_feed =
    match Git_fixture.write repo "docs/line\nfeed.md" "# L\n\n@cites x!\n" with
    | () -> true
    | exception Sys_error _ -> false
  in
  ignore (Git_fixture.git repo [ "add"; "-A" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "-m"; "c" ]);
  let head = String.trim (Git_fixture.git repo [ "rev-parse"; "HEAD" ]) in
  let run form gate =
    match
      Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
        ~manifest:None ~base:None ~mode:Mode.Tree ~gate ~strict:false ~form
        ~tool:"v1" ()
    with
    | Ok report -> report
    | Error error ->
        Alcotest.failf "the check fails: %s"
          (String.concat "; " (Scan.messages error))
  in
  let text = run Check.Brief None in
  Alcotest.(check (list string))
    "the messages of the text"
    [
      "the base is the merge base of HEAD and refs/heads/main, " ^ head;
      "warning: the ledger ref refs/sinter/ledger is absent, so every plan \
       counts as open; fetch it with git fetch origin \
       refs/sinter/ledger:refs/sinter/ledger";
    ]
    (Check.messages text);
  Alcotest.(check (pair int (list string)))
    "the code and the places of the text"
    ( 0,
      [ "docs/b.md:1:1:" ]
      @ (if line_feed then [ "docs/line\xef\xbf\xbdfeed.md:3:1:" ] else [])
      @ [ "docs/table.md:5:1:" ] )
    ( Check.code text,
      List.map
        (fun line -> List.hd (String.split_on_char ' ' line))
        (written text) );
  let json = run Check.Json (Some Finding_class.Review) in
  Alcotest.(check (pair int int))
    "the code and the number of lines of the JSON"
    (1, if line_feed then 4 else 3)
    (Check.code json, List.length (written json));
  Alcotest.(check bool)
    "the index first, and no line that names the base" true
    (String.starts_with ~prefix:"{\"base\":\"" (List.hd (written json))
    && List.length (Check.messages json) = 1)

let case name f = Alcotest.test_case name `Quick f

let diff_lines ?base repo =
  match
    Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
      ~manifest:None ~base ~mode:Mode.Diff ~gate:None ~strict:false
      ~form:Check.Brief ~tool:"v1" ()
  with
  | Ok report -> written report
  | Error error ->
      Alcotest.failf "the check fails: %s"
        (String.concat "; " (Scan.messages error))

let commit repo message =
  ignore (Git_fixture.git repo [ "add"; "-A" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "-m"; message ])

let a_diff_against_the_merge_base_reports_what_the_branch_adds () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml" packs;
  Git_fixture.write repo "docs/a.md" "# A\n\n@cites old v1\n@revs a\n";
  commit repo "main";
  ignore (Git_fixture.git repo [ "checkout"; "-q"; "-b"; "work" ]);
  Git_fixture.write repo "docs/a.md"
    "# A\n\n@cites old v1\n@revs a\n\n## B\n\n@cites new v1\n";
  commit repo "work";
  ignore (Git_fixture.git repo [ "checkout"; "-q"; "main" ]);
  Git_fixture.write repo "docs/main.md" "# M\n\n@cites later v1\n";
  commit repo "later on main";
  ignore (Git_fixture.git repo [ "checkout"; "-q"; "work" ]);
  Alcotest.(check (list string))
    "the finding of the branch"
    [
      "docs/a.md:5:1: unplanned-change no step of an open plan, no rule, and \
       no exempt path covers docs/a.md";
      "docs/a.md:8:1: dangling no declaration has the slug new";
    ]
    (diff_lines repo)

let a_diff_compares_each_file_as_git_stores_it () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml" packs;
  List.iter
    (fun name ->
      Git_fixture.write repo
        ("docs/" ^ name ^ ".md")
        ("# " ^ name ^ "\n\n@cites old-" ^ name ^ " v1\n@revs x\n"))
    [ "untracked"; "intent"; "assumed"; "skipped"; "crlf" ];
  commit repo "base";
  ignore
    (Git_fixture.git repo
       [ "rm"; "-q"; "--cached"; "docs/untracked.md"; "docs/intent.md" ]);
  ignore (Git_fixture.git repo [ "add"; "-N"; "docs/intent.md" ]);
  ignore
    (Git_fixture.git repo
       [ "update-index"; "--assume-unchanged"; "docs/assumed.md" ]);
  ignore
    (Git_fixture.git repo
       [ "update-index"; "--skip-worktree"; "docs/skipped.md" ]);
  Git_fixture.append_config repo "[core]\n\tautocrlf = true\n";
  Git_fixture.write repo "docs/crlf.md"
    "# crlf\r\n\r\n@cites old-crlf v1\r\n@revs x\r\n";
  List.iter
    (fun name ->
      Git_fixture.write repo
        ("docs/" ^ name ^ ".md")
        ("# " ^ name ^ "\n\nNew line.\n\n## S\n\n@cites old-" ^ name
       ^ " v1\n@revs x\n"))
    [ "assumed"; "skipped" ];
  Alcotest.(check (list string))
    "the findings that the changes add"
    [
      "docs/assumed.md:3:1: unplanned-change no step of an open plan, no rule, \
       and no exempt path covers docs/assumed.md";
      "docs/assumed.md:7:1: dangling no declaration has the slug old-assumed";
      "docs/skipped.md:3:1: unplanned-change no step of an open plan, no rule, \
       and no exempt path covers docs/skipped.md";
      "docs/skipped.md:7:1: dangling no declaration has the slug old-skipped";
    ]
    (diff_lines ~base:"HEAD" repo)

let tests =
  [
    case "a diff against the merge base reports what the branch adds"
      a_diff_against_the_merge_base_reports_what_the_branch_adds;
    case "a diff compares each file as git stores it"
      a_diff_compares_each_file_as_git_stores_it;
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
    case "a record holds every field of a finding"
      a_record_holds_every_field_of_a_finding;
    case "a record leaves out what a finding does not have"
      a_record_leaves_out_what_a_finding_does_not_have;
    a_record_is_canonical_and_names_a_gate_only_with_a_tier;
    case "a record holds the mark and the related places"
      a_record_holds_the_mark_and_the_related_places;
    a_record_writes_the_mark_and_the_related_places_it_has;
    case "a check reads the repository and reports at its gate"
      a_check_reads_the_repository_and_reports_at_its_gate;
  ]
