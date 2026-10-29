(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let markdown = "[scan]\npacks.markdown.files = [\"**/*.md\"]\n"

let read text =
  match Manifest.of_string text with
  | Ok manifest -> manifest
  | Error errors ->
      Alcotest.failf "the manifest has errors:\n%s"
        (String.concat "\n"
           (List.map (Manifest.render ~path:"sinter.toml") errors))

let lines text =
  match Manifest.of_string text with
  | Ok _ -> [ "no error" ]
  | Error errors -> List.map (Manifest.render ~path:"sinter.toml") errors

let reports name text expected =
  Alcotest.(check (list string)) name expected (lines text)

let the_smallest_manifest_takes_every_default () =
  let manifest = read markdown in
  Alcotest.(check (option string))
    "sinter-spec" None
    (Option.map Major_minor.to_string (Manifest.sinter_spec manifest));
  Alcotest.(check string)
    "default-branch" "main"
    (Manifest.default_branch manifest);
  Alcotest.(check bool) "warn-only" false (Manifest.warn_only manifest);
  Alcotest.(check bool)
    "verifies" true
    (Manifest.verifies manifest = Manifest.Whole_run);
  Alcotest.(check int)
    "no namespace" 0
    (List.length (Manifest.namespaces manifest));
  Alcotest.(check int)
    "no written tier" 0
    (List.length (Manifest.written_tiers manifest));
  Alcotest.(check bool)
    "no historical member" true
    (Path_set.is_empty (Manifest.historical manifest));
  Alcotest.(check bool)
    "no exempt member" true
    (Path_set.is_empty (Manifest.exempt manifest));
  Alcotest.(check bool)
    "no location" true
    (List.for_all
       (fun kind -> Manifest.location manifest kind = None)
       Manifest.[ Req; Design; Decision; Plan ]);
  Alcotest.(check bool)
    "no kind needs approval" true
    (List.for_all
       (fun kind -> Manifest.approval manifest kind = Manifest.Declaration)
       Manifest.[ Req; Design; Decision; Plan ]);
  Alcotest.(check (list string))
    "no agent marker" []
    (Manifest.agent_markers manifest)

let members set = List.map Path_set.member_to_string (Path_set.members set)

let pack_summary (pack : Manifest.pack) =
  Printf.sprintf "%s %s %s" pack.name
    (String.concat "," (members pack.files))
    (match pack.version with
    | None -> "-"
    | Some version -> Major_minor.to_string version)

let sinter_example =
  {|sinter-spec = "1.0"

[scan]
packs.markdown.files = ["**/*.md"]
packs.ocaml.files = ["**/*.ml", "**/*.mli"]
packs.ocaml.version = "1.0"
packs.rust.files = ["**/*.rs"]
packs.rust.version = "1.0"
namespaces.gh = "[1-9][0-9]*"

[paths]
exempt = [
  ".gitignore",
  "LICENSES/",
  "REUSE.toml",
  "THIRD_PARTY.md",
  "bridge/Cargo.lock",
  "bridge/Cargo.toml",
  "dune-project",
  "sinter.opam",
  "sinter.opam.locked",
]
decision = ["docs/decisions/"]

[check]
warn-only = true
|}

let the_example_of_sinter_reads () =
  let manifest = read sinter_example in
  Alcotest.(check (option string))
    "sinter-spec" (Some "1.0")
    (Option.map Major_minor.to_string (Manifest.sinter_spec manifest));
  Alcotest.(check (list string))
    "packs"
    [ "markdown **/*.md -"; "ocaml **/*.ml,**/*.mli 1.0"; "rust **/*.rs 1.0" ]
    (List.map pack_summary (Manifest.packs manifest));
  Alcotest.(check (list (pair string string)))
    "namespaces"
    [ ("gh", "[1-9][0-9]*") ]
    (List.map
       (fun (ns, pattern) -> (ns, Id_pattern.to_string pattern))
       (Manifest.namespaces manifest));
  Alcotest.(check bool) "warn-only" true (Manifest.warn_only manifest);
  Alcotest.(check (list string))
    "exempt"
    [
      ".gitignore";
      "LICENSES/";
      "REUSE.toml";
      "THIRD_PARTY.md";
      "bridge/Cargo.lock";
      "bridge/Cargo.toml";
      "dune-project";
      "sinter.opam";
      "sinter.opam.locked";
    ]
    (members (Manifest.exempt manifest));
  Alcotest.(check (option (list string)))
    "the location of decisions" (Some [ "docs/decisions/" ])
    (Option.map members (Manifest.location manifest Manifest.Decision));
  Alcotest.(check (option (list string)))
    "the location of requirements" None
    (Option.map members (Manifest.location manifest Manifest.Req))

let typescript_example =
  {|sinter-spec = "1.0"

[scan]
packs.markdown.files = ["**/*.md", "!test/fixtures/"]
packs.typescript.files = ["**/*.ts", "!**/*.d.ts"]
packs.typescript.version = "1.0"
packs.typescript.runners.vitest = {}
namespaces.gh = "[1-9][0-9]*"
namespaces.jira = "[A-Z]+-[1-9][0-9]*"

[paths]
exempt = [
  ".gitignore",
  "LICENSE",
  "package-lock.json",
  "package.json",
  "tsconfig.json",
]
historical = ["docs/devlog/"]
decision = ["docs/decisions/"]

[proof]
req = "approval"
verifies = "each-test"

[check]
warn-only = true
tiers.review.dangling = "block"
tiers.merged.dangling = "block"
|}

let the_example_of_a_typescript_project_reads () =
  let manifest = read typescript_example in
  Alcotest.(check (list string))
    "packs"
    [
      "markdown **/*.md,!test/fixtures/ -"; "typescript **/*.ts,!**/*.d.ts 1.0";
    ]
    (List.map pack_summary (Manifest.packs manifest));
  Alcotest.(check (list (list string)))
    "runners" [ []; [ "vitest" ] ]
    (List.map
       (fun (pack : Manifest.pack) ->
         List.map (fun (runner : Manifest.runner) -> runner.name) pack.runners)
       (Manifest.packs manifest));
  Alcotest.(check (list string))
    "the namespaces, sorted" [ "gh"; "jira" ]
    (List.map fst (Manifest.namespaces manifest));
  Alcotest.(check (list string))
    "historical" [ "docs/devlog/" ]
    (members (Manifest.historical manifest));
  Alcotest.(check int)
    "two written tiers" 2
    (List.length (Manifest.written_tiers manifest));
  Alcotest.(check (list string))
    "approval"
    [ "approval"; "declaration"; "declaration"; "declaration" ]
    (List.map
       (fun kind -> Manifest.approval_name (Manifest.approval manifest kind))
       Manifest.[ Req; Design; Decision; Plan ]);
  Alcotest.(check string)
    "verifies" "each-test"
    (Manifest.verifies_name (Manifest.verifies manifest))

let tier =
  Alcotest.testable
    (fun f t ->
      Format.pp_print_string f
        (match t with None -> "none" | Some t -> Finding_class.tier_name t))
    ( = )

let the_tier_that_applies_follows_the_three_rules () =
  let manifest = read typescript_example in
  let check name expected gate finding_class =
    Alcotest.check tier name expected
      (Manifest.tier manifest gate finding_class)
  in
  check "a written tier applies under warn-only" (Some Finding_class.Block)
    Finding_class.Review Finding_class.Dangling;
  check "warn-only lowers a built-in block" (Some Finding_class.Warn)
    Finding_class.Turn Finding_class.Dangling;
  check "warn-only leaves a built-in warn" (Some Finding_class.Warn)
    Finding_class.Turn Finding_class.Typo_tag;
  check "warn-only leaves a built-in off" (Some Finding_class.Off)
    Finding_class.Turn Finding_class.Awaiting_approval;
  check "a class with no tier at the gate" None Finding_class.Merged
    Finding_class.Scope_outside_plan;
  check "pack-mismatch takes no tier" None Finding_class.Review
    Finding_class.Pack_mismatch

let without_warn_only_the_built_in_tier_applies () =
  let manifest = read (markdown ^ "[check]\ntiers.turn.dangling = \"off\"\n") in
  Alcotest.check tier "a built-in block stays" (Some Finding_class.Block)
    (Manifest.tier manifest Finding_class.Review Finding_class.Dangling);
  Alcotest.check tier "a written off" (Some Finding_class.Off)
    (Manifest.tier manifest Finding_class.Turn Finding_class.Dangling);
  Alcotest.check tier "a written tier for another class does not apply"
    (Some Finding_class.Block)
    (Manifest.tier manifest Finding_class.Turn Finding_class.Suspect)

let written_tiers_are_sorted () =
  let manifest =
    read
      (markdown
     ^ "[check]\n\
        tiers.merged.suspect = \"warn\"\n\
        tiers.turn.dangling = \"off\"\n\
        tiers.turn.parse-error = \"block\"\n")
  in
  Alcotest.(check (list string))
    "gate, then class"
    [ "turn parse-error block"; "turn dangling off"; "merged suspect warn" ]
    (List.map
       (fun (gate, finding_class, tier) ->
         String.concat " "
           [
             Finding_class.gate_name gate;
             Finding_class.name finding_class;
             Finding_class.tier_name tier;
           ])
       (Manifest.written_tiers manifest))

let built_in_paths_join_the_written_ones () =
  let manifest =
    read
      (markdown
     ^ "[paths]\n\
        historical = [\"docs/devlog/\", \"!docs/devlog/keep.md\"]\n\
        exempt = [\"gen/\", \"!.plans/**\"]\n")
  in
  let historical = Manifest.is_historical manifest in
  Alcotest.(check bool)
    "the journal of a plan" true
    (historical ".plans/a.log.md");
  Alcotest.(check bool) "a written member" true (historical "docs/devlog/x.md");
  Alcotest.(check bool)
    "a written ! glob" false
    (historical "docs/devlog/keep.md");
  Alcotest.(check bool) "a plan file" false (historical ".plans/a.md");
  let exempt =
    Manifest.is_exempt manifest
      ~plan_file:(fun path -> path = ".plans/a.md")
      ~manifest:(Some "conf/sinter.toml")
  in
  Alcotest.(check bool) "a plan file is exempt" true (exempt ".plans/a.md");
  Alcotest.(check bool)
    "the manifest is exempt" true
    (exempt "conf/sinter.toml");
  Alcotest.(check bool) "the lock file is exempt" true (exempt "sinter.lock");
  Alcotest.(check bool) "a written member" true (exempt "gen/x.ml");
  Alcotest.(check bool) "another file" false (exempt "src/x.ml");
  Alcotest.(check bool)
    "a manifest outside the repository" false
    (Manifest.is_exempt manifest
       ~plan_file:(fun _ -> false)
       ~manifest:None "sinter.toml");
  Alcotest.(check string)
    "the built-in historical glob" ".plans/**/*.log.md"
    Manifest.builtin_historical;
  Alcotest.(check string) "the lock file" "sinter.lock" Manifest.lock_file

let agent_markers_keep_their_order () =
  let manifest =
    read
      (markdown
     ^ "[proof]\n\
        agent-markers = [\"B_1\", \"_a\", \"CLAUDECODE\", \"z\", \"Zz_09\", \
        \"A9\"]\n")
  in
  Alcotest.(check (list string))
    "the markers"
    [ "B_1"; "_a"; "CLAUDECODE"; "z"; "Zz_09"; "A9" ]
    (Manifest.agent_markers manifest)

let each_kind_takes_its_own_approval () =
  let manifest =
    read
      (markdown
     ^ "[proof]\n\
        plan = \"approval\"\n\
        req = \"approval\"\n\
        design = \"declaration\"\n")
  in
  Alcotest.(check (list string))
    "the values of req, design, decision, and plan"
    [ "approval"; "declaration"; "declaration"; "approval" ]
    (List.map
       (fun kind -> Manifest.approval_name (Manifest.approval manifest kind))
       Manifest.[ Req; Design; Decision; Plan ])

let each_word_of_proof_has_its_name () =
  Alcotest.(check (list string))
    "the words"
    [ "declaration"; "approval"; "whole-run"; "each-test" ]
    [
      Manifest.approval_name Manifest.Declaration;
      Manifest.approval_name Manifest.Approval;
      Manifest.verifies_name Manifest.Whole_run;
      Manifest.verifies_name Manifest.Each_test;
    ]

let every_location_kind_reads () =
  let manifest =
    read
      (markdown
     ^ "[paths]\n\
        req = [\"docs/req/\"]\n\
        design = [\"docs/design/\"]\n\
        decision = [\"docs/decisions/\"]\n")
  in
  Alcotest.(check (list (option (list string))))
    "the locations"
    [
      Some [ "docs/req/" ];
      Some [ "docs/design/" ];
      Some [ "docs/decisions/" ];
      None;
    ]
    (List.map
       (fun kind -> Option.map members (Manifest.location manifest kind))
       Manifest.[ Req; Design; Decision; Plan ])

let a_default_branch_reads () =
  Alcotest.(check string)
    "default-branch" "release/1.0"
    (Manifest.default_branch
       (read ("default-branch = \"release/1.0\"\n" ^ markdown)))

let an_empty_array_is_an_absent_key () =
  let manifest =
    read
      (markdown
     ^ "[paths]\nhistorical = []\nreq = []\n[proof]\nagent-markers = []\n")
  in
  Alcotest.(check bool)
    "historical" true
    (Path_set.is_empty (Manifest.historical manifest));
  Alcotest.(check int)
    "agent markers" 0
    (List.length (Manifest.agent_markers manifest));
  Alcotest.(check bool)
    "no location" true
    (Option.is_none (Manifest.location manifest Manifest.Req))

let every_form_of_toml_means_the_same () =
  let forms =
    [
      "[check.tiers.review]\n\
       dangling = \"warn\"\n\
       [scan.packs.markdown]\n\
       files = [\"a\"]\n";
      "[check]\n\
       tiers.review.dangling = \"warn\"\n\
       [scan]\n\
       packs.markdown.files = ['a']\n";
      "check = { tiers = { review = { dangling = \"warn\" } } }\n\
       scan.packs.markdown = { files = [\"a\"] }\n";
      "\"check\".'tiers'.\"review\".dangling = \"warn\"\n\
       scan . packs . markdown . files = [\n\
      \  \"a\", # a comment\n\
       ]\n";
    ]
  in
  List.iter
    (fun text ->
      let manifest = read text in
      Alcotest.check tier text (Some Finding_class.Warn)
        (Manifest.tier manifest Finding_class.Review Finding_class.Dangling);
      Alcotest.(check (list string))
        text [ "markdown a -" ]
        (List.map pack_summary (Manifest.packs manifest)))
    forms

let a_syntax_error_reports_the_toml_reader () =
  reports "a key with no value" "a =\n"
    [
      ("sinter.toml:1:4: "
      ^
      match Toml.parse "a =\n" with
      | Error e -> Toml.error_message e
      | Ok _ -> "");
    ];
  reports "a dotted key under a later header" "[a.b.c]\nz = 9\n[a]\nb.c.x = 1\n"
    [
      "sinter.toml:4:1: the dotted key 'b.c.x' adds a key to the table \
       'a.b.c', which a table header made; write 'x' under the header [a.b.c]";
    ]

let sinter_spec_errors () =
  reports "a newer version" "sinter-spec = \"1.2\"\nfoo = 1\n"
    [
      "sinter.toml:1:15: this manifest needs specification 1.2, and this \
       sinter implements 1.0; install a newer sinter";
    ];
  reports "an older major version" "sinter-spec = \"0.9\"\n"
    [
      "sinter.toml:1:15: this manifest is for specification 0.9, and this \
       sinter implements 1.0, a new major version that can change the meaning \
       of a key; read the notes on the changes in specification 1.0, then \
       update the manifest and its 'sinter-spec'";
    ];
  reports "a patch number" "sinter-spec = \"1.0.0\"\n"
    [
      "sinter.toml:1:15: 'sinter-spec' takes a version of the form \
       MAJOR.MINOR, such as \"1.0\", not \"1.0.0\"";
    ];
  reports "an integer" "sinter-spec = 1\n"
    [
      "sinter.toml:1:15: 'sinter-spec' takes a version of the form \
       MAJOR.MINOR, such as \"1.0\", not an integer";
    ];
  reports "a minor version of the same major"
    ("sinter-spec = \"1.0\"\n" ^ markdown)
    [ "no error" ]

let the_version_comes_before_the_names () =
  reports "an unknown key after a newer version"
    "sinter-spec = \"2.0\"\n[chek]\n"
    [
      "sinter.toml:1:15: this manifest needs specification 2.0, and this \
       sinter implements 1.0; install a newer sinter";
    ]

let unknown_keys () =
  reports "a near name" "[paths]\nhistoric = []\n"
    [
      "sinter.toml:2:1: unknown key 'historic' in [paths]; did you mean \
       'historical'?";
    ];
  reports "a near kind in [paths]" "[paths]\ndecisions = []\n"
    [
      "sinter.toml:2:1: unknown key 'decisions' in [paths]; did you mean \
       'decision'?";
    ];
  reports "a near kind in [proof]" "[proof]\nreqs = \"approval\"\n"
    [ "sinter.toml:2:1: unknown key 'reqs' in [proof]; did you mean 'req'?" ];
  reports "a near key in [proof]" "[proof]\nverifis = \"each-test\"\n"
    [
      "sinter.toml:2:1: unknown key 'verifis' in [proof]; did you mean \
       'verifies'?";
    ];
  reports "no near name in [paths] or [proof]"
    "[paths]\nfoo = []\n[proof]\nbar = 1\n"
    [
      "sinter.toml:2:1: unknown key 'foo' in [paths]";
      "sinter.toml:4:1: unknown key 'bar' in [proof]";
    ];
  reports "no near name" "[check]\nfoo = 1\n"
    [ "sinter.toml:2:1: unknown key 'foo' in [check]" ];
  reports "a table at the top level" "[chek]\n"
    [
      "sinter.toml:1:2: unknown key 'chek' at the top level; did you mean \
       'check'?";
    ];
  reports "the first part of a dotted key in error"
    "[scan]\npakcs.markdown.files = [\"**/*.md\"]\n"
    [ "sinter.toml:2:1: unknown key 'pakcs' in [scan]; did you mean 'packs'?" ];
  reports "a later part of a dotted key in error"
    (markdown ^ "[check]\ntiers.review.danglng = \"block\"\n")
    [
      "sinter.toml:4:14: unknown finding class 'danglng' in \
       [check.tiers.review]; did you mean 'dangling'?";
    ];
  reports "a key in a pack table" "[scan.packs.ocaml]\nfile = [\"a\"]\n"
    [
      "sinter.toml:2:1: unknown key 'file' in [scan.packs.ocaml]; did you mean \
       'files'?";
    ];
  reports "a tie goes to the first name in byte order" "[prohs]\n"
    [
      "sinter.toml:1:2: unknown key 'prohs' at the top level; did you mean \
       'paths'?";
    ]

let an_old_name_is_an_unknown_name () =
  reports "target" "target = \"trunk\"\n"
    [ "sinter.toml:1:1: unknown key 'target' at the top level" ];
  reports "the gate merge" "[check.tiers.merge]\n"
    [
      "sinter.toml:1:14: unknown gate 'merge' in [check.tiers]; did you mean \
       'merged'?";
    ];
  reports "the gate target" "[check.tiers.target]\n"
    [
      "sinter.toml:1:14: unknown gate 'target' in [check.tiers]; the gates are \
       'turn', 'review', or 'merged'";
    ];
  reports "scan.refs" "[scan]\nrefs.gh = \"[1-9][0-9]*\"\n"
    [ "sinter.toml:2:1: unknown key 'refs' in [scan]" ];
  reports "the table plan" "[plan]\nexempt = []\n"
    [
      "sinter.toml:1:2: unknown key 'plan' at the top level; did you mean \
       'scan'?";
    ];
  reports "plan.locations" "plan.locations.decision = [\"d/\"]\n"
    [
      "sinter.toml:1:1: unknown key 'plan' at the top level; did you mean \
       'scan'?";
    ];
  reports "spec" "spec = \"1.0\"\n"
    [ "sinter.toml:1:1: unknown key 'spec' at the top level" ];
  reports "check.rollout-cap" "[check]\nrollout-cap = true\n"
    [ "sinter.toml:2:1: unknown key 'rollout-cap' in [check]" ];
  reports "the table ledger" "[ledger]\napproval-required = [\"req\"]\n"
    [ "sinter.toml:1:2: unknown key 'ledger' at the top level" ];
  reports "the table evidence" "[evidence]\ntest-coverage = \"required\"\n"
    [ "sinter.toml:1:2: unknown key 'evidence' at the top level" ];
  reports "check.historical" "[check]\nhistorical = [\"docs/\"]\n"
    [ "sinter.toml:2:1: 'historical' belongs in [paths]" ];
  reports "approval-required and test-coverage under [proof]"
    "[proof]\napproval-required = [\"req\"]\ntest-coverage = \"required\"\n"
    [
      "sinter.toml:2:1: unknown key 'approval-required' in [proof]";
      "sinter.toml:3:1: unknown key 'test-coverage' in [proof]";
    ]

let a_name_with_a_control_character_is_escaped () =
  reports "an unknown key" "\"a\\nb\" = 1\n"
    [ "sinter.toml:1:1: unknown key \"a\\nb\" at the top level" ];
  reports "a space is no control character" "\"a b\" = 1\n"
    [ "sinter.toml:1:1: unknown key 'a b' at the top level" ];
  reports "an unknown gate and a pack name"
    (markdown
   ^ "packs.\"x\\ty\".files = [\"a\"]\n\
      [check.tiers]\n\
      \"m\\u007Fe\".dangling = \"warn\"\n")
    [
      "sinter.toml:3:7: \"x\\ty\" is not a pack name; a pack name is \
       lower-case letters and digits, in words joined by '-', such as 'ocaml' \
       or 'tree-sitter'";
      "sinter.toml:5:1: unknown gate \"m\\u007Fe\" in [check.tiers]; the gates \
       are 'turn', 'review', or 'merged'";
    ]

let keys_at_the_wrong_place () =
  reports "a top-level key under a table"
    "[check]\ndefault-branch = \"trunk\"\n"
    [
      "sinter.toml:2:1: 'default-branch' belongs at the top level, above the \
       first table header";
    ];
  reports "a table under another table" "[paths]\ncheck = 1\n"
    [
      "sinter.toml:2:1: 'check' is a table of the top level; write its keys \
       under the header [check]";
    ];
  reports "a key of another table" "[scan]\nwarn-only = true\n"
    [ "sinter.toml:2:1: 'warn-only' belongs in [check]" ];
  reports "a key of a pack" "files = []\n"
    [ "sinter.toml:1:1: 'files' belongs in [scan.packs.<name>]" ];
  reports "a fixed name where a gate goes" "[check.tiers]\nwarn-only = true\n"
    [ "sinter.toml:2:1: 'warn-only' belongs in [check]" ];
  reports "a fixed name where a class goes"
    "[check.tiers.review]\nhistorical = []\n"
    [ "sinter.toml:2:1: 'historical' belongs in [paths]" ];
  reports "a key of [proof] under [paths]" "[paths]\nverifies = \"x\"\n"
    [ "sinter.toml:2:1: 'verifies' belongs in [proof]" ];
  reports "a key of [paths] under [proof]" "[proof]\nexempt = []\n"
    [ "sinter.toml:2:1: 'exempt' belongs in [paths]" ];
  reports "a table where a kind goes" "[paths]\nproof = 1\n"
    [
      "sinter.toml:2:1: 'proof' is a table of the top level; write its keys \
       under the header [proof]";
    ]

let wrong_types () =
  reports "a string for a boolean" "[check]\nwarn-only = \"yes\"\n"
    [ "sinter.toml:2:13: 'warn-only' takes true or false, not a string" ];
  reports "a member that is not a string" "[paths]\nhistorical = [\"a\", 1]\n"
    [
      "sinter.toml:2:20: 'historical' takes an array of strings, and this \
       member is an integer";
    ];
  reports "an integer for a table" "scan = 1\n"
    [ "sinter.toml:1:8: 'scan' takes a table, not an integer" ];
  reports "an array of tables for a table" "[[check]]\n"
    [ "sinter.toml:1:3: 'check' takes a table, not an array of tables" ];
  reports "a table for a string" "[default-branch]\n"
    [ "sinter.toml:1:2: 'default-branch' takes a string, not a table" ];
  reports "a string for an array" "[paths]\nhistorical = \"docs/\"\n"
    [ "sinter.toml:2:14: 'historical' takes an array of strings, not a string" ];
  reports "an array for a word of [proof]"
    "[proof]\nreq = [\"approval\"]\nverifies = true\nagent-markers = \"A\"\n"
    [
      "sinter.toml:2:7: 'req' takes a string, not an array";
      "sinter.toml:3:12: 'verifies' takes a string, not a boolean";
      "sinter.toml:4:17: 'agent-markers' takes an array of strings, not a \
       string";
    ];
  reports "a string for the table of a kind" "[paths]\ndecision = \"d/\"\n"
    [ "sinter.toml:2:12: 'decision' takes an array of strings, not a string" ];
  reports "a float, a date, and a boolean"
    "default-branch = 1.5\n\
     [paths]\n\
     historical = [true]\n\
     [check]\n\
     warn-only = 1979-05-27\n"
    [
      "sinter.toml:1:18: 'default-branch' takes a string, not a float";
      "sinter.toml:3:15: 'historical' takes an array of strings, and this \
       member is a boolean";
      "sinter.toml:5:13: 'warn-only' takes true or false, not a date or a time";
    ]

let names_that_vary () =
  reports "an unknown gate"
    (markdown ^ "[check]\ntiers.trun.dangling = \"warn\"\n")
    [
      "sinter.toml:4:7: unknown gate 'trun' in [check.tiers]; did you mean \
       'turn'?";
    ];
  reports "a gate far from every gate" "[check.tiers.pr]\n"
    [
      "sinter.toml:1:14: unknown gate 'pr' in [check.tiers]; the gates are \
       'turn', 'review', or 'merged'";
    ];
  reports "a class with no tier at the gate"
    "[check.tiers.merged]\nscope-outside-plan = \"warn\"\n"
    [
      "sinter.toml:2:1: 'scope-outside-plan' takes no tier at the gate 'merged'";
    ];
  reports "config-changed, pack-mismatch, and an unknown class"
    "[check.tiers.review]\n\
     config-changed = \"warn\"\n\
     pack-mismatch = \"warn\"\n\
     xyz = \"warn\"\n"
    [
      "sinter.toml:2:1: 'config-changed' takes no tier; it always reports and \
       never blocks";
      "sinter.toml:3:1: 'pack-mismatch' takes no tier at any gate";
      "sinter.toml:4:1: unknown finding class 'xyz' in [check.tiers.review]; \
       'tiers' names built-in finding classes only";
    ];
  reports "config-changed is never a suggestion"
    "[check.tiers.review]\nconfig-chnged = \"warn\"\n"
    [
      "sinter.toml:2:1: unknown finding class 'config-chnged' in \
       [check.tiers.review]; 'tiers' names built-in finding classes only";
    ];
  reports "the suggestion is a class that takes a tier at the gate"
    "[check.tiers.merged]\nbad-scop = \"warn\"\n"
    [
      "sinter.toml:2:1: unknown finding class 'bad-scop' in \
       [check.tiers.merged]; 'tiers' names built-in finding classes only";
    ];
  reports "kinds of locations"
    "[paths]\ndecisions = [\"docs/\"]\nplan = [\"x\"]\nfoo = []\n"
    [
      "sinter.toml:2:1: unknown key 'decisions' in [paths]; did you mean \
       'decision'?";
      "sinter.toml:3:1: 'plan' takes no location; plan files always live under \
       .plans/";
      "sinter.toml:4:1: unknown key 'foo' in [paths]";
    ];
  reports "the location of plans as a dotted key" "paths.plan = [\"x\"]\n"
    [
      "sinter.toml:1:7: 'plan' takes no location; plan files always live under \
       .plans/";
    ];
  reports "pack names and namespaces"
    "[scan.packs.Markdown]\n\
     files = [\"a\"]\n\
     [scan.namespaces]\n\
     GH = \"x\"\n\
     \"a-\" = \"x\"\n\
     \"-a\" = \"x\"\n\
     \"\" = \"x\"\n\
     \"1a\" = \"x\"\n\
     aB = \"x\"\n\
     a_b = \"x\"\n"
    [
      "sinter.toml:1:13: 'Markdown' is not a pack name; a pack name is \
       lower-case letters and digits, in words joined by '-', such as 'ocaml' \
       or 'tree-sitter'";
      "sinter.toml:4:1: 'GH' is not a namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:5:1: 'a-' is not a namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:6:1: '-a' is not a namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:7:1: '' is not a namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:8:1: '1a' is not a namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:9:1: 'aB' is not a namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:10:1: 'a_b' is not a namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
    ];
  reports "names with words and digits"
    (markdown
   ^ "packs.tree-sitter2.files = [\"a\"]\n\
      packs.tree-sitter2.version = \"1.0\"\n\
      namespaces.a1-b2 = \"x\"\n\
      namespaces.z9-a0 = \"x\"\n\
      namespaces.z = \"x\"\n")
    [ "no error" ];
  reports "a version for markdown"
    "[scan.packs.markdown]\nfiles = [\"**/*.md\"]\nversion = \"1.0\"\n"
    [
      "sinter.toml:3:1: the pack markdown is built into sinter and takes no \
       version";
    ]

let values () =
  reports "a default branch that is not a branch name"
    ("default-branch = \"a..b\"\n" ^ markdown)
    [
      "sinter.toml:1:20: \"a..b\" is not a branch name; a branch name cannot \
       hold '..'";
    ];
  reports "a column counts code points"
    ("default-branch = \"\xc3\xa9..b\"\n" ^ markdown)
    [
      "sinter.toml:1:20: \"\xc3\xa9..b\" is not a branch name; a branch name \
       cannot hold '..'";
    ];
  reports "an escape puts the error at the string"
    ("default-branch = \"a\\u002e.b\"\n" ^ markdown)
    [
      "sinter.toml:1:18: \"a..b\" is not a branch name; a branch name cannot \
       hold '..'";
    ];
  reports "globs, packs, and patterns"
    "[scan]\n\
     packs.markdown.files = [\"src/**.ts\", \"!x\", \"!x\"]\n\
     packs.x.files = [\"!a\"]\n\
     packs.y.version = \"1\"\n\
     packs.z.files = []\n\
     packs.w.files = [\"a\"]\n\
     namespaces.gh = \".x\"\n\
     namespaces.jira = \"[0-9]*\"\n"
    [
      "sinter.toml:2:30: \"src/**.ts\" is not a glob: the segment '**.ts' \
       holds '**' and other characters; write '**/*.ts'";
      "sinter.toml:2:44: \"!x\" occurs twice in 'files'";
      "sinter.toml:3:7: the pack x needs 'version', the release that the \
       repository uses, such as \"1.0\"";
      "sinter.toml:3:17: 'files' holds only '!' globs, so it holds no path; \
       add a glob without '!'";
      "sinter.toml:4:7: the pack y needs 'files', the globs of the files that \
       it reads";
      "sinter.toml:4:19: 'version' takes a version of the form MAJOR.MINOR, \
       such as \"1.0\", not \"1\"";
      "sinter.toml:5:7: the pack z needs 'files', the globs of the files that \
       it reads";
      "sinter.toml:5:7: the pack z needs 'version', the release that the \
       repository uses, such as \"1.0\"";
      "sinter.toml:6:7: the pack w needs 'version', the release that the \
       repository uses, such as \"1.0\"";
      "sinter.toml:7:18: '.' is not in the id pattern language; put it in a \
       class, for example [.]";
      "sinter.toml:8:20: the pattern matches an empty id";
    ];
  reports "a pack with files and a bad version"
    (markdown
   ^ "packs.ocaml.files = [\"**/*.ml\"]\npacks.ocaml.version = \"v1\"\n")
    [
      "sinter.toml:4:23: 'version' takes a version of the form MAJOR.MINOR, \
       such as \"1.0\", not \"v1\"";
    ];
  reports "a pack with a bad glob and a version"
    (markdown ^ "packs.ocaml.files = [\"?\"]\npacks.ocaml.version = \"1.0\"\n")
    [
      "sinter.toml:3:23: \"?\" is not a glob: a glob cannot hold '?'; '*' \
       matches any characters inside one name";
    ];
  reports "a ! glob that is not a glob"
    (markdown ^ "[paths]\nhistorical = [\"a\", \"!/b\"]\n")
    [
      "sinter.toml:4:22: \"!/b\" is not a glob: a glob cannot start with '/'; \
       a glob always matches from the repository root";
    ];
  reports "words"
    (markdown
   ^ "[check]\n\
      tiers.review.dangling = \"blok\"\n\
      [proof]\n\
      req = \"aproval\"\n\
      agent-markers = [\"MY-VAR\", \"A\", \"A\", \"1A\", \"\"]\n\
      verifies = \"each-tests\"\n\
      plan = \"declared\"\n")
    [
      "sinter.toml:4:25: 'dangling' takes \"off\", \"warn\", or \"block\", not \
       \"blok\"; did you mean \"block\"?";
      "sinter.toml:6:7: 'req' takes \"declaration\" or \"approval\", not \
       \"aproval\"; did you mean \"approval\"?";
      "sinter.toml:7:18: \"MY-VAR\" is not a name of an environment variable; \
       a name holds letters, digits, and '_', and does not start with a digit";
      "sinter.toml:7:33: \"A\" occurs twice in 'agent-markers'";
      "sinter.toml:7:38: \"1A\" is not a name of an environment variable; a \
       name holds letters, digits, and '_', and does not start with a digit";
      "sinter.toml:7:44: \"\" is not a name of an environment variable; a name \
       holds letters, digits, and '_', and does not start with a digit";
      "sinter.toml:8:12: 'verifies' takes \"whole-run\" or \"each-test\", not \
       \"each-tests\"; did you mean \"each-test\"?";
      "sinter.toml:9:8: 'plan' takes \"declaration\" or \"approval\", not \
       \"declared\"";
    ];
  reports "a word far from every word"
    (markdown ^ "[proof]\nverifies = \"x\"\n")
    [
      "sinter.toml:4:12: 'verifies' takes \"whole-run\" or \"each-test\", not \
       \"x\"";
    ]

let a_manifest_with_no_pack () =
  reports "no pack" "[check]\nwarn-only = true\n"
    [
      "sinter.toml names no pack; add a line such as packs.markdown.files = \
       [\"**/*.md\"] under [scan]";
    ];
  reports "an empty table of packs" "[scan.packs]\n"
    [
      "sinter.toml names no pack; add a line such as packs.markdown.files = \
       [\"**/*.md\"] under [scan]";
    ]

let the_names_come_before_the_values () =
  reports "an unknown key and a bad glob"
    "[check]\nfoo = 1\nwarn-only = 1\n[scan]\npacks.markdown.files = [\"a?\"]\n"
    [
      "sinter.toml:2:1: unknown key 'foo' in [check]";
      "sinter.toml:3:13: 'warn-only' takes true or false, not an integer";
    ]

let a_large_manifest_reads_quickly () =
  let strings format count =
    "[" ^ String.concat ", " (List.init count (Printf.sprintf format)) ^ "]"
  in
  let packs =
    String.concat ""
      (List.init 1_000 (fun i ->
           Printf.sprintf
             "packs.p%d.files = [\"a\"]\npacks.p%d.version = \"1.0\"\n" i i))
  in
  let manifest =
    read
      (markdown ^ packs ^ "[paths]\nhistorical = " ^ strings "\"d%d/\"" 2_000
     ^ "\n[proof]\nagent-markers = " ^ strings "\"M%d\"" 2_000 ^ "\n")
  in
  Alcotest.(check int) "packs" 1_001 (List.length (Manifest.packs manifest));
  Alcotest.(check int)
    "markers" 2_000
    (List.length (Manifest.agent_markers manifest));
  let repeated =
    markdown ^ "[proof]\nagent-markers = " ^ strings "\"M%d\"" 2_000
    ^ "\n[paths]\nhistorical = " ^ strings "\"d%d/\"" 1_999
    |> fun text -> String.sub text 0 (String.length text - 1) ^ ", \"d0/\"]\n"
  in
  match Manifest.of_string repeated with
  | Error [ error ] ->
      Alcotest.(check string)
        "the repeated member at the end" "\"d0/\" occurs twice in 'historical'"
        (Manifest.message error)
  | _ -> Alcotest.fail "one error was expected"

let errors_come_in_the_order_of_their_places () =
  reports "keys written out of order"
    "[check]\nzz = 1\naa = 2\n[proof]\nbb = 3\n"
    [
      "sinter.toml:2:1: unknown key 'zz' in [check]";
      "sinter.toml:3:1: unknown key 'aa' in [check]";
      "sinter.toml:5:1: unknown key 'bb' in [proof]";
    ];
  reports "two errors in one line"
    (markdown ^ "[paths]\nhistorical = [1, 2]\n")
    [
      "sinter.toml:4:15: 'historical' takes an array of strings, and this \
       member is an integer";
      "sinter.toml:4:18: 'historical' takes an array of strings, and this \
       member is an integer";
    ]

let the_example_messages_of_the_specification () =
  let message text =
    match lines text with
    | [ line ] -> (
        match String.index_opt line ' ' with
        | Some i -> String.sub line (i + 1) (String.length line - i - 1)
        | None -> line)
    | other -> String.concat " | " other
  in
  let check text expected =
    Alcotest.(check string) text expected (message text)
  in
  check "[paths]\nhistoric = 1\n"
    "unknown key 'historic' in [paths]; did you mean 'historical'?";
  check "[check]\ndefault-branch = \"trunk\"\n"
    "'default-branch' belongs at the top level, above the first table header";
  check "[check]\nwarn-only = \"x\"\n"
    "'warn-only' takes true or false, not a string";
  check "[scan.packs.markdown]\nfiles = [\"a\"]\nversion = \"1.0\"\n"
    "the pack markdown is built into sinter and takes no version";
  check "[check.tiers.review]\nconfig-changed = \"warn\"\n"
    "'config-changed' takes no tier; it always reports and never blocks";
  check "[check.tiers.merged]\nscope-outside-plan = \"warn\"\n"
    "'scope-outside-plan' takes no tier at the gate 'merged'";
  check
    (markdown ^ "namespaces.gh = \".\"\n")
    "'.' is not in the id pattern language; put it in a class, for example [.]";
  check
    (markdown ^ "namespaces.gh = \"[0-9]*\"\n")
    "the pattern matches an empty id"

let rec value_text node =
  match Toml.value node with
  | Toml.String text -> Toml.basic_string text
  | Toml.Boolean flag -> string_of_bool flag
  | Toml.Integer number -> Int64.to_string number
  | Toml.Array members ->
      "[" ^ String.concat "," (List.map value_text members) ^ "]"
  | Toml.Table table ->
      "{"
      ^ String.concat ","
          (List.map
             (fun ((key : Toml.key), node) -> key.name ^ "=" ^ value_text node)
             table)
      ^ "}"
  | other -> Toml.Kind.name (Toml.Kind.of_value other)

let place (position : Toml.position) =
  Printf.sprintf "%d:%d" position.line position.column

let runner_summary (runner : Manifest.runner) =
  String.concat " "
    (runner.name
    :: (place runner.at.start ^ "-" ^ place runner.at.stop)
    :: List.map
         (fun ((key : Toml.key), node) ->
           key.name ^ "@" ^ place key.at.start ^ "=" ^ value_text node)
         runner.settings)

let pack_runners manifest name =
  match
    List.find_opt
      (fun (pack : Manifest.pack) -> pack.name = name)
      (Manifest.packs manifest)
  with
  | Some pack -> pack.runners
  | None -> Alcotest.failf "no pack %s" name

let runners_of manifest name =
  List.map runner_summary (pack_runners manifest name)

let runners_keep_their_order_and_their_settings () =
  let manifest =
    read
      (markdown
     ^ "packs.ts.files = [\"**/*.ts\"]\n\
        packs.ts.version = \"1.0\"\n\
        packs.ts.runners.vitest.config = \"vitest.config.ts\"\n\
        packs.ts.runners.vitest.coverage = true\n\
        packs.ts.runners.vitest.reporters = [\"junit\", 'json']\n\
        packs.ts.runners.vitest.retries = 2\n\
        packs.ts.runners.vitest.env.CI = \"1\"\n\
        packs.ts.runners.jest = {}\n")
  in
  Alcotest.(check (list string))
    "the runners of ts"
    [
      "vitest 5:18-5:24 config@5:25=\"vitest.config.ts\" coverage@6:25=true \
       reporters@7:25=[\"junit\",\"json\"] retries@8:25=2 env@9:25={CI=\"1\"}";
      "jest 10:18-10:22";
    ]
    (runners_of manifest "ts");
  Alcotest.(check (list string))
    "markdown has no runner" []
    (runners_of manifest "markdown")

let a_pack_with_no_runners_has_none () =
  let manifest =
    read
      (markdown
     ^ "packs.ts.files = [\"a\"]\n\
        packs.ts.version = \"1.0\"\n\
        packs.go.files = [\"b\"]\n\
        packs.go.version = \"1.0\"\n\
        packs.go.runners = {}\n")
  in
  Alcotest.(check (list string)) "no runners key" [] (runners_of manifest "ts");
  Alcotest.(check (list string)) "an empty table" [] (runners_of manifest "go")

let every_form_of_a_runner_table_reads_the_same () =
  let forms =
    [
      "[scan.packs.ts.runners.vitest]\n\
       mode = \"run\"\n\
       [scan.packs.ts]\n\
       files = [\"a\"]\n\
       version = \"1.0\"\n";
      "[scan]\n\
       packs.ts.runners.vitest = { mode = \"run\" }\n\
       packs.ts.files = [\"a\"]\n\
       packs.ts.version = \"1.0\"\n";
      "scan.packs.ts = { runners.vitest.mode = \"run\", files = [\"a\"], \
       version = \"1.0\" }\n";
      "[scan.packs.ts]\n\
       files = [\"a\"]\n\
       version = \"1.0\"\n\
       runners = { vitest = { mode = \"run\" } }\n";
    ]
  in
  List.iter
    (fun text ->
      Alcotest.(check (list (pair string (list string))))
        text
        [ ("vitest", [ "mode=\"run\"" ]) ]
        (List.map
           (fun (runner : Manifest.runner) ->
             ( runner.name,
               List.map
                 (fun ((key : Toml.key), node) ->
                   key.name ^ "=" ^ value_text node)
                 runner.settings ))
           (pack_runners (read text) "ts")))
    forms

let a_dotted_key_can_add_a_key_to_a_table_above_a_header_table () =
  let manifest =
    read
      "[scan.packs.ts.runners.vitest]\n\
       mode = \"run\"\n\
       [scan]\n\
       packs.ts.files = [\"a\"]\n\
       packs.ts.version = \"1.0\"\n"
  in
  Alcotest.(check (list string))
    "the runners of ts"
    [ "vitest 1:24-1:30 mode@2:1=\"run\"" ]
    (runners_of manifest "ts")

let a_runner_can_take_any_name_of_the_layout () =
  let manifest =
    read
      (markdown
     ^ "packs.ts.files = [\"a\"]\n\
        packs.ts.version = \"1.0\"\n\
        packs.ts.runners.files = {}\n\
        packs.ts.runners.version.mode = 1\n\
        packs.ts.runners.runners = {}\n\
        packs.ts.runners.check = {}\n")
  in
  Alcotest.(check (list string))
    "the runners"
    [
      "files 5:18-5:23";
      "version 6:18-6:25 mode@6:26=1";
      "runners 7:18-7:25";
      "check 8:18-8:23";
    ]
    (runners_of manifest "ts")

let ts = "packs.ts.files = [\"a\"]\npacks.ts.version = \"1.0\"\n"

let runner_errors () =
  reports "bad runner names"
    (markdown ^ ts
   ^ "packs.ts.runners.Vitest = {}\n\
      packs.ts.runners.-a = {}\n\
      packs.ts.runners.\"\" = {}\n\
      packs.ts.runners.a_b = {}\n\
      packs.ts.runners.\"x\\ny\" = {}\n")
    [
      "sinter.toml:5:18: 'Vitest' is not a runner name; a runner name is \
       lower-case letters and digits, in words joined by '-', such as 'vitest' \
       or 'cargo-nextest'";
      "sinter.toml:6:18: '-a' is not a runner name; a runner name is \
       lower-case letters and digits, in words joined by '-', such as 'vitest' \
       or 'cargo-nextest'";
      "sinter.toml:7:18: '' is not a runner name; a runner name is lower-case \
       letters and digits, in words joined by '-', such as 'vitest' or \
       'cargo-nextest'";
      "sinter.toml:8:18: 'a_b' is not a runner name; a runner name is \
       lower-case letters and digits, in words joined by '-', such as 'vitest' \
       or 'cargo-nextest'";
      "sinter.toml:9:18: \"x\\ny\" is not a runner name; a runner name is \
       lower-case letters and digits, in words joined by '-', such as 'vitest' \
       or 'cargo-nextest'";
    ];
  reports "a runner in three packs, written out of byte order"
    (markdown
   ^ "packs.c.files = [\"c\"]\n\
      packs.c.version = \"1.0\"\n\
      packs.c.runners.vitest = {}\n\
      packs.a.files = [\"a\"]\n\
      packs.a.version = \"1.0\"\n\
      packs.a.runners.jest = {}\n\
      packs.a.runners.vitest = {}\n\
      packs.b.files = [\"b\"]\n\
      packs.b.version = \"1.0\"\n\
      packs.b.runners.vitest.mode = 1\n\
      packs.b.runners.mocha = {}\n")
    [
      "sinter.toml:5:17: 'vitest' is in the runners of two packs, a and c; \
       remove it from one of them";
      "sinter.toml:12:17: 'vitest' is in the runners of two packs, a and b; \
       remove it from one of them";
    ];
  reports "a bad name in two packs counts once"
    (markdown ^ ts
   ^ "packs.ts.runners.X = {}\n\
      packs.go.files = [\"b\"]\n\
      packs.go.version = \"1.0\"\n\
      packs.go.runners.X = {}\n")
    [
      "sinter.toml:5:18: 'X' is not a runner name; a runner name is lower-case \
       letters and digits, in words joined by '-', such as 'vitest' or \
       'cargo-nextest'";
      "sinter.toml:8:18: 'X' is not a runner name; a runner name is lower-case \
       letters and digits, in words joined by '-', such as 'vitest' or \
       'cargo-nextest'";
    ];
  reports "runners for markdown"
    "[scan.packs.markdown]\nfiles = [\"**/*.md\"]\nrunners.x = {}\nx.mode = 1\n"
    [
      "sinter.toml:3:1: the pack markdown is built into sinter and has no \
       runner";
      "sinter.toml:4:1: unknown key 'x' in [scan.packs.markdown]";
    ];
  reports "a runner table under the pack and not under runners"
    (markdown ^ ts
   ^ "packs.ts.runners.vitest = {}\n\
      packs.ts.vitest.mode = 1\n\
      packs.ts.runner = {}\n")
    [
      "sinter.toml:6:10: unknown key 'vitest' in [scan.packs.ts]";
      "sinter.toml:7:10: unknown key 'runner' in [scan.packs.ts]; did you mean \
       'runners'?";
    ];
  reports "a runner that is not a table"
    (markdown ^ ts
   ^ "packs.ts.runners.vitest = 1\n\
      packs.ts.runners.jest = [{ a = 1 }]\n\
      [[scan.packs.ts.runners.mocha]]\n")
    [
      "sinter.toml:5:27: 'vitest' takes a table, not an integer";
      "sinter.toml:6:25: 'jest' takes a table, not an array";
      "sinter.toml:7:25: 'mocha' takes a table, not an array of tables";
    ];
  reports "an array of runner names is not a table"
    (markdown ^ ts ^ "packs.ts.runners = [\"vitest\"]\n")
    [ "sinter.toml:5:20: 'runners' takes a table, not an array" ];
  reports "a bad name with its table"
    (markdown ^ ts ^ "packs.ts.runners.Vitest.mode = 1\n")
    [
      "sinter.toml:5:18: 'Vitest' is not a runner name; a runner name is \
       lower-case letters and digits, in words joined by '-', such as 'vitest' \
       or 'cargo-nextest'";
    ];
  reports "a runner key out of a pack" "runners = {}\n[check]\nrunners = {}\n"
    [
      "sinter.toml:1:1: 'runners' belongs in [scan.packs.<name>]";
      "sinter.toml:3:1: 'runners' belongs in [scan.packs.<name>]";
    ];
  reports "the names come before the runner values"
    "[scan.packs.markdown]\n\
     files = [\"a\"]\n\
     runners = {}\n\
     [scan.packs.a]\n\
     files = [\"a\"]\n\
     version = \"1.0\"\n\
     runners.vitest = {}\n\
     [scan.packs.b]\n\
     files = [\"b\"]\n\
     version = \"1.0\"\n\
     runners.vitest = {}\n"
    [
      "sinter.toml:3:1: the pack markdown is built into sinter and has no \
       runner";
    ]

let message problem =
  Manifest.message (Manifest.At ({ Toml.line = 1; column = 1 }, problem))

let every_problem_has_a_message () =
  let check name expected problem =
    Alcotest.(check string) name expected (message problem)
  in
  check "a key newer than sinter-spec"
    "'check.foo' needs specification 1.1, and the manifest states sinter-spec \
     = \"1.0\"; write sinter-spec = \"1.1\""
    (Manifest.Key_too_new
       {
         key = [ "check"; "foo" ];
         since = Major_minor.make 1 1;
         sinter_spec = Major_minor.make 1 0;
       });
  check "a wrong type of no key" "'' takes a string, not an integer"
    (Manifest.Wrong_type
       { key = []; expected = Manifest.A_string; found = Toml.Kind.Integer });
  check "a member of no key"
    "'' takes an array of strings, and this member is a float"
    (Manifest.Wrong_member_type { key = []; found = Toml.Kind.Float });
  check "an unknown gate with no near name"
    "unknown gate 'x' in [check.tiers]; the gates are 'turn', 'review', or \
     'merged'"
    (Manifest.Unknown_gate { name = "x"; nearest = None });
  check "a word of a single choice" "'k' takes \"a\", not \"b\""
    (Manifest.Unknown_value
       { key = [ "k" ]; value = "b"; choices = [ "a" ]; nearest = None });
  check "a word of no choice" "'k' takes , not \"b\""
    (Manifest.Unknown_value
       { key = [ "k" ]; value = "b"; choices = []; nearest = None });
  check "a misplaced key whose place is quoted"
    "'x' belongs in [\"a b\".<name>]"
    (Manifest.Misplaced_key { name = "x"; place = [ "a b"; "<name>" ] });
  check "an unknown key in a nested table" "unknown key 'x' in [a.\"b c\"]"
    (Manifest.Unknown_key { name = "x"; table = [ "a"; "b c" ]; nearest = None });
  check "a pattern error" "an alternative of the pattern is empty"
    (Manifest.Bad_id_pattern
       { namespace = "gh"; error = Id_pattern.Empty_alternative 0 });
  Alcotest.(check string)
    "the error of no pack, without a path"
    "the manifest names no pack; add a line such as packs.markdown.files = \
     [\"**/*.md\"] under [scan]"
    (Manifest.message Manifest.No_pack)

let a_value_in_a_message_is_a_toml_string () =
  Alcotest.(check string)
    "the escapes"
    "\"a\\\"b\\\\c\\nd\\te\\u0001f\\u007Fg\xc3\xa9 h\" is not a name of an \
     environment variable; a name holds letters, digits, and '_', and does not \
     start with a digit"
    (message (Manifest.Bad_marker "a\"b\\c\nd\te\001f\127g\xc3\xa9 h"))

let a_table_with_an_empty_name () =
  Alcotest.(check string)
    "the empty name in quotes" "unknown key 'x' in [\"\"]"
    (message
       (Manifest.Unknown_key { name = "x"; table = [ "" ]; nearest = None }))

let a_runner_message_stays_on_one_line () =
  Alcotest.(check string)
    "names that need quotes"
    "\"a\\tb\" is in the runners of two packs, \"c d\" and \"e\\nf\"; remove \
     it from one of them"
    (message
       (Manifest.Runner_in_two_packs
          { runner = "a\tb"; pack = "e\nf"; other = "c d" }));
  Alcotest.(check string)
    "a name with an upper-case letter"
    "'Files' is not a runner name; a runner name is lower-case letters and \
     digits, in words joined by '-', such as 'vitest' or 'cargo-nextest'"
    (message (Manifest.Bad_runner_name "Files"))

let newer_keys_names_each_key_newer_than_sinter_spec () =
  match
    Toml.parse "default-branch = \"a\"\n[check]\nwarn-only = true\nfoo = 1\n"
  with
  | Error _ -> Alcotest.fail "the text does not parse"
  | Ok document ->
      Alcotest.(check (list string))
        "the keys newer than 0.9"
        [
          "s:1:1: 'default-branch' needs specification 1.0, and the manifest \
           states sinter-spec = \"0.9\"; write sinter-spec = \"1.0\"";
          "s:3:1: 'check.warn-only' needs specification 1.0, and the manifest \
           states sinter-spec = \"0.9\"; write sinter-spec = \"1.0\"";
        ]
        (List.map
           (Manifest.render ~path:"s")
           (Manifest.newer_keys ~sinter_spec:(Major_minor.make 0 9) document));
      Alcotest.(check int)
        "no key is newer than 1.0" 0
        (List.length
           (Manifest.newer_keys ~sinter_spec:(Major_minor.make 1 0) document))

let render_names_the_path_and_the_place () =
  Alcotest.(check string)
    "a place" "conf/s.toml:3:14: 'pack-mismatch' takes no tier at any gate"
    (Manifest.render ~path:"conf/s.toml"
       (Manifest.At
          ({ Toml.line = 3; column = 14 }, Manifest.No_tier_at_any_gate)))

let rows () =
  let text =
    In_channel.with_open_bin "../spec/manifest.md" In_channel.input_all
  in
  let rec section = function
    | [] -> []
    | line :: rest when String.starts_with ~prefix:"### 3.2" line -> rest
    | _ :: rest -> section rest
  in
  let rec table acc = function
    | [] -> List.rev acc
    | line :: _ when String.starts_with ~prefix:"### " line -> List.rev acc
    | line :: rest when String.starts_with ~prefix:"| `" line ->
        let cells =
          String.split_on_char '|' line
          |> List.map String.trim
          |> List.filter (fun cell -> cell <> "")
        in
        let key = List.hd cells in
        let key = String.sub key 1 (String.length key - 2) in
        table ((key, List.nth cells (List.length cells - 1)) :: acc) rest
    | _ :: rest -> table acc rest
  in
  table [] (section (String.split_on_char '\n' text))

let since_is_that_of_the_specification () =
  let rows = rows () in
  Alcotest.(check int) "the number of keys" 15 (List.length rows);
  List.iter
    (fun (key, since) ->
      let path =
        List.map
          (fun name -> if name.[0] = '<' then "any" else name)
          (String.split_on_char '.' key)
      in
      Alcotest.(check (option string))
        key (Some since)
        (Option.map Major_minor.to_string (Manifest.since path)))
    rows

let since_of_no_setting_is_none () =
  List.iter
    (fun path ->
      Alcotest.(check bool)
        (String.concat "." path) true
        (Manifest.since path = None))
    [
      [];
      [ "scan" ];
      [ "check"; "tiers"; "review" ];
      [ "foo" ];
      [ "sinter-spec"; "x" ];
      [ "check"; "tiers"; "a"; "b"; "c" ];
      [ "scan"; "packs"; "ts"; "files"; "x" ];
      [ "scan"; "packs"; "ts"; "version"; "x" ];
      [ "scan"; "packs"; "ts"; "runners" ];
      [ "scan"; "packs"; "ts"; "runners"; "x"; "a"; "b" ];
      [ "scan"; "packs"; "ts"; "vitest" ];
      [ "scan"; "packs"; "ts"; "vitest"; "a" ];
    ]

let a_name_that_varies_is_any_name_but_a_fixed_one () =
  List.iter
    (fun path ->
      Alcotest.(check (option string))
        (String.concat "." path) (Some "1.0")
        (Option.map Major_minor.to_string (Manifest.since path)))
    [
      [ "scan"; "packs"; "files"; "files" ];
      [ "scan"; "packs"; "runners"; "runners"; "runners" ];
      [ "scan"; "packs"; "ts"; "runners"; "check"; "files" ];
      [ "scan"; "packs"; "ts"; "runners"; "files" ];
      [ "scan"; "packs"; "ts"; "runners"; "files-2"; "x" ];
      [ "check"; "tiers"; "warn-only"; "files" ];
    ]

let the_implemented_version_is_1_0 () =
  Alcotest.(check string)
    "specification" "1.0"
    (Major_minor.to_string Manifest.specification)

let with_file text f =
  let path = Filename.temp_file "sinter-manifest" ".toml" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      Out_channel.with_open_bin path (fun channel -> output_string channel text);
      f path)

