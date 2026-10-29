(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 300) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let reader =
  lazy
    (match Markdown.create (Sinter_bridge.create ()) with
    | Ok reader -> reader
    | Error _ -> failwith "the reader does not start")

let document text =
  match Markdown.read (Lazy.force reader) text with
  | Ok document -> document
  | Error _ -> Alcotest.fail "the text gives no document"

let tag text index = (document text).tags.(index)

let show_edit (edit : Fix.edit) =
  Printf.sprintf "%d:%d-%d:%d %S" edit.line edit.col edit.eline edit.ecol
    edit.text

let check_alternatives fix expected =
  Alcotest.(check (list (list string)))
    "the alternatives" expected
    (List.map (List.map show_edit) (Fix.alternatives fix))

let check_text fix expected =
  Alcotest.(check string) "the text" expected (Fix.text fix)

let word_replaces_the_tag_word () =
  let fix = Fix.word (tag "# A\n\n- @reqq a v1 Why.\n" 0) "req" in
  check_alternatives fix [ [ "3:3-3:8 \"@req\"" ] ];
  check_text fix "@req"

let pin_without_a_revision_inserts_after_the_target () =
  let fix = Fix.pin (tag "# A\n\n@satisfies \xc3\xa9t\xc3\xa9\tWhy.\n" 0) 3 in
  check_alternatives fix [ [ "3:15-3:15 \" v3\"" ] ];
  check_text fix "@satisfies \xc3\xa9t\xc3\xa9 v3"

let pin_with_a_revision_replaces_it () =
  let fix =
    Fix.pin
      (tag "# A\n\n- [ ] @cites \xc3\xa9t\xc3\xa9 \t v2 caf\xc3\xa9\n" 0)
      10
  in
  check_alternatives fix [ [ "3:20-3:22 \"v10\"" ] ];
  check_text fix "@cites \xc3\xa9t\xc3\xa9 v10"

let bump_replaces_or_adds_the_revision () =
  check_alternatives
    (Fix.bump (tag "# A\n@req a v1 Why.\n" 0) 2)
    [ [ "2:8-2:10 \"v2\"" ] ];
  let fix = Fix.bump (tag "# A\n@design b\n" 0) 2 in
  check_alternatives fix [ [ "2:10-2:10 \" v2\"" ] ];
  check_text fix "@design b v2"

let spelling_replaces_the_target () =
  let fix = Fix.spelling (tag "# A\n@cites Login v2 Why.\n" 0) "login" in
  check_alternatives fix [ [ "2:8-2:13 \"login\"" ] ];
  check_text fix "@cites login v2";
  check_text (Fix.spelling (tag "# A\n@cites Login\n" 0) "login") "@cites login"

let rename_replaces_the_target_and_a_changed_revision () =
  let fix = Fix.rename (tag "# A\n@cites old\tv1 Why.\n" 0) "new" 4 in
  check_alternatives fix [ [ "2:8-2:11 \"new\""; "2:12-2:14 \"v4\"" ] ];
  check_text fix "@cites new v4"

let rename_leaves_a_revision_that_stays () =
  let fix = Fix.rename (tag "# A\n@cites old v4\n" 0) "new" 4 in
  check_alternatives fix [ [ "2:8-2:11 \"new\"" ] ];
  check_text fix "@cites new v4"

let rename_writes_no_revision_on_a_tag_without_one () =
  let fix = Fix.rename (tag "# A\n@satisfies old\n" 0) "new" 4 in
  check_alternatives fix [ [ "2:12-2:15 \"new\"" ] ];
  check_text fix "@satisfies new"

let successors_give_one_alternative_each () =
  let fix =
    Fix.successors (tag "# A\n@cites gone v1\n" 0) ("b", 2) [ ("c", 1) ]
  in
  check_alternatives fix
    [ [ "2:8-2:12 \"b\""; "2:13-2:15 \"v2\"" ]; [ "2:8-2:12 \"c\"" ] ];
  check_text fix "@cites b v2 or @cites c v1";
  let fix = Fix.successors (tag "# A\n@cites gone\n" 0) ("b", 2) [] in
  check_alternatives fix [ [ "2:8-2:12 \"b\"" ] ];
  check_text fix "@cites b"

