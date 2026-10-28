(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

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
       namespaces.gh = \"[1-9][0-9]*\"\n"
  with
  | Ok manifest -> manifest
  | Error _ -> failwith "the manifest has errors"

let facts files =
  Facts.make manifest
    (List.map (fun (path, text) -> (path, document text)) files)

type table = {
  revisions : (string * int) list;
  spellings : (string * string) list;
  renames : (string * (string * int)) list;
  successors : (string * (string * int) list) list;
  words : (string * string) list;
}

let no_fix =
  { revisions = []; spellings = []; renames = []; successors = []; words = [] }

let fixes_of table =
  {
    Repair.revision = (fun target -> List.assoc_opt target table.revisions);
    spelling = (fun target -> List.assoc_opt target table.spellings);
    renamed = (fun target -> List.assoc_opt target table.renames);
    successors =
      (fun target ->
        Option.value (List.assoc_opt target table.successors) ~default:[]);
    word = (fun word -> List.assoc_opt word table.words);
  }

let tag ?(column = 1) ?target ?rev ?(desc = "") word =
  { Repair.column; word; target; rev; desc }

let repair ?(table = no_fix) removed added =
  Repair.is_repair (fixes_of table) ~removed ~added

let current = { no_fix with revisions = [ ("a", 2) ] }
let verdicts = Alcotest.(check (list (pair string bool)))

let a_hunk_with_no_line_is_no_repair () =
  Alcotest.(check bool) "no line" false (repair ~table:current [] [])

let ack_lines_are_each_one_edit () =
  let ack = tag "ack" ~target:"retired" ~desc:" 0123abcd" in
  verdicts "each hunk"
    [
      ("an added ack", true);
      ("a removed ack", true);
      ("a changed ack", true);
      ("a re-pin and an inserted ack", true);
      ("an ack and a line that is no edit", false);
    ]
    [
      ("an added ack", repair [] [ ack ]);
      ("a removed ack", repair [ ack ] []);
      ("a changed ack", repair [ ack ] [ { ack with desc = " 89abcdef" } ]);
      ( "a re-pin and an inserted ack",
        repair ~table:current
          [ tag "cites" ~target:"a" ~rev:1 ]
          [ tag "cites" ~target:"a" ~rev:2; ack ] );
      ( "an ack and a line that is no edit",
        repair ~table:current [] [ ack; tag "cites" ~target:"a" ~rev:2 ] );
    ]

let a_re_pin_writes_the_current_revision () =
  let cites rev = tag "cites" ~target:"a" ~rev in
  verdicts "each re-pin"
    [
      ("to the current revision", true);
      ("to another revision", false);
      ("to the same revision", false);
      ("of a target with no declaration", false);
      ("to no revision", false);
    ]
    [
      ("to the current revision", repair ~table:current [ cites 1 ] [ cites 2 ]);
      ("to another revision", repair ~table:current [ cites 1 ] [ cites 3 ]);
      ("to the same revision", repair ~table:current [ cites 2 ] [ cites 2 ]);
      ("of a target with no declaration", repair [ cites 1 ] [ cites 2 ]);
      ( "to no revision",
        repair ~table:current [ cites 1 ] [ tag "cites" ~target:"a" ] );
    ]

let an_added_revision_needs_a_word_that_unpinned_pins () =
  verdicts "each added revision"
    [
      ("satisfies", true);
      ("verifies", true);
      ("refines", true);
      ("supersedes", true);
      ("cites", false);
      ("satisfies, to another revision", false);
    ]
    (List.map
       (fun word ->
         ( word,
           repair ~table:current
             [ tag word ~target:"a" ]
             [ tag word ~target:"a" ~rev:2 ] ))
       [ "satisfies"; "verifies"; "refines"; "supersedes"; "cites" ]
    @ [
        ( "satisfies, to another revision",
          repair ~table:current
            [ tag "satisfies" ~target:"a" ]
            [ tag "satisfies" ~target:"a" ~rev:3 ] );
      ])

let a_bump_writes_any_higher_revision () =
  let req ?rev () = tag "req" ~target:"a" ?rev in
  verdicts "each bump"
    [
      ("v1 to v2", true);
      ("v1 to v5", true);
      ("no revision to v2", true);
      ("no revision to v1", false);
      ("v1 to no revision", false);
      ("v2 to v2", false);
      ("v3 to v2", false);
      ("design v1 to v2", true);
      ("decision v1 to v2", true);
      ("rule v1 to v2", false);
      ("a changed slug", false);
    ]
    [
      ("v1 to v2", repair [ req ~rev:1 () ] [ req ~rev:2 () ]);
      ("v1 to v5", repair [ req ~rev:1 () ] [ req ~rev:5 () ]);
      ("no revision to v2", repair [ req () ] [ req ~rev:2 () ]);
      ("no revision to v1", repair [ req () ] [ req ~rev:1 () ]);
      ("v1 to no revision", repair [ req ~rev:1 () ] [ req () ]);
      ("v2 to v2", repair [ req ~rev:2 () ] [ req ~rev:2 () ]);
      ("v3 to v2", repair [ req ~rev:3 () ] [ req ~rev:2 () ]);
      ( "design v1 to v2",
        repair
          [ tag "design" ~target:"a" ~rev:1 ]
          [ tag "design" ~target:"a" ~rev:2 ] );
      ( "decision v1 to v2",
        repair
          [ tag "decision" ~target:"a" ~rev:1 ]
          [ tag "decision" ~target:"a" ~rev:2 ] );
      ( "rule v1 to v2",
        repair
          [ tag "rule" ~target:"a" ~rev:1 ]
          [ tag "rule" ~target:"a" ~rev:2 ] );
      ( "a changed slug",
        repair [ req ~rev:1 () ] [ tag "req" ~target:"b" ~rev:2 ] );
    ]

let an_added_plan_id_is_any_id () =
  let plan ?rev target = tag "plan" ~target ?rev in
  verdicts "each change of a plan line"
    [
      ("an id added", true);
      ("another id added", true);
      ("an id changed", false);
      ("a slug changed", false);
      ("an id in upper case", false);
      ("an id removed", false);
      ("a revision changed", false);
      ("nothing changed", false);
      ("an id on a req", false);
      ("an id on an invalid slug", false);
    ]
    [
      ("an id added", repair [ plan "a" ] [ plan "a@3f2a9c" ]);
      ("another id added", repair [ plan "a" ] [ plan "a@012345" ]);
      ("an id changed", repair [ plan "a@3f2a9c" ] [ plan "a@012345" ]);
      ("a slug changed", repair [ plan "a" ] [ plan "b@3f2a9c" ]);
      ("an id in upper case", repair [ plan "a" ] [ plan "a@3F2A9C" ]);
      ("an id removed", repair [ plan "a@3f2a9c" ] [ plan "a" ]);
      ("a revision changed", repair [ plan ~rev:1 "a" ] [ plan "a@3f2a9c" ]);
      ("nothing changed", repair [ plan "a" ] [ plan "a" ]);
      ( "an id on a req",
        repair [ tag "req" ~target:"a" ] [ tag "req" ~target:"a@3f2a9c" ] );
      ("an id on an invalid slug", repair [ plan "-a" ] [ plan "-a@3f2a9c" ]);
    ]

let a_retarget_names_what_its_fix_names () =
  let table =
    {
      no_fix with
      spellings = [ ("lock", "Lock") ];
      renames = [ ("old", ("new", 3)) ];
      successors = [ ("gone", [ ("next", 2); ("other", 4) ]) ];
    }
  in
  let check name word (old_target, old_rev) (target, rev) =
    ( name,
      repair ~table
        [ tag word ~target:old_target ?rev:old_rev ]
        [ tag word ~target ?rev ] )
  in
  verdicts "each retarget"
    [
      ("the declared spelling", true);
      ("the declared spelling with a new revision", false);
      ("another spelling", false);
      ("the renamed declaration with its revision", true);
      ("the renamed declaration with no revision", true);
      ("the renamed declaration with the old revision", false);
      ("the renamed declaration with a revision added", false);
      ("another declaration than the renamed one", false);
      ("the first successor", true);
      ("the second successor", true);
      ("a successor with no revision", true);
      ("a successor with the old revision", false);
      ("a successor in a satisfies", false);
      ("no successor", false);
    ]
    [
      check "the declared spelling" "cites" ("lock", Some 1) ("Lock", Some 1);
      check "the declared spelling with a new revision" "cites" ("lock", Some 1)
        ("Lock", Some 2);
      check "another spelling" "cites" ("lock", Some 1) ("LOCK", Some 1);
      check "the renamed declaration with its revision" "satisfies"
        ("old", Some 1) ("new", Some 3);
      check "the renamed declaration with no revision" "cites" ("old", None)
        ("new", None);
      check "the renamed declaration with the old revision" "satisfies"
        ("old", Some 1) ("new", Some 1);
      check "the renamed declaration with a revision added" "cites"
        ("old", None) ("new", Some 3);
      check "another declaration than the renamed one" "satisfies"
        ("old", Some 1) ("next", Some 3);
      check "the first successor" "cites" ("gone", Some 1) ("next", Some 2);
      check "the second successor" "cites" ("gone", Some 1) ("other", Some 4);
      check "a successor with no revision" "cites" ("gone", None) ("next", None);
      check "a successor with the old revision" "cites" ("gone", Some 1)
        ("next", Some 1);
      check "a successor in a satisfies" "satisfies" ("gone", Some 1)
        ("next", Some 2);
      check "no successor" "cites" ("lock", Some 1) ("next", Some 2);
    ]

let a_corrected_word_is_the_word_of_the_fix () =
  let table = { no_fix with words = [ ("reqq", "req"); ("citse", "cites") ] } in
  verdicts "each corrected word"
    [
      ("the word of the fix", true);
      ("the word of the fix, with no target", true);
      ("another word", false);
      ("the word of the fix and a new target", false);
      ("the word of the fix and a new revision", false);
    ]
    [
      ( "the word of the fix",
        repair ~table
          [ tag "reqq" ~target:"a" ~rev:1 ]
          [ tag "req" ~target:"a" ~rev:1 ] );
      ( "the word of the fix, with no target",
        repair ~table [ tag "citse" ] [ tag "cites" ] );
      ( "another word",
        repair ~table
          [ tag "reqq" ~target:"a" ~rev:1 ]
          [ tag "design" ~target:"a" ~rev:1 ] );
      ( "the word of the fix and a new target",
        repair ~table
          [ tag "reqq" ~target:"a" ~rev:1 ]
          [ tag "req" ~target:"b" ~rev:1 ] );
      ( "the word of the fix and a new revision",
        repair ~table
          [ tag "reqq" ~target:"a" ~rev:1 ]
          [ tag "req" ~target:"a" ~rev:2 ] );
    ]

let a_pair_keeps_its_column_and_its_description () =
  let old = tag "cites" ~target:"a" ~rev:1 ~desc:" Text." ~column:3 in
  let fixed = { old with rev = Some 2 } in
  verdicts "each pair"
    [
      ("the same column and description", true);
      ("a moved @", false);
      ("another description", false);
      ("other spaces before the description", false);
    ]
    [
      ( "the same column and description",
        repair ~table:current [ old ] [ fixed ] );
      ("a moved @", repair ~table:current [ old ] [ { fixed with column = 1 } ]);
      ( "another description",
        repair ~table:current [ old ] [ { fixed with desc = " Other." } ] );
      ( "other spaces before the description",
        repair ~table:current [ old ] [ { fixed with desc = "  Text." } ] );
    ]

let every_pair_must_be_an_edit () =
  let pin = (tag "cites" ~target:"a" ~rev:1, tag "cites" ~target:"a" ~rev:2) in
  let stray =
    (tag "cites" ~target:"b" ~rev:1, tag "cites" ~target:"b" ~rev:2)
  in
  verdicts "each hunk"
    [
      ("two re-pins", true);
      ("a re-pin and a change that is no edit", false);
      ("a removed line with no added line", false);
      ("an added line with no removed line", false);
    ]
    [
      ( "two re-pins",
        repair ~table:current [ fst pin; fst pin ] [ snd pin; snd pin ] );
      ( "a re-pin and a change that is no edit",
        repair ~table:current [ fst pin; fst stray ] [ snd pin; snd stray ] );
      ("a removed line with no added line", repair ~table:current [ fst pin ] []);
      ( "an added line with no removed line",
        repair ~table:current [] [ snd pin ] );
    ]

let tags_gives_the_tags_of_a_range_of_tag_lines () =
  let text =
    "# A\n\n\
     @req a v1 Text.\n\
    \  @cites b v2\n\
     - @cites c\n\n\
     Prose.\n\n\
     @cites d v1\n"
  in
  let doc = document text in
  let shown range =
    Option.map
      (List.map (fun (t : Repair.tag) ->
           Printf.sprintf "%d %s %s %s %S" t.column t.word
             (Option.value t.target ~default:"-")
             (Option.fold ~none:"-" ~some:string_of_int t.rev)
             t.desc))
      range
  in
  Alcotest.(check (list (option (list string))))
    "the tags of each range"
    [
      Some [ "1 req a 1 \" Text.\""; "3 cites b 2 \"\"" ];
      Some [ "3 cites c - \"\"" ];
      Some [];
      Some [];
      None;
      None;
      None;
      None;
    ]
    (List.map shown
       [
         Repair.tags doc ~first:3 ~count:2;
         Repair.tags doc ~first:5 ~count:1;
         Repair.tags doc ~first:1 ~count:0;
         Repair.tags doc ~first:40 ~count:0;
         Repair.tags doc ~first:2 ~count:2;
         Repair.tags doc ~first:5 ~count:2;
         Repair.tags doc ~first:9 ~count:1;
         Repair.tags doc ~first:10 ~count:1;
       ])

let hunk ?(old_line = 1) ?(removed = 0) ?(line = 1) ?(added = 0) () =
  {
    Git.line;
    eline = (if added = 0 then line else line + added - 1);
    ecol = 1;
    old_line;
    added;
    removed;
  }

let hunk_reads_the_removed_lines_at_the_base_and_the_added_lines_now () =
  let base = document "# A\n\n- [ ] @cites a v1\n@ack retired 0123abcd\n"
  and tree = document "# A\n\n- [x] @cites a v1\n- [x] @cites a v2\n" in
  let fixes = fixes_of current in
  verdicts "each hunk"
    [
      ("a re-pin", true);
      ("a change of the task marker alone", false);
      ("a deleted file of an ack", true);
      ("an added file of an ack", true);
      ("a removed line of a file with no document", false);
      ("an added line of a file with no document", false);
      ("a hunk with no line", false);
      ("a removed line that is no tag line", false);
    ]
    [
      ( "a re-pin",
        Repair.hunk fixes ~base:(Some base) (Some tree)
          (hunk ~old_line:3 ~removed:1 ~line:4 ~added:1 ()) );
      ( "a change of the task marker alone",
        Repair.hunk fixes ~base:(Some base) (Some tree)
          (hunk ~old_line:3 ~removed:1 ~line:3 ~added:1 ()) );
      ( "a deleted file of an ack",
        Repair.hunk fixes ~base:(Some base) None
          (hunk ~old_line:4 ~removed:1 ()) );
      ( "an added file of an ack",
        Repair.hunk fixes ~base:None (Some base) (hunk ~line:4 ~added:1 ()) );
      ( "a removed line of a file with no document",
        Repair.hunk fixes ~base:None (Some tree)
          (hunk ~old_line:3 ~removed:1 ~line:4 ~added:1 ()) );
      ( "an added line of a file with no document",
        Repair.hunk fixes ~base:(Some base) None
          (hunk ~old_line:3 ~removed:1 ~line:4 ~added:1 ()) );
      ("a hunk with no line", Repair.hunk fixes ~base:None None (hunk ()));
      ( "a removed line that is no tag line",
        Repair.hunk fixes ~base:(Some base) (Some tree)
          (hunk ~old_line:2 ~removed:2 ~line:3 ~added:2 ()) );
    ]

let fixes_reads_what_each_fix_writes () =
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
        ( "docs/more.md",
          "# More\n\n\
           @req Cache-Ttl v4\n\n\
           ## Old\n\n\
           @decision old v2\n\
           @deprecated\n\n\
           ## Was\n\n\
           @decision was v1\n\n\
           ## Now\n\n\
           @decision now v3\n\
           @supersedes was v1\n\n\
           ## Also\n\n\
           @decision also v1\n\
           @supersedes was v1\n" );
        ("docs/use.md", "# Use\n\n@cites lockout v1\n");
      ]
  in
  let fixes = Repair.fixes ~base tree in
  let pair = Option.map (fun (slug, rev) -> Printf.sprintf "%s v%d" slug rev) in
  Alcotest.(check (list (option string)))
    "what each fix writes"
    [
      Some "4";
      None;
      None;
      Some "Cache-Ttl";
      None;
      Some "account-lockout v2";
      None;
      Some "also v1, now v3";
      Some "";
      Some "";
      Some "cites";
      None;
    ]
    [
      Option.map string_of_int (fixes.revision "Cache-Ttl");
      Option.map string_of_int (fixes.revision "gone");
      Option.map string_of_int (fixes.revision "gh/2");
      fixes.spelling "cache-ttl";
      fixes.spelling "Cache-Ttl";
      pair (fixes.renamed "lockout");
      pair (fixes.renamed "account-lockout");
      Some
        (String.concat ", "
           (List.map
              (fun (slug, rev) -> Printf.sprintf "%s v%d" slug rev)
              (fixes.successors "was")));
      Some (String.concat ", " (List.map fst (fixes.successors "old")));
      Some (String.concat ", " (List.map fst (fixes.successors "gone")));
      fixes.word "citse";
      fixes.word "cites";
    ]