let load_reads_a_file () =
  with_file markdown (fun path ->
      match Manifest.load path with
      | Ok manifest ->
          Alcotest.(check int)
            "one pack" 1
            (List.length (Manifest.packs manifest))
      | Error _ -> Alcotest.fail "the file did not read")

let load_gives_the_errors_of_the_text () =
  with_file "[chek]\n" (fun path ->
      match Manifest.load path with
      | Error
          (Manifest.Invalid
             [ Manifest.At ({ line = 1; column = 2 }, Manifest.Unknown_key _) ])
        ->
          ()
      | _ -> Alcotest.fail "no error of the unknown key")

let load_of_no_file_is_missing () =
  let path =
    Filename.concat
      (Filename.get_temp_dir_name ())
      "sinter-no-such-manifest.toml"
  in
  match Manifest.load path with
  | Error Manifest.Missing -> ()
  | _ -> Alcotest.fail "a file that does not exist is not Missing"

let load_of_a_folder_is_unreadable () =
  match Manifest.load (Filename.get_temp_dir_name ()) with
  | Error (Manifest.Unreadable reason) ->
      Alcotest.(check bool) "a reason" true (String.length reason > 0)
  | _ -> Alcotest.fail "a folder is not Unreadable"

let load_of_a_path_under_a_file_is_missing () =
  with_file markdown (fun path ->
      match Manifest.load (Filename.concat path "x") with
      | Error Manifest.Missing -> ()
      | _ -> Alcotest.fail "a path under a file is not Missing")

