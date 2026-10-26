(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type field = Capture_name | Node_type | Node_text
type error = Path_not_utf_8 | Not_utf_8 of field

let end_of_range source (range : Sinter_bridge.range) =
  if range.end_column = 0 && range.end_row > range.start_row then
    let line_start =
      if range.end_byte < 2 then 0
      else
        match String.rindex_from_opt source (range.end_byte - 2) '\n' with
        | Some index -> index + 1
        | None -> 0
    in
    (range.end_row, range.end_byte - line_start + 1)
  else (range.end_row + 1, range.end_column + 1)

(* @cites json-handling *)
(* Every string of a record is UTF-8. The function checks the path first,
   then the capture name, the node type, and the text. *)
let first_not_utf_8 ~path (capture : Sinter_bridge.Query.capture) =
  let valid = Sinter_bridge.Utf_8.is_valid in
  if not (valid path) then Some Path_not_utf_8
  else if not (valid capture.name) then Some (Not_utf_8 Capture_name)
  else if not (valid capture.node_type) then Some (Not_utf_8 Node_type)
  else if not (valid capture.text) then Some (Not_utf_8 Node_text)
  else None

(* @cites json-handling *)
(* @cites exit-codes-by-gate *)
(* The text of a capture is not normalized to Unicode NFC. *)
let of_capture ~path ~source (capture : Sinter_bridge.Query.capture) =
  let range = capture.range in
  if
    range.start_byte < 0
    || range.end_byte < range.start_byte
    || range.end_byte > String.length source
  then
    invalid_arg
      "Sinter_core.Parse_record: the byte range of the capture is not inside \
       the source";
  match first_not_utf_8 ~path capture with
  | Some error -> Error error
  | None ->
      let end_line, end_column = end_of_range source range in
      Ok
        [
          ("path", Jsonl.string path);
          ("pat", Jsonl.int capture.pattern);
          ("cap", Jsonl.string capture.name);
          ("node", Jsonl.string capture.node_type);
          ("sb", Jsonl.int range.start_byte);
          ("eb", Jsonl.int range.end_byte);
          ("line", Jsonl.int (range.start_row + 1));
          ("col", Jsonl.int (range.start_column + 1));
          ("eline", Jsonl.int end_line);
          ("ecol", Jsonl.int end_column);
          ("text", Jsonl.string capture.text);
        ]

let message ~path = function
  | Path_not_utf_8 -> "the file name is not UTF-8 text: " ^ String.escaped path
  | Not_utf_8 field ->
      let what =
        match field with
        | Capture_name -> "the name of a capture"
        | Node_type -> "the type of a node"
        | Node_text -> "the text of a node"
      in
      Printf.sprintf "%s: %s is not UTF-8 text" path what
