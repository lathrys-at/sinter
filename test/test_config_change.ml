(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 200) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let parse text =
  match Toml.parse text with
  | Ok table -> table
  | Error error -> Alcotest.failf "not TOML: %s" (Toml.error_message error)

let no_plan _ = false

let side ?(plan_file = no_plan) text =
  Config_change.side ~plan_file ~location:"sinter.toml" (parse text)

let value_text = function
  | Config_change.String text -> Printf.sprintf "%S" text
  | Config_change.Boolean flag -> string_of_bool flag

let entries ?plan_file text =
  List.map
    (fun (id, value) -> id ^ " " ^ value_text value)
    (Config_change.entries (side ?plan_file text))

let changes base now = Config_change.changes ~base:(side base) (side now)
let details base now = List.map Config_change.detail (changes base now)
let strings = Alcotest.(list string)

let defaults =
  [
    "setting:check.warn-only false";
    "setting:default-branch \"main\"";
    "setting:proof.decision \"declaration\"";
    "setting:proof.design \"declaration\"";
    "setting:proof.plan \"declaration\"";
    "setting:proof.req \"declaration\"";
    "setting:proof.step \"change\"";
    "setting:proof.verifies \"whole-run\"";
  ]

let with_defaults written =
  let written_ids =
    List.map (fun entry -> List.hd (String.split_on_char ' ' entry)) written
  in
  List.sort compare
    (written
    @ List.filter
        (fun entry ->
          not (List.mem (List.hd (String.split_on_char ' ' entry)) written_ids))
        defaults)

let an_empty_manifest_has_every_default () =
  Alcotest.check strings "the entries" defaults (entries "")

let every_setting_gives_its_entries () =
  Alcotest.check strings "the entries"
    [
      "gate:merged/cycle \"off\"";
      "gate:review/dangling \"warn\"";
      "setting:check.warn-only true";
      "setting:default-branch \"trunk\"";
      "setting:paths.decision=docs/decisions/ \"docs/decisions/\"";
      "setting:paths.exempt=gen/ \"gen/\"";
      "setting:paths.historical=docs/devlog/ \"docs/devlog/\"";
      "setting:proof.agent-markers=MY_AGENT \"MY_AGENT\"";
      "setting:proof.decision \"declaration\"";
      "setting:proof.design \"declaration\"";
      "setting:proof.plan \"approval\"";
      "setting:proof.req \"approval\"";
      "setting:proof.step \"promises\"";
      "setting:proof.verifies \"each-test\"";
      "setting:scan.namespaces.gh \"[1-9][0-9]*\"";
      "setting:scan.packs.markdown.files=!old/ \"!old/\"";
      "setting:scan.packs.markdown.files=**/*.md \"**/*.md\"";
      "setting:scan.packs.ocaml.files=**/*.ml \"**/*.ml\"";
      "setting:scan.packs.ocaml.runners=dune-test \"dune-test\"";
      "setting:scan.packs.ocaml.version \"1.2\"";
    ]
    (entries
       "sinter-spec = \"1.0\"\n\
        default-branch = \"trunk\"\n\
        [scan]\n\
        packs.markdown.files = [\"**/*.md\", \"!old/\"]\n\
        packs.ocaml.files = [\"**/*.ml\"]\n\
        packs.ocaml.version = \"1.2\"\n\
        packs.ocaml.runners.dune-test = { timeout = 5 }\n\
        namespaces.gh = \"[1-9][0-9]*\"\n\
        [paths]\n\
        exempt = [\"gen/\"]\n\
        historical = [\"docs/devlog/\"]\n\
        decision = [\"docs/decisions/\"]\n\
        [proof]\n\
        req = \"approval\"\n\
        plan = \"approval\"\n\
        design = \"declaration\"\n\
        agent-markers = [\"MY_AGENT\"]\n\
        verifies = \"each-test\"\n\
        step = \"promises\"\n\
        [check]\n\
        warn-only = true\n\
        tiers.review.dangling = \"warn\"\n\
        tiers.merged.cycle = \"off\"\n")

let a_built_in_member_gives_no_entry () =
  Alcotest.check strings "the entries"
    (with_defaults
       [
         "setting:paths.exempt=docs/ \"docs/\"";
         "setting:paths.historical=old/ \"old/\"";
       ])
    (entries
       ~plan_file:(fun path -> path = ".plans/p.md")
       "[paths]\n\
        historical = [\".plans/**/*.log.md\", \"old/\"]\n\
        exempt = [\".plans/p.md\", \"sinter.toml\", \"sinter.lock\", \"docs/\"]\n")

let a_member_written_twice_gives_one_entry () =
  Alcotest.check strings "the entries"
    (with_defaults [ "setting:proof.agent-markers=A \"A\"" ])
    (entries "[proof]\nagent-markers = [\"A\", \"A\"]\n");
  match changes "" "[proof]\nagent-markers = [\"A\", \"B\", \"A\"]\n" with
  | [ first; _ ] -> (
      match first.written with
      | Some span ->
          Alcotest.(check (pair int int))
            "the first place" (2, 18)
            (span.start.line, span.start.column)
      | None -> Alcotest.fail "the member has no place")
  | other -> Alcotest.failf "%d changes" (List.length other)