let word_gen =
  Gen.oneof_list
    [
      "cites";
      "satisfies";
      "verifies";
      "refines";
      "supersedes";
      "req";
      "design";
      "decision";
      "rule";
      "plan";
      "reqq";
      "citse";
      "";
    ]

let target_gen = Gen.oneof_list [ "a"; "A"; "b"; "c" ]
let rev_gen = Gen.int_range 1 4
let desc_gen = Gen.oneof_list [ ""; " Text."; "  Text."; " Other." ]

let tag_gen =
  Gen.(
    let* column = int_range 1 3 in
    let* word = word_gen in
    let* target = option target_gen in
    let* rev = option rev_gen in
    let+ desc = desc_gen in
    { Repair.column; word; target; rev; desc })

let table_gen =
  Gen.(
    let small value = list_size (int_bound 3) (pair target_gen value) in
    let* revisions = small rev_gen in
    let* spellings = small target_gen in
    let* renames = small (pair target_gen rev_gen) in
    let* successors =
      small (list_size (int_bound 2) (pair target_gen rev_gen))
    in
    let+ words = list_size (int_bound 3) (pair word_gen word_gen) in
    { revisions; spellings; renames; successors; words })

let print_tag (t : Repair.tag) =
  Printf.sprintf "{%d @%s %s %s %S}" t.column t.word
    (Option.value t.target ~default:"-")
    (Option.fold ~none:"-" ~some:string_of_int t.rev)
    t.desc

