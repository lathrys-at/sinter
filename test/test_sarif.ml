(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let field name (json : Yojson.Safe.t) =
  match json with `Assoc pairs -> List.assoc_opt name pairs | _ -> None

let rec at path json =
  match path with
  | [] -> Some json
  | name :: rest -> Option.bind (field name json) (at rest)

let text_at path json =
  match at path json with Some (`String text) -> Some text | _ -> None

let list_at path json =
  match at path json with Some (`List items) -> items | _ -> []

let int_at path json =
  match at path json with Some (`Int n) -> Some n | _ -> None

let decode uri =
  let buffer = Buffer.create (String.length uri) in
  let hex c =
    match c with
    | '0' .. '9' -> Some (Char.code c - 48)
    | 'A' .. 'F' -> Some (Char.code c - 55)
    | _ -> None
  in
  let rec walk index =
    if index >= String.length uri then Some (Buffer.contents buffer)
    else
      match uri.[index] with
      | '%' when index + 2 < String.length uri -> (
          match (hex uri.[index + 1], hex uri.[index + 2]) with
          | Some high, Some low ->
              Buffer.add_char buffer (Char.chr ((high * 16) + low));
              walk (index + 3)
          | _ -> None)
      | ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~' | '/') as
        c ->
          Buffer.add_char buffer c;
          walk (index + 1)
      | _ -> None
  in
  walk 0

let braces_doubled text =
  let length = String.length text in
  let rec walk index =
    index >= length
    ||
    match text.[index] with
    | ('{' | '}') as c ->
        index + 1 < length && text.[index + 1] = c && walk (index + 2)
    | _ -> walk (index + 1)
  in
  walk 0

let links text =
  let length = String.length text in
  let rec digits index acc =
    if index < length && text.[index] >= '0' && text.[index] <= '9' then
      digits (index + 1) ((acc * 10) + Char.code text.[index] - 48)
    else (index, acc)
  in
  let rec walk index opener found =
    if index >= length then List.rev found
    else
      match text.[index] with
      | '\\' -> walk (index + 2) opener found
      | '[' -> walk (index + 1) (Some (index + 1)) found
      | ']' -> (
          let stop, n = digits (index + 2) 0 in
          match opener with
          | Some start
            when index + 1 < length
                 && text.[index + 1] = '('
                 && stop > index + 2
                 && stop < length
                 && text.[stop] = ')' ->
              walk (stop + 1) None
                ((String.sub text start (index - start), n) :: found)
          | _ -> walk (index + 1) opener found)
      | _ -> walk (index + 1) opener found
  in
  walk 0 None []

let unescape text =
  let buffer = Buffer.create (String.length text) in
  let rec walk index =
    if index < String.length text then
      match text.[index] with
      | '\\' when index + 1 < String.length text ->
          Buffer.add_char buffer text.[index + 1];
          walk (index + 2)
      | ('{' | '}') as c
        when index + 1 < String.length text && text.[index + 1] = c ->
          Buffer.add_char buffer c;
          walk (index + 2)
      | c ->
          Buffer.add_char buffer c;
          walk (index + 1)
  in
  walk 0;
  Buffer.contents buffer

let problems = ref []
let fail problem = problems := problem :: !problems
let expect condition problem = if not condition then fail problem

let non_empty_text path json name =
  match text_at path json with
  | Some text when text <> "" -> Some text
  | _ ->
      fail (name ^ ": " ^ String.concat "." path ^ " is missing or empty");
      None

let check_message json name =
  Option.iter
    (fun text -> expect (braces_doubled text) (name ^ ": a brace is single"))
    (non_empty_text [ "message"; "text" ] json name)

let check_region json name =
  List.iter
    (fun key ->
      match int_at [ key ] json with
      | Some n when n >= 1 -> ()
      | _ -> fail (name ^ ": region lacks " ^ key))
    [ "startLine"; "startColumn"; "endLine"; "endColumn" ]