let what_the_base_side_leaves_out =
  [
    ("a key of no place", "colour = \"red\"\n[scan]\nx = 1\n[check]\ny = 2\n");
    ("sinter-spec", "sinter-spec = \"1.0\"\n");
    ("a default branch of the wrong type", "default-branch = 1\n");
    ( "a table of the wrong type",
      "scan = 1\ncheck = \"x\"\npaths = []\nproof = true\n" );
    ("an array of tables", "[[scan]]\nx = 1\n[[check.tiers]]\n");
    ("a pack of the wrong type", "[scan.packs]\nocaml = 1\n");
    ("packs of the wrong type", "[scan]\npacks = 2\n");
    ( "a pack name that is not a name",
      "[scan]\n\
       packs.\"a.b\".files = [\"x\"]\n\
       packs.\"a=b\".version = \"1.0\"\n\
       packs.Big.files = [\"y\"]\n" );
    ( "files that are not an array of strings",
      "[scan]\n\
       packs.a.files = \"x\"\n\
       packs.b.files = [1, 2.5, true, [\"x\"], { k = \"v\" }, 1979-05-27]\n" );
    ("a version of the wrong type", "[scan]\npacks.ocaml.version = 1.0\n");
    ( "the version and the runners of markdown",
      "[scan]\n\
       packs.markdown.version = \"1.0\"\n\
       packs.markdown.runners.vitest = {}\n" );
    ( "a runner that is not a table or not a name",
      "[scan]\npacks.ts.runners.vitest = true\npacks.ts.runners.\"a.b\" = {}\n"
    );
    ( "a runners key that is not a table",
      "[scan]\npacks.ts.runners = [\"vitest\"]\n" );
    ( "a namespace that is not a name or not a string",
      "[scan]\n\
       namespaces.\"a=b\" = \"x\"\n\
       namespaces.gh = 7\n\
       namespaces.\"g h\" = \"x\"\n" );
    ("a warn-only of the wrong type", "[check]\nwarn-only = \"true\"\n");
    ( "a path set of the wrong type",
      "[paths]\nhistorical = \"old/\"\nexempt = { a = 1 }\ndecision = true\n" );
    ( "tiers that Sinter does not know",
      "[check.tiers]\n\
       review.dangeling = \"warn\"\n\
       gate.dangling = \"warn\"\n\
       review.dangling = \"hard\"\n\
       review.cycle = 2\n\
       merged.code-drift = \"warn\"\n\
       turn.config-changed = \"off\"\n\
       review.pack-mismatch = \"warn\"\n" );
    ("a gate of the wrong type", "[check.tiers]\nmerged = \"warn\"\n");
    ("a tier table of the wrong type", "[check]\ntiers = 3\n");
    ( "locations of no kind",
      "[paths]\nplan = [\"x\"]\nissue = [\"y\"]\nreq = \"z\"\n" );
    ( "approvals of no kind or of no word",
      "[proof]\n\
       test = \"approval\"\n\
       Req = \"approval\"\n\
       req = 3\n\
       plan = \"yes\"\n\
       design = [\"approval\"]\n" );
    ("agent markers that are not strings", "[proof]\nagent-markers = [1]\n");
    ("a verifies that is not a word", "[proof]\nverifies = \"always\"\n");
    ("a verifies of the wrong type", "[proof]\nverifies = true\n");
    ("a step that is not a word", "[proof]\nstep = \"approve\"\n");
    ("a step of the wrong type", "[proof]\nstep = [\"promises\"]\n");
    ( "the tables and keys of an older layout",
      "[plan]\n\
       exempt = [\"a/\"]\n\
       locations.decision = [\"d/\"]\n\
       [ledger]\n\
       approval-required = [\"req\"]\n\
       agent-markers = [\"A\"]\n\
       [evidence]\n\
       test-coverage = \"required\"\n\
       [check]\n\
       historical = [\"h/\"]\n" );
  ]

let the_base_side_counts_only_what_sinter_knows () =
  List.iter
    (fun (name, text) -> Alcotest.check strings name defaults (entries text))
    what_the_base_side_leaves_out

let a_member_of_the_wrong_type_leaves_the_others () =
  Alcotest.check strings "the entries"
    (with_defaults
       [
         "setting:proof.agent-markers=A \"A\"";
         "setting:scan.packs.a.files=x \"x\"";
       ])
    (entries
       "[scan]\n\
        packs.a.files = [1, \"x\", false]\n\
        [proof]\n\
        agent-markers = [\"A\", 2]\n")

let a_manifest_compared_with_itself_has_no_change () =
  Alcotest.check strings "no change" []
    (details "[check]\nwarn-only = true\n" "[check]\nwarn-only = true\n")

let a_written_default_is_no_change () =
  Alcotest.check strings "no change" []
    (details ""
       "default-branch = \"main\"\n\
        [proof]\n\
        req = \"declaration\"\n\
        design = \"declaration\"\n\
        decision = \"declaration\"\n\
        plan = \"declaration\"\n\
        verifies = \"whole-run\"\n\
        step = \"change\"\n\
        [check]\n\
        warn-only = false\n")