let print_table table =
  let pairs show list =
    String.concat "; "
      (List.map (fun (key, value) -> key ^ "=" ^ show value) list)
  in
  let rev (slug, rev) = Printf.sprintf "%s v%d" slug rev in
  Printf.sprintf
    "revisions: %s | spellings: %s | renames: %s | successors: %s | words: %s"
    (pairs string_of_int table.revisions)
    (pairs Fun.id table.spellings)
    (pairs rev table.renames)
    (pairs (fun list -> String.concat "," (List.map rev list)) table.successors)
    (pairs Fun.id table.words)

let print_pairs = QCheck2.Print.(list (pair print_tag print_tag))

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let is_ack (t : Repair.tag) = String.equal t.word "ack"

let equal_tags_are_no_repair =
  property ~name:"a pair of equal tags is no repair"
    ~print:QCheck2.Print.(pair print_table print_tag)
    Gen.(pair table_gen tag_gen)
    (fun (table, t) -> is_ack t || not (repair ~table [ t ] [ t ]))

let a_pair_with_another_column_or_description_is_no_repair =
  property ~name:"a pair with another column or description is no repair"
    ~print:QCheck2.Print.(triple print_table print_tag print_tag)
    Gen.(triple table_gen tag_gen tag_gen)
    (fun (table, o, n) ->
      is_ack o || is_ack n
      || (o.column = n.column && String.equal o.desc n.desc)
      || not (repair ~table [ o ] [ n ]))

