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

let manifest =
  match
    Manifest.of_string
      "[scan]\n\
       packs.markdown.files = [\"**/*.md\"]\n\
       [check]\n\
       historical = [\"old/**\"]\n\
       [plan]\n\
       exempt = [\"vendor/\", \"!vendor/own.c\"]\n"
  with
  | Ok manifest -> manifest
  | Error _ -> failwith "the manifest has errors"

let facts files =
  Facts.make manifest
    (List.map (fun (path, text) -> (path, document text)) files)

let hunk ?(old_line = 1) ?(removed = 0) ?(line = 1) ?(added = 0) ?(ecol = 1) ()
    =
  {
    Git.line;
    eline = (if added = 0 then line else line + added - 1);
    ecol;
    old_line;
    added;
    removed;
  }

let edit ?old_line ?removed ?line ?added ?ecol () =
  Git.Modified (Git.Text [ hunk ?old_line ?removed ?line ?added ?ecol () ])

let plan =
  ( ".plans/work.md",
    "# Work\n\n\
     @plan work\n\
     @scope src/**, docs/**, lib/**\n\n\
     ## Own\n\n\
     @scope src/**\n\
     @req x\n\n\
     ## Inherits\n\n\
     @req y\n" )

let unplanned ?(base = []) ?(manifest_path = Some "sinter.toml") tree diff =
  List.map
    (fun (finding : Finding.t) -> Finding.subject_id finding.subject)
    (Unplanned.findings ~base:(facts base) ~manifest:manifest_path (facts tree)
       diff)

let strings = Alcotest.(list string)

let a_step_covers_the_paths_of_its_effective_scope () =
  Alcotest.check strings "the uncovered hunks" [ "hunk:test/a.ml:1-1" ]
    (unplanned [ plan ]
       [
         ("docs/a.md", edit ~added:1 ());
         ("lib/a.ml", edit ~added:1 ());
         ("src/a.ml", edit ~added:1 ());
         ("test/a.ml", edit ~added:1 ());
       ])

let a_plan_with_no_step_covers_nothing () =
  Alcotest.check strings "the uncovered hunks" [ "hunk:src/a.ml:1-1" ]
    (unplanned
       [ (".plans/bare.md", "# Bare\n\n@plan bare\n@scope src/**\n") ]
       [ ("src/a.ml", edit ~added:1 ()) ])

let an_exempt_path_needs_no_step () =
  Alcotest.check strings "the uncovered hunks"
    [ "hunk:vendor/own.c:1-1"; "hunk:config/sinter.toml:1-1" ]
    (unplanned
       ~base:[ (".plans/gone.md", "# Gone\n\n@plan gone\n") ]
       [ plan ]
       [
         ("vendor/lib.c", edit ~added:1 ());
         ("vendor/own.c", edit ~added:1 ());
         (".plans/work.md", edit ~added:1 ());
         (".plans/gone.md", Git.Deleted (Git.Text [ hunk ~removed:4 () ]));
         ("sinter.toml", edit ~added:1 ());
         ("config/sinter.toml", edit ~added:1 ());
         ("sinter.lock", edit ~added:1 ());
       ])

let the_manifest_is_exempt_only_inside_the_repository () =
  Alcotest.check strings "the uncovered hunks" [ "hunk:sinter.toml:1-1" ]
    (unplanned ~manifest_path:None []
       [ ("sinter.toml", edit ~added:1 ()); ("sinter.lock", edit ~added:1 ()) ])

let a_file_under_plans_that_is_no_plan_is_not_exempt () =
  Alcotest.check strings "the uncovered hunks"
    [ "hunk:.plans/notes.md:1-1" ]
    (unplanned
       [ (".plans/notes.md", "# Notes\n\nText.\n") ]
       [ (".plans/notes.md", edit ~added:1 ()) ])

let a_historical_path_gives_no_finding () =
  Alcotest.check strings "the uncovered hunks" []
    (unplanned []
       [
         (".plans/work.log.md", edit ~added:1 ()); ("old/a.md", edit ~added:1 ());
       ])

let a_mechanical_repair_needs_no_step () =
  let base =
    [
      ("docs/spec.md", "# Spec\n\n@req a v1 Text.\n");
      ("notes/use.md", "# Use\n\n@cites a v1\n\nProse.\n");
    ]
  and tree =
    [
      ("docs/spec.md", "# Spec\n\n@req a v2 Other text.\n");
      ("notes/use.md", "# Use\n\n@cites a v2\n\nProse, longer.\n");
    ]
  in
  Alcotest.check strings "the uncovered hunks"
    [ "hunk:docs/spec.md:3-3"; "hunk:notes/use.md:5-5" ]
    (unplanned ~base tree
       [
         ("docs/spec.md", edit ~old_line:3 ~removed:1 ~line:3 ~added:1 ());
         ( "notes/use.md",
           Git.Modified
             (Git.Text
                [
                  hunk ~old_line:3 ~removed:1 ~line:3 ~added:1 ();
                  hunk ~old_line:5 ~removed:1 ~line:5 ~added:1 ();
                ]) );
       ])