let rows =
  [
    ( "",
      "default-branch = \"trunk\"\n",
      "default-branch: \"main\" -> \"trunk\" (changes)",
      "default-branch: \"trunk\" -> \"main\" (changes)" );
    ( "default-branch = \"dev\"\n",
      "default-branch = \"trunk\"\n",
      "default-branch: \"dev\" -> \"trunk\" (changes)",
      "default-branch: \"trunk\" -> \"dev\" (changes)" );
    ( "[scan]\npacks.a.files = [\"x\"]\n",
      "[scan]\npacks.a.files = [\"x\", \"y\"]\n",
      "scan.packs.a.files: added \"y\" (strengthens)",
      "scan.packs.a.files: removed \"y\" (weakens)" );
    ( "[scan]\npacks.a.files = [\"x\"]\n",
      "[scan]\npacks.a.files = [\"x\", \"!y\"]\n",
      "scan.packs.a.files: added \"!y\" (weakens)",
      "scan.packs.a.files: removed \"!y\" (strengthens)" );
    ( "[scan]\npacks.a.version = \"1.0\"\n",
      "[scan]\npacks.a.version = \"1.1\"\n",
      "scan.packs.a.version: \"1.0\" -> \"1.1\" (changes)",
      "scan.packs.a.version: \"1.1\" -> \"1.0\" (changes)" );
    ( "",
      "[scan]\npacks.a.version = \"1.1\"\n",
      "scan.packs.a.version: added \"1.1\" (changes)",
      "scan.packs.a.version: removed \"1.1\" (changes)" );
    ( "",
      "[scan]\npacks.a.runners.vitest = {}\n",
      "scan.packs.a.runners: added \"vitest\" (changes)",
      "scan.packs.a.runners: removed \"vitest\" (changes)" );
    ( "",
      "[scan]\npacks.a.runners.vitest.mode = \"ci\"\n",
      "scan.packs.a.runners: added \"vitest\" (changes)",
      "scan.packs.a.runners: removed \"vitest\" (changes)" );
    ( "",
      "[scan]\nnamespaces.jira = \"[A-Z]+-[1-9][0-9]*\"\n",
      "scan.namespaces.jira: added \"[A-Z]+-[1-9][0-9]*\" (weakens)",
      "scan.namespaces.jira: removed \"[A-Z]+-[1-9][0-9]*\" (strengthens)" );
    ( "[scan]\nnamespaces.gh = \"[0-9]+\"\n",
      "[scan]\nnamespaces.gh = \"[1-9][0-9]*\"\n",
      "scan.namespaces.gh: \"[0-9]+\" -> \"[1-9][0-9]*\" (changes)",
      "scan.namespaces.gh: \"[1-9][0-9]*\" -> \"[0-9]+\" (changes)" );
    ( "",
      "[check]\nwarn-only = true\n",
      "check.warn-only: false -> true (weakens)",
      "check.warn-only: true -> false (strengthens)" );
    ( "",
      "[check]\ntiers.review.dangling = \"warn\"\n",
      "check.tiers.review.dangling: \"block\" -> \"warn\" (weakens)",
      "check.tiers.review.dangling: \"warn\" -> \"block\" (strengthens)" );
    ( "[check]\ntiers.turn.untraced = \"warn\"\n",
      "[check]\ntiers.turn.untraced = \"block\"\n",
      "check.tiers.turn.untraced: \"warn\" -> \"block\" (strengthens)",
      "check.tiers.turn.untraced: \"block\" -> \"warn\" (weakens)" );
    ( "[check]\ntiers.turn.untraced = \"warn\"\n",
      "[check]\ntiers.turn.untraced = \"off\"\n",
      "check.tiers.turn.untraced: \"warn\" -> \"off\" (weakens)",
      "check.tiers.turn.untraced: \"off\" -> \"warn\" (strengthens)" );
    ( "",
      "[check]\ntiers.review.dangling = \"block\"\n",
      "check.tiers.review.dangling: \"block\" -> \"block\" (changes)",
      "check.tiers.review.dangling: \"block\" -> \"block\" (changes)" );
    ( "",
      "[paths]\nexempt = [\"gen/\"]\n",
      "paths.exempt: added \"gen/\" (weakens)",
      "paths.exempt: removed \"gen/\" (strengthens)" );
    ( "",
      "[paths]\nexempt = [\"!gen/\"]\n",
      "paths.exempt: added \"!gen/\" (strengthens)",
      "paths.exempt: removed \"!gen/\" (weakens)" );
    ( "",
      "[paths]\nhistorical = [\"docs/devlog/\"]\n",
      "paths.historical: added \"docs/devlog/\" (weakens)",
      "paths.historical: removed \"docs/devlog/\" (strengthens)" );
    ( "",
      "[paths]\nhistorical = [\"!docs/devlog/\"]\n",
      "paths.historical: added \"!docs/devlog/\" (strengthens)",
      "paths.historical: removed \"!docs/devlog/\" (weakens)" );
    ( "",
      "[paths]\nreq = [\"docs/\"]\n",
      "paths.req: added \"docs/\" (weakens)",
      "paths.req: removed \"docs/\" (strengthens)" );
    ( "",
      "[paths]\ndesign = [\"!docs/\"]\n",
      "paths.design: added \"!docs/\" (strengthens)",
      "paths.design: removed \"!docs/\" (weakens)" );
    ( "",
      "[proof]\nreq = \"approval\"\n",
      "proof.req: \"declaration\" -> \"approval\" (strengthens)",
      "proof.req: \"approval\" -> \"declaration\" (weakens)" );
    ( "[proof]\nplan = \"declaration\"\n",
      "[proof]\nplan = \"approval\"\n",
      "proof.plan: \"declaration\" -> \"approval\" (strengthens)",
      "proof.plan: \"approval\" -> \"declaration\" (weakens)" );
    ( "",
      "[proof]\nagent-markers = [\"BOT\"]\n",
      "proof.agent-markers: added \"BOT\" (strengthens)",
      "proof.agent-markers: removed \"BOT\" (weakens)" );
    ( "",
      "[proof]\nverifies = \"each-test\"\n",
      "proof.verifies: \"whole-run\" -> \"each-test\" (strengthens)",
      "proof.verifies: \"each-test\" -> \"whole-run\" (weakens)" );
    ( "",
      "[proof]\nstep = \"promises\"\n",
      "proof.step: \"change\" -> \"promises\" (strengthens)",
      "proof.step: \"promises\" -> \"change\" (weakens)" );
    ( "[proof]\nstep = \"approval\"\n",
      "[proof]\nstep = \"promises\"\n",
      "proof.step: \"approval\" -> \"promises\" (strengthens)",
      "proof.step: \"promises\" -> \"approval\" (weakens)" );
    ( "",
      "[proof]\nstep = \"approval\"\n",
      "proof.step: \"change\" -> \"approval\" (changes)",
      "proof.step: \"approval\" -> \"change\" (changes)" );
  ]

