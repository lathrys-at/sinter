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

let a_check_reports_a_class_only_where_it_has_a_tier () =
  Alcotest.(check (list bool))
    "unmarked-step with no gate, and at turn, review, and merged"
    [ true; false; true; false ]
    (List.map
       (fun gate -> Check.reports plain gate Finding_class.Unmarked_step)
       [
         None;
         Some Finding_class.Turn;
         Some Finding_class.Review;
         Some Finding_class.Merged;
       ]);
  Alcotest.(check (list bool))
    "renamed-step at review and at merged" [ true; false ]
    (List.map
       (fun gate -> Check.reports plain (Some gate) Finding_class.Renamed_step)
       Finding_class.[ Review; Merged ]);
  Alcotest.(check (list bool))
    "a class that is off, that warns, and that blocks at turn"
    [ false; true; true ]
    (List.map
       (fun finding_class ->
         Check.reports plain (Some Finding_class.Turn) finding_class)
       Finding_class.[ Unmeasured; Typo_tag; Dangling ])

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
      finding Finding_class.Unmeasured edge;
      finding Finding_class.Dangling edge;
      finding Finding_class.Unverified_promise edge;
      finding Finding_class.Parse_error error_node;
    ]
  in
  let tiers = Alcotest.(list (pair string (option (pair string string)))) in
  Alcotest.check tiers
    "the entries at turn, where untraced takes no tier and unmeasured is off"
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
      ("unmeasured", Some ("merged", "warn"));
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

let entry ?tier ?(path = "a.md") ?fix () =
  {
    Check.finding =
      Finding.make Finding_class.Untraced
        (Finding.Line { path; line = 1 })
        ~place:(place ~path ()) ?fix ();
    tier = Option.map (fun tier -> (Finding_class.Review, tier)) tier;
  }

let the_summary_counts_findings_files_tiers_and_fixes () =
  let fix = Edits.word_fix "f" in
  Alcotest.(check (list string))
    "the summaries"
    [
      "no findings in 0 files";
      "no findings in 1 file";
      "no findings in 7 files";
      "1 finding in 1 file";
      "1 finding in 1 file: 1 warn; 1 has a fix";
      "3 findings in 2 files: 2 block, 1 warn; 2 have a fix";
      "2 findings in 2 files: 2 block";
      "2 findings in 1 file; 2 have a fix";
    ]
    [
      Check.summary ~documents:0 [];
      Check.summary ~documents:1 [];
      Check.summary ~documents:7 [];
      Check.summary ~documents:3 [ entry () ];
      Check.summary ~documents:3 [ entry ~tier:Finding_class.Warn ~fix () ];
      Check.summary ~documents:3
        [
          entry ~tier:Finding_class.Block ~fix ();
          entry ~tier:Finding_class.Warn ();
          entry ~tier:Finding_class.Block ~path:"b.md" ~fix ();
        ];
      Check.summary ~documents:3
        [
          entry ~tier:Finding_class.Block ();
          entry ~tier:Finding_class.Block ~path:"b.md" ();
        ];
      Check.summary ~documents:3 [ entry ~fix (); entry ~fix () ];
    ]

let entries_gen =
  Gen.(
    bind
      (option (oneof_list Finding_class.gates))
      (fun gate ->
        list_size (int_range 1 8)
          (map2
             (fun finding tier ->
               {
                 Check.finding;
                 tier = Option.map (fun gate -> (gate, tier)) gate;
               })
             finding_gen
             (oneof_list [ Finding_class.Warn; Finding_class.Block ]))))

let number_before text word =
  let words = String.split_on_char ' ' text in
  let rec find = function
    | number :: next :: rest ->
        if
          String.equal next word
          || String.equal next (word ^ ",")
          || String.equal next (word ^ ";")
          || String.equal next (word ^ ":")
        then int_of_string_opt number
        else find (next :: rest)
    | _ -> None
  in
  find words

