(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Cmdliner

(* An opam release build carries the package version; print it. A
   development build carries none, so use "git describe": on a tagged
   commit it is the tag; otherwise it is a bare hash (no dot), and the
   next planned release version is prefixed. *)
let version =
  match Build_info.V1.version () with
  | Some v ->
      let s = Build_info.V1.Version.to_string v in
      if s <> "" && s.[0] <> 'v' then "v" ^ s else s
  | None ->
      let d = Sinter_core.Git_version.describe in
      if String.contains d '.' then d
      else if d = "unknown" then "v" ^ Sinter_core.Version.base ^ "-dev"
      else "v" ^ Sinter_core.Version.base ^ "-dev+" ^ d

let cmd =
  let doc = "plans die into residue; residue is checked" in
  let info = Cmd.info "sinter" ~version ~doc in
  Cmd.group info ~default:Term.(ret (const (`Help (`Pager, None)))) []

let () = exit (Cmd.eval cmd)
