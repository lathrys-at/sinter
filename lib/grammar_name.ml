(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* The name of the grammar in a wasm module. The bridge needs the name,
   and the module carries it: a grammar exports one function whose
   name is "tree_sitter_" and the name of the grammar.

   The reader below walks the section list of the module and reads the
   export section. Every count and every length in that format is an
   unsigned LEB128 integer. A module that the reader cannot follow
   gives None; the loader then reports what is wrong with it. *)
let of_wasm wasm =
  let length = String.length wasm in
  let prefix = "tree_sitter_" in
  let byte offset = Char.code (String.get wasm offset) in
  let rec number offset shift value =
    if
      offset >= length
      || shift
         > (28
           [@mutaml.skip
             "shift starts at 0 and rises by 7, so it takes 0, 7, 14, 21, 28, \
              35, and never a value between 28 and 29"])
    then None
    else
      let part = byte offset in
      let value = value lor ((part land 0x7F) lsl shift) in
      if part < 0x80 then Some (value, offset + 1)
      else number (offset + 1) (shift + 7) value
  in
  let name offset =
    match number offset 0 0 with
    | Some (size, start)
      when (start + size <= length)
           [@mutaml.skip
             "the two differ for one input only, a name that ends at the end \
              of the module, and both give None there: a section never ends \
              past the module, so stop is at most length, and export then \
              finds offset >= stop"] ->
        Some (String.sub wasm start size, start + size)
    | _ -> None
  in
  let rec export offset stop count =
    if count = 0 then None
    else
      match name offset with
      | None -> None
      | Some (found, offset) -> (
          if
            (* One byte for the kind of the export, then its index. *)
            offset >= stop
          then None
          else if String.starts_with ~prefix found then
            let name =
              String.sub found (String.length prefix)
                (String.length found - String.length prefix)
            in
            (* The bridge takes the name as a C string, and a module
               can export a name that holds a NUL byte. *)
            if String.contains name '\000' then None else Some name
          else
            match
              number (offset + 1) 0
                (0
                [@mutaml.skip
                  "this caller writes Some (_, offset) and throws the value \
                   away, and the value number starts from changes neither the \
                   offset it gives back nor whether it gives None"])
            with
            | None -> None
            | Some (_, offset) -> export offset stop (count - 1))
  in
  let exports start stop =
    match number start 0 0 with
    | None -> None
    | Some (count, offset) -> export offset stop count
  in
  let rec section offset =
    if
      (offset >= length)
      [@mutaml.skip
        "the two differ for one input only, a section list that ends at the \
         end of the module, and both give None there: with offset equal to \
         length the changed test lets the reader on to number (length + 1) 0 \
         0, whose first test stops it at once"]
    then None
    else
      match number (offset + 1) 0 0 with
      | None -> None
      | Some (size, body) when body + size <= length ->
          if byte offset = 7 then exports body (body + size)
          else section (body + size)
      | Some _ -> None
  in
  if
    (length < 8)
    [@mutaml.skip
      "a module of exactly 8 bytes gives None either way: the unchanged code \
       goes on to section 8, which finds offset >= length at once"]
    || not (String.starts_with ~prefix:"\000asm" wasm)
  then None
  else
    match section 8 with
    (* The bridge loads a grammar under a C string, so a name that
       holds a NUL byte is no name at all. *)
    | Some name when String.contains name '\000' -> None
    | found -> found

let of_path path =
  let base = Filename.remove_extension (Filename.basename path) in
  let underscored = String.map (fun c -> if c = '-' then '_' else c) base in
  let prefix = "tree_sitter_" in
  let length = String.length prefix in
  if
    String.length underscored > length
    && String.equal (String.sub underscored 0 length) prefix
  then String.sub underscored length (String.length underscored - length)
  else underscored