let the_summary_counts_equal_the_entries =
  property "the counts of the summary equal the entries" entries_gen
    (fun entries ->
      String.concat "; "
        (List.map (fun (e : Check.entry) -> print_finding e.finding) entries))
    (fun entries ->
      let text = Check.summary ~documents:9 entries in
      let count word = Option.value (number_before text word) ~default:0 in
      let total = List.length entries in
      let files =
        List.length
          (List.sort_uniq String.compare
             (List.filter_map
                (fun (entry : Check.entry) ->
                  Option.map
                    (fun ({ path; _ } : Finding.place) -> path)
                    entry.finding.place)
                entries))
      in
      let fixes =
        List.length
          (List.filter
             (fun (entry : Check.entry) -> Option.is_some entry.finding.fix)
             entries)
      in
      let gated =
        List.exists
          (fun (entry : Check.entry) -> Option.is_some entry.tier)
          entries
      in
      count (if total = 1 then "finding" else "findings") = total
      && count (if files = 1 then "file" else "files") = files
      && count "has" + count "have" = fixes
      && (if gated then count "block" + count "warn" = total
          else count "block" + count "warn" = 0)
      && List.for_all
           (fun (tier, word) ->
             count word
             = List.length
                 (List.filter
                    (fun (entry : Check.entry) ->
                      match entry.tier with
                      | Some (_, t) -> t = tier
                      | None -> false)
                    entries))
           [ (Finding_class.Block, "block"); (Finding_class.Warn, "warn") ])

let fold_entry_gen =
  Gen.(
    map
      (fun (finding_class, path, line, tier) ->
        {
          Check.finding =
            Finding.make finding_class
              (Finding.Line { path; line })
              ~place:(place ~path ~line ()) ();
          tier;
        })
      (quad
         (oneof_list
            Finding_class.
              [ Untraced; Unmet_promise; Awaiting_approval; Dangling ])
         (oneof_list [ "a.md"; "b.md" ])
         (int_range 1 9)
         (oneof_list
            [
              None;
              Some (Finding_class.Review, Finding_class.Warn);
              Some (Finding_class.Review, Finding_class.Block);
            ])))

let fold_entries_gen =
  Gen.map
    (fun entries ->
      List.sort
        (fun (a : Check.entry) (b : Check.entry) ->
          Finding.compare a.finding b.finding)
        entries)
    (Gen.list_size (Gen.int_range 0 12) fold_entry_gen)

let print_entries entries =
  String.concat "; "
    (List.map
       (fun (entry : Check.entry) ->
         print_finding entry.finding
         ^ Option.fold ~none:""
             ~some:(fun (_, tier) -> " " ^ Finding_class.tier_name tier)
             entry.tier)
       entries)

let key (entry : Check.entry) =
  ( entry.finding.finding_class,
    Option.map (fun ({ path; _ } : Finding.place) -> path) entry.finding.place
  )

let foldable (entry : Check.entry) =
  List.mem entry.finding.finding_class
    Finding_class.[ Untraced; Unmet_promise; Awaiting_approval ]
  && match entry.tier with Some (_, Finding_class.Block) -> false | _ -> true

let folding_keeps_every_entry =
  property "the folded counts and the single entries make up the entries"
    fold_entries_gen print_entries (fun entries ->
      let items = Check.fold ~strict:false ~verbose:false entries in
      let group entry =
        List.filter
          (fun other -> foldable other && key other = key entry)
          entries
      in
      List.fold_left
        (fun total -> function
          | Check.Single _ -> total + 1
          | Check.Folded { count; _ } -> total + count)
        0 items
      = List.length entries
      && List.for_all
           (function
             | Check.Single entry ->
                 not (foldable entry && List.length (group entry) >= 2)
             | Check.Folded { first; count } ->
                 foldable first && count >= 2
                 && count = List.length (group first)
                 && List.hd (group first) == first)
           items)

