(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let first_invalid text =
  let length = String.length text in
  let rec walk offset =
    if offset >= length then None
    else
      let decoded = String.get_utf_8_uchar text offset in
      if Uchar.utf_decode_is_valid decoded then
        walk (offset + Uchar.utf_decode_length decoded)
      else Some offset
  in
  walk 0

let is_valid text = Option.is_none (first_invalid text)

let escaped text =
  let length = String.length text in
  let buffer = Buffer.create length in
  let rec copy offset =
    if offset < length then
      let decoded = String.get_utf_8_uchar text offset in
      if Uchar.utf_decode_is_valid decoded then (
        let size = Uchar.utf_decode_length decoded in
        Buffer.add_substring buffer text offset size;
        copy (offset + size))
      else (
        Printf.bprintf buffer "\\x%02x" (Char.code text.[offset]);
        copy (offset + 1))
  in
  copy 0;
  Buffer.contents buffer
