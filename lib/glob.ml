(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* [Name pattern] holds the characters of one segment, in which ['*']
   matches any sequence of bytes. *)
type segment = Any_names | Name of string
type t = { text : string; segments : segment list }

type error =
  | Empty
  | Leading_slash
  | Empty_segment of int
  | Dot_segment of { offset : int; segment : string }
  | Double_star_in_segment of { offset : int; segment : string }
  | Forbidden_character of { offset : int; character : char }

let is_forbidden = function
  | '?' | '[' | ']' | '{' | '}' | '\\' -> true
  | _ -> false

let contains_double_star segment =
  let rec from i =
    i + 1 < String.length segment
    && ((segment.[i] = '*' && segment.[i + 1] = '*') || from (i + 1))
  in
  from 0

let first_forbidden ~offset segment =
  let rec from i =
    if i >= String.length segment then None
    else if is_forbidden segment.[i] then
      Some
        (Forbidden_character { offset = offset + i; character = segment.[i] })
    else from (i + 1)
  in
  from 0

(* [check ~offset segment] is the error of one segment that is not the
   empty last segment, which a final '/' makes. *)
let check ~offset segment =
  if segment = "" then Some (Empty_segment offset)
  else if segment = "." || segment = ".." then
    Some (Dot_segment { offset; segment })
  else if segment <> "**" && contains_double_star segment then
    Some (Double_star_in_segment { offset; segment })
  else first_forbidden ~offset segment

let of_string text =
  if text = "" then Error Empty
  else if text.[0] = '/' then Error Leading_slash
  else
    let rec read offset acc = function
      | [] -> Ok { text; segments = List.rev acc }
      | [ "" ] -> Ok { text; segments = List.rev (Any_names :: acc) }
      | segment :: rest -> (
          match check ~offset segment with
          | Some error -> Error error
          | None ->
              let parsed = if segment = "**" then Any_names else Name segment in
              read (offset + String.length segment + 1) (parsed :: acc) rest)
    in
    read 0 [] (String.split_on_char '/' text)

let to_string glob = glob.text

(* The first offset at or after [from] where [part] occurs in [name]
   and ends at or before [limit]. *)
let rec find name part ~from ~limit =
  if from + String.length part > limit then None
  else if String.sub name from (String.length part) = part then Some from
  else find name part ~from:(from + 1) ~limit

(* The match of one name against one segment. The segment is pieces
   between the '*' of it: the name starts with the first piece, ends
   with the last, and holds the pieces between them in order, each at
   its first place after the one before. *)
let name_matches pattern name =
  match String.split_on_char '*' pattern with
  | [] | [ _ ] -> String.equal pattern name
  | first :: rest ->
      let last = List.nth rest (List.length rest - 1) in
      let middle = List.filteri (fun i _ -> i < List.length rest - 1) rest in
      let limit = String.length name - String.length last in
      let rec inside from = function
        | [] -> true
        | part :: parts -> (
            match find name part ~from ~limit with
            | Some at -> inside (at + String.length part) parts
            | None -> false)
      in
      String.length first <= limit
      && String.starts_with ~prefix:first name
      && String.ends_with ~suffix:last name
      && inside (String.length first) middle

(* [reachable.(j)] is [true] when the segments read so far match the
   first [j] names. *)
let matches glob path =
  let names = Array.of_list (String.split_on_char '/' path) in
  let count = Array.length names in
  let rec walk reachable = function
    | [] -> reachable.(count)
    | [ Any_names ] ->
        let rec some_before j =
          j < count && (reachable.(j) || some_before (j + 1))
        in
        some_before 0
    | Any_names :: rest ->
        let next = Array.make (count + 1) false in
        let seen = ref false in
        for j = 0 to count do
          seen := !seen || reachable.(j);
          next.(j) <- !seen
        done;
        walk next rest
    | Name pattern :: rest ->
        let next = Array.make (count + 1) false in
        for j = 0 to count - 1 do
          next.(j + 1) <- reachable.(j) && name_matches pattern names.(j)
        done;
        walk next rest
  in
  let start = Array.make (count + 1) false in
  start.(0) <- true;
  walk start glob.segments

let error_offset = function
  | Empty | Leading_slash -> 0
  | Empty_segment offset
  | Dot_segment { offset; _ }
  | Double_star_in_segment { offset; _ }
  | Forbidden_character { offset; _ } ->
      offset

(* The segment [**rest], where [rest] holds no '*' at its start and no
   "**", meant every file at any depth whose name ends with [rest]. *)
let suggestion segment =
  let length = String.length segment in
  if length > 2 && String.sub segment 0 2 = "**" && segment.[2] <> '*' then
    let rest = String.sub segment 2 (length - 2) in
    if contains_double_star rest then None else Some ("**/*" ^ rest)
  else None

let message = function
  | Empty -> "a glob cannot be empty"
  | Leading_slash ->
      "a glob cannot start with '/'; a glob always matches from the repository \
       root"
  | Empty_segment _ -> "a glob cannot hold two '/' together"
  | Dot_segment { segment; _ } ->
      Printf.sprintf "a glob cannot hold the segment '%s'" segment
  | Double_star_in_segment { segment; _ } -> (
      let start =
        Printf.sprintf "the segment '%s' holds '**' and other characters"
          segment
      in
      match suggestion segment with
      | Some better -> Printf.sprintf "%s; write '%s'" start better
      | None ->
          start
          ^ "; '**' must be a whole segment, and '*' matches characters inside \
             one name")
  | Forbidden_character { character; _ } ->
      let advice =
        match character with
        | '?' -> "; '*' matches any characters inside one name"
        | '[' | ']' -> "; write one glob for each name"
        | '{' | '}' -> "; write one glob for each choice"
        | _ -> ""
      in
      Printf.sprintf "a glob cannot hold '%c'%s" character advice
