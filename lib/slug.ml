(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let is_alphanumeric = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' -> true
  | _ -> false

let is_valid text =
  let length = String.length text in
  let rec run offset =
    let rec stop offset =
      if offset < length && is_alphanumeric text.[offset] then stop (offset + 1)
      else offset
    in
    let stop = stop offset in
    if stop = offset then false
    else if stop = length then true
    else match text.[stop] with '-' | '_' | '.' -> run (stop + 1) | _ -> false
  in
  run 0

let of_heading text =
  String.map
    (fun byte ->
      if is_alphanumeric byte then Char.lowercase_ascii byte else '-')
    text
  |> String.split_on_char '-'
  |> List.filter (fun part -> part <> "")
  |> String.concat "-"