let check_artifact json name =
  match text_at [ "uri" ] json with
  | Some uri when uri <> "" ->
      expect (Option.is_some (decode uri)) (name ^ ": the uri does not decode");
      expect
        (text_at [ "uriBaseId" ] json = Some "%SRCROOT%")
        (name ^ ": no uriBaseId")
  | _ -> fail (name ^ ": no uri")

let check_physical json name =
  match at [ "physicalLocation" ] json with
  | None -> fail (name ^ ": no physicalLocation")
  | Some physical ->
      (match at [ "artifactLocation" ] physical with
      | Some artifact -> check_artifact artifact name
      | None -> fail (name ^ ": no artifactLocation"));
      (match at [ "region" ] physical with
      | Some region -> check_region region name
      | None -> fail (name ^ ": no region"));
      Option.iter
        (fun context ->
          check_region context (name ^ " context");
          let point line column json =
            (int_at [ line ] json, int_at [ column ] json)
          in
          let region = Option.value (at [ "region" ] physical) ~default:`Null in
          let start json = point "startLine" "startColumn" json
          and stop json = point "endLine" "endColumn" json in
          expect
            (compare (start context) (start region) <= 0
            && compare (stop region) (stop context) <= 0
            && (start context, stop context) <> (start region, stop region))
            (name ^ ": the context region is no proper superset of the region"))
        (at [ "contextRegion" ] physical)

let check_fix json name =
  Option.iter
    (fun text -> expect (braces_doubled text) (name ^ ": a brace is single"))
    (non_empty_text [ "description"; "text" ] json name);
  match list_at [ "artifactChanges" ] json with
  | [] -> fail (name ^ ": no artifactChanges")
  | changes ->
      List.iter
        (fun change ->
          (match at [ "artifactLocation" ] change with
          | Some artifact -> check_artifact artifact name
          | None -> fail (name ^ ": a change has no artifactLocation"));
          match list_at [ "replacements" ] change with
          | [] -> fail (name ^ ": a change has no replacements")
          | replacements ->
              List.iter
                (fun replacement ->
                  (match at [ "deletedRegion" ] replacement with
                  | Some region -> check_region region name
                  | None -> fail (name ^ ": no deletedRegion"));
                  match at [ "insertedContent" ] replacement with
                  | None -> ()
                  | Some content ->
                      expect
                        (match text_at [ "text" ] content with
                        | Some text -> text <> ""
                        | None -> false)
                        (name ^ ": empty insertedContent"))
                replacements)
        changes

let check_result rules index result =
  let name = Printf.sprintf "result %d" index in
  check_message result name;
  let rule_id = text_at [ "ruleId" ] result in
  (match (int_at [ "ruleIndex" ] result, rule_id) with
  | Some position, Some id ->
      expect
        (position >= 0
        && position < List.length rules
        && text_at [ "id" ] (List.nth rules position) = Some id)
        (name ^ ": ruleIndex does not name ruleId")
  | _ -> fail (name ^ ": no ruleId or ruleIndex"));
  expect
    (List.mem
       (text_at [ "level" ] result)
       [ Some "none"; Some "note"; Some "warning"; Some "error" ])
    (name ^ ": no level");
  Option.iter ignore
    (non_empty_text [ "partialFingerprints"; "sinterFindingId/v1" ] result name);
  (match at [ "locations" ] result with
  | None -> ()
  | Some (`List [ location ]) ->
      check_physical location name;
      Option.iter
        (fun _ -> check_message location (name ^ " location"))
        (at [ "message" ] location)
  | Some _ -> fail (name ^ ": locations is not one location"));
  let related = list_at [ "relatedLocations" ] result in
  let ids =
    List.filter_map (fun location -> int_at [ "id" ] location) related
  in
  expect
    (List.length ids = List.length related
    && List.length (List.sort_uniq Int.compare ids) = List.length ids)
    (name ^ ": the related ids are not unique");
  List.iter
    (fun location ->
      check_message location (name ^ " related");
      Option.iter
        (fun _ -> check_physical location (name ^ " related"))
        (at [ "physicalLocation" ] location))
    related;
  List.iter
    (fun (_, n) ->
      expect
        (List.exists
           (fun location ->
             int_at [ "id" ] location = Some n
             && Option.is_some (at [ "physicalLocation" ] location))
           related)
        (Printf.sprintf "%s: the link %d names no related place" name n))
    (links (Option.value (text_at [ "message"; "text" ] result) ~default:""));
  match at [ "fixes" ] result with
  | None -> ()
  | Some (`List (_ :: _ as fixes)) ->
      List.iteri
        (fun index fix -> check_fix fix (Printf.sprintf "%s fix %d" name index))
        fixes
  | Some _ -> fail (name ^ ": fixes is empty")

let check_log (json : Yojson.Safe.t) =
  problems := [];
  Option.iter ignore (non_empty_text [ "$schema" ] json "log");
  expect (text_at [ "version" ] json = Some "2.1.0") "log: version";
  (match list_at [ "runs" ] json with
  | [ run ] ->
      Option.iter ignore (non_empty_text [ "tool"; "driver"; "name" ] run "run");
      expect
        (text_at [ "columnKind" ] run = Some "unicodeCodePoints")
        "run: columnKind";
      let rules = list_at [ "tool"; "driver"; "rules" ] run in
      expect
        (List.map (text_at [ "id" ]) rules
        = List.map
            (fun finding_class -> Some (Finding_class.name finding_class))
            Finding_class.all)
        "run: the rules are not Finding_class.all";
      List.iter
        (fun rule ->
          List.iter
            (fun key ->
              match non_empty_text [ key; "text" ] rule "rule" with
              | Some text ->
                  expect (String.length text <= 1024) "rule: text too long"
              | None -> ())
            [ "shortDescription"; "fullDescription"; "help" ])
        rules;
      (match at [ "results" ] run with
      | Some (`List _) -> ()
      | _ -> fail "run: no results");
      List.iteri (check_result rules) (list_at [ "results" ] run)
  | _ -> fail "log: not one run");
  List.rev !problems

