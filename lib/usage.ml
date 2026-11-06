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
  if
    index + 1
    < (String.length text
       [@mutaml.skip
         "the two forms differ only when index + 1 is the last index of text, \
          and there both branches give the length of text: when the last byte \
          is [, sequence_end at index + 2 gives index + 2, which is that \
          length; otherwise min gives that length. The mark also takes out the \
          mutant that adds 1 to this length, which reads the byte past the end \
          of text when an escape byte ends it"])
    && text.[index + 1] = '['
  then sequence_end text (index + 2)
  else min (String.length text) (index + 2)

let plain ~quotes text =
  let buffer =
    Buffer.create
      (String.length text
       [@mutaml.skip
         "Buffer.create takes any size and raises a size below 1 to 1; the \
          size is only the first room of a buffer that grows as it needs, and \
          no output reads it"])
  in
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
                 (String.sub line 0 colon
                  [@mutaml.skip
                    "one byte more than colon adds only the byte at colon, the \
                     colon itself, which is neither a space nor the escape \
                     code. The mark also takes out colon - 1, which leaves the \
                     last byte of the name unchecked; 1 in place of 0 and 0 + \
                     1, which leave the first byte of the name unchecked; and \
                     0 - 1, which makes String.sub raise"])) ->
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
