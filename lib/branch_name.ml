(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type error =
  | Empty
  | Full_ref_name
  | Bad_character of { offset : int; character : char }
  | Two_dots of int
  | At_brace of int
  | Empty_component of int
  | Component_starts_with_dot of int
  | Component_ends_with_lock of int
  | Ends_with_dot of int

let is_bad = function
  | '\000' .. '\031' | '\127' | ' ' | '~' | '^' | ':' | '?' | '*' | '[' | '\\'
    ->
      true
  | _ -> false

(* [component name start] checks the component of [name] that starts
   at [start], and gives the offset of the '/' or of the end of
   [name] that closes it. *)
let component name start =
  let length = String.length name in
  let rec scan i last =
    if i >= length || name.[i] = '/' then Ok i
    else
      let c = name.[i] in
      if is_bad c then Error (Bad_character { offset = i; character = c })
      else if c = '.' && last = '.' then Error (Two_dots (i - 1))
      else if c = '{' && last = '@' then Error (At_brace (i - 1))
      else scan (i + 1) c
  in
  match scan start '\000' with
  | Error _ as error -> error
  | Ok stop when stop = start -> Error (Empty_component start)
  | Ok _ when name.[start] = '.' -> Error (Component_starts_with_dot start)
  | Ok stop
    when String.ends_with ~suffix:".lock" (String.sub name start (stop - start))
    ->
      Error (Component_ends_with_lock (stop - 5))
  | Ok stop -> Ok stop

let check name =
  let length = String.length name in
  let rec components start =
    match component name start with
    | Error error -> Error error
    | Ok stop when stop < length -> components (stop + 1)
    | Ok _ when name.[length - 1] = '.' -> Error (Ends_with_dot (length - 1))
    | Ok _ -> Ok ()
  in
  if name = "" then Error Empty
  else if String.starts_with ~prefix:"refs/" name then Error Full_ref_name
  else components 0

let error_offset = function
  | Empty | Full_ref_name -> 0
  | Bad_character { offset; _ } -> offset
  | Two_dots offset
  | At_brace offset
  | Empty_component offset
  | Component_starts_with_dot offset
  | Component_ends_with_lock offset
  | Ends_with_dot offset ->
      offset

let message = function
  | Empty -> "a branch name cannot be empty"
  | Full_ref_name ->
      "a branch name cannot start with 'refs/'; write the name of the branch \
       alone, such as 'main'"
  | Bad_character { character = ' '; _ } -> "a branch name cannot hold a space"
  | Bad_character { character; _ } when character < ' ' || character = '\127' ->
      "a branch name cannot hold a control character"
  | Bad_character { character; _ } ->
      Printf.sprintf "a branch name cannot hold '%c'" character
  | Two_dots _ -> "a branch name cannot hold '..'"
  | At_brace _ -> "a branch name cannot hold '@{'"
  | Empty_component _ ->
      "a branch name cannot start or end with '/', or hold two '/' together"
  | Component_starts_with_dot _ ->
      "no part of a branch name between two '/' can start with '.'"
  | Component_ends_with_lock _ ->
      "no part of a branch name between two '/' can end with '.lock'"
  | Ends_with_dot _ -> "a branch name cannot end with '.'"
