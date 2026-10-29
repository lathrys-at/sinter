(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let base_commit = "0123456789abcdef0123456789abcdef01234567"

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
  "[scan]\n\
   packs.markdown.files = [\"**/*.md\"]\n\
   namespaces.gh = \"[1-9][0-9]*\"\n"

let manifest extra =
  match Manifest.of_string (markdown ^ extra) with
  | Ok manifest -> manifest
  | Error _ -> Alcotest.fail "the manifest has errors"

let findings ?(extra = "") ?(not_text = []) files =
  Findings.tree (manifest extra)
    (List.map (fun (path, text) -> (path, document text)) files)
    ~base:base_commit ~not_text

let place_text (finding : Finding.t) =
  match finding.place with
  | None -> "-:-:-"
  | Some { path; span } ->
      Printf.sprintf "%s:%d:%d-%d:%d" path span.start.line span.start.column
        span.stop.line span.stop.column

let show (finding : Finding.t) =
  String.concat " | "
    ([ place_text finding; Finding.id finding ]
    @ Option.to_list finding.detail
    @ Option.fold ~none:[]
        ~some:(fun fix -> [ "fix: " ^ Finding.escape (Fix.text fix) ])
        finding.fix)

let check ?extra ?not_text finding_class files expected =
  Alcotest.(check (list string))
    (Finding_class.name finding_class)
    expected
    (List.map show
       (List.filter
          (fun (finding : Finding.t) -> finding.finding_class = finding_class)
          (findings ?extra ?not_text files)))

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

let typo_tag_takes_the_first_word_in_byte_order_of_two_equally_near () =
  check Finding_class.Typo_tag
    [ ("docs/a.md", "# A\n\n@reck x\n") ]
    [
      "docs/a.md:3:1-3:8 | finding:typo-tag:line:docs/a.md@L3 | @reck is not a \
       tag word of sinter | fix: @ack";
    ]

let ignored_tag_sits_at_a_later_paragraph () =
  check Finding_class.Ignored_tag
    [ ("docs/a.md", "# A\n\nText.\n\n@req a v1\n\n> @req b v1\n") ]
    [
      "docs/a.md:5:1-5:10 | finding:ignored-tag:line:docs/a.md@L5 | sinter \
       reads tags only in the first paragraph of a section or a list item";
    ]

let invalid_target_names_why_the_target_fails () =
  check Finding_class.Invalid_target
    [
      ( "docs/a.md",
        "# A\n\n\
         @req a! v1\n\
         @cites xy/1\n\
         @cites gh/0\n\
         @cites gh/12\n\
         @satisfies b_ v1\n\
         @ack retired x 1234abcd\n\
         @deprecated now\n" );
      (".plans/p.md", "# P\n\n@plan p/q\n\n## S\n\n@scope lib/**\n@req Q!\n");
    ]
    [
      ".plans/p.md:3:1-3:10 | finding:invalid-target:tag:.plans/p.md@L3C1 | \
       p/q is not a valid slug";
      ".plans/p.md:8:1-8:8 | finding:invalid-target:tag:.plans/p.md@L8C1 | Q! \
       is not a valid slug";
      "docs/a.md:3:1-3:11 | finding:invalid-target:tag:docs/a.md@L3C1 | a! is \
       not a valid slug";
      "docs/a.md:4:1-4:12 | finding:invalid-target:tag:docs/a.md@L4C1 | the \
       manifest declares no namespace xy";
      "docs/a.md:5:1-5:12 | finding:invalid-target:tag:docs/a.md@L5C1 | 0 does \
       not match the id pattern of the namespace gh";
      "docs/a.md:7:1-7:17 | finding:invalid-target:tag:docs/a.md@L7C1 | b_ is \
       not a valid slug";
    ]

let invalid_target_names_the_part_of_a_plan_target_that_fails () =
  let plan path target = (path, "# P\n\n@plan " ^ target ^ "\n") in
  check Finding_class.Invalid_target
    [
      plan ".plans/a.md" "a@3F2A9C";
      plan ".plans/b.md" "b@3f2a9";
      plan ".plans/c.md" "c@3f2a9c0";
      plan ".plans/d.md" "d@3f2a9c@012345";
      plan ".plans/e.md" "e@";
      plan ".plans/f.md" "-f@3f2a9c";
      plan ".plans/g.md" "g@3f2a9c";
      plan ".plans/h.md" "@3f2a9c";
    ]
    [
      ".plans/a.md:3:1-3:15 | finding:invalid-target:tag:.plans/a.md@L3C1 | \
       the plan id after the @ in a@3F2A9C is not six lowercase hex digits";
      ".plans/b.md:3:1-3:14 | finding:invalid-target:tag:.plans/b.md@L3C1 | \
       the plan id after the @ in b@3f2a9 is not six lowercase hex digits";
      ".plans/c.md:3:1-3:16 | finding:invalid-target:tag:.plans/c.md@L3C1 | \
       the plan id after the @ in c@3f2a9c0 is not six lowercase hex digits";
      ".plans/d.md:3:1-3:22 | finding:invalid-target:tag:.plans/d.md@L3C1 | \
       the plan id after the @ in d@3f2a9c@012345 is not six lowercase hex \
       digits";
      ".plans/e.md:3:1-3:9 | finding:invalid-target:tag:.plans/e.md@L3C1 | the \
       plan id after the @ in e@ is not six lowercase hex digits";
      ".plans/f.md:3:1-3:16 | finding:invalid-target:tag:.plans/f.md@L3C1 | -f \
       is not a valid slug";
      ".plans/h.md:3:1-3:14 | finding:invalid-target:tag:.plans/h.md@L3C1 | \
       @3f2a9c has no slug before the @";
    ]

let misplaced_plan_sits_outside_the_first_block_of_a_plan_file () =
  check Finding_class.Misplaced_plan
    [
      ("docs/a.md", "# A\n\n@plan a\n");
      ("docs/b.md", "# B\n\n@plan\n");
      (".plans/p.md", "# P\n\n@plan p\n\n## S\n\n@plan q\n");
      (".plans/q.md", "# Q\n\n@plan q\n");
      (".plans/r.md", "# R\n\n@plan r\n\n## S\n\n@plan\n");
    ]
    [
      ".plans/p.md:7:1-7:8 | finding:misplaced-plan:tag:.plans/p.md@L7C1 | \
       @plan q is not in the first tag block of its file";
      ".plans/r.md:7:1-7:6 | finding:misplaced-plan:tag:.plans/r.md@L7C1 | \
       @plan is not in the first tag block of its file";
      "docs/a.md:3:1-3:8 | finding:misplaced-plan:tag:docs/a.md@L3C1 | @plan a \
       is not in a file under .plans/";
      "docs/b.md:3:1-3:6 | finding:misplaced-plan:tag:docs/b.md@L3C1 | @plan \
       is not in a file under .plans/";
    ]

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
      ".plans/q.md:3:1-3:8 | finding:duplicate:tag:.plans/q.md@L3C1 | an open \
       plan with the slug p is declared earlier";
      ".plans/q.md:9:1-9:8 | finding:duplicate:line:.plans/q.md@L9 | the slug \
       one of step:P/one is declared earlier";
      "docs/b.md:3:1-3:13 | finding:duplicate:tag:docs/b.md@L3C1 | the slug \
       Auth of req:Auth is declared earlier";
      "docs/b.md:7:1-7:13 | finding:duplicate:tag:docs/b.md@L7C1 | the slug \
       auth of design:auth is declared earlier";
    ]