let load_of_a_file_it_cannot_open_is_unreadable () =
  with_file markdown (fun path ->
      Unix.chmod path 0;
      match Manifest.load path with
      | Error (Manifest.Unreadable reason) ->
          Alcotest.(check bool) "a reason" true (String.length reason > 0)
      | Ok _ when Unix.geteuid () = 0 -> ()
      | _ -> Alcotest.fail "a file with no read permission is not Unreadable")

let property ?(count = 200) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let line =
  Gen.oneof_list
    [
      "[scan]";
      "[check]";
      "[plan]";
      "[paths]";
      "[proof]";
      "[ledger]";
      "[evidence]";
      "[scan.packs.markdown]";
      "[check.tiers.review]";
      "[[check]]";
      "sinter-spec = \"1.0\"";
      "sinter-spec = \"9.0\"";
      "default-branch = \"main\"";
      "default-branch = \"a..b\"";
      "packs.markdown.files = [\"**/*.md\"]";
      "packs.ocaml.files = [\"**/*.ml\"]";
      "packs.ocaml.version = \"1.0\"";
      "packs.ocaml.runners.dune-test = {}";
      "packs.ocaml.runners.dune-test.mode = 1";
      "packs.rust.runners = [\"dune-test\", \"X\", \"files\", 1]";
      "packs.rust.runners.X = {}";
      "[scan.packs.ocaml.runners.check]";
      "[scan.packs.ocaml]";
      "runners.a = {}";
      "dune-test = 2";
      "files = [\"a\", \"!b\"]";
      "version = \"1\"";
      "namespaces.gh = \"[1-9][0-9]*\"";
      "namespaces.x = \".\"";
      "warn-only = true";
      "warn-only = 1";
      "historical = [\"docs/\"]";
      "tiers.review.dangling = \"block\"";
      "dangling = \"warn\"";
      "config-changed = \"warn\"";
      "exempt = [\"a\", 2]";
      "locations.decision = [\"d/\"]";
      "decision = [\"d/\"]";
      "plan = [\"x\"]";
      "req = \"approval\"";
      "plan = \"declaration\"";
      "verifies = \"each-test\"";
      "verifies = \"all\"";
      "approval-required = [\"req\"]";
      "agent-markers = [\"A\"]";
      "test-coverage = \"required\"";
      "historic = 1";
      "a = {";
      "b.c = 'x'";
      "\"x\\ny\" = 1";
      "tiers.\"m\\re\\u001B\" = {}";
      "# a comment";
      "";
    ]

