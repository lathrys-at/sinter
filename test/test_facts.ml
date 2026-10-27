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
  "[scan]\n\
   packs.markdown.files = [\"**/*.md\"]\n\
   namespaces.gh = \"[1-9][0-9]*\"\n"

let manifest ?(extra = "") () =
  match Manifest.of_string (markdown ^ extra) with
  | Ok manifest -> manifest
  | Error _ -> Alcotest.fail "the manifest has errors"

let facts ?(extra = "") files =
  Facts.make (manifest ~extra ())
    (List.map (fun (path, text) -> (path, document text)) files)

let records ?extra ?(changed = []) files =
  Facts.records (facts ?extra files) ~changed

let lines ?extra ?changed files =
  List.map Jsonl.to_string (records ?extra ?changed files)

let field name record = List.assoc_opt name record

let id record =
  match field "id" record with
  | Some (Jsonl.Scalar (Jsonl.String id)) -> id
  | _ -> ""

let find wanted records =
  match
    List.find_opt (fun record -> String.equal (id record) wanted) records
  with
  | Some record -> record
  | None -> Alcotest.failf "no record has the id %s" wanted

let show = function
  | None -> "(absent)"
  | Some value -> Jsonl.to_string [ ("value", value) ]

let check_field ?(message = "") records wanted name expected =
  Alcotest.(check string)
    (Printf.sprintf "%s %s %s" wanted name message)
    (show expected)
    (show (field name (find wanted records)))

let str text = Some (Jsonl.string text)
let int number = Some (Jsonl.int number)
let bool value = Some (Jsonl.bool value)
let ids records = List.map id records

let lockout =
  "# Lockout\n\n\
   @req auth-lockout v2 Lock the account.\n\
   @cites policy v1\n\
   Five failures freeze it.\n\
   More prose.\n\n\
   Body text.\n\n\
   ## Policy\n\n\
   @decision policy\n"

let a_declaration_gives_its_record () =
  let xh =
    Sha256.hex
      "# Lockout\n\n\
       Lock the account.\n\
       @cites policy\n\
       Five failures freeze it.\n\
       More prose.\n\n\
       Body text.\n"
  in
  Alcotest.(check string)
    "the record of req:auth-lockout"
    (Printf.sprintf
       "{\"approval_required\":false,\"approved\":true,\"col\":1,\"declined\":false,\"desc\":\"Lock \
        the account.\\nFive failures freeze it.\\nMore \
        prose.\",\"ecol\":39,\"eline\":3,\"id\":\"req:auth-lockout\",\"inforce\":true,\"kind\":\"req\",\"line\":3,\"pack\":\"markdown\",\"path\":\"docs/a.md\",\"rev\":2,\"slug\":\"auth-lockout\",\"title\":\"Lockout\",\"v\":1,\"xeline\":8,\"xh\":\"%s\",\"xline\":1}"
       xh)
    (Jsonl.to_string
       (find "req:auth-lockout" (records [ ("docs/a.md", lockout) ])))

let a_declaration_without_a_revision_has_revision_1 () =
  let records = records [ ("docs/a.md", lockout) ] in
  check_field records "decision:policy" "rev" (int 1);
  check_field records "decision:policy" "title" (str "Policy");
  check_field records "decision:policy" "desc" None;
  check_field records "decision:policy" "xline" (int 10);
  check_field records "decision:policy" "xeline" (int 12)

let a_declaration_in_a_list_item_or_at_level_0_has_no_title () =
  let records =
    records
      [
        ("a.md", "@decision top\n\n# Head\n\nText.\n\n- @req item v1 An item.\n");
      ]
  in
  check_field records "decision:top" "title" None;
  check_field records "req:item" "title" None;
  check_field records "req:item" "desc" (str "An item.")

let the_trailing_prose_goes_to_the_last_declaration_of_the_block () =
  let records =
    records [ ("a.md", "# H\n\n@req first First.\n@req second\nThe prose.\n") ]
  in
  check_field records "req:first" "desc" (str "First.");
  check_field records "req:second" "desc" (str "The prose.");
  check_field records "req:first" "xeline" (int 3);
  check_field records "req:second" "xline" (int 4)

let a_status_tag_retires_its_declaration () =
  let records =
    records [ ("a.md", "# H\n\n@decision old\n@deprecated No longer.\n") ]
  in
  check_field records "decision:old" "status" (str "deprecated");
  check_field records "decision:old" "inforce" (bool false)

let a_status_tag_outside_the_block_of_the_declaration_is_inert () =
  let records =
    records [ ("a.md", "# H\n\n@decision old\n\n- @deprecated in an item\n") ]
  in
  check_field records "decision:old" "status" None;
  check_field records "decision:old" "inforce" (bool true)

let a_status_tag_of_another_kind_is_inert () =
  let records =
    records
      [
        ( "a.md",
          "# H\n\n@req old\n@rejected\n\n## D\n\n@decision d\n@deferred\n" );
      ]
  in
  check_field records "req:old" "status" None;
  check_field records "decision:d" "status" (str "deferred")

let the_first_status_tag_gives_the_status () =
  let records =
    records [ ("a.md", "# H\n\n@decision d\n@rejected\n@deprecated\n") ]
  in
  check_field records "decision:d" "status" (str "rejected")

let a_status_tag_applies_to_the_declaration_whose_extent_holds_it () =
  let records =
    records [ ("a.md", "# H\n\n@decision a\n@decision b\n@deprecated\n") ]
  in
  check_field records "decision:a" "status" None;
  check_field records "decision:b" "status" (str "deprecated")

let a_kind_that_needs_approval_is_not_approved () =
  let records =
    records ~extra:"[ledger]\napproval-required = [\"req\", \"plan\"]\n"
      [ ("docs/a.md", lockout) ]
  in
  check_field records "req:auth-lockout" "approved" (bool false);
  check_field records "req:auth-lockout" "approval_required" (bool true);
  check_field records "decision:policy" "approved" (bool true);
  check_field records "decision:policy" "approval_required" (bool false)

let each_kind_needs_approval_alone () =
  let file =
    ("a.md", "# A\n\n@req r\n\n# B\n\n@design d\n\n# C\n\n@decision c\n")
  in
  Alcotest.(check (list (list string)))
    "the approved declarations under each setting"
    [
      [ "design:d"; "req:r" ];
      [ "decision:c"; "req:r" ];
      [ "decision:c"; "design:d" ];
    ]
    (List.map
       (fun kind ->
         let records =
           records
             ~extra:
               (Printf.sprintf "[ledger]\napproval-required = [\"%s\"]\n" kind)
             [ file ]
         in
         List.filter
           (fun id ->
             field "approved" (find id records) = Some (Jsonl.bool true))
           (ids records))
       [ "decision"; "design"; "req" ])

let a_rule_or_a_bad_slug_gives_no_declaration () =
  Alcotest.(check (list string))
    "no record" []
    (ids
       (records [ ("a.md", "# H\n\n@rule r v1\n\n## B\n\n@req a/b\n@req\n") ]))

let a_citation_takes_its_declaration_as_source () =
  Alcotest.(check string)
    "the record of the citation"
    "{\"col\":1,\"dangling\":false,\"dst\":\"decision:policy\",\"ecol\":17,\"eline\":4,\"id\":\"cites:req:auth-lockout->policy\",\"kind\":\"cites\",\"line\":4,\"pack\":\"markdown\",\"path\":\"docs/a.md\",\"rev\":1,\"src\":\"req:auth-lockout\",\"suspect\":false,\"target\":\"policy\",\"v\":1}"
    (Jsonl.to_string
       (find "cites:req:auth-lockout->policy"
          (records [ ("docs/a.md", lockout) ])))

let a_citation_outside_every_extent_takes_its_section_as_a_site () =
  let records =
    records
      [
        ( "docs/b.md",
          "# Notes\n\nSee @here.\n@cites policy The policy.\n\nMore.\n" );
      ]
  in
  Alcotest.(check (list string))
    "the records, in order"
    [
      "{\"col\":1,\"dangling\":true,\"desc\":\"The \
       policy.\",\"ecol\":26,\"eline\":4,\"id\":\"cites:site:docs/b.md#notes->policy\",\"kind\":\"cites\",\"line\":4,\"pack\":\"markdown\",\"path\":\"docs/b.md\",\"src\":\"site:docs/b.md#notes\",\"suspect\":false,\"target\":\"policy\",\"v\":1}";
      "{\"col\":1,\"ecol\":26,\"eline\":4,\"id\":\"site:docs/b.md#notes\",\"kind\":\"site\",\"line\":3,\"name\":\"notes\",\"pack\":\"markdown\",\"path\":\"docs/b.md\",\"v\":1,\"xeline\":6,\"xline\":1}";
    ]
    (List.map Jsonl.to_string records)

let a_site_at_level_0_has_no_name () =
  let records = records [ ("b.md", "@cites x\n") ] in
  check_field records "site:b.md" "name" None;
  check_field records "cites:site:b.md->x" "src" (str "site:b.md")

