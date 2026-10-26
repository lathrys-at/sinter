(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type t = { word : string; rest : string }

let is_blank = function ' ' | '\t' -> true | _ -> false

let is_alphanumeric = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' -> true
  | _ -> false

let rec skip keep text offset =
  if offset < String.length text && keep text.[offset] then
    skip keep text (offset + 1)
  else offset

let read text =
  let at = skip is_blank text 0 in
  if at < String.length text && text.[at] = '@' then
    let stop =
      skip (fun byte -> is_alphanumeric byte || byte = '-') text (at + 1)
    in
    Some
      ( at,
        {
          word = String.sub text (at + 1) (stop - at - 1);
          rest = String.sub text stop (String.length text - stop);
        } )
  else None

type parts = {
  target : string option;
  revision : int option;
  description : string;
}

let largest_revision = 9_007_199_254_740_991

let revision token =
  if String.starts_with ~prefix:"v" token then
    let digits = String.sub token 1 (String.length token - 1) in
    if
      (not (String.starts_with ~prefix:"0" digits))
      && String.for_all (function '0' .. '9' -> true | _ -> false) digits
    then
      match int_of_string_opt digits with
      | Some value when value <= largest_revision -> Some value
      | Some _ | None -> None
    else None
  else None

let is_token_byte byte = not (is_blank byte)

let tokens rest =
  let start = skip is_blank rest 0 in
  if start >= String.length rest then None
  else
    let stop = skip is_token_byte rest start in
    let next = skip is_blank rest stop in
    let next_stop = skip is_token_byte rest next in
    let second = String.sub rest next (next_stop - next) in
    Some
      ( start,
        stop,
        Option.map (fun value -> (next_stop, value)) (revision second) )

let tail text offset = String.sub text offset (String.length text - offset)

let parts rest =
  match tokens rest with
  | None -> { target = None; revision = None; description = "" }
  | Some (start, stop, None) ->
      {
        target = Some (String.sub rest start (stop - start));
        revision = None;
        description = tail rest stop;
      }
  | Some (start, stop, Some (revision_stop, value)) ->
      {
        target = Some (String.sub rest start (stop - start));
        revision = Some value;
        description = tail rest revision_stop;
      }

let without_revision rest =
  match tokens rest with
  | Some (_, stop, Some (revision_stop, _)) ->
      String.sub rest 0 stop ^ tail rest revision_stop
  | Some (_, _, None) | None -> rest