let duplicate_of_plans_names_the_full_form_or_the_open_slug () =
  let plan path target = (path, "# P\n\n@plan " ^ target ^ "\n") in
  check Finding_class.Duplicate
    [
      plan ".plans/a.md" "up@3f2a9c";
      plan ".plans/b.md" "up@3f2a9c";
      plan ".plans/c.md" "Up@012345";
      plan ".plans/d.md" "down";
      plan ".plans/e.md" "down";
      plan ".plans/f.md" "side@012345";
    ]
    [
      ".plans/b.md:3:1-3:16 | finding:duplicate:tag:.plans/b.md@L3C1 | a plan \
       with the full form up@3f2a9c is declared earlier";
      ".plans/c.md:3:1-3:16 | finding:duplicate:tag:.plans/c.md@L3C1 | an open \
       plan with the slug up is declared earlier";
      ".plans/e.md:3:1-3:11 | finding:duplicate:tag:.plans/e.md@L3C1 | a plan \
       with the full form down is declared earlier";
    ]

let missing_plan_id_pastes_an_id_from_the_base_and_the_path () =
  let plan path target = (path, "# P\n\n@plan " ^ target ^ "\n") in
  check Finding_class.Missing_plan_id
    [
      plan ".plans/p.md" "p";
      plan ".plans/q.md" "q@3f2a9c";
      plan ".plans/work.md" "Work";
      plan ".plans/x.md" "x@3F2A9C";
      ("old/.plans/o.md", "# O\n\n@plan o\n");
    ]
    ~extra:"[paths]\nhistorical = [\"old/**\"]\n"
    [
      ".plans/p.md:3:1-3:8 | finding:missing-plan-id:plan:p | the plan p has \
       no plan id | fix: @plan p@a153a1";
      ".plans/work.md:3:1-3:11 | finding:missing-plan-id:plan:Work | the plan \
       Work has no plan id | fix: @plan Work@321afa";
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
      "docs/a.md:7:1-7:13 | finding:unpinned:satisfies:req:a->a | @satisfies a \
       names no revision | fix: @satisfies a v3";
      "docs/a.md:9:1-9:17 | finding:unpinned:refines:req:a->nothing | @refines \
       nothing names no revision";
      "docs/a.md:11:1-11:17 | finding:unpinned:supersedes:req:a->gh/1 | \
       @supersedes gh/1 names no revision";
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
      "docs/a.md:13:1-13:7 | finding:cycle:req:a | req:a is in a cycle with \
       req:b, req:c";
      "docs/a.md:18:1-18:12 | finding:cycle:decision:d | decision:d is in a \
       cycle with itself";
    ]

let retired_of_a_status_pastes_the_ack_of_its_block () =
  check Finding_class.Retired
    [
      ( "docs/a.md",
        "# A\n\n@decision old\n@deprecated\n\n## B\n\n@decision new\n" );
      ("docs/b.md", "# B\n\n@cites old\n@cites new\n@refines old v1\n");
    ]
    [
      "docs/b.md:3:1-3:11 | finding:retired:cites:site:docs/b.md#b->old | \
       decision:old is deprecated | fix: @ack retired old 393d3530";
    ]

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

let retired_of_a_superseded_item_names_its_successor () =
  check Finding_class.Retired
    [
      superseded;
      ( "docs/b.md",
        "# B\n\n@cites gone\n@cites gone v1\n@cites x v1\n@cites y\n" );
    ]
    [
      "docs/b.md:3:1-3:12 | finding:retired:cites:site:docs/b.md#b->gone | \
       decision:gone is superseded by decision:new | fix: @cites new";
      "docs/b.md:4:1-4:15 | finding:retired:cites:site:docs/b.md#b->gone | \
       decision:gone is superseded by decision:new | fix: @cites new v3";
      "docs/b.md:5:1-5:12 | finding:retired:cites:site:docs/b.md#b->x | \
       decision:x is superseded by decision:z | fix: @cites z v1";
      "docs/b.md:6:1-6:9 | finding:retired:cites:site:docs/b.md#b->y | \
       decision:y is superseded by decision:z | fix: @cites z";
    ]

let retired_names_each_successor_in_the_order_of_their_ids () =
  check Finding_class.Retired
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
      "docs/b.md:3:1-3:12 | finding:retired:cites:site:docs/b.md#b->a | \
       decision:a is superseded by decision:b, decision:c | fix: @cites b v2 \
       or @cites c v1";
    ]

let wrong_source_sits_at_a_citation_without_its_source () =
  check Finding_class.Wrong_source
    [
      ("docs/a.md", "# A\n\n@req a v1\n@verifies a v1\n@refines a v1\n");
      ( "docs/b.md",
        "# B\n\nText.\n\n- @refines a v1\n- @supersedes a v1\n- @cites a\n" );
    ]
    [
      "docs/a.md:4:1-4:15 | finding:wrong-source:verifies:req:a->a | @verifies \
       a needs a test as its source";
      "docs/b.md:5:3-5:16 | finding:wrong-source:refines:site:docs/b.md#b->a | \
       @refines a needs a declaration that holds it";
      "docs/b.md:6:3-6:19 | \
       finding:wrong-source:supersedes:site:docs/b.md#b->a | @supersedes a \
       needs a declaration that holds it";
    ]

