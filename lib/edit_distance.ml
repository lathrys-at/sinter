(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* A character is a code point, or one byte outside a valid UTF-8
   sequence. *)
type character = Code_point of Uchar.t | Stray of char

let characters text =
  let rec go i acc =
    if i >= String.length text then Array.of_list (List.rev acc)
    else
      let decoded = String.get_utf_8_uchar text i in
      if Uchar.utf_decode_is_valid decoded then
        go
          (i + Uchar.utf_decode_length decoded)
          (Code_point (Uchar.utf_decode_uchar decoded) :: acc)
      else go (i + 1) (Stray text.[i] :: acc)
  in
  go 0 []

module Rows = Map.Make (struct
  type t = character

  let compare = compare
end)

(* The algorithm of Lowrance and Wagner. [d.(i).(j)] is the distance
   between the first [i] characters of [a] and the first [j] of [b].
   [last_row] maps a character to the last row of [a] that holds it;
   [last_column] is the last column of [b], in the row [i], that holds
   the character [a.(i-1)]. *)
let distance a b =
  let a = characters a and b = characters b in
  let rows = Array.length a and columns = Array.length b in
  let d =
    Array.init (rows + 1) (fun i ->
        Array.init (columns + 1) (fun j ->
            if i = 0 then j else if j = 0 then i else max_int))
  in
  let last_row = ref Rows.empty in
  for i = 1 to rows do
    let last_column = ref 0 in
    for j = 1 to columns do
      let i1 = Option.value (Rows.find_opt b.(j - 1) !last_row) ~default:0 in
      let j1 = !last_column in
      let cost =
        if a.(i - 1) = b.(j - 1) then begin
          last_column := j;
          0
        end
        else 1
      in
      let transposed =
        if i1 > 0 && j1 > 0 then
          d.(i1 - 1).(j1 - 1) + (i - i1 - 1) + 1 + (j - j1 - 1)
        else max_int
      in
      d.(i).(j) <-
        min
          (min (d.(i - 1).(j - 1) + cost) (d.(i).(j - 1) + 1))
          (min (d.(i - 1).(j) + 1) transposed)
    done;
    last_row := Rows.add a.(i - 1) i !last_row
  done;
  d.(rows).(columns)

(* The distance is at least the difference of the two lengths, so a
   candidate whose length differs by more than [most] is not within
   [most] edits. *)
let nearest name candidates =
  let most = 2 in
  let length text = Array.length (characters text) in
  let name_length = length name in
  List.filter
    (fun candidate -> abs (length candidate - name_length) <= most)
    candidates
  |> List.map (fun candidate -> (distance name candidate, candidate))
  |> List.filter (fun (edits, _) -> edits <= most)
  |> List.sort compare
  |> function
  | [] -> None
  | (_, candidate) :: _ -> Some candidate
