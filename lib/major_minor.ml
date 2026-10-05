(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* Each number is its decimal digits, with no leading zero, so that a
   number of any size compares by its length and then by its bytes. *)
type t = { major : string; minor : string }

let make major minor =
  if major < 0 || minor < 0 then
    invalid_arg "Major_minor.make: a number is below 0";
  { major = string_of_int major; minor = string_of_int minor }

let is_number text =
  text <> ""
  && String.for_all (fun c -> c >= '0' && c <= '9') text
  && (text = "0" || text.[0] <> '0')

let of_string text =
  match String.split_on_char '.' text with
  | [ major; minor ] when is_number major && is_number minor ->
      Some { major; minor }
  | _ -> None

let to_string version = version.major ^ "." ^ version.minor

let compare_numbers a b =
  match Int.compare (String.length a) (String.length b) with
  | 0 -> String.compare a b
  | order -> order

let compare a b =
  match compare_numbers a.major b.major with
  | 0 -> compare_numbers a.minor b.minor
  | order -> order

let newer a ~than = compare a than > 0
let older_major a ~than = compare_numbers a.major than.major < 0
