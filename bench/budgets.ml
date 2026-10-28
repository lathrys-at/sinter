(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

type t = { scan : float; check : float; check_diff : float option }

let commands = [ "scan"; "check"; "check-diff" ]
let keys = [ "allocation-growth" ]

let unknown ~where names allowed =
  List.find_opt (fun name -> not (List.mem name allowed)) names
  |> Option.map (fun name -> Printf.sprintf "%s: unknown key %s" where name)

let find (table : Toml.table) name =
  List.find_map
    (fun ((key : Toml.key), node) ->
      if String.equal key.name name then Some (Toml.value node) else None)
    table

let names (table : Toml.table) =
  List.map (fun ((key : Toml.key), _) -> key.name) table

let ( let* ) = Result.bind

let limit (table : Toml.table) command =
  let* table =
    match find table command with
    | Some (Toml.Table table) -> Ok table
    | Some value ->
        Error
          (Printf.sprintf "[%s] is %s, not a table" command
             (Toml.Kind.name (Toml.Kind.of_value value)))
    | None -> Error (Printf.sprintf "the table [%s] is missing" command)
  in
  let* () =
    match unknown ~where:("[" ^ command ^ "]") (names table) keys with
    | Some message -> Error message
    | None -> Ok ()
  in
  let key = command ^ ".allocation-growth" in
  match find table "allocation-growth" with
  | Some (Toml.Integer value) when Int64.compare value 0L > 0 ->
      Ok (Int64.to_float value)
  | Some (Toml.Float value) when value > 0. && Float.is_finite value -> Ok value
  | Some _ -> Error (key ^ " is not a positive number")
  | None -> Error (key ^ " is missing")

let of_string text =
  match Toml.parse text with
  | Error error ->
      let at = Toml.error_position error in
      Error
        (Printf.sprintf "line %d, column %d: %s" at.line at.column
           (Toml.error_message error))
  | Ok table ->
      let* () =
        match unknown ~where:"the budgets" (names table) commands with
        | Some message -> Error message
        | None -> Ok ()
      in
      let* scan = limit table "scan" in
      let* check = limit table "check" in
      let* check_diff =
        match find table "check-diff" with
        | None -> Ok None
        | Some _ -> Result.map Option.some (limit table "check-diff")
      in
      Ok { scan; check; check_diff }

let growth budgets = function
  | "scan" -> Some budgets.scan
  | "check" -> Some budgets.check
  | "check-diff" -> budgets.check_diff
  | _ -> None

type verdict = Pass of float | Fail of float | Skipped of string

type outcome = {
  command : string;
  phase : string option;
  limit : float;
  verdict : verdict;
}

let judge limit value = if value <= limit then Pass value else Fail value

let check budgets ~words =
  List.concat_map
    (fun (command, limit) ->
      let outcome phase verdict = { command; phase; limit; verdict } in
      let small = words ~tree:"n1000" ~command in
      match words ~tree:"n10000" ~command with
      | [] ->
          [
            outcome None
              (Skipped
                 "the run counted no phase on the tree n1000 or on the tree \
                  n10000");
          ]
      | large ->
          List.map
            (fun (phase, words) ->
              outcome (Some phase)
                (match List.assoc_opt phase small with
                | Some base when base > 0. -> judge limit (words /. base)
                | Some _ | None ->
                    Skipped "the tree n1000 counts no word in the phase"))
            large)
    ([ ("scan", budgets.scan); ("check", budgets.check) ]
    @ Option.fold ~none:[]
        ~some:(fun limit -> [ ("check-diff", limit) ])
        budgets.check_diff)
