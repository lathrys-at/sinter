(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type position = { line : int; column : int }
type t = { text : string; starts : int array; ends : int array }

let byte_order_mark text =
  if String.starts_with ~prefix:"\xEF\xBB\xBF" text then 3 else 0

let make text =
  let length = String.length text in
  let rec scan segment first starts ends =
    match String.index_from_opt text segment '\n' with
    | Some feed -> scan (feed + 1) (feed + 1) (first :: starts) (feed :: ends)
    | None when segment < length -> (first :: starts, length :: ends)
    | None -> (starts, ends)
  in
  let starts, ends = scan 0 (byte_order_mark text) [] [] in
  {
    text;
    starts = Array.of_list (List.rev starts);
    ends = Array.of_list (List.rev ends);
  }

let text index = index.text
let count index = Array.length index.starts

let check_line index line =
  if line < 1 || line > count index then
    invalid_arg (Printf.sprintf "Line_index: no line %d" line)

let first index line =
  check_line index line;
  index.starts.(line - 1)

let content_end index line =
  check_line index line;
  let start = index.starts.(line - 1) and stop = index.ends.(line - 1) in
  if
    stop < String.length index.text
    && stop > start
    && index.text.[stop - 1] = '\r'
  then stop - 1
  else stop

let content index line =
  let start = first index line in
  String.sub index.text start (content_end index line - start)

let check_offset index offset =
  if offset < 0 || offset > String.length index.text || count index = 0 then
    invalid_arg (Printf.sprintf "Line_index: no place at offset %d" offset)

let line_of index offset =
  check_offset index offset;
  let rec search low high =
    if low >= high then low
    else
      let middle = (low + high) / 2 in
      if index.ends.(middle - 1) < offset then search (middle + 1) high
      else search low middle
  in
  search 1 (count index)

let is_character_start byte = Char.code byte land 0xC0 <> 0x80

let characters text start stop =
  let rec go offset total =
    if offset >= stop then total
    else
      go (offset + 1)
        (if is_character_start text.[offset] then total + 1 else total)
  in
  go start 0

let position index offset =
  let line = line_of index offset in
  let start = index.starts.(line - 1) in
  let stop = content_end index line in
  let column =
    if offset >= stop then 1 + characters index.text start stop
    else max 1 (characters index.text start (offset + 1))
  in
  { line; column }

let after index stop =
  if stop < 1 || stop > String.length index.text then
    invalid_arg (Printf.sprintf "Line_index: no byte before offset %d" stop);
  let place = position index (stop - 1) in
  { place with column = place.column + 1 }