let text = Gen.(map (String.concat "\n") (list_size (0 -- 8) line))

let damaged =
  Gen.(
    text >>= fun text ->
    let n = String.length text in
    if n = 0 then return text
    else
      int_bound (n - 1) >>= fun i ->
      oneof
        [
          map
            (fun c -> String.mapi (fun j d -> if j = i then c else d) text)
            char;
          return (String.sub text 0 i);
          return
            (String.sub text 0 i
            ^ String.sub text i (n - i)
            ^ String.sub text i (n - i));
        ])

let place_of = function
  | Manifest.At (position, _) -> Some (position.Toml.line, position.column)
  | Manifest.No_pack -> None

let of_string_answers_any_text =
  property ~count:400
    ~name:"of_string answers any text with sorted one-line errors in it"
    ~print:QCheck2.Print.string
    Gen.(oneof [ text; damaged ])
    (fun text ->
      match Manifest.of_string text with
      | Ok manifest -> Manifest.packs manifest <> []
      | Error [] -> false
      | Error errors ->
          let lines = List.length (String.split_on_char '\n' text) in
          let places = List.filter_map place_of errors in
          List.for_all
            (fun (line, column) -> line >= 1 && line <= lines && column >= 1)
            places
          && places = List.sort compare places
          && List.length (List.sort_uniq compare errors) = List.length errors
          && List.mem Manifest.No_pack errors = (errors = [ Manifest.No_pack ])
          && List.for_all
               (fun e ->
                 let message = Manifest.message e in
                 String.length message > 0
                 && (not (String.contains message '\n'))
                 && not (String.contains message '\r'))
               errors)

