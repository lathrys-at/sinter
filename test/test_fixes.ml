(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 100) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

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
    (List.map (fun (path, text) -> (path, Edits.document text)) files)

let findings ~base files =
  let tree = facts files in
  Adjudicator.classes ~base:(facts base) tree
    (Findings.of_facts tree ~base:"0123456789abcdef0123456789abcdef01234567"
       ~not_text:[])

let decisions =
  "# Decisions\n\n\
   ## Login\n\n\
   @req login v2\n\
   Login.\n\n\
   ## Old\n\n\
   @decision old v1\n\
   Old.\n\n\
   ## New\n\n\
   @decision new v3\n\
   @supersedes old v1\n\
   New.\n\n\
   ## Other\n\n\
   @decision other v1\n\
   @supersedes old v1\n\
   Other.\n\n\
   ## Gone\n\n\
   @decision gone v2\n\
   Gone.\n\n\
   ## Next\n\n\
   @decision next v2\n\
   @supersedes gone v2\n\
   Next.\n\n\
   ## Dep\n\n\
   @decision dep v2\n\
   @deprecated\n\
   Dep.\n"

let base =
  [
    ("docs/decisions.md", decisions);
    ("docs/moved.md", "# Moved\n\n@req moved v1 Move it.\n");
    ( "docs/edited.md",
      "# Edited\n\n@req edited v2\nOld.\n\n## Plain\n\n@design plain\nOld.\n" );
  ]

let tree guide =
  [
    ("docs/decisions.md", decisions);
    ("docs/moved.md", "# Moved\n\n@req moved-new v1 Move it.\n");
    ( "docs/edited.md",
      "# Edited\n\n@req edited v2\nNew.\n\n## Plain\n\n@design plain\nNew.\n" );
    ("docs/guide.md", guide);
    (".plans/p.md", "# P\n\n@plan p\n");
  ]

type line = {
  word : string;
  target : string;
  gap : string;
  rev : int option;
  desc : string;
}

let line =
  Gen.(
    map
      (fun (word, target, gap, (rev, desc)) -> { word; target; gap; rev; desc })
      (quad
         (oneof_list
            [ "cites"; "satisfies"; "cites"; "cite"; "satisfie"; "reqq" ])
         (oneof_list
            [
              "login"; "Login"; "old"; "gone"; "dep"; "moved"; "next"; "nowhere";
            ])
         (oneof_list [ " "; "\t"; " \t " ])
         (pair
            (oneof_list [ None; Some 1; Some 2; Some 3; Some 9 ])
            (oneof_list [ ""; " Why."; " caf\xc3\xa9"; "  " ]))))

let render_line line =
  Printf.sprintf "@%s %s%s%s" line.word line.target
    (match line.rev with
    | Some rev -> Printf.sprintf "%sv%d" line.gap rev
    | None -> "")
    line.desc

let first_seen lines =
  List.rev
    (List.fold_left
       (fun kept line ->
         if
           List.exists
             (fun other ->
               String.equal other.word line.word
               && String.equal other.target line.target)
             kept
         then kept
         else line :: kept)
       [] lines)

type block = { marker : string; indent : string; lines : line list }

let block =
  Gen.(
    map2
      (fun (marker, indent) lines ->
        { marker; indent; lines = first_seen lines })
      (oneof_list
         [ ("", ""); ("- ", "  "); ("- [ ] ", "      "); ("10. ", "    ") ])
      (list_size (int_range 1 3) line))

let render_guide ending final blocks =
  String.concat ending
    ("# Guide"
    :: List.concat
         (List.mapi
            (fun index block ->
              ""
              :: Printf.sprintf "## G%d" index
              :: ""
              :: List.mapi
                   (fun position line ->
                     (if position = 0 then block.marker else block.indent)
                     ^ render_line line)
                   block.lines)
            blocks))
  ^ if final then ending else ""

let guide =
  Gen.(
    map3 render_guide
      (oneof_list [ "\n"; "\r\n" ])
      bool
      (list_size (int_range 1 4) block))

type change = {
  finding : Finding.t;
  path : string;
  before : string;
  after : string;
  edits : Fix.edit list;
}

