(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type row = {
  tree : string;
  declarations : int option;
  command : string;
  exit_code : int;
  peak_kib : Measurement.summary;
  instructions : Measurement.summary option;
  footprint_kib : Measurement.summary option;
  phase_words : (string * float) list;
}

type t = {
  platform : string;
  instruction_counter : string option;
  no_count_reason : string option;
  runs : int;
  seed : int;
  rows : row list;
}

let first_row report ~tree ~command =
  List.find_opt
    (fun row -> String.equal row.tree tree && String.equal row.command command)
    report.rows

let peak report ~tree ~command =
  Option.map
    (fun row -> row.peak_kib.Measurement.median)
    (first_row report ~tree ~command)

let instructions report ~tree ~command =
  Option.bind (first_row report ~tree ~command) (fun row ->
      Option.map
        (fun (summary : Measurement.summary) -> summary.median)
        row.instructions)

let words report ~tree ~command =
  Option.fold ~none:[]
    ~some:(fun row -> row.phase_words)
    (first_row report ~tree ~command)

let summary_json (summary : Measurement.summary) =
  `Assoc
    [
      ("median", `Float summary.median);
      ("min", `Float summary.min);
      ("max", `Float summary.max);
      ("spread_percent", `Float summary.spread);
    ]

let option_json json = function None -> `Null | Some value -> json value
let string_json text = `String text

let verdict_json (verdict : Budgets.verdict) =
  match verdict with
  | Pass value -> [ ("result", `String "pass"); ("value", `Float value) ]
  | Fail value -> [ ("result", `String "fail"); ("value", `Float value) ]
  | Skipped reason ->
      [ ("result", `String "skipped"); ("reason", `String reason) ]

let to_json report outcomes =
  `Assoc
    [
      ("platform", `String report.platform);
      ("instruction_counter", option_json string_json report.instruction_counter);
      ("no_count_reason", option_json string_json report.no_count_reason);
      ("runs", `Int report.runs);
      ("seed", `Int report.seed);
      ( "results",
        `List
          (List.map
             (fun row ->
               `Assoc
                 [
                   ("tree", `String row.tree);
                   ( "declarations",
                     option_json (fun count -> `Int count) row.declarations );
                   ("command", `String row.command);
                   ("exit", `Int row.exit_code);
                   ("peak_kib", summary_json row.peak_kib);
                   ("instructions", option_json summary_json row.instructions);
                   ("footprint_kib", option_json summary_json row.footprint_kib);
                   ( "phase_words",
                     `List
                       (List.map
                          (fun (phase, words) ->
                            `Assoc
                              [
                                ("phase", `String phase); ("words", `Float words);
                              ])
                          row.phase_words) );
                 ])
             report.rows) );
      ( "budgets",
        `List
          (List.map
             (fun (outcome : Budgets.outcome) ->
               `Assoc
                 ([
                    ("command", `String outcome.command);
                    ("budget", `String outcome.budget);
                    ("phase", option_json string_json outcome.phase);
                    ("limit", `Float outcome.limit);
                  ]
                 @ verdict_json outcome.verdict))
             outcomes) );
    ]

let ( let* ) = Result.bind

let field name = function
  | `Assoc fields -> (
      match List.assoc_opt name fields with
      | Some value -> Ok value
      | None -> Error (Printf.sprintf "the key %s is missing" name))
  | _ -> Error (Printf.sprintf "the key %s is not in an object" name)

let wrong name kind = Error (Printf.sprintf "%s is not %s" name kind)

let as_string name = function
  | `String text -> Ok text
  | _ -> wrong name "a string"

let as_int name = function
  | `Int value -> Ok value
  | _ -> wrong name "an integer"

let as_float name = function
  | `Float value -> Ok value
  | `Int value -> Ok (float_of_int value)
  | _ -> wrong name "a number"

let as_option name read = function
  | `Null -> Ok None
  | value -> Result.map Option.some (read name value)

let read name read json =
  let* value = field name json in
  read name value

let summary name json =
  match json with
  | `Assoc _ ->
      let* median = read "median" as_float json in
      let* min = read "min" as_float json in
      let* max = read "max" as_float json in
      let* spread = read "spread_percent" as_float json in
      Ok { Measurement.median; min; max; spread }
  | _ -> wrong name "an object"

let phases name = function
  | `List items ->
      List.fold_right
        (fun item phases ->
          let* phases = phases in
          let* phase = read "phase" as_string item in
          let* words = read "words" as_float item in
          Ok ((phase, words) :: phases))
        items (Ok [])
  | _ -> wrong name "an array"

let row json =
  let* tree = read "tree" as_string json in
  let* declarations =
    read "declarations" (fun name -> as_option name as_int) json
  in
  let* command = read "command" as_string json in
  let* exit_code = read "exit" as_int json in
  let* peak_kib = read "peak_kib" summary json in
  let* instructions =
    read "instructions" (fun name -> as_option name summary) json
  in
  let* footprint_kib =
    read "footprint_kib" (fun name -> as_option name summary) json
  in
  let* phase_words = read "phase_words" phases json in
  Ok
    {
      tree;
      declarations;
      command;
      exit_code;
      peak_kib;
      instructions;
      footprint_kib;
      phase_words;
    }

let rows name = function
  | `List items ->
      List.fold_right
        (fun item rows ->
          let* rows = rows in
          let* row = row item in
          Ok (row :: rows))
        items (Ok [])
  | _ -> wrong name "an array"

let of_json json =
  let* platform = read "platform" as_string json in
  let* instruction_counter =
    read "instruction_counter" (fun name -> as_option name as_string) json
  in
  let* no_count_reason =
    read "no_count_reason" (fun name -> as_option name as_string) json
  in
  let* runs = read "runs" as_int json in
  let* seed = read "seed" as_int json in
  let* rows = read "results" rows json in
  Ok { platform; instruction_counter; no_count_reason; runs; seed; rows }

let of_string text =
  match Yojson.Basic.from_string text with
  | json -> of_json json
  | exception Yojson.Json_error message -> Error ("not JSON: " ^ message)

let cell ~scale ~digits = function
  | None -> "-"
  | Some (summary : Measurement.summary) ->
      Printf.sprintf "%.*f [%.1f%%]" digits (summary.median /. scale)
        summary.spread

let to_markdown report outcomes =
  let rows =
    List.map
      (fun row ->
        Printf.sprintf "| %s | %s | %d | %s | %s | %s |" row.tree row.command
          row.exit_code
          (cell ~scale:1024. ~digits:1 (Some row.peak_kib))
          (cell ~scale:1e9 ~digits:3 row.instructions)
          (cell ~scale:1024. ~digits:1 row.footprint_kib))
      report.rows
  in
  let budget_rows =
    List.map
      (fun (outcome : Budgets.outcome) ->
        let result, value =
          match outcome.verdict with
          | Pass value -> ("pass", Printf.sprintf "%.2f" value)
          | Fail value -> ("**fail**", Printf.sprintf "%.2f" value)
          | Skipped reason -> ("skipped: " ^ reason, "-")
        in
        Printf.sprintf "| %s | %s | %s | %.2f | %s | %s |" outcome.command
          outcome.budget
          (Option.value outcome.phase ~default:"-")
          outcome.limit value result)
      outcomes
  in
  String.concat "\n"
    ([
       "## Performance";
       "";
       (match (report.instruction_counter, report.no_count_reason) with
       | Some counter, _ -> counter ^ " counts the instructions."
       | None, Some reason -> "No instruction count: " ^ reason ^ "."
       | None, None -> "No instruction count.");
       "";
       "| tree | command | exit | peak memory (MiB) | instructions (G) | peak \
        footprint (MiB) |";
       "|---|---|---|---|---|---|";
     ]
    @ rows
    @
    match budget_rows with
    | [] -> [ "" ]
    | _ ->
        [
          "";
          "| command | budget | phase | limit | measure | result |";
          "|---|---|---|---|---|---|";
        ]
        @ budget_rows @ [ "" ])