let settings =
  let some_of choices =
    Gen.(map (List.sort_uniq compare) (list_size (0 -- 3) (oneof_list choices)))
  in
  Gen.(
    let strings items =
      "[" ^ String.concat ", " (List.map (Printf.sprintf "%S") items) ^ "]"
    in
    let optional key value =
      map (fun keep -> if keep then [ (key, value) ] else []) bool
    in
    let globs = some_of [ "docs/"; "a/**/b"; "*.md"; "x" ] in
    let pairs =
      [
        oneof_list [ []; [ ([ "default-branch" ], "\"trunk\"") ] ];
        return
          [
            ( [ "scan"; "packs"; "markdown"; "files" ],
              strings [ "**/*.md"; "!x/" ] );
          ];
        ( optional [ "scan"; "packs"; "ocaml"; "files" ] (strings [ "**/*.ml" ])
        >|= function
          | [] -> []
          | pair ->
              pair @ [ ([ "scan"; "packs"; "ocaml"; "version" ], "\"1.2\"") ] );
        optional [ "scan"; "namespaces"; "gh" ] "\"[1-9][0-9]*\"";
        map (fun b -> [ ([ "check"; "warn-only" ], string_of_bool b) ]) bool;
        some_of
          [
            ("review", "dangling", "warn");
            ("turn", "suspect", "off");
            ("merged", "cycle", "block");
          ]
        >|= List.map (fun (gate, cls, tier) ->
            ([ "check"; "tiers"; gate; cls ], Printf.sprintf "%S" tier));
        map
          (fun g ->
            if g = [] then [] else [ ([ "paths"; "exempt" ], strings g) ])
          globs;
        map
          (fun g ->
            if g = [] then [] else [ ([ "paths"; "historical" ], strings g) ])
          globs;
        map
          (fun g ->
            if g = [] then [] else [ ([ "paths"; "decision" ], strings g) ])
          globs;
        some_of
          [
            ("req", "approval"); ("plan", "approval"); ("design", "declaration");
          ]
        >|= List.map (fun (kind, value) ->
            ([ "proof"; kind ], Printf.sprintf "%S" value));
        map
          (fun m ->
            if m = [] then [] else [ ([ "proof"; "agent-markers" ], strings m) ])
          (some_of [ "A"; "B_2"; "CLAUDECODE" ]);
        optional [ "proof"; "verifies" ] "\"each-test\"";
      ]
    in
    flatten_list pairs >|= List.concat)