let changes ~base files =
  List.concat_map
    (fun (finding : Finding.t) ->
      match (finding.fix, finding.place) with
      | Some fix, Some place ->
          let before = List.assoc place.path files in
          List.map
            (fun edits ->
              {
                finding;
                path = place.path;
                before;
                after = Edits.apply before edits;
                edits;
              })
            (Fix.alternatives fix)
      | _ -> [])
    (findings ~base files)

let edited files change =
  List.map
    (fun (path, text) ->
      (path, if String.equal path change.path then change.after else text))
    files

let repairs ~base files change =
  not
    (List.exists
       (fun finding ->
         String.equal (Finding.id finding) (Finding.id change.finding))
       (findings ~base (edited files change)))

let hunk before after =
  let old = Array.of_list (String.split_on_char '\n' before)
  and fresh = Array.of_list (String.split_on_char '\n' after) in
  let shorter = min (Array.length old) (Array.length fresh) in
  let rec prefix count =
    if count < shorter && String.equal old.(count) fresh.(count) then
      prefix (count + 1)
    else count
  in
  let prefix = prefix 0 in
  let rec suffix count =
    if
      count < shorter - prefix
      && String.equal
           old.(Array.length old - 1 - count)
           fresh.(Array.length fresh - 1 - count)
    then suffix (count + 1)
    else count
  in
  let suffix = suffix 0 in
  let added = Array.length fresh - prefix - suffix in
  {
    Git.line = prefix + 1;
    eline = prefix + max added 1;
    ecol = 1;
    old_line = prefix + 1;
    added;
    removed = Array.length old - prefix - suffix;
  }

let is_mechanical ~base files change =
  Repair.hunk
    (Repair.fixes ~base:(facts base) (facts (edited files change)))
    ~base:(Some (Edits.document change.before))
    (Some (Edits.document change.after))
    (hunk change.before change.after)

let lines text = String.split_on_char '\n' text

let tag_at (document : Markdown.t) line =
  List.find
    (fun (tag : Markdown.tag) -> tag.span.start.line = line)
    (Array.to_list document.tags)

let touches_only_its_place change =
  let line =
    match change.finding.place with
    | Some place -> place.span.start.line
    | None -> Alcotest.fail "a fix with no place"
  in
  let old = Edits.document change.before
  and fresh = Edits.document change.after in
  let before = lines change.before and after = lines change.after in
  let same_tag_line =
    let o = tag_at old line and n = tag_at fresh line in
    o.span.start.column = n.span.start.column && String.equal o.desc n.desc
  in
  match change.finding.ackable with
  | true ->
      let edge = tag_at old line in
      let last =
        List.fold_left
          (fun _ index -> old.tags.(index).span.start.line)
          line old.blocks.(edge.block).tags
      in
      let ack = tag_at fresh (last + 1) in
      List.length after = List.length before + 1
      && List.filteri (fun index _ -> index <> last) after = before
      && String.equal ack.word "ack"
      && ack.block = edge.block
      && ack.span.start.column = (tag_at old last).span.start.column
      && same_tag_line
  | false ->
      List.length after = List.length before
      && List.for_all Fun.id
           (List.mapi
              (fun index (o, n) -> index = line - 1 || String.equal o n)
              (List.combine before after))
      && same_tag_line
      && List.for_all
           (fun (edit : Fix.edit) -> edit.line = line && edit.eline = line)
           change.edits

let the_edits_repair_the_finding =
  property ~name:"the edits of each alternative remove the finding"
    ~print:String.escaped guide (fun guide ->
      let files = tree guide in
      List.for_all (repairs ~base files) (changes ~base files))

let the_edits_are_a_mechanical_repair =
  property ~name:"the edits of each alternative make a mechanical repair"
    ~print:String.escaped guide (fun guide ->
      let files = tree guide in
      List.for_all (is_mechanical ~base files) (changes ~base files))

let the_edits_touch_only_their_place =
  property ~name:"the edits change only the tag line or add one line after it"
    ~print:String.escaped guide (fun guide ->
      List.for_all touches_only_its_place (changes ~base (tree guide)))