let parse text =
  match Yojson.Safe.from_string text with
  | json -> json
  | exception Yojson.Json_error message -> Alcotest.failf "not JSON: %s" message

let log ?(mode = Mode.Tree) ?(gate = Finding_class.Review) findings =
  Sarif.to_string ~tool:"v9" ~mode ~gate ~base:"abc" findings

let result_of findings =
  match list_at [ "runs" ] (parse (log findings)) with
  | [ run ] -> list_at [ "results" ] run
  | _ -> Alcotest.fail "not one run"

let only finding tier =
  match result_of [ (finding, tier) ] with
  | [ result ] -> result
  | _ -> Alcotest.fail "not one result"

let place ?(path = "a.md") line col eline ecol =
  {
    Finding.path;
    span =
      {
        Markdown.start = { line; column = col };
        stop = { line = eline; column = ecol };
      };
  }

let subject = Finding.Line { path = "a.md"; line = 3 }
let json_text = Alcotest.(check (option string))
let json_int = Alcotest.(check (option int))

let no_problems text =
  Alcotest.(check (list string)) "no problem" [] (check_log (parse text))

let writes_the_run () =
  let text = log ~mode:Mode.Diff ~gate:Finding_class.Turn [] in
  no_problems text;
  Alcotest.(check bool)
    "the keys are sorted and the line starts with $schema" true
    (String.starts_with
       ~prefix:
         "{\"$schema\":\"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json\",\"runs\":[{\"columnKind\":\"unicodeCodePoints\",\"properties\":{\"base\":\"abc\",\"gate\":\"turn\",\"mode\":\"diff\"},\"results\":[],\"tool\":{\"driver\":{\"name\":\"sinter\",\"rules\":[{"
       text);
  Alcotest.(check bool)
    "the line ends with the driver version and the log version" true
    (String.ends_with ~suffix:"}],\"version\":\"v9\"}}}],\"version\":\"2.1.0\"}"
       text);
  Alcotest.(check bool) "one line" false (String.contains text '\n')