let a_site_without_a_first_paragraph_spans_its_extent () =
  let records = records [ ("b.md", "# Head\n\n- @cites x\n- other item\n") ] in
  let site = find "site:b.md#head" records in
  Alcotest.(check (list string))
    "the span of the extent" [ "1"; "1"; "4"; "13" ]
    (List.map
       (fun name -> show (field name site))
       [ "line"; "col"; "eline"; "ecol" ]
    |> List.map (fun text -> String.sub text 9 (String.length text - 10)))

let sites_of_headings_with_one_slug_are_numbered () =
  Alcotest.(check (list string))
    "two sites"
    [ "site:b.md#a-b"; "site:b.md#a-b-1" ]
    (List.filter
       (fun id -> String.starts_with ~prefix:"site:" id)
       (ids (records [ ("b.md", "# A b\n\n@cites x\n\n# A-b\n\n@cites y\n") ])))

let a_target_resolves_across_files () =
  let records =
    records
      [
        ("a.md", "# A\n\n@cites far v3\n"); ("z/b.md", "# B\n\n@design far v3\n");
      ]
  in
  check_field records "cites:site:a.md#a->far" "dst" (str "design:far");
  check_field records "cites:site:a.md#a->far" "dangling" (bool false);
  check_field records "cites:site:a.md#a->far" "suspect" (bool false)

let a_target_that_differs_only_in_case_is_dangling () =
  let records =
    records [ ("a.md", "# A\n\n@cites Far\n\n# B\n\n@req far\n") ]
  in
  check_field records "cites:site:a.md#a->Far" "dst" None;
  check_field records "cites:site:a.md#a->Far" "dangling" (bool true)

let a_malformed_target_is_not_dangling () =
  let records = records [ ("a.md", "# A\n\n@cites not_ok!\n@cites -x\n") ] in
  check_field records "cites:site:a.md#a->not_ok!" "dangling" (bool false);
  check_field records "cites:site:a.md#a->-x" "dangling" (bool false);
  check_field records "cites:site:a.md#a->-x" "dst" None

let an_external_id_of_a_declared_namespace_resolves () =
  let records =
    records
      [ ("a.md", "# A\n\n@cites gh/12\n@cites gh/12 again\n@cites gh/3\n") ]
  in
  check_field records "cites:site:a.md#a->gh/12" "dst" (str "external:gh/12");
  Alcotest.(check (list string))
    "one record per distinct external id, after the located records"
    [
      "{\"id\":\"external:gh/12\",\"kind\":\"external\",\"name\":\"12\",\"ns\":\"gh\",\"pack\":\"markdown\",\"v\":1}";
      "{\"id\":\"external:gh/3\",\"kind\":\"external\",\"name\":\"3\",\"ns\":\"gh\",\"pack\":\"markdown\",\"v\":1}";
    ]
    (List.filteri
       (fun index _ -> index >= 4)
       (List.map Jsonl.to_string records))

let a_resolved_external_id_is_not_dangling () =
  check_field
    (records [ ("a.md", "# A\n\n@cites gh/12\n") ])
    "cites:site:a.md#a->gh/12" "dangling" (bool false)

let external_ids_come_in_the_order_of_their_ids () =
  Alcotest.(check (list string))
    "the ids of the external ids, in byte order"
    [ "external:a-b/1"; "external:a/1"; "external:gh/2" ]
    (List.filter
       (fun id -> String.starts_with ~prefix:"external:" id)
       (ids
          (records
             ~extra:"namespaces.a = \"[0-9]\"\nnamespaces.a-b = \"[0-9]\"\n"
             [ ("a.md", "# A\n\n@cites gh/2\n@cites a/1\n@cites a-b/1\n") ])))

let an_external_id_that_does_not_resolve_gives_no_record () =
  let records = records [ ("a.md", "# A\n\n@cites jira/12\n@cites gh/0x\n") ] in
  check_field records "cites:site:a.md#a->jira/12" "dst" None;
  check_field records "cites:site:a.md#a->jira/12" "dangling" (bool false);
  check_field records "cites:site:a.md#a->gh/0x" "dangling" (bool false);
  Alcotest.(check (list string))
    "no external record" []
    (List.filter
       (fun id -> String.starts_with ~prefix:"external:" id)
       (ids records))

let a_pin_to_another_revision_is_suspect () =
  let records =
    records
      [
        ( "a.md",
          "# A\n\n\
           @req a v2\n\n\
           # B\n\n\
           @design b v1\n\
           @refines a v1\n\
           @cites a v2\n\
           @cites a\n" );
      ]
  in
  check_field records "refines:design:b->a" "suspect" (bool true);
  check_field records "refines:design:b->a" "rev" (int 1);
  check_field records "cites:design:b->a" "suspect" (bool false)
    ~message:"(the first of two)";
  check_field records "refines:design:b->a" "rung" None;
  check_field records "refines:design:b->a" "effective" None

let a_verifies_edge_in_markdown_has_the_wrong_source () =
  check_field
    (records [ ("a.md", "# A\n\n@req a\n@verifies a v1\n") ])
    "verifies:req:a->a" "rung" (str "wrong-source")

let an_inline_description_loses_its_blanks () =
  let records =
    records [ ("a.md", "# A\n\n@cites x v1 \t text  here \t\n@cites y\n") ]
  in
  check_field records "cites:site:a.md#a->x" "desc" (str "text  here");
  check_field records "cites:site:a.md#a->y" "desc" None

let supersedes =
  "# A\n\n@decision new v1\n@supersedes old v1\n\n# B\n\n@decision old\n"

let an_effective_supersedes_edge_retires_its_target () =
  let records = records [ ("a.md", supersedes) ] in
  check_field records "supersedes:decision:new->old" "effective" (bool true);
  check_field records "decision:old" "inforce" (bool false);
  check_field records "decision:new" "inforce" (bool true)

let a_source_that_is_not_approved_retires_nothing () =
  let records =
    records ~extra:"[ledger]\napproval-required = [\"decision\"]\n"
      [ ("a.md", supersedes) ]
  in
  check_field records "supersedes:decision:new->old" "effective" (bool false);
  check_field records "decision:old" "inforce" (bool true)

let chain ?(kind = "decision") ?(middle = "") () =
  [
    ( "a.md",
      "# A\n\n@decision c\n@supersedes b v1\n\n# B\n\n@" ^ kind ^ " b\n"
      ^ middle ^ "@supersedes a v1\n\n# C\n\n@decision a\n" );
  ]

let a_chain_retires_each_declaration_before_its_end () =
  let records = records (chain ()) in
  check_field records "supersedes:decision:c->b" "effective" (bool true);
  check_field records "supersedes:decision:b->a" "effective" (bool true);
  check_field records "decision:c" "inforce" (bool true);
  check_field records "decision:b" "inforce" (bool false);
  check_field records "decision:a" "inforce" (bool false)

let a_status_tag_on_the_middle_of_a_chain_brings_back_the_first () =
  let records = records (chain ~middle:"@deprecated\n" ()) in
  check_field records "supersedes:decision:c->b" "effective" (bool true);
  check_field records "supersedes:decision:b->a" "effective" (bool false);
  check_field records "decision:b" "inforce" (bool false);
  check_field records "decision:a" "inforce" (bool true)

let a_middle_that_is_not_approved_retires_nothing () =
  let records =
    records ~extra:"[ledger]\napproval-required = [\"design\"]\n"
      (chain ~kind:"design" ())
  in
  check_field records "supersedes:decision:c->b" "effective" (bool true);
  check_field records "supersedes:design:b->a" "effective" (bool false);
  check_field records "design:b" "inforce" (bool false);
  check_field records "decision:a" "inforce" (bool true)

let two_declarations_that_supersede_one_both_retire_it () =
  let records =
    records
      [
        ( "a.md",
          "# A\n\n\
           @decision b\n\
           @supersedes a v1\n\n\
           # B\n\n\
           @decision c\n\
           @supersedes a v1\n\n\
           # C\n\n\
           @decision a\n" );
      ]
  in
  check_field records "supersedes:decision:b->a" "effective" (bool true);
  check_field records "supersedes:decision:c->a" "effective" (bool true);
  check_field records "decision:a" "inforce" (bool false)

let declarations_of_two_files_keep_their_own_numbers () =
  let records =
    records
      [
        ("a.md", "# A\n\n@decision x\n@deprecated\n");
        ("b.md", "# B\n\n@decision y\n@supersedes z v1\n\n# Z\n\n@decision z\n");
      ]
  in
  check_field records "supersedes:decision:y->z" "effective" (bool true);
  check_field records "decision:z" "inforce" (bool false)

let a_rule_that_supersedes_retires_its_target () =
  check_field
    (records
       [
         ("a.md", "# R\n\n@rule r v1\n@supersedes d v1\n\n# D\n\n@decision d\n");
       ])
    "decision:d" "inforce" (bool false)

