(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

exception Error of Error_text.t

type control = Done of int | Failed of int * string

type response = {
  rid : Jsonl.value option;
  output : Jsonl.record list;
  outcome : control;
}

type entry = {
  language : Sinter_bridge.Language.t;
  size : int;
  modified : float;
}

type t = {
  engine : Sinter_bridge.t;
  grammars : (string, entry) Hashtbl.t;
  mutable closed : bool;
}

let create () =
  match Sinter_bridge.create () with
  | engine ->
      {
        engine;
        grammars =
          Hashtbl.create
            (4
            [@mutaml.skip
              "Hashtbl.create raises its argument to power_2_above 16, which \
               gives 16 for 4 and for 5, so both build the same table"]);
        closed = false;
      }
  | exception Sinter_bridge.Error message ->
      raise
        (Error
           {
             Error_text.fault = "the parser bridge does not start: " ^ message;
             help = Error_text.fault_of_sinter;
             place = None;
           })

let close state =
  if not state.closed then (
    state.closed <- true;
    (Hashtbl.iter
       (fun _ entry -> Sinter_bridge.Language.close entry.language)
       state.grammars;
     Hashtbl.reset state.grammars;
     Sinter_bridge.close state.engine)
    [@mutaml.skip
      "close sets closed before it frees the grammars, respond raises on a \
       closed state, a second close does nothing, and t is abstract, so no \
       road reads a grammar or the table after close; dropping a line only \
       leaves the grammars to the garbage collector"])

let stamp path =
  match Unix.stat path with
  | stats -> Some (stats.st_size, stats.st_mtime)
  | exception Unix.Unix_error _ -> None

let forget state path found =
  Hashtbl.remove state.grammars path;
  Option.iter (fun entry -> Sinter_bridge.Language.close entry.language) found

let with_language state path use =
  let now = stamp path in
  match Hashtbl.find_opt state.grammars path with
  | Some entry when now = Some (entry.size, entry.modified) ->
      use entry.language
  | found -> (
      forget state path found;
      let language =
        match Grammar.load state.engine ~path with
        | Ok language -> language
        | Error error ->
            raise
              (Parse.Error
                 {
                   Error_text.fault = Grammar.message ~path error;
                   help = Grammar.help error;
                   place = None;
                 })
      in
      match now with
      | Some (size, modified) ->
          Hashtbl.replace state.grammars path { language; size; modified };
          use language
      | None ->
          Fun.protect
            ~finally:(fun () -> Sinter_bridge.Language.close language)
            (fun () -> use language))

let printable message =
  if Sinter_bridge.Utf_8.is_valid message then message
  else String.escaped message

let record_of_item rid = function
  | Parse.Capture record -> ("rid", rid) :: record
  | Parse.Tree { path; sexp } ->
      [ ("rid", rid); ("path", Jsonl.string path); ("tree", Jsonl.string sexp) ]

let run state rid (op : Request.op) =
  let collected = ref [] in
  let emit item = collected := record_of_item rid item :: !collected in
  let outcome =
    match op with
    | Request.Parse { grammar; output; files } -> (
        let query =
          match output with
          | Request.Captures path -> Some path
          | Request.Tree -> None
        in
        match
          with_language state grammar (fun language ->
              Parse.fold language ~query ~paths:files ~f:emit)
        with
        | () -> Done Exit_code.clean
        | exception Parse.Error { fault; _ } ->
            Failed (Exit_code.environment_error, printable fault)
        | exception Sinter_bridge.Error message ->
            Failed (Exit_code.environment_error, printable message)
        | exception Sys_error message ->
            Failed (Exit_code.environment_error, printable message))
  in
  { rid = Some rid; output = List.rev !collected; outcome }

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
  let rid =
    match response.rid with None -> [] | Some value -> [ ("rid", value) ]
  in
  let last =
    match response.outcome with
    | Done code ->
        [ ("code", Jsonl.int code); ("event", Jsonl.string "done") ] @ rid
    | Failed (code, message) ->
        [
          ("code", Jsonl.int code);
          ("event", Jsonl.string "error");
          ("message", Jsonl.string message);
        ]
        @ rid
  in
  response.output @ [ last ]
