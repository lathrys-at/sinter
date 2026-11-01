(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let refused path =
  match Unix.openfile path [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 with
  | descriptor ->
      Unix.close descriptor;
      false
  | exception Unix.Unix_error ((Unix.EACCES | Unix.EPERM), _, _) -> true

let with_unreadable path f =
  let permissions = (Unix.stat path).Unix.st_perm in
  Unix.chmod path 0o000;
  Fun.protect
    ~finally:(fun () -> Unix.chmod path permissions)
    (fun () -> if refused path then Some (f ()) else None)
