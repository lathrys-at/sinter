(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type id = string

let is_hex_digit = function '0' .. '9' | 'a' .. 'f' -> true | _ -> false

let id_of_string text =
  if String.length text = 6 && String.for_all is_hex_digit text then Some text
  else None

type t = { slug : string; id : id option }
type error = Invalid_slug of string | Invalid_id of string

let parse text =
  let slug, id =
    match String.index_opt text '@' with
    | None -> (text, None)
    | Some at ->
        ( String.sub text 0 at,
          Some (String.sub text (at + 1) (String.length text - at - 1)) )
  in
  if not (Slug.is_valid slug) then Error (Invalid_slug slug)
  else
    match id with
    | None -> Ok { slug; id = None }
    | Some text -> (
        match id_of_string text with
        | Some id -> Ok { slug; id = Some id }
        | None -> Error (Invalid_id text))

let to_string { slug; id } =
  match id with None -> slug | Some id -> slug ^ "@" ^ id
