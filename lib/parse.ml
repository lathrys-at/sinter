(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

exception Error of string

let fail format = Printf.ksprintf (fun message -> raise (Error message)) format

let is_utf_8 text =
  let length = String.length text in
  let rec check offset =
    offset >= length
    ||
    let decoded = String.get_utf_8_uchar text offset in
    Uchar.utf_decode_is_valid decoded
    && check (offset + Uchar.utf_decode_length decoded)
  in
  check 0

(* @cites json-handling *)
(* Every string in a record is UTF-8. The text of a capture comes from
   the file, and the name of the file goes into the record beside
   it. *)
let check_utf_8 path text =
  let length = String.length text in
  let offset = ref 0 in
  while !offset < length do
    let decoded = String.get_utf_8_uchar text !offset in
    if not (Uchar.utf_decode_is_valid decoded) then
      fail "%s: the file is not UTF-8 text, at byte %d" path !offset;
    offset := !offset + Uchar.utf_decode_length decoded
  done

let check_path path =
  if not (is_utf_8 path) then
    fail "the file name is not UTF-8 text: %s" (String.escaped path)

(* @cites json-handling *)
(* Every string of a record is UTF-8. [what] names the string, in the
   words the bridge uses for it. The caller checks [path] first, so
   that the message of a failure names a file the reader can read. *)
let check_string path what text =
  if not (is_utf_8 text) then fail "%s: %s is not UTF-8 text" path what

let read_file path =
  if try Sys.is_directory path with Sys_error _ -> false then
    fail "%s: is a directory" path;
  let channel =
    try open_in_bin path with Sys_error message -> fail "%s" message
  in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      try really_input_string channel (in_channel_length channel) with
      | Sys_error message ->
          (* The message of a failed read does not name the file, and
             the message of a failed open does. *)
          fail "%s: %s" path message
      | End_of_file ->
          fail "%s: the file ended sooner than its length says" path)

(* The name of the grammar in a wasm module. The bridge needs the name,
   and the module carries it: a grammar exports one function whose
   name is "tree_sitter_" and the name of the grammar.

   The reader below walks the section list of the module and reads the
   export section. Every count and every length in that format is an
   unsigned LEB128 integer. A module that the reader cannot follow
   gives None; the loader then reports what is wrong with it. *)
let name_of_wasm wasm =
  let length = String.length wasm in
  let prefix = "tree_sitter_" in
  let byte offset = Char.code (String.get wasm offset) in
  let rec number offset shift value =
    if offset >= length || shift > 28 then None
    else
      let part = byte offset in
      let value = value lor ((part land 0x7F) lsl shift) in
      if part < 0x80 then Some (value, offset + 1)
      else number (offset + 1) (shift + 7) value
  in
  let name offset =
    match number offset 0 0 with
    | Some (size, start) when start + size <= length ->
        Some (String.sub wasm start size, start + size)
    | _ -> None
  in
  let rec export offset stop count =
    if count = 0 then None
    else
      match name offset with
      | None -> None
      | Some (found, offset) -> (
          if
            (* One byte for the kind of the export, then its index. *)
            offset >= stop
          then None
          else if String.starts_with ~prefix found then
            let name =
              String.sub found (String.length prefix)
                (String.length found - String.length prefix)
            in
            (* The bridge takes the name as a C string, and a module
               can export a name that holds a NUL byte. *)
            if String.contains name '\000' then None else Some name
          else
            match number (offset + 1) 0 0 with
            | None -> None
            | Some (_, offset) -> export offset stop (count - 1))
  in
  let exports start stop =
    match number start 0 0 with
    | None -> None
    | Some (count, offset) -> export offset stop count
  in
  let rec section offset =
    if offset >= length then None
    else
      match number (offset + 1) 0 0 with
      | None -> None
      | Some (size, body) when body + size <= length ->
          if byte offset = 7 then exports body (body + size)
          else section (body + size)
      | Some _ -> None
  in
  if length < 8 || not (String.starts_with ~prefix:"\000asm" wasm) then None
  else
    match section 8 with
    (* The bridge loads a grammar under a C string, so a name that
       holds a NUL byte is no name at all. *)
    | Some name when String.contains name '\000' -> None
    | found -> found

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

(* @cites json-handling *)
(* @cites exit-codes *)
(* The text of a capture is not normalized to Unicode NFC.

   This function fails in two ways, and the two are of different
   kinds. A byte range outside the source can only be a fault of the
   tool, because the same string is the source of the parse and the
   source of the record; so it breaks a precondition and ends the
   command. A string that is not UTF-8 can be a fault of the data the
   tool was given; so it is an error of the run. *)
let record_of_capture ~path ~source (capture : Sinter_bridge.capture) =
  if
    capture.start_byte < 0
    || capture.end_byte < capture.start_byte
    || capture.end_byte > String.length source
  then
    invalid_arg
      "Sinter_core.Parse: the byte range of the capture is not inside the \
       source";
  check_path path;
  check_string path "the name of a capture" capture.name;
  check_string path "the type of a node" capture.node_type;
  check_string path "the text of a node" capture.text;
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

type item = Capture of Jsonl.record | Tree of { path : string; sexp : string }

let load engine ~grammar =
  let wasm = read_file grammar in
  let name =
    match name_of_wasm wasm with
    | Some name -> name
    | None -> grammar_name grammar
  in
  try Sinter_bridge.load engine ~name ~wasm
  with Sinter_bridge.Error message ->
    fail "%s: the grammar does not load: %s" grammar message

let fold language ~query ~paths ~f =
  List.iter check_path paths;
  match query with
  | None ->
      List.iter
        (fun path -> f (Tree { path; sexp = tree language ~path }))
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
          List.iter
            (fun record -> f (Capture record))
            (captures language ~query ~path))
        paths

let run ~grammar ~query ~paths channel =
  (* run reports a file name that is not UTF-8 text before it reads
     the grammar, and fold checks the names again for its own
     callers. *)
  List.iter check_path paths;
  let engine =
    try Sinter_bridge.create ()
    with Sinter_bridge.Error message ->
      fail "the parser bridge does not start: %s" message
  in
  Fun.protect
    ~finally:(fun () -> Sinter_bridge.close engine)
    (fun () ->
      let language = load engine ~grammar in
      let write = function
        | Capture record -> Jsonl.output channel record
        | Tree { path = _; sexp } -> output_string channel (sexp ^ "\n")
      in
      try
        fold language ~query ~paths ~f:write;
        flush channel
      with Sys_error message -> fail "cannot write the output: %s" message)