let each_row_of_the_direction_table_holds_both_ways () =
  List.iter
    (fun (base, now, forward, backward) ->
      Alcotest.check strings ("forward: " ^ forward) [ forward ]
        (details base now);
      Alcotest.check strings ("backward: " ^ backward) [ backward ]
        (details now base))
    rows

let a_tier_applies_under_the_warn_only_of_its_side () =
  Alcotest.check strings "warn-only on both sides, a pair added"
    [ "check.tiers.review.dangling: \"warn\" -> \"warn\" (changes)" ]
    (details "[check]\nwarn-only = true\n"
       "[check]\nwarn-only = true\ntiers.review.dangling = \"warn\"\n");
  Alcotest.check strings "warn-only on both sides, a pair removed"
    [ "check.tiers.review.dangling: \"block\" -> \"warn\" (weakens)" ]
    (details "[check]\nwarn-only = true\ntiers.review.dangling = \"block\"\n"
       "[check]\nwarn-only = true\n");
  Alcotest.check strings "warn-only added with the pair"
    [
      "check.tiers.review.dangling: \"block\" -> \"block\" (changes)";
      "check.warn-only: false -> true (weakens)";
    ]
    (details "" "[check]\nwarn-only = true\ntiers.review.dangling = \"block\"\n");
  Alcotest.check strings "warn-only removed with the pair"
    [
      "check.tiers.review.dangling: \"warn\" -> \"block\" (strengthens)";
      "check.warn-only: true -> false (strengthens)";
    ]
    (details "[check]\nwarn-only = true\ntiers.review.dangling = \"warn\"\n" "");
  Alcotest.check strings "a tier that is not block stays under warn-only"
    [ "check.tiers.turn.untraced: \"off\" -> \"warn\" (strengthens)" ]
    (details "[check]\nwarn-only = true\n"
       "[check]\nwarn-only = true\ntiers.turn.untraced = \"warn\"\n");
  Alcotest.check strings "the same written tier is no change" []
    (details "[check]\ntiers.review.dangling = \"warn\"\n"
       "[check]\nwarn-only = true\ntiers.review.dangling = \"warn\"\n"
    |> List.filter (fun d -> String.starts_with ~prefix:"check.tiers" d))

let a_change_names_its_places_and_its_subject () =
  let base =
    "[scan]\n\
     packs.markdown.files = [\"**/*.md\", \"old/\"]\n\
     namespaces.gh = \"x\"\n\
     packs.ocaml.runners.dune = {}\n\
     [check]\n\
     tiers.review.dangling = \"warn\"\n"
  and now =
    "default-branch = \"trunk\"\n\
     [scan]\n\
     packs.markdown.files = [\"**/*.md\", 'new/']\n\
     packs.ocaml.runners.\"vitest\".mode = \"ci\"\n\
     [check]\n\
     warn-only = true # a comment\n\
     tiers.merged.cycle = \"off\"\n"
  in
  let span = function
    | None -> "-"
    | Some (span : Toml.span) ->
        Printf.sprintf "%d:%d-%d:%d" span.start.line span.start.column
          span.stop.line span.stop.column
  in
  Alcotest.check strings "the changes"
    [
      "gate:merged/cycle 7:1-7:27 - false";
      "gate:review/dangling - 6:1-6:31 false";
      "setting:check.warn-only 6:1-6:17 - false";
      "setting:default-branch 1:1-1:25 - false";
      "setting:scan.namespaces.gh - 3:1-3:20 true";
      "setting:scan.packs.markdown.files=new/ 3:36-3:42 - false";
      "setting:scan.packs.markdown.files=old/ - 2:36-2:42 true";
      "setting:scan.packs.ocaml.runners=dune - 4:21-4:25 true";
      "setting:scan.packs.ocaml.runners=vitest 4:21-4:29 - false";
    ]
    (List.map
       (fun (change : Config_change.change) ->
         Printf.sprintf "%s %s %s %b" change.id (span change.written)
           (span change.was) change.tombstone)
       (changes base now));
  Alcotest.check strings "the key paths"
    [
      "check.tiers.merged.cycle";
      "check.tiers.review.dangling";
      "check.warn-only";
      "default-branch";
      "scan.namespaces.gh";
      "scan.packs.markdown.files";
      "scan.packs.markdown.files";
      "scan.packs.ocaml.runners";
      "scan.packs.ocaml.runners";
    ]
    (List.map
       (fun (change : Config_change.change) -> String.concat "." change.key)
       (changes base now))

let a_detail_writes_a_string_as_toml_does () =
  Alcotest.check strings "the details"
    [ "proof.agent-markers: added \"A\\\"B\\\\\" (strengthens)" ]
    (details "" "[proof]\nagent-markers = ['A\"B\\']\n")

let hunk ~line ~eline ~ecol ~old_line ~added ~removed =
  { Git.line; eline; ecol; old_line; added; removed }

