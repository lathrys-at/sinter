(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let is_digit = function '0' .. '9' -> true | _ -> false
let is_blank = function ' ' | '\t' -> true | _ -> false

let length text =
  let size = String.length text in
  let rec skip keep offset =
    if offset < size && keep text.[offset] then skip keep (offset + 1)
    else offset
  in
  let at offset byte = offset < size && text.[offset] = byte in
  let digits offset = skip is_digit offset in
  let rec runs offset =
    if at offset '.' && offset + 1 < size && is_digit text.[offset + 1] then
      runs (digits (offset + 1))
    else offset
  in
  let first = digits 0 in
  if first = 0 || not (at first '.') then 0
  else
    let after_dot = first + 1 in
    let stop =
      if after_dot < size && is_digit text.[after_dot] then
        let stop = runs (digits after_dot) in
        if at stop '.' then stop + 1 else stop
      else after_dot
    in
    if stop < size && is_blank text.[stop] then skip is_blank stop else 0

let remove text =
  let cut = length text in
  String.sub text cut (String.length text - cut)