let every_member_of_a_supersedes_cycle_is_in_force () =
  let records =
    records
      [
        ( "a.md",
          "# A\n\n\
           @decision a\n\
           @supersedes b v1\n\n\
           # B\n\n\
           @decision b\n\
           @supersedes a v1\n\n\
           # S\n\n\
           @decision s\n\
           @supersedes s v1\n" );
      ]
  in
  List.iter
    (fun id -> check_field records id "inforce" (bool true))
    [ "decision:a"; "decision:b"; "decision:s" ]

let a_cycle_counts_its_edges_that_are_not_effective () =
  let records =
    records
      [
        ( "a.md",
          "# Z\n\n\
           @decision z\n\
           @supersedes x v1\n\n\
           # X\n\n\
           @decision x\n\
           @supersedes y v1\n\n\
           # Y\n\n\
           @decision y\n\
           @deprecated\n\
           @supersedes x v1\n" );
      ]
  in
  check_field records "supersedes:decision:z->x" "effective" (bool true);
  check_field records "supersedes:decision:y->x" "effective" (bool false);
  check_field records "decision:x" "inforce" (bool true);
  check_field records "decision:y" "inforce" (bool false)

let a_supersedes_edge_from_a_site_is_not_effective () =
  let records =
    records [ ("a.md", "# A\n\n@supersedes old v1\n\n# B\n\n@decision old\n") ]
  in
  check_field records "supersedes:site:a.md#a->old" "effective" (bool false);
  check_field records "decision:old" "inforce" (bool true)

let an_ack_names_the_fact_of_its_block () =
  let records =
    records
      [
        ( "a.md",
          "# A\n\n\
           @req a\n\
           @ack retired  cache-ttl 1a2b3c4d\n\n\
           # B\n\n\
           @cites a\n\
           @ack stale 0123abcd\n" );
      ]
  in
  Alcotest.(check string)
    "the ack of a declaration"
    "{\"block\":\"req:a\",\"col\":1,\"ecol\":33,\"eline\":4,\"hash\":\"1a2b3c4d\",\"id\":\"ack:req:a:retired  \
     cache-ttl\",\"kind\":\"ack\",\"line\":4,\"pack\":\"markdown\",\"path\":\"a.md\",\"target\":\"retired  \
     cache-ttl\",\"v\":1}"
    (Jsonl.to_string (find "ack:req:a:retired  cache-ttl" records));
  check_field records "ack:site:a.md#b:stale" "block" (str "site:a.md#b")

let the_hash_of_an_ack_follows_its_last_blank () =
  let records =
    records
      [
        ( "a.md",
          "# A\n\n@req a\n@ack x y\tH1 \t\n\n# B\n\n@req b\n@ack p\tq \t R2\n"
        );
      ]
  in
  check_field records "ack:req:a:x y" "hash" (str "H1");
  check_field records "ack:req:b:p\tq" "hash" (str "R2")

let an_ack_with_no_fact_or_no_hash_gives_no_record () =
  Alcotest.(check (list string))
    "no ack record" []
    (List.filter
       (fun id -> String.starts_with ~prefix:"ack:" id)
       (ids
          (records
             [
               ( "a.md",
                 "# A\n\n@ack stale 0123abcd\n\n# B\n\n@req b\n@ack 0123abcd\n"
               );
             ])))

let auth_plan =
  "# Auth lockout\n\n\
   @plan auth-lockout\n\
   @scope src/**\n\n\
   ## Lock the account\n\n\
   @scope src/auth/**\n\
   @req auth-lockout\n\
   @verifies auth-lockout\n\n\
   ## Record the policy\n\n\
   @decision lockout-policy\n"

let a_plan_file_gives_its_plan_steps_and_promises () =
  let csh =
    Sha256.hex
      "{\"promises\":[{\"scope\":[\"src/**\"],\"target\":\"lockout-policy\",\"word\":\"decision\"},{\"scope\":[\"src/auth/**\"],\"target\":\"auth-lockout\",\"word\":\"req\"},{\"scope\":[\"src/auth/**\"],\"target\":\"auth-lockout\",\"word\":\"verifies\"}],\"scope\":[\"src/**\"]}"
  in
  Alcotest.(check (list string))
    "the records, in order"
    [
      Printf.sprintf
        "{\"active\":false,\"approved\":true,\"col\":1,\"csh\":\"%s\",\"declined\":false,\"ecol\":19,\"eline\":3,\"id\":\"plan:auth-lockout\",\"kind\":\"plan\",\"line\":3,\"open\":true,\"pack\":\"markdown\",\"path\":\".plans/auth.md\",\"scope\":[\"src/**\"],\"slug\":\"auth-lockout\",\"title\":\"Auth \
         lockout\",\"v\":1}"
        csh;
      "{\"col\":1,\"ecol\":18,\"eline\":9,\"id\":\"promise:step:auth-lockout/lock-the-account:req:auth-lockout\",\"kind\":\"promise\",\"line\":9,\"met\":false,\"out_of_scope\":false,\"pack\":\"markdown\",\"path\":\".plans/auth.md\",\"plan\":\"auth-lockout\",\"step\":\"lock-the-account\",\"target\":\"auth-lockout\",\"v\":1,\"word\":\"req\"}";
      "{\"col\":1,\"ecol\":23,\"eline\":10,\"id\":\"promise:step:auth-lockout/lock-the-account:verifies:auth-lockout\",\"kind\":\"promise\",\"line\":10,\"met\":false,\"out_of_scope\":false,\"pack\":\"markdown\",\"path\":\".plans/auth.md\",\"plan\":\"auth-lockout\",\"step\":\"lock-the-account\",\"target\":\"auth-lockout\",\"v\":1,\"word\":\"verifies\"}";
      "{\"col\":1,\"ecol\":25,\"eline\":14,\"id\":\"promise:step:auth-lockout/record-the-policy:decision:lockout-policy\",\"kind\":\"promise\",\"line\":14,\"met\":false,\"out_of_scope\":false,\"pack\":\"markdown\",\"path\":\".plans/auth.md\",\"plan\":\"auth-lockout\",\"step\":\"record-the-policy\",\"target\":\"lockout-policy\",\"v\":1,\"word\":\"decision\"}";
      "{\"active\":false,\"col\":1,\"done\":false,\"ecol\":20,\"eline\":6,\"id\":\"step:auth-lockout/lock-the-account\",\"kind\":\"step\",\"line\":6,\"met\":0,\"own_scope\":true,\"pack\":\"markdown\",\"path\":\".plans/auth.md\",\"plan\":\"auth-lockout\",\"refactor\":false,\"scope\":[\"src/auth/**\"],\"slug\":\"lock-the-account\",\"title\":\"Lock \
       the account\",\"total\":2,\"v\":1}";
      "{\"active\":false,\"col\":1,\"done\":false,\"ecol\":21,\"eline\":12,\"id\":\"step:auth-lockout/record-the-policy\",\"kind\":\"step\",\"line\":12,\"met\":0,\"own_scope\":false,\"pack\":\"markdown\",\"path\":\".plans/auth.md\",\"plan\":\"auth-lockout\",\"refactor\":false,\"scope\":[\"src/**\"],\"slug\":\"record-the-policy\",\"title\":\"Record \
       the policy\",\"total\":1,\"v\":1}";
    ]
    (lines [ (".plans/auth.md", auth_plan) ])

let promise = "promise:step:auth-lockout/lock-the-account:req:auth-lockout"

let a_declaration_in_the_scope_of_the_step_meets_its_promise () =
  let records =
    records
      [
        (".plans/auth.md", auth_plan);
        ("src/auth/a.md", "# A\n\n@req auth-lockout\n");
        ("src/d.md", "# D\n\n@decision lockout-policy\n");
      ]
  in
  check_field records promise "met" (bool true);
  check_field records promise "by" (str "req:auth-lockout");
  check_field records "step:auth-lockout/lock-the-account" "met" (int 1);
  check_field records "step:auth-lockout/record-the-policy" "met" (int 1);
  check_field records "step:auth-lockout/record-the-policy" "done" (bool true)

let a_declaration_outside_the_scope_is_out_of_scope () =
  let records =
    records
      [
        (".plans/auth.md", auth_plan);
        ("docs/a.md", "# A\n\n@req auth-lockout\n");
      ]
  in
  check_field records promise "met" (bool false);
  check_field records promise "by" None;
  check_field records promise "out_of_scope" (bool true)

let a_declaration_of_another_kind_meets_no_promise () =
  let records =
    records
      [
        (".plans/auth.md", auth_plan);
        ("src/auth/a.md", "# A\n\n@design auth-lockout\n");
      ]
  in
  check_field records promise "met" (bool false);
  check_field records promise "out_of_scope" (bool false)

let the_default_location_of_the_kind_meets_a_promise () =
  let records =
    records ~extra:"[plan]\nlocations.req = [\"docs/\"]\n"
      [
        (".plans/auth.md", auth_plan);
        ("docs/a.md", "# A\n\n@req auth-lockout\n");
      ]
  in
  check_field records promise "met" (bool true);
  check_field records promise "out_of_scope" (bool false)