let render_dotted settings =
  String.concat ""
    (List.map
       (fun (path, value) -> Toml.render_path path ^ " = " ^ value ^ "\n")
       settings)

let render_by ?(reverse = false) ~depth settings =
  let groups =
    List.fold_left
      (fun groups (path, value) ->
        let table =
          List.filteri (fun i _ -> i < min depth (List.length path - 1)) path
        in
        let rest = List.filteri (fun i _ -> i >= List.length table) path in
        let line = Toml.render_path rest ^ " = " ^ value ^ "\n" in
        match List.assoc_opt table groups with
        | Some lines ->
            (table, lines @ [ line ]) :: List.remove_assoc table groups
        | None -> (table, [ line ]) :: groups)
      [] settings
    |> List.sort compare
  in
  let top, tables = List.partition (fun (table, _) -> table = []) groups in
  String.concat ""
    (List.map
       (fun (table, lines) ->
         (if table = [] then "" else "[" ^ Toml.render_path table ^ "]\n")
         ^ String.concat "" lines)
       (top @ if reverse then List.rev tables else tables))

type tree = Leaf of string | Node of (string * tree) list

let rec add_setting nodes path value =
  match path with
  | [] -> nodes
  | [ name ] -> nodes @ [ (name, Leaf value) ]
  | name :: rest -> (
      match List.assoc_opt name nodes with
      | Some (Node children) ->
          List.map
            (fun (n, tree) ->
              if n = name then (n, Node (add_setting children rest value))
              else (n, tree))
            nodes
      | Some (Leaf _) | None ->
          nodes @ [ (name, Node (add_setting [] rest value)) ])

let rec render_tree = function
  | Leaf value -> value
  | Node children ->
      "{ "
      ^ String.concat ", "
          (List.map
             (fun (name, tree) ->
               Toml.render_path [ name ] ^ " = " ^ render_tree tree)
             children)
      ^ " }"

let render_inline settings =
  String.concat ""
    (List.map
       (fun (name, tree) ->
         Toml.render_path [ name ] ^ " = " ^ render_tree tree ^ "\n")
       (List.fold_left
          (fun nodes (path, value) -> add_setting nodes path value)
          [] settings))

let summary manifest =
  String.concat "\n"
    ([
       Manifest.default_branch manifest;
       string_of_bool (Manifest.warn_only manifest);
       String.concat "," (members (Manifest.historical manifest));
       String.concat "," (members (Manifest.exempt manifest));
       (match Manifest.location manifest Manifest.Decision with
       | None -> "-"
       | Some set -> String.concat "," (members set));
       String.concat ","
         (List.map
            (fun kind ->
              Manifest.approval_name (Manifest.approval manifest kind))
            Manifest.[ Req; Design; Decision; Plan ]);
       String.concat "," (Manifest.agent_markers manifest);
       Manifest.verifies_name (Manifest.verifies manifest);
     ]
    @ List.map pack_summary (Manifest.packs manifest)
    @ List.map
        (fun (ns, p) -> ns ^ "=" ^ Id_pattern.to_string p)
        (Manifest.namespaces manifest)
    @ List.map
        (fun (g, c, t) ->
          String.concat " "
            [
              Finding_class.gate_name g;
              Finding_class.name c;
              Finding_class.tier_name t;
            ])
        (Manifest.written_tiers manifest))

let shuffle seed list =
  List.map (fun x -> (Hashtbl.hash (seed, x), x)) list
  |> List.sort compare |> List.map snd

let every_form_and_order_reads_the_same =
  property ~name:"every TOML form and every order of the keys reads the same"
    ~print:(fun s -> render_dotted s)
    settings
    (fun settings ->
      let reference = summary (read (render_by ~depth:1 settings)) in
      List.for_all
        (fun text -> summary (read text) = reference)
        [
          render_dotted settings;
          render_dotted (shuffle 1 settings);
          render_by ~depth:4 settings;
          render_by ~depth:2 (shuffle 2 settings);
          render_by ~reverse:true ~depth:4 (shuffle 3 settings);
          render_inline (shuffle 4 settings);
        ])

