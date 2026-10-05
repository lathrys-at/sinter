(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let digest data = Sinter_bridge.sha256 data
let digits = "0123456789abcdef"

let hex data =
  let raw = digest data in
  String.init
    (2 * String.length raw)
    (fun index ->
      let byte = Char.code raw.[index / 2] in
      let nibble = if index mod 2 = 0 then byte lsr 4 else byte land 0xF in
      digits.[nibble])