let writes_each_rule () =
  match list_at [ "runs" ] (parse (log [])) with
  | [ run ] ->
      List.iter2
        (fun rule finding_class ->
          let sentence = Some (Finding_class.summary finding_class) in
          json_text "id"
            (Some (Finding_class.name finding_class))
            (text_at [ "id" ] rule);
          json_text "short" sentence
            (text_at [ "shortDescription"; "text" ] rule);
          json_text "full" sentence (text_at [ "fullDescription"; "text" ] rule);
          json_text "help" sentence (text_at [ "help"; "text" ] rule);
          Alcotest.(check int)
            "four keys" 4
            (match rule with `Assoc pairs -> List.length pairs | _ -> 0))
        (list_at [ "tool"; "driver"; "rules" ] run)
        Finding_class.all
  | _ -> Alcotest.fail "not one run"

let gives_each_tier_its_level () =
  List.iter
    (fun (tier, level) ->
      let finding =
        Finding.make Finding_class.Dangling subject ~detail:"d" ()
      in
      json_text
        (Finding_class.tier_name tier)
        (Some level)
        (text_at [ "level" ] (only finding tier));
      json_text "the tier property"
        (Some (Finding_class.tier_name tier))
        (text_at [ "properties"; "tier" ] (only finding tier)))
    Finding_class.[ (Off, "none"); (Warn, "warning"); (Block, "error") ]

let writes_the_result_fields () =
  let finding =
    Finding.make Finding_class.Retired
      (Finding.Fact { id = "cites:x"; ack_name = "x" })
      ~ackable:true ~detail:"d" ()
  in
  let result = only finding Finding_class.Warn in
  json_text "ruleId" (Some "retired") (text_at [ "ruleId" ] result);
  json_int "ruleIndex"
    (Some
       (List.length
          (List.filter
             (fun c -> compare c Finding_class.Retired < 0)
             Finding_class.all)))
    (int_at [ "ruleIndex" ] result);
  json_text "fingerprint"
    (Some (Finding.id finding))
    (text_at [ "partialFingerprints"; "sinterFindingId/v1" ] result);
  json_text "subject" (Some "cites:x")
    (text_at [ "properties"; "subject" ] result);
  json_text "ack_subject" (Some "x")
    (text_at [ "properties"; "ack_subject" ] result);
  Alcotest.(check bool)
    "ackable" true
    (at [ "properties"; "ackable" ] result = Some (`Bool true));
  json_text "gate" (Some "review") (text_at [ "properties"; "gate" ] result);
  Alcotest.(check bool) "no locations" true (at [ "locations" ] result = None);
  Alcotest.(check bool)
    "no related locations" true
    (at [ "relatedLocations" ] result = None);
  Alcotest.(check bool) "no fixes" true (at [ "fixes" ] result = None)

let writes_no_location_for_a_finding_with_no_place () =
  let finding =
    Finding.make Finding_class.Stale_delivery
      (Finding.Message_line { commit = "c0ffee"; line = 9 })
      ~detail:"the line names no step"
      ~related:[ { label = "the step"; place = Some (place 3 1 3 8) } ]
      ()
  in
  let text = log [ (finding, Finding_class.Block) ] in
  no_problems text;
  let result = only finding Finding_class.Block in
  Alcotest.(check bool) "no locations" true (at [ "locations" ] result = None);
  json_text "the message links the step"
    (Some "the line names no step ([the step](1))")
    (text_at [ "message"; "text" ] result);
  json_text "the subject" (Some "message:c0ffee@L9")
    (text_at [ "properties"; "subject" ] result);
  Alcotest.(check bool) "no fixes" true (at [ "fixes" ] result = None)

let names_the_class_without_a_detail () =
  json_text "the class name" (Some "cycle")
    (text_at [ "message"; "text" ]
       (only (Finding.make Finding_class.Cycle subject ()) Finding_class.Block))

