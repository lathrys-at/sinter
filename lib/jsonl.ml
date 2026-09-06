(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type scalar = String of string | Int of int | Bool of bool
type value = Scalar of scalar | Array of scalar list
type record = (string * value) list

let string s = Scalar (String s)
let int i = Scalar (Int i)
let bool b = Scalar (Bool b)
let strings l = Array (List.map (fun s -> String s) l)
let ints l = Array (List.map (fun i -> Int i) l)

(* spec/jsonl.md section 2 allows an integer in
   [-(2^53-1), 2^53-1]. A reader that holds numbers as IEEE 754
   double-precision floats, which JavaScript does, represents every
   integer in that range exactly. *)
let max_int_value = 9007199254740991
let min_int_value = -9007199254740991

(* The UTF-16 code units of a UTF-8 string. A code point below
   U+10000 is one code unit. A code point at U+10000 or above is a
   pair of surrogate code units. *)
let utf16_units s =
  let units = ref [] in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    let decoded = String.get_utf_8_uchar s !i in
    i := !i + Uchar.utf_decode_length decoded;
    let point = Uchar.to_int (Uchar.utf_decode_uchar decoded) in
    if point < 0x10000 then units := point :: !units
    else
      let rest = point - 0x10000 in
      units :=
        (0xDC00 lor (rest land 0x3FF)) :: (0xD800 lor (rest lsr 10)) :: !units
  done;
  List.rev !units

let compare_keys a b =
  (* Two names that hold the same bytes are equal. The decode below
     is only needed when they differ. *)
  if String.equal a b then 0
  else List.compare Int.compare (utf16_units a) (utf16_units b)

(* RFC 8785 section 3.2.2.2 defines this escaping. It is the escaping
   that ECMAScript's JSON.stringify produces: seven two-character
   escapes, then \u00xx with lowercase hex for the other control
   characters, and the literal UTF-8 bytes for everything else. *)
let add_escaped buffer s =
  Buffer.add_char buffer '"';
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    let decoded = String.get_utf_8_uchar s !i in
    if not (Uchar.utf_decode_is_valid decoded) then
      invalid_arg "Sinter_core.Jsonl: a string value is not valid UTF-8";
    let length = Uchar.utf_decode_length decoded in
    let point = Uchar.to_int (Uchar.utf_decode_uchar decoded) in
    (match point with
    | 0x22 -> Buffer.add_string buffer "\\\""
    | 0x5C -> Buffer.add_string buffer "\\\\"
    | 0x08 -> Buffer.add_string buffer "\\b"
    | 0x0C -> Buffer.add_string buffer "\\f"
    | 0x0A -> Buffer.add_string buffer "\\n"
    | 0x0D -> Buffer.add_string buffer "\\r"
    | 0x09 -> Buffer.add_string buffer "\\t"
    | point when point < 0x20 ->
        Buffer.add_string buffer (Printf.sprintf "\\u%04x" point)
    | _ -> Buffer.add_substring buffer s !i length);
    i := !i + length
  done;
  Buffer.add_char buffer '"'

let add_scalar buffer = function
  | String s -> add_escaped buffer s
  | Int i ->
      if i < min_int_value || i > max_int_value then
        invalid_arg
          "Sinter_core.Jsonl: an integer value is outside the range that \
           spec/jsonl.md section 2 allows";
      Buffer.add_string buffer (string_of_int i)
  | Bool b -> Buffer.add_string buffer (if b then "true" else "false")

let add_value buffer = function
  | Scalar s -> add_scalar buffer s
  | Array items ->
      Buffer.add_char buffer '[';
      List.iteri
        (fun index item ->
          if index > 0 then Buffer.add_char buffer ',';
          add_scalar buffer item)
        items;
      Buffer.add_char buffer ']'

let to_string record =
  let sorted =
    List.stable_sort (fun (a, _) (b, _) -> compare_keys a b) record
  in
  let rec check_unique = function
    | (a, _) :: ((b, _) :: _ as rest) ->
        if String.equal a b then
          invalid_arg
            (Printf.sprintf
               "Sinter_core.Jsonl: the record holds the field %S twice" a);
        check_unique rest
    | _ -> ()
  in
  check_unique sorted;
  let buffer = Buffer.create 256 in
  Buffer.add_char buffer '{';
  List.iteri
    (fun index (name, value) ->
      if index > 0 then Buffer.add_char buffer ',';
      add_escaped buffer name;
      Buffer.add_char buffer ':';
      add_value buffer value)
    sorted;
  Buffer.add_char buffer '}';
  Buffer.contents buffer

let output channel record =
  Stdlib.output_string channel (to_string record);
  Stdlib.output_char channel '\n'
