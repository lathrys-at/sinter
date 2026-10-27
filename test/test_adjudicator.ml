(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
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
       [check]\n\
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
    @ Option.fold ~none:[] ~some:(fun fix -> [ "fix: " ^ fix ]) finding.fix)

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
      "docs/a.md:3 | finding:unbumped:req:edited | the extent differs from the \
       base, and the revision is not above v2 | fix: @req edited v3";
      "docs/a.md:10 | finding:unbumped:design:lowered | the extent differs \
       from the base, and the revision is not above v4 | fix: @design lowered \
       v5";
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
       req:moved v1, and a change of kind needs a higher revision | fix: \
       @design moved v2";
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
      "docs/a.md:3 | finding:unbumped:req:old | the extent differs from the \
       base, and the revision is not above v1 | fix: @req old v2";
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
      "docs/a.md:3 | finding:unbumped:req:x | the extent differs from the \
       base, and the revision is not above v1 | fix: @req x v2";
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
          (Findings.of_facts tree_facts ~not_text:[])))

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

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
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
    case "the findings keep their order with the new ones"
      the_findings_keep_their_order_with_the_new_ones;
    case "renamed takes the place of dangling"
      renamed_takes_the_place_of_dangling;
    case "two candidates leave the edge dangling"
      two_candidates_leave_the_edge_dangling;
    case "a slug with two tombstones leaves the edge dangling"
      a_slug_with_two_tombstones_leaves_the_edge_dangling;
    a_tree_like_its_base_has_no_finding;
  ]
