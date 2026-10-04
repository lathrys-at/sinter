(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

(* The specifications, as dune copies them beside the build copy of
   test/. *)
let spec_folder = "../spec"

(* Each line of each fenced block that opens with ```json, with the
   name of its file. *)
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

let tests =
  [
    Alcotest.test_case "every JSON example in the specifications is canonical"
      `Quick every_json_example_in_the_specifications_is_canonical;
  ]
