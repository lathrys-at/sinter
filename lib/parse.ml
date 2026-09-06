(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

exception Error of string

let fail format = Printf.ksprintf (fun message -> raise (Error message)) format

(* Every string in a record is UTF-8, and the text of a capture comes
   from the file.
   @cites json-handling *)
let check_utf_8 path text =
  let length = String.length text in
  let offset = ref 0 in
  while !offset < length do
    let decoded = String.get_utf_8_uchar text !offset in
    if not (Uchar.utf_decode_is_valid decoded) then
      fail "%s: the file is not UTF-8 text, at byte %d" path !offset;
    offset := !offset + Uchar.utf_decode_length decoded
  done

let read_file path =
  let channel =
    try open_in_bin path with Sys_error message -> fail "%s" message
  in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      try really_input_string channel (in_channel_length channel) with
      | Sys_error message -> fail "%s" message
      | End_of_file ->
          fail "%s: the file ended sooner than its length says" path)

let grammar_name path =
  let base = Filename.remove_extension (Filename.basename path) in
  let underscored = String.map (fun c -> if c = '-' then '_' else c) base in
  let prefix = "tree_sitter_" in
  let length = String.length prefix in
  if
    String.length underscored > length
    && String.equal (String.sub underscored 0 length) prefix
  then String.sub underscored length (String.length underscored - length)
  else underscored

(* A record holds an end line that is inclusive and an end column that
   is exclusive. tree-sitter gives an end point where both are
   exclusive, so a node that ends at the start of a row ends, for a
   record, at the end of the row before it. *)
let end_of_capture source (capture : Sinter_bridge.capture) =
  if capture.end_column = 0 && capture.end_row > capture.start_row then
    let line_start =
      if capture.end_byte < 2 then 0
      else
        match String.rindex_from_opt source (capture.end_byte - 2) '\n' with
        | Some index -> index + 1
        | None -> 0
    in
    (capture.end_row, capture.end_byte - line_start + 1)
  else (capture.end_row + 1, capture.end_column + 1)

(* The text of a capture is not normalized to Unicode NFC.
   @cites json-handling *)
let record_of_capture ~path ~source (capture : Sinter_bridge.capture) =
  let end_line, end_column = end_of_capture source capture in
  [
    ("path", Jsonl.string path);
    ("pat", Jsonl.int capture.pattern);
    ("cap", Jsonl.string capture.name);
    ("node", Jsonl.string capture.node_type);
    ("sb", Jsonl.int capture.start_byte);
    ("eb", Jsonl.int capture.end_byte);
    ("line", Jsonl.int (capture.start_row + 1));
    ("col", Jsonl.int (capture.start_column + 1));
    ("eline", Jsonl.int end_line);
    ("ecol", Jsonl.int end_column);
    ("text", Jsonl.string capture.text);
  ]

let read_source path =
  let source = read_file path in
  check_utf_8 path source;
  source

let of_bridge path f =
  try f () with Sinter_bridge.Error message -> fail "%s: %s" path message

let captures language ~query ~path =
  let source = read_source path in
  let found =
    of_bridge path (fun () -> Sinter_bridge.captures language ~source ~query)
  in
  List.map (record_of_capture ~path ~source) found

let tree language ~path =
  let source = read_source path in
  of_bridge path (fun () -> Sinter_bridge.tree language ~source)

let run ~grammar ~query ~paths channel =
  let wasm = read_file grammar in
  let name = grammar_name grammar in
  let engine =
    try Sinter_bridge.create ()
    with Sinter_bridge.Error message ->
      fail "the parser bridge does not start: %s" message
  in
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.close engine)
    (fun () ->
      let language =
        try Sinter_bridge.load engine ~name ~wasm
        with Sinter_bridge.Error message ->
          fail "%s: the grammar does not load: %s" grammar message
      in
      match query with
      | None ->
          List.iter
            (fun path -> output_string channel (tree language ~path ^ "\n"))
            paths
      | Some query_path ->
          let query = read_source query_path in
          if String.length (String.trim query) = 0 then
            fail "%s: the query file is empty" query_path;
          (* A query that does not compile fails in the same way for
             every file. Run it once over an empty text, so that the
             failure names the query file and not a source file. *)
          of_bridge query_path (fun () ->
              ignore (Sinter_bridge.captures language ~source:"" ~query));
          List.iter
            (fun path ->
              List.iter (Jsonl.output channel) (captures language ~query ~path))
            paths)