let show (finding : Finding.t) =
  let place =
    match finding.place with
    | Some { path; span } ->
        Printf.sprintf "%s:%d:%d-%d:%d" path span.start.line span.start.column
          span.stop.line span.stop.column
    | None -> "-"
  in
  String.concat " | "
    ([
       place;
       Finding.id finding;
       Finding.ack_subject finding.subject;
       string_of_bool finding.ackable;
     ]
    @ Option.to_list finding.detail
    @ Option.to_list (Option.map Fix.text finding.fix))

let findings ?(hunks = []) ~base now =
  List.map show
    (Config_change.findings ~plan_file:no_plan ~location:"conf/sinter.toml"
       ~hunks ~base (parse now))

let a_finding_sits_at_its_subject_or_at_a_hunk () =
  let base =
    "[scan]\n\
     namespaces.gh = \"x\"\n\
     namespaces.jira = \"y\"\n\
     [check]\n\
     tiers.review.dangling = \"warn\"\n\
     warn-only = true\n"
  and now = "[check]\ntiers.merged.cycle = \"off\"\n" in
  Alcotest.check strings "the findings"
    [
      "conf/sinter.toml:2:1-2:27 | finding:config-changed:gate:merged/cycle | \
       gate:merged/cycle | false | check.tiers.merged.cycle: \"warn\" -> \
       \"off\" (weakens)";
      "conf/sinter.toml:1:1-2:28 | finding:config-changed:gate:review/dangling \
       | gate:review/dangling | false | check.tiers.review.dangling: \"warn\" \
       -> \"block\" (strengthens)";
      "conf/sinter.toml:3:1-3:1 | \
       finding:config-changed:setting:check.warn-only | \
       setting:check.warn-only | false | check.warn-only: true -> false \
       (strengthens)";
      "conf/sinter.toml:1:1-2:28 | \
       finding:config-changed:tombstone:setting:scan.namespaces.gh | \
       tombstone:setting:scan.namespaces.gh | false | scan.namespaces.gh: \
       removed \"x\" (strengthens)";
      "conf/sinter.toml:1:1-2:28 | \
       finding:config-changed:tombstone:setting:scan.namespaces.jira | \
       tombstone:setting:scan.namespaces.jira | false | scan.namespaces.jira: \
       removed \"y\" (strengthens)";
    ]
    (findings
       ~hunks:
         [
           hunk ~line:1 ~eline:2 ~ecol:28 ~old_line:1 ~added:2 ~removed:5;
           hunk ~line:3 ~eline:3 ~ecol:1 ~old_line:6 ~added:0 ~removed:1;
         ]
       ~base:(Some base) now)

let a_hunk_must_hold_the_first_line_of_the_entry () =
  let base = "[paths]\n\nhistorical = [\n  \"a/\",\n  \"b/\",\n]\n" in
  let at hunks = findings ~hunks ~base:(Some base) "" in
  let place lines =
    List.map (fun line -> List.nth (String.split_on_char ' ' line) 0) lines
  in
  Alcotest.check strings "before the entry"
    [ "conf/sinter.toml:1:1-1:1"; "conf/sinter.toml:1:1-1:1" ]
    (place
       (at [ hunk ~line:2 ~eline:2 ~ecol:4 ~old_line:1 ~added:1 ~removed:3 ]));
  Alcotest.check strings "the first and the last line of a hunk"
    [ "conf/sinter.toml:7:1-8:9"; "conf/sinter.toml:9:1-9:1" ]
    (place
       (at
          [
            hunk ~line:7 ~eline:8 ~ecol:9 ~old_line:2 ~added:2 ~removed:3;
            hunk ~line:9 ~eline:9 ~ecol:1 ~old_line:5 ~added:0 ~removed:2;
          ]));
  Alcotest.check strings "a hunk that removes no line"
    [ "conf/sinter.toml:1:1-1:1"; "conf/sinter.toml:1:1-1:1" ]
    (place
       (at [ hunk ~line:4 ~eline:5 ~ecol:3 ~old_line:4 ~added:2 ~removed:0 ]))

let the_line_of_a_value_is_the_line_of_its_key () =
  let base = "[scan]\nnamespaces.gh = \"\"\"\n[0-9]+\"\"\"\n" in
  let at hunks =
    List.map
      (fun line -> List.nth (String.split_on_char ' ' line) 0)
      (findings ~hunks ~base:(Some base) "")
  in
  Alcotest.check strings "a hunk that removes the last line of the value"
    [ "conf/sinter.toml:1:1-1:1" ]
    (at [ hunk ~line:2 ~eline:2 ~ecol:1 ~old_line:3 ~added:0 ~removed:1 ]);
  Alcotest.check strings "a hunk that removes the line of the key"
    [ "conf/sinter.toml:2:1-2:1" ]
    (at [ hunk ~line:2 ~eline:2 ~ecol:1 ~old_line:2 ~added:0 ~removed:1 ])

let an_absent_base_gives_every_setting_as_added () =
  Alcotest.check strings "the details"
    [
      "conf/sinter.toml:2:25-2:34 | \
       finding:config-changed:setting:scan.packs.markdown.files=**/*.md | \
       setting:scan.packs.markdown.files=**/*.md | false | \
       scan.packs.markdown.files: added \"**/*.md\" (strengthens)";
    ]
    (findings ~base:None "[scan]\npacks.markdown.files = [\"**/*.md\"]\n")

let a_base_that_is_not_toml_is_an_empty_manifest () =
  List.iter
    (fun base ->
      Alcotest.check strings (Printf.sprintf "%S" base)
        [
          "conf/sinter.toml:1:1-1:25 | \
           finding:config-changed:setting:default-branch | \
           setting:default-branch | false | default-branch: \"main\" -> \
           \"trunk\" (changes); the base manifest is not valid TOML";
        ]
        (findings ~base:(Some base) "default-branch = \"trunk\"\n"))
    [
      "default-branch = \"trunk\"\nx = = 1\n";
      "default-branch = \"tr\xffnk\"\n";
      "[a]\n[a]\n";
    ]

