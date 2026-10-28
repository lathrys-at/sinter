(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let is_character_start byte = Char.code byte land 0xC0 <> 0x80

let offset lines (line, column) =
  let text = Line_index.text lines in
  let stop = Line_index.content_end lines line in
  let rec walk offset remaining =
    if remaining = 0 then offset
    else if offset >= stop then
      invalid_arg "Edits.apply: the column is past the line"
    else
      let rec next offset =
        if offset < stop && not (is_character_start text.[offset]) then
          next (offset + 1)
        else offset
      in
      walk (next (offset + 1)) (remaining - 1)
  in
  walk (Line_index.first lines line) (column - 1)

let apply text (edits : Fix.edit list) =
  let lines = Line_index.make text in
  let placed =
    List.sort
      (fun (a, _, _) (b, _, _) -> Int.compare b a)
      (List.map
         (fun (edit : Fix.edit) ->
           ( offset lines (edit.line, edit.col),
             offset lines (edit.eline, edit.ecol),
             edit.text ))
         edits)
  in
  List.fold_left
    (fun text (start, stop, inserted) ->
      String.sub text 0 start ^ inserted
      ^ String.sub text stop (String.length text - stop))
    text placed

let reader =
  lazy
    (match Markdown.create (Sinter_bridge.create ()) with
    | Ok reader -> reader
    | Error _ -> failwith "the reader does not start")

let document text =
  match Markdown.read (Lazy.force reader) text with
  | Ok document -> document
  | Error _ -> failwith "the text gives no document"

let tag text = (document text).tags.(0)
let word_fix word = Fix.word (tag "@x a\n") word