let cites_plan = "# P\n\n@plan p\n@scope docs/**\n\n## Cite\n\n@cites target\n"
let cites_promise = "promise:step:p/cite:cites:target"

let an_edge_that_resolves_and_is_not_suspect_meets_its_promise () =
  let records rev =
    records
      [
        (".plans/p.md", cites_plan);
        ("docs/a.md", "# A\n\n@cites target v1\n");
        ("other/t.md", Printf.sprintf "# T\n\n@req target v%d\n" rev);
      ]
  in
  check_field (records 1) cites_promise "met" (bool true);
  check_field (records 1) cites_promise "by"
    (str "cites:site:docs/a.md#a->target");
  check_field (records 2) cites_promise "met" (bool false) ~message:"(suspect)";
  check_field (records 2) cites_promise "out_of_scope" (bool false)

let a_dangling_edge_meets_no_promise () =
  let records =
    records
      [ (".plans/p.md", cites_plan); ("docs/a.md", "# A\n\n@cites target\n") ]
  in
  check_field records cites_promise "met" (bool false)

let a_verifies_promise_is_never_met_in_markdown () =
  let records =
    records
      [
        (".plans/auth.md", auth_plan);
        ( "src/auth/a.md",
          "# A\n\n@req auth-lockout\n@verifies auth-lockout v1\n" );
      ]
  in
  check_field records
    "promise:step:auth-lockout/lock-the-account:verifies:auth-lockout" "met"
    (bool false);
  check_field records "step:auth-lockout/lock-the-account" "done" (bool false)

let refactor = "# P\n\n@plan p\n\n## Clean\n\n@scope lib/**\n"

let a_step_with_no_promise_is_done_when_the_diff_changes_its_scope () =
  check_field
    (records ~changed:[ "bin/x.ml"; "lib/y.ml" ] [ (".plans/p.md", refactor) ])
    "step:p/clean" "done" (bool true);
  check_field
    (records ~changed:[ "bin/x.ml" ] [ (".plans/p.md", refactor) ])
    "step:p/clean" "done" (bool false);
  check_field
    (records [ (".plans/p.md", refactor) ])
    "step:p/clean" "refactor" (bool true)

let an_external_id_meets_a_promised_citation () =
  check_field
    (records
       [
         ( ".plans/p.md",
           "# P\n\n@plan p\n@scope docs/**\n\n## C\n\n@cites gh/7\n" );
         ("docs/a.md", "# A\n\n@cites gh/7\n");
       ])
    "promise:step:p/c:cites:gh/7" "by"
    (str "cites:site:docs/a.md#a->gh/7")

let only_a_verifies_edge_in_the_scope_keeps_a_step_from_done () =
  check_field
    (records ~changed:[ "lib/y.ml" ]
       [
         (".plans/p.md", refactor);
         ("lib/a.md", "# A\n\n@cites x v1\n");
         ("doc/a.md", "# A\n\n@verifies x v1\n");
       ])
    "step:p/clean" "done" (bool true)

let a_verifies_edge_in_the_scope_keeps_a_step_from_done () =
  check_field
    (records ~changed:[ "lib/y.ml" ]
       [ (".plans/p.md", refactor); ("lib/a.md", "# A\n\n@verifies x v1\n") ])
    "step:p/clean" "done" (bool false)

let only_a_step_with_no_promise_needs_the_changes () =
  Alcotest.(check (list bool))
    "a plan with a refactor step, and one without" [ true; false ]
    (List.map
       (fun text -> Facts.needs_changes (facts [ (".plans/p.md", text) ]))
       [ refactor; auth_plan ])

let repeated_promises_of_a_step_collapse () =
  let records =
    records [ (".plans/p.md", "# P\n\n@plan p\n\n## S\n\n@req a\n@req a\n") ]
  in
  check_field records "promise:step:p/s:req:a" "line" (int 7);
  check_field records "step:p/s" "total" (int 1)

let a_step_holds_the_promises_of_its_items_and_subsections () =
  Alcotest.(check (list string))
    "the promises of the step"
    [ "promise:step:p/s:req:in-item"; "promise:step:p/s:req:in-sub" ]
    (List.filter
       (fun id -> String.starts_with ~prefix:"promise:" id)
       (ids
          (records
             [
               ( ".plans/p.md",
                 "# P\n\n\
                  @plan p\n\n\
                  ## S\n\n\
                  Text.\n\n\
                  - @req in-item\n\n\
                  ### Sub\n\n\
                  @req in-sub\n" );
             ])))

let a_level_2_section_with_no_plan_tag_is_no_step () =
  Alcotest.(check (list string))
    "the plan alone" [ "plan:p" ]
    (ids
       (records
          [ (".plans/p.md", "# P\n\n@plan p\n\n## Notes\n\nJust text.\n") ]))

let a_plan_at_level_0_with_no_scope_has_no_title () =
  let records = records [ (".plans/p.md", "@plan p\n\n## S\n\n@req r\n") ] in
  check_field records "plan:p" "title" None;
  check_field records "plan:p" "scope" (Some (Jsonl.strings []));
  check_field records "step:p/s" "scope" (Some (Jsonl.strings []))

let a_scope_line_holds_globs_between_commas () =
  let records =
    records
      [ (".plans/p.md", "# P\n\n@plan p\n@scope a/**,  b/ ,, !a/x/\t,\n") ]
  in
  check_field records "plan:p" "scope"
    (Some (Jsonl.strings [ "a/**"; "b/"; "!a/x/" ]))

let a_glob_with_a_bang_narrows_the_scope_of_a_step () =
  let records path =
    records
      [
        ( ".plans/p.md",
          "# P\n\n@plan p\n\n## S\n\n@scope src/**, !src/gen/, [x, !\n@req r\n"
        );
        (path, "# R\n\n@req r\n");
      ]
  in
  check_field (records "src/a.md") "promise:step:p/s:req:r" "met" (bool true);
  check_field (records "src/gen/a.md") "promise:step:p/s:req:r" "met"
    (bool false);
  check_field (records "src/gen/a.md") "promise:step:p/s:req:r" "out_of_scope"
    (bool true)

let a_plan_that_needs_approval_is_not_approved () =
  check_field
    (records ~extra:"[ledger]\napproval-required = [\"plan\"]\n"
       [ (".plans/p.md", refactor) ])
    "plan:p" "approved" (bool false)

let tags_in_a_plan_file_give_no_declaration_and_no_edge () =
  Alcotest.(check (list string))
    "no declaration and no edge" []
    (List.filter
       (fun id ->
         not
           (String.starts_with ~prefix:"p" id
           || String.starts_with ~prefix:"step" id))
       (ids
          (records
             [ (".plans/auth.md", auth_plan ^ "\n## More\n\n@cites x v1\n") ])))

let a_file_whose_first_block_has_no_plan_tag_is_no_plan () =
  Alcotest.(check (list string))
    "an ordinary file" [ "req:x" ]
    (ids
       (records [ (".plans/notes.md", "# N\n\n@req x\n\n## S\n\n@plan p\n") ]))

let a_plan_tag_outside_plans_gives_no_plan () =
  Alcotest.(check (list string))
    "no record" []
    (ids
       (records
          [
            ("docs/p.md", "# P\n\n@plan p\n");
            (".plans/q.md", "# Q\n\n@plan Bad/Slug\n\n## S\n\n@req r\n");
          ]))

let the_index_names_the_tree_and_the_base () =
  Alcotest.(check string)
    "the index record"
    "{\"base\":\"b\",\"default_branch\":\"main\",\"evidence\":false,\"kind\":\"index\",\"manifest\":\"sinter.toml\",\"mode\":\"tree\",\"packs\":[],\"tool\":\"v1\",\"tree\":\"t\",\"v\":1}"
    (Jsonl.to_string
       (Facts.index ~tree:"t" ~base:"b" ~default_branch:"main"
          ~manifest:"sinter.toml" ~tool:"v1"))

module Gen = QCheck2.Gen

let line =
  Gen.oneof
    [
      Gen.oneof_list
        [
          "# A";
          "## S";
          "## S";
          "### T";
          "";
          "";
          "Prose.";
          "> @req q v1";
          "```";
          "<!-- c -->";
          "---";
          "+++";
          "\t@cites a v1";
        ];
      Gen.map3
        (fun prefix word (target, rest) -> prefix ^ "@" ^ word ^ target ^ rest)
        (Gen.oneof_list [ ""; "- "; "  "; "1. "; "- [x] "; "  - " ])
        (Gen.oneof_list
           [
             "req";
             "design";
             "decision";
             "rule";
             "plan";
             "scope";
             "cites";
             "satisfies";
             "verifies";
             "refines";
             "supersedes";
             "deprecated";
             "rejected";
             "deferred";
             "ack";
             "pin";
             "";
           ])
        (Gen.pair
           (Gen.oneof_list
              [
                ""; " a"; " b"; " A"; " gh/1"; " x/y"; " bad!"; " src/**, a.md";
              ])
           (Gen.oneof_list
              [ ""; " v1"; " v2"; " v0"; " 0123abcd"; " some text" ]));
    ]