let an_unchanged_base_gives_no_finding () =
  Alcotest.check strings "no finding" []
    (findings ~base:(Some "# old\n[check]\n'warn-only' = true\n")
       "[check] # new\nwarn-only = true\n")

type leaf =
  | Text of string
  | Flag of bool
  | Empty_table
  | Strings of string list

let sublist pool =
  Gen.(
    map
      (fun keep -> List.filteri (fun i _ -> List.nth keep i) pool)
      (list_size (return (List.length pool)) bool))

let optional key gen =
  Gen.(map (function Some leaf -> [ (key, leaf) ] | None -> []) (option gen))

let members key pool =
  Gen.(
    map
      (function [] -> [] | members -> [ (key, Strings members) ])
      (sublist pool))

let globs = [ "**/*.md"; "docs/"; "!docs/old/"; "a b/"; "*.ml"; "x'y/" ]

let config =
  Gen.(
    let pack name =
      bool >>= fun named ->
      if not named then return []
      else
        let path rest = "scan" :: "packs" :: name :: rest in
        let files = members (path [ "files" ]) globs in
        if name = "markdown" then files
        else
          map
            (fun parts -> List.concat parts)
            (flatten_list
               [
                 files;
                 optional (path [ "version" ])
                   (map (fun v -> Text v) (oneof_list [ "1.0"; "1.2" ]));
                 map
                   (List.map (fun runner ->
                        (path [ "runners"; runner ], Empty_table)))
                   (sublist [ "vitest"; "dune-test" ]);
               ])
    in
    let tier = map (fun t -> Text t) (oneof_list [ "off"; "warn"; "block" ]) in
    flatten_list
      [
        optional [ "default-branch" ]
          (map (fun b -> Text b) (oneof_list [ "main"; "trunk"; "dev" ]));
        pack "markdown";
        pack "ocaml";
        pack "go";
        map
          (List.map (fun (ns, pattern) ->
               ([ "scan"; "namespaces"; ns ], Text pattern)))
          (sublist [ ("gh", "[1-9][0-9]*"); ("jira", "[A-Z]+-[0-9]+") ]);
        optional [ "check"; "warn-only" ] (map (fun b -> Flag b) bool);
        members [ "paths"; "historical" ] (".plans/**/*.log.md" :: globs);
        flatten_list
          (List.map
             (fun (gate, cls) -> optional [ "check"; "tiers"; gate; cls ] tier)
             [
               ("review", "dangling");
               ("turn", "untraced");
               ("merged", "cycle");
               ("turn", "suspect");
             ])
        >|= List.concat;
        members [ "paths"; "exempt" ] ("sinter.toml" :: "sinter.lock" :: globs);
        members [ "paths"; "req" ] globs;
        members [ "paths"; "decision" ] globs;
        flatten_list
          (List.map
             (fun kind ->
               optional [ "proof"; kind ]
                 (map
                    (fun word -> Text word)
                    (oneof_list [ "declaration"; "approval" ])))
             [ "req"; "design"; "decision"; "plan" ])
        >|= List.concat;
        members [ "proof"; "agent-markers" ] [ "CI_AGENT"; "MY_BOT" ];
        optional [ "proof"; "verifies" ]
          (map (fun c -> Text c) (oneof_list [ "whole-run"; "each-test" ]));
        optional [ "proof"; "step" ]
          (map
             (fun c -> Text c)
             (oneof_list [ "change"; "approval"; "promises" ]));
      ]
    >|= List.concat)

let shuffle rng list =
  List.map (fun x -> (Random.State.bits rng, x)) list
  |> List.sort (fun (a, _) (b, _) -> compare a b)
  |> List.map snd

let chance rng = Random.State.int rng 3 = 0

let key rng names =
  String.concat "."
    (List.map
       (fun name ->
         if chance rng then Toml.basic_string name
         else Toml.render_path [ name ])
       names)

let string rng text =
  if chance rng && not (String.contains text '\'') then "'" ^ text ^ "'"
  else Toml.basic_string text

let leaf rng ~lines = function
  | Text text -> string rng text
  | Flag flag -> string_of_bool flag
  | Empty_table -> "{}"
  | Strings members ->
      let members = List.map (string rng) (shuffle rng members) in
      if lines && chance rng then
        "[\n"
        ^ String.concat ""
            (List.map
               (fun member ->
                 (if chance rng then "  # a member\n" else "")
                 ^ "  " ^ member ^ ",\n")
               members)
        ^ "]"
      else "[" ^ String.concat ", " members ^ "]"

let setting rng path value = key rng path ^ " = " ^ leaf rng ~lines:true value

let decorate rng lines =
  List.concat_map
    (fun line ->
      (if chance rng then [ "# a comment" ] else [])
      @ (if chance rng then [ "" ] else [])
      @ [ (if chance rng then line ^ " # after" else line) ])
    lines

let rec split_at n list =
  match (n, list) with
  | 0, rest | _, ([] as rest) -> ([], rest)
  | n, x :: rest ->
      let front, back = split_at (n - 1) rest in
      (x :: front, back)

let groups ~depth settings =
  List.fold_left
    (fun groups (path, value) ->
      let table, rest = split_at (min depth (List.length path - 1)) path in
      let line = (rest, value) in
      match List.assoc_opt table groups with
      | Some lines ->
          (table, lines @ [ line ]) :: List.remove_assoc table groups
      | None -> (table, [ line ]) :: groups)
    [] settings