let doubles_the_braces_and_escapes_the_links () =
  let finding =
    Finding.make Finding_class.Config_changed subject ~detail:"a {b} [x](1)"
      ~related:
        [
          { label = "in {a} [file] \\"; place = Some (place 2 1 2 4) };
          { label = "no [file] {x}"; place = None };
        ]
      ()
  in
  let result = only finding Finding_class.Warn in
  json_text "the message"
    (Some "a {{b}} [x](1) ([in {{a}} \\[file\\] \\\\](1); no [file] {{x}})")
    (text_at [ "message"; "text" ] result);
  match list_at [ "relatedLocations" ] result with
  | [ first; second ] ->
      json_int "first id" (Some 1) (int_at [ "id" ] first);
      json_text "first label" (Some "in {{a}} [file] \\")
        (text_at [ "message"; "text" ] first);
      json_text "first uri" (Some "a.md")
        (text_at [ "physicalLocation"; "artifactLocation"; "uri" ] first);
      json_int "first line" (Some 2)
        (int_at [ "physicalLocation"; "region"; "startLine" ] first);
      json_int "first end column" (Some 4)
        (int_at [ "physicalLocation"; "region"; "endColumn" ] first);
      json_int "second id" (Some 2) (int_at [ "id" ] second);
      json_text "second label" (Some "no [file] {{x}}")
        (text_at [ "message"; "text" ] second);
      Alcotest.(check bool)
        "no physical location" true
        (at [ "physicalLocation" ] second = None)
  | _ -> Alcotest.fail "not two related locations"

let writes_the_place_as_the_region () =
  let finding =
    Finding.make Finding_class.Dangling subject ~place:(place 3 2 4 5)
      ~detail:"d" ()
  in
  let result = only finding Finding_class.Block in
  match list_at [ "locations" ] result with
  | [ location ] ->
      let region key = int_at [ "physicalLocation"; "region"; key ] location in
      json_int "startLine" (Some 3) (region "startLine");
      json_int "startColumn" (Some 2) (region "startColumn");
      json_int "endLine" (Some 4) (region "endLine");
      json_int "endColumn" (Some 5) (region "endColumn");
      Alcotest.(check bool)
        "no context region" true
        (at [ "physicalLocation"; "contextRegion" ] location = None);
      Alcotest.(check bool) "no message" true (at [ "message" ] location = None)
  | _ -> Alcotest.fail "not one location"

let writes_the_mark_as_the_region () =
  let finding =
    Finding.make Finding_class.Suspect subject ~place:(place 3 1 3 23)
      ~mark:{ start = 8; stop = 20; label = "a {mark}" }
      ~detail:"d" ()
  in
  let result = only finding Finding_class.Block in
  match list_at [ "locations" ] result with
  | [ location ] ->
      let region name key = int_at [ "physicalLocation"; name; key ] location in
      json_int "startLine" (Some 3) (region "region" "startLine");
      json_int "startColumn" (Some 8) (region "region" "startColumn");
      json_int "endLine" (Some 3) (region "region" "endLine");
      json_int "endColumn" (Some 20) (region "region" "endColumn");
      json_int "context start" (Some 1) (region "contextRegion" "startColumn");
      json_int "context end" (Some 23) (region "contextRegion" "endColumn");
      json_int "context line" (Some 3) (region "contextRegion" "endLine");
      json_text "the label" (Some "a {{mark}}")
        (text_at [ "message"; "text" ] location)
  | _ -> Alcotest.fail "not one location"

let writes_no_context_for_a_mark_of_the_whole_place () =
  let finding =
    Finding.make Finding_class.Typo_tag subject ~place:(place 3 1 3 10)
      ~mark:{ start = 1; stop = 10; label = "m" }
      ~detail:"d" ()
  in
  match list_at [ "locations" ] (only finding Finding_class.Warn) with
  | [ location ] ->
      Alcotest.(check bool)
        "no context region" true
        (at [ "physicalLocation"; "contextRegion" ] location = None);
      json_int "the region ends at the mark" (Some 10)
        (int_at [ "physicalLocation"; "region"; "endColumn" ] location);
      json_text "the label" (Some "m") (text_at [ "message"; "text" ] location)
  | _ -> Alcotest.fail "not one location"