let tree =
  Gen.map
    (fun files ->
      List.sort_uniq (fun (a, _) (b, _) -> String.compare a b) files)
    (Gen.list_size (Gen.int_bound 3)
       (Gen.pair
          (Gen.oneof_list [ "a.md"; "src/b.md"; ".plans/p.md"; ".plans/q.md" ])
          (Gen.map (String.concat "\n") (Gen.list_size (Gen.int_bound 14) line))))

let print_tree = QCheck2.Print.(list (pair string string))

let property name check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:200 ~name ~print:print_tree tree check)

let text name record =
  match field name record with
  | Some (Jsonl.Scalar (Jsonl.String text)) -> Some text
  | _ -> None

let number name record =
  match field name record with
  | Some (Jsonl.Scalar (Jsonl.Int number)) -> Some number
  | _ -> None

let key record =
  match text "path" record with
  | Some path ->
      ( 0,
        Option.value (text "kind" record) ~default:"",
        path,
        Option.value (number "line" record) ~default:0,
        Option.value (number "col" record) ~default:0,
        id record )
  | None -> (1, "", "", 0, 0, id record)

let rec sorted = function
  | a :: (b :: _ as rest) -> compare a b <= 0 && sorted rest
  | [] | [ _ ] -> true

let records_come_in_their_order =
  property "the records come in the order of kind, path, line, col, and id"
    (fun files -> sorted (List.map key (records ~changed:[ "a.md" ] files)))

let every_reference_names_a_record =
  property "every src, dst, block, and by names a record, or a rule"
    (fun files ->
      let records = records files in
      let known = ids records in
      List.for_all
        (fun record ->
          List.for_all
            (fun name ->
              match text name record with
              | None -> true
              | Some named ->
                  List.mem named known
                  || String.starts_with ~prefix:"rule:" named)
            [ "src"; "dst"; "block"; "by" ])
        records)

let every_record_is_canonical =
  property "every record writes as a canonical line" (fun files ->
      List.for_all
        (fun record -> String.length (Jsonl.to_string record) > 0)
        (records files))

let span_text (span : Markdown.span) =
  Printf.sprintf "%d:%d-%d:%d" span.start.line span.start.column span.stop.line
    span.stop.column

let the_view_gives_each_declaration_in_order () =
  let facts =
    facts
      [
        ( "docs/b.md",
          "# B\n\n@req b v2 Text.\n\n## C\n\n@deprecated\n@design c\n" );
        ("docs/a.md", "# A\n\n@decision a\n@rejected\n");
      ]
  in
  Alcotest.(check (list string))
    "kind, slug, rev, path, span, status"
    [
      "req b 2 docs/b.md 3:1-3:16 -";
      "design c 1 docs/b.md 8:1-8:10 deprecated";
      "decision a 1 docs/a.md 3:1-3:12 rejected";
    ]
    (List.map
       (fun (d : Facts.declaration) ->
         String.concat " "
           [
             d.kind;
             d.slug;
             string_of_int d.rev;
             d.path;
             span_text d.span;
             Option.value d.status ~default:"-";
           ])
       (Facts.declarations facts))

let is_in_force_reads_status_and_supersession () =
  let facts =
    facts
      [
        ( "docs/a.md",
          "# A\n\n\
           @decision a\n\n\
           ## B\n\n\
           @decision b\n\
           @supersedes a v1\n\n\
           ## C\n\n\
           @decision c\n\
           @deferred\n" );
      ]
  in
  Alcotest.(check (list bool))
    "a is superseded, b is in force, c is deferred" [ false; true; false ]
    (List.mapi
       (fun index _ -> Facts.is_in_force facts index)
       (Facts.declarations facts));
  List.iter
    (fun index ->
      match Facts.is_in_force facts index with
      | (_ : bool) -> Alcotest.failf "index %d: no exception" index
      | exception Invalid_argument _ -> ())
    [ -1; 3 ]

let successors facts id =
  let declarations = Array.of_list (Facts.declarations facts) in
  let place index =
    let declaration = declarations.(index) in
    Facts.declaration_id declaration ^ " " ^ declaration.path
  in
  match
    List.find_opt
      (fun index -> String.equal (Facts.declaration_id declarations.(index)) id)
      (List.init (Array.length declarations) Fun.id)
  with
  | Some index -> List.map place (Facts.successors facts index)
  | None -> Alcotest.failf "no declaration has the id %s" id

let check_successors facts id expected =
  Alcotest.(check (list string)) id expected (successors facts id)

let successors_follow_a_chain_to_its_end () =
  let facts = facts (chain ()) in
  check_successors facts "decision:a" [ "decision:c a.md" ];
  check_successors facts "decision:b" [ "decision:c a.md" ];
  check_successors facts "decision:c" []

let successors_stop_where_a_status_tag_stops_an_edge () =
  let facts = facts (chain ~middle:"@deprecated\n" ()) in
  check_successors facts "decision:b" [ "decision:c a.md" ];
  check_successors facts "decision:a" []

let a_status_tag_alone_gives_no_successors () =
  check_successors
    (facts [ ("a.md", "# A\n\n@decision a\n@rejected\n") ])
    "decision:a" []

let successors_come_in_the_order_of_their_ids () =
  check_successors
    (facts
       [
         ( "a.md",
           "# C\n\n\
            @decision c\n\
            @supersedes a v1\n\n\
            # B\n\n\
            @decision b\n\
            @supersedes a v1\n\n\
            # A\n\n\
            @decision a\n" );
       ])
    "decision:a"
    [ "decision:b a.md"; "decision:c a.md" ]

let a_successor_that_two_paths_reach_comes_once () =
  check_successors
    (facts
       [
         ( "a.md",
           "# D\n\n\
            @decision d\n\
            @supersedes b v1\n\
            @supersedes c v1\n\n\
            # C\n\n\
            @decision c\n\
            @supersedes a v1\n\n\
            # B\n\n\
            @decision b\n\
            @supersedes a v1\n\n\
            # A\n\n\
            @decision a\n" );
       ])
    "decision:a" [ "decision:d a.md" ]

let of_two_successors_with_one_id_the_first_record_stays () =
  check_successors
    (facts
       [
         ("z.md", "# Z\n\n@decision b v2\n@supersedes a v1\n");
         ( "y.md",
           "# Y\n\n@decision b v3\n@supersedes a v1\n\n## A\n\n@decision a\n" );
       ])
    "decision:a" [ "decision:b y.md" ]

let a_member_of_a_cycle_has_no_successors () =
  let facts =
    facts
      [
        ( "a.md",
          "# A\n\n\
           @decision a\n\
           @supersedes b v1\n\
           @supersedes x v1\n\n\
           # B\n\n\
           @decision b\n\
           @supersedes a v1\n\n\
           # X\n\n\
           @decision x\n" );
      ]
  in
  check_successors facts "decision:a" [];
  check_successors facts "decision:b" [];
  check_successors facts "decision:x" [ "decision:a a.md" ]

let successors_refuse_an_index_out_of_range () =
  let facts = facts (chain ()) in
  List.iter
    (fun index ->
      match Facts.successors facts index with
      | (_ : int list) -> Alcotest.failf "index %d: no exception" index
      | exception Invalid_argument _ -> ())
    [ -1; 3 ]

let graph =
  Gen.(
    list_size (int_range 1 6)
      (triple
         (oneof_list [ "decision"; "decision"; "design" ])
         (oneof_list [ ""; ""; ""; "@deprecated\n"; "@rejected\n" ])
         (list_size (int_bound 2) (int_bound 6))))

let graph_text declarations =
  "# G\n\n"
  ^ String.concat ""
      (List.mapi
         (fun n (kind, status, superseded) ->
           Printf.sprintf "## D%d\n\n@%s d%d\n%s%s\n" n kind n status
             (String.concat ""
                (List.map (Printf.sprintf "@supersedes d%d v1\n") superseded)))
         declarations)

let successors_end_in_force_and_only_effective_edges_retire =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:200
       ~name:
         "a declaration that an effective edge retires has successors, each in \
          force; only a status tag or an effective edge retires a declaration"
       ~print:graph_text graph (fun graph ->
         let facts =
           facts ~extra:"[ledger]\napproval-required = [\"design\"]\n"
             [ ("a.md", graph_text graph) ]
         in
         let declarations = Array.of_list (Facts.declarations facts) in
         let effective_into index =
           List.exists
             (fun ((edge : Facts.edge), target) ->
               match (edge.word, edge.source, target) with
               | "supersedes", Some source, Facts.Declaration target ->
                   target = index
                   && Option.is_none declarations.(source).status
                   && not (String.equal declarations.(source).kind "design")
               | _ -> false)
             (Facts.edges facts)
         in
         List.for_all
           (fun index ->
             let in_force = Facts.is_in_force facts index in
             let successors = Facts.successors facts index in
             let retired_by_an_edge = (not in_force) && effective_into index in
             (if retired_by_an_edge then
                successors <> []
                && List.for_all (Facts.is_in_force facts) successors
              else successors = [])
             && (Option.is_some declarations.(index).status
                || effective_into index || in_force)
             && (Option.is_none declarations.(index).status || not in_force))
           (List.init (Array.length declarations) Fun.id)))

