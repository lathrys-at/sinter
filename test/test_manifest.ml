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

(* The examples of the specification. *)

let the_smallest_manifest_takes_every_default () =
  let manifest = read markdown in
  Alcotest.(check (option string))
    "spec" None
    (Option.map Major_minor.to_string (Manifest.spec manifest));
  Alcotest.(check string) "target" "main" (Manifest.target manifest);
  Alcotest.(check bool) "rollout-cap" false (Manifest.rollout_cap manifest);
  Alcotest.(check bool)
    "coverage-attribution" true
    (Manifest.coverage_attribution manifest = Manifest.Optional);
  Alcotest.(check int)
    "no ref namespace" 0
    (List.length (Manifest.ref_namespaces manifest));
  Alcotest.(check int)
    "no written tier" 0
    (List.length (Manifest.written_tiers manifest));
  Alcotest.(check bool)
    "no historical member" true
    (Path_set.is_empty (Manifest.historical manifest));
  Alcotest.(check bool)
    "no ambient member" true
    (Path_set.is_empty (Manifest.ambient manifest));
  Alcotest.(check bool)
    "no shared member" true
    (Path_set.is_empty (Manifest.shared manifest));
  Alcotest.(check bool)
    "no location" true
    (List.for_all
       (fun kind -> Manifest.location manifest kind = None)
       Manifest.[ Req; Design; Decision; Plan ]);
  Alcotest.(check int)
    "no kind needs approval" 0
    (List.length (Manifest.approval_required manifest));
  Alcotest.(check (list string))
    "no harness marker" []
    (Manifest.harness_markers manifest)

let members set = List.map Path_set.member_to_string (Path_set.members set)

let pack_summary (pack : Manifest.pack) =
  Printf.sprintf "%s %s %s" pack.name
    (String.concat "," (members pack.files))
    (match pack.version with
    | None -> "-"
    | Some version -> Major_minor.to_string version)

let sinter_example =
  {|spec = "1.0"

[scan]
packs.markdown.files = ["**/*.md"]
packs.ocaml.files = ["**/*.ml", "**/*.mli"]
packs.ocaml.version = "1.0"
packs.rust.files = ["**/*.rs"]
packs.rust.version = "1.0"
refs.gh = "[1-9][0-9]*"

[check]
rollout-cap = true

[plan]
ambient = [
  "bridge/Cargo.lock",
  "sinter.opam",
  "sinter.opam.locked",
]
shared = [
  ".gitignore",
  "LICENSES/",
  "REUSE.toml",
  "THIRD_PARTY.md",
  "bridge/Cargo.toml",
  "dune-project",
]
locations.decision = ["docs/decisions/"]
|}

let the_example_of_sinter_reads () =
  let manifest = read sinter_example in
  Alcotest.(check (option string))
    "spec" (Some "1.0")
    (Option.map Major_minor.to_string (Manifest.spec manifest));
  Alcotest.(check (list string))
    "packs"
    [ "markdown **/*.md -"; "ocaml **/*.ml,**/*.mli 1.0"; "rust **/*.rs 1.0" ]
    (List.map pack_summary (Manifest.packs manifest));
  Alcotest.(check (list (pair string string)))
    "refs"
    [ ("gh", "[1-9][0-9]*") ]
    (List.map
       (fun (ns, pattern) -> (ns, Id_pattern.to_string pattern))
       (Manifest.ref_namespaces manifest));
  Alcotest.(check bool) "rollout-cap" true (Manifest.rollout_cap manifest);
  Alcotest.(check (list string))
    "ambient"
    [ "bridge/Cargo.lock"; "sinter.opam"; "sinter.opam.locked" ]
    (members (Manifest.ambient manifest));
  Alcotest.(check (list string))
    "shared"
    [
      ".gitignore";
      "LICENSES/";
      "REUSE.toml";
      "THIRD_PARTY.md";
      "bridge/Cargo.toml";
      "dune-project";
    ]
    (members (Manifest.shared manifest));
  Alcotest.(check (option (list string)))
    "the location of decisions" (Some [ "docs/decisions/" ])
    (Option.map members (Manifest.location manifest Manifest.Decision));
  Alcotest.(check (option (list string)))
    "the location of requirements" None
    (Option.map members (Manifest.location manifest Manifest.Req))