let untraced_names_what_is_missing () =
  check Finding_class.Untraced
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
      "docs/a.md:3:1-3:7 | finding:untraced:req:a | nothing satisfies req:a, \
       and nothing verifies it";
      "docs/a.md:7:1-7:10 | finding:untraced:design:b | nothing verifies \
       design:b";
    ];
  check Finding_class.Untraced
    [
      ("docs/a.md", "# A\n\n@req a\n");
      ("docs/b.md", "# B\n\nText.\n\n- @verifies a v1\n");
    ]
    [ "docs/a.md:3:1-3:7 | finding:untraced:req:a | nothing satisfies req:a" ]

let plan steps =
  ( ".plans/p.md",
    "# P\n\n@plan p\n@scope lib/**, docs/, bin/main.ml, src/*/**, !lib/x/**\n"
    ^ steps )

let scope_outside_plan_names_the_globs_outside_the_plan () =
  check Finding_class.Scope_outside_plan
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
      ".plans/p.md:11:1-11:7 | finding:scope-outside-plan:step:p/out | \
       step:p/out has bin/**, bin/, lib, test/a.ml, src/a/*.ml, lib/? in its \
       scope, outside the scope of the plan";
    ];
  check Finding_class.Scope_outside_plan
    [
      (".plans/p.md", "# P\n\n@plan p\n\n## S\n\n@scope a/**\n@req a\n");
      ( ".plans/q.md",
        "# Q\n\n@plan q\n@scope **\n\n## S\n\n@scope a/**, b/c, b/, x/?\n" );
      ( ".plans/r.md",
        "# R\n\n@plan r\n@scope a/?, pkg/*\n\n## S\n\n@scope a/b, pkg/, pkg/a\n"
      );
    ]
    [
      ".plans/p.md:5:1-5:5 | finding:scope-outside-plan:step:p/s | step:p/s \
       has a/** in its scope, outside the scope of the plan";
      ".plans/q.md:6:1-6:5 | finding:scope-outside-plan:step:q/s | step:q/s \
       has x/? in its scope, outside the scope of the plan";
      ".plans/r.md:6:1-6:5 | finding:scope-outside-plan:step:r/s | step:r/s \
       has a/b, pkg/ in its scope, outside the scope of the plan";
    ]

let step_without_promises_sits_at_each_step_without_promises () =
  let files =
    [
      plan
        "\n\
         ## Tidy\n\n\
         @scope lib/**\n\n\
         ## Write\n\n\
         @req a\n\n\
         ## Bare ##\n\n\
         @scope docs/\n";
      ( ".plans/q.md",
        "# Q\n\n@plan q@0a1b2c\n@scope **\n\n## Only\n\n@scope a/**\n" );
    ]
  in
  check ~extra:"[proof]\nstep = \"promises\"\n"
    Finding_class.Step_without_promises files
    [
      ".plans/p.md:6:1-6:8 | finding:step-without-promises:step:p/tidy | \
       step:p/tidy has no promise, and proof.step is \"promises\"";
      ".plans/p.md:14:1-14:11 | finding:step-without-promises:step:p/bare | \
       step:p/bare has no promise, and proof.step is \"promises\"";
      ".plans/q.md:6:1-6:8 | finding:step-without-promises:step:q@0a1b2c/only \
       | step:q@0a1b2c/only has no promise, and proof.step is \"promises\"";
    ];
  List.iter
    (fun extra -> check ~extra Finding_class.Step_without_promises files [])
    [ ""; "[proof]\nstep = \"change\"\n"; "[proof]\nstep = \"approval\"\n" ]

let step_without_promises_is_not_ackable_and_has_no_fix () =
  List.iter
    (fun (finding : Finding.t) ->
      if finding.finding_class = Finding_class.Step_without_promises then begin
        Alcotest.(check bool) "not ackable" false finding.ackable;
        Alcotest.(check bool) "no fix" true (Option.is_none finding.fix)
      end)
    (findings ~extra:"[proof]\nstep = \"promises\"\n"
       [ plan "\n## Tidy\n\n@scope lib/**\n" ])

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
      ".plans/p.md:12:1-12:7 | finding:scope-overlap:step:p/two | step:p/two \
       shares promises and scope with step:p/one";
      ".plans/p.md:22:1-22:8 | finding:scope-overlap:step:p/four | step:p/four \
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

let promise_out_of_scope_names_the_facts_outside () =
  check ~extra:"[paths]\ndecision = [\"docs/decisions/\"]\n"
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
       finding:promise-out-of-scope:promise:step:p/one:req:a | the promise \
       req:a is met only outside the scope of step:p/one";
      ".plans/p.md:11:1-11:12 | \
       finding:promise-out-of-scope:promise:step:p/one:decision:d | the \
       promise decision:d is met only outside the scope of step:p/one";
      ".plans/p.md:12:1-12:9 | \
       finding:promise-out-of-scope:promise:step:p/one:cites:a | the promise \
       cites:a is met only outside the scope of step:p/one";
    ]

let a_live_ack_accepts_its_finding () =
  let files ack =
    [
      ("docs/a.md", "# A\n\n@decision old\n@deprecated\n");
      ("docs/b.md", "# B\n\n@cites old\n@cites x\n" ^ ack);
      ("docs/c.md", "# C\n\n@decision x\n@deprecated\n");
    ]
  in
  check Finding_class.Retired (files "")
    [
      "docs/b.md:3:1-3:11 | finding:retired:cites:site:docs/b.md#b->old | \
       decision:old is deprecated | fix: @ack retired old c55c7593";
      "docs/b.md:4:1-4:9 | finding:retired:cites:site:docs/b.md#b->x | \
       decision:x is deprecated | fix: @ack retired x c55c7593";
    ];
  check Finding_class.Retired
    (files "@ack retired old c55c7593\n")
    [
      "docs/b.md:4:1-4:9 | finding:retired:cites:site:docs/b.md#b->x | \
       decision:x is deprecated | fix: @ack retired x c55c7593";
    ];
  check Finding_class.Retired (files "@ack retired c55c7593d\n") [];
  check Finding_class.Retired (files "@ack retired\tc55c7593\n") []

