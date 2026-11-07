(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Paths = Set.Make (String)

type t = {
  root : string;
  manifest : string;
  readable : Paths.t;
  files : (string, Line_index.t option) Hashtbl.t;
}

let create ~root ~manifest ~files =
  {
    root;
    manifest;
    readable = Paths.of_list files;
    files =
      Hashtbl.create
        (64
        [@mutaml.skip
          "the number is only the first size of a table that grows as it \
           needs, and the code reads the table only by its keys, never in its \
           order"]);
  }

let read_text source path =
  Option.bind
    (Result.to_option (Repo_file.read ~root:source.root path))
    (fun content ->
      if Sinter_bridge.Utf_8.is_valid content then Some content else None)

let read source path =
  if
    Filename.is_relative path
    && (String.equal path source.manifest || Paths.mem path source.readable)
  then Option.map Line_index.make (read_text source path)
  else None

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
