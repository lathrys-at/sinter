(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let base = "0.1.0"

let render ~package ~describe =
  match package with
  | Some s -> if s <> "" && s.[0] <> 'v' then "v" ^ s else s
  | None ->
      if String.contains describe '.' then describe
      else if describe = "unknown" then "v" ^ base ^ "-dev"
      else "v" ^ base ^ "-dev+" ^ describe
