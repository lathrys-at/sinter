(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type t = { word : string; rest : string }

let is_blank = function ' ' | '\t' -> true | _ -> false

let is_alphanumeric = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' -> true
  | _ -> false

(* The first offset from [offset] whose byte [keep] refuses, or the
   length of [text]. *)
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

(* 2^53 - 1, the largest integer of a JSON Lines record, has 16
   digits. *)
let largest_revision = 9_007_199_254_740_991

let revision token =
  let digits = String.length token - 1 in
  if
    digits >= 1 && digits <= 16
    && token.[0] = 'v'
    && token.[1] <> '0'
    && String.for_all
         (function '0' .. '9' -> true | _ -> false)
         (String.sub token 1 digits)
  then
    let value = int_of_string (String.sub token 1 digits) in
    if value <= largest_revision then Some value else None
  else None

let is_token_byte byte = not (is_blank byte)

(* The offsets of the target token and of the revision token, when
   they exist: [(target_start, target_stop, revision)] with [revision]
   the start and the stop of the revision token and its value. *)
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