let verbose_and_strict_fold_nothing =
  property "-v and --strict fold nothing" fold_entries_gen print_entries
    (fun entries ->
      let single = List.map (fun entry -> Check.Single entry) entries in
      Check.fold ~strict:false ~verbose:true entries = single
      && Check.fold ~strict:true ~verbose:false entries = single)

let a_group_folds_only_when_it_may () =
  let at ?tier finding_class path line =
    {
      Check.finding =
        Finding.make finding_class
          (Finding.Line { path; line })
          ~place:(place ~path ~line ()) ();
      tier = Option.map (fun tier -> (Finding_class.Review, tier)) tier;
    }
  in
  let shape items =
    List.map
      (function
        | Check.Single _ -> "single"
        | Check.Folded { count; _ } -> Printf.sprintf "folded %d" count)
      items
  in
  Alcotest.(check (list (list string)))
    "two that fold, a group of 1, a class that blocks, a class that does not \
     fold, and two files"
    [
      [ "folded 2" ];
      [ "single" ];
      [ "single"; "single" ];
      [ "single"; "single" ];
      [ "single"; "single" ];
    ]
    (List.map
       (fun entries -> shape (Check.fold ~strict:false ~verbose:false entries))
       [
         [
           at Finding_class.Untraced "a.md" 1;
           at Finding_class.Untraced "a.md" 2;
         ];
         [ at Finding_class.Untraced "a.md" 1 ];
         [
           at ~tier:Finding_class.Block Finding_class.Untraced "a.md" 1;
           at ~tier:Finding_class.Block Finding_class.Untraced "a.md" 2;
         ];
         [
           at Finding_class.Dangling "a.md" 1;
           at Finding_class.Dangling "a.md" 2;
         ];
         [
           at Finding_class.Untraced "a.md" 1;
           at Finding_class.Untraced "b.md" 2;
         ];
       ])

let the_fold_note_counts_findings_and_lines () =
  let at path line =
    {
      Check.finding =
        Finding.make Finding_class.Untraced
          (Finding.Line { path; line })
          ~place:(place ~path ~line ()) ();
      tier = None;
    }
  in
  Alcotest.(check (list (option string)))
    "no fold, one folded line, and two"
    [
      None;
      Some "2 findings are folded into 1 line; use -v to list each one";
      Some "5 findings are folded into 2 lines; use -v to list each one";
    ]
    [
      Check.fold_note [ Check.Single (at "a.md" 1) ];
      Check.fold_note
        [
          Check.Folded { first = at "a.md" 1; count = 2 };
          Check.Single (at "c.md" 1);
        ];
      Check.fold_note
        [
          Check.Folded { first = at "a.md" 1; count = 2 };
          Check.Folded { first = at "b.md" 1; count = 3 };
        ];
    ]

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
        ~verbose:true ~quiet:false ~tool:"v1" ()
    with
    | Ok report -> report
    | Error error ->
        Alcotest.failf "the check fails: %s"
          (String.concat "; "
             (List.map
                (fun { Error_text.fault; help; _ } -> fault ^ "; " ^ help)
                (Scan.explain error)))
  in
  let text = run Check.Brief None in
  Alcotest.(check (list string))
    "the messages of the text"
    [
      (if line_feed then "3 findings in 3 files" else "2 findings in 2 files");
      "note: base " ^ String.sub head 0 7 ^ ", the merge base of HEAD and main";
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
    && Check.messages json = [])

