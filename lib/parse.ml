(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

exception Error of string

let fail format = Printf.ksprintf (fun message -> raise (Error message)) format
let is_utf_8 = Sinter_bridge.Utf_8.is_valid

let check_path path =
  if not (is_utf_8 path) then
    fail "the file name is not UTF-8 text: %s" (String.escaped path)

(* @cites json-handling *)
(* Every string of a record is UTF-8. [what] names the string, in the
   words the bridge uses for it. The caller checks [path] first, so
   that the message of a failure names a file the reader can read. *)
let check_string path what text =
  if not (is_utf_8 text) then fail "%s: %s is not UTF-8 text" path what

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
(* @cites exit-codes-by-gate *)
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
  match Text_file.read_text path with
  | Ok source -> source
  | Error error -> raise (Error (Text_file.message path error))

let of_bridge path f =
  try f () with Sinter_bridge.Error message -> fail "%s: %s" path message

(* The name of the file goes into every record, so a name that is not
   UTF-8 text fails before the file is read, and it fails the same way
   for a file that gives no capture. *)
let captures language ~query ~path =
  check_path path;
  let source = read_source path in
  let found =
    of_bridge path (fun () -> Sinter_bridge.captures language ~source ~query)
  in
  List.map (record_of_capture ~path ~source) found

let tree language ~path =
  check_path path;
  let source = read_source path in
  of_bridge path (fun () -> Sinter_bridge.tree language ~source)

type item = Capture of Jsonl.record | Tree of { path : string; sexp : string }

let load engine ~grammar =
  let wasm =
    match Text_file.read grammar with
    | Ok wasm -> wasm
    | Error error -> raise (Error (Text_file.message grammar error))
  in
  let name =
    match Grammar_name.of_wasm wasm with
    | Some name -> name
    | None -> Grammar_name.of_path grammar
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
  (* fold checks every path before it reads one. So with a grammar
     that does not load and a file name that is not UTF-8 text given
     together, the failure names the grammar. *)
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