let plan_id_inserts_after_the_target () =
  let id =
    match Plan_target.id_of_string "3f2a9c" with
    | Some id -> id
    | None -> Alcotest.fail "no plan id"
  in
  let fix = Fix.plan_id (tag "# P\n\n@plan \xc3\xa9t\xc3\xa9  Why.\n" 0) id in
  check_alternatives fix [ [ "3:10-3:10 \"@3f2a9c\"" ] ];
  check_text fix "@plan \xc3\xa9t\xc3\xa9@3f2a9c"

let ack_inserts_a_line_after_the_last_tag_line () =
  let document =
    document "# A\n\n- @cites x\n  @cites y  \r\n\n## B\n@cites z\n"
  in
  let hash = String.sub document.blocks.(0).hash 0 8 in
  let fix = Fix.ack document ~block:0 ~target:"x" in
  check_alternatives fix
    [ [ Printf.sprintf "4:13-4:13 \"\\r\\n  @ack retired x %s\"" hash ] ];
  check_text fix ("@ack retired x " ^ hash);
  let hash = String.sub document.blocks.(1).hash 0 8 in
  check_alternatives
    (Fix.ack document ~block:1 ~target:"z")
    [ [ Printf.sprintf "7:9-7:9 \"\\n@ack retired z %s\"" hash ] ]

let refuses name gives =
  Alcotest.(check bool)
    name true
    (match gives () with exception Invalid_argument _ -> true | _ -> false)

let a_fix_needs_a_target () =
  let bare = tag "# A\n@cites\n" 0 in
  refuses "pin" (fun () -> Fix.pin bare 2);
  refuses "bump" (fun () -> Fix.bump bare 2);
  refuses "spelling" (fun () -> Fix.spelling bare "a");
  refuses "rename" (fun () -> Fix.rename bare "a" 1);
  refuses "successors" (fun () -> Fix.successors bare ("a", 1) []);
  refuses "plan_id" (fun () ->
      Fix.plan_id bare (Plan_target.derive ~base:"" ~path:""))

let a_fix_changes_the_revision () =
  refuses "a pin to the same revision" (fun () ->
      Fix.pin (tag "# A\n@cites a v2\n" 0) 2);
  refuses "a bump to the same revision" (fun () ->
      Fix.bump (tag "# A\n@req a v2\n" 0) 2);
  refuses "a bump to a lower revision" (fun () ->
      Fix.bump (tag "# A\n@req a v2\n" 0) 1);
  refuses "a bump to v1 of a tag with no revision" (fun () ->
      Fix.bump (tag "# A\n@req a\n" 0) 1);
  ignore (Fix.pin (tag "# A\n@cites a v2\n" 0) 1 : Fix.t);
  ignore (Fix.bump (tag "# A\n@req a v2\n" 0) 3 : Fix.t)

let an_ack_needs_a_block () =
  let document = document "# A\n@cites a\n" in
  refuses "a block past the last" (fun () ->
      Fix.ack document ~block:1 ~target:"a");
  refuses "a negative block" (fun () ->
      Fix.ack document ~block:(-1) ~target:"a")

let fixes text =
  let document = document text in
  let tag = document.tags.(0) in
  [
    Fix.word tag "req";
    Fix.pin tag 2;
    Fix.pin document.tags.(1) 2;
    Fix.bump tag 2;
    Fix.spelling tag "b";
    Fix.rename tag "b" 2;
    Fix.successors tag ("b", 2) [];
    Fix.successors tag ("b", 2) [ ("c", 1) ];
    Fix.plan_id tag (Plan_target.derive ~base:"" ~path:"");
    Fix.ack document ~block:0 ~target:"a";
  ]

let help_is_one_constant_for_each_form () =
  let first = fixes "# A\n@cites a\n@cites b v1\n"
  and second = fixes "# B\n\n- @req z Why.\n  @cites y v9\n" in
  Alcotest.(check bool)
    "the same string for each form" true
    (List.for_all2 (fun a b -> Fix.help a == Fix.help b) first second);
  let helps = List.map Fix.help first in
  Alcotest.(check int)
    "a different message for each form" (List.length helps)
    (List.length (List.sort_uniq String.compare helps))

