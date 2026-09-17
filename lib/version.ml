(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let base = "0.1.0"

(* An opam release build carries the version of the package; print
   that. A build that dune makes carries none, so read the
   description of the checkout instead: on a tagged commit it holds
   the tag, and otherwise it is a bare hash with no full stop in it,
   which the version of the next planned release goes in front of. *)
let render ~package ~describe =
  match package with
  | Some s -> if s <> "" && s.[0] <> 'v' then "v" ^ s else s
  | None ->
      if String.contains describe '.' then describe
      else if describe = "unknown" then "v" ^ base ^ "-dev"
      else "v" ^ base ^ "-dev+" ^ describe
