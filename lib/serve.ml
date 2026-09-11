(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

exception Error of string

type control = Done of int | Failed of int * string

type response = {
  rid : Jsonl.value option;
  output : Jsonl.record list;
  outcome : control;
}

(* One grammar, and the state of its file when the loop loaded it. *)
type entry = { language : Sinter_bridge.language; size : int; modified : float }

type t = {
  engine : Sinter_bridge.t;
  grammars : (string, entry) Hashtbl.t;
  mutable closed : bool;
}

let create () =
  match Sinter_bridge.create () with
  | engine -> { engine; grammars = Hashtbl.create 4; closed = false }
  | exception Sinter_bridge.Error message ->
      raise (Error ("the parser bridge does not start: " ^ message))

let close state =
  if not state.closed then (
    state.closed <- true;
    Hashtbl.reset state.grammars;
    Sinter_bridge.close state.engine)

(* The size and the modification time of the file at [path]. The pair
   is None when the file does not stat; the loader then reports what is
   wrong with the file. *)
let stamp path =
  match Unix.stat path with
  | stats -> Some (stats.st_size, stats.st_mtime)
  | exception Unix.Unix_error _ -> None

(* The grammar of the file at [path], loaded once and kept. The loop
   reads the stamp before it reads the file, so a file that changes
   during the load is loaded again on the next request. A grammar that
   does not load is not kept. *)
let language state path =
  let now = stamp path in
  match Hashtbl.find_opt state.grammars path with
  | Some entry when now = Some (entry.size, entry.modified) -> entry.language
  | _ ->
      Hashtbl.remove state.grammars path;
      let language = Parse.load state.engine ~grammar:path in
      (match now with
      | Some (size, modified) ->
          Hashtbl.replace state.grammars path { language; size; modified }
      | None -> ());
      language

(* A message goes into a record, and a string of a record is UTF-8.
   Every message this library builds is UTF-8; a message from
   elsewhere that is not is escaped rather than dropped. *)
let printable message =
  if Jsonl.is_utf_8 message then message else String.escaped message

let record_of_item tag = function
  | Parse.Capture record -> ("rid", tag) :: record
  | Parse.Tree { path; sexp } ->
      [ ("rid", tag); ("path", Jsonl.string path); ("tree", Jsonl.string sexp) ]

let run state tag (op : Request.op) =
  let collected = ref [] in
  let emit item = collected := record_of_item tag item :: !collected in
  let outcome =
    match op with
    | Request.Parse { grammar; output; files } -> (
        let query =
          match output with
          | Request.Captures path -> Some path
          | Request.Tree -> None
        in
        match
          let language = language state grammar in
          Parse.fold language ~query ~paths:files ~f:emit
        with
        | () -> Done Exit_code.clean
        | exception Parse.Error message ->
            Failed (Exit_code.environment_error, printable message)
        | exception Sinter_bridge.Error message ->
            Failed (Exit_code.environment_error, printable message)
        | exception Sys_error message ->
            Failed (Exit_code.environment_error, printable message))
  in
  { rid = Some tag; output = List.rev !collected; outcome }

let respond state line =
  if state.closed then
    invalid_arg "Sinter_core.Serve: the state of the loop is closed";
  match Request.of_line line with
  | Error { rid; cause } ->
      {
        rid = Option.map Request.value_of_rid rid;
        output = [];
        outcome =
          Failed (Exit_code.usage_error, printable (Request.message cause));
      }
  | Ok request -> run state (Request.value_of_rid request.rid) request.op

let control response = response.outcome

let lines response =
  let tag =
    match response.rid with None -> [] | Some value -> [ ("rid", value) ]
  in
  let last =
    match response.outcome with
    | Done code ->
        [ ("code", Jsonl.int code); ("event", Jsonl.string "done") ] @ tag
    | Failed (code, message) ->
        [
          ("code", Jsonl.int code);
          ("event", Jsonl.string "error");
          ("message", Jsonl.string message);
        ]
        @ tag
  in
  response.output @ [ last ]
