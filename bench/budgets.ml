(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

type limits = { peak_kib : int option; growth : float }
type t = { scan : limits; check : limits; check_diff : limits option }

let commands = [ "scan"; "check"; "check-diff" ]
let keys = [ "peak-memory-kib"; "allocation-growth" ]

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

let limits (table : Toml.table) command =
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
  let key name = Printf.sprintf "%s.%s" command name in
  let* peak_kib =
    match find table "peak-memory-kib" with
    | Some (Toml.Integer value) when Int64.compare value 0L > 0 ->
        Ok (Some (Int64.to_int value))
    | Some _ -> Error (key "peak-memory-kib" ^ " is not a positive integer")
    | None when String.equal command "check-diff" -> Ok None
    | None -> Error (key "peak-memory-kib" ^ " is missing")
  in
  let* growth =
    match find table "allocation-growth" with
    | Some (Toml.Integer value) when Int64.compare value 0L > 0 ->
        Ok (Int64.to_float value)
    | Some (Toml.Float value) when value > 0. && Float.is_finite value ->
        Ok value
    | Some _ -> Error (key "allocation-growth" ^ " is not a positive number")
    | None -> Error (key "allocation-growth" ^ " is missing")
  in
  Ok { peak_kib; growth }

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
      let* scan = limits table "scan" in
      let* check = limits table "check" in
      let* check_diff =
        match find table "check-diff" with
        | None -> Ok None
        | Some _ -> Result.map Option.some (limits table "check-diff")
      in
      Ok { scan; check; check_diff }

let limits_of budgets = function
  | "scan" -> Some budgets.scan
  | "check" -> Some budgets.check
  | "check-diff" -> budgets.check_diff
  | _ -> None

let peak_kib budgets command =
  Option.bind (limits_of budgets command) (fun limits -> limits.peak_kib)

let growth budgets command =
  Option.map (fun limits -> limits.growth) (limits_of budgets command)

type verdict = Pass of float | Fail of float | Skipped of string

type outcome = {
  command : string;
  budget : string;
  phase : string option;
  limit : float;
  verdict : verdict;
}

let judge limit value = if value <= limit then Pass value else Fail value

let check budgets ~linux ~peak ~words =
  List.concat_map
    (fun (command, limits) ->
      let memory =
        Option.map
          (fun kib ->
            let limit = float_of_int kib in
            let verdict =
              if not linux then Skipped "the memory budget is a Linux number"
              else
                match peak ~tree:"n10000" ~command with
                | Some value -> judge limit value
                | None -> Skipped "the run did not measure the tree n10000"
            in
            {
              command;
              budget = "peak-memory-kib";
              phase = None;
              limit;
              verdict;
            })
          limits.peak_kib
      in
      let growth phase verdict =
        {
          command;
          budget = "allocation-growth";
          phase;
          limit = limits.growth;
          verdict;
        }
      in
      let small = words ~tree:"n1000" ~command in
      let growths =
        match words ~tree:"n10000" ~command with
        | [] ->
            [
              growth None
                (Skipped
                   "the run counted no phase on the tree n1000 or on the tree \
                    n10000");
            ]
        | large ->
            List.map
              (fun (phase, words) ->
                growth (Some phase)
                  (match List.assoc_opt phase small with
                  | Some base when base > 0. ->
                      judge limits.growth (words /. base)
                  | Some _ | None ->
                      Skipped "the tree n1000 counts no word in the phase"))
              large
      in
      Option.to_list memory @ growths)
    ([ ("scan", budgets.scan); ("check", budgets.check) ]
    @ Option.fold ~none:[]
        ~some:(fun limits -> [ ("check-diff", limits) ])
        budgets.check_diff)
