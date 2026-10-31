(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let spec_folder = "../spec"

let examples () =
  Sys.readdir spec_folder |> Array.to_list
  |> List.filter (fun name -> Filename.check_suffix name ".md")
  |> List.sort compare
  |> List.concat_map (fun name ->
      let text =
        In_channel.with_open_bin
          (Filename.concat spec_folder name)
          In_channel.input_all
      in
      let rec scan inside found = function
        | [] -> List.rev found
        | "```json" :: rest -> scan true found rest
        | "```" :: rest -> scan false found rest
        | "" :: rest -> scan inside found rest
        | line :: rest ->
            scan inside (if inside then (name, line) :: found else found) rest
      in
      scan false [] (String.split_on_char '\n' text))

let scalar = function
  | `String s -> Jsonl.String s
  | `Int i -> Jsonl.Int i
  | `Bool b -> Jsonl.Bool b
  | other ->
      Alcotest.failf "a value that a record cannot hold: %s"
        (Yojson.Safe.to_string other)

let value = function
  | `List items -> Jsonl.Array (List.map scalar items)
  | other -> Jsonl.Scalar (scalar other)

let record_of_line line =
  match Yojson.Safe.from_string line with
  | `Assoc fields -> List.map (fun (key, field) -> (key, value field)) fields
  | _ -> Alcotest.failf "an example that is not an object: %s" line

let every_json_example_in_the_specifications_is_canonical () =
  let found = examples () in
  Alcotest.(check bool) "the specifications hold examples" true (found <> []);
  List.iter
    (fun (name, line) ->
      Alcotest.(check string)
        (name ^ ": the example is in canonical form")
        line
        (Jsonl.to_string (record_of_line line)))
    found

let read path = In_channel.with_open_bin path In_channel.input_all

let blocks ~info name =
  let opening = "```" ^ info in
  let rec scan block found = function
    | [] -> List.rev found
    | line :: rest when block = None && String.equal line opening ->
        scan (Some []) found rest
    | "```" :: rest -> (
        match block with
        | Some lines ->
            scan None
              (String.concat "" (List.rev_map (fun line -> line ^ "\n") lines)
              :: found)
              rest
        | None -> scan None found rest)
    | line :: rest ->
        scan (Option.map (fun lines -> line :: lines) block) found rest
  in
  scan None []
    (String.split_on_char '\n' (read (Filename.concat spec_folder name)))

let shown_with_nul block =
  let buffer = Buffer.create (String.length block) in
  let rec walk index =
    if index < String.length block then
      if
        block.[index] = '^'
        && index + 1 < String.length block
        && block.[index + 1] = '@'
      then (
        Buffer.add_char buffer '\000';
        walk (index + 2))
      else (
        if block.[index] <> '\n' then Buffer.add_char buffer block.[index];
        walk (index + 1))
  in
  walk 0;
  Buffer.contents buffer

let porcelain_examples =
  [
    ("check-porcelain-at-a-gate-prints-the-headers-that-it-names", false);
    ("check-porcelain-without-a-gate-gives-the-tier-none", false);
    ( "check-porcelain-quotes-a-path-with-a-tab-and-not-a-path-with-a-space",
      false );
    ("check-porcelain-z-ends-each-field-with-nul", true);
  ]

let case_file case path =
  read (Filename.concat "cases" (Filename.concat case path))

let words text =
  String.concat " "
    (List.filter
       (fun word -> word <> "")
       (String.split_on_char ' '
          (String.map (fun byte -> if byte = '\n' then ' ' else byte) text)))

let each_porcelain_example_is_the_output_of_its_case () =
  let found = blocks ~info:"text" "porcelain.md" in
  Alcotest.(check int)
    "one example for each case"
    (List.length porcelain_examples)
    (List.length found);
  List.iter2
    (fun (case, nul) block ->
      Alcotest.(check string)
        case
        (case_file case "expected/stdout")
        (if nul then shown_with_nul block else block))
    porcelain_examples found

let each_porcelain_example_names_the_input_of_its_case () =
  let text = words (read (Filename.concat spec_folder "porcelain.md")) in
  List.iter
    (fun (case, _) ->
      let command =
        "`sinter "
        ^ String.concat " "
            (List.filter
               (fun word -> word <> "")
               (String.split_on_char '\n' (case_file case "args")))
        ^ "`"
      in
      Alcotest.(check bool)
        (case ^ ": " ^ command)
        true
        (Option.is_some
           (let rec find index =
              if index + String.length command > String.length text then None
              else if
                String.equal
                  (String.sub text index (String.length command))
                  command
              then Some index
              else find (index + 1)
            in
            find 0)))
    porcelain_examples;
  Alcotest.(check (list string))
    "the file of the run at a gate"
    (List.map
       (fun (case, _) -> case_file case "tree/docs/guide.md")
       (List.filteri (fun index _ -> index < 2) porcelain_examples))
    (let file = blocks ~info:"markdown" "porcelain.md" in
     file @ file)

let tests =
  [
    Alcotest.test_case "every JSON example in the specifications is canonical"
      `Quick every_json_example_in_the_specifications_is_canonical;
    Alcotest.test_case "each porcelain example is the output of its case" `Quick
      each_porcelain_example_is_the_output_of_its_case;
    Alcotest.test_case "each porcelain example names the input of its case"
      `Quick each_porcelain_example_names_the_input_of_its_case;
  ]