let case name f = Alcotest.test_case name `Quick f

let the_options_choose_the_lines_of_standard_error () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml" packs;
  Git_fixture.write repo "docs/a.md" "# A\n\n@cites x\n";
  ignore (Git_fixture.git repo [ "add"; "-A" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "-m"; "c" ]);
  let head = String.trim (Git_fixture.git repo [ "rev-parse"; "HEAD" ]) in
  let messages form verbose quiet =
    match
      Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
        ~manifest:None ~base:(Some "HEAD") ~mode:Mode.Tree ~gate:None
        ~strict:false ~form ~verbose ~quiet ~tool:"v1" ()
    with
    | Ok report -> Check.messages report
    | Error error ->
        Alcotest.failf "the check fails: %s"
          (String.concat "; "
             (List.map
                (fun { Error_text.fault; help; _ } -> fault ^ "; " ^ help)
                (Scan.explain error)))
  in
  let note = "note: base " ^ String.sub head 0 7 ^ ", from --base HEAD" in
  Alcotest.(check (list (list string)))
    "full, brief with -v, full with -q, full with -v and -q, and JSON with -v"
    [ [ "1 finding in 1 file" ]; [ "1 finding in 1 file"; note ]; []; []; [] ]
    [
      messages Check.Full false false;
      messages Check.Brief true false;
      messages Check.Full false true;
      messages Check.Full true true;
      messages Check.Json true false;
    ]

let folding_leaves_the_json_as_it_is () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml" packs;
  Git_fixture.write repo "docs/a.md" "# A\n\n@req x\n\n## B\n\n@req y\n";
  ignore (Git_fixture.git repo [ "add"; "-A" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "-m"; "c" ]);
  let run form verbose =
    match
      Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
        ~manifest:None ~base:(Some "HEAD") ~mode:Mode.Tree ~gate:None
        ~strict:false ~form ~verbose ~quiet:false ~tool:"v1" ()
    with
    | Ok report -> report
    | Error _ -> Alcotest.fail "the check fails"
  in
  let brief = run Check.Brief false in
  Alcotest.(check (list string))
    "the folded brief form and its messages"
    [
      "docs/a.md:3:1: untraced 2 findings in this file";
      "2 findings in 1 file";
      "note: 2 findings are folded into 1 line; use -v to list each one";
    ]
    (written brief @ Check.messages brief);
  Alcotest.(check (list string))
    "the JSON with and without -v"
    (written (run Check.Json true))
    (written (run Check.Json false));
  Alcotest.(check int)
    "the records of the JSON" 3
    (List.length (written (run Check.Json false)))

let notices_write_the_warning_and_the_note_in_their_styles () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml" packs;
  Git_fixture.write repo ".plans/p.md" "# P\n\n@plan p\n";
  ignore (Git_fixture.git repo [ "add"; "-A" ]);
  ignore (Git_fixture.git repo [ "commit"; "-q"; "-m"; "c" ]);
  match
    Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
      ~manifest:None ~base:(Some "HEAD") ~mode:Mode.Tree ~gate:None
      ~strict:false ~form:Check.Full ~verbose:true ~quiet:false ~tool:"v1" ()
  with
  | Error _ -> Alcotest.fail "the check fails"
  | Ok report ->
      let written renderer =
        let buffer = Buffer.create 128 in
        let ppf = Format.formatter_of_buffer buffer in
        Style.prepare ppf renderer;
        Check.notices ppf report;
        Buffer.contents buffer
      in
      let head = String.trim (Git_fixture.git repo [ "rev-parse"; "HEAD" ]) in
      let base = "base " ^ String.sub head 0 7 ^ ", from --base HEAD\n" in
      let summary = "1 finding in 1 file; 1 has a fix\n" in
      let ledger = " no ledger found, so every plan counts as open\n" in
      Alcotest.(check (pair string string))
        "the lines with no style and with styles"
        ( summary ^ "warning:" ^ ledger ^ "note: " ^ base,
          summary ^ "\x1b[1m\x1b[33mwarning:\x1b[0;1m\x1b[0m" ^ ledger
          ^ "\x1b[1mnote:\x1b[0m " ^ base )
        (written `None, written `Ansi_tty)

let diff_lines ?base repo =
  match
    Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
      ~manifest:None ~base ~mode:Mode.Diff ~gate:None ~strict:false
      ~form:Check.Brief ~verbose:false ~quiet:false ~tool:"v1" ()
  with
  | Ok report -> written report
  | Error error ->
      Alcotest.failf "the check fails: %s"
        (String.concat "; "
           (List.map
              (fun { Error_text.fault; help; _ } -> fault ^ "; " ^ help)
              (Scan.explain error)))

let contains_text part text =
  let length = String.length part in
  let rec from index =
    index + length <= String.length text
    && (String.sub text index length = part || from (index + 1))
  in
  from 0

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

let a_mark_that_the_branch_adds_needs_a_change_in_its_scope () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml" packs;
  let plan marks =
    "# P\n\n@plan p@0a1b2c\n@scope lib/**\n\n## A\n\n@scope lib/a/**\n" ^ marks
    ^ "Do a.\n\n## B\n\n@scope lib/b/**\n" ^ marks ^ "Do b.\n"
  in
  Git_fixture.write repo ".plans/p.md" (plan "");
  Git_fixture.write repo "lib/a/x.md" "# X\n";
  Git_fixture.write repo "lib/b/y.md" "# Y\n";
  commit repo "main";
  ignore (Git_fixture.git repo [ "checkout"; "-q"; "-b"; "work" ]);
  Git_fixture.write repo ".plans/p.md" (plan "@delivered 000000\n");
  Git_fixture.write repo "lib/a/x.md" "# X\n\nMore.\n";
  Git_fixture.make_executable repo "lib/b/y.md";
  commit repo "work";
  Alcotest.(check (list string))
    "the mark of the step whose scope the branch does not change"
    [
      ".plans/p.md:15:1: mark-without-change the diff adds the mark of \
       step:p@0a1b2c/b, and it changes no file in the scope of the step";
    ]
    (List.filter
       (fun line -> contains_text "mark-without-change" line)
       (diff_lines repo))

let tree_lines repo =
  match
    Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
      ~manifest:None ~base:None ~mode:Mode.Tree ~gate:None ~strict:false
      ~form:Check.Brief ~verbose:false ~quiet:false ~tool:"v1" ()
  with
  | Ok report -> written report
  | Error _ -> Alcotest.fail "the check fails"

let unmarked_step_reads_the_promises_that_the_base_meets_in_both_modes () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml" packs;
  let plan text =
    "# P\n\n@plan p@0a1b2c\n@scope docs/**\n\n## Do it\n\n@req a\n" ^ text
  in
  Git_fixture.write repo ".plans/p.md" (plan "Text.\n");
  Git_fixture.write repo "docs/a.md" "# A\n\n@req a\n";
  commit repo "main";
  ignore (Git_fixture.git repo [ "checkout"; "-q"; "-b"; "work" ]);
  Git_fixture.write repo ".plans/p.md" (plan "Other text.\n");
  commit repo "work";
  let unmarked lines =
    List.filter (fun line -> contains_text "unmarked-step" line) lines
  in
  Alcotest.(check (pair (list string) (list string)))
    "no unmarked-step in tree mode and in diff mode" ([], [])
    (unmarked (tree_lines repo), unmarked (diff_lines repo))

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

let raw report =
  let buffer = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buffer in
  Style.prepare ppf `None;
  Check.write ppf report;
  Buffer.contents buffer

