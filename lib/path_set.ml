(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type member = Plain of Glob.t | Excluded of Glob.t
type t = member list

type error =
  | Bad_glob of { index : int; start : int; error : Glob.error }
  | Repeated of { index : int; member : string }
  | No_plain_glob

let empty = []

let read_member index text =
  let start, glob, make =
    if String.length text > 0 && text.[0] = '!' then
      (1, String.sub text 1 (String.length text - 1), fun g -> Excluded g)
    else (0, text, fun g -> Plain g)
  in
  match Glob.of_string glob with
  | Ok glob -> Ok (make glob)
  | Error error -> Error (Bad_glob { index; start; error })

module Texts = Set.Make (String)

let of_strings texts =
  let rec read index seen members errors = function
    | [] -> (List.rev members, List.rev errors)
    | text :: rest -> (
        match read_member index text with
        | Error error -> read (index + 1) seen members (error :: errors) rest
        | Ok _ when Texts.mem text seen ->
            let error = Repeated { index; member = text } in
            read (index + 1) seen members (error :: errors) rest
        | Ok member ->
            read (index + 1) (Texts.add text seen) (member :: members) errors
              rest)
  in
  let members, errors = read 0 Texts.empty [] [] texts in
  let plain = function Plain _ -> true | Excluded _ -> false in
  match errors with
  | [] when members <> [] && not (List.exists plain members) ->
      Error [ No_plain_glob ]
  | [] -> Ok members
  | errors -> Error errors

let members set = set
let is_empty set = set = []

let mem set path =
  List.exists
    (function Plain g -> Glob.matches g path | Excluded _ -> false)
    set
  && not
       (List.exists
          (function Excluded g -> Glob.matches g path | Plain _ -> false)
          set)

let member_to_string = function
  | Plain glob -> Glob.to_string glob
  | Excluded glob -> "!" ^ Glob.to_string glob