type canonical = {
  branch : string option;
  ocaml : bool;
  gh : bool;
  exempt : string list;
  historical : string list;
  decision : string list;
  approvals : (Manifest.kind * Manifest.approval) list;
  markers : string list;
  each_test : bool option;
  warn_only : bool option;
  tiers : (string * string * string) list;
}

let canonical =
  let some_of choices =
    Gen.(map (List.sort_uniq compare) (list_size (0 -- 3) (oneof_list choices)))
  in
  let globs = some_of [ "docs/"; "a/**/b"; "*.md"; "!x/"; "x" ] in
  let globs =
    Gen.map
      (fun g -> if List.for_all (fun x -> x.[0] = '!') g then [] else g)
      globs
  in
  Gen.(
    let* branch = option (oneof_list [ "trunk"; "release/1.0" ]) in
    let* ocaml = bool in
    let* gh = bool in
    let* exempt = globs in
    let* historical = globs in
    let* decision = globs in
    let* approvals =
      list_size (0 -- 4)
        (pair
           (oneof_list Manifest.[ Req; Design; Decision; Plan ])
           (oneof_list Manifest.[ Declaration; Approval ]))
      >|= List.sort_uniq (fun (a, _) (b, _) -> compare a b)
    in
    let* markers = some_of [ "A"; "B_2"; "CLAUDECODE" ] in
    let* each_test = option bool in
    let* warn_only = option bool in
    let* tiers =
      some_of
        [
          ("review", "dangling", "warn");
          ("turn", "suspect", "off");
          ("merged", "cycle", "block");
        ]
    in
    return
      {
        branch;
        ocaml;
        gh;
        exempt;
        historical;
        decision;
        approvals;
        markers;
        each_test;
        warn_only;
        tiers;
      })

let render_canonical c =
  let strings items =
    "[" ^ String.concat ", " (List.map (Printf.sprintf "%S") items) ^ "]"
  in
  let table name lines =
    if lines = [] then "" else "\n[" ^ name ^ "]\n" ^ String.concat "" lines
  in
  let line key value = key ^ " = " ^ value ^ "\n" in
  let array key items =
    if items = [] then [] else [ line key (strings items) ]
  in
  String.concat ""
    [
      (match c.branch with
      | Some branch -> line "default-branch" (Printf.sprintf "%S" branch)
      | None -> "");
      table "scan"
        ([ line "packs.markdown.files" "[\"**/*.md\"]" ]
        @ (if c.ocaml then
             [
               line "packs.ocaml.files" "[\"**/*.ml\"]";
               line "packs.ocaml.version" "\"1.0\"";
             ]
           else [])
        @ if c.gh then [ line "namespaces.gh" "\"[1-9][0-9]*\"" ] else []);
      table "paths"
        (array "exempt" c.exempt
        @ array "historical" c.historical
        @ array "decision" c.decision);
      table "proof"
        (List.map
           (fun (kind, approval) ->
             line (Manifest.kind_name kind)
               (Printf.sprintf "%S" (Manifest.approval_name approval)))
           c.approvals
        @ array "agent-markers" c.markers
        @
        match c.each_test with
        | Some true -> [ line "verifies" "\"each-test\"" ]
        | Some false -> [ line "verifies" "\"whole-run\"" ]
        | None -> []);
      table "check"
        ((match c.warn_only with
           | Some flag -> [ line "warn-only" (string_of_bool flag) ]
           | None -> [])
        @ List.map
            (fun (gate, cls, tier) ->
              line
                (String.concat "." [ "tiers"; gate; cls ])
                (Printf.sprintf "%S" tier))
            c.tiers);
    ]

let a_manifest_in_the_canonical_form_reads_back_its_values =
  property ~name:"a manifest in the canonical form reads back its values"
    ~print:render_canonical canonical (fun c ->
      let manifest = read (render_canonical c) in
      let kinds = Manifest.[ Req; Design; Decision; Plan ] in
      Manifest.default_branch manifest = Option.value c.branch ~default:"main"
      && (List.map (fun (p : Manifest.pack) -> p.name) (Manifest.packs manifest)
         = if c.ocaml then [ "markdown"; "ocaml" ] else [ "markdown" ])
      && (List.map fst (Manifest.namespaces manifest)
         = if c.gh then [ "gh" ] else [])
      && members (Manifest.exempt manifest) = c.exempt
      && members (Manifest.historical manifest) = c.historical
      && (Option.map members (Manifest.location manifest Manifest.Decision)
         = if c.decision = [] then None else Some c.decision)
      && List.for_all
           (fun kind ->
             Manifest.approval manifest kind
             = Option.value
                 (List.assoc_opt kind c.approvals)
                 ~default:Manifest.Declaration)
           kinds
      && Manifest.agent_markers manifest = c.markers
      && (Manifest.verifies manifest
         =
         if c.each_test = Some true then Manifest.Each_test
         else Manifest.Whole_run)
      && Manifest.warn_only manifest = (c.warn_only = Some true)
      && List.sort compare
           (List.map
              (fun (g, cls, t) ->
                ( Finding_class.gate_name g,
                  Finding_class.name cls,
                  Finding_class.tier_name t ))
              (Manifest.written_tiers manifest))
         = List.sort compare c.tiers)

let runner_pool =
  [
    "vitest";
    "jest";
    "dune-test";
    "cargo-nextest";
    "go-test";
    "r2";
    "check";
    "default-branch";
    "plan";
  ]

let pack_pool = [ "c"; "go"; "ocaml"; "rust"; "typescript" ]
let setting_keys = [ "mode"; "args"; "files"; "default-branch"; "warn-only" ]

let setting_values =
  [
    "\"--ci\"";
    "true";
    "[\"a\", \"b\"]";
    "3";
    "{ k = \"v\" }";
    "[]";
    "1.5";
    "1979-05-27";
    "[{ k = 1 }]";
    "\"\xc3\xbc\xf0\x9f\x98\x80\"";
  ]

type runners_model = {
  packs : (string * string list) list;
  empty : bool;
  runner_settings : (string list * string) list;
}

let take n list = List.filteri (fun i _ -> i < n) list

let rec has_prefix prefix path =
  match (prefix, path) with
  | [], _ -> true
  | p :: ps, n :: ns -> p = n && has_prefix ps ns
  | _ :: _, [] -> false

let without prefix settings =
  List.filter (fun (path, _) -> not (has_prefix prefix path)) settings

let runners_key pack rest = "scan" :: "packs" :: pack :: "runners" :: rest

let runners_model =
  Gen.(
    int_range 1 3 >>= fun count ->
    shuffle_list pack_pool >>= fun packs ->
    shuffle_list runner_pool >>= fun runners ->
    int_bound 6 >>= fun used ->
    list_size (return used) (int_bound (count - 1)) >>= fun owners ->
    let owned = List.combine (take used runners) owners in
    let packs =
      List.mapi
        (fun i pack ->
          ( pack,
            List.filter_map
              (fun (runner, owner) -> if owner = i then Some runner else None)
              owned ))
        (take count packs)
    in
    let settings_of (pack, runner) =
      shuffle_list setting_keys >>= fun keys ->
      int_bound 3 >>= fun n ->
      flatten_list
        (List.map
           (fun key ->
             oneof_list setting_values >|= fun value ->
             (runners_key pack [ runner; key ], value))
           (take n keys))
    in
    flatten_list
      (List.concat_map
         (fun (pack, runners) ->
           List.map (fun runner -> settings_of (pack, runner)) runners)
         packs)
    >>= fun settings ->
    bool >|= fun empty ->
    { packs; empty; runner_settings = List.concat settings })

let runner_entries model =
  List.concat_map
    (fun (pack, runners) ->
      if runners = [] then
        if model.empty then [ (runners_key pack [], "{}") ] else []
      else
        List.filter_map
          (fun runner ->
            if
              List.exists
                (fun (path, _) -> has_prefix (runners_key pack [ runner ]) path)
                model.runner_settings
            then None
            else Some (runners_key pack [ runner ], "{}"))
          runners)
    model.packs
  @ model.runner_settings

let manifest_settings packs entries =
  ([ "scan"; "packs"; "markdown"; "files" ], "[\"**/*.md\"]")
  :: List.concat_map
       (fun pack ->
         [
           ( [ "scan"; "packs"; pack; "files" ],
             Printf.sprintf "[\"**/*.%s\"]" pack );
           ([ "scan"; "packs"; pack; "version" ], "\"1.0\"");
         ])
       packs
  @ entries

let rendered settings =
  Gen.(
    pair (shuffle_list settings)
      (oneof_list
         [
           render_dotted;
           (fun s -> render_by ~depth:1 s);
           (fun s -> render_by ~depth:2 s);
           (fun s -> render_by ~depth:4 s);
           (fun s -> render_by ~reverse:true ~depth:4 s);
           render_inline;
         ])
    >|= fun (settings, render) -> (settings, render settings))

let offset_of text (position : Toml.position) =
  let length = String.length text in
  let rec skip i =
    if i < length && Char.code text.[i] land 0xC0 = 0x80 then skip (i + 1)
    else i
  in
  let rec go i line column =
    if i >= length || (line = position.line && column = position.column) then i
    else if text.[i] = '\n' then go (i + 1) (line + 1) 1
    else go (skip (i + 1)) line (column + 1)
  in
  go 0 1 1

let position_of text offset =
  let line = ref 1 and column = ref 1 in
  String.iteri
    (fun i c ->
      if i < offset then
        if c = '\n' then begin
          incr line;
          column := 1
        end
        else if Char.code c land 0xC0 <> 0x80 then incr column)
    text;
  { Toml.line = !line; column = !column }

let text_of text (span : Toml.span) =
  let start = offset_of text span.start in
  String.sub text start (offset_of text span.stop - start)

let runners_read_as_written =
  property ~count:300
    ~name:"runners and runner settings read as written, in every form and order"
    ~print:(fun (_, _, text) -> text)
    Gen.(
      runners_model >>= fun model ->
      rendered
        (manifest_settings (List.map fst model.packs) (runner_entries model))
      >|= fun (settings, text) -> (model, settings, text))
    (fun (model, settings, text) ->
      let in_the_file pack runner =
        List.filter_map
          (function
            | [ "scan"; "packs"; p; "runners"; r; key ], value
              when p = pack && r = runner -> (
                match Toml.parse ("v = " ^ value) with
                | Ok [ (_, node) ] -> Some (key, value_text node)
                | _ -> Some (key, "not a TOML value: " ^ value))
            | _ -> None)
          settings
      in
      let packs = Manifest.packs (read text) in
      List.length packs = List.length model.packs + 1
      && List.for_all
           (fun (pack : Manifest.pack) ->
             List.sort compare
               (List.map
                  (fun (runner : Manifest.runner) -> runner.name)
                  pack.runners)
             = List.sort compare
                 (Option.value ~default:[]
                    (List.assoc_opt pack.name model.packs))
             && List.for_all
                  (fun (runner : Manifest.runner) ->
                    text_of text runner.at = Toml.render_path [ runner.name ]
                    && List.map
                         (fun ((key : Toml.key), node) ->
                           (key.name, value_text node))
                         runner.settings
                       = in_the_file pack.name runner.name
                    && List.for_all
                         (fun ((key : Toml.key), _) ->
                           text_of text key.at = Toml.render_path [ key.name ])
                         runner.settings)
                  pack.runners)
           packs)