let typescript_example =
  {|spec = "1.0"

[scan]
packs.markdown.files = ["**/*.md", "!test/fixtures/"]
packs.typescript.files = ["**/*.ts", "!**/*.d.ts"]
packs.typescript.version = "1.0"
refs.gh = "[1-9][0-9]*"
refs.jira = "[A-Z]+-[1-9][0-9]*"

[check]
rollout-cap = true
historical = ["docs/devlog/"]
tiers.merge.dangling = "block"
tiers.target.dangling = "block"

[plan]
ambient = ["package-lock.json"]
shared = [".gitignore", "LICENSE", "package.json", "tsconfig.json"]
locations.decision = ["docs/decisions/"]

[ledger]
approval-required = ["req"]

[evidence]
coverage-attribution = "required"
|}

let the_example_of_a_typescript_project_reads () =
  let manifest = read typescript_example in
  Alcotest.(check (list string))
    "packs"
    [
      "markdown **/*.md,!test/fixtures/ -"; "typescript **/*.ts,!**/*.d.ts 1.0";
    ]
    (List.map pack_summary (Manifest.packs manifest));
  Alcotest.(check (list string))
    "the namespaces, sorted" [ "gh"; "jira" ]
    (List.map fst (Manifest.ref_namespaces manifest));
  Alcotest.(check (list string))
    "historical" [ "docs/devlog/" ]
    (members (Manifest.historical manifest));
  Alcotest.(check int)
    "two written tiers" 2
    (List.length (Manifest.written_tiers manifest));
  Alcotest.(check bool)
    "approval" true
    (Manifest.approval_required manifest = [ Manifest.Req ]);
  Alcotest.(check bool)
    "coverage-attribution" true
    (Manifest.coverage_attribution manifest = Manifest.Required)

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
  check "a written tier passes the cap" (Some Finding_class.Block)
    Finding_class.Merge Finding_class.Dangling;
  check "the cap lowers a built-in block" (Some Finding_class.Warn)
    Finding_class.Turn Finding_class.Dangling;
  check "the cap leaves a built-in warn" (Some Finding_class.Warn)
    Finding_class.Turn Finding_class.Typo_tag;
  check "the cap leaves a built-in off" (Some Finding_class.Off)
    Finding_class.Turn Finding_class.Unstamped;
  check "a class with no tier at the gate" None Finding_class.Target
    Finding_class.Bad_scope;
  check "pack-drift takes no tier" None Finding_class.Merge
    Finding_class.Pack_drift

let without_the_cap_the_built_in_tier_applies () =
  let manifest = read (markdown ^ "[check]\ntiers.turn.dangling = \"off\"\n") in
  Alcotest.check tier "a built-in block stays" (Some Finding_class.Block)
    (Manifest.tier manifest Finding_class.Merge Finding_class.Dangling);
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
        tiers.target.suspect = \"warn\"\n\
        tiers.turn.dangling = \"off\"\n\
        tiers.turn.parse-error = \"block\"\n")
  in
  Alcotest.(check (list string))
    "gate, then class"
    [ "turn parse-error block"; "turn dangling off"; "target suspect warn" ]
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
     ^ "[check]\n\
        historical = [\"docs/devlog/\", \"!docs/devlog/keep.md\"]\n\
        [plan]\n\
        ambient = [\"gen/\", \"!.plans/**\"]\n")
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
  let ambient =
    Manifest.is_ambient manifest
      ~plan_file:(fun path -> path = ".plans/a.md")
      ~manifest:(Some "conf/sinter.toml")
  in
  Alcotest.(check bool) "a plan file is ambient" true (ambient ".plans/a.md");
  Alcotest.(check bool)
    "the manifest is ambient" true
    (ambient "conf/sinter.toml");
  Alcotest.(check bool) "the lock file is ambient" true (ambient "sinter.lock");
  Alcotest.(check bool) "a written member" true (ambient "gen/x.ml");
  Alcotest.(check bool) "another file" false (ambient "src/x.ml");
  Alcotest.(check bool)
    "a manifest outside the repository" false
    (Manifest.is_ambient manifest
       ~plan_file:(fun _ -> false)
       ~manifest:None "sinter.toml");
  Alcotest.(check string)
    "the built-in historical glob" ".plans/**/*.log.md"
    Manifest.builtin_historical;
  Alcotest.(check string) "the lock file" "sinter.lock" Manifest.lock_file

let harness_markers_keep_their_order () =
  let manifest =
    read
      (markdown
     ^ "[ledger]\n\
        harness-markers = [\"B_1\", \"_a\", \"CLAUDECODE\", \"z\", \"Zz_09\", \
        \"A9\"]\n")
  in
  Alcotest.(check (list string))
    "the markers"
    [ "B_1"; "_a"; "CLAUDECODE"; "z"; "Zz_09"; "A9" ]
    (Manifest.harness_markers manifest)

