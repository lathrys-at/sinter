(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type printed = Same | Tab | Replaced

let classify code =
  if code = 0x09 then Tab
  else if
    code < 0x20
    || (code >= 0x7f && code <= 0x9f)
    || (code >= 0x202a && code <= 0x202e)
    || (code >= 0x2066 && code <= 0x2069)
  then Replaced
  else Same

let printed decoded =
  if Uchar.utf_decode_is_valid decoded then
    classify (Uchar.to_int (Uchar.utf_decode_uchar decoded))
  else Replaced

let character_width decoded =
  match printed decoded with
  | Tab -> 4
  | Replaced -> 1
  | Same -> max 0 (Uucp.Break.tty_width_hint (Uchar.utf_decode_uchar decoded))

let rec unchanged text offset =
  offset >= String.length text
  ||
  let decoded = String.get_utf_8_uchar text offset in
  printed decoded = Same
  && unchanged text (offset + Uchar.utf_decode_length decoded)

let replacement = "\xef\xbf\xbd"

let clean text =
  if unchanged text 0 then text
  else
    let buffer = Buffer.create (String.length text + 8) in
    let rec copy offset =
      if offset < String.length text then (
        let decoded = String.get_utf_8_uchar text offset in
        let size = Uchar.utf_decode_length decoded in
        (match printed decoded with
        | Same -> Buffer.add_substring buffer text offset size
        | Tab -> Buffer.add_string buffer "    "
        | Replaced -> Buffer.add_string buffer replacement);
        copy (offset + size))
    in
    copy 0;
    Buffer.contents buffer

let rec widths text offset before total =
  if before <= 0 || offset >= String.length text then total
  else
    let decoded = String.get_utf_8_uchar text offset in
    widths text
      (offset + Uchar.utf_decode_length decoded)
      (before - 1)
      (total + character_width decoded)

let column_width line column = widths line 0 (column - 1) 0
let width text = widths text 0 max_int 0

let rec count text offset total =
  if offset >= String.length text then total
  else
    count text
      (offset + Uchar.utf_decode_length (String.get_utf_8_uchar text offset))
      (total + 1)

let length line = count line 0 0