let edges_give_what_their_targets_resolve_to () =
  let facts =
    facts
      [
        ( "docs/a.md",
          "# A\n\n@req a v1\n@cites gh/4 Text.\n\n## B\n\n@refines a v1\n" );
        ( "docs/b.md",
          "# B\n\nProse.\n\n- @cites zz/1\n- @cites nothing\n- @cites bad!\n" );
      ]
  in
  let target = function
    | Facts.Declaration index -> Printf.sprintf "declaration %d" index
    | Facts.External { ns; id } -> Printf.sprintf "external %s %s" ns id
    | Facts.Unresolved { dangling } -> Printf.sprintf "unresolved %b" dangling
  in
  Alcotest.(check (list string))
    "word, path, span, src, source, target, rev, desc, block, resolution"
    [
      "cites docs/a.md 4:1-4:18 req:a 0 gh/4 - Text. 0 external gh 4";
      "refines docs/a.md 8:1-8:14 req:a 0 a 1  1 declaration 0";
      "cites docs/b.md 5:3-5:14 site:docs/b.md#b - zz/1 -  0 unresolved false";
      "cites docs/b.md 6:3-6:17 site:docs/b.md#b - nothing -  1 unresolved true";
      "cites docs/b.md 7:3-7:14 site:docs/b.md#b - bad! -  2 unresolved false";
    ]
    (List.map
       (fun ((edge : Facts.edge), resolution) ->
         String.concat " "
           [
             edge.word;
             edge.path;
             span_text edge.span;
             edge.src;
             Option.fold ~none:"-" ~some:string_of_int edge.source;
             edge.target_text;
             Option.fold ~none:"-" ~some:string_of_int edge.rev;
             edge.desc;
             string_of_int edge.block_index;
             target resolution;
           ])
       (Facts.edges facts))

let acks_give_their_block () =
  let facts =
    facts
      [
        ( "docs/a.md",
          "# A\n\n@req a v1\n\n## B\n\n@cites a\n@ack retired a 1234abcd\n" );
        ( "docs/b.md",
          "# B\n\nText.\n\n## C\n\n@cites a\n@ack retired 89abcdef\n" );
      ]
  in
  Alcotest.(check (list string))
    "path, span, block, target, hash, block index"
    [
      "docs/a.md 8:1-8:24 req:a retired a 1234abcd 1";
      "docs/b.md 8:1-8:22 site:docs/b.md#c retired 89abcdef 0";
    ]
    (List.map
       (fun (ack : Facts.ack) ->
         String.concat " "
           [
             ack.path;
             span_text ack.span;
             ack.block;
             ack.target;
             ack.hash;
             string_of_int ack.block_index;
           ])
       (Facts.acks facts))

let plans_give_their_steps_and_promises () =
  let facts =
    facts
      [
        ( ".plans/p.md",
          "# P\n\n\
           @plan p\n\
           @scope lib/**, test/**\n\n\
           ## One\n\n\
           @scope lib/**\n\
           @req a\n\
           @verifies a\n\n\
           ## Two\n\n\
           @cites b\n" );
      ]
  in
  Alcotest.(check (list string))
    "plans, steps, promises"
    [
      "plan p .plans/p.md 3:1-3:8 P lib/**,test/**";
      "step one 6:1-6:7 One lib/** effective lib/**";
      "promise req a 9:1-9:7";
      "promise verifies a 10:1-10:12";
      "step two 12:1-12:7 Two - effective lib/**,test/**";
      "promise cites b 14:1-14:9";
    ]
    (List.concat_map
       (fun (plan : Facts.plan) ->
         String.concat " "
           [
             "plan";
             plan.slug;
             plan.path;
             span_text plan.span;
             Option.value plan.title ~default:"-";
             String.concat "," plan.scope;
           ]
         :: List.concat_map
              (fun (step : Facts.step) ->
                String.concat " "
                  [
                    "step";
                    step.slug;
                    span_text step.span;
                    step.title;
                    Option.fold ~none:"-" ~some:(String.concat ",")
                      step.own_scope;
                    "effective";
                    String.concat "," (Facts.effective_scope plan step);
                  ]
                :: List.map
                     (fun (promise : Facts.promise) ->
                       String.concat " "
                         [
                           "promise";
                           promise.word;
                           promise.target;
                           span_text promise.span;
                         ])
                     step.promises)
              plan.steps)
       (Facts.plans facts))

let standing_names_the_facts_that_meet_and_the_one_in_scope () =
  let facts =
    facts ~extra:"[plan]\nlocations.decision = [\"docs/decisions/\"]\n"
      [
        ( ".plans/p.md",
          "# P\n\n\
           @plan p\n\
           @scope lib/**\n\n\
           ## One\n\n\
           @req a\n\
           @req b\n\
           @decision c\n\
           @cites a\n\
           @verifies a\n" );
        ("docs/a.md", "# A\n\n@req a v1\n@cites a v2\n\n## C\n\n@cites a v1\n");
        ("lib/a.md", "# A\n\n@req a v1\n");
        ("docs/decisions/c.md", "# C\n\n@decision c\n");
        ("lib/b.md", "# B\n\n@verifies a v1\n");
      ]
  in
  match Facts.plans facts with
  | [ ({ steps = [ step ]; _ } as plan) ] ->
      let fact_text (fact : Facts.meeting_fact) =
        Printf.sprintf "%s %s %s" fact.id fact.path (span_text fact.span)
      in
      Alcotest.(check (list string))
        "by, then the facts that meet the promise"
        [
          "req a: lib/a.md | req:a docs/a.md 3:1-3:10, req:a lib/a.md 3:1-3:10";
          "req b: - | ";
          "decision c: docs/decisions/c.md | decision:c docs/decisions/c.md \
           3:1-3:12";
          "cites a: - | cites:req:a->a docs/a.md 8:1-8:12";
          "verifies a: - | ";
        ]
        (List.map
           (fun (promise : Facts.promise) ->
             let standing = Facts.standing facts plan step promise in
             Printf.sprintf "%s %s: %s | %s" promise.word promise.target
               (Option.fold ~none:"-"
                  ~some:(fun (by : Facts.meeting_fact) -> by.path)
                  standing.by)
               (String.concat ", " (List.map fact_text standing.meeting_facts)))
           step.promises)
  | _ -> Alcotest.fail "one plan with one step"

let lookup_lines =
  [
    "@req a";
    "@req a v2";
    "@req A";
    "@req b";
    "@design a";
    "@decision a";
    "@decision c";
    "@cites a";
    "@cites a v1";
    "@cites a v2";
    "@cites gh/1";
    "@cites x/y";
    "@satisfies b";
    "@satisfies b v1";
    "@refines a";
    "@verifies a";
    "@verifies b";
    "@deprecated";
    "@ack retired a 0123abcd";
    "@ack retired 89abcdef";
    "@cites a\n@ack retired a 0123abcd\n@ack retired b 89abcdef";
  ]

let lookup_promises =
  [
    "@req a";
    "@req A";
    "@req b";
    "@design a";
    "@decision a";
    "@decision c";
    "@cites a";
    "@cites gh/1";
    "@satisfies b";
    "@refines a";
    "@verifies a";
  ]

let lookup_scopes =
  [ "src/**"; "lib/**"; "**"; "docs/**"; "a.md"; "src/**, !src/b.md"; "" ]

let lookup_tree =
  let ordinary =
    Gen.map2
      (fun path sections ->
        ( path,
          "# T\n\n"
          ^ String.concat ""
              (List.mapi
                 (fun n lines ->
                   Printf.sprintf "## S%d\n\n%s\n\n" n
                     (String.concat "\n" lines))
                 sections) ))
      (Gen.oneof_list [ "a.md"; "src/b.md"; "lib/c.md"; "docs/decisions/d.md" ])
      (Gen.list_size (Gen.int_range 1 4)
         (Gen.list_size (Gen.int_range 1 3) (Gen.oneof_list lookup_lines)))
  in
  let plan =
    Gen.map2
      (fun scope steps ->
        ( ".plans/p.md",
          Printf.sprintf "# P\n\n@plan p\n@scope %s\n\n" scope
          ^ String.concat ""
              (List.mapi
                 (fun n (own, promises) ->
                   Printf.sprintf "## Step %d\n\n%s%s\n\n" n
                     (if String.equal own "" then "" else "@scope " ^ own ^ "\n")
                     (String.concat "\n" promises))
                 steps) ))
      (Gen.oneof_list [ "**"; "src/**, lib/**, docs/**"; "src/**" ])
      (Gen.list_size (Gen.int_range 1 4)
         (Gen.pair
            (Gen.oneof_list lookup_scopes)
            (Gen.list_size (Gen.int_range 0 4) (Gen.oneof_list lookup_promises))))
  in
  Gen.map2
    (fun files plan ->
      List.sort_uniq (fun (a, _) (b, _) -> String.compare a b) (plan :: files))
    (Gen.list_size (Gen.int_range 1 4) ordinary)
    plan