let approval_kinds_keep_their_order () =
  let manifest =
    read
      (markdown
     ^ "[ledger]\n\
        approval-required = [\"plan\", \"req\", \"design\", \"decision\"]\n")
  in
  Alcotest.(check (list string))
    "the kinds"
    [ "plan"; "req"; "design"; "decision" ]
    (List.map Manifest.kind_name (Manifest.approval_required manifest))

let every_location_kind_reads () =
  let manifest =
    read
      (markdown
     ^ "[plan.locations]\n\
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

let a_target_branch_reads () =
  Alcotest.(check string)
    "target" "release/1.0"
    (Manifest.target (read ("target = \"release/1.0\"\n" ^ markdown)))

let an_empty_array_is_an_absent_key () =
  let manifest =
    read
      (markdown
     ^ "[check]\n\
        historical = []\n\
        [ledger]\n\
        approval-required = []\n\
        [plan.locations]\n\
        req = []\n")
  in
  Alcotest.(check bool)
    "historical" true
    (Path_set.is_empty (Manifest.historical manifest));
  Alcotest.(check int)
    "approval" 0
    (List.length (Manifest.approval_required manifest));
  Alcotest.(check bool)
    "no location" true
    (Option.is_none (Manifest.location manifest Manifest.Req))

let every_form_of_toml_means_the_same () =
  let forms =
    [
      "[check.tiers.merge]\n\
       dangling = \"warn\"\n\
       [scan.packs.markdown]\n\
       files = [\"a\"]\n";
      "[check]\n\
       tiers.merge.dangling = \"warn\"\n\
       [scan]\n\
       packs.markdown.files = ['a']\n";
      "check = { tiers = { merge = { dangling = \"warn\" } } }\n\
       scan.packs.markdown = { files = [\"a\"] }\n";
      "\"check\".'tiers'.\"merge\".dangling = \"warn\"\n\
       scan . packs . markdown . files = [\n\
      \  \"a\", # a comment\n\
       ]\n";
    ]
  in
  List.iter
    (fun text ->
      let manifest = read text in
      Alcotest.check tier text (Some Finding_class.Warn)
        (Manifest.tier manifest Finding_class.Merge Finding_class.Dangling);
      Alcotest.(check (list string))
        text [ "markdown a -" ]
        (List.map pack_summary (Manifest.packs manifest)))
    forms

(* Errors, as the lines that report them. *)

let a_syntax_error_reports_the_toml_reader () =
  reports "a key with no value" "a =\n"
    [
      ("sinter.toml:1:4: "
      ^
      match Toml.parse "a =\n" with
      | Error e -> Toml.error_message e
      | Ok _ -> "");
    ];
  reports "a dotted key under a later header" "[a.b.c]\nz = 9\n[a]\nb.ct = 1\n"
    [
      "sinter.toml:4:1: the dotted key 'b.ct' adds a key to the table 'a.b', \
       which a table header made; write 'ct' under the header [a.b]";
    ]

let spec_errors () =
  reports "a newer version" "spec = \"1.2\"\nfoo = 1\n"
    [
      "sinter.toml:1:8: this manifest needs specification 1.2, and this sinter \
       implements 1.0; install a newer sinter";
    ];
  reports "an older major version" "spec = \"0.9\"\n"
    [
      "sinter.toml:1:8: this manifest is for specification 0.9, and this \
       sinter implements 1.0, a new major version that can change the meaning \
       of a key; read the notes on the changes in specification 1.0, then \
       update the manifest and its 'spec'";
    ];
  reports "a patch number" "spec = \"1.0.0\"\n"
    [
      "sinter.toml:1:8: 'spec' takes a version of the form MAJOR.MINOR, such \
       as \"1.0\", not \"1.0.0\"";
    ];
  reports "an integer" "spec = 1\n"
    [
      "sinter.toml:1:8: 'spec' takes a version of the form MAJOR.MINOR, such \
       as \"1.0\", not an integer";
    ];
  reports "a minor version of the same major"
    ("spec = \"1.0\"\n" ^ markdown)
    [ "no error" ]

let the_version_comes_before_the_names () =
  reports "an unknown key after a newer version" "spec = \"2.0\"\n[chek]\n"
    [
      "sinter.toml:1:8: this manifest needs specification 2.0, and this sinter \
       implements 1.0; install a newer sinter";
    ]

let unknown_keys () =
  reports "a near name" "[check]\nhistoric = []\n"
    [
      "sinter.toml:2:1: unknown key 'historic' in [check]; did you mean \
       'historical'?";
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
    (markdown ^ "[check]\ntiers.merge.danglng = \"block\"\n")
    [
      "sinter.toml:4:13: unknown finding class 'danglng' in \
       [check.tiers.merge]; did you mean 'dangling'?";
    ];
  reports "a key in a pack table" "[scan.packs.ocaml]\nfile = [\"a\"]\n"
    [
      "sinter.toml:2:1: unknown key 'file' in [scan.packs.ocaml]; did you mean \
       'files'?";
    ];
  reports "a tie goes to the first name in byte order" "[plan]\nshare = []\n"
    [ "sinter.toml:2:1: unknown key 'share' in [plan]; did you mean 'shared'?" ]

let keys_at_the_wrong_place () =
  reports "a top-level key under a table" "[evidence]\ntarget = \"trunk\"\n"
    [
      "sinter.toml:2:1: 'target' belongs at the top level, above the first \
       table header";
    ];
  reports "a table under another table" "[plan]\ncheck = 1\n"
    [
      "sinter.toml:2:1: 'check' is a table of the top level; write its keys \
       under the header [check]";
    ];
  reports "a key of another table" "[scan]\nrollout-cap = true\n"
    [ "sinter.toml:2:1: 'rollout-cap' belongs in [check]" ];
  reports "a key of a pack" "files = []\n"
    [ "sinter.toml:1:1: 'files' belongs in [scan.packs.<name>]" ];
  reports "a fixed name where a gate goes" "[check.tiers]\nrollout-cap = true\n"
    [ "sinter.toml:2:1: 'rollout-cap' belongs in [check]" ];
  reports "a fixed name where a class goes"
    "[check.tiers.merge]\nhistorical = []\n"
    [ "sinter.toml:2:1: 'historical' belongs in [check]" ];
  reports "a fixed name where a kind goes" "[plan.locations]\nshared = []\n"
    [ "sinter.toml:2:1: 'shared' belongs in [plan]" ]

let wrong_types () =
  reports "a string for a boolean" "[check]\nrollout-cap = \"yes\"\n"
    [ "sinter.toml:2:15: 'rollout-cap' takes true or false, not a string" ];
  reports "a member that is not a string" "[check]\nhistorical = [\"a\", 1]\n"
    [
      "sinter.toml:2:20: 'historical' takes an array of strings, and this \
       member is an integer";
    ];
  reports "an integer for a table" "scan = 1\n"
    [ "sinter.toml:1:8: 'scan' takes a table, not an integer" ];
  reports "an array of tables for a table" "[[check]]\n"
    [ "sinter.toml:1:3: 'check' takes a table, not an array of tables" ];
  reports "a table for a string" "[target]\n"
    [ "sinter.toml:1:2: 'target' takes a string, not a table" ];
  reports "a string for an array" "[check]\nhistorical = \"docs/\"\n"
    [ "sinter.toml:2:14: 'historical' takes an array of strings, not a string" ];
  reports "a float, a date, and a boolean"
    "target = 1.5\n[check]\nrollout-cap = 1979-05-27\nhistorical = [true]\n"
    [
      "sinter.toml:1:10: 'target' takes a string, not a float";
      "sinter.toml:3:15: 'rollout-cap' takes true or false, not a date or a \
       time";
      "sinter.toml:4:15: 'historical' takes an array of strings, and this \
       member is a boolean";
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
       'turn', 'merge', or 'target'";
    ];
  reports "a class with no tier at the gate"
    "[check.tiers.target]\nbad-scope = \"warn\"\n"
    [ "sinter.toml:2:1: 'bad-scope' takes no tier at the gate 'target'" ];
  reports "config-changed, pack-drift, and an unknown class"
    "[check.tiers.merge]\n\
     config-changed = \"warn\"\n\
     pack-drift = \"warn\"\n\
     xyz = \"warn\"\n"
    [
      "sinter.toml:2:1: 'config-changed' takes no tier; it always reports and \
       never blocks";
      "sinter.toml:3:1: 'pack-drift' takes no tier at any gate";
      "sinter.toml:4:1: unknown finding class 'xyz' in [check.tiers.merge]; \
       'tiers' names built-in finding classes only";
    ];
  reports "config-changed is never a suggestion"
    "[check.tiers.merge]\nconfig-chnged = \"warn\"\n"
    [
      "sinter.toml:2:1: unknown finding class 'config-chnged' in \
       [check.tiers.merge]; 'tiers' names built-in finding classes only";
    ];
  reports "the suggestion is a class that takes a tier at the gate"
    "[check.tiers.target]\nbad-scop = \"warn\"\n"
    [
      "sinter.toml:2:1: unknown finding class 'bad-scop' in \
       [check.tiers.target]; 'tiers' names built-in finding classes only";
    ];
  reports "kinds of locations"
    "[plan.locations]\ndecisions = [\"docs/\"]\nplan = [\"x\"]\nfoo = []\n"
    [
      "sinter.toml:2:1: unknown kind 'decisions' in [plan.locations]; did you \
       mean 'decision'?";
      "sinter.toml:3:1: 'plan' takes no location; plan files always live under \
       .plans/";
      "sinter.toml:4:1: unknown kind 'foo' in [plan.locations]; the kinds are \
       'req', 'design', or 'decision'";
    ];
  reports "pack names and namespaces"
    "[scan.packs.Markdown]\n\
     files = [\"a\"]\n\
     [scan.refs]\n\
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
      "sinter.toml:4:1: 'GH' is not a ref namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:5:1: 'a-' is not a ref namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:6:1: '-a' is not a ref namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:7:1: '' is not a ref namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:8:1: '1a' is not a ref namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:9:1: 'aB' is not a ref namespace; a namespace is lower-case \
       letters and digits, in words joined by '-', such as 'gh' or 'jira'";
      "sinter.toml:10:1: 'a_b' is not a ref namespace; a namespace is \
       lower-case letters and digits, in words joined by '-', such as 'gh' or \
       'jira'";
    ];
  reports "names with words and digits"
    (markdown
   ^ "packs.tree-sitter2.files = [\"a\"]\n\
      packs.tree-sitter2.version = \"1.0\"\n\
      refs.a1-b2 = \"x\"\n\
      refs.z9-a0 = \"x\"\n\
      refs.z = \"x\"\n")
    [ "no error" ];
  reports "a version for markdown"
    "[scan.packs.markdown]\nfiles = [\"**/*.md\"]\nversion = \"1.0\"\n"
    [
      "sinter.toml:3:1: the pack markdown is built into sinter and takes no \
       version";
    ]

let values () =
  reports "a target that is not a branch name"
    ("target = \"a..b\"\n" ^ markdown)
    [
      "sinter.toml:1:12: \"a..b\" is not a branch name; a branch name cannot \
       hold '..'";
    ];
  reports "a column counts code points"
    ("target = \"\xc3\xa9..b\"\n" ^ markdown)
    [
      "sinter.toml:1:12: \"\xc3\xa9..b\" is not a branch name; a branch name \
       cannot hold '..'";
    ];
  reports "an escape puts the error at the string"
    ("target = \"a\\u002e.b\"\n" ^ markdown)
    [
      "sinter.toml:1:10: \"a..b\" is not a branch name; a branch name cannot \
       hold '..'";
    ];
  reports "globs, packs, and patterns"
    "[scan]\n\
     packs.markdown.files = [\"src/**.ts\", \"!x\", \"!x\"]\n\
     packs.x.files = [\"!a\"]\n\
     packs.y.version = \"1\"\n\
     packs.z.files = []\n\
     packs.w.files = [\"a\"]\n\
     refs.gh = \".x\"\n\
     refs.jira = \"[0-9]*\"\n"
    [
      "sinter.toml:2:30: \"src/**.ts\" is not a glob: the segment '**.ts' \
       holds '**' and other characters; write '**/*.ts'";
      "sinter.toml:2:44: \"!x\" occurs twice in 'files'";
      "sinter.toml:3:17: 'files' holds only '!' globs, so it holds no path; \
       add a glob without '!'";
      "sinter.toml:4:7: the pack 'y' needs 'files', the globs of the files \
       that it reads";
      "sinter.toml:4:19: 'version' takes a version of the form MAJOR.MINOR, \
       such as \"1.0\", not \"1\"";
      "sinter.toml:5:7: the pack 'z' needs 'files', the globs of the files \
       that it reads";
      "sinter.toml:6:7: the pack 'w' needs 'version', the release that the \
       repository uses, such as \"1.0\"";
      "sinter.toml:7:12: '.' is not in the id pattern language; put it in a \
       class, for example [.]";
      "sinter.toml:8:14: the pattern matches an empty id";
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
    (markdown ^ "[check]\nhistorical = [\"a\", \"!/b\"]\n")
    [
      "sinter.toml:4:22: \"!/b\" is not a glob: a glob cannot start with '/'; \
       a glob always matches from the repository root";
    ];
  reports "words"
    (markdown
   ^ "[check]\n\
      tiers.merge.dangling = \"blok\"\n\
      [ledger]\n\
      approval-required = [\"reqs\", \"req\", \"req\"]\n\
      harness-markers = [\"MY-VAR\", \"A\", \"A\", \"1A\", \"\"]\n\
      [evidence]\n\
      coverage-attribution = \"requird\"\n")
    [
      "sinter.toml:4:24: 'dangling' takes \"off\", \"warn\", or \"block\", not \
       \"blok\"; did you mean \"block\"?";
      "sinter.toml:6:22: 'approval-required' takes \"req\", \"design\", \
       \"decision\", or \"plan\", not \"reqs\"; did you mean \"req\"?";
      "sinter.toml:6:37: \"req\" occurs twice in 'approval-required'";
      "sinter.toml:7:20: \"MY-VAR\" is not a name of an environment variable; \
       a name holds letters, digits, and '_', and does not start with a digit";
      "sinter.toml:7:35: \"A\" occurs twice in 'harness-markers'";
      "sinter.toml:7:40: \"1A\" is not a name of an environment variable; a \
       name holds letters, digits, and '_', and does not start with a digit";
      "sinter.toml:7:46: \"\" is not a name of an environment variable; a name \
       holds letters, digits, and '_', and does not start with a digit";
      "sinter.toml:9:24: 'coverage-attribution' takes \"optional\" or \
       \"required\", not \"requird\"; did you mean \"required\"?";
    ];
  reports "a word far from every word"
    (markdown ^ "[evidence]\ncoverage-attribution = \"x\"\n")
    [
      "sinter.toml:4:24: 'coverage-attribution' takes \"optional\" or \
       \"required\", not \"x\"";
    ]

let a_manifest_with_no_pack () =
  reports "no pack" "[check]\nrollout-cap = true\n"
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
    "[check]\n\
     foo = 1\n\
     rollout-cap = 1\n\
     [scan]\n\
     packs.markdown.files = [\"a?\"]\n"
    [
      "sinter.toml:2:1: unknown key 'foo' in [check]";
      "sinter.toml:3:15: 'rollout-cap' takes true or false, not an integer";
    ]

let errors_come_in_the_order_of_their_places () =
  reports "keys written out of order"
    "[check]\nzz = 1\naa = 2\n[ledger]\nbb = 3\n"
    [
      "sinter.toml:2:1: unknown key 'zz' in [check]";
      "sinter.toml:3:1: unknown key 'aa' in [check]";
      "sinter.toml:5:1: unknown key 'bb' in [ledger]";
    ];
  reports "two errors in one line"
    (markdown ^ "[check]\nhistorical = [1, 2]\n")
    [
      "sinter.toml:4:15: 'historical' takes an array of strings, and this \
       member is an integer";
      "sinter.toml:4:18: 'historical' takes an array of strings, and this \
       member is an integer";
    ]

(* The informative example messages of the specification, through the
   reader. *)
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
  check "[check]\nhistoric = 1\n"
    "unknown key 'historic' in [check]; did you mean 'historical'?";
  check "[evidence]\ntarget = \"trunk\"\n"
    "'target' belongs at the top level, above the first table header";
  check "[check]\nrollout-cap = \"x\"\n"
    "'rollout-cap' takes true or false, not a string";
  check "[scan.packs.markdown]\nfiles = [\"a\"]\nversion = \"1.0\"\n"
    "the pack markdown is built into sinter and takes no version";
  check "[check.tiers.merge]\nconfig-changed = \"warn\"\n"
    "'config-changed' takes no tier; it always reports and never blocks";
  check "[check.tiers.target]\nbad-scope = \"warn\"\n"
    "'bad-scope' takes no tier at the gate 'target'";
  check
    (markdown ^ "refs.gh = \".\"\n")
    "'.' is not in the id pattern language; put it in a class, for example [.]";
  check (markdown ^ "refs.gh = \"[0-9]*\"\n") "the pattern matches an empty id"

(* Messages that the reader cannot give today, and the corners of the
   message function. *)
let message problem =
  Manifest.message (Manifest.At ({ Toml.line = 1; column = 1 }, problem))

let every_problem_has_a_message () =
  let check name expected problem =
    Alcotest.(check string) name expected (message problem)
  in
  check "a key newer than spec"
    "'check.foo' needs specification 1.1, and the manifest states spec = \
     \"1.0\"; write spec = \"1.1\""
    (Manifest.Key_too_new
       {
         key = [ "check"; "foo" ];
         since = Major_minor.make 1 1;
         spec = Major_minor.make 1 0;
       });
  check "a wrong type of no key" "'' takes a string, not an integer"
    (Manifest.Wrong_type
       { key = []; expected = Manifest.A_string; found = Toml.Kind.Integer });
  check "a member of no key"
    "'' takes an array of strings, and this member is a float"
    (Manifest.Wrong_member_type { key = []; found = Toml.Kind.Float });
  check "an unknown gate with no near name"
    "unknown gate 'x' in [check.tiers]; the gates are 'turn', 'merge', or \
     'target'"
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

let newer_keys_names_each_key_newer_than_spec () =
  match Toml.parse "target = \"a\"\n[check]\nrollout-cap = true\nfoo = 1\n" with
  | Error _ -> Alcotest.fail "the text does not parse"
  | Ok document ->
      Alcotest.(check (list string))
        "the keys newer than 0.9"
        [
          "s:1:1: 'target' needs specification 1.0, and the manifest states \
           spec = \"0.9\"; write spec = \"1.0\"";
          "s:3:1: 'check.rollout-cap' needs specification 1.0, and the \
           manifest states spec = \"0.9\"; write spec = \"1.0\"";
        ]
        (List.map
           (Manifest.render ~path:"s")
           (Manifest.newer_keys ~spec:(Major_minor.make 0 9) document));
      Alcotest.(check int)
        "no key is newer than 1.0" 0
        (List.length
           (Manifest.newer_keys ~spec:(Major_minor.make 1 0) document))

let render_names_the_path_and_the_place () =
  Alcotest.(check string)
    "a place" "conf/s.toml:3:14: 'pack-drift' takes no tier at any gate"
    (Manifest.render ~path:"conf/s.toml"
       (Manifest.At
          ({ Toml.line = 3; column = 14 }, Manifest.No_tier_at_any_gate)))

(* The column "since" of the table of keys of the specification. *)
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
  Alcotest.(check int) "the number of keys" 14 (List.length rows);
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
      [ "check"; "tiers"; "merge" ];
      [ "foo" ];
      [ "spec"; "x" ];
      [ "check"; "tiers"; "a"; "b"; "c" ];
    ]

let the_implemented_version_is_1_0 () =
  Alcotest.(check string)
    "specification" "1.0"
    (Major_minor.to_string Manifest.specification)

(* Reading a file. *)

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

(* A process that runs as root reads the file all the same, so the test
   holds only for another user. *)
let load_of_a_file_it_cannot_open_is_unreadable () =
  with_file markdown (fun path ->
      Unix.chmod path 0;
      match Manifest.load path with
      | Error (Manifest.Unreadable reason) ->
          Alcotest.(check bool) "a reason" true (String.length reason > 0)
      | Ok _ when Unix.geteuid () = 0 -> ()
      | _ -> Alcotest.fail "a file with no read permission is not Unreadable")

(* Properties. *)

let property ?(count = 200) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

(* Lines that a manifest can hold, valid or not, so that a text of a few
   of them reaches every step of the reader. *)
let line =
  Gen.oneof_list
    [
      "[scan]";
      "[check]";
      "[plan]";
      "[ledger]";
      "[evidence]";
      "[scan.packs.markdown]";
      "[check.tiers.merge]";
      "[[check]]";
      "spec = \"1.0\"";
      "spec = \"9.0\"";
      "target = \"main\"";
      "target = \"a..b\"";
      "packs.markdown.files = [\"**/*.md\"]";
      "packs.ocaml.files = [\"**/*.ml\"]";
      "packs.ocaml.version = \"1.0\"";
      "files = [\"a\", \"!b\"]";
      "version = \"1\"";
      "refs.gh = \"[1-9][0-9]*\"";
      "refs.x = \".\"";
      "rollout-cap = true";
      "rollout-cap = 1";
      "historical = [\"docs/\"]";
      "tiers.merge.dangling = \"block\"";
      "dangling = \"warn\"";
      "config-changed = \"warn\"";
      "ambient = [\"a\", 2]";
      "locations.decision = [\"d/\"]";
      "approval-required = [\"req\"]";
      "harness-markers = [\"A\"]";
      "coverage-attribution = \"required\"";
      "historic = 1";
      "a = {";
      "b.c = 'x'";
      "# a comment";
      "";
    ]

let text = Gen.(map (String.concat "\n") (list_size (0 -- 8) line))

(* A text with one byte written over, cut short, or doubled. *)
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
    ~name:"of_string answers any text with sorted errors in it"
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
               (fun e -> String.length (Manifest.message e) > 0)
               errors)

