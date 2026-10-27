(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type t = { mutable phases : (string * int) list }

let variable = "SINTER_PHASE_WORDS"
let create () = { phases = [] }

let words () =
  let minor, promoted, major = Gc.counters () in
  minor +. major -. promoted

let add counts name words =
  counts.phases <-
    (if List.mem_assoc name counts.phases then
       List.map
         (fun (phase, total) ->
           if String.equal phase name then (phase, total + words)
           else (phase, total))
         counts.phases
     else counts.phases @ [ (name, words) ])

let measure phases name f =
  match phases with
  | None -> f ()
  | Some counts ->
      let before = words () in
      let result = f () in
      let after = words () in
      add counts name (int_of_float (after -. before));
      result

let phases counts = counts.phases

let to_string counts =
  String.concat ""
    (List.map
       (fun (name, words) -> Printf.sprintf "%s %d\n" name words)
       counts.phases)
