(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let key_path key =
  if
    key = []
    || List.exists
         (fun name ->
           name = "" || String.contains name '.' || String.contains name '=')
         key
  then invalid_arg "Fact_id: a key path needs names without '.' and '='"
  else String.concat "." key

let setting key = "setting:" ^ key_path key
let member key value = "setting:" ^ key_path key ^ "=" ^ value

let gate gate finding_class =
  Printf.sprintf "gate:%s/%s"
    (Finding_class.gate_name gate)
    (Finding_class.name finding_class)

let tombstone was = "tombstone:" ^ was
