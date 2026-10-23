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
      (".plans/p.md", "# P\n\n@plan p/q\n\n## S\n\n@req Q!\n");
    ]
    [
      ".plans/p.md:3:1-3:10 | finding:bad-target:tag:.plans/p.md@L3C1 | p/q is \
       not a valid slug";
      ".plans/p.md:7:1-7:8 | finding:bad-target:tag:.plans/p.md@L7C1 | Q! is \
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
    case "a historical path gives no finding" a_historical_path_gives_no_finding;
    case "the findings are sorted" the_findings_are_sorted;
  ]
