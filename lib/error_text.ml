(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type place = { path : string; span : Toml.span; line : string option }
type t = { fault : string; help : string; place : place option }

let fault_of_sinter = "report this as a fault of sinter"
let output_help = "check that the output stays open and that the disk has space"