let probe_guide =
  "# Guide\n\n\
   ## Typo\n\n\
   @reqq a v1\n\
   @satisfie login v2 Why.\n\n\
   ## Typo item\n\n\
   - text\n\
  \  @cite login\n\n\
   ## Pins\n\n\
   @satisfies login Why.\n\
   @refines login\tcaf\xc3\xa9\n\
   @cites login v1 Why.\n\
   @verifies login \t v9\n\n\
   ## Spell\n\n\
   @cites Login v2\n\
   @satisfies Login\n\n\
   ## Retired\n\n\
   @cites old v1\n\
   @satisfies new v3\n\
   @cites gone \t v1 Why.\n\n\
   ## Retired bare\n\n\
   @cites old\n\
   @cites gone\n\n\
   ## Ack paragraph\n\n\
   @cites dep v2 Why.\n\
   @cites login v2\n\n\
   ## Ack item\n\n\
   - @cites dep\n\n\
   ## Ack task\n\n\
   - [ ] @cites dep v1\n\
  \      @cites login v2\n\n\
   ## Ack number\n\n\
   10. @cites dep\n\n\
   ## Ack tab\n\n\
   - a\n\n\
   \t- @cites dep\n\n\
   ## Ack later\n\n\
   - @cites login v2\n\
  \  @cites dep Why.\n\n\
   ## Moved\n\n\
   @cites moved v1\n\
   @satisfies moved\n\
   @refines moved v2 Why.\n"

let probe =
  [
    ("docs/decisions.md", decisions);
    ("docs/moved.md", "# Moved\n\n@req moved-new v1 Move it.\n");
    ( "docs/edited.md",
      "# Edited\n\n@req edited v2\nNew.\n\n## Plain\n\n@design plain\nNew.\n" );
    ("docs/guide.md", probe_guide);
    ( "docs/crlf.md",
      "# Crlf\r\n\
       \r\n\
       - @cites dep\r\n\
      \  @cites old v1\r\n\
       \r\n\
       ## Last\r\n\
       \r\n\
       @cites dep v2  \r\n" );
    ("docs/end.md", "# End\n\n@cites login v2\n@cites dep caf\xc3\xa9");
    ("docs/bom.md", "\xef\xbb\xbf@cites dep\n@cites Login\n");
    (".plans/p.md", "# P\n\n- @plan p Why.\n");
  ]