let by_tables rng ~depth settings =
  let top, tables =
    List.partition (fun (table, _) -> table = []) (groups ~depth settings)
  in
  List.concat_map
    (fun (_, lines) ->
      List.map (fun (path, value) -> setting rng path value) (shuffle rng lines))
    top
  @ List.concat_map
      (fun (table, lines) ->
        ("[" ^ key rng table ^ "]")
        :: List.map
             (fun (path, value) -> setting rng path value)
             (shuffle rng lines))
      (shuffle rng tables)

type tree = Leaf of leaf | Node of (string * tree) list

let rec insert nodes path value =
  match path with
  | [] -> nodes
  | [ name ] -> nodes @ [ (name, Leaf value) ]
  | name :: rest -> (
      match List.assoc_opt name nodes with
      | Some (Node children) ->
          List.map
            (fun (n, tree) ->
              if n = name then (n, Node (insert children rest value))
              else (n, tree))
            nodes
      | Some (Leaf _) | None -> nodes @ [ (name, Node (insert [] rest value)) ])

let rec inline rng = function
  | Leaf value -> leaf rng ~lines:false value
  | Node children ->
      "{ "
      ^ String.concat ", "
          (List.map
             (fun (name, tree) -> key rng [ name ] ^ " = " ^ inline rng tree)
             (shuffle rng children))
      ^ " }"

let render seed settings =
  let rng = Random.State.make [| seed |] in
  let lines =
    match Random.State.int rng 5 with
    | 0 ->
        List.map
          (fun (path, value) -> setting rng path value)
          (shuffle rng settings)
    | 1 -> by_tables rng ~depth:1 settings
    | 2 -> by_tables rng ~depth:2 settings
    | 3 -> by_tables rng ~depth:4 settings
    | _ ->
        List.map
          (fun (name, tree) -> key rng [ name ] ^ " = " ^ inline rng tree)
          (shuffle rng
             (List.fold_left
                (fun nodes (path, value) -> insert nodes path value)
                [] settings))
  in
  String.concat "\n" (decorate rng lines) ^ "\n"

let plan_file path = path = "x'y/"

let side_of seed settings =
  Config_change.side ~plan_file ~location:"sinter.toml"
    (parse (render seed settings))

let print_settings (seed, settings) = render seed settings

let a_manifest_compared_with_itself_gives_no_change_law =
  property ~name:"a manifest compared with itself gives no change"
    ~print:print_settings
    Gen.(pair int config)
    (fun (seed, settings) ->
      let side = side_of seed settings in
      Config_change.changes ~base:side side = [])

let a_change_of_form_only_gives_no_change =
  property ~name:"a change of the TOML form only gives no change"
    ~print:(fun (a, b, settings) ->
      print_settings (a, settings) ^ "----\n" ^ print_settings (b, settings))
    Gen.(triple int int config)
    (fun (a, b, settings) ->
      let one = side_of a settings and other = side_of b settings in
      Config_change.changes ~base:one other = []
      && Config_change.entries one = Config_change.entries other)

let two_manifests = Gen.(pair (pair int config) (pair int config))
let print_two (a, b) = print_settings a ^ "----\n" ^ print_settings b

let swapped (change : Config_change.change) =
  ( change.id,
    (match change.form with
    | Config_change.Changed { old; now } ->
        Config_change.Changed { old = now; now = old }
    | Config_change.Added value -> Config_change.Removed value
    | Config_change.Removed value -> Config_change.Added value),
    match change.direction with
    | Config_change.Strengthens -> Config_change.Weakens
    | Config_change.Weakens -> Config_change.Strengthens
    | Config_change.Changes -> Config_change.Changes )

let swapping_the_sides_swaps_each_change =
  property ~name:"swapping the sides swaps each change" ~print:print_two
    two_manifests (fun ((a, one), (b, other)) ->
      let one = side_of a one and other = side_of b other in
      List.map swapped (Config_change.changes ~base:one other)
      = List.map
          (fun (change : Config_change.change) ->
            (change.id, change.form, change.direction))
          (Config_change.changes ~base:other one))

let each_difference_gives_one_finding =
  property ~name:"each id in one set, or with two values, gives one finding"
    ~print:print_two two_manifests (fun ((a, one), (b, other)) ->
      let base = Config_change.entries (side_of a one)
      and now = Config_change.entries (side_of b other) in
      let ids = List.sort_uniq compare (List.map fst base @ List.map fst now) in
      let expected =
        List.filter
          (fun id -> List.assoc_opt id base <> List.assoc_opt id now)
          ids
      in
      let findings =
        Config_change.findings ~plan_file ~location:"sinter.toml" ~hunks:[]
          ~base:(Some (render a one))
          (parse (render b other))
      in
      List.map
        (fun (change : Config_change.change) -> change.id)
        (Config_change.changes ~base:(side_of a one) (side_of b other))
      = expected
      && List.length findings = List.length expected
      && List.for_all
           (fun (finding : Finding.t) ->
             finding.finding_class = Finding_class.Config_changed
             && (not finding.ackable)
             &&
             match finding.detail with
             | Some detail -> not (String.contains detail '\n')
             | None -> false)
           findings)

let damaged =
  Gen.(
    pair (pair int config) (list_size (int_range 1 4) (pair nat char))
    >|= fun ((seed, settings), edits) ->
    let text = Bytes.of_string (render seed settings) in
    List.iter
      (fun (at, c) ->
        if Bytes.length text > 0 then
          Bytes.set text (at mod Bytes.length text) c)
      edits;
    Bytes.to_string text)