let pairs_gen = Gen.(list_size (int_range 1 3) (pair tag_gen tag_gen))

let a_hunk_is_a_repair_when_each_pair_is =
  property ~name:"a hunk is a repair when each of its pairs is one"
    ~print:QCheck2.Print.(pair print_table print_pairs)
    Gen.(pair table_gen pairs_gen)
    (fun (table, pairs) ->
      let pairs =
        List.filter (fun (o, n) -> not (is_ack o || is_ack n)) pairs
      in
      pairs = []
      || repair ~table (List.map fst pairs) (List.map snd pairs)
         = List.for_all (fun (o, n) -> repair ~table [ o ] [ n ]) pairs)

let insert gen kept =
  Gen.(
    let* inserted = list_size (int_bound 2) gen in
    let+ keys =
      list_size (pure (List.length kept + List.length inserted)) nat
    in
    List.map snd
      (List.stable_sort
         (fun (a, _) (b, _) -> Int.compare a b)
         (List.combine keys (kept @ inserted))))

let ack_gen =
  Gen.map2
    (fun column target -> tag "ack" ~column ~target ~desc:" 0123abcd")
    (Gen.int_range 1 3) target_gen

let ack_lines_do_not_change_the_verdict =
  property ~name:"ack lines in a hunk with other lines leave the verdict"
    ~print:
      QCheck2.Print.(
        triple print_table print_pairs (pair (list print_tag) (list print_tag)))
    Gen.(
      let* table = table_gen in
      let* pairs = pairs_gen in
      let pairs =
        List.filter (fun (o, n) -> not (is_ack o || is_ack n)) pairs
      in
      let* removed = insert ack_gen (List.map fst pairs) in
      let+ added = insert ack_gen (List.map snd pairs) in
      (table, pairs, (removed, added)))
    (fun (table, pairs, (removed, added)) ->
      pairs = []
      || repair ~table removed added
         = repair ~table (List.map fst pairs) (List.map snd pairs))

