(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type t = { plan : string; step : string; hash : string }

let prefix = "Delivers: "

let make ~plan ~step ~hash =
  match (Plan_target.parse plan, Plan_target.id_of_string hash) with
  | Ok _, Some _ when Slug.is_valid step -> Some { plan; step; hash }
  | _ -> None

let to_string line = prefix ^ line.plan ^ "/" ^ line.step ^ " " ^ line.hash
let trailing = function ' ' | '\t' | '\r' -> true | _ -> false

let trimmed text =
  let rec stop index =
    if index > 0 && trailing text.[index - 1] then stop (index - 1) else index
  in
  let length = stop (String.length text) in
  if length = String.length text then text else String.sub text 0 length

let of_string text =
  let text = trimmed text in
  if not (String.starts_with ~prefix text) then None
  else
    let rest =
      String.sub text (String.length prefix)
        (String.length text - String.length prefix)
    in
    match String.split_on_char ' ' rest with
    | [ name; hash ] -> (
        match String.index_opt name '/' with
        | None -> None
        | Some slash ->
            make ~plan:(String.sub name 0 slash)
              ~step:
                (String.sub name (slash + 1) (String.length name - slash - 1))
              ~hash)
    | _ -> None

type found = { commit : string; number : int; text : string; line : t option }

let read ~commit message =
  List.concat
    (List.mapi
       (fun index line ->
         if String.starts_with ~prefix line then
           let text = trimmed line in
           [ { commit; number = index + 1; text; line = of_string text } ]
         else [])
       (String.split_on_char '\n' message))

let shown text =
  let rec pieces rest =
    match Sinter_bridge.Utf_8.first_invalid rest with
    | None -> [ rest ]
    | Some offset ->
        String.sub rest 0 offset
        :: Printf.sprintf "\\x%02x" (Char.code rest.[offset])
        :: pieces
             (String.sub rest (offset + 1) (String.length rest - offset - 1))
  in
  String.concat "" (pieces text)