let help_messages_are_fixed () =
  Alcotest.(check (list string))
    "the messages"
    [
      "replace the tag word with the nearest tag word that Sinter knows";
      "pin the citation to the revision of the declaration";
      "check that the citation still holds, then pin it to the current revision";
      "raise the revision above every revision in the base";
      "write the slug as the declaration spells it";
      "cite the declaration by its new slug";
      "cite the successor in place of the retired item";
      "cite one of the successors in place of the retired item";
      "give the plan an id after its slug";
      "if the citation still holds, accept the finding with an @ack line";
    ]
    (List.map Fix.help (fixes "# A\n@cites a\n@cites b v1\n"))

let line_endings = Gen.oneof_list [ "\n"; "\r\n" ]

let character =
  Gen.oneof_list [ "a"; " "; "\t"; "\xc3\xa9"; "\xf0\x9f\x98\x80"; "\r"; "z" ]

let text =
  Gen.map3
    (fun bom lines final ->
      (if bom then "\xef\xbb\xbf" else "")
      ^ String.concat ""
          (List.mapi
             (fun index (characters, ending) ->
               String.concat "" characters
               ^
               if index = List.length lines - 1 && not final then "" else ending)
             lines))
    Gen.bool
    (Gen.list_size (Gen.int_range 1 4)
       (Gen.pair (Gen.list_size (Gen.int_range 0 5) character) line_endings))
    Gen.bool

type piece = { at : int * int; bytes : string }

let pieces text =
  let body, bom =
    if String.starts_with ~prefix:"\xef\xbb\xbf" text then
      (String.sub text 3 (String.length text - 3), "\xef\xbb\xbf")
    else (text, "")
  in
  let count = Line_index.count (Line_index.make text) in
  let lines =
    List.filteri (fun index _ -> index < count) (String.split_on_char '\n' body)
  in
  { at = (1, 0); bytes = bom }
  :: List.concat
       (List.mapi
          (fun index line ->
            let last =
              index = count - 1 && not (String.ends_with ~suffix:"\n" body)
            in
            let content, ending =
              if last then (line, "")
              else if String.ends_with ~suffix:"\r" line then
                (String.sub line 0 (String.length line - 1), "\r\n")
              else (line, "\n")
            in
            let characters = ref [] and current = Buffer.create 4 in
            String.iter
              (fun byte ->
                if Char.code byte land 0xC0 <> 0x80 && Buffer.length current > 0
                then (
                  characters := Buffer.contents current :: !characters;
                  Buffer.clear current);
                Buffer.add_char current byte)
              content;
            if Buffer.length current > 0 then
              characters := Buffer.contents current :: !characters;
            let characters = List.rev !characters in
            List.mapi
              (fun column bytes -> { at = (index + 1, column + 1); bytes })
              characters
            @ [
                { at = (index + 1, List.length characters + 1); bytes = ending };
              ])
          lines)

let reference text (edits : Fix.edit list) =
  String.concat ""
    (List.map
       (fun piece ->
         let starting =
           List.filter_map
             (fun (edit : Fix.edit) ->
               if (edit.line, edit.col) = piece.at then Some edit.text else None)
             edits
         in
         let dropped =
           List.exists
             (fun (edit : Fix.edit) ->
               compare (edit.line, edit.col) piece.at <= 0
               && compare piece.at (edit.eline, edit.ecol) < 0)
             edits
         in
         String.concat "" starting ^ if dropped then "" else piece.bytes)
       (pieces text))

let positions text =
  List.filter_map
    (fun piece -> if snd piece.at >= 1 then Some piece.at else None)
    (pieces text)