let any_base_text_gives_findings =
  property ~count:400 ~name:"any base text gives findings and no exception"
    ~print:(Printf.sprintf "%S")
    Gen.(oneof [ damaged; string; string_printable ])
    (fun base ->
      let findings =
        Config_change.findings ~plan_file ~location:"sinter.toml" ~hunks:[]
          ~base:(Some base)
          (parse "[check]\nwarn-only = true\n")
      in
      let invalid = Result.is_error (Toml.parse base) in
      List.for_all
        (fun (finding : Finding.t) ->
          match finding.detail with
          | Some detail ->
              (not (String.contains detail '\n'))
              && String.ends_with
                   ~suffix:"; the base manifest is not valid TOML" detail
                 = invalid
          | None -> false)
        findings)

let names =
  [
    "scan";
    "packs";
    "markdown";
    "files";
    "check";
    "tiers";
    "review";
    "dangling";
    "a.b";
    "a=b";
    "x y";
    "\x01";
    "plan";
    "exempt";
    "paths";
    "proof";
    "req";
    "verifies";
    "step";
    "historical";
    "ledger";
    "agent-markers";
    "runners";
    "vitest";
    "namespaces";
  ]

let wild_value =
  Gen.oneof_list
    [
      "1";
      "2.5";
      "true";
      "\"s\"";
      "[]";
      "[1, \"a\"]";
      "{ k = 1 }";
      "1979-05-27";
      "07:32:00";
      "[{ a = 1 }]";
      "\"warn\"";
      "\"approval\"";
      "\"each-test\"";
      "\"promises\"";
      "[\"x\", \"x\"]";
    ]

let wild =
  Gen.(
    list_size (int_range 0 12)
      (pair (list_size (int_range 1 5) (oneof_list names)) wild_value)
    >|= fun lines ->
    String.concat ""
      (List.map
         (fun (path, value) -> Toml.render_path path ^ " = " ^ value ^ "\n")
         lines))

let every_entry_of_any_document_has_an_id_that_parses =
  property ~count:400 ~name:"every entry of any document has an id that parses"
    ~print:(fun text -> text)
    wild
    (fun text ->
      match Toml.parse text with
      | Error _ -> true
      | Ok document ->
          List.for_all
            (fun (id, _) ->
              (String.starts_with ~prefix:"setting:" id
              || String.starts_with ~prefix:"gate:" id)
              && not (String.exists (fun c -> c = ' ' || c < ' ') id))
            (Config_change.entries
               (Config_change.side ~plan_file ~location:"sinter.toml" document)))

let proof_defaults =
  [
    ([ "proof"; "req" ], "declaration");
    ([ "proof"; "design" ], "declaration");
    ([ "proof"; "decision" ], "declaration");
    ([ "proof"; "plan" ], "declaration");
    ([ "proof"; "verifies" ], "whole-run");
    ([ "proof"; "step" ], "change");
  ]

let each_key_of_proof_has_its_written_value_or_its_default =
  property ~name:"each key of [proof] has its written value or its default"
    ~print:print_settings
    Gen.(pair int config)
    (fun (seed, settings) ->
      let entries = Config_change.entries (side_of seed settings) in
      List.for_all
        (fun (key, default) ->
          let expected =
            match List.assoc_opt key settings with
            | Some (Text word) -> word
            | Some _ | None -> default
          in
          List.assoc_opt (Fact_id.setting key) entries
          = Some (Config_change.String expected))
        proof_defaults)

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "an empty manifest has every default"
      an_empty_manifest_has_every_default;
    case "every setting gives its entries" every_setting_gives_its_entries;
    case "a built-in member gives no entry" a_built_in_member_gives_no_entry;
    case "a member written twice gives one entry"
      a_member_written_twice_gives_one_entry;
    case "the base side counts only what sinter knows"
      the_base_side_counts_only_what_sinter_knows;
    case "a member of the wrong type leaves the others"
      a_member_of_the_wrong_type_leaves_the_others;
    case "a manifest compared with itself has no change"
      a_manifest_compared_with_itself_has_no_change;
    case "a written default is no change" a_written_default_is_no_change;
    case "each row of the direction table holds both ways"
      each_row_of_the_direction_table_holds_both_ways;
    case "a tier applies under the warn-only of its side"
      a_tier_applies_under_the_warn_only_of_its_side;
    case "a change names its places and its subject"
      a_change_names_its_places_and_its_subject;
    case "a detail writes a string as toml does"
      a_detail_writes_a_string_as_toml_does;
    case "a finding sits at its subject or at a hunk"
      a_finding_sits_at_its_subject_or_at_a_hunk;
    case "a hunk must hold the first line of the entry"
      a_hunk_must_hold_the_first_line_of_the_entry;
    case "the line of a value is the line of its key"
      the_line_of_a_value_is_the_line_of_its_key;
    case "an absent base gives every setting as added"
      an_absent_base_gives_every_setting_as_added;
    case "a base that is not toml is an empty manifest"
      a_base_that_is_not_toml_is_an_empty_manifest;
    case "an unchanged base gives no finding" an_unchanged_base_gives_no_finding;
    a_manifest_compared_with_itself_gives_no_change_law;
    a_change_of_form_only_gives_no_change;
    swapping_the_sides_swaps_each_change;
    each_difference_gives_one_finding;
    any_base_text_gives_findings;
    every_entry_of_any_document_has_an_id_that_parses;
    each_key_of_proof_has_its_written_value_or_its_default;
  ]
