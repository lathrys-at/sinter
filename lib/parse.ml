(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

exception Error of string

let fail format = Printf.ksprintf (fun message -> raise (Error message)) format

let check_path path =
  if not (Sinter_bridge.Utf_8.is_valid path) then
    raise (Error (Parse_record.message ~path Parse_record.Path_not_utf_8))

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
  List.map
    (fun capture ->
      match Parse_record.of_capture ~path ~source capture with
      | Ok record -> record
      | Error error -> raise (Error (Parse_record.message ~path error)))
    found

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
