(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type t =
  | Null
  | Bool of bool
  | Int of int
  | String of string
  | Array of t list
  | Object of (string * t) list

type step = Key of string | Index of int

type error =
  | Repeated_key of { path : step list; key : string }
  | Out_of_range of { path : step list; value : int }
  | Not_utf_8 of { path : step list; text : string }

let after_the_surrogates point = point >= 0xE000 && point < 0x10000
let outside_the_basic_plane point = point >= 0x10000

let compare_points a b =
  if after_the_surrogates a && outside_the_basic_plane b then 1
  else if outside_the_basic_plane a && after_the_surrogates b then -1
  else Int.compare a b

let compare_keys a b =
  let length_a = String.length a and length_b = String.length b in
  let rec walk i j =
    if i >= length_a then if j >= length_b then 0 else -1
    else if j >= length_b then 1
    else
      let decoded_a = String.get_utf_8_uchar a i
      and decoded_b = String.get_utf_8_uchar b j in
      let point_a = Uchar.to_int (Uchar.utf_decode_uchar decoded_a)
      and point_b = Uchar.to_int (Uchar.utf_decode_uchar decoded_b) in
      if point_a = point_b then
        walk
          (i + Uchar.utf_decode_length decoded_a)
          (j + Uchar.utf_decode_length decoded_b)
      else compare_points point_a point_b
  in
  walk 0 0

exception Refused of error

let within step = function
  | Repeated_key { path; key } -> Repeated_key { path = step :: path; key }
  | Out_of_range { path; value } -> Out_of_range { path = step :: path; value }
  | Not_utf_8 { path; text } -> Not_utf_8 { path = step :: path; text }

(* @cites json-handling *)
let max_int_value = 9007199254740991
let min_int_value = -9007199254740991

(* @cites json-handling *)
let escape buffer = function
  | '"' -> Buffer.add_string buffer "\\\""
  | '\\' -> Buffer.add_string buffer "\\\\"
  | '\b' -> Buffer.add_string buffer "\\b"
  | '\012' -> Buffer.add_string buffer "\\f"
  | '\n' -> Buffer.add_string buffer "\\n"
  | '\r' -> Buffer.add_string buffer "\\r"
  | '\t' -> Buffer.add_string buffer "\\t"
  | c -> Buffer.add_string buffer (Printf.sprintf "\\u%04x" (Char.code c))

let add_string buffer s =
  Buffer.add_char buffer '"';
  let n = String.length s in
  let rec go start i =
    if i >= n then Buffer.add_substring buffer s start (i - start)
    else
      match s.[i] with
      | ('"' | '\\' | '\000' .. '\031') as c ->
          Buffer.add_substring buffer s start (i - start);
          escape buffer c;
          go (i + 1) (i + 1)
      | '\128' .. '\255' ->
          let decoded = String.get_utf_8_uchar s i in
          if not (Uchar.utf_decode_is_valid decoded) then
            raise (Refused (Not_utf_8 { path = []; text = s }));
          go start (i + Uchar.utf_decode_length decoded)
      | _ -> go start (i + 1)
  in
  go 0 0;
  Buffer.add_char buffer '"'

let rec check_unique = function
  | (a, _) :: ((b, _) :: _ as rest) ->
      if String.equal a b then
        raise (Refused (Repeated_key { path = []; key = a }));
      check_unique rest
  | [ _ ] | [] -> ()

let rec add buffer = function
  | Null -> Buffer.add_string buffer "null"
  | Bool b -> Buffer.add_string buffer (if b then "true" else "false")
  | Int i ->
      if i < min_int_value || i > max_int_value then
        raise (Refused (Out_of_range { path = []; value = i }));
      Buffer.add_string buffer (string_of_int i)
  | String s -> add_string buffer s
  | Array items ->
      Buffer.add_char buffer '[';
      add_items buffer 0 items;
      Buffer.add_char buffer ']'
  | Object members ->
      let sorted =
        List.stable_sort
          (fun (a, _) (b, _) ->
            match compare_keys a b with
            | 0 -> String.compare a b
            | order -> order)
          members
      in
      check_unique sorted;
      Buffer.add_char buffer '{';
      add_members buffer true sorted;
      Buffer.add_char buffer '}'

and add_items buffer index = function
  | [] -> ()
  | item :: rest ->
      if index > 0 then Buffer.add_char buffer ',';
      (try add buffer item
       with Refused error -> raise (Refused (within (Index index) error)));
      add_items buffer (index + 1) rest

and add_members buffer first = function
  | [] -> ()
  | (key, value) :: rest ->
      if not first then Buffer.add_char buffer ',';
      (try
         add_string buffer key;
         Buffer.add_char buffer ':';
         add buffer value
       with Refused error -> raise (Refused (within (Key key) error)));
      add_members buffer false rest

let to_string value =
  let buffer =
    Buffer.create
      (256
      [@mutaml.skip
        "the number is only the first size of a buffer that grows as it needs, \
         and no output reads it"])
  in
  match add buffer value with
  | () -> Ok (Buffer.contents buffer)
  | exception Refused error -> Error error
