(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let reader =
  lazy
    (match Markdown.create (Sinter_bridge.create ()) with
    | Ok reader -> reader
    | Error _ -> failwith "the reader does not start")

let document text =
  match Markdown.read (Lazy.force reader) text with
  | Ok document -> document
  | Error _ -> Alcotest.fail "the text gives no document"

let markdown =
  "[scan]\npacks.markdown.files = [\"**/*.md\"]\nrefs.gh = \"[1-9][0-9]*\"\n"

let manifest extra =
  match Manifest.of_string (markdown ^ extra) with
  | Ok manifest -> manifest
  | Error _ -> Alcotest.fail "the manifest has errors"

let findings ?(extra = "") ?(not_text = []) files =
  Findings.tree (manifest extra)
    (List.map (fun (path, text) -> (path, document text)) files)
    ~not_text

let place_text (finding : Finding.t) =
  match finding.place with
  | None -> "-:-:-"
  | Some { path; span } ->
      Printf.sprintf "%s:%d:%d-%d:%d" path span.start.line span.start.column
        span.stop.line span.stop.column

(* One finding as one line: its place, its id, its detail, and its
   fix. *)
let show (finding : Finding.t) =
  String.concat " | "
    ([ place_text finding; Finding.id finding ]
    @ Option.to_list finding.detail
    @ Option.fold ~none:[] ~some:(fun fix -> [ "fix: " ^ fix ]) finding.fix)

(* Checks that the findings of [files] of the class [finding_class] are
   [expected], each as {!show} gives it. *)
let check ?extra ?not_text finding_class files expected =
  Alcotest.(check (list string))
    (Finding_class.name finding_class)
    expected
    (List.map show
       (List.filter
          (fun (finding : Finding.t) -> finding.finding_class = finding_class)
          (findings ?extra ?not_text files)))

(* {1 The classes of the reader} *)

let parse_error_sits_at_each_error_and_at_a_file_that_is_not_text () =
  check
    ~not_text:[ ("docs/b.md", 7) ]
    Finding_class.Parse_error
    [
      ( "docs/a.md",
        "# T\n\n| Name | D |\n| ---- | - |\n| `x`  | y |\n|      |   |\n" );
      ("docs/c.md", "| a |\n|---|\n| x\xe2\x80\x94 |\n|  |\n");
    ]
    [
      "docs/a.md:5:1-6:13 | finding:parse-error:file:docs/a.md@L5C1 | the \
       markdown parser cannot read the text here";
      "docs/b.md:1:1-1:1 | finding:parse-error:file:docs/b.md | the file is \
       not UTF-8 text at byte 7";
      "docs/c.md:4:4-4:4 | finding:parse-error:file:docs/c.md@L4C4 | the \
       markdown parser cannot read the text here";
    ]

let typo_tag_names_the_nearest_word () =
  check Finding_class.Typo_tag
    [
      ( "docs/a.md",
        "# A\n\n\
         @reqq a v1\n\n\
         ## B\n\n\
         @Req b\n\n\
         ## C\n\n\
         @pin x\n\n\
         ## D\n\n\
         @param y\n\n\
         ## E\n\n\
         @ z\n" );
    ]
    [
      "docs/a.md:3:1-3:11 | finding:typo-tag:line:docs/a.md@L3 | @reqq is not \
       a tag word of sinter | fix: @req";
      "docs/a.md:7:1-7:7 | finding:typo-tag:line:docs/a.md@L7 | @Req is not a \
       tag word of sinter | fix: @req";
      "docs/a.md:11:1-11:7 | finding:typo-tag:line:docs/a.md@L11 | @pin is not \
       a tag word of sinter | fix: @plan";
    ]

(* "reck" is two edits from "ack" and from "req", and from no word
   nearer. The vocabulary lists "req" first; byte order puts "ack"
   first. *)
let typo_tag_takes_the_first_word_in_byte_order_of_two_equally_near () =
  check Finding_class.Typo_tag
    [ ("docs/a.md", "# A\n\n@reck x\n") ]
    [
      "docs/a.md:3:1-3:8 | finding:typo-tag:line:docs/a.md@L3 | @reck is not a \
       tag word of sinter | fix: @ack";
    ]

let unread_tag_sits_at_a_later_paragraph () =
  check Finding_class.Unread_tag
    [ ("docs/a.md", "# A\n\nText.\n\n@req a v1\n\n> @req b v1\n") ]
    [
      "docs/a.md:5:1-5:10 | finding:unread-tag:line:docs/a.md@L5 | sinter \
       reads tags only in the first paragraph of a section or a list item";
    ]

let bad_target_names_why_the_target_fails () =
  check Finding_class.Bad_target
    [
      ( "docs/a.md",
        "# A\n\n\
         @req a! v1\n\
         @cites xy/1\n\
         @cites gh/0\n\
         @cites gh/12\n\
         @satisfies b_ v1\n\
         @ack disendorsed x 1234abcd\n\
         @deprecated now\n" );
      (".plans/p.md", "# P\n\n@plan p/q\n\n## S\n\n@scope lib/**\n@req Q!\n");
    ]
    [
      ".plans/p.md:3:1-3:10 | finding:bad-target:tag:.plans/p.md@L3C1 | p/q is \
       not a valid slug";
      ".plans/p.md:8:1-8:8 | finding:bad-target:tag:.plans/p.md@L8C1 | Q! is \
       not a valid slug";
      "docs/a.md:3:1-3:11 | finding:bad-target:tag:docs/a.md@L3C1 | a! is not \
       a valid slug";
      "docs/a.md:4:1-4:12 | finding:bad-target:tag:docs/a.md@L4C1 | the \
       manifest declares no ref namespace xy";
      "docs/a.md:5:1-5:12 | finding:bad-target:tag:docs/a.md@L5C1 | 0 does not \
       match the id pattern of the ref namespace gh";
      "docs/a.md:7:1-7:17 | finding:bad-target:tag:docs/a.md@L7C1 | b_ is not \
       a valid slug";
    ]

let misplaced_plan_sits_outside_the_first_block_of_a_plan_file () =
  check Finding_class.Misplaced_plan
    [
      ("docs/a.md", "# A\n\n@plan a\n");
      (".plans/p.md", "# P\n\n@plan p\n\n## S\n\n@plan q\n");
      (".plans/q.md", "# Q\n\n@plan q\n");
    ]
    [
      ".plans/p.md:7:1-7:8 | finding:misplaced-plan:tag:.plans/p.md@L7C1 | a \
       @plan tag stands only in the first tag block of its file";
      "docs/a.md:3:1-3:8 | finding:misplaced-plan:tag:docs/a.md@L3C1 | a @plan \
       tag stands only in a file under .plans/";
    ]

(* {1 The classes of the facts} *)

let duplicate_sits_at_each_later_member_of_a_group () =
  check Finding_class.Duplicate
    [
      ("docs/b.md", "# B\n\n@req Auth v1\n\n## C\n\n@design auth\n");
      ("docs/a.md", "# A\n\n@decision auth\n\n## D\n\n@req other\n");
      ("docs/c.md", "# C\n\n@rule auth\n");
      ( ".plans/q.md",
        "# Q\n\n\
         @plan P\n\n\
         ## One\n\n\
         @req x\n\n\
         ## One!\n\n\
         @req y\n\n\
         ## Two\n\n\
         @scope a/**\n" );
      (".plans/p.md", "# P\n\n@plan p\n");
    ]
    [
      ".plans/q.md:3:1-3:8 | finding:duplicate:tag:.plans/q.md@L3C1 | the slug \
       p comes first at .plans/p.md:3";
      ".plans/q.md:9:1-9:8 | finding:duplicate:line:.plans/q.md@L9 | the slug \
       one comes first at .plans/q.md:5";
      "docs/b.md:3:1-3:13 | finding:duplicate:tag:docs/b.md@L3C1 | the slug \
       auth comes first at docs/a.md:3";
      "docs/b.md:7:1-7:13 | finding:duplicate:tag:docs/b.md@L7C1 | the slug \
       auth comes first at docs/a.md:3";
    ]

let unpinned_pastes_the_revision_of_the_target () =
  check Finding_class.Unpinned
    [
      ( "docs/a.md",
        "# A\n\n\
         @req a v3\n\n\
         ## B\n\n\
         @satisfies a\n\
         @verifies a v3\n\
         @refines nothing\n\
         @cites a\n\
         @supersedes gh/1\n" );
    ]
    [
      "docs/a.md:7:1-7:13 | finding:unpinned:satisfies:req:a->a | the \
       @satisfies names no revision | fix: @satisfies a v3";
      "docs/a.md:9:1-9:17 | finding:unpinned:refines:req:a->nothing | the \
       @refines names no revision";
      "docs/a.md:11:1-11:17 | finding:unpinned:supersedes:req:a->gh/1 | the \
       @supersedes names no revision";
    ]

let dangling_names_the_spelling_that_differs_in_case () =
  check Finding_class.Dangling
    [
      ("docs/a.md", "# A\n\n@req login v1\n@rule logout\n");
      ( "docs/b.md",
        "# B\n\n\
         @cites Login v2\n\
         @satisfies nothing v1\n\
         @cites logout\n\
         @cites bad!\n\
         @cites zz/1\n\
         @cites login\n" );
    ]
    [
      "docs/b.md:3:1-3:16 | finding:dangling:cites:site:docs/b.md#b->Login | \
       no declaration has the slug Login | fix: @cites login v2";
      "docs/b.md:4:1-4:22 | \
       finding:dangling:satisfies:site:docs/b.md#b->nothing | no declaration \
       has the slug nothing";
      "docs/b.md:5:1-5:14 | finding:dangling:cites:site:docs/b.md#b->logout | \
       no declaration has the slug logout";
    ]

let suspect_pastes_the_current_revision () =
  check Finding_class.Suspect
    [
      ( "docs/a.md",
        "# A\n\n\
         @req a v2\n\n\
         ## B\n\n\
         @cites a v1\n\
         @satisfies a v2\n\
         @verifies a v3\n\
         @cites a\n" );
    ]
    [
      "docs/a.md:7:1-7:12 | finding:suspect:cites:req:a->a | the @cites names \
       v1, and req:a is at v2 | fix: @cites a v2";
      "docs/a.md:9:1-9:15 | finding:suspect:verifies:req:a->a | the @verifies \
       names v3, and req:a is at v2 | fix: @verifies a v2";
    ]

let cycle_names_its_smallest_member_and_the_others () =
  check Finding_class.Cycle
    [
      ( "docs/a.md",
        "# A\n\n\
         @req c\n\
         @refines b v1\n\n\
         ## B\n\n\
         @req b\n\
         @refines a v1\n\n\
         ## C\n\n\
         @req a\n\
         @refines c v1\n\n\
         ## D\n\n\
         @decision d\n\
         @supersedes d v1\n\n\
         ## E\n\n\
         @req e\n\
         @refines a v1\n\n\
         ## F\n\n\
         Text.\n\n\
         @cites e\n" );
      ("docs/b.md", "# B\n\nText.\n\n- @req f\n  @cites f\n");
    ]
    [
      "docs/a.md:13:1-13:7 | finding:cycle:req:a | with req:b, req:c";
      "docs/a.md:18:1-18:12 | finding:cycle:decision:d";
    ]

let disendorsed_of_a_status_pastes_the_ack_of_its_block () =
  check Finding_class.Disendorsed
    [
      ( "docs/a.md",
        "# A\n\n@decision old\n@deprecated\n\n## B\n\n@decision new\n" );
      ("docs/b.md", "# B\n\n@cites old\n@cites new\n@refines old v1\n");
    ]
    [
      "docs/b.md:3:1-3:11 | finding:disendorsed:cites:site:docs/b.md#b->old | \
       decision:old is deprecated | fix: @ack disendorsed old 393d3530";
    ]

(* Records where new, at v3, supersedes gone; and z supersedes y, which
   supersedes x. *)
let superseded =
  ( "docs/a.md",
    "# A\n\n\
     @decision new v3\n\
     @supersedes gone v1\n\n\
     ## Gone\n\n\
     @decision gone\n\n\
     ## Z\n\n\
     @decision z\n\
     @supersedes y v1\n\n\
     ## Y\n\n\
     @decision y v2\n\
     @supersedes x v1\n\n\
     ## X\n\n\
     @decision x\n" )

let disendorsed_of_a_superseded_item_names_its_successor () =
  check Finding_class.Disendorsed
    [
      superseded;
      ( "docs/b.md",
        "# B\n\n@cites gone\n@cites gone v1\n@cites x v1\n@cites y\n" );
    ]
    [
      "docs/b.md:3:1-3:12 | finding:disendorsed:cites:site:docs/b.md#b->gone | \
       decision:gone is superseded by decision:new | fix: @cites new";
      "docs/b.md:4:1-4:15 | finding:disendorsed:cites:site:docs/b.md#b->gone | \
       decision:gone is superseded by decision:new | fix: @cites new v3";
      "docs/b.md:5:1-5:12 | finding:disendorsed:cites:site:docs/b.md#b->x | \
       decision:x is superseded by decision:z | fix: @cites z v1";
      "docs/b.md:6:1-6:9 | finding:disendorsed:cites:site:docs/b.md#b->y | \
       decision:y is superseded by decision:z | fix: @cites z";
    ]

let disendorsed_names_each_successor_in_the_order_of_their_ids () =
  check Finding_class.Disendorsed
    [
      ( "docs/a.md",
        "# A\n\n\
         @decision c\n\
         @supersedes a v1\n\n\
         ## B\n\n\
         @decision b v2\n\
         @supersedes a v1\n\n\
         ## A\n\n\
         @decision a\n\
         @deprecated\n" );
      ("docs/b.md", "# B\n\n@cites a v1\n");
    ]
    [
      "docs/b.md:3:1-3:12 | finding:disendorsed:cites:site:docs/b.md#b->a | \
       decision:a is superseded by decision:b, decision:c | fix: @cites b v2 \
       or @cites c v1";
    ]

let orphan_sits_at_a_citation_without_its_source () =
  check Finding_class.Orphan
    [
      ("docs/a.md", "# A\n\n@req a v1\n@verifies a v1\n@refines a v1\n");
      ( "docs/b.md",
        "# B\n\nText.\n\n- @refines a v1\n- @supersedes a v1\n- @cites a\n" );
    ]
    [
      "docs/a.md:4:1-4:15 | finding:orphan:verifies:req:a->a | a @verifies \
       needs a test as its source";
      "docs/b.md:5:3-5:16 | finding:orphan:refines:site:docs/b.md#b->a | a \
       @refines needs a declaration that holds it";
      "docs/b.md:6:3-6:19 | finding:orphan:supersedes:site:docs/b.md#b->a | a \
       @supersedes needs a declaration that holds it";
    ]

let uncovered_names_what_is_missing () =
  check Finding_class.Uncovered
    [
      ( "docs/a.md",
        "# A\n\n\
         @req a\n\n\
         ## B\n\n\
         @design b\n\n\
         ## C\n\n\
         @req c\n\n\
         ## D\n\n\
         @req d\n\
         @deprecated\n\n\
         ## E\n\n\
         @decision e\n" );
      ( "docs/b.md",
        "# B\n\n\
         Text.\n\n\
         - @satisfies b v1\n\
         - @verifies c v1\n\
         - @satisfies c v1\n\
         - @cites a\n\
         - @satisfies gh/1 v1\n\
         - @verifies nothing v1\n" );
    ]
    [
      "docs/a.md:3:1-3:7 | finding:uncovered:req:a | nothing satisfies it, and \
       nothing verifies it";
      "docs/a.md:7:1-7:10 | finding:uncovered:design:b | nothing verifies it";
    ];
  check Finding_class.Uncovered
    [
      ("docs/a.md", "# A\n\n@req a\n");
      ("docs/b.md", "# B\n\nText.\n\n- @verifies a v1\n");
    ]
    [ "docs/a.md:3:1-3:7 | finding:uncovered:req:a | nothing satisfies it" ]

(* {1 The classes of plans} *)

let plan steps =
  ( ".plans/p.md",
    "# P\n\n@plan p\n@scope lib/**, docs/, bin/main.ml, src/*/**, !lib/x/**\n"
    ^ steps )

let bad_scope_names_the_globs_outside_the_plan () =
  check Finding_class.Bad_scope
    [
      plan
        "\n\
         ## In\n\n\
         @scope lib/a/**, lib/, docs/b/, bin/main.ml, src/a/, src/a/b.ml, \
         !test/**\n\
         @req a\n\n\
         ## Out\n\n\
         @scope bin/**, bin/, lib, test/a.ml, src/a/*.ml, lib/?\n\
         @req b\n\n\
         ## Bare\n\n\
         @req c\n";
    ]
    [
      ".plans/p.md:11:1-11:7 | finding:bad-scope:step:p/out | the scope of the \
       plan does not hold bin/**, bin/, lib, test/a.ml, src/a/*.ml, lib/?";
    ];
  check Finding_class.Bad_scope
    [
      (".plans/p.md", "# P\n\n@plan p\n\n## S\n\n@scope a/**\n@req a\n");
      ( ".plans/q.md",
        "# Q\n\n@plan q\n@scope **\n\n## S\n\n@scope a/**, b/c, b/, x/?\n" );
      ( ".plans/r.md",
        "# R\n\n@plan r\n@scope a/?, pkg/*\n\n## S\n\n@scope a/b, pkg/, pkg/a\n"
      );
    ]
    [
      ".plans/p.md:5:1-5:5 | finding:bad-scope:step:p/s | the scope of the \
       plan does not hold a/**";
      ".plans/q.md:6:1-6:5 | finding:bad-scope:step:q/s | the scope of the \
       plan does not hold x/?";
      ".plans/r.md:6:1-6:5 | finding:bad-scope:step:r/s | the scope of the \
       plan does not hold a/b, pkg/";
    ]

let scope_overlap_sits_at_the_later_step () =
  check Finding_class.Scope_overlap
    [
      ( ".plans/p.md",
        "# P\n\n\
         @plan p\n\
         @scope lib/**\n\n\
         ## One\n\n\
         @scope lib/a/**\n\
         @req a\n\
         @req b\n\n\
         ## Two\n\n\
         @scope lib/a/x.ml\n\
         @req a\n\n\
         ## Three\n\n\
         @scope lib/b/**\n\
         @req b\n\n\
         ## Four\n\n\
         @req b\n\
         @req a\n\n\
         ## Five\n\n\
         @scope lib/a/**\n\
         @req c\n\
         @design a\n" );
    ]
    [
      ".plans/p.md:12:1-12:7 | finding:scope-overlap:step:p/two | this step \
       shares promises and scope with step:p/one";
      ".plans/p.md:22:1-22:8 | finding:scope-overlap:step:p/four | this step \
       shares promises and scope with step:p/one, step:p/two, step:p/three";
    ]

let unverified_promise_sits_at_a_promise_with_no_verifies () =
  check Finding_class.Unverified_promise
    [
      ( ".plans/p.md",
        "# P\n\n\
         @plan p\n\n\
         ## One\n\n\
         @req a\n\
         @design b\n\
         @decision c\n\n\
         ## Two\n\n\
         @verifies a\n\
         @verifies B\n" );
      (".plans/q.md", "# Q\n\n@plan q\n\n## One\n\n@verifies b\n");
    ]
    [
      ".plans/p.md:8:1-8:10 | \
       finding:unverified-promise:promise:step:p/one:design:b | the plan \
       promises no @verifies b";
    ]

let promise_out_of_scope_names_the_residue_outside () =
  check ~extra:"[plan]\nlocations.decision = [\"docs/decisions/\"]\n"
    Finding_class.Promise_out_of_scope
    [
      ( ".plans/p.md",
        "# P\n\n\
         @plan p\n\n\
         ## One\n\n\
         @scope lib/**\n\
         @req a\n\
         @req b\n\
         @decision c\n\
         @decision d\n\
         @cites a\n\
         @req e\n" );
      ("docs/a.md", "# A\n\n@req a v1\n@cites a v1\n\n## E\n\n@req e\n");
      ("lib/b.md", "# B\n\n@req b v1\n");
      ("docs/decisions/c.md", "# C\n\n@decision c\n");
      ("docs/d.md", "# D\n\n@decision d\n");
      ("lib/e.md", "# E\n\n@req e\n");
    ]
    [
      ".plans/p.md:8:1-8:7 | \
       finding:promise-out-of-scope:promise:step:p/one:req:a | req:a at \
       docs/a.md:3 is outside the scope of the step";
      ".plans/p.md:11:1-11:12 | \
       finding:promise-out-of-scope:promise:step:p/one:decision:d | decision:d \
       at docs/d.md:3 is outside the scope of the step";
      ".plans/p.md:12:1-12:9 | \
       finding:promise-out-of-scope:promise:step:p/one:cites:a | \
       cites:req:a->a at docs/a.md:4 is outside the scope of the step";
    ]

(* {1 The rule of acks} *)

let a_live_ack_discharges_its_finding () =
  let files ack =
    [
      ("docs/a.md", "# A\n\n@decision old\n@deprecated\n");
      ("docs/b.md", "# B\n\n@cites old\n@cites x\n" ^ ack);
      ("docs/c.md", "# C\n\n@decision x\n@deprecated\n");
    ]
  in
  check Finding_class.Disendorsed (files "")
    [
      "docs/b.md:3:1-3:11 | finding:disendorsed:cites:site:docs/b.md#b->old | \
       decision:old is deprecated | fix: @ack disendorsed old c55c7593";
      "docs/b.md:4:1-4:9 | finding:disendorsed:cites:site:docs/b.md#b->x | \
       decision:x is deprecated | fix: @ack disendorsed x c55c7593";
    ];
  check Finding_class.Disendorsed
    (files "@ack disendorsed old c55c7593\n")
    [
      "docs/b.md:4:1-4:9 | finding:disendorsed:cites:site:docs/b.md#b->x | \
       decision:x is deprecated | fix: @ack disendorsed x c55c7593";
    ];
  check Finding_class.Disendorsed (files "@ack disendorsed c55c7593d\n") [];
  check Finding_class.Disendorsed (files "@ack disendorsed\tc55c7593\n") []

let a_void_ack_discharges_nothing () =
  let files ack =
    [
      ("docs/a.md", "# A\n\n@decision old\n@deprecated\n");
      ("docs/b.md", "# B\n\n@cites old\n" ^ ack);
    ]
  in
  let finding hash =
    [
      "docs/b.md:3:1-3:11 | finding:disendorsed:cites:site:docs/b.md#b->old | \
       decision:old is deprecated | fix: @ack disendorsed old " ^ hash;
    ]
  in
  check Finding_class.Disendorsed (files "") (finding "ba974016");
  List.iter
    (fun ack ->
      check Finding_class.Disendorsed (files ack) (finding "ba974016"))
    [
      "@ack disendorsed old 00000000\n";
      "@ack disendorsed old ba97401\n";
      "@ack disendorsed other ba974016\n";
      "@ack dangling old ba974016\n";
      "@ack disendorsedx ba974016\n";
      "@ack disendorsed old BA974016\n";
    ]

let an_ack_discharges_only_the_findings_of_its_block () =
  check Finding_class.Disendorsed
    [
      ("docs/a.md", "# A\n\n@decision old\n@deprecated\n");
      ( "docs/b.md",
        "# B\n\n\
         @cites old\n\n\
         ## C\n\n\
         @cites zz\n\
         @ack disendorsed old ba974016\n" );
      ("docs/c.md", "# C\n\n@cites old\n@ack disendorsed old ba974016\n");
    ]
    [
      "docs/b.md:3:1-3:11 | finding:disendorsed:cites:site:docs/b.md#b->old | \
       decision:old is deprecated | fix: @ack disendorsed old ba974016";
    ]

(* Each finding of [files] of the class disendorsed, as {!show} gives
   it, with whether it is ackable. *)
let disendorsed_ackable files =
  List.filter_map
    (fun (finding : Finding.t) ->
      if finding.finding_class = Finding_class.Disendorsed then
        Some (show finding, finding.ackable)
      else None)
    (findings files)

let an_ack_does_not_discharge_the_finding_of_a_superseded_item () =
  let files records ack =
    [ records; ("docs/b.md", "# B\n\n@cites gone\n" ^ ack) ]
  in
  let acks =
    [ "@ack disendorsed gone 62671b3a\n"; "@ack disendorsed 62671b3a\n" ]
  in
  List.iter
    (fun ack ->
      Alcotest.(check (list (pair string bool)))
        ack
        [
          ( "docs/b.md:3:1-3:12 | \
             finding:disendorsed:cites:site:docs/b.md#b->gone | decision:gone \
             is superseded by decision:new | fix: @cites new",
            false );
        ]
        (disendorsed_ackable (files superseded ack)))
    ("" :: acks);
  (* The hash of each ack is the block hash: each discharges the finding
     when a status tag retires gone. *)
  List.iter
    (fun ack ->
      Alcotest.(check (list (pair string bool)))
        ("a status tag, " ^ ack) []
        (disendorsed_ackable
           (files ("docs/a.md", "# A\n\n@decision gone\n@deprecated\n") ack)))
    acks

let an_ack_still_discharges_the_finding_of_an_item_that_a_status_retires () =
  let files ack =
    [
      superseded;
      ("docs/c.md", "# C\n\n@decision old\n@deprecated\n");
      ("docs/b.md", "# B\n\n@cites old\n@cites gone\n" ^ ack);
    ]
  in
  Alcotest.(check (list (pair string bool)))
    "both findings"
    [
      ( "docs/b.md:3:1-3:11 | finding:disendorsed:cites:site:docs/b.md#b->old \
         | decision:old is deprecated | fix: @ack disendorsed old 0fda7530",
        true );
      ( "docs/b.md:4:1-4:12 | finding:disendorsed:cites:site:docs/b.md#b->gone \
         | decision:gone is superseded by decision:new | fix: @cites new",
        false );
    ]
    (disendorsed_ackable (files ""));
  Alcotest.(check (list (pair string bool)))
    "the finding of gone"
    [
      ( "docs/b.md:4:1-4:12 | finding:disendorsed:cites:site:docs/b.md#b->gone \
         | decision:gone is superseded by decision:new | fix: @cites new",
        false );
    ]
    (disendorsed_ackable (files "@ack disendorsed 0fda7530\n"))

(* {1 Text that holds control characters} *)

(* Every finding of [files], each as {!show} gives it. *)
let all ?extra files = List.map show (findings ?extra files)

let a_lone_carriage_return_stays_in_one_line () =
  Alcotest.(check (list string))
    "the findings"
    [
      "docs/guide.md:3:1-3:15 | finding:bad-target:tag:docs/guide.md@L3C1 | \
       foo\\rbar is not a valid slug";
    ]
    (all [ ("docs/guide.md", "# Guide\n\n@cites foo\rbar\n") ]);
  Alcotest.(check (list string))
    "the findings of a file with carriage returns for line endings"
    [
      "docs/a.md:1:6-1:32 | finding:bad-target:tag:docs/a.md@L1C6 | x.\\r\\r## \
       is not a valid slug";
      "docs/a.md:1:23-1:32 | finding:uncovered:req:b | nothing satisfies it, \
       and nothing verifies it";
    ]
    (all [ ("docs/a.md", "# A\r\r@cites x.\r\r## B\r\r@req b v1\r") ])

let a_line_feed_in_a_path_stays_in_one_line () =
  Alcotest.(check (list string))
    "the findings"
    [
      "docs/a\n\
       b.md:3:1-3:10 | finding:uncovered:req:x | nothing satisfies it, and \
       nothing verifies it";
      "docs/c.md:3:1-3:10 | finding:duplicate:tag:docs/c.md@L3C1 | the slug x \
       comes first at docs/a\\nb.md:3";
      "docs/c.md:3:1-3:10 | finding:uncovered:req:x | nothing satisfies it, \
       and nothing verifies it";
    ]
    (all
       [
         ("docs/a\nb.md", "# A\n\n@req x v1\n");
         ("docs/c.md", "# C\n\n@req x v1\n");
       ])

let a_control_character_of_a_plan_stays_in_one_line () =
  Alcotest.(check (list string))
    "the findings"
    [
      ".plans/p.md:6:1-6:5 | finding:bad-scope:step:p/a | the scope of the \
       plan does not hold src/**\\r";
      ".plans/p.md:12:1-12:9 | finding:bad-target:tag:.plans/p.md@L12C1 | \
       x\\ry is not a valid slug";
      ".plans/p.md:12:1-12:9 | \
       finding:unverified-promise:promise:step:p/b:req:x\ry | the plan \
       promises no @verifies x\\ry";
      ".plans/p.md:13:1-13:7 | \
       finding:promise-out-of-scope:promise:step:p/b:req:z | req:z at \
       docs/z\\x01q.md:3 is outside the scope of the step";
      ".plans/p.md:13:1-13:7 | \
       finding:unverified-promise:promise:step:p/b:req:z | the plan promises \
       no @verifies z";
    ]
    (List.filter
       (fun line -> String.starts_with ~prefix:".plans/" line)
       (all
          [
            ( ".plans/p.md",
              "# P\n\n\
               @plan p\n\
               @scope lib/**\n\n\
               ## A\n\n\
               @scope src/**\r\r\n\n\
               ## B\n\n\
               @req x\ry\n\
               @req z\n" );
            ("docs/z\001q.md", "# Z\n\n@req z v1\n");
          ]))

let a_ref_with_no_namespace_or_no_id_says_so () =
  check Finding_class.Bad_target
    [ ("docs/a.md", "# A\n\n@cites /x\n@cites gh/\n@cites zz/\n") ]
    [
      "docs/a.md:3:1-3:10 | finding:bad-target:tag:docs/a.md@L3C1 | the ref /x \
       names no namespace";
      "docs/a.md:4:1-4:11 | finding:bad-target:tag:docs/a.md@L4C1 | the ref \
       gh/ names no id";
      "docs/a.md:5:1-5:11 | finding:bad-target:tag:docs/a.md@L5C1 | the \
       manifest declares no ref namespace zz";
    ]

(* {1 The components of cycles} *)

let cycle_finds_each_component_once () =
  (* The declarations come in this order: a, b, c, d, e, f, g, h. a and
     b make a cycle that is done before c is reached; c reaches a, d,
     and back to c; e, f, and g make a cycle with a branch from f back
     to e; h refines a member of a cycle and is in none. *)
  check Finding_class.Cycle
    [
      ( "docs/a.md",
        "# A\n\n\
         @req a\n\
         @refines b v1\n\n\
         ## B\n\n\
         @req b\n\
         @refines a v1\n\n\
         ## C\n\n\
         @req c\n\
         @refines a v1\n\
         @refines d v1\n\n\
         ## D\n\n\
         @req d\n\
         @supersedes c v1\n\n\
         ## E\n\n\
         @req e\n\
         @refines f v1\n\n\
         ## F\n\n\
         @req f\n\
         @refines g v1\n\
         @refines e v1\n\n\
         ## G\n\n\
         @req g\n\
         @refines e v1\n\n\
         ## H\n\n\
         @req h\n\
         @refines g v1\n" );
    ]
    [
      "docs/a.md:3:1-3:7 | finding:cycle:req:a | with req:b";
      "docs/a.md:13:1-13:7 | finding:cycle:req:c | with req:d";
      "docs/a.md:24:1-24:7 | finding:cycle:req:e | with req:f, req:g";
    ]

let cycle_takes_its_subject_by_id_not_by_place () =
  check Finding_class.Cycle
    [
      ( "docs/a.md",
        "# A\n\n\
         @req z\n\
         @refines m v1\n\n\
         ## M\n\n\
         @req m\n\
         @refines b v1\n\n\
         ## B\n\n\
         @req b\n\
         @refines z v1\n" );
    ]
    [ "docs/a.md:13:1-13:7 | finding:cycle:req:b | with req:m, req:z" ]

(* {1 The global rules} *)

let a_historical_path_gives_no_finding () =
  check ~extra:"[check]\nhistorical = [\"notes/**\"]\n" Finding_class.Typo_tag
    [
      ("notes/a.md", "# A\n\n@reqq a\n");
      (".plans/p.log.md", "# P\n\n@reqq a\n");
      ("docs/a.md", "# A\n\n@reqq a\n");
    ]
    [
      "docs/a.md:3:1-3:8 | finding:typo-tag:line:docs/a.md@L3 | @reqq is not a \
       tag word of sinter | fix: @req";
    ]

let the_findings_are_sorted () =
  let findings =
    findings
      [
        ("docs/b.md", "# B\n\n@reqq a\n\nText.\n\n@req b\n");
        ("docs/a.md", "# A\n\n@plan a!\n");
      ]
  in
  Alcotest.(check (list string))
    "the order"
    (List.map show (List.sort Finding.compare findings))
    (List.map show findings);
  Alcotest.(check int) "the number" 4 (List.length findings)

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "parse-error sits at each error and at a file that is not text"
      parse_error_sits_at_each_error_and_at_a_file_that_is_not_text;
    case "typo-tag names the nearest word" typo_tag_names_the_nearest_word;
    case "typo-tag takes the first word in byte order of two equally near"
      typo_tag_takes_the_first_word_in_byte_order_of_two_equally_near;
    case "unread-tag sits at a later paragraph"
      unread_tag_sits_at_a_later_paragraph;
    case "bad-target names why the target fails"
      bad_target_names_why_the_target_fails;
    case "misplaced-plan sits outside the first block of a plan file"
      misplaced_plan_sits_outside_the_first_block_of_a_plan_file;
    case "duplicate sits at each later member of a group"
      duplicate_sits_at_each_later_member_of_a_group;
    case "unpinned pastes the revision of the target"
      unpinned_pastes_the_revision_of_the_target;
    case "dangling names the spelling that differs in case"
      dangling_names_the_spelling_that_differs_in_case;
    case "suspect pastes the current revision"
      suspect_pastes_the_current_revision;
    case "cycle names its smallest member and the others"
      cycle_names_its_smallest_member_and_the_others;
    case "disendorsed of a status pastes the ack of its block"
      disendorsed_of_a_status_pastes_the_ack_of_its_block;
    case "disendorsed of a superseded item names its successor"
      disendorsed_of_a_superseded_item_names_its_successor;
    case "disendorsed names each successor in the order of their ids"
      disendorsed_names_each_successor_in_the_order_of_their_ids;
    case "orphan sits at a citation without its source"
      orphan_sits_at_a_citation_without_its_source;
    case "uncovered names what is missing" uncovered_names_what_is_missing;
    case "bad-scope names the globs outside the plan"
      bad_scope_names_the_globs_outside_the_plan;
    case "scope-overlap sits at the later step"
      scope_overlap_sits_at_the_later_step;
    case "unverified-promise sits at a promise with no verifies"
      unverified_promise_sits_at_a_promise_with_no_verifies;
    case "promise-out-of-scope names the residue outside"
      promise_out_of_scope_names_the_residue_outside;
    case "a live ack discharges its finding" a_live_ack_discharges_its_finding;
    case "a void ack discharges nothing" a_void_ack_discharges_nothing;
    case "an ack discharges only the findings of its block"
      an_ack_discharges_only_the_findings_of_its_block;
    case "an ack does not discharge the finding of a superseded item"
      an_ack_does_not_discharge_the_finding_of_a_superseded_item;
    case "an ack still discharges the finding of an item that a status retires"
      an_ack_still_discharges_the_finding_of_an_item_that_a_status_retires;
    case "a lone carriage return stays in one line"
      a_lone_carriage_return_stays_in_one_line;
    case "a line feed in a path stays in one line"
      a_line_feed_in_a_path_stays_in_one_line;
    case "a control character of a plan stays in one line"
      a_control_character_of_a_plan_stays_in_one_line;
    case "a ref with no namespace or no id says so"
      a_ref_with_no_namespace_or_no_id_says_so;
    case "cycle finds each component once" cycle_finds_each_component_once;
    case "cycle takes its subject by id, not by place"
      cycle_takes_its_subject_by_id_not_by_place;
    case "a historical path gives no finding" a_historical_path_gives_no_finding;
    case "the findings are sorted" the_findings_are_sorted;
  ]
