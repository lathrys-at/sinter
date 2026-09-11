(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type id = Text of string | Number of int
type output = Captures of string | Tree
type op = Parse of { grammar : string; output : output; files : string list }
type t = { id : id; op : op }

type cause =
  | Not_json
  | Not_an_object
  | No_id
  | Bad_id
  | No_op
  | Bad_op
  | Unknown_op of string
  | Unknown_field of string
  | Repeated_field of string
  | Missing_field of string
  | Wrong_type of { field : string; wanted : string }
  | Empty_field of string
  | Not_text of string
  | Both_query_and_tree
  | Neither_query_nor_tree

type error = { id : id option; cause : cause }

let message = function
  | Not_json -> "the request is not JSON"
  | Not_an_object -> "the request is not a JSON object"
  | No_id -> "the request has no id"
  | Bad_id ->
      "the id must be a string, or an integer between -(2^53-1) and 2^53-1"
  | No_op -> "the request has no op"
  | Bad_op -> "the op must be a string"
  | Unknown_op name -> Printf.sprintf "there is no operation named %S" name
  | Unknown_field field ->
      Printf.sprintf "the field %S does not belong to this operation" field
  | Repeated_field field -> Printf.sprintf "the field %S is given twice" field
  | Missing_field field -> Printf.sprintf "the field %S is missing" field
  | Wrong_type { field; wanted } ->
      Printf.sprintf "the field %S must hold %s" field wanted
  | Empty_field field -> Printf.sprintf "the field %S must not be empty" field
  | Not_text field -> Printf.sprintf "the field %S must be UTF-8 text" field
  | Both_query_and_tree ->
      "query and tree exclude each other; give one of the two"
  | Neither_query_nor_tree -> "give either query or tree"

let value_of_id = function
  | Text text -> Jsonl.string text
  | Number number -> Jsonl.int number

(* @cites json-handling *)
(* The canonical form allows an integer in this range only, so a tag
   outside it could not be written back. *)
let max_number = 9007199254740991
let min_number = -9007199254740991
let ( let* ) = Result.bind
let untagged cause = Error { id = None; cause }
let bad id cause = Error { id = Some id; cause }

(* Every name that a parse request may hold. *)
let parse_fields = [ "id"; "op"; "grammar"; "query"; "tree"; "files" ]

let read_id fields =
  match List.filter (fun (name, _) -> String.equal name "id") fields with
  | [] -> untagged No_id
  | _ :: _ :: _ -> untagged (Repeated_field "id")
  | [ (_, `String text) ] when Jsonl.is_utf_8 text -> Ok (Text text)
  | [ (_, `Int number) ] when number >= min_number && number <= max_number ->
      Ok (Number number)
  | _ -> untagged Bad_id

(* A name that two pairs share. yojson keeps both pairs, and a record
   that holds one field twice is not a record. A line holds as many
   fields as its writer put in it, so the search sorts the names
   instead of comparing every pair of them. *)
let repeated fields =
  let rec adjacent = function
    | first :: (second :: _ as rest) ->
        if String.equal first second then Some first else adjacent rest
    | _ -> None
  in
  adjacent (List.sort String.compare (List.map fst fields))

let text id field = function
  | `String value ->
      if Jsonl.is_utf_8 value then Ok value else bad id (Not_text field)
  | _ -> bad id (Wrong_type { field; wanted = "a string" })

let flag id field = function
  | `Bool value -> Ok value
  | _ -> bad id (Wrong_type { field; wanted = "true or false" })

let paths id field value =
  let wanted = "an array of one string or more" in
  match value with
  | `List items ->
      let rec collect kept = function
        | [] -> Ok (List.rev kept)
        | `String item :: rest ->
            if Jsonl.is_utf_8 item then collect (item :: kept) rest
            else bad id (Not_text field)
        | _ -> bad id (Wrong_type { field; wanted })
      in
      let* collected = collect [] items in
      if collected = [] then bad id (Empty_field field) else Ok collected
  | _ -> bad id (Wrong_type { field; wanted })

let required id field read fields =
  match List.assoc_opt field fields with
  | None -> bad id (Missing_field field)
  | Some value -> read id field value

let optional id field read fields =
  match List.assoc_opt field fields with
  | None -> Ok None
  | Some value ->
      let* value = read id field value in
      Ok (Some value)

let unknown id known fields =
  match
    List.find_opt
      (fun (name, _) -> not (List.exists (String.equal name) known))
      fields
  with
  | Some (name, _) -> bad id (Unknown_field name)
  | None -> Ok ()

let read_parse id fields =
  let* () = unknown id parse_fields fields in
  let* grammar = required id "grammar" text fields in
  let* query = optional id "query" text fields in
  let* tree = optional id "tree" flag fields in
  let* files = required id "files" paths fields in
  let* output =
    match (query, tree) with
    | Some _, Some true -> bad id Both_query_and_tree
    | None, (None | Some false) -> bad id Neither_query_nor_tree
    | Some query, (None | Some false) -> Ok (Captures query)
    | None, Some true -> Ok Tree
  in
  Ok { id; op = Parse { grammar; output; files } }

let read_op id fields =
  match List.assoc_opt "op" fields with
  | None -> bad id No_op
  | Some (`String "parse") -> read_parse id fields
  | Some (`String name) -> bad id (Unknown_op name)
  | Some _ -> bad id Bad_op

let of_line line =
  (* A line of any depth reaches this reader, and yojson reads a nested
     value with a recursion. *)
  match Yojson.Safe.from_string line with
  | exception Yojson.Json_error _ -> untagged Not_json
  | exception Stack_overflow -> untagged Not_json
  | `Assoc fields -> (
      let* id = read_id fields in
      match repeated fields with
      | Some name -> bad id (Repeated_field name)
      | None -> read_op id fields)
  | _ -> untagged Not_an_object