let writes_a_context_for_a_mark_at_the_start_of_the_place () =
  List.iter
    (fun (stop, eline, ecol) ->
      let finding =
        Finding.make Finding_class.Typo_tag subject
          ~place:(place 3 1 eline ecol)
          ~mark:{ start = 1; stop; label = "m" }
          ~detail:"d" ()
      in
      match list_at [ "locations" ] (only finding Finding_class.Warn) with
      | [ location ] ->
          Alcotest.(check bool)
            "a context region" true
            (Option.is_some
               (at [ "physicalLocation"; "contextRegion" ] location))
      | _ -> Alcotest.fail "not one location")
    [ (9, 3, 10); (10, 4, 10) ]

let marks_the_first_line_of_a_place_of_two_lines () =
  let finding =
    Finding.make Finding_class.Suspect subject ~place:(place 3 1 4 2)
      ~mark:{ start = 2; stop = 5; label = "m" }
      ~detail:"d" ()
  in
  match list_at [ "locations" ] (only finding Finding_class.Block) with
  | [ location ] ->
      json_int "the end line of the mark" (Some 3)
        (int_at [ "physicalLocation"; "region"; "endLine" ] location);
      json_int "the end line of the context" (Some 4)
        (int_at [ "physicalLocation"; "contextRegion"; "endLine" ] location)
  | _ -> Alcotest.fail "not one location"

let percent_encodes_the_path () =
  let path = "d i/%c#?:+\xc3\xa9~-_.Z9[\".md" in
  let finding =
    Finding.make Finding_class.Dangling subject ~place:(place ~path 1 1 1 2)
      ~detail:"d" ()
  in
  match list_at [ "locations" ] (only finding Finding_class.Block) with
  | [ location ] ->
      json_text "the uri" (Some "d%20i/%25c%23%3F%3A%2B%C3%A9~-_.Z9%5B%22.md")
        (text_at [ "physicalLocation"; "artifactLocation"; "uri" ] location);
      json_text "the base" (Some "%SRCROOT%")
        (text_at
           [ "physicalLocation"; "artifactLocation"; "uriBaseId" ]
           location)
  | _ -> Alcotest.fail "not one location"

let replacements result =
  List.map
    (fun fix ->
      ( text_at [ "description"; "text" ] fix,
        List.map
          (fun change ->
            ( text_at [ "artifactLocation"; "uri" ] change,
              List.map
                (fun replacement ->
                  ( List.map
                      (fun key -> int_at [ "deletedRegion"; key ] replacement)
                      [ "startLine"; "startColumn"; "endLine"; "endColumn" ],
                    at [ "insertedContent" ] replacement ))
                (list_at [ "replacements" ] change) ))
          (list_at [ "artifactChanges" ] fix) ))
    (list_at [ "fixes" ] result)

let with_fix fix =
  only
    (Finding.make Finding_class.Retired subject ~place:(place 1 1 1 12)
       ~detail:"d" ~fix ())
    Finding_class.Warn

let writes_one_fix_for_each_alternative () =
  let fix = Fix.successors (Edits.tag "@cites a v1\n") ("bb", 2) [ ("c", 3) ] in
  let text value = Some (`Assoc [ ("text", `String value) ]) in
  Alcotest.(check bool)
    "two fixes, each with its replacements" true
    (replacements (with_fix fix)
    = [
        ( Some (Fix.help fix),
          [
            ( Some "a.md",
              [
                ([ Some 1; Some 8; Some 1; Some 9 ], text "bb");
                ([ Some 1; Some 10; Some 1; Some 12 ], text "v2");
              ] );
          ] );
        ( Some (Fix.help fix),
          [
            ( Some "a.md",
              [
                ([ Some 1; Some 8; Some 1; Some 9 ], text "c");
                ([ Some 1; Some 10; Some 1; Some 12 ], text "v3");
              ] );
          ] );
      ])

