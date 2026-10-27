(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type t = Tree | Diff

let name = function Tree -> "tree" | Diff -> "diff"
