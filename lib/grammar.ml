(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type error =
  | Unreadable of Text_file.error
  | Not_loaded of Sinter_bridge.Language.error

let load engine ~path =
  match Text_file.read path with
  | Error error -> Error (Unreadable error)
  | Ok wasm -> (
      let name =
        match Grammar_name.of_wasm wasm with
        | Some name -> name
        | None -> Grammar_name.of_path path
      in
      match Sinter_bridge.Language.load engine ~name ~wasm with
      | Ok language -> Ok language
      | Error error -> Error (Not_loaded error))

let message ~path = function
  | Unreadable error -> Text_file.message path error
  | Not_loaded error ->
      Printf.sprintf "%s: the grammar does not load: %s" path
        (Sinter_bridge.Language.message error)
