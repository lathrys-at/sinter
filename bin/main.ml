(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Cmdliner

let cmd =
  let doc = "plans die into residue; residue is checked" in
  let info = Cmd.info "sinter" ~version:Sinter_core.Version.current ~doc in
  Cmd.group info ~default:Term.(ret (const (`Help (`Pager, None)))) []

let () = exit (Cmd.eval cmd)
