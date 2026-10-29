(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Bridge = Sinter_bridge

type error =
  | Unreadable of Text_file.error
  | Empty
  | Not_compiled of Bridge.Query.error
  | Not_parsed of Bridge.Tree.error
  | Not_run of Bridge.Query.run_error

let ( let* ) = Result.bind

let read path =
  Result.map_error (fun e -> Unreadable e) (Text_file.read_text path)

let compile language ~path =
  let* text = read path in
  if String.length (String.trim text) = 0 then Error Empty
  else
    Result.map_error
      (fun e -> Not_compiled e)
      (Bridge.Query.compile language text)

let with_tree language ~path use =
  let* source = read path in
  let* tree =
    Result.map_error (fun e -> Not_parsed e) (Bridge.Tree.parse language source)
  in
  Fun.protect
    ~finally:(fun () -> Bridge.Tree.close tree)
    (fun () -> use source tree)

let captures language query ~path =
  with_tree language ~path (fun source tree ->
      match Bridge.Query.run query tree with
      | Ok found -> Ok (source, found)
      | Error error -> Error (Not_run error))

let tree language ~path =
  with_tree language ~path (fun _ tree -> Ok (Bridge.Tree.sexp tree))

let message ~path = function
  | Unreadable error -> Text_file.message path error
  | Empty -> path ^ ": the query file is empty"
  | Not_compiled error ->
      path ^ ": cannot read the query: " ^ Bridge.Query.message error
  | Not_parsed error -> path ^ ": " ^ Bridge.Tree.message error
  | Not_run error -> path ^ ": " ^ Bridge.Query.run_message error

let help = function
  | Unreadable _ -> "name a file that you can read and that holds UTF-8 text"
  | Empty -> "write a tree-sitter query in the file"
  | Not_compiled _ -> "correct the query at the place that the message names"
  | Not_parsed _ -> "parse a file that the grammar can read"
  | Not_run _ -> Error_text.fault_of_sinter
