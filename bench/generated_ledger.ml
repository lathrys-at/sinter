(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let base_seconds = 1767225600

let ts n =
  let seconds = base_seconds + n in
  let tm = Unix.gmtime (float_of_int seconds) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (tm.tm_year + 1900)
    (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec

let fields ~seq n =
  [
    ("v", Json.Int 1);
    ("seq", Json.Int seq);
    ("kind", Json.String "approval");
    ("by", Json.String "approver@example.com");
    ("ts", Json.String (ts n));
    ("head", Json.String (String.make 40 'a'));
    ("branch", Json.String "main");
    ("tool", Json.String "sinter 0.1.0");
    ("subject", Json.String (Printf.sprintf "req:r%d" n));
    ("rev", Json.Int 1);
    ("xh", Json.String (Sha256.hex (string_of_int n)));
  ]

let printed value =
  match Json.to_string value with
  | Ok text -> text
  | Error _ -> invalid_arg "Generated_ledger: a field does not print"

let entry ?seq n =
  let fields = fields ~seq:(Option.value seq ~default:(n + 1)) n in
  match Ledger.id_of (Json.Object fields) with
  | Ok id -> printed (Json.Object (("id", Json.String id) :: fields))
  | Error _ -> invalid_arg "Generated_ledger: a field does not print"

let id_of_line line =
  let key = "\"id\":\"e-" in
  let rec find from =
    match String.index_from_opt line from '"' with
    | None -> invalid_arg "Generated_ledger.chunks: a line holds no id"
    | Some at ->
        if
          at + String.length key + 12 <= String.length line
          && String.sub line at (String.length key) = key
        then String.sub line (at + String.length key - 2) 14
        else find (at + 1)
  in
  find 0

let chunks lines =
  let rec group acc current count = function
    | [] -> List.rev (if current = [] then acc else List.rev current :: acc)
    | line :: rest ->
        if count = Ledger.chunk_size then
          group (List.rev current :: acc) [ line ] 1 rest
        else group acc (line :: current) (count + 1) rest
  in
  List.map
    (fun chunk ->
      match chunk with
      | first :: _ ->
          let id = id_of_line first in
          ( Printf.sprintf "entries/%s/%s.jsonl" (String.sub id 2 2) id,
            String.concat "" (List.map (fun line -> line ^ "\n") chunk) )
      | [] -> invalid_arg "Generated_ledger.chunks: an empty chunk")
    (group [] [] 0 lines)

let write repo ~entries ~per_commit =
  if entries < 0 then invalid_arg "Generated_ledger.write: entries < 0";
  if per_commit < 1 then invalid_arg "Generated_ledger.write: per_commit < 1";
  let ref = Ledger.ref_name in
  let first = Git_fixture.commit ~ref ~mark:1 ~message:"start" [] in
  let rec commits acc mark written open_lines open_path =
    if written >= entries then List.rev acc
    else
      let count = min per_commit (entries - written) in
      let rec add lines path n remaining changes =
        if remaining = 0 then (lines, path, n, changes)
        else
          let lines, path, changes =
            if List.length lines = Ledger.chunk_size then ([], None, changes)
            else (lines, path, changes)
          in
          let lines = lines @ [ entry n ] in
          let path =
            match path with
            | Some path -> path
            | None -> fst (List.hd (chunks [ List.hd lines ]))
          in
          let content = String.concat "" (List.map (fun l -> l ^ "\n") lines) in
          let changes = (path, content) :: List.remove_assoc path changes in
          add lines (Some path) (n + 1) (remaining - 1) changes
      in
      let lines, path, written, changes =
        add open_lines open_path written count []
      in
      let command =
        Git_fixture.commit ~ref ~mark
          ~message:(Printf.sprintf "write %d" mark)
          (List.rev_map
             (fun (path, content) -> Git_fixture.File (path, content))
             changes)
      in
      commits (command :: acc) (mark + 1) written lines path
  in
  Git_fixture.import repo (first :: commits [] 2 0 [] None)