let porcelain_check ?(mode = Mode.Tree) ?gate ?(strict = false)
    ?(verbose = false) ?(quiet = false) ?(nul = false) headers repo =
  Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
    ~manifest:None ~base:(Some "HEAD") ~mode ~gate ~strict
    ~form:(Check.Porcelain { nul; headers })
    ~verbose ~quiet ~tool:"v9.9.9-dev+abc" ()

let porcelain_report ?mode ?gate ?strict ?verbose ?quiet ?nul headers repo =
  match
    porcelain_check ?mode ?gate ?strict ?verbose ?quiet ?nul headers repo
  with
  | Ok report -> report
  | Error error ->
      Alcotest.failf "the check fails: %s"
        (String.concat "; "
           (List.map
              (fun { Error_text.fault; help; _ } -> fault ^ "; " ^ help)
              (Scan.explain error)))

let porcelain_repo () =
  let repo = Git_fixture.init () in
  Git_fixture.write repo "sinter.toml" packs;
  Git_fixture.write repo ".plans/p.md" "# P\n\n@plan p\n";
  Git_fixture.write repo "docs/a.md"
    "# A\n\n@cites x\n\n## R\n\n@req r\n\n## S\n\n@req s\n";
  Git_fixture.write repo "docs/a\tb.md" "# T\n\n@cites \"y\n";
  commit repo "c";
  repo