let lookup_extra = "[plan]\nlocations.decision = [\"docs/decisions/\"]\n"

let lookup_property name check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:200 ~name ~print:print_tree lookup_tree
       (fun files -> check (facts ~extra:lookup_extra files)))

let place (span : Markdown.span) = (span.start.line, span.start.column)

let scanned_meeting facts (promise : Facts.promise) =
  let declarations = Array.of_list (Facts.declarations facts) in
  let found =
    if List.mem promise.word [ "req"; "design"; "decision" ] then
      List.filter_map
        (fun (d : Facts.declaration) ->
          if
            String.equal d.kind promise.word
            && String.equal d.slug promise.target
          then Some (Facts.declaration_id d, d.path, place d.span)
          else None)
        (Facts.declarations facts)
    else if String.equal promise.word "verifies" then []
    else
      List.filter_map
        (fun ((edge : Facts.edge), target) ->
          let meets =
            match (target, edge.rev) with
            | Facts.Declaration index, Some rev ->
                declarations.(index).rev = rev
            | Facts.Declaration _, None | Facts.External _, _ -> true
            | Facts.Unresolved _, _ -> false
          in
          if
            String.equal edge.word promise.word
            && String.equal edge.target_text promise.target
            && meets
          then Some (Facts.edge_id edge, edge.path, place edge.span)
          else None)
        (Facts.edges facts)
  in
  List.stable_sort
    (fun (_, path_a, place_a) (_, path_b, place_b) ->
      compare (path_a, place_a) (path_b, place_b))
    found

let indexed_meeting (standing : Facts.standing) =
  List.map
    (fun (fact : Facts.meeting_fact) -> (fact.id, fact.path, place fact.span))
    standing.meeting_facts

let the_meeting_index_gives_the_list_scan =
  lookup_property
    "the facts that meet each promise are the list scan of the declarations \
     and edges" (fun facts ->
      List.for_all
        (fun (plan : Facts.plan) ->
          List.for_all
            (fun (step : Facts.step) ->
              List.for_all
                (fun promise ->
                  indexed_meeting (Facts.standing facts plan step promise)
                  = scanned_meeting facts promise)
                step.promises)
            plan.steps)
        (Facts.plans facts))

let standing_refuses_a_promise_of_other_facts () =
  let plan_file =
    ( ".plans/p.md",
      "# P\n\n@plan p\n@scope **\n\n## One\n\n@req a\n\n## Two\n\n@req b\n" )
  in
  let facts = facts [ plan_file ] and others = facts [ plan_file ] in
  match (Facts.plans facts, Facts.plans others) with
  | ( [
        ({
           steps = [ ({ promises = [ a ]; _ } as one); { promises = [ b ]; _ } ];
           _;
         } as plan);
      ],
      [
        ({ steps = [ ({ promises = [ other_a ]; _ } as other_one); _ ]; _ } as
         other);
      ] ) ->
      List.iter
        (fun (name, plan, step, promise) ->
          match Facts.standing facts plan step promise with
          | (_ : Facts.standing) -> Alcotest.failf "%s: no exception" name
          | exception Invalid_argument _ -> ())
        [
          ("a plan of other facts", other, other_one, other_a);
          ("a step of another plan", plan, other_one, other_a);
          ("a promise of another step", plan, one, b);
        ];
      ignore (Facts.standing facts plan one a)
  | _ -> Alcotest.fail "one plan with two steps of one promise in each"

let scope_set globs =
  match Path_set.of_strings (List.sort_uniq String.compare globs) with
  | Ok set -> set
  | Error _ -> Alcotest.failf "a bad scope: %s" (String.concat ", " globs)

let changed_paths =
  Gen.list_size (Gen.int_bound 2)
    (Gen.oneof_list [ "a.md"; "src/b.md"; "lib/c.md"; "src/z.md"; "z.md" ])

let print_lookup_case = QCheck2.Print.(pair print_tree (list string))

let a_step_is_done_by_the_list_scan_of_the_verifies_edges =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:200
       ~name:
         "a step is done when no verifies edge is in its scope, by the list \
          scan, and its promises are met or the diff changes its scope"
       ~print:print_lookup_case (Gen.pair lookup_tree changed_paths)
       (fun (files, changed) ->
         let facts = facts ~extra:lookup_extra files in
         let records = Facts.records facts ~changed in
         List.for_all
           (fun (plan : Facts.plan) ->
             List.for_all
               (fun (step : Facts.step) ->
                 let in_scope =
                   Path_set.mem (scope_set (Facts.effective_scope plan step))
                 in
                 let verified =
                   not
                     (List.exists
                        (fun ((edge : Facts.edge), _) ->
                          String.equal edge.word "verifies"
                          && in_scope edge.path)
                        (Facts.edges facts))
                 in
                 let met =
                   List.length
                     (List.filter
                        (fun promise ->
                          Option.is_some
                            (Facts.standing facts plan step promise).by)
                        step.promises)
                 in
                 let total = List.length step.promises in
                 let expected =
                   verified
                   &&
                   if total = 0 then List.exists in_scope changed
                   else met = total
                 in
                 check_field records (Facts.step_id plan step) "done"
                   (bool expected);
                 true)
               plan.steps)
           (Facts.plans facts)))

let by_of_each_promise_is_the_first_meeting_fact_in_place =
  lookup_property
    "the by of each promise is the first fact that meets it in the scope of \
     its step or in the default location of its kind" (fun facts ->
      let manifest = manifest ~extra:lookup_extra () in
      List.for_all
        (fun (plan : Facts.plan) ->
          List.for_all
            (fun (step : Facts.step) ->
              let standing = Facts.standing facts plan step in
              let in_scope =
                Path_set.mem (scope_set (Facts.effective_scope plan step))
              in
              List.for_all
                (fun (promise : Facts.promise) ->
                  let location =
                    Option.bind
                      (match promise.word with
                      | "req" -> Some Manifest.Req
                      | "design" -> Some Manifest.Design
                      | "decision" -> Some Manifest.Decision
                      | _ -> None)
                      (Manifest.location manifest)
                  in
                  let expected =
                    List.find_opt
                      (fun (_, path, _) ->
                        in_scope path
                        || Option.fold ~none:false
                             ~some:(fun set -> Path_set.mem set path)
                             location)
                      (scanned_meeting facts promise)
                  in
                  let standing = standing promise in
                  Option.map
                    (fun (fact : Facts.meeting_fact) ->
                      (fact.id, fact.path, place fact.span))
                    standing.by
                  = expected
                  && indexed_meeting standing = scanned_meeting facts promise)
                step.promises)
            plan.steps)
        (Facts.plans facts))

let block_hash_is_the_hash_of_the_listed_document =
  property
    "the block hash of each block of each file is the hash in the document \
     that the list of files holds" (fun files ->
      let documents =
        List.map (fun (path, text) -> (path, document text)) files
      in
      let facts = Facts.make (manifest ()) documents in
      List.for_all
        (fun (path, _) ->
          let listed : Markdown.t = List.assoc path documents in
          Array.for_all Fun.id
            (Array.mapi
               (fun index (block : Markdown.block) ->
                 String.equal block.hash (Facts.block_hash facts path index))
               listed.blocks)
          &&
          match Facts.block_hash facts path (Array.length listed.blocks) with
          | (_ : string) -> false
          | exception Invalid_argument _ -> true)
        documents
      &&
      match Facts.block_hash facts "missing.md" 0 with
      | (_ : string) -> false
      | exception Not_found -> true)

let block_hash_reads_the_first_of_two_files_with_one_path () =
  let first = document "# A\n\n@req a\nOne.\n" in
  let second = document "# A\n\n@req a\nTwo.\n" in
  let facts = Facts.make (manifest ()) [ ("a.md", first); ("a.md", second) ] in
  Alcotest.(check string)
    "the hash" first.blocks.(0).hash
    (Facts.block_hash facts "a.md" 0);
  Alcotest.(check bool)
    "the two hashes differ" false
    (String.equal first.blocks.(0).hash second.blocks.(0).hash)