let fix_lines_of_170c04b =
  [
    ( "docs/bom.md:1:1: retired cites:site:docs/bom.md->dep decision:dep is \
       deprecated",
      "  fix: @ack retired dep 8d5cd79d" );
    ( "docs/bom.md:2:1: dangling cites:site:docs/bom.md->Login no declaration \
       has the slug Login",
      "  fix: @cites login" );
    ( "docs/crlf.md:3:3: retired cites:site:docs/crlf.md#crlf->dep \
       decision:dep is deprecated",
      "  fix: @ack retired dep a7b16d5b" );
    ( "docs/crlf.md:4:3: retired cites:site:docs/crlf.md#crlf->old \
       decision:old is superseded by decision:new, decision:other",
      "  fix: @cites new v3 or @cites other v1" );
    ( "docs/crlf.md:8:1: retired cites:site:docs/crlf.md#last->dep \
       decision:dep is deprecated",
      "  fix: @ack retired dep 485ef95f" );
    ( "docs/edited.md:3:1: unbumped req:edited the extent differs from the \
       base, and the revision is not above v2",
      "  fix: @req edited v3" );
    ( "docs/edited.md:8:1: unbumped design:plain the extent differs from the \
       base, and the revision is not above v1",
      "  fix: @design plain v2" );
    ( "docs/end.md:4:1: retired cites:site:docs/end.md#end->dep decision:dep \
       is deprecated",
      "  fix: @ack retired dep 02a3ba13" );
    ( "docs/guide.md:5:1: typo-tag line:docs/guide.md@L5 @reqq is not a tag \
       word of sinter",
      "  fix: @req" );
    ( "docs/guide.md:6:1: typo-tag line:docs/guide.md@L6 @satisfie is not a \
       tag word of sinter",
      "  fix: @satisfies" );
    ( "docs/guide.md:11:3: typo-tag line:docs/guide.md@L11 @cite is not a tag \
       word of sinter",
      "  fix: @cites" );
    ( "docs/guide.md:15:1: unpinned satisfies:site:docs/guide.md#pins->login \
       the @satisfies names no revision",
      "  fix: @satisfies login v2" );
    ( "docs/guide.md:16:1: unpinned refines:site:docs/guide.md#pins->login the \
       @refines names no revision",
      "  fix: @refines login v2" );
    ( "docs/guide.md:17:1: suspect cites:site:docs/guide.md#pins->login the \
       @cites names v1, and req:login is at v2",
      "  fix: @cites login v2" );
    ( "docs/guide.md:18:1: suspect verifies:site:docs/guide.md#pins->login the \
       @verifies names v9, and req:login is at v2",
      "  fix: @verifies login v2" );
    ( "docs/guide.md:22:1: dangling cites:site:docs/guide.md#spell->Login no \
       declaration has the slug Login",
      "  fix: @cites login v2" );
    ( "docs/guide.md:23:1: dangling satisfies:site:docs/guide.md#spell->Login \
       no declaration has the slug Login",
      "  fix: @satisfies login" );
    ( "docs/guide.md:27:1: retired cites:site:docs/guide.md#retired->old \
       decision:old is superseded by decision:new, decision:other",
      "  fix: @cites new v3 or @cites other v1" );
    ( "docs/guide.md:29:1: retired cites:site:docs/guide.md#retired->gone \
       decision:gone is superseded by decision:next",
      "  fix: @cites next v2" );
    ( "docs/guide.md:29:1: suspect cites:site:docs/guide.md#retired->gone the \
       @cites names v1, and decision:gone is at v2",
      "  fix: @cites gone v2" );
    ( "docs/guide.md:33:1: retired cites:site:docs/guide.md#retired-bare->old \
       decision:old is superseded by decision:new, decision:other",
      "  fix: @cites new or @cites other" );
    ( "docs/guide.md:34:1: retired cites:site:docs/guide.md#retired-bare->gone \
       decision:gone is superseded by decision:next",
      "  fix: @cites next" );
    ( "docs/guide.md:38:1: retired cites:site:docs/guide.md#ack-paragraph->dep \
       decision:dep is deprecated",
      "  fix: @ack retired dep 3be6fe65" );
    ( "docs/guide.md:43:3: retired cites:site:docs/guide.md#ack-item->dep \
       decision:dep is deprecated",
      "  fix: @ack retired dep 9b26ac71" );
    ( "docs/guide.md:47:7: retired cites:site:docs/guide.md#ack-task->dep \
       decision:dep is deprecated",
      "  fix: @ack retired dep 29872d68" );
    ( "docs/guide.md:47:7: suspect cites:site:docs/guide.md#ack-task->dep the \
       @cites names v1, and decision:dep is at v2",
      "  fix: @cites dep v2" );
    ( "docs/guide.md:52:5: retired cites:site:docs/guide.md#ack-number->dep \
       decision:dep is deprecated",
      "  fix: @ack retired dep 035bdeb6" );
    ( "docs/guide.md:58:4: retired cites:site:docs/guide.md#ack-tab->dep \
       decision:dep is deprecated",
      "  fix: @ack retired dep 5cd8cefe" );
    ( "docs/guide.md:63:3: retired cites:site:docs/guide.md#ack-later->dep \
       decision:dep is deprecated",
      "  fix: @ack retired dep 3188e4cb" );
    ( "docs/guide.md:67:1: renamed cites:site:docs/guide.md#moved->moved the \
       base declares req:moved, and req:moved-new has its extent now",
      "  fix: @cites moved-new v1" );
    ( "docs/guide.md:68:1: renamed satisfies:site:docs/guide.md#moved->moved \
       the base declares req:moved, and req:moved-new has its extent now",
      "  fix: @satisfies moved-new" );
    ( "docs/guide.md:69:1: renamed refines:site:docs/guide.md#moved->moved the \
       base declares req:moved, and req:moved-new has its extent now",
      "  fix: @refines moved-new v1" );
  ]

let the_fix_line_is_the_line_of_170c04b () =
  let entries =
    List.map
      (fun finding -> Check.text { Check.finding; tier = None })
      (List.filter
         (fun (finding : Finding.t) ->
           finding.finding_class <> Finding_class.Missing_plan_id)
         (findings ~base probe))
  in
  Alcotest.(check (list (pair string string)))
    "the fix lines" fix_lines_of_170c04b
    (List.filter_map
       (function [ first; fix ] -> Some (first, fix) | _ -> None)
       entries)