(* A manifest as a list of settings, each a key path and the TOML text of
   its value. *)
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
        oneof_list [ []; [ ([ "target" ], "\"trunk\"") ] ];
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
        optional [ "scan"; "refs"; "gh" ] "\"[1-9][0-9]*\"";
        map (fun b -> [ ([ "check"; "rollout-cap" ], string_of_bool b) ]) bool;
        map
          (fun g ->
            if g = [] then [] else [ ([ "check"; "historical" ], strings g) ])
          globs;
        some_of
          [
            ("merge", "dangling", "warn");
            ("turn", "suspect", "off");
            ("target", "cycle", "block");
          ]
        >|= List.map (fun (gate, cls, tier) ->
            ([ "check"; "tiers"; gate; cls ], Printf.sprintf "%S" tier));
        map
          (fun g ->
            if g = [] then [] else [ ([ "plan"; "ambient" ], strings g) ])
          globs;
        map
          (fun g ->
            if g = [] then []
            else [ ([ "plan"; "locations"; "decision" ], strings g) ])
          globs;
        map
          (fun k ->
            if k = [] then []
            else [ ([ "ledger"; "approval-required" ], strings k) ])
          (some_of [ "req"; "plan" ]);
        optional [ "evidence"; "coverage-attribution" ] "\"required\"";
      ]
    in
    flatten_list pairs >|= List.concat)