let block_acks_are_the_list_scan_of_the_acks =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:200
       ~name:
         "the acks of each block are the acks of the list whose path and block \
          index are those of the block, in the order of the list"
       ~print:print_tree lookup_tree (fun files ->
         let documents =
           List.map (fun (path, text) -> (path, document text)) files
         in
         let facts = Facts.make (manifest ()) documents in
         let acks = Facts.acks facts in
         List.for_all
           (fun (path, (document : Markdown.t)) ->
             List.for_all
               (fun index ->
                 Facts.block_acks facts path index
                 = List.filter
                     (fun (ack : Facts.ack) ->
                       String.equal ack.path path && ack.block_index = index)
                     acks)
               (List.init (Array.length document.blocks + 1) Fun.id))
           (("missing.md", document "") :: documents)))

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "a declaration gives its record" a_declaration_gives_its_record;
    case "a declaration without a revision has revision 1"
      a_declaration_without_a_revision_has_revision_1;
    case "a declaration in a list item or at level 0 has no title"
      a_declaration_in_a_list_item_or_at_level_0_has_no_title;
    case "the trailing prose goes to the last declaration of the block"
      the_trailing_prose_goes_to_the_last_declaration_of_the_block;
    case "a status tag retires its declaration"
      a_status_tag_retires_its_declaration;
    case "a status tag outside the block of the declaration is inert"
      a_status_tag_outside_the_block_of_the_declaration_is_inert;
    case "a status tag of another kind is inert"
      a_status_tag_of_another_kind_is_inert;
    case "the first status tag gives the status"
      the_first_status_tag_gives_the_status;
    case "a status tag applies to the declaration whose extent holds it"
      a_status_tag_applies_to_the_declaration_whose_extent_holds_it;
    case "a kind that needs approval is not approved"
      a_kind_that_needs_approval_is_not_approved;
    case "each kind needs approval alone" each_kind_needs_approval_alone;
    case "a rule or a bad slug gives no declaration"
      a_rule_or_a_bad_slug_gives_no_declaration;
    case "a citation takes its declaration as source"
      a_citation_takes_its_declaration_as_source;
    case "a citation outside every extent takes its section as a site"
      a_citation_outside_every_extent_takes_its_section_as_a_site;
    case "a site at level 0 has no name" a_site_at_level_0_has_no_name;
    case "a site without a first paragraph spans its extent"
      a_site_without_a_first_paragraph_spans_its_extent;
    case "sites of headings with one slug are numbered"
      sites_of_headings_with_one_slug_are_numbered;
    case "a target resolves across files" a_target_resolves_across_files;
    case "a target that differs only in case is dangling"
      a_target_that_differs_only_in_case_is_dangling;
    case "a malformed target is not dangling" a_malformed_target_is_not_dangling;
    case "an external id of a declared namespace resolves"
      an_external_id_of_a_declared_namespace_resolves;
    case "a resolved external id is not dangling"
      a_resolved_external_id_is_not_dangling;
    case "external ids come in the order of their ids"
      external_ids_come_in_the_order_of_their_ids;
    case "an external id that does not resolve gives no record"
      an_external_id_that_does_not_resolve_gives_no_record;
    case "a pin to another revision is suspect"
      a_pin_to_another_revision_is_suspect;
    case "a verifies edge in markdown has the wrong source"
      a_verifies_edge_in_markdown_has_the_wrong_source;
    case "an inline description loses its blanks"
      an_inline_description_loses_its_blanks;
    case "an effective supersedes edge retires its target"
      an_effective_supersedes_edge_retires_its_target;
    case "a source that is not approved retires nothing"
      a_source_that_is_not_approved_retires_nothing;
    case "a chain retires each declaration before its end"
      a_chain_retires_each_declaration_before_its_end;
    case "a status tag on the middle of a chain brings back the first"
      a_status_tag_on_the_middle_of_a_chain_brings_back_the_first;
    case "a middle that is not approved retires nothing"
      a_middle_that_is_not_approved_retires_nothing;
    case "two declarations that supersede one both retire it"
      two_declarations_that_supersede_one_both_retire_it;
    case "declarations of two files keep their own numbers"
      declarations_of_two_files_keep_their_own_numbers;
    case "a rule that supersedes retires its target"
      a_rule_that_supersedes_retires_its_target;
    case "every member of a supersedes cycle is in force"
      every_member_of_a_supersedes_cycle_is_in_force;
    case "a cycle counts its edges that are not effective"
      a_cycle_counts_its_edges_that_are_not_effective;
    case "a supersedes edge from a site is not effective"
      a_supersedes_edge_from_a_site_is_not_effective;
    case "an ack names the fact of its block" an_ack_names_the_fact_of_its_block;
    case "the hash of an ack follows its last blank"
      the_hash_of_an_ack_follows_its_last_blank;
    case "an ack with no fact or no hash gives no record"
      an_ack_with_no_fact_or_no_hash_gives_no_record;
    case "a plan file gives its plan, steps, and promises"
      a_plan_file_gives_its_plan_steps_and_promises;
    case "a declaration in the scope of the step meets its promise"
      a_declaration_in_the_scope_of_the_step_meets_its_promise;
    case "a declaration outside the scope is out of scope"
      a_declaration_outside_the_scope_is_out_of_scope;
    case "a declaration of another kind meets no promise"
      a_declaration_of_another_kind_meets_no_promise;
    case "the default location of the kind meets a promise"
      the_default_location_of_the_kind_meets_a_promise;
    case "an edge that resolves and is not suspect meets its promise"
      an_edge_that_resolves_and_is_not_suspect_meets_its_promise;
    case "a dangling edge meets no promise" a_dangling_edge_meets_no_promise;
    case "a verifies promise is never met in markdown"
      a_verifies_promise_is_never_met_in_markdown;
    case "a step with no promise is done when the diff changes its scope"
      a_step_with_no_promise_is_done_when_the_diff_changes_its_scope;
    case "an external id meets a promised citation"
      an_external_id_meets_a_promised_citation;
    case "only a verifies edge in the scope keeps a step from done"
      only_a_verifies_edge_in_the_scope_keeps_a_step_from_done;
    case "a verifies edge in the scope keeps a step from done"
      a_verifies_edge_in_the_scope_keeps_a_step_from_done;
    case "only a step with no promise needs the changes"
      only_a_step_with_no_promise_needs_the_changes;
    case "repeated promises of a step collapse"
      repeated_promises_of_a_step_collapse;
    case "a step holds the promises of its items and subsections"
      a_step_holds_the_promises_of_its_items_and_subsections;
    case "a level-2 section with no plan tag is no step"
      a_level_2_section_with_no_plan_tag_is_no_step;
    case "a plan at level 0 with no scope has no title"
      a_plan_at_level_0_with_no_scope_has_no_title;
    case "a scope line holds globs between commas"
      a_scope_line_holds_globs_between_commas;
    case "a glob with a bang narrows the scope of a step"
      a_glob_with_a_bang_narrows_the_scope_of_a_step;
    case "a plan that needs approval is not approved"
      a_plan_that_needs_approval_is_not_approved;
    case "tags in a plan file give no declaration and no edge"
      tags_in_a_plan_file_give_no_declaration_and_no_edge;
    case "a file whose first block has no plan tag is no plan"
      a_file_whose_first_block_has_no_plan_tag_is_no_plan;
    case "a plan tag outside .plans/ gives no plan"
      a_plan_tag_outside_plans_gives_no_plan;
    case "the index names the tree and the base"
      the_index_names_the_tree_and_the_base;
    case "the view gives each declaration in order"
      the_view_gives_each_declaration_in_order;
    case "is_in_force reads status and supersession"
      is_in_force_reads_status_and_supersession;
    case "successors follow a chain to its end"
      successors_follow_a_chain_to_its_end;
    case "successors stop where a status tag stops an edge"
      successors_stop_where_a_status_tag_stops_an_edge;
    case "a status tag alone gives no successors"
      a_status_tag_alone_gives_no_successors;
    case "successors come in the order of their ids"
      successors_come_in_the_order_of_their_ids;
    case "a successor that two paths reach comes once"
      a_successor_that_two_paths_reach_comes_once;
    case "of two successors with one id, the first record stays"
      of_two_successors_with_one_id_the_first_record_stays;
    case "a member of a cycle has no successors"
      a_member_of_a_cycle_has_no_successors;
    case "successors refuse an index out of range"
      successors_refuse_an_index_out_of_range;
    successors_end_in_force_and_only_effective_edges_retire;
    case "edges give what their targets resolve to"
      edges_give_what_their_targets_resolve_to;
    case "acks give their block" acks_give_their_block;
    case "plans give their steps and promises"
      plans_give_their_steps_and_promises;
    case "standing names the facts that meet and the one in scope"
      standing_names_the_facts_that_meet_and_the_one_in_scope;
    the_meeting_index_gives_the_list_scan;
    case "standing refuses a promise of other facts"
      standing_refuses_a_promise_of_other_facts;
    a_step_is_done_by_the_list_scan_of_the_verifies_edges;
    by_of_each_promise_is_the_first_meeting_fact_in_place;
    block_hash_is_the_hash_of_the_listed_document;
    block_acks_are_the_list_scan_of_the_acks;
    case "block hash reads the first of two files with one path"
      block_hash_reads_the_first_of_two_files_with_one_path;
    records_come_in_their_order;
    every_reference_names_a_record;
    every_record_is_canonical;
  ]