type locate = Only of string | Last of string | Before of string * string

let is_word_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' -> true
  | _ -> false

let occurrences token text =
  let n = String.length token in
  List.filter
    (fun i ->
      String.sub text i n = token
      && ((not (is_word_char token.[0]))
         || i = 0
         || not (is_word_char text.[i - 1]))
      && ((not (is_word_char token.[n - 1]))
         || i + n = String.length text
         || not (is_word_char text.[i + n])))
    (List.init (max 0 (String.length text - n + 1)) Fun.id)

let locate text = function
  | Only token -> (
      match occurrences token text with
      | [ i ] -> Some (position_of text i)
      | _ -> None)
  | Last token -> (
      match List.rev (occurrences token text) with
      | i :: _ -> Some (position_of text i)
      | [] -> None)
  | Before (word, token) -> (
      match occurrences token text with
      | [ i ] -> (
          match
            List.rev (List.filter (fun j -> j < i) (occurrences word text))
          with
          | j :: _ -> Some (position_of text j)
          | [] -> None)
      | _ -> None)

let bad_runner_names =
  [ "Vitest"; "1x"; "x-"; "-x"; "x--y"; "x_y"; ""; "a.b"; "\xc3\xa9" ]

let stray_names runners =
  let in_use =
    pack_pool @ runner_pool @ setting_keys
    @ [ "files"; "version"; "runners"; "scan"; "packs"; "markdown"; "true" ]
  in
  List.concat_map
    (fun name ->
      List.init (String.length name) (fun i ->
          String.sub name 0 i
          ^ String.sub name (i + 1) (String.length name - i - 1)))
    runners
  @ [ "mocha"; "runner"; "versions"; "file" ]
  |> List.filter (fun name ->
      String.length name >= 3 && not (List.mem name in_use))

let faults model =
  let entries = runner_entries model in
  let owned =
    List.concat_map
      (fun (pack, runners) -> List.map (fun runner -> (pack, runner)) runners)
      model.packs
  in
  let open Gen in
  let bad_name =
    oneof_list model.packs >>= fun (pack, _) ->
    oneof_list bad_runner_names >>= fun bad ->
    bool >|= fun with_setting ->
    ( List.filter (fun (path, _) -> path <> runners_key pack []) entries
      @ [
          (if with_setting then (runners_key pack [ bad; "mode" ], "1")
           else (runners_key pack [ bad ], "{}"));
        ],
      Manifest.Bad_runner_name bad,
      Only (Toml.render_path [ bad ]) )
  and stray_table =
    oneof_list model.packs >>= fun (pack, runners) ->
    oneof_list (stray_names runners) >|= fun name ->
    ( entries @ [ ([ "scan"; "packs"; pack; name; "mode" ], "1") ],
      Manifest.Unknown_key
        {
          name;
          table = [ "scan"; "packs"; pack ];
          nearest = Edit_distance.nearest name [ "files"; "version"; "runners" ];
        },
      Only name )
  and markdown_runners =
    oneof_list [ "{ md-runner = {} }"; "[\"md-runner\"]"; "'md-runner'" ]
    >|= fun value ->
    ( entries @ [ (runners_key "markdown" [], value) ],
      Manifest.Markdown_runners,
      Before ("runners", "md-runner") )
  and runners_not_a_table =
    oneof_list model.packs >>= fun (pack, _) ->
    oneof_list
      [
        ("'one'", Toml.Kind.String);
        ("44", Toml.Kind.Integer);
        ("[\"vitest\"]", Toml.Kind.Array);
        ("08:00:00", Toml.Kind.Datetime);
        ("false", Toml.Kind.Boolean);
      ]
    >|= fun (value, found) ->
    ( without (runners_key pack []) entries @ [ (runners_key pack [], value) ],
      Manifest.Wrong_type
        { key = runners_key pack []; expected = Manifest.A_table; found },
      Only value )
  in
  let not_a_table () =
    oneof_list owned >>= fun (pack, runner) ->
    oneof_list
      [
        ("'x'", Toml.Kind.String);
        ("false", Toml.Kind.Boolean);
        ("17", Toml.Kind.Integer);
        ("[1]", Toml.Kind.Array);
        ("2.5", Toml.Kind.Float);
        ("07:32:00", Toml.Kind.Datetime);
      ]
    >|= fun (value, found) ->
    ( without (runners_key pack [ runner ]) entries
      @ [ (runners_key pack [ runner ], value) ],
      Manifest.Wrong_type
        {
          key = runners_key pack [ runner ];
          expected = Manifest.A_table;
          found;
        },
      Only value )
  and in_two_packs pairs =
    oneof_list pairs >|= fun (pack, runner, later) ->
    ( without (runners_key later []) entries
      @ [ (runners_key later [], "{ '" ^ runner ^ "' = {} }") ],
      Manifest.Runner_in_two_packs { runner; pack = later; other = pack },
      Only ("'" ^ runner ^ "'") )
  in
  let pairs =
    List.concat_map
      (fun (pack, runner) ->
        List.filter_map
          (fun (later, _) ->
            if String.compare later pack > 0 then Some (pack, runner, later)
            else None)
          model.packs)
      owned
  in
  oneof
    ([ bad_name; stray_table; markdown_runners; runners_not_a_table ]
    @ (if owned = [] then [] else [ not_a_table () ])
    @ if pairs = [] then [] else [ in_two_packs pairs ])

let one_fault_gives_its_one_error =
  property ~count:300
    ~name:
      "one fault in the runners gives its one error, in every form and order"
    ~print:(fun (text, problem, _) ->
      text ^ "\nthe error that was expected: " ^ message problem)
    Gen.(
      runners_model >>= fun model ->
      faults model >>= fun (entries, problem, at) ->
      rendered (manifest_settings (List.map fst model.packs) entries)
      >|= fun (_, text) -> (text, problem, at))
    (fun (text, problem, at) ->
      match (locate text at, Manifest.of_string text) with
      | Some position, Error errors ->
          errors = [ Manifest.At (position, problem) ]
      | _ -> false)

let case name test = Alcotest.test_case name `Quick test

let the_document_keeps_every_key_with_its_place () =
  let manifest =
    read
      "default-branch = \"trunk\"\n\
       [scan]\n\
       packs.markdown.files = [\"**/*.md\"]\n"
  in
  let rec paths prefix table =
    List.concat_map
      (fun ((key : Toml.key), node) ->
        let path = prefix @ [ key.name ] in
        let start = (Toml.span node).start in
        let here =
          Printf.sprintf "%s %d:%d" (String.concat "." path) start.line
            start.column
        in
        match Toml.value node with
        | Toml.Table table -> here :: paths path table
        | _ -> [ here ])
      table
  in
  Alcotest.(check (list string))
    "the keys and the places of their values"
    [
      "default-branch 1:18";
      "scan 2:2";
      "scan.packs 3:1";
      "scan.packs.markdown 3:7";
      "scan.packs.markdown.files 3:24";
    ]
    (paths [] (Manifest.document manifest))

let a_name_follows_the_pattern_of_a_pack_name () =
  List.iter
    (fun (name, expected) ->
      Alcotest.(check bool)
        (Printf.sprintf "%S" name) expected (Manifest.is_name name))
    [
      ("ocaml", true);
      ("tree-sitter", true);
      ("a1-b2", true);
      ("x", true);
      ("", false);
      ("1a", false);
      ("-a", false);
      ("a-", false);
      ("a--b", false);
      ("Ab", false);
      ("a.b", false);
      ("a=b", false);
      ("a b", false);
      ("a_b", false);
    ]

let tests =
  [
    case "the document keeps every key with its place"
      the_document_keeps_every_key_with_its_place;
    case "a name follows the pattern of a pack name"
      a_name_follows_the_pattern_of_a_pack_name;
    case "the smallest manifest takes every default"
      the_smallest_manifest_takes_every_default;
    case "the example of sinter reads" the_example_of_sinter_reads;
    case "the example of a typescript project reads"
      the_example_of_a_typescript_project_reads;
    case "the tier that applies follows the three rules"
      the_tier_that_applies_follows_the_three_rules;
    case "without warn-only the built-in tier applies"
      without_warn_only_the_built_in_tier_applies;
    case "written tiers are sorted" written_tiers_are_sorted;
    case "built-in paths join the written ones"
      built_in_paths_join_the_written_ones;
    case "agent markers keep their order" agent_markers_keep_their_order;
    case "each kind takes its own approval" each_kind_takes_its_own_approval;
    case "each word of proof has its name" each_word_of_proof_has_its_name;
    case "every location kind reads" every_location_kind_reads;
    case "a default branch reads" a_default_branch_reads;
    case "an empty array is an absent key" an_empty_array_is_an_absent_key;
    case "every form of TOML means the same" every_form_of_toml_means_the_same;
    case "a syntax error reports the TOML reader"
      a_syntax_error_reports_the_toml_reader;
    case "sinter-spec errors" sinter_spec_errors;
    case "the version comes before the names" the_version_comes_before_the_names;
    case "unknown keys" unknown_keys;
    case "an old name is an unknown name" an_old_name_is_an_unknown_name;
    case "a name with a control character is escaped"
      a_name_with_a_control_character_is_escaped;
    case "keys at the wrong place" keys_at_the_wrong_place;
    case "wrong types" wrong_types;
    case "names that vary" names_that_vary;
    case "values" values;
    case "a manifest with no pack" a_manifest_with_no_pack;
    case "the names come before the values" the_names_come_before_the_values;
    case "a large manifest reads quickly" a_large_manifest_reads_quickly;
    case "errors come in the order of their places"
      errors_come_in_the_order_of_their_places;
    case "the example messages of the specification"
      the_example_messages_of_the_specification;
    case "runners keep their order and their settings"
      runners_keep_their_order_and_their_settings;
    case "a pack with no runners has none" a_pack_with_no_runners_has_none;
    case "every form of a runner table reads the same"
      every_form_of_a_runner_table_reads_the_same;
    case "a dotted key can add a key to a table above a header table"
      a_dotted_key_can_add_a_key_to_a_table_above_a_header_table;
    case "a runner can take any name of the layout"
      a_runner_can_take_any_name_of_the_layout;
    case "runner errors" runner_errors;
    case "every problem has a message" every_problem_has_a_message;
    case "render names the path and the place"
      render_names_the_path_and_the_place;
    case "a value in a message is a TOML string"
      a_value_in_a_message_is_a_toml_string;
    case "a table with an empty name" a_table_with_an_empty_name;
    case "a runner message stays on one line" a_runner_message_stays_on_one_line;
    case "since is that of the specification" since_is_that_of_the_specification;
    case "since of no setting is none" since_of_no_setting_is_none;
    case "a name that varies is any name but a fixed one"
      a_name_that_varies_is_any_name_but_a_fixed_one;
    case "the implemented version is 1.0" the_implemented_version_is_1_0;
    case "load reads a file" load_reads_a_file;
    case "load gives the errors of the text" load_gives_the_errors_of_the_text;
    case "load of no file is missing" load_of_no_file_is_missing;
    case "load of a folder is unreadable" load_of_a_folder_is_unreadable;
    case "load of a path under a file is missing"
      load_of_a_path_under_a_file_is_missing;
    case "load of a file it cannot open is unreadable"
      load_of_a_file_it_cannot_open_is_unreadable;
    case "newer_keys names each key newer than sinter-spec"
      newer_keys_names_each_key_newer_than_sinter_spec;
    of_string_answers_any_text;
    every_form_and_order_reads_the_same;
    a_manifest_in_the_canonical_form_reads_back_its_values;
    runners_read_as_written;
    one_fault_gives_its_one_error;
  ]