let header_lines report =
  List.filter (fun line -> String.starts_with ~prefix:"#" line) (written report)

let each_header_prints_alone_after_the_version () =
  let repo = porcelain_repo () in
  let head = String.trim (Git_fixture.git repo [ "rev-parse"; "HEAD" ]) in
  Alcotest.(check (list (list string)))
    "base, ledger, gate, mode, and tool, each alone"
    [
      [ "# porcelain 1"; "# base " ^ head ];
      [ "# porcelain 1"; "# ledger none" ];
      [ "# porcelain 1"; "# gate none" ];
      [ "# porcelain 1"; "# mode tree" ];
      [ "# porcelain 1"; "# tool v9.9.9-dev+abc" ];
    ]
    (List.map
       (fun header ->
         header_lines (porcelain_report (Porcelain.Headers [ header ]) repo))
       Porcelain.headers)

let the_headers_print_once_each_in_their_order () =
  let repo = porcelain_repo () in
  let head = String.trim (Git_fixture.git repo [ "rev-parse"; "HEAD" ]) in
  ignore (Git_fixture.git repo [ "update-ref"; "refs/sinter/ledger"; "HEAD" ]);
  Alcotest.(check (list string))
    "all five, in a mixed order with a repeat, in diff mode at a gate"
    [
      "# porcelain 1";
      "# base " ^ head;
      "# ledger " ^ head;
      "# gate merged";
      "# mode diff";
      "# tool v9.9.9-dev+abc";
    ]
    (header_lines
       (porcelain_report ~mode:Mode.Diff ~gate:Finding_class.Merged
          (Porcelain.Headers
             [
               Porcelain.Tool;
               Porcelain.Mode;
               Porcelain.Gate;
               Porcelain.Tool;
               Porcelain.Ledger;
               Porcelain.Base;
             ])
          repo));
  Alcotest.(check (list string))
    "no header, and the version alone" [ "# porcelain 1" ]
    (header_lines (porcelain_report Porcelain.No_headers repo)
    @ header_lines (porcelain_report (Porcelain.Headers []) repo))

let a_failed_lookup_of_the_ledger_is_an_error () =
  let repo = porcelain_repo () in
  let tree =
    String.trim (Git_fixture.git repo [ "rev-parse"; "HEAD^{tree}" ])
  in
  let commit =
    String.trim (Git_fixture.git repo [ "commit-tree"; "-m"; "l"; tree ])
  in
  ignore (Git_fixture.git repo [ "update-ref"; "refs/sinter/ledger"; commit ]);
  let objects =
    Filename.concat (Git_fixture.root repo)
      (Filename.concat ".git/objects" (String.sub commit 0 2))
  in
  let file = Filename.concat objects (String.sub commit 2 38) in
  Unix.chmod file 0o644;
  Out_channel.with_open_bin file (fun channel ->
      Out_channel.output_string channel "xx");
  Alcotest.(check (pair bool bool))
    "the header ledger fails, and a run that does not name it does not"
    (true, true)
    ( (match porcelain_check (Porcelain.Headers [ Porcelain.Ledger ]) repo with
      | Error (Scan.Repository _) -> true
      | Ok _ | Error _ -> false),
      match
        porcelain_check
          (Porcelain.Headers [ Porcelain.Base; Porcelain.Gate ])
          repo
      with
      | Ok _ -> true
      | Error _ -> false )