let only_ack_lines_are_a_repair =
  property ~name:"a hunk of ack lines alone is a repair"
    ~print:QCheck2.Print.(pair (list print_tag) (list print_tag))
    Gen.(
      pair (list_size (int_bound 3) ack_gen) (list_size (int_bound 3) ack_gen))
    (fun (removed, added) ->
      (removed = [] && added = []) || repair removed added)

let other_lines_of_unequal_number_are_no_repair =
  property ~name:"other lines of unequal number are no repair"
    ~print:QCheck2.Print.(triple print_table (list print_tag) (list print_tag))
    Gen.(
      triple table_gen
        (list_size (int_bound 3) tag_gen)
        (list_size (int_bound 3) tag_gen))
    (fun (table, removed, added) ->
      List.length (List.filter (fun t -> not (is_ack t)) removed)
      = List.length (List.filter (fun t -> not (is_ack t)) added)
      || not (repair ~table removed added))

type edit = {
  name : string;
  table : table;
  old_tag : Repair.tag;
  new_tag : Repair.tag;
}

let citation =
  Gen.oneof_list [ "cites"; "satisfies"; "verifies"; "refines"; "supersedes" ]

let edit_gen =
  Gen.(
    let* column = int_range 1 3 in
    let* desc = desc_gen in
    let* a = target_gen in
    let* b = target_gen in
    let b = if String.equal a b then a ^ "x" else b in
    let* old_rev = rev_gen in
    let* rev = rev_gen in
    let rev = if rev = old_rev then rev + 1 else rev in
    let* pinned = bool in
    let make word target rev =
      { Repair.column; word; target = Some target; rev; desc }
    in
    let kept = if pinned then Some old_rev else None in
    let written = Option.map (fun _ -> rev) kept in
    let* word = citation in
    let* kind = int_bound 7 in
    match kind with
    | 0 ->
        pure
          {
            name = "re-pin";
            table = { no_fix with revisions = [ (a, rev) ] };
            old_tag = make word a (Some old_rev);
            new_tag = make word a (Some rev);
          }
    | 1 ->
        let+ word =
          oneof_list [ "satisfies"; "verifies"; "refines"; "supersedes" ]
        in
        {
          name = "added revision";
          table = { no_fix with revisions = [ (a, rev) ] };
          old_tag = make word a None;
          new_tag = make word a (Some rev);
        }
    | 2 ->
        let+ word = oneof_list [ "req"; "design"; "decision" ] in
        let low = min old_rev rev and high = max old_rev rev in
        {
          name = "bump";
          table = no_fix;
          old_tag =
            make word a (if low = 1 && not pinned then None else Some low);
          new_tag = make word a (Some high);
        }
    | 3 ->
        pure
          {
            name = "case fix";
            table = { no_fix with spellings = [ (a, b) ] };
            old_tag = make word a kept;
            new_tag = make word b kept;
          }
    | 4 ->
        pure
          {
            name = "renamed";
            table = { no_fix with renames = [ (a, (b, rev)) ] };
            old_tag = make word a kept;
            new_tag = make word b written;
          }
    | 5 ->
        let+ first = bool in
        let others = [ (b ^ "y", rev + 1) ] in
        {
          name = "retired";
          table =
            {
              no_fix with
              successors =
                [
                  ( a,
                    if first then (b, rev) :: others else others @ [ (b, rev) ]
                  );
                ];
            };
          old_tag = make "cites" a kept;
          new_tag = make "cites" b written;
        }
    | 6 ->
        let+ target = option target_gen in
        {
          name = "corrected word";
          table = { no_fix with words = [ ("reqq", "req") ] };
          old_tag = { Repair.column; word = "reqq"; target; rev = kept; desc };
          new_tag = { Repair.column; word = "req"; target; rev = kept; desc };
        }
    | _ ->
        let+ id = map (Printf.sprintf "%06x") (int_bound 0xffffff) in
        {
          name = "added plan id";
          table = no_fix;
          old_tag = make "plan" a kept;
          new_tag = make "plan" (a ^ "@" ^ id) kept;
        })

