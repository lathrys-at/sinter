(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let rows () =
  let text =
    In_channel.with_open_bin "../spec/algebra.md" In_channel.input_all
  in
  let lines = String.split_on_char '\n' text in
  let rec section = function
    | [] -> []
    | line :: rest when String.starts_with ~prefix:"## 9." line -> rest
    | _ :: rest -> section rest
  in
  let rec table acc = function
    | [] -> List.rev acc
    | line :: _ when String.starts_with ~prefix:"## " line -> List.rev acc
    | line :: rest when String.starts_with ~prefix:"| `" line ->
        let cells =
          String.split_on_char '|' line
          |> List.map String.trim
          |> List.filter (fun cell -> cell <> "")
        in
        let name =
          String.sub (List.hd cells) 1 (String.length (List.hd cells) - 2)
        in
        table ((name, List.nth cells (List.length cells - 1)) :: acc) rest
    | _ :: rest -> table acc rest
  in
  table [] (section lines)

let tier_text = function
  | None -> "—"
  | Some tier -> Finding_class.tier_name tier

let tiers_text finding_class =
  let tiers =
    List.map
      (fun gate -> tier_text (Finding_class.builtin_tier finding_class gate))
      Finding_class.gates
  in
  match tiers with
  | [ "—"; "—"; "—" ] -> "—"
  | tiers -> String.concat ", " tiers

let the_classes_are_those_of_the_specification () =
  let rows = rows () in
  Alcotest.(check bool) "the table has rows" true (List.length rows > 30);
  Alcotest.(check (list string))
    "the names, in the order of the table" (List.map fst rows)
    (List.map Finding_class.name Finding_class.all);
  Alcotest.(check bool)
    "compare follows the order of all" true
    (List.sort compare Finding_class.all = Finding_class.all)

let each_tier_is_that_of_the_specification () =
  List.iter
    (fun (name, tiers) ->
      match Finding_class.of_name name with
      | None -> Alcotest.failf "no class %s" name
      | Some finding_class ->
          Alcotest.(check string)
            ("the tiers of " ^ name) tiers (tiers_text finding_class))
    (rows ())

let of_name_reads_each_name_back () =
  List.iter
    (fun finding_class ->
      Alcotest.(check bool)
        ("of_name of " ^ Finding_class.name finding_class)
        true
        (Finding_class.of_name (Finding_class.name finding_class)
        = Some finding_class))
    Finding_class.all

let of_name_refuses_other_names () =
  Alcotest.(check bool) "Dangling" true (Finding_class.of_name "Dangling" = None);
  Alcotest.(check bool) "dangle" true (Finding_class.of_name "dangle" = None);
  Alcotest.(check bool) "the empty name" true (Finding_class.of_name "" = None)

let gates_have_their_names () =
  Alcotest.(check (list string))
    "the gate names"
    [ "turn"; "review"; "merged" ]
    (List.map Finding_class.gate_name Finding_class.gates);
  List.iter
    (fun gate ->
      Alcotest.(check bool)
        ("gate_of_name of " ^ Finding_class.gate_name gate)
        true
        (Finding_class.gate_of_name (Finding_class.gate_name gate) = Some gate))
    Finding_class.gates;
  Alcotest.(check bool) "Turn" true (Finding_class.gate_of_name "Turn" = None)

let tiers_have_their_names () =
  Alcotest.(check (list string))
    "the tier names" [ "off"; "warn"; "block" ]
    (List.map Finding_class.tier_name Finding_class.[ Off; Warn; Block ]);
  List.iter
    (fun tier ->
      Alcotest.(check bool)
        ("tier_of_name of " ^ Finding_class.tier_name tier)
        true
        (Finding_class.tier_of_name (Finding_class.tier_name tier) = Some tier))
    Finding_class.[ Off; Warn; Block ];
  Alcotest.(check bool)
    "blocks" true
    (Finding_class.tier_of_name "blocks" = None)

let contains text piece =
  let size = String.length piece in
  let rec scan index =
    index + size <= String.length text
    && (String.equal (String.sub text index size) piece || scan (index + 1))
  in
  scan 0

let each_class_has_one_sentence () =
  List.iter
    (fun finding_class ->
      let name = Finding_class.name finding_class in
      let sentence = Finding_class.summary finding_class in
      let length = String.length sentence in
      Alcotest.(check bool) (name ^ ": not empty") true (length > 0);
      Alcotest.(check bool) (name ^ ": at most 1024 bytes") true (length <= 1024);
      Alcotest.(check bool)
        (name ^ ": starts with a capital letter or @")
        true
        (match sentence.[0] with 'A' .. 'Z' | '@' -> true | _ -> false);
      Alcotest.(check char)
        (name ^ ": ends with a full stop")
        '.'
        sentence.[length - 1];
      Alcotest.(check bool)
        (name ^ ": one sentence") false
        (contains (String.sub sentence 0 (length - 1)) ".");
      Alcotest.(check bool)
        (name ^ ": printable ASCII only")
        true
        (String.for_all (fun c -> c >= ' ' && c <= '~') sentence);
      Alcotest.(check bool)
        (name ^ ": no brace") false
        (String.contains sentence '{' || String.contains sentence '}'))
    Finding_class.all

let no_two_classes_share_a_sentence () =
  let sentences = List.map Finding_class.summary Finding_class.all in
  Alcotest.(check int)
    "one sentence for each class"
    (List.length Finding_class.all)
    (List.length (List.sort_uniq String.compare sentences))

let case name test = Alcotest.test_case name `Quick test

let tests =
  [
    case "the classes are those of the specification"
      the_classes_are_those_of_the_specification;
    case "each tier is that of the specification"
      each_tier_is_that_of_the_specification;
    case "of_name reads each name back" of_name_reads_each_name_back;
    case "of_name refuses other names" of_name_refuses_other_names;
    case "gates have their names" gates_have_their_names;
    case "tiers have their names" tiers_have_their_names;
    case "each class has one sentence" each_class_has_one_sentence;
    case "no two classes share a sentence" no_two_classes_share_a_sentence;
  ]