let writes_the_ack_insert () =
  let fix = Fix.ack (Edits.document "@cites a\r\n") ~block:0 ~target:"a" in
  match Fix.alternatives fix with
  | [ [ edit ] ] ->
      Alcotest.(check bool)
        "an empty region and the text with its line ending" true
        (replacements (with_fix fix)
        = [
            ( Some (Fix.help fix),
              [
                ( Some "a.md",
                  [
                    ( [ Some 1; Some 9; Some 1; Some 9 ],
                      Some (`Assoc [ ("text", `String edit.text) ]) );
                  ] );
              ] );
          ]);
      Alcotest.(check bool)
        "the text starts with CR LF" true
        (String.starts_with ~prefix:"\r\n@ack retired a " edit.text)
  | _ -> Alcotest.fail "not one edit"

let writes_a_deletion_with_no_content () =
  let fix = Fix.spelling (Edits.tag "@cites a\n") "" in
  Alcotest.(check bool)
    "no insertedContent" true
    (replacements (with_fix fix)
    = [
        ( Some (Fix.help fix),
          [ (Some "a.md", [ ([ Some 1; Some 8; Some 1; Some 9 ], None) ]) ] );
      ])

let writes_every_result_in_order () =
  let findings =
    List.map
      (fun finding_class ->
        (Finding.make finding_class subject (), Finding_class.Warn))
      Finding_class.all
  in
  Alcotest.(check (list (option string)))
    "one result for each finding, in order"
    (List.map (fun c -> Some (Finding_class.name c)) Finding_class.all)
    (List.map (text_at [ "ruleId" ]) (result_of findings))

let refuses_a_string_that_is_not_utf_8 () =
  Alcotest.check_raises "a detail that is not UTF-8"
    (Invalid_argument
       "Sinter_core.Sarif: a string is not valid UTF-8, or a line or a column \
        is outside the range of JSON") (fun () ->
      ignore
        (log
           [
             ( Finding.make Finding_class.Dangling subject ~detail:"\xff" (),
               Finding_class.Warn );
           ]))

let structural_check_finds_faults () =
  let has_problem text = check_log (Yojson.Safe.from_string text) <> [] in
  Alcotest.(check bool) "an empty object" true (has_problem "{}");
  Alcotest.(check bool) "a single brace" false (braces_doubled "a {b");
  Alcotest.(check bool) "doubled braces" true (braces_doubled "a {{b}}");
  Alcotest.(check (list (pair string int)))
    "the links, each from its nearest opener"
    [ ("a\\]", 1); ("b", 22) ]
    (links "x [a\\]](1) y [x [b](22) [c](z)");
  Alcotest.(check string) "unescape" "a]{b}\\" (unescape "a\\]{{b}}\\\\");
  Alcotest.(check (option string)) "a bad escape" None (decode "a%2");
  Alcotest.(check (option string)) "a space" None (decode "a b")

module Gen = QCheck2.Gen

let property ?(count = 300) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let findings = Gen.list_size (Gen.int_range 0 5) Generators.sarif_finding
let print_findings = QCheck2.Print.list Generators.print_sarif_finding

let a_log_passes_the_structural_check =
  property ~name:"a log parses and passes the structural check"
    ~print:print_findings findings (fun findings ->
      match check_log (parse (log findings)) with
      | [] -> true
      | problems -> QCheck2.Test.fail_report (String.concat "\n" problems))