let print_edit edit =
  Printf.sprintf "%s: %s -> %s, %s" edit.name (print_tag edit.old_tag)
    (print_tag edit.new_tag) (print_table edit.table)

let the_tag_of_each_fix_is_a_repair =
  property ~name:"the tag that each fix writes is a repair" ~print:print_edit
    edit_gen (fun edit ->
      repair ~table:edit.table [ edit.old_tag ] [ edit.new_tag ])

let another_revision_than_the_fix_writes_is_no_repair =
  property ~name:"another revision than the fix writes is no repair"
    ~print:print_edit edit_gen (fun edit ->
      String.equal edit.name "bump"
      ||
      let rev =
        match edit.new_tag.rev with
        | Some rev -> Some (rev + 1)
        | None -> Some 1
      in
      not
        (repair ~table:edit.table [ edit.old_tag ]
           [ { edit.new_tag with rev } ]))

let a_bump_needs_a_higher_revision =
  property ~name:"a bump needs a higher revision"
    ~print:QCheck2.Print.(triple string (option int) (option int))
    Gen.(
      triple
        (oneof_list [ "req"; "design"; "decision" ])
        (option rev_gen) (option rev_gen))
    (fun (word, old_rev, rev) ->
      repair [ tag word ~target:"a" ?rev:old_rev ] [ tag word ~target:"a" ?rev ]
      = (Option.value rev ~default:1 > Option.value old_rev ~default:1))

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "a hunk with no line is no repair" a_hunk_with_no_line_is_no_repair;
    case "ack lines are each one edit" ack_lines_are_each_one_edit;
    case "a re-pin writes the current revision"
      a_re_pin_writes_the_current_revision;
    case "an added revision needs a word that unpinned pins"
      an_added_revision_needs_a_word_that_unpinned_pins;
    case "a bump writes any higher revision" a_bump_writes_any_higher_revision;
    case "an added plan id is any id" an_added_plan_id_is_any_id;
    case "a retarget names what its fix names"
      a_retarget_names_what_its_fix_names;
    case "a corrected word is the word of the fix"
      a_corrected_word_is_the_word_of_the_fix;
    case "a pair keeps its column and its description"
      a_pair_keeps_its_column_and_its_description;
    case "every pair must be an edit" every_pair_must_be_an_edit;
    case "tags gives the tags of a range of tag lines"
      tags_gives_the_tags_of_a_range_of_tag_lines;
    case "hunk reads the removed lines at the base and the added lines now"
      hunk_reads_the_removed_lines_at_the_base_and_the_added_lines_now;
    case "fixes reads what each fix writes" fixes_reads_what_each_fix_writes;
    equal_tags_are_no_repair;
    a_pair_with_another_column_or_description_is_no_repair;
    a_hunk_is_a_repair_when_each_pair_is;
    ack_lines_do_not_change_the_verdict;
    only_ack_lines_are_a_repair;
    other_lines_of_unequal_number_are_no_repair;
    the_tag_of_each_fix_is_a_repair;
    another_revision_than_the_fix_writes_is_no_repair;
    a_bump_needs_a_higher_revision;
  ]