(* Three forms of one manifest: every key path as one dotted key at the
   top level; a header for each table of the top level; a header for
   each table that holds a value. *)
let render_dotted settings =
  String.concat ""
    (List.map
       (fun (path, value) -> Toml.render_path path ^ " = " ^ value ^ "\n")
       settings)

let render_by ~depth settings =
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
  String.concat ""
    (List.map
       (fun (table, lines) ->
         (if table = [] then "" else "[" ^ Toml.render_path table ^ "]\n")
         ^ String.concat "" lines)
       groups)

let summary manifest =
  String.concat "\n"
    ([
       Manifest.target manifest;
       string_of_bool (Manifest.rollout_cap manifest);
       String.concat "," (members (Manifest.historical manifest));
       String.concat "," (members (Manifest.ambient manifest));
       (match Manifest.location manifest Manifest.Decision with
       | None -> "-"
       | Some set -> String.concat "," (members set));
       String.concat ","
         (List.map Manifest.kind_name (Manifest.approval_required manifest));
       (match Manifest.coverage_attribution manifest with
       | Manifest.Optional -> "optional"
       | Required -> "required");
     ]
    @ List.map pack_summary (Manifest.packs manifest)
    @ List.map
        (fun (ns, p) -> ns ^ "=" ^ Id_pattern.to_string p)
        (Manifest.ref_namespaces manifest)
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
        ])

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "the smallest manifest takes every default"
      the_smallest_manifest_takes_every_default;
    case "the example of sinter reads" the_example_of_sinter_reads;
    case "the example of a typescript project reads"
      the_example_of_a_typescript_project_reads;
    case "the tier that applies follows the three rules"
      the_tier_that_applies_follows_the_three_rules;
    case "without the cap the built-in tier applies"
      without_the_cap_the_built_in_tier_applies;
    case "written tiers are sorted" written_tiers_are_sorted;
    case "built-in paths join the written ones"
      built_in_paths_join_the_written_ones;
    case "harness markers keep their order" harness_markers_keep_their_order;
    case "approval kinds keep their order" approval_kinds_keep_their_order;
    case "every location kind reads" every_location_kind_reads;
    case "a target branch reads" a_target_branch_reads;
    case "an empty array is an absent key" an_empty_array_is_an_absent_key;
    case "every form of TOML means the same" every_form_of_toml_means_the_same;
    case "a syntax error reports the TOML reader"
      a_syntax_error_reports_the_toml_reader;
    case "spec errors" spec_errors;
    case "the version comes before the names" the_version_comes_before_the_names;
    case "unknown keys" unknown_keys;
    case "keys at the wrong place" keys_at_the_wrong_place;
    case "wrong types" wrong_types;
    case "names that vary" names_that_vary;
    case "values" values;
    case "a manifest with no pack" a_manifest_with_no_pack;
    case "the names come before the values" the_names_come_before_the_values;
    case "errors come in the order of their places"
      errors_come_in_the_order_of_their_places;
    case "the example messages of the specification"
      the_example_messages_of_the_specification;
    case "every problem has a message" every_problem_has_a_message;
    case "render names the path and the place"
      render_names_the_path_and_the_place;
    case "a value in a message is a TOML string"
      a_value_in_a_message_is_a_toml_string;
    case "a table with an empty name" a_table_with_an_empty_name;
    case "since is that of the specification" since_is_that_of_the_specification;
    case "since of no setting is none" since_of_no_setting_is_none;
    case "the implemented version is 1.0" the_implemented_version_is_1_0;
    case "load reads a file" load_reads_a_file;
    case "load gives the errors of the text" load_gives_the_errors_of_the_text;
    case "load of no file is missing" load_of_no_file_is_missing;
    case "load of a folder is unreadable" load_of_a_folder_is_unreadable;
    case "load of a path under a file is missing"
      load_of_a_path_under_a_file_is_missing;
    case "load of a file it cannot open is unreadable"
      load_of_a_file_it_cannot_open_is_unreadable;
    case "newer_keys names each key newer than spec"
      newer_keys_names_each_key_newer_than_spec;
    of_string_answers_any_text;
    every_form_and_order_reads_the_same;
  ]