let a_void_ack_accepts_nothing () =
  let files ack =
    [
      ("docs/a.md", "# A\n\n@decision old\n@deprecated\n");
      ("docs/b.md", "# B\n\n@cites old\n" ^ ack);
    ]
  in
  let finding hash =
    [
      "docs/b.md:3:1-3:11 | finding:retired:cites:site:docs/b.md#b->old | \
       decision:old is deprecated | fix: @ack retired old " ^ hash;
    ]
  in
  check Finding_class.Retired (files "") (finding "ba974016");
  List.iter
    (fun ack -> check Finding_class.Retired (files ack) (finding "ba974016"))
    [
      "@ack retired old 00000000\n";
      "@ack retired old ba97401\n";
      "@ack retired other ba974016\n";
      "@ack dangling old ba974016\n";
      "@ack retiredx ba974016\n";
      "@ack retired old BA974016\n";
    ]

let an_ack_accepts_only_the_findings_of_its_block () =
  check Finding_class.Retired
    [
      ("docs/a.md", "# A\n\n@decision old\n@deprecated\n");
      ( "docs/b.md",
        "# B\n\n@cites old\n\n## C\n\n@cites zz\n@ack retired old ba974016\n" );
      ("docs/c.md", "# C\n\n@cites old\n@ack retired old ba974016\n");
    ]
    [
      "docs/b.md:3:1-3:11 | finding:retired:cites:site:docs/b.md#b->old | \
       decision:old is deprecated | fix: @ack retired old ba974016";
    ]

let retired_ackable files =
  List.filter_map
    (fun (finding : Finding.t) ->
      if finding.finding_class = Finding_class.Retired then
        Some (show finding, finding.ackable)
      else None)
    (findings files)

let an_ack_does_not_accept_the_finding_of_a_superseded_item () =
  let files records ack =
    [ records; ("docs/b.md", "# B\n\n@cites gone\n" ^ ack) ]
  in
  let acks = [ "@ack retired gone 62671b3a\n"; "@ack retired 62671b3a\n" ] in
  List.iter
    (fun ack ->
      Alcotest.(check (list (pair string bool)))
        ack
        [
          ( "docs/b.md:3:1-3:12 | finding:retired:cites:site:docs/b.md#b->gone \
             | decision:gone is superseded by decision:new | fix: @cites new",
            false );
        ]
        (retired_ackable (files superseded ack)))
    ("" :: acks);
  List.iter
    (fun ack ->
      Alcotest.(check (list (pair string bool)))
        ("a status tag, " ^ ack) []
        (retired_ackable
           (files ("docs/a.md", "# A\n\n@decision gone\n@deprecated\n") ack)))
    acks

let an_ack_still_accepts_the_finding_of_an_item_that_a_status_retires () =
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
      ( "docs/b.md:3:1-3:11 | finding:retired:cites:site:docs/b.md#b->old | \
         decision:old is deprecated | fix: @ack retired old 0fda7530",
        true );
      ( "docs/b.md:4:1-4:12 | finding:retired:cites:site:docs/b.md#b->gone | \
         decision:gone is superseded by decision:new | fix: @cites new",
        false );
    ]
    (retired_ackable (files ""));
  Alcotest.(check (list (pair string bool)))
    "the finding of gone"
    [
      ( "docs/b.md:4:1-4:12 | finding:retired:cites:site:docs/b.md#b->gone | \
         decision:gone is superseded by decision:new | fix: @cites new",
        false );
    ]
    (retired_ackable (files "@ack retired 0fda7530\n"))

let all ?extra files = List.map show (findings ?extra files)

let a_lone_carriage_return_stays_in_one_line () =
  Alcotest.(check (list string))
    "the findings"
    [
      "docs/guide.md:3:1-3:15 | finding:invalid-target:tag:docs/guide.md@L3C1 \
       | foo\\rbar is not a valid slug";
    ]
    (all [ ("docs/guide.md", "# Guide\n\n@cites foo\rbar\n") ]);
  Alcotest.(check (list string))
    "the findings of a file with carriage returns for line endings"
    [
      "docs/a.md:1:6-1:32 | finding:invalid-target:tag:docs/a.md@L1C6 | \
       x.\\r\\r## is not a valid slug";
      "docs/a.md:1:23-1:32 | finding:untraced:req:b | nothing satisfies req:b, \
       and nothing verifies it";
    ]
    (all [ ("docs/a.md", "# A\r\r@cites x.\r\r## B\r\r@req b v1\r") ])