let a_tool_header_that_needs_quotes_is_refused () =
  let repo = porcelain_repo () in
  let check tool headers =
    Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
      ~manifest:None ~base:(Some "HEAD") ~mode:Mode.Tree ~gate:None
      ~strict:false
      ~form:(Check.Porcelain { nul = false; headers })
      ~verbose:false ~quiet:false ~tool ()
  in
  List.iter
    (fun tool ->
      Alcotest.check_raises tool
        (Invalid_argument
           "Porcelain.add_header: a name or a value that needs quotes")
        (fun () -> ignore (check tool (Porcelain.Headers [ Porcelain.Tool ]))))
    [ ""; "v1 x"; "v1\n" ];
  Alcotest.(check bool)
    "an empty tool and no header tool" true
    (Result.is_ok (check "" (Porcelain.Headers [ Porcelain.Base ])))

let the_porcelain_form_prints_only_warnings_on_standard_error () =
  let repo = porcelain_repo () in
  List.iter
    (fun (verbose, quiet, strict) ->
      let report =
        porcelain_report ~verbose ~quiet ~strict (Porcelain.Headers []) repo
      in
      Alcotest.(check (pair (list string) int))
        (Printf.sprintf "-v %b, -q %b, --strict %b" verbose quiet strict)
        ( [ "warning: no ledger found, so every plan counts as open" ],
          if strict then 1 else 0 )
        (Check.messages report, Check.code report);
      Alcotest.(check int)
        "the version and every finding, with none folded" 6
        (List.length (written report)))
    [
      (false, false, false);
      (true, false, false);
      (false, true, false);
      (true, true, true);
    ]

let run_records repo =
  match
    Check.run ~env:(Git_fixture.env repo) ~dir:(Git_fixture.root repo)
      ~manifest:None ~base:(Some "HEAD") ~mode:Mode.Tree
      ~gate:(Some Finding_class.Review) ~strict:false ~form:Check.Json
      ~verbose:false ~quiet:false ~tool:"v1" ()
  with
  | Ok report -> written report
  | Error _ -> Alcotest.fail "the check fails"

