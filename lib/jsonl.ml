(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type scalar = String of string | Int of int | Bool of bool
type flat = (string * scalar) list
type value = Scalar of scalar | Array of scalar list | Objects of flat list
type record = (string * value) list

let string s = Scalar (String s)
let int i = Scalar (Int i)
let bool b = Scalar (Bool b)
let strings l = Array (List.map (fun s -> String s) l)
let ints l = Array (List.map (fun i -> Int i) l)
let objects l = Objects l
let compare_keys = Json.compare_keys

let json_of_scalar = function
  | String s -> Json.String s
  | Int i -> Json.Int i
  | Bool b -> Json.Bool b

let json_of_flat fields =
  Json.Object
    (List.map (fun (name, scalar) -> (name, json_of_scalar scalar)) fields)

let json_of_value = function
  | Scalar scalar -> json_of_scalar scalar
  | Array items -> Json.Array (List.map json_of_scalar items)
  | Objects items -> Json.Array (List.map json_of_flat items)

let refusal = function
  | Json.Repeated_key { path = []; key } ->
      Printf.sprintf "the record holds the field %S twice" key
  | Json.Repeated_key { path = _ :: _; key } ->
      Printf.sprintf "an object holds the field %S twice" key
  | Json.Out_of_range _ ->
      "an integer value is outside the range -(2^53-1) to 2^53-1"
  | Json.Not_utf_8 _ -> "a string value is not valid UTF-8"

let to_string record =
  match
    Json.to_string
      (Json.Object
         (List.map (fun (name, value) -> (name, json_of_value value)) record))
  with
  | Ok line -> line
  | Error error -> invalid_arg ("Sinter_core.Jsonl: " ^ refusal error)

let output channel record =
  Stdlib.output_string channel (to_string record);
  Stdlib.output_char channel '\n'