let a_line_feed_in_a_path_stays_in_one_line () =
  Alcotest.(check (list string))
    "the findings"
    [
      "docs/a\n\
       b.md:3:1-3:10 | finding:untraced:req:x | nothing satisfies req:x, and \
       nothing verifies it";
      "docs/c.md:3:1-3:10 | finding:duplicate:tag:docs/c.md@L3C1 | the slug x \
       of req:x is declared earlier";
      "docs/c.md:3:1-3:10 | finding:untraced:req:x | nothing satisfies req:x, \
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
      ".plans/p.md:3:1-3:8 | finding:missing-plan-id:plan:p | the plan p has \
       no plan id | fix: @plan p@a153a1";
      ".plans/p.md:6:1-6:5 | finding:scope-outside-plan:step:p/a | step:p/a \
       has src/**\\r in its scope, outside the scope of the plan";
      ".plans/p.md:12:1-12:9 | finding:invalid-target:tag:.plans/p.md@L12C1 | \
       x\\ry is not a valid slug";
      ".plans/p.md:12:1-12:9 | \
       finding:unverified-promise:promise:step:p/b:req:x\ry | the plan \
       promises no @verifies x\\ry";
      ".plans/p.md:13:1-13:7 | \
       finding:promise-out-of-scope:promise:step:p/b:req:z | the promise req:z \
       is met only outside the scope of step:p/b";
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

let an_external_id_with_no_namespace_or_no_id_says_so () =
  check Finding_class.Invalid_target
    [ ("docs/a.md", "# A\n\n@cites /x\n@cites gh/\n@cites zz/\n") ]
    [
      "docs/a.md:3:1-3:10 | finding:invalid-target:tag:docs/a.md@L3C1 | the \
       external id /x names no namespace";
      "docs/a.md:4:1-4:11 | finding:invalid-target:tag:docs/a.md@L4C1 | the \
       external id gh/ names no id";
      "docs/a.md:5:1-5:11 | finding:invalid-target:tag:docs/a.md@L5C1 | the \
       manifest declares no namespace zz";
    ]

let cycle_finds_each_component_once () =
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
      "docs/a.md:3:1-3:7 | finding:cycle:req:a | req:a is in a cycle with req:b";
      "docs/a.md:13:1-13:7 | finding:cycle:req:c | req:c is in a cycle with \
       req:d";
      "docs/a.md:24:1-24:7 | finding:cycle:req:e | req:e is in a cycle with \
       req:f, req:g";
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
    [
      "docs/a.md:13:1-13:7 | finding:cycle:req:b | req:b is in a cycle with \
       req:m, req:z";
    ]

let a_historical_path_gives_no_finding () =
  check ~extra:"[paths]\nhistorical = [\"notes/**\"]\n" Finding_class.Typo_tag
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

let nearest_word_names_the_word_that_the_fix_of_typo_tag_writes () =
  Alcotest.(check (list (option string)))
    "the word of each tag word"
    [ Some "req"; Some "req"; Some "verifies"; None; None; None; None ]
    (List.map Findings.nearest_word
       [ "reqq"; "Req"; "verifie"; "req"; "ack"; "param"; "" ])

module Gen = QCheck2.Gen

let near_word =
  Gen.(
    let* word =
      oneof_list
        [ "req"; "design"; "cites"; "verifies"; "ack"; "scope"; "plan"; "pin" ]
    in
    let* edits = int_bound 3 in
    let rec edit word count =
      if count = 0 then pure word
      else
        let* position = int_bound (String.length word) in
        let* letter = char_range 'a' 'z' in
        let* how = int_bound 2 in
        let before = String.sub word 0 position
        and after = String.sub word position (String.length word - position) in
        let rest () = String.sub after 1 (String.length after - 1) in
        edit
          (match how with
          | 0 -> before ^ String.make 1 letter ^ after
          | 1 when after <> "" -> before ^ rest ()
          | _ when after <> "" -> before ^ String.make 1 letter ^ rest ()
          | _ -> word)
          (count - 1)
    in
    edit word edits)

let nearest_word_is_a_word_of_the_vocabulary_within_two_edits =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:500
       ~name:"nearest_word gives a word of the vocabulary within two edits"
       ~print:(Printf.sprintf "%S") near_word (fun word ->
         match Findings.nearest_word word with
         | None -> true
         | Some nearest ->
             (not (String.equal nearest word))
             && Edit_distance.distance word nearest <= 2
             && Findings.nearest_word nearest = None))

let declared_spelling_names_the_spelling_that_the_fix_of_dangling_writes () =
  let facts =
    Facts.make (manifest "")
      [
        ( "docs/a.md",
          document
            "# A\n\n\
             @req Lock-Out v1\n\n\
             ## B\n\n\
             @design LOCK-out v1\n\n\
             ## C\n\n\
             @rule Rate v1\n\n\
             ## D\n\n\
             @decision kept v1\n" );
      ]
  in
  Alcotest.(check (list (option string)))
    "the spelling of each tag target"
    [ Some "LOCK-out"; None; None; Some "kept"; None; None; None ]
    (List.map
       (Findings.declared_spelling facts)
       [ "lock-out"; "Lock-Out"; "rate"; "KEPT"; "kept"; "gone"; "gh/1" ])

let declared_spelling_gives_the_fix_of_each_dangling_finding =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:200
       ~name:"declared_spelling gives the target of the fix of each dangling"
       ~print:QCheck2.Print.(list string)
       Gen.(
         list_size (int_range 1 6)
           (map2
              (fun word slug -> Printf.sprintf "@%s %s v1" word slug)
              (oneof_list [ "req"; "design"; "rule"; "cites"; "satisfies" ])
              (oneof_list [ "a"; "A"; "b-c"; "B-C"; "b-C"; "d" ])))
       (fun lines ->
         let facts =
           Facts.make (manifest "")
             [
               ( "docs/a.md",
                 document
                   (String.concat ""
                      (List.mapi
                         (fun index line ->
                           Printf.sprintf "# S%d\n\n%s\n\n" index line)
                         lines)) );
             ]
         in
         let spelling = Findings.declared_spelling facts in
         let fixes =
           List.filter_map
             (fun (finding : Finding.t) ->
               if finding.finding_class = Finding_class.Dangling then
                 Some
                   ( Finding.subject_id finding.subject,
                     Option.map Fix.text finding.fix )
               else None)
             (Findings.of_facts facts ~base:base_commit ~not_text:[])
         in
         List.for_all
           (fun ((edge : Facts.edge), _) ->
             match List.assoc_opt (Facts.edge_id edge) fixes with
             | Some fix ->
                 fix
                 = Option.map
                     (fun target -> Printf.sprintf "@%s %s v1" edge.word target)
                     (spelling edge.target_text)
             | None -> spelling edge.target_text = None)
           (Facts.edges facts)))