let each_porcelain_line_holds_the_values_of_its_record () =
  let repo = porcelain_repo () in
  let json = run_records repo in
  let lines =
    written
      (porcelain_report ~gate:Finding_class.Review (Porcelain.Headers []) repo)
  in
  let field record name =
    match List.assoc_opt name record with
    | Some (`String text) -> text
    | Some (`Int number) -> Int.to_string number
    | Some _ -> Alcotest.failf "the field %s is not a string or an int" name
    | None -> ""
  in
  Alcotest.(check (list (list string)))
    "the values of each line and of each record, in order"
    (List.map
       (fun record ->
         let record =
           match Yojson.Safe.from_string record with
           | `Assoc fields -> fields
           | _ -> Alcotest.fail "a record that is not an object"
         in
         List.map (field record)
           [
             "tier";
             "class";
             "path";
             "line";
             "col";
             "eline";
             "ecol";
             "subject";
             "detail";
           ])
       (List.tl json))
    (List.map
       (fun line ->
         List.map
           (fun item ->
             match Test_porcelain.unquote item with
             | Ok value -> value
             | Error reason -> Alcotest.failf "%s in %S" reason item)
           (String.split_on_char '\t' line))
       (List.tl lines))

let a_porcelain_line_and_a_record_hold_the_same_values =
  property "a porcelain line and a record of one finding hold the same values"
    Gen.(pair Generators.porcelain_finding gate_gen)
    (fun (value, _) -> Generators.print_porcelain_finding value)
    (fun ((finding, tier), gate) ->
      let entry =
        { Check.finding; tier = Option.map (fun tier -> (gate, tier)) tier }
      in
      let record = Check.record ~mode:Mode.Tree entry in
      let field name =
        match List.assoc_opt name record with
        | Some (Jsonl.Scalar (Jsonl.String text)) -> text
        | Some (Jsonl.Scalar (Jsonl.Int number)) -> Int.to_string number
        | Some _ -> "?"
        | None -> if name = "tier" then "none" else ""
      in
      let buffer = Buffer.create 64 in
      Porcelain.add_finding buffer ~nul:false ~tier finding;
      let line = Buffer.contents buffer in
      List.map Result.ok
        (List.map field
           [
             "tier";
             "class";
             "path";
             "line";
             "col";
             "eline";
             "ecol";
             "subject";
             "detail";
           ])
      = List.map Test_porcelain.unquote
          (String.split_on_char '\t'
             (String.sub line 0 (String.length line - 1))))

let the_porcelain_form_with_nul_ends_each_field_with_nul () =
  let repo = porcelain_repo () in
  let text =
    raw (porcelain_report ~nul:true (Porcelain.Headers [ Porcelain.Mode ]) repo)
  in
  Alcotest.(check (pair (list string) int))
    "the headers, and the number of items of the findings"
    ([ "# porcelain 1"; "# mode tree" ], 5 * 9)
    (let items = String.split_on_char '\000' text in
     let headers, fields =
       List.partition (fun item -> String.starts_with ~prefix:"# " item) items
     in
     (headers, List.length fields - 1))

let tests =
  [
    case "each header prints alone after the version"
      each_header_prints_alone_after_the_version;
    case "the headers print once each in their order"
      the_headers_print_once_each_in_their_order;
    case "a failed lookup of the ledger is an error"
      a_failed_lookup_of_the_ledger_is_an_error;
    case "a tool header that needs quotes is refused"
      a_tool_header_that_needs_quotes_is_refused;
    case "the porcelain form prints only warnings on standard error"
      the_porcelain_form_prints_only_warnings_on_standard_error;
    case "each porcelain line holds the values of its record"
      each_porcelain_line_holds_the_values_of_its_record;
    case "the porcelain form with -z ends each field with NUL"
      the_porcelain_form_with_nul_ends_each_field_with_nul;
    a_porcelain_line_and_a_record_hold_the_same_values;
    case "a mark that the branch adds needs a change in its scope"
      a_mark_that_the_branch_adds_needs_a_change_in_its_scope;
    case "unmarked-step reads the promises that the base meets in both modes"
      unmarked_step_reads_the_promises_that_the_base_meets_in_both_modes;
    case "a check reports a class only where it has a tier"
      a_check_reports_a_class_only_where_it_has_a_tier;
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
    case "the summary counts findings, files, tiers, and fixes"
      the_summary_counts_findings_files_tiers_and_fixes;
    the_summary_counts_equal_the_entries;
    folding_keeps_every_entry;
    verbose_and_strict_fold_nothing;
    case "a group folds only when it may" a_group_folds_only_when_it_may;
    case "the fold note counts findings and lines"
      the_fold_note_counts_findings_and_lines;
    case "a record holds every field of a finding"
      a_record_holds_every_field_of_a_finding;
    case "a record leaves out what a finding does not have"
      a_record_leaves_out_what_a_finding_does_not_have;
    a_record_is_canonical_and_names_a_gate_only_with_a_tier;
    case "a record holds the mark and the related places"
      a_record_holds_the_mark_and_the_related_places;
    a_record_writes_the_mark_and_the_related_places_it_has;
    case "the options choose the lines of standard error"
      the_options_choose_the_lines_of_standard_error;
    case "folding leaves the JSON as it is" folding_leaves_the_json_as_it_is;
    case "notices write the warning and the note in their styles"
      notices_write_the_warning_and_the_note_in_their_styles;
    case "a check reads the repository and reports at its gate"
      a_check_reads_the_repository_and_reports_at_its_gate;
  ]
