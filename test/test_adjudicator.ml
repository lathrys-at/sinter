(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let base_commit = "0123456789abcdef0123456789abcdef01234567"

module Gen = QCheck2.Gen

let property ?(count = 200) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let reader =
  lazy
    (match Markdown.create (Sinter_bridge.create ()) with
    | Ok reader -> reader
    | Error _ -> failwith "the reader does not start")

let document text =
  match Markdown.read (Lazy.force reader) text with
  | Ok document -> document
  | Error _ -> Alcotest.fail "the text gives no document"

let manifest =
  match
    Manifest.of_string
      "[scan]\n\
       packs.markdown.files = [\"**/*.md\"]\n\
       namespaces.gh = \"[1-9][0-9]*\"\n\
       [paths]\n\
       historical = [\"old/**\"]\n"
  with
  | Ok manifest -> manifest
  | Error _ -> failwith "the manifest has errors"

let facts files =
  Facts.make manifest
    (List.map (fun (path, text) -> (path, document text)) files)

let show (finding : Finding.t) =
  String.concat " | "
    ([
       (match finding.place with
       | Some { path; span } -> Printf.sprintf "%s:%d" path span.start.line
       | None -> "-");
       Finding.id finding;
     ]
    @ Option.to_list finding.detail
    @ Option.fold ~none:[]
        ~some:(fun fix -> [ "fix: " ^ Finding.escape (Fix.text fix) ])
        finding.fix)

let compared ?(findings = []) base tree =
  List.map show (Adjudicator.classes ~base:(facts base) (facts tree) findings)

let strings = Alcotest.(list string)

let a_tombstone_names_each_fact_that_the_working_tree_lacks () =
  let base =
    facts
      [
        ( "docs/a.md",
          "# A\n\n\
           @req gone v3 Text.\n\
           @cites gh/7\n\
           @cites kept v1\n\n\
           ## Site\n\n\
           @cites kept v1\n\
           @ack stale 01ba4719\n" );
        ("docs/b.md", "# B\n\n@req kept v1\n");
        ("docs/c.md", "# C\n\n@cites kept v1\n@ack stale 01ba4719\n");
        ( ".plans/p.md",
          "# P\n\n@plan p\n@scope docs/**\n\n## Step\n\n@req promised\n" );
      ]
  in
  let tree = facts [ ("docs/b.md", "# B\n\n@req kept v1\n") ] in
  let tombstones = Adjudicator.tombstones ~base tree in
  Alcotest.check strings "the tombstones"
    [
      "req req:gone docs/a.md:3 gone v3";
      "cites cites:req:gone->gh/7 docs/a.md:4";
      "cites cites:req:gone->kept docs/a.md:5";
      "cites cites:site:docs/c.md#c->kept docs/c.md:3";
      "site site:docs/c.md#c docs/c.md:3";
      "ack ack:req:gone:stale docs/a.md:10";
      "ack ack:site:docs/c.md#c:stale docs/c.md:4";
      "plan plan:p .plans/p.md:3";
      "step step:p/step .plans/p.md:6";
      "promise promise:step:p/step:req:promised .plans/p.md:8";
      "external external:gh/7 -";
    ]
    (List.map
       (fun (t : Adjudicator.tombstone) ->
         String.concat " "
           ([
              t.kind;
              t.was;
              (match t.place with
              | Some (path, span) -> Printf.sprintf "%s:%d" path span.start.line
              | None -> "-");
            ]
           @ Option.fold ~none:[]
               ~some:(fun (d : Adjudicator.declared) ->
                 [ Printf.sprintf "%s v%d" d.slug d.rev ])
               t.declared))
       tombstones);
  Alcotest.(check (option string))
    "the extent hash of the declaration"
    (List.find_map
       (fun (d : Facts.declaration) ->
         if String.equal d.slug "gone" then Some d.extent.hash else None)
       (Facts.declarations base))
    (List.find_map
       (fun (t : Adjudicator.tombstone) ->
         Option.map (fun (d : Adjudicator.declared) -> d.xh) t.declared)
       tombstones)

let two_facts_of_one_id_give_one_tombstone () =
  Alcotest.(check int)
    "one tombstone" 1
    (List.length
       (Adjudicator.tombstones
          ~base:
            (facts
               [
                 ("a.md", "# A\n\n@req x v1\n"); ("b.md", "# B\n\n@req x v2\n");
               ])
          (facts [ ("a.md", "# A\n") ])))

let a_tree_like_its_base_has_no_tombstone () =
  let files = [ ("a.md", "# A\n\n@req x v1\n@cites gh/1\n") ] in
  Alcotest.(check int)
    "no tombstone" 0
    (List.length (Adjudicator.tombstones ~base:(facts files) (facts files)))

let unbumped_needs_a_higher_revision_for_a_changed_extent () =
  Alcotest.check strings "the findings"
    [
      "docs/a.md:3 | finding:unbumped:req:edited | the extent of req:edited \
       differs from the base, and its revision is not above v2 | fix: @req \
       edited v3";
      "docs/a.md:10 | finding:unbumped:design:lowered | the extent of \
       design:lowered differs from the base, and its revision is not above v4 \
       | fix: @design lowered v5";
    ]
    (compared
       [
         ( "docs/a.md",
           "# A\n\n\
            @req edited v2 Old.\n\n\
            ## B\n\n\
            @req bumped v1 Old.\n\n\
            ## C\n\n\
            @design lowered v4 Old.\n\n\
            ## D\n\n\
            @req same v1 Same.\n" );
       ]
       [
         ( "docs/a.md",
           "# A\n\n\
            @req edited v2 New.\n\n\
            ## B\n\n\
            @req bumped v2 New.\n\n\
            ## C\n\
            @design lowered v3 New.\n\n\
            ## D\n\n\
            @req same v1 Same.\n\n\
            ## E\n\n\
            @req new v1\n" );
       ])

let unbumped_counts_a_change_of_kind () =
  Alcotest.check strings "the findings"
    [
      "docs/a.md:3 | finding:unbumped:design:moved | the base declares \
       req:moved v1, so design:moved needs a higher revision for its change of \
       kind | fix: @design moved v2";
    ]
    (compared
       [
         ( "docs/a.md",
           "# A\n\n@req moved v1 Text.\n\n## B\n\n@req raised v1 T.\n" );
       ]
       [
         ( "docs/a.md",
           "# A\n\n@design moved v1 Text.\n\n## B\n\n@decision raised v2 T.\n"
         );
       ])

let unbumped_ignores_a_renumbered_heading_and_a_moved_file () =
  Alcotest.check strings "no finding" []
    (compared
       [
         ("docs/a.md", "# 1. A\n\n@req a v1 Text.\n\n## 1.1 Inner\n\nProse.\n");
       ]
       [
         ( "docs/moved.md",
           "Intro.\n\n# 2. A\n\n@req a v1 Text.\n\n## 2.3 Inner\n\nProse.\n" );
       ])

let unbumped_holds_for_a_retired_declaration_and_not_under_a_historical_path ()
    =
  Alcotest.check strings "the findings"
    [
      "docs/a.md:3 | finding:unbumped:req:old | the extent of req:old differs \
       from the base, and its revision is not above v1 | fix: @req old v2";
    ]
    (compared
       [
         ("docs/a.md", "# A\n\n@req old v1\n@deprecated\nText.\n");
         ("old/b.md", "# B\n\n@req log v1 Then.\n");
       ]
       [
         ("docs/a.md", "# A\n\n@req old v1\n@deprecated\nOther text.\n");
         ("old/b.md", "# B\n\n@req log v1 Now.\n");
       ])

let unbumped_reads_every_declaration_of_the_slug_at_the_base () =
  Alcotest.check strings "the findings"
    [
      "docs/c.md:3 | finding:unbumped:req:y | the extent of req:y differs from \
       the base, and its revision is not above v4 | fix: @req y v5";
    ]
    (compared
       [
         ("docs/a.md", "# A\n\n@design x v3 Old.\n\n# Y\n\n@req y v4 Old.\n");
         ("docs/b.md", "# B\n\n@req x v1 Old.\n\n# Y\n\n@req y v2 Old.\n");
       ]
       [
         ("docs/a.md", "# A\n\n@design x v3 Old.\n\n# Y\n\n@req y v4 Old.\n");
         ("docs/b.md", "# B\n\n@req x v2 New.\n");
         ("docs/c.md", "# C\n\n@req y v2 New.\n");
       ])

let the_findings_keep_their_order_with_the_new_ones () =
  let finding path line =
    Finding.make Finding_class.Typo_tag
      (Finding.Line { path; line })
      ~place:
        {
          path;
          span = { start = { line; column = 1 }; stop = { line; column = 3 } };
        }
      ()
  in
  Alcotest.check strings "the order"
    [
      "docs/a.md:1 | finding:typo-tag:line:docs/a.md@L1";
      "docs/a.md:3 | finding:unbumped:req:x | the extent of req:x differs from \
       the base, and its revision is not above v1 | fix: @req x v2";
      "docs/b.md:1 | finding:typo-tag:line:docs/b.md@L1";
    ]
    (compared
       ~findings:[ finding "docs/b.md" 1; finding "docs/a.md" 1 ]
       [ ("docs/a.md", "# A\n\n@req x v1 Old.\n") ]
       [ ("docs/a.md", "# A\n\n@req x v1 New.\n") ])

let with_tree_findings base tree =
  let tree_facts = facts tree in
  List.map show
    (List.filter
       (fun (finding : Finding.t) ->
         List.mem finding.finding_class
           [ Finding_class.Dangling; Finding_class.Renamed ])
       (Adjudicator.classes ~base:(facts base) tree_facts
          (Findings.of_facts tree_facts ~base:base_commit ~not_text:[])))

let renamed_takes_the_place_of_dangling () =
  Alcotest.check strings "the findings"
    [
      "docs/use.md:3 | finding:renamed:cites:site:docs/use.md#use->lockout | \
       the base declares req:lockout, and req:account-lockout has its extent \
       now | fix: @cites account-lockout v2";
      "docs/use.md:4 | finding:renamed:satisfies:site:docs/use.md#use->lockout \
       | the base declares req:lockout, and req:account-lockout has its extent \
       now | fix: @satisfies account-lockout";
    ]
    (with_tree_findings
       [
         ("docs/spec.md", "# Spec\n\n@req lockout v1 Lock it.\n");
         ("docs/use.md", "# Use\n\n@cites lockout v1\n@satisfies lockout\n");
       ]
       [
         ("docs/moved.md", "# Spec\n\n@req account-lockout v2 Lock it.\n");
         ("docs/use.md", "# Use\n\n@cites lockout v1\n@satisfies lockout\n");
       ])

let two_candidates_leave_the_edge_dangling () =
  let dangling =
    [
      "docs/use.md:3 | finding:dangling:cites:site:docs/use.md#use->a | no \
       declaration has the slug a";
    ]
  in
  Alcotest.check strings "two new declarations with the extent hash" dangling
    (with_tree_findings
       [
         ("docs/spec.md", "# Spec\n\n@req a v1 Same.\n");
         ("docs/use.md", "# Use\n\n@cites a v1\n");
       ]
       [
         ("docs/one.md", "# Spec\n\n@req b v1 Same.\n");
         ("docs/two.md", "# Spec\n\n@req c v1 Same.\n");
         ("docs/use.md", "# Use\n\n@cites a v1\n");
       ]);
  Alcotest.check strings "two tombstones with the extent hash" dangling
    (with_tree_findings
       [
         ("docs/spec.md", "# Spec\n\n@req a v1 Same.\n");
         ("docs/other.md", "# Spec\n\n@req z v1 Same.\n");
         ("docs/use.md", "# Use\n\n@cites a v1\n");
       ]
       [
         ("docs/one.md", "# Spec\n\n@req b v1 Same.\n");
         ("docs/use.md", "# Use\n\n@cites a v1\n");
       ]);
  Alcotest.check strings "a change of kind" dangling
    (with_tree_findings
       [
         ("docs/spec.md", "# Spec\n\n@req a v1 Same.\n");
         ("docs/use.md", "# Use\n\n@cites a v1\n");
       ]
       [
         ("docs/one.md", "# Spec\n\n@design b v1 Same.\n");
         ("docs/use.md", "# Use\n\n@cites a v1\n");
       ]);
  Alcotest.check strings "another extent" dangling
    (with_tree_findings
       [
         ("docs/spec.md", "# Spec\n\n@req a v1 Same.\n");
         ("docs/use.md", "# Use\n\n@cites a v1\n");
       ]
       [
         ("docs/one.md", "# Spec\n\n@req b v1 Other.\n");
         ("docs/use.md", "# Use\n\n@cites a v1\n");
       ])

let a_slug_with_two_tombstones_leaves_the_edge_dangling () =
  Alcotest.check strings "two declarations of the slug at the base"
    [
      "docs/use.md:3 | finding:dangling:cites:site:docs/use.md#use->a | no \
       declaration has the slug a";
    ]
    (with_tree_findings
       [
         ("docs/one.md", "# Spec\n\n@req a v1 Same.\n");
         ("docs/two.md", "# Other\n\n@design a v1 Other.\n");
         ("docs/use.md", "# Use\n\n@cites a v1\n");
       ]
       [
         ("docs/one.md", "# Spec\n\n@req b v1 Same.\n");
         ("docs/use.md", "# Use\n\n@cites a v1\n");
       ])

let a_new_promise_of_a_slug_of_the_base_collides () =
  let plan steps = "# P\n\n@plan p\n@scope docs/**\n\n" ^ steps in
  Alcotest.check strings "the findings"
    [
      ".plans/p.md:12 | finding:promise-collision:promise:step:p/new:req:taken \
       | the base already declares design:taken";
    ]
    (compared
       [
         ("docs/a.md", "# A\n\n@design taken v1\n\n## B\n\n@req kept v1\n");
         (".plans/p.md", plan "## Old\n\n@req kept\n");
       ]
       [
         ("docs/a.md", "# A\n\n@design taken v1\n\n## B\n\n@req kept v1\n");
         ( ".plans/p.md",
           plan
             "## Old\n\n\
              @req kept\n\n\
              ## New\n\n\
              @req taken\n\
              @verifies taken\n\
              @req free\n" );
       ])

let collisions ~base:(base_path, base_target) (path, target) =
  let plan target =
    "# P\n\n@plan " ^ target ^ "\n@scope docs/**\n\n## S\n\n@req taken\n"
  in
  let declared = ("docs/a.md", "# A\n\n@req taken v1\n") in
  List.length
    (List.filter
       (fun (finding : Finding.t) ->
         finding.finding_class = Finding_class.Promise_collision)
       (Adjudicator.classes
          ~base:(facts [ declared; (base_path, plan base_target) ])
          (facts [ declared; (path, plan target) ])
          []))

let the_same_plan_across_the_base_holds_its_promises () =
  Alcotest.(check (list int))
    "the counts of promise-collision" [ 0; 0; 0; 1; 1; 1 ]
    [
      collisions ~base:(".plans/p.md", "p") (".plans/p.md", "p@3f2a9c");
      collisions ~base:(".plans/p.md", "p@3f2a9c") (".plans/q.md", "p@3f2a9c");
      collisions ~base:(".plans/p.md", "p") (".plans/q.md", "p");
      collisions ~base:(".plans/p.md", "p") (".plans/q.md", "p@3f2a9c");
      collisions ~base:(".plans/p.md", "p@3f2a9c") (".plans/p.md", "p@012345");
      collisions ~base:(".plans/p.md", "p@3f2a9c") (".plans/p.md", "p");
    ]

let text_gen =
  Gen.(
    let* words =
      list_size (int_range 1 4) (oneof_list [ "req"; "design"; "decision" ])
    in
    let+ texts =
      list_size (pure (List.length words)) (oneof_list [ "A."; "B."; "" ])
    in
    String.concat ""
      (List.mapi
         (fun index (word, text) ->
           Printf.sprintf "# S%d\n\n@%s s%d v%d %s\n\n" index word index
             (1 + (index mod 3))
             text)
         (List.combine words texts)))

let a_tree_like_its_base_has_no_finding =
  property ~name:"a tree like its base adds no finding"
    ~print:(Printf.sprintf "%S") text_gen (fun text ->
      let files = [ ("docs/a.md", text) ] in
      Adjudicator.classes ~base:(facts files) (facts files) [] = [])

let section_gen =
  Gen.(
    let* kind = oneof_list [ "req"; "design" ] in
    let* slug = oneof_list [ "a"; "b"; "c" ] in
    let* rev = int_range 1 3 in
    let* text = oneof_list [ "A."; "B." ] in
    let+ cited = oneof_list [ "a"; "b"; "c"; "d" ] in
    Printf.sprintf "# %s\n\n@%s %s v%d %s\n@cites %s v1\n\n" text kind slug rev
      text cited)

let file_gen =
  Gen.(
    let* sections = list_size (int_range 1 2) section_gen in
    pure (String.concat "" sections))

let plan_gen =
  Gen.(
    map
      (fun (plan, slug) ->
        Printf.sprintf "# P\n\n@plan %s\n@scope docs/**\n\n## S\n\n@req %s\n"
          plan slug)
      (pair
         (oneof_list [ "p"; "p@3f2a9c"; "p@012345" ])
         (oneof_list [ "a"; "b"; "c" ])))

type version =
  | Same of string
  | Changed of string * string
  | Base_only of string
  | Tree_only of string

let version_gen text =
  Gen.(
    oneof
      [
        map (fun t -> Same t) text;
        map2 (fun a b -> Changed (a, b)) text text;
        map (fun t -> Base_only t) text;
        map (fun t -> Tree_only t) text;
      ])

let trees_gen =
  Gen.(
    triple (version_gen file_gen) (version_gen file_gen) (version_gen plan_gen))

let print_version = function
  | Same t -> Printf.sprintf "same %S" t
  | Changed (a, b) -> Printf.sprintf "%S -> %S" a b
  | Base_only t -> Printf.sprintf "base only %S" t
  | Tree_only t -> Printf.sprintf "tree only %S" t

let print_trees (a, b, p) =
  Printf.sprintf "a: %s; b: %s; plan: %s" (print_version a) (print_version b)
    (print_version p)

let a_base_without_the_same_files_gives_the_same_classes =
  property
    ~name:"a base without the files that are the same gives the same classes"
    ~print:print_trees trees_gen (fun (a, b, p) ->
      let files =
        List.map
          (fun (path, version) ->
            match version with
            | Same text ->
                let d = document text in
                (path, Some d, Some d, true)
            | Changed (x, y) ->
                (path, Some (document x), Some (document y), false)
            | Base_only text -> (path, Some (document text), None, false)
            | Tree_only text -> (path, None, Some (document text), false))
          [ ("docs/a.md", a); ("docs/b.md", b); (".plans/p.md", p) ]
      in
      let tree =
        Facts.make manifest
          (List.filter_map
             (fun (path, _, t, _) -> Option.map (fun t -> (path, t)) t)
             files)
      in
      let full =
        Facts.make manifest
          (List.filter_map
             (fun (path, b, _, _) -> Option.map (fun b -> (path, b)) b)
             files)
      and part =
        Facts.make manifest
          (List.filter_map
             (fun (path, b, _, same) ->
               if same then None else Option.map (fun b -> (path, b)) b)
             files)
      in
      let same path =
        List.exists (fun (p, _, _, same) -> same && String.equal p path) files
      in
      let found = Findings.of_facts tree ~base:base_commit ~not_text:[] in
      let tombstone (t : Adjudicator.tombstone) = t.was in
      List.map show (Adjudicator.classes ~base:full tree found)
      = List.map show
          (Adjudicator.classes ~same
             ~whole_base:(lazy full)
             ~base:part tree found)
      && List.map tombstone (Adjudicator.tombstones ~base:full tree)
         = List.map tombstone (Adjudicator.tombstones ~same ~base:part tree))

let renamed_to_names_the_new_declaration_of_the_fix () =
  let base =
    facts
      [
        ("docs/spec.md", "# Spec\n\n@req lockout v1 Lock it.\n");
        ("docs/use.md", "# Use\n\n@cites lockout v1\n");
      ]
  and tree =
    facts
      [
        ("docs/moved.md", "# Spec\n\n@req account-lockout v2 Lock it.\n");
        ("docs/use.md", "# Use\n\n@cites lockout v1\n");
      ]
  in
  let renamed_to = Adjudicator.renamed_to ~base tree in
  Alcotest.(check (list (option string)))
    "the new declaration of each tag target"
    [ Some "req:account-lockout v2"; None; None; None ]
    (List.map
       (fun target ->
         Option.map
           (fun (d : Facts.declaration) ->
             Printf.sprintf "%s v%d" (Facts.declaration_id d) d.rev)
           (renamed_to target))
       [ "lockout"; "account-lockout"; "other"; "Bad!" ])

let renamed_to_holds_for_the_edges_that_renamed_reports =
  property ~name:"renamed_to names a declaration for each renamed edge alone"
    ~print:print_trees trees_gen (fun (a, b, p) ->
      let side at_base =
        List.filter_map
          (fun (path, version) ->
            Option.map
              (fun text -> (path, document text))
              (match version with
              | Same t -> Some t
              | Changed (x, y) -> Some (if at_base then x else y)
              | Base_only t -> if at_base then Some t else None
              | Tree_only t -> if at_base then None else Some t))
          [ ("docs/a.md", a); ("docs/b.md", b); (".plans/p.md", p) ]
      in
      let base = Facts.make manifest (side true)
      and tree = Facts.make manifest (side false) in
      let reported =
        List.filter_map
          (fun (finding : Finding.t) ->
            if finding.finding_class = Finding_class.Renamed then
              Some
                ( Finding.subject_id finding.subject,
                  Option.map Fix.text finding.fix )
            else None)
          (Adjudicator.classes ~base tree
             (Findings.of_facts tree ~base:base_commit ~not_text:[]))
      in
      let renamed_to = Adjudicator.renamed_to ~base tree in
      List.for_all
        (fun ((edge : Facts.edge), _) ->
          let fix =
            Option.map
              (fun (d : Facts.declaration) ->
                Printf.sprintf "@%s %s%s" edge.word d.slug
                  (Option.fold ~none:""
                     ~some:(fun _ -> Printf.sprintf " v%d" d.rev)
                     edge.rev))
              (renamed_to edge.target_text)
          in
          List.assoc_opt (Facts.edge_id edge) reported
          = Option.map Option.some fix)
        (Facts.edges tree))

let parts (finding : Finding.t) =
  String.concat " / "
    ((match finding.place with
     | Some { path; span } -> Printf.sprintf "%s:%d" path span.start.line
     | None -> "-")
    :: (match finding.mark with
    | Some { start; stop; label } -> Printf.sprintf "%d-%d %s" start stop label
    | None -> "no mark")
    :: List.map
         (fun ({ label; place } : Finding.related) ->
           match place with
           | Some { path; span } ->
               Printf.sprintf "%s at %s:%d:%d-%d:%d" label path span.start.line
                 span.start.column span.stop.line span.stop.column
           | None -> label)
         finding.related)

let unbumped_marks_the_revision_or_the_word () =
  Alcotest.check strings "the marks"
    [
      "docs/a.md:3 / 13-15 changed since the base, still v2";
      "docs/a.md:7 / 1-5 changed since the base, still v1";
    ]
    (List.map parts
       (Adjudicator.classes
          ~base:
            (facts
               [
                 ( "docs/a.md",
                   "# A\n\n@req edited v2 Old.\n\n## B\n\n@req bare Old.\n" );
               ])
          (facts
             [
               ( "docs/a.md",
                 "# A\n\n@req edited v2 New.\n\n## B\n\n@req bare New.\n" );
             ])
          []))

let renamed_marks_the_target_and_names_the_new_declaration () =
  let base =
    [
      ("docs/spec.md", "# Spec\n\n@req lockout v1 Lock it.\n");
      ("docs/use.md", "# Use\n\n- @cites lockout v1\n");
    ]
  and tree =
    [
      ("docs/moved.md", "# Spec\n\n@req account-lockout v2 Lock it.\n");
      ("docs/use.md", "# Use\n\n- @cites lockout v1\n");
    ]
  in
  let tree_facts = facts tree in
  Alcotest.check strings "the marks"
    [
      "docs/use.md:3 / 10-17 renamed since the base / declared here now at \
       docs/moved.md:3:1-3:33";
    ]
    (List.filter_map
       (fun (finding : Finding.t) ->
         if finding.finding_class = Finding_class.Renamed then
           Some (parts finding)
         else None)
       (Adjudicator.classes ~base:(facts base) tree_facts []))

let promise_collision_marks_the_target () =
  let plan steps = "# P\n\n@plan p\n@scope docs/**\n\n" ^ steps in
  Alcotest.check strings "the marks"
    [ ".plans/p.md:8 / 6-11 the base declares this slug" ]
    (List.map parts
       (Adjudicator.classes
          ~base:(facts [ ("docs/a.md", "# A\n\n@design taken v1\n") ])
          (facts
             [
               ("docs/a.md", "# A\n\n@design taken v1\n");
               (".plans/p.md", plan "## New\n\n@req taken\n");
             ])
          []))

let case name f = Alcotest.test_case name `Quick f

let renamed_steps ?same ?whole_base base tree =
  List.map show
    (List.filter
       (fun (finding : Finding.t) ->
         finding.finding_class = Finding_class.Renamed_step
         || finding.finding_class = Finding_class.Promise_collision)
       (Adjudicator.classes ?same ?whole_base ~base:(facts base) (facts tree) []))

let steps_plan steps =
  (".plans/p.md", "# P\n\n@plan p@0a1b2c\n@scope **\n" ^ steps)

let lost slug =
  Printf.sprintf
    ".plans/p.md:3 | finding:renamed-step:step:p@0a1b2c/%s | step:p@0a1b2c/%s \
     is started in the base, and the plan has no step with the slug %s now"
    slug slug slug

let renamed_step_reports_each_lost_slug_of_a_started_step () =
  let a = ("docs/a.md", "# A\n\n@req a\n\n## B\n\n@req b\n") in
  let one = steps_plan "\n## Do it\n\n@req a\n@req b\n" in
  Alcotest.check strings "a rename"
    [ lost "do-it" ]
    (renamed_steps [ one; a ]
       [ steps_plan "\n## Do that\n\n@req a\n@req b\n"; a ]);
  Alcotest.check strings "a split"
    [ lost "do-it" ]
    (renamed_steps [ one; a ]
       [ steps_plan "\n## Do a\n\n@req a\n\n## Do b\n\n@req b\n"; a ]);
  Alcotest.check strings "a removal"
    [ lost "do-it" ]
    (renamed_steps [ one; a ] [ steps_plan "\n## Other\n\n@req c\n"; a ]);
  Alcotest.check strings "a step that is not started" []
    (renamed_steps [ one ] [ steps_plan "\n## Do that\n\n@req a\n@req b\n" ]);
  Alcotest.check strings "the slug stays" []
    (renamed_steps [ one; a ]
       [ steps_plan "\n## Do it\n\n@req a\n@req b\nMore.\n"; a ]);
  Alcotest.check strings "another plan: a collision, and no renamed-step"
    [
      ".plans/p.md:8 | \
       finding:promise-collision:promise:step:p@111111/do-that:req:a | the \
       base already declares req:a";
    ]
    (renamed_steps [ one; a ]
       [
         ( ".plans/p.md",
           "# P\n\n@plan p@111111\n@scope **\n\n## Do that\n\n@req a\n" );
         a;
       ])

let renamed_step_reads_the_unchanged_files_of_the_base () =
  let a = ("docs/a.md", "# A\n\n@req a\n") in
  let one = steps_plan "\n## Do it\n\n@req a\n" in
  Alcotest.check strings "the meeting fact sits in an unchanged file"
    [ lost "do-it" ]
    (renamed_steps ~same:(String.equal "docs/a.md")
       ~whole_base:(lazy (facts [ one; a ]))
       [ one ]
       [ steps_plan "\n## Do that\n\n@req a\n"; a ])

let commit = "0123456789abcdef0123456789abcdef01234567"
let other_commit = "fedcba9876543210fedcba9876543210fedcba98"

let delivery_findings ?(commit = commit) ?(base = []) wanted message tree =
  List.map show
    (List.filter
       (fun (finding : Finding.t) -> finding.finding_class = wanted)
       (Adjudicator.classes
          ~deliveries:(Delivery_line.read ~commit message)
          ~base:(facts base) (facts tree) []))

let refactor_plan =
  ( ".plans/p.md",
    "# P\n\n@plan p@0a1b2c\n@scope **\n\n## Tidy\n\n@scope lib/**\nTidy it.\n"
  )

let line_of (path, text) slug =
  match Facts.plans (facts [ (path, text) ]) with
  | [ plan ] -> (
      match
        List.find_opt
          (fun (step : Facts.step) -> String.equal step.slug slug)
          plan.steps
      with
      | Some step -> (
          match Facts.delivery plan step with
          | Some line -> Delivery_line.to_string line
          | None -> Alcotest.fail "the step has no delivery line")
      | None -> Alcotest.fail "no such step")
  | _ -> Alcotest.fail "the text gives no plan"

let stale message =
  delivery_findings Finding_class.Stale_delivery message [ refactor_plan ]

let stale_delivery_reports_each_line_that_does_not_count () =
  let good = line_of refactor_plan "tidy" in
  Alcotest.(check strings) "a line that counts" [] (stale (good ^ "\n"));
  Alcotest.(check strings)
    "a line with blanks at its end that counts" []
    (stale (good ^ " \t\r\n"));
  Alcotest.(check strings)
    "a line of another form"
    [
      "- | finding:stale-delivery:message:" ^ commit
      ^ "@L3 | the line \"Delivers: p@0a1b2c/tidy\" of commit 0123456 does not \
         match the form Delivers: <plan>/<step> <hash>";
    ]
    (stale "Tidy\n\nDelivers: p@0a1b2c/tidy\n");
  Alcotest.(check strings)
    "a line of no step"
    [
      "- | finding:stale-delivery:message:" ^ commit
      ^ "@L1 | the line \"Delivers: p@0a1b2c/other 000000\" of commit 0123456 \
         names no step of an open plan";
      "- | finding:stale-delivery:message:" ^ commit
      ^ "@L2 | the line \"Delivers: p/tidy 000000\" of commit 0123456 names no \
         step of an open plan";
    ]
    (stale "Delivers: p@0a1b2c/other 000000\nDelivers: p/tidy 000000\n");
  Alcotest.(check strings)
    "a line of another hash"
    [
      "- | finding:stale-delivery:message:" ^ commit
      ^ "@L1 | the line \"Delivers: p@0a1b2c/tidy 000000\" of commit 0123456 \
         does not match the step hash of step:p@0a1b2c/tidy; write \"" ^ good
      ^ "\"";
    ]
    (stale "Delivers: p@0a1b2c/tidy 000000\n")

let stale_delivery_names_the_step_and_has_no_place_and_no_fix () =
  match
    List.filter
      (fun (finding : Finding.t) ->
        finding.finding_class = Finding_class.Stale_delivery)
      (Adjudicator.classes
         ~deliveries:
           (Delivery_line.read ~commit "Delivers: p@0a1b2c/tidy 000000\n"
           @ Delivery_line.read ~commit:other_commit
               "x\nDelivers: p@0a1b2c/tidy 000000\n")
         ~base:(facts []) (facts [ refactor_plan ]) [])
  with
  | [ first; second ] ->
      Alcotest.(check (list string))
        "one finding for each commit"
        [ "message:" ^ commit ^ "@L1"; "message:" ^ other_commit ^ "@L2" ]
        (List.sort compare
           (List.map
              (fun (finding : Finding.t) -> Finding.ack_subject finding.subject)
              [ first; second ]));
      Alcotest.(check bool) "no place" true (Option.is_none first.place);
      Alcotest.(check bool) "no fix" true (Option.is_none first.fix);
      Alcotest.(check bool) "not ackable" false first.ackable;
      Alcotest.(check (list string))
        "the related place is the step"
        [ "the step .plans/p.md:6" ]
        (List.map
           (fun (related : Finding.related) ->
             match related.place with
             | Some { path; span } ->
                 Printf.sprintf "%s %s:%d" related.label path span.start.line
             | None -> related.label)
           first.related)
  | findings ->
      Alcotest.failf "two findings were expected, not %d" (List.length findings)

let stale_delivery_shows_the_line_as_one_line_of_utf_8 () =
  Alcotest.(check strings)
    "the control characters and the bytes that are not UTF-8"
    [
      "- | finding:stale-delivery:message:" ^ commit
      ^ "@L1 | the line \"Delivers: \\x1b[31mp\\xff/tidy 000000\" of commit \
         0123456 does not match the form Delivers: <plan>/<step> <hash>";
    ]
    (stale "Delivers: \x1b[31mp\xff/tidy 000000\n")

let two_promise_plan =
  ( ".plans/p.md",
    "# P\n\n@plan p@0a1b2c\n@scope **\n\n## Do it\n\n@req a\n@req b\nText.\n" )

let unmet ?(commit = commit) message files =
  delivery_findings ~commit Finding_class.Delivery_on_unmet_step message files

let related_parts (finding : Finding.t) =
  List.map
    (fun (related : Finding.related) ->
      match related.place with
      | Some { path; span } ->
          Printf.sprintf "%s %s:%d" related.label path span.start.line
      | None -> related.label)
    finding.related

let delivery_on_unmet_step_sits_at_a_step_with_an_unmet_promise () =
  let line = line_of two_promise_plan "do-it" ^ "\n" in
  let a = ("lib/a.md", "# A\n\n@req a\n")
  and b = ("lib/b.md", "# B\n\n@req b\n") in
  let finding =
    ".plans/p.md:6 | finding:delivery-on-unmet-step:step:p@0a1b2c/do-it | \
     commit 0123456 delivers step:p@0a1b2c/do-it, and 1 of its 2 promises are \
     not met"
  in
  Alcotest.(check strings)
    "one promise not met" [ finding ]
    (unmet line [ two_promise_plan; a ]);
  Alcotest.(check strings)
    "every promise met" []
    (unmet line [ two_promise_plan; a; b ]);
  Alcotest.(check strings)
    "a line that does not count" []
    (unmet "Delivers: p@0a1b2c/do-it 000000\n" [ two_promise_plan; a ]);
  Alcotest.(check strings)
    "no line" []
    (unmet "Fix it\n" [ two_promise_plan; a ]);
  Alcotest.(check strings)
    "two lines for one step give one finding" [ finding ]
    (List.map show
       (List.filter
          (fun (finding : Finding.t) ->
            finding.finding_class = Finding_class.Delivery_on_unmet_step)
          (Adjudicator.classes
             ~deliveries:
               (Delivery_line.read ~commit ("Do it\n\n" ^ line ^ line)
               @ Delivery_line.read ~commit:other_commit line)
             ~base:(facts [])
             (facts [ two_promise_plan; a ])
             [])))

let delivery_on_unmet_step_names_each_promise_not_met () =
  match
    List.filter
      (fun (finding : Finding.t) ->
        finding.finding_class = Finding_class.Delivery_on_unmet_step)
      (Adjudicator.classes
         ~deliveries:
           (Delivery_line.read ~commit (line_of two_promise_plan "do-it"))
         ~base:(facts [])
         (facts [ two_promise_plan ])
         [])
  with
  | [ finding ] ->
      Alcotest.(check (list string))
        "the related places"
        [ "not met .plans/p.md:8"; "not met .plans/p.md:9" ]
        (related_parts finding);
      Alcotest.(check bool) "no fix" true (Option.is_none finding.fix);
      Alcotest.(check bool) "not ackable" false finding.ackable
  | findings ->
      Alcotest.failf "one finding was expected, not %d" (List.length findings)

let delivery_on_unmet_step_counts_no_verifies_edge_of_a_markdown_file () =
  let plan =
    ( ".plans/p.md",
      "# P\n\n@plan p@0a1b2c\n@scope **\n\n## Do it\n\n@req a\n@verifies a\n" )
  in
  Alcotest.(check int)
    "the promised verifies is not met" 1
    (List.length
       (unmet
          (line_of plan "do-it" ^ "\n")
          [ plan; ("lib/a.md", "# A\n\n@req a\n\n## T\n\n@verifies a v1\n") ]))

let tests =
  [
    case "delivery-on-unmet-step sits at a step with an unmet promise"
      delivery_on_unmet_step_sits_at_a_step_with_an_unmet_promise;
    case "delivery-on-unmet-step names each promise not met"
      delivery_on_unmet_step_names_each_promise_not_met;
    case "delivery-on-unmet-step counts no verifies edge of a markdown file"
      delivery_on_unmet_step_counts_no_verifies_edge_of_a_markdown_file;
    case "stale-delivery reports each line that does not count"
      stale_delivery_reports_each_line_that_does_not_count;
    case "stale-delivery names the step and has no place and no fix"
      stale_delivery_names_the_step_and_has_no_place_and_no_fix;
    case "stale-delivery shows the line as one line of UTF-8"
      stale_delivery_shows_the_line_as_one_line_of_utf_8;
    Alcotest.test_case "renamed-step reports each lost slug of a started step"
      `Quick renamed_step_reports_each_lost_slug_of_a_started_step;
    Alcotest.test_case "renamed-step reads the unchanged files of the base"
      `Quick renamed_step_reads_the_unchanged_files_of_the_base;
    case "unbumped marks the revision or the word"
      unbumped_marks_the_revision_or_the_word;
    case "renamed marks the target and names the new declaration"
      renamed_marks_the_target_and_names_the_new_declaration;
    case "promise-collision marks the target" promise_collision_marks_the_target;
    case "a tombstone names each fact that the working tree lacks"
      a_tombstone_names_each_fact_that_the_working_tree_lacks;
    case "two facts of one id give one tombstone"
      two_facts_of_one_id_give_one_tombstone;
    case "a tree like its base has no tombstone"
      a_tree_like_its_base_has_no_tombstone;
    case "unbumped needs a higher revision for a changed extent"
      unbumped_needs_a_higher_revision_for_a_changed_extent;
    case "unbumped counts a change of kind" unbumped_counts_a_change_of_kind;
    case "unbumped ignores a renumbered heading and a moved file"
      unbumped_ignores_a_renumbered_heading_and_a_moved_file;
    case
      "unbumped holds for a retired declaration and not under a historical path"
      unbumped_holds_for_a_retired_declaration_and_not_under_a_historical_path;
    case "unbumped reads every declaration of the slug at the base"
      unbumped_reads_every_declaration_of_the_slug_at_the_base;
    case "the findings keep their order with the new ones"
      the_findings_keep_their_order_with_the_new_ones;
    case "renamed takes the place of dangling"
      renamed_takes_the_place_of_dangling;
    case "two candidates leave the edge dangling"
      two_candidates_leave_the_edge_dangling;
    case "a slug with two tombstones leaves the edge dangling"
      a_slug_with_two_tombstones_leaves_the_edge_dangling;
    case "a new promise of a slug of the base collides"
      a_new_promise_of_a_slug_of_the_base_collides;
    case "the same plan across the base holds its promises"
      the_same_plan_across_the_base_holds_its_promises;
    a_tree_like_its_base_has_no_finding;
    a_base_without_the_same_files_gives_the_same_classes;
    case "renamed_to names the new declaration of the fix"
      renamed_to_names_the_new_declaration_of_the_fix;
    renamed_to_holds_for_the_edges_that_renamed_reports;
  ]