let case name test = Alcotest.test_case name `Quick test

let of_facts_gives_the_findings_of_tree () =
  let files =
    List.map
      (fun (path, text) -> (path, document text))
      [
        ("docs/a.md", "# A\n\n@req a v1\n@cites missing v1\n@satisfie a v1\n");
        ("docs/b.md", "# B\n\n@verifies a v2\n@satisfies a\n");
        (".plans/p.md", "# P\n\n@plan p\n@scope docs/**\n\n## S\n\n@req z\n");
      ]
  in
  let m = manifest "" in
  let facts = Facts.make m files in
  Alcotest.(check bool)
    "the manifest of the facts" true
    (Facts.manifest facts == m);
  Alcotest.(check bool)
    "the files of the facts" true
    (Facts.files facts == files);
  Alcotest.(check (list string))
    "the findings"
    (List.map show
       (Findings.tree m files ~base:base_commit ~not_text:[ ("docs/c.md", 3) ]))
    (List.map show
       (Findings.of_facts facts ~base:base_commit
          ~not_text:[ ("docs/c.md", 3) ]))

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

let check_parts ?extra finding_class files expected =
  Alcotest.(check (list string))
    (Finding_class.name finding_class)
    expected
    (List.map parts
       (List.filter
          (fun (finding : Finding.t) -> finding.finding_class = finding_class)
          (findings ?extra files)))

let typo_tag_marks_the_word () =
  check_parts Finding_class.Typo_tag
    [ ("docs/a.md", "# A\n\n- @reqq \xc3\xa9 v1\n") ]
    [ "docs/a.md:3 / 3-8 not a tag word" ]

let invalid_target_marks_the_target () =
  check_parts Finding_class.Invalid_target
    [
      ( "docs/a.md",
        "# A\n\n@req a! v1\n@cites xy/1\n@cites gh/0\n@cites /1\n@cites gh/\n"
      );
    ]
    [
      "docs/a.md:3 / 6-8 not a valid slug";
      "docs/a.md:4 / 8-12 no such namespace";
      "docs/a.md:5 / 8-12 does not match the id pattern";
      "docs/a.md:6 / 8-10 names no namespace";
      "docs/a.md:7 / 8-11 names no id";
    ]

let misplaced_plan_marks_the_word () =
  check_parts Finding_class.Misplaced_plan
    [
      ("docs/a.md", "# A\n\n@plan a\n");
      (".plans/p.md", "# P\n\n@plan p\n\n## S\n\n@plan q\n");
    ]
    [
      ".plans/p.md:7 / 1-6 not in the first tag block";
      "docs/a.md:3 / 1-6 not in a file under .plans/";
    ]

let missing_plan_id_marks_the_target () =
  check_parts Finding_class.Missing_plan_id
    [ (".plans/p.md", "# P\n\n@plan  upkeep\n") ]
    [ ".plans/p.md:3 / 8-14 no plan id" ]

let invalid_target_marks_the_target_of_a_plan () =
  check_parts Finding_class.Invalid_target
    [
      (".plans/a.md", "# A\n\n@plan a@3F2A9C\n");
      (".plans/b.md", "# B\n\n@plan @3f2a9c\n");
      (".plans/c.md", "# C\n\n@plan c!@3f2a9c\n");
    ]
    [
      ".plans/a.md:3 / 7-15 not a valid plan id";
      ".plans/b.md:3 / 7-14 no slug before the @";
      ".plans/c.md:3 / 7-16 not a valid slug";
    ]

let duplicate_marks_the_target_and_names_the_first () =
  check_parts Finding_class.Duplicate
    [
      ("docs/b.md", "# B\n\nText.\n\n- @req Auth v1\n");
      ("docs/a.md", "# A\n\n@decision auth\n");
      ( ".plans/q.md",
        "# Q\n\n@plan P\n\n## One\n\n@req x\n\n## One!\n\n@req y\n" );
      (".plans/p.md", "# P\n\n@plan p\n");
    ]
    [
      ".plans/q.md:3 / 7-8 declared again here / first declared here at \
       .plans/p.md:3:1-3:8";
      ".plans/q.md:9 / no mark / first declared here at .plans/q.md:5:1-5:7";
      "docs/b.md:5 / 8-12 declared again here / first declared here at \
       docs/a.md:3:1-3:15";
    ]

let unpinned_marks_the_target_and_names_the_declaration () =
  check_parts Finding_class.Unpinned
    [
      ( "docs/a.md",
        "# A\n\n@req a v3\n\n## B\n\n@satisfies a\n@satisfies gh/1\n" );
    ]
    [
      "docs/a.md:7 / 12-13 no revision / declared here at v3 at \
       docs/a.md:3:1-3:10";
      "docs/a.md:8 / 12-16 no revision";
    ]

let dangling_marks_the_target () =
  check_parts Finding_class.Dangling
    [ ("docs/b.md", "# B\n\n- @cites Login v2\n") ]
    [ "docs/b.md:3 / 10-15 no declaration has this slug" ]

let suspect_marks_the_revision_and_names_the_declaration () =
  check_parts Finding_class.Suspect
    [
      ( "docs/a.md",
        "# A\n\n@req a v2\n\n## B\n\n@cites a v1\n@verifies a\tv3 x\n" );
    ]
    [
      "docs/a.md:7 / 10-12 names v1 / now at v2 at docs/a.md:3:1-3:10";
      "docs/a.md:8 / 13-15 names v3 / now at v2 at docs/a.md:3:1-3:10";
    ]

let retired_marks_the_target_and_names_the_item_and_its_successors () =
  check_parts Finding_class.Retired
    [
      ("docs/a.md", "# A\n\n@decision old\n@deprecated\n");
      ("docs/b.md", "# B\n\n@cites old\n");
    ]
    [
      "docs/b.md:3 / 8-11 cites a retired item / the cited item is deprecated \
       at docs/a.md:3:1-3:14";
    ];
  check_parts Finding_class.Retired
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
      "docs/b.md:3 / 8-9 cites a retired item / a successor at \
       docs/a.md:3:1-3:12 / a successor at docs/a.md:8:1-8:15 / the cited item \
       is superseded at docs/a.md:13:1-13:12";
    ]

let wrong_source_marks_the_word () =
  check_parts Finding_class.Wrong_source
    [
      ("docs/a.md", "# A\n\n@req a v1\n@verifies a v1\n");
      ("docs/b.md", "# B\n\nText.\n\n- @refines a v1\n");
    ]
    [
      "docs/a.md:4 / 1-10 needs a test as its source";
      "docs/b.md:5 / 3-11 needs a declaration that holds it";
    ]

let untraced_marks_the_target () =
  check_parts Finding_class.Untraced
    [
      ("docs/a.md", "# A\n\n@req a\n\n## B\n\n@design b\n");
      ("docs/b.md", "# B\n\nText.\n\n- @satisfies b v1\n");
    ]
    [
      "docs/a.md:3 / 6-7 nothing satisfies it, and nothing verifies it";
      "docs/a.md:7 / 9-10 nothing verifies it";
    ]

let unverified_promise_marks_the_target () =
  check_parts Finding_class.Unverified_promise
    [ (".plans/p.md", "# P\n\n@plan p\n\n## One\n\n@design b\n") ]
    [ ".plans/p.md:7 / 9-10 no promised @verifies" ]

let promise_out_of_scope_marks_the_target_and_names_each_fact () =
  check_parts Finding_class.Promise_out_of_scope
    [
      (".plans/p.md", "# P\n\n@plan p\n\n## One\n\n@scope lib/**\n@req a\n");
      ("docs/b.md", "# B\n\n@req a v1\n");
      ("docs/a.md", "# A\n\nText.\n\n- @req a v1\n");
    ]
    [
      ".plans/p.md:8 / 6-7 met only outside the scope of the step / meets the \
       promise outside the scope at docs/a.md:5:3-5:12 / meets the promise \
       outside the scope at docs/b.md:3:1-3:10";
    ]

let cycle_names_each_other_member () =
  check_parts Finding_class.Cycle
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
         @supersedes d v1\n" );
    ]
    [
      "docs/a.md:13 / no mark / part of the cycle at docs/a.md:3:1-3:7 / part \
       of the cycle at docs/a.md:8:1-8:7";
      "docs/a.md:18 / no mark";
    ]

let scope_overlap_names_each_earlier_step () =
  check_parts Finding_class.Scope_overlap
    [
      ( ".plans/p.md",
        "# P\n\n\
         @plan p\n\
         @scope lib/**\n\n\
         ## One\n\n\
         @scope lib/a/**\n\
         @req a\n\n\
         ## Two\n\n\
         @req b\n\n\
         ## Three\n\n\
         @req a\n\
         @req b\n" );
    ]
    [
      ".plans/p.md:15 / no mark / shares promises and scope at \
       .plans/p.md:6:1-6:7 / shares promises and scope at \
       .plans/p.md:11:1-11:7";
    ]

let tag_line =
  Gen.map
    (fun ((prefix, word), (blank, target), revision) ->
      prefix ^ "@" ^ word ^ blank ^ target ^ revision)
    (Gen.triple
       (Gen.pair
          (Gen.oneof_list [ ""; "- "; "* [ ] "; "  "; "\t" ])
          (Gen.oneof_list
             [
               "req";
               "design";
               "decision";
               "rule";
               "cites";
               "satisfies";
               "verifies";
               "refines";
               "supersedes";
               "plan";
               "deprecated";
               "reqq";
               "Req";
             ]))
       (Gen.pair
          (Gen.oneof_list [ " "; "\t"; " \t " ])
          (Gen.oneof_list
             [
               "a";
               "b";
               "Auth";
               "auth";
               "x!";
               "gh/1";
               "gh/0";
               "xy/1";
               "/1";
               "\xc3\xa9t\xc3\xa9";
               "";
             ]))
       (Gen.oneof_list [ ""; " v1"; " v2"; "\tv3 text \xc3\xa9"; " v0" ]))

let section =
  Gen.oneof_weighted
    [
      ( 6,
        Gen.map2
          (fun heading lines ->
            heading ^ "\n\n" ^ String.concat "\n" lines ^ "\n")
          (Gen.oneof_list [ "# A"; "## B"; "## C"; "### D" ])
          (Gen.list_size (Gen.int_range 1 4) tag_line) );
      (1, Gen.return "## R\n\n@req ra\n@refines rb v1\n");
      (1, Gen.return "## S\n\n@req rb\n@refines ra v1\n");
      (1, Gen.return "## O\n\n@decision old\n@deprecated\n");
      (1, Gen.return "## N\n\n@decision new v2\n@supersedes old v1\n");
      (1, Gen.return "## U\n\n@cites old v1\n@cites lockout v1\n");
    ]

let file_text =
  Gen.map (String.concat "\n") (Gen.list_size (Gen.int_range 1 4) section)

let generated_tree =
  Gen.map4
    (fun a b c steps ->
      [
        ("docs/a.md", a);
        ("docs/b.md", b);
        ("src/c.md", c);
        (".plans/p.md", "# P\n\n@plan p\n@scope docs/**\n\n" ^ steps);
      ])
    file_text file_text file_text file_text

let renamed_in (base, tree) =
  let add text files =
    List.map
      (fun (path, content) ->
        if String.equal path "docs/a.md" then (path, content ^ "\n" ^ text)
        else (path, content))
      files
  in
  ( add "## L\n\n@req lockout v1 Lock it.\n" base,
    add "## L\n\n@req account v2 Lock it.\n" tree )

let print_tree files =
  String.concat "\n"
    (List.map (fun (path, text) -> "== " ^ path ^ "\n" ^ text) files)

let characters line =
  let rec go offset acc =
    if offset >= String.length line then Array.of_list (List.rev acc)
    else
      let rec next at =
        if at < String.length line && Char.code line.[at] land 0xC0 = 0x80 then
          next (at + 1)
        else at
      in
      let stop = next (offset + 1) in
      go stop (String.sub line offset (stop - offset) :: acc)
  in
  go 0 []

let marks_hold files (finding : Finding.t) =
  let texts =
    List.map (fun (path, text) -> (path, Line_index.make text)) files
  in
  let in_tree (place : Finding.place) =
    match List.assoc_opt place.path texts with
    | Some lines ->
        place.span.start.line >= 1
        && place.span.stop.line <= Line_index.count lines
    | None -> false
  in
  let mark_holds =
    match (finding.mark, finding.place) with
    | None, _ -> true
    | Some _, None -> false
    | Some { start; stop; _ }, Some place -> (
        match List.assoc_opt place.path texts with
        | None -> false
        | Some lines ->
            let line = place.span.start.line in
            let content = characters (Line_index.content lines line) in
            let text =
              String.concat ""
                (Array.to_list (Array.sub content (start - 1) (stop - start)))
            in
            let tag =
              Array.to_list (document (Line_index.text lines)).tags
              |> List.find (fun (tag : Markdown.tag) ->
                  tag.span.start.line = line)
            in
            List.mem text
              ((("@" ^ tag.word) :: Option.to_list tag.target)
              @ Option.to_list
                  (Option.map (fun rev -> "v" ^ string_of_int rev) tag.rev)))
  in
  mark_holds
  && List.for_all
       (fun (related : Finding.related) ->
         Option.fold ~none:true ~some:in_tree related.place)
       finding.related

let marks_and_related_places_hold_on_any_tree =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:300
       ~name:
         "on any tree, each mark covers a part of its tag, and each related \
          place lies in the tree"
       ~print:(fun (base, tree) ->
         print_tree base ^ "\n==== tree\n" ^ print_tree tree)
       (Gen.map
          (fun (base, tree, rename) ->
            if rename then renamed_in (base, tree) else (base, tree))
          (Gen.triple generated_tree generated_tree Gen.bool))
       (fun (base, tree) ->
         let facts files =
           Facts.make (manifest "")
             (List.map (fun (path, text) -> (path, document text)) files)
         in
         let tree_facts = facts tree in
         List.for_all (marks_hold tree)
           (Adjudicator.classes ~base:(facts base) tree_facts
              (Findings.of_facts tree_facts ~base:base_commit ~not_text:[]))))

let tests =
  [
    marks_and_related_places_hold_on_any_tree;
    Alcotest.test_case "typo-tag marks the word" `Quick typo_tag_marks_the_word;
    Alcotest.test_case "invalid-target marks the target" `Quick
      invalid_target_marks_the_target;
    Alcotest.test_case "misplaced-plan marks the word" `Quick
      misplaced_plan_marks_the_word;
    Alcotest.test_case "missing-plan-id marks the target" `Quick
      missing_plan_id_marks_the_target;
    Alcotest.test_case "invalid-target marks the target of a plan" `Quick
      invalid_target_marks_the_target_of_a_plan;
    Alcotest.test_case "duplicate marks the target and names the first" `Quick
      duplicate_marks_the_target_and_names_the_first;
    Alcotest.test_case "unpinned marks the target and names the declaration"
      `Quick unpinned_marks_the_target_and_names_the_declaration;
    Alcotest.test_case "dangling marks the target" `Quick
      dangling_marks_the_target;
    Alcotest.test_case "suspect marks the revision and names the declaration"
      `Quick suspect_marks_the_revision_and_names_the_declaration;
    Alcotest.test_case
      "retired marks the target and names the item and its successors" `Quick
      retired_marks_the_target_and_names_the_item_and_its_successors;
    Alcotest.test_case "wrong-source marks the word" `Quick
      wrong_source_marks_the_word;
    Alcotest.test_case "untraced marks the target" `Quick
      untraced_marks_the_target;
    Alcotest.test_case "unverified-promise marks the target" `Quick
      unverified_promise_marks_the_target;
    Alcotest.test_case
      "promise-out-of-scope marks the target and names each fact" `Quick
      promise_out_of_scope_marks_the_target_and_names_each_fact;
    Alcotest.test_case "cycle names each other member" `Quick
      cycle_names_each_other_member;
    Alcotest.test_case "scope-overlap names each earlier step" `Quick
      scope_overlap_names_each_earlier_step;
    case "of_facts gives the findings of tree"
      of_facts_gives_the_findings_of_tree;
    case "parse-error sits at each error and at a file that is not text"
      parse_error_sits_at_each_error_and_at_a_file_that_is_not_text;
    case "typo-tag names the nearest word" typo_tag_names_the_nearest_word;
    case "nearest_word names the word that the fix of typo-tag writes"
      nearest_word_names_the_word_that_the_fix_of_typo_tag_writes;
    nearest_word_is_a_word_of_the_vocabulary_within_two_edits;
    case "declared_spelling names the spelling that the fix of dangling writes"
      declared_spelling_names_the_spelling_that_the_fix_of_dangling_writes;
    declared_spelling_gives_the_fix_of_each_dangling_finding;
    case "typo-tag takes the first word in byte order of two equally near"
      typo_tag_takes_the_first_word_in_byte_order_of_two_equally_near;
    case "ignored-tag sits at a later paragraph"
      ignored_tag_sits_at_a_later_paragraph;
    case "invalid-target names why the target fails"
      invalid_target_names_why_the_target_fails;
    case "misplaced-plan sits outside the first block of a plan file"
      misplaced_plan_sits_outside_the_first_block_of_a_plan_file;
    case "invalid-target names the part of a plan target that fails"
      invalid_target_names_the_part_of_a_plan_target_that_fails;
    case "duplicate sits at each later member of a group"
      duplicate_sits_at_each_later_member_of_a_group;
    case "duplicate of plans names the full form or the open slug"
      duplicate_of_plans_names_the_full_form_or_the_open_slug;
    case "missing-plan-id pastes an id from the base and the path"
      missing_plan_id_pastes_an_id_from_the_base_and_the_path;
    case "unpinned pastes the revision of the target"
      unpinned_pastes_the_revision_of_the_target;
    case "dangling names the spelling that differs in case"
      dangling_names_the_spelling_that_differs_in_case;
    case "suspect pastes the current revision"
      suspect_pastes_the_current_revision;
    case "cycle names its smallest member and the others"
      cycle_names_its_smallest_member_and_the_others;
    case "retired of a status pastes the ack of its block"
      retired_of_a_status_pastes_the_ack_of_its_block;
    case "retired of a superseded item names its successor"
      retired_of_a_superseded_item_names_its_successor;
    case "retired names each successor in the order of their ids"
      retired_names_each_successor_in_the_order_of_their_ids;
    case "wrong-source sits at a citation without its source"
      wrong_source_sits_at_a_citation_without_its_source;
    case "untraced names what is missing" untraced_names_what_is_missing;
    case "scope-outside-plan names the globs outside the plan"
      scope_outside_plan_names_the_globs_outside_the_plan;
    case "scope-overlap sits at the later step"
      scope_overlap_sits_at_the_later_step;
    case "unverified-promise sits at a promise with no verifies"
      unverified_promise_sits_at_a_promise_with_no_verifies;
    case "promise-out-of-scope names the facts outside"
      promise_out_of_scope_names_the_facts_outside;
    case "a live ack accepts its finding" a_live_ack_accepts_its_finding;
    case "a void ack accepts nothing" a_void_ack_accepts_nothing;
    case "an ack accepts only the findings of its block"
      an_ack_accepts_only_the_findings_of_its_block;
    case "an ack does not accept the finding of a superseded item"
      an_ack_does_not_accept_the_finding_of_a_superseded_item;
    case "an ack still accepts the finding of an item that a status retires"
      an_ack_still_accepts_the_finding_of_an_item_that_a_status_retires;
    case "a lone carriage return stays in one line"
      a_lone_carriage_return_stays_in_one_line;
    case "a line feed in a path stays in one line"
      a_line_feed_in_a_path_stays_in_one_line;
    case "a control character of a plan stays in one line"
      a_control_character_of_a_plan_stays_in_one_line;
    case "an external id with no namespace or no id says so"
      an_external_id_with_no_namespace_or_no_id_says_so;
    case "cycle finds each component once" cycle_finds_each_component_once;
    case "cycle takes its subject by id, not by place"
      cycle_takes_its_subject_by_id_not_by_place;
    case "a historical path gives no finding" a_historical_path_gives_no_finding;
    case "step-without-promises sits at each step without promises"
      step_without_promises_sits_at_each_step_without_promises;
    case "step-without-promises is not ackable and has no fix"
      step_without_promises_is_not_ackable_and_has_no_fix;
    case "the findings are sorted" the_findings_are_sorted;
  ]