let a_hunk_with_no_line_gives_a_finding () =
  Alcotest.check strings "the uncovered hunks"
    [ "hunk:notes/b.bin:1-1"; "hunk:notes/empty.md:1-1" ]
    (unplanned
       [ ("notes/empty.md", "") ]
       [
         ("notes/b.bin", Git.Modified Git.Binary);
         ("notes/empty.md", Git.Added (Git.Text []));
         ("notes/mode.sh", Git.Modified (Git.Text []));
       ])

let a_finding_sits_at_its_hunk () =
  let shown (finding : Finding.t) =
    Printf.sprintf "%s | %s | %s | %s | %s | %b" (Finding.id finding)
      (Finding.ack_subject finding.subject)
      (match finding.place with
      | Some { path; span } ->
          Printf.sprintf "%s:%d:%d-%d:%d" path span.start.line span.start.column
            span.stop.line span.stop.column
      | None -> "-")
      (Option.value finding.detail ~default:"-")
      (Option.fold ~none:"-" ~some:Fix.text finding.fix)
      finding.ackable
  in
  Alcotest.check strings "the findings"
    [
      "finding:unplanned-change:hunk:notes/a.md:4-6 | hunk:notes/a.md:4-6 | \
       notes/a.md:4:1-6:12 | no step of an open plan, no rule, and no exempt \
       path covers notes/a.md | - | false";
      "finding:unplanned-change:hunk:notes/a.md:9-9 | hunk:notes/a.md:9-9 | \
       notes/a.md:9:1-9:1 | no step of an open plan, no rule, and no exempt \
       path covers notes/a.md | - | false";
      "finding:unplanned-change:hunk:notes/gone.md:1-1 | \
       hunk:notes/gone.md:1-1 | notes/gone.md:1:1-1:1 | no step of an open \
       plan, no rule, and no exempt path covers notes/gone.md | - | false";
    ]
    (List.map shown
       (Unplanned.findings ~base:(facts []) ~manifest:None (facts [])
          [
            ( "notes/a.md",
              Git.Modified
                (Git.Text
                   [
                     hunk ~old_line:4 ~removed:2 ~line:4 ~added:3 ~ecol:12 ();
                     hunk ~old_line:8 ~removed:1 ~line:9 ();
                   ]) );
            ("notes/gone.md", Git.Deleted (Git.Text [ hunk ~removed:3 () ]));
          ]))

module Gen = QCheck2.Gen

let diff_gen =
  Gen.(
    let hunk_gen =
      let* old_line = int_range 1 9 in
      let* removed = int_bound 3 in
      let* line = int_range 1 9 in
      let+ added = int_bound 3 in
      hunk ~old_line ~removed ~line ~added ()
    in
    let content =
      oneof
        [
          pure Git.Binary;
          map (fun hunks -> Git.Text hunks) (list_size (int_bound 3) hunk_gen);
        ]
    in
    let* paths =
      map
        (List.sort_uniq String.compare)
        (list_size (int_bound 6)
           (oneof_list
              [
                "src/a.ml";
                "test/a.ml";
                "vendor/x.c";
                "vendor/own.c";
                "old/a.md";
                "README";
                "sinter.toml";
              ]))
    in
    flatten_list
      (List.map
         (fun path ->
           let+ change =
             oneof
               [
                 map (fun c -> Git.Added c) content;
                 map (fun c -> Git.Deleted c) content;
                 map (fun c -> Git.Modified c) content;
               ]
           in
           (path, change))
         paths))

let each_uncovered_hunk_gives_one_finding_at_its_place =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:300
       ~name:"each hunk of an uncovered path gives one finding at its place"
       ~print:Generators.print_changes diff_gen (fun diff ->
         let expected =
           List.concat_map
             (fun (path, change) ->
               if List.mem path [ "test/a.ml"; "vendor/own.c"; "README" ] then
                 List.map
                   (fun (h : Git.hunk) ->
                     ( Printf.sprintf "hunk:%s:%d-%d" path h.line h.eline,
                       Some
                         {
                           Finding.path;
                           span =
                             {
                               start = { line = h.line; column = 1 };
                               stop = { line = h.eline; column = h.ecol };
                             };
                         } ))
                   (Git.hunks change)
               else [])
             diff
         in
         expected
         = List.map
             (fun (finding : Finding.t) ->
               (Finding.subject_id finding.subject, finding.place))
             (Unplanned.findings ~base:(facts []) ~manifest:(Some "sinter.toml")
                (facts [ plan ]) diff)))

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "a step covers the paths of its effective scope"
      a_step_covers_the_paths_of_its_effective_scope;
    case "a plan with no step covers nothing" a_plan_with_no_step_covers_nothing;
    case "an exempt path needs no step" an_exempt_path_needs_no_step;
    case "the manifest is exempt only inside the repository"
      the_manifest_is_exempt_only_inside_the_repository;
    case "a file under .plans/ that is no plan is not exempt"
      a_file_under_plans_that_is_no_plan_is_not_exempt;
    case "a historical path gives no finding" a_historical_path_gives_no_finding;
    case "a mechanical repair needs no step" a_mechanical_repair_needs_no_step;
    case "a hunk with no line gives a finding"
      a_hunk_with_no_line_gives_a_finding;
    case "a finding sits at its hunk" a_finding_sits_at_its_hunk;
    each_uncovered_hunk_gives_one_finding_at_its_place;
  ]