let with_edits =
  Gen.bind text (fun text ->
      let positions = Array.of_list (positions text) in
      let count = max 1 (Array.length positions) in
      Gen.map
        (fun choices ->
          let rec pair = function
            | (start, kind) :: (stop, _) :: rest ->
                let line, col = positions.(start)
                and eline, ecol = positions.(stop) in
                let edit =
                  match kind mod 4 with
                  | 0 -> { Fix.line; col; eline = line; ecol = col; text = "@" }
                  | 1 -> { Fix.line; col; eline; ecol; text = "" }
                  | 2 -> { Fix.line; col; eline; ecol; text = "\xc3\xa9x" }
                  | _ -> { Fix.line; col; eline; ecol; text = "\r\n  @" }
                in
                edit :: pair rest
            | [ _ ] | [] -> []
          in
          ( text,
            if Array.length positions = 0 then []
            else
              pair
                (List.sort_uniq
                   (fun (a, _) (b, _) -> Int.compare a b)
                   (List.map
                      (fun (index, kind) -> (index mod count, kind))
                      choices)) ))
        (Gen.list_size (Gen.int_range 0 8)
           (Gen.pair (Gen.int_range 0 1000) (Gen.int_range 0 3))))

let print (text, edits) =
  String.escaped text ^ " with "
  ^ String.concat "; "
      (List.map (fun edit -> String.escaped (show_edit edit)) edits)

let apply_agrees_with_a_reference_on_characters =
  property
    ~name:"the test apply agrees with a reference that splits the characters"
    ~print with_edits (fun (text, edits) ->
      String.equal (Edits.apply text edits) (reference text edits))

let apply_takes_the_edits_in_any_order =
  property ~name:"the test apply gives one text for every order of the edits"
    ~print:(fun ((text, edits), shuffled) ->
      print (text, edits) ^ " and " ^ print (text, shuffled))
    (Gen.bind with_edits (fun (text, edits) ->
         Gen.map
           (fun shuffled -> ((text, edits), shuffled))
           (Gen.shuffle_list edits)))
    (fun ((text, edits), shuffled) ->
      String.equal (Edits.apply text edits) (Edits.apply text shuffled))

let every_edit_lies_on_the_line_of_the_first_edit =
  property
    ~name:"every edit of an alternative lies on the line of its first edit"
    ~print:String.escaped Generators.tag_block (fun text ->
      List.for_all
        (fun fix ->
          List.for_all
            (function
              | [] -> false
              | (first : Fix.edit) :: _ as edits ->
                  List.for_all
                    (fun (edit : Fix.edit) ->
                      edit.line = first.line && edit.eline = first.line)
                    edits)
            (Fix.alternatives fix))
        (fixes text))

let tests =
  [
    every_edit_lies_on_the_line_of_the_first_edit;
    Alcotest.test_case "Word replaces the tag word" `Quick
      word_replaces_the_tag_word;
    Alcotest.test_case "Pin without a revision inserts after the target" `Quick
      pin_without_a_revision_inserts_after_the_target;
    Alcotest.test_case "Pin with a revision replaces it" `Quick
      pin_with_a_revision_replaces_it;
    Alcotest.test_case "Bump replaces or adds the revision" `Quick
      bump_replaces_or_adds_the_revision;
    Alcotest.test_case "Spelling replaces the target" `Quick
      spelling_replaces_the_target;
    Alcotest.test_case "Rename replaces the target and a changed revision"
      `Quick rename_replaces_the_target_and_a_changed_revision;
    Alcotest.test_case "Rename leaves a revision that stays" `Quick
      rename_leaves_a_revision_that_stays;
    Alcotest.test_case "Rename writes no revision on a tag without one" `Quick
      rename_writes_no_revision_on_a_tag_without_one;
    Alcotest.test_case "Successors give one alternative each" `Quick
      successors_give_one_alternative_each;
    Alcotest.test_case "Plan_id inserts after the target" `Quick
      plan_id_inserts_after_the_target;
    Alcotest.test_case "Ack inserts a line after the last tag line" `Quick
      ack_inserts_a_line_after_the_last_tag_line;
    Alcotest.test_case "a fix needs a target" `Quick a_fix_needs_a_target;
    Alcotest.test_case "a fix changes the revision" `Quick
      a_fix_changes_the_revision;
    Alcotest.test_case "an ack needs a block" `Quick an_ack_needs_a_block;
    Alcotest.test_case "help is one constant for each form" `Quick
      help_is_one_constant_for_each_form;
    Alcotest.test_case "the help messages are fixed" `Quick
      help_messages_are_fixed;
    apply_agrees_with_a_reference_on_characters;
    apply_takes_the_edits_in_any_order;
  ]
