(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* A code point is its scalar value, from 0. A byte outside a valid
   sequence is -1 less the byte, so it differs from every code point. *)
let characters text =
  let rec go i acc =
    if i >= String.length text then Array.of_list (List.rev acc)
    else
      let decoded = String.get_utf_8_uchar text i in
      if Uchar.utf_decode_is_valid decoded then
        go
          (i + Uchar.utf_decode_length decoded)
          (Uchar.to_int (Uchar.utf_decode_uchar decoded) :: acc)
      else go (i + 1) ((-1 - Char.code text.[i]) :: acc)
  in
  go 0 []

(* The algorithm of Lowrance and Wagner. [d.(i).(j)] is the distance
   between the first [i] characters of [a] and the first [j] of [b].
   [last_row] maps a character to the last row of [a] that holds it;
   [last_column] is the last column of [b], in the row [i], that holds
   the character [a.(i-1)]. *)
let distance a b =
  let a = characters a and b = characters b in
  let rows = Array.length a and columns = Array.length b in
  let d = Array.make_matrix (rows + 1) (columns + 1) 0 in
  for i = 0 to rows do
    d.(i).(0) <- i
  done;
  for j = 0 to columns do
    d.(0).(j) <- j
  done;
  let last_row = Hashtbl.create 16 in
  for i = 1 to rows do
    let last_column = ref 0 in
    for j = 1 to columns do
      let i1 = Option.value (Hashtbl.find_opt last_row b.(j - 1)) ~default:0 in
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
    Hashtbl.replace last_row a.(i - 1) i
  done;
  d.(rows).(columns)

let nearest name candidates =
  let better (distance_a, a) (distance_b, b) =
    distance_a < distance_b
    || (distance_a = distance_b && String.compare a b < 0)
  in
  List.fold_left
    (fun best candidate ->
      let found = (distance name candidate, candidate) in
      if fst found > 2 then best
      else
        match best with
        | Some known when not (better found known) -> best
        | _ -> Some found)
    None candidates
  |> Option.map snd
