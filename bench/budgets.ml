(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

type limits = { all : float; phases : (string * float) list }

type t = {
  scan : limits;
  check : limits;
  check_diff : limits option;
  ledger_log : limits option;
  ledger_verify : limits option;
}

let commands = [ "scan"; "check"; "check-diff"; "ledger-log"; "ledger-verify" ]
let keys = [ "allocation-growth"; "phases" ]

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
  let positive key = function
    | Some (Toml.Integer value) when Int64.compare value 0L > 0 ->
        Ok (Int64.to_float value)
    | Some (Toml.Float value) when value > 0. && Float.is_finite value ->
        Ok value
    | Some _ -> Error (key ^ " is not a positive number")
    | None -> Error (key ^ " is missing")
  in
  let* all =
    positive (command ^ ".allocation-growth") (find table "allocation-growth")
  in
  let* phases =
    match find table "phases" with
    | None -> Ok []
    | Some (Toml.Table phases) ->
        List.fold_left
          (fun found ((key : Toml.key), node) ->
            let* found = found in
            let* limit =
              positive
                (command ^ ".phases." ^ key.name)
                (Some (Toml.value node))
            in
            Ok (found @ [ (key.name, limit) ]))
          (Ok []) phases
    | Some value ->
        Error
          (Printf.sprintf "%s.phases is %s, not a table" command
             (Toml.Kind.name (Toml.Kind.of_value value)))
  in
  Ok { all; phases }

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
      let optional command =
        match find table command with
        | None -> Ok None
        | Some _ -> Result.map Option.some (limit table command)
      in
      let* check_diff = optional "check-diff" in
      let* ledger_log = optional "ledger-log" in
      let* ledger_verify = optional "ledger-verify" in
      Ok { scan; check; check_diff; ledger_log; ledger_verify }

let limits budgets = function
  | "scan" -> Some budgets.scan
  | "check" -> Some budgets.check
  | "check-diff" -> budgets.check_diff
  | "ledger-log" -> budgets.ledger_log
  | "ledger-verify" -> budgets.ledger_verify
  | _ -> None

let growth budgets command =
  Option.map (fun limits -> limits.all) (limits budgets command)

let trees = function
  | "ledger-log" | "ledger-verify" -> ("l1000", "l100000")
  | _ -> ("n1000", "n10000")

type verdict = Pass of float | Fail of float | Skipped of string

type outcome = {
  command : string;
  phase : string option;
  limit : float;
  verdict : verdict;
}

let judge limit value = if value <= limit then Pass value else Fail value

let commas = function
  | [] -> "none"
  | [ one ] -> one
  | [ first; second ] -> first ^ " and " ^ second
  | names -> (
      match List.rev names with
      | last :: earlier ->
          String.concat ", " (List.rev earlier) ^ ", and " ^ last
      | [] -> "none")

let check budgets ~words =
  let commands =
    [ ("scan", budgets.scan); ("check", budgets.check) ]
    @ List.filter_map
        (fun (command, limits) ->
          Option.map (fun limits -> (command, limits)) limits)
        [
          ("check-diff", budgets.check_diff);
          ("ledger-log", budgets.ledger_log);
          ("ledger-verify", budgets.ledger_verify);
        ]
  in
  let unknown =
    List.find_map
      (fun (command, limits) ->
        match List.map fst (words ~tree:(snd (trees command)) ~command) with
        | [] -> None
        | phases ->
            List.find_map
              (fun (name, _) ->
                if List.mem name phases then None
                else
                  Some
                    (Printf.sprintf
                       "%s.phases.%s names no phase of %s; its phases are %s"
                       command name command (commas phases)))
              limits.phases)
      commands
  in
  match unknown with
  | Some message -> Error message
  | None ->
      Ok
        (List.concat_map
           (fun (command, limits) ->
             let limit = function
               | Some phase ->
                   Option.value
                     (List.assoc_opt phase limits.phases)
                     ~default:limits.all
               | None -> limits.all
             in
             let outcome phase verdict =
               { command; phase; limit = limit phase; verdict }
             in
             let small_tree, large_tree = trees command in
             let small = words ~tree:small_tree ~command in
             match words ~tree:large_tree ~command with
             | [] ->
                 [
                   outcome None
                     (Skipped
                        (Printf.sprintf
                           "the run counted no phase on the tree %s or on the \
                            tree %s"
                           small_tree large_tree));
                 ]
             | large ->
                 List.map
                   (fun (phase, words) ->
                     outcome (Some phase)
                       (match List.assoc_opt phase small with
                       | Some base when base > 0. ->
                           judge (limit (Some phase)) (words /. base)
                       | Some _ | None ->
                           Skipped
                             (Printf.sprintf
                                "the tree %s counts no word in the phase"
                                small_tree)))
                   large)
           commands)