let probe_changes = lazy (changes ~base probe)

let every_fix_of_the_probe_repairs_its_finding () =
  List.iter
    (fun change ->
      Alcotest.(check bool)
        (Finding.id change.finding)
        true
        (repairs ~base probe change))
    (Lazy.force probe_changes)

let every_fix_of_the_probe_is_a_mechanical_repair () =
  List.iter
    (fun change ->
      Alcotest.(check bool)
        (Finding.id change.finding)
        true
        (is_mechanical ~base probe change))
    (Lazy.force probe_changes)

let every_fix_of_the_probe_touches_only_its_place () =
  List.iter
    (fun change ->
      Alcotest.(check bool)
        (Finding.id change.finding)
        true
        (touches_only_its_place change))
    (Lazy.force probe_changes)

let edit_of (fields : Jsonl.flat) =
  match
    List.map
      (fun name -> List.assoc_opt name fields)
      [ "alt"; "path"; "line"; "col"; "eline"; "ecol"; "text" ]
  with
  | [
   Some (Jsonl.Int alt);
   Some (Jsonl.String path);
   Some (Jsonl.Int line);
   Some (Jsonl.Int col);
   Some (Jsonl.Int eline);
   Some (Jsonl.Int ecol);
   Some (Jsonl.String text);
  ]
    when List.length fields = 7 ->
      Some (alt, path, line, col, eline, ecol, text)
  | _ -> None

let canonical (finding : Finding.t) =
  let record = Check.record ~mode:Mode.Tree { Check.finding; tier = None } in
  match
    (finding.fix, List.assoc_opt "help" record, List.assoc_opt "edits" record)
  with
  | None, None, None -> true
  | ( Some fix,
      Some (Jsonl.Scalar (Jsonl.String help)),
      Some (Jsonl.Objects objects) ) ->
      let edits = List.map edit_of objects in
      let edits = List.filter_map Fun.id edits in
      let rec sorted = function
        | first :: (second :: _ as rest) ->
            compare first second < 0 && sorted rest
        | [ _ ] | [] -> true
      in
      let rec apart = function
        | (alt, path, _, _, eline, ecol, _)
          :: ((alt', path', line', col', _, _, _) :: _ as rest) ->
            (alt <> alt' || path <> path'
            || compare (eline, ecol) (line', col') <= 0)
            && apart rest
        | [ _ ] | [] -> true
      in
      let alts =
        List.sort_uniq Int.compare
          (List.map (fun (alt, _, _, _, _, _, _) -> alt) edits)
      in
      String.equal help (Fix.help fix)
      && List.length edits = List.length objects
      && edits <> [] && sorted edits && apart edits
      && alts = List.init (List.length alts) (fun index -> index + 1)
      && List.map
           (fun (_, _, line, col, eline, ecol, text) ->
             { Fix.line; col; eline; ecol; text })
           edits
         = List.concat (Fix.alternatives fix)
  | _ -> false

let the_json_edits_are_canonical =
  property ~name:"help and edits come together, and the edits are canonical"
    ~print:String.escaped guide (fun guide ->
      List.for_all canonical (findings ~base (tree guide)))

let the_json_edits_of_the_probe_are_canonical () =
  List.iter
    (fun finding ->
      Alcotest.(check bool) (Finding.id finding) true (canonical finding))
    (findings ~base probe)

let tests =
  [
    the_edits_repair_the_finding;
    the_edits_are_a_mechanical_repair;
    the_edits_touch_only_their_place;
    the_json_edits_are_canonical;
    Alcotest.test_case "the JSON edits of the probe are canonical" `Quick
      the_json_edits_of_the_probe_are_canonical;
    Alcotest.test_case "the fix line is the line of 170c04b" `Quick
      the_fix_line_is_the_line_of_170c04b;
    Alcotest.test_case "every fix of the probe repairs its finding" `Quick
      every_fix_of_the_probe_repairs_its_finding;
    Alcotest.test_case "every fix of the probe is a mechanical repair" `Quick
      every_fix_of_the_probe_is_a_mechanical_repair;
    Alcotest.test_case "every fix of the probe touches only its place" `Quick
      every_fix_of_the_probe_touches_only_its_place;
  ]
