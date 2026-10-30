(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let escape = '\027'
let bold = "\027[01m"
let reset = "\027[m"

let rec sequence_end text index =
  if index >= String.length text then index
  else
    match text.[index] with
    | '\x20' .. '\x3f' -> sequence_end text (index + 1)
    | _ -> index + 1

let escape_end text index =
  if index + 1 < String.length text && text.[index + 1] = '[' then
    sequence_end text (index + 2)
  else min (String.length text) (index + 2)

let plain ~quotes text =
  let buffer = Buffer.create (String.length text) in
  let rec walk index ~opened =
    if index < String.length text then
      if text.[index] = escape then
        let stop = escape_end text index in
        let code = String.sub text index (stop - index) in
        let opened =
          if quotes && String.equal code bold && not opened then (
            Buffer.add_char buffer '\'';
            true)
          else if quotes && String.equal code reset && opened then (
            Buffer.add_char buffer '\'';
            false)
          else opened
        in
        walk stop ~opened
      else (
        Buffer.add_char buffer text.[index];
        walk (index + 1) ~opened)
  in
  walk 0 ~opened:false;
  Buffer.contents buffer

let lines text =
  let text =
    if String.ends_with ~suffix:"\n" text then
      String.sub text 0 (String.length text - 1)
    else text
  in
  String.split_on_char '\n' text

let message line =
  match String.index_opt line ':' with
  | Some colon
    when colon > 0
         && colon + 1 < String.length line
         && line.[colon + 1] = ' '
         && not
              (String.exists
                 (fun c -> c = ' ' || c = escape)
                 (String.sub line 0 colon)) ->
      Some (String.sub line (colon + 2) (String.length line - colon - 2))
  | Some _ | None -> None

let usage_prefix = "Usage: "

let one_line text =
  String.concat " "
    (List.filter_map
       (fun line ->
         match String.trim (plain ~quotes:false line) with
         | "" -> None
         | line -> Some line)
       (lines text))

let error text =
  let usage_and_message =
    match lines text with
    | [ usage; line ] when String.starts_with ~prefix:usage_prefix usage ->
        Option.map
          (fun message ->
            ( String.sub usage
                (String.length usage_prefix)
                (String.length usage - String.length usage_prefix),
              message ))
          (message line)
    | _ -> None
  in
  match usage_and_message with
  | Some (usage, message) ->
      {
        Error_text.fault = plain ~quotes:true message;
        help = "usage: " ^ plain ~quotes:false usage;
        place = None;
      }
  | None -> { Error_text.fault = one_line text; help = ""; place = None }