let a_log_holds_one_result_for_each_finding =
  property ~name:"a log holds one result for each finding, as the mapping says"
    ~print:print_findings findings (fun findings ->
      let results = result_of findings in
      List.length results = List.length findings
      && List.for_all2
           (fun result ((finding : Finding.t), tier) ->
             let uri_path path = Option.bind (text_at [ "uri" ] path) decode in
             text_at [ "ruleId" ] result
             = Some (Finding_class.name finding.finding_class)
             && text_at [ "properties"; "tier" ] result
                = Some (Finding_class.tier_name tier)
             && text_at [ "partialFingerprints"; "sinterFindingId/v1" ] result
                = Some (Finding.id finding)
             && (match (finding.place, list_at [ "locations" ] result) with
               | None, [] -> true
               | Some { path; _ }, [ location ] ->
                   Option.bind
                     (at [ "physicalLocation"; "artifactLocation" ] location)
                     uri_path
                   = Some path
               | _ -> false)
             && List.length (list_at [ "relatedLocations" ] result)
                = List.length finding.related
             && List.for_all2
                  (fun location ({ place; _ } : Finding.related) ->
                    match place with
                    | None -> at [ "physicalLocation" ] location = None
                    | Some { path; _ } ->
                        Option.bind
                          (at
                             [ "physicalLocation"; "artifactLocation" ]
                             location)
                          uri_path
                        = Some path)
                  (list_at [ "relatedLocations" ] result)
                  finding.related
             && List.map
                  (fun (text, n) -> (unescape text, n))
                  (links
                     (Option.value
                        (text_at [ "message"; "text" ] result)
                        ~default:""))
                = List.filter_map Fun.id
                    (List.mapi
                       (fun index ({ label; place } : Finding.related) ->
                         Option.map (fun _ -> (label, index + 1)) place)
                       finding.related)
             && List.for_all
                  (fun fix ->
                    List.for_all
                      (fun change ->
                        match finding.place with
                        | Some { path; _ } ->
                            Option.bind
                              (at [ "artifactLocation" ] change)
                              uri_path
                            = Some path
                        | None -> false)
                      (list_at [ "artifactChanges" ] fix))
                  (list_at [ "fixes" ] result)
             && List.length (list_at [ "fixes" ] result)
                =
                match finding.fix with
                | Some fix -> List.length (Fix.alternatives fix)
                | None -> 0)
           results findings)

let tests =
  [
    Alcotest.test_case "writes the run" `Quick writes_the_run;
    Alcotest.test_case "writes each rule" `Quick writes_each_rule;
    Alcotest.test_case "gives each tier its level" `Quick
      gives_each_tier_its_level;
    Alcotest.test_case "writes the result fields" `Quick
      writes_the_result_fields;
    Alcotest.test_case "writes no location for a finding with no place" `Quick
      writes_no_location_for_a_finding_with_no_place;
    Alcotest.test_case "names the class without a detail" `Quick
      names_the_class_without_a_detail;
    Alcotest.test_case "doubles the braces and escapes the links" `Quick
      doubles_the_braces_and_escapes_the_links;
    Alcotest.test_case "writes the place as the region" `Quick
      writes_the_place_as_the_region;
    Alcotest.test_case "writes the mark as the region" `Quick
      writes_the_mark_as_the_region;
    Alcotest.test_case "writes no context for a mark of the whole place" `Quick
      writes_no_context_for_a_mark_of_the_whole_place;
    Alcotest.test_case "writes a context for a mark at the start of the place"
      `Quick writes_a_context_for_a_mark_at_the_start_of_the_place;
    Alcotest.test_case "marks the first line of a place of two lines" `Quick
      marks_the_first_line_of_a_place_of_two_lines;
    Alcotest.test_case "percent-encodes the path" `Quick
      percent_encodes_the_path;
    Alcotest.test_case "writes one fix for each alternative" `Quick
      writes_one_fix_for_each_alternative;
    Alcotest.test_case "writes the @ack insert" `Quick writes_the_ack_insert;
    Alcotest.test_case "writes a deletion with no content" `Quick
      writes_a_deletion_with_no_content;
    Alcotest.test_case "writes every result in order" `Quick
      writes_every_result_in_order;
    Alcotest.test_case "refuses a string that is not UTF-8" `Quick
      refuses_a_string_that_is_not_utf_8;
    Alcotest.test_case "the structural check finds faults" `Quick
      structural_check_finds_faults;
    a_log_passes_the_structural_check;
    a_log_holds_one_result_for_each_finding;
  ]
