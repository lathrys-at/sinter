(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type t = { root : string; files : (string, Line_index.t option) Hashtbl.t }

let create ~root = { root; files = Hashtbl.create 64 }

let read source path =
  let full =
    if Filename.is_relative path then Filename.concat source.root path else path
  in
  Result.to_option (Result.map Line_index.make (Text_file.read_text full))

let file source path =
  match Hashtbl.find_opt source.files path with
  | Some lines -> lines
  | None ->
      let lines = read source path in
      Hashtbl.add source.files path lines;
      lines

let line source path number =
  Option.bind (file source path) (fun lines ->
      if number >= 1 && number <= Line_index.count lines then
        Some (Line_index.content lines number)
      else None)
