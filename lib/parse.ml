(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

exception Error of string

type item = Capture of Jsonl.record | Tree of { path : string; sexp : string }

let fail format = Printf.ksprintf (fun message -> raise (Error message)) format

let check_path path =
  if not (Sinter_bridge.Utf_8.is_valid path) then
    raise (Error (Parse_record.message ~path Parse_record.Path_not_utf_8))

(* An internal fault of the bridge names the file that the bridge was
   working on. *)
let of_bridge path f =
  try f () with Sinter_bridge.Error message -> fail "%s: %s" path message

let or_fail path = function
  | Ok value -> value
  | Error error -> raise (Error (Query_file.message ~path error))

(* Every record of a file is built before the caller sees one, so the
   caller sees no record of a file that fails. *)
let records ~path ~source found =
  List.map
    (fun capture ->
      match Parse_record.of_capture ~path ~source capture with
      | Ok record -> record
      | Error error -> raise (Error (Parse_record.message ~path error)))
    found

let load engine ~grammar =
  match Grammar.load engine ~path:grammar with
  | Ok language -> language
  | Error error -> raise (Error (Grammar.message ~path:grammar error))

(* The name of the file goes into every record, so a name that is not
   UTF-8 text fails before any file is read, and it fails the same way
   for a file that gives no capture. *)
let fold language ~query ~paths ~f =
  List.iter check_path paths;
  match query with
  | None ->
      List.iter
        (fun path ->
          let sexp =
            or_fail path
              (of_bridge path (fun () -> Query_file.tree language ~path))
          in
          f (Tree { path; sexp }))
        paths
  | Some query_path ->
      (* A query that does not compile fails in the same way for every
         file, so the failure names the query file. *)
      let query =
        or_fail query_path
          (of_bridge query_path (fun () ->
               Query_file.compile language ~path:query_path))
      in
      Fun.protect
        ~finally:(fun () -> Sinter_bridge.Query.close query)
        (fun () ->
          List.iter
            (fun path ->
              let source, found =
                or_fail path
                  (of_bridge path (fun () ->
                       Query_file.captures language query ~path))
              in
              List.iter
                (fun record -> f (Capture record))
                (records ~path ~source found))
            paths)

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
      Fun.protect
        ~finally:(fun () -> Sinter_bridge.Language.close language)
        (fun () ->
          let write = function
            | Capture record -> Jsonl.output channel record
            | Tree { path = _; sexp } -> output_string channel (sexp ^ "\n")
          in
          try
            fold language ~query ~paths ~f:write;
            flush channel
          with Sys_error message -> fail "cannot write the output: %s" message))
