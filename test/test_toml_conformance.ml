(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

(* Dune runs the test in the build copy of test/, so the paths below are
   relative to that directory. *)
let suite = "fixtures/toml-test"

let read path =
  In_channel.with_open_bin (Filename.concat suite path) In_channel.input_all

let list name =
  read name |> String.split_on_char '\n' |> List.filter (fun line -> line <> "")

(* The cases of each list. *)
let toml_1_0 = lazy (list "files-toml-1.0.0")

let only_toml_1_1 =
  lazy
    (let earlier = Lazy.force toml_1_0 in
     List.filter
       (fun path -> not (List.mem path earlier))
       (list "files-toml-1.1.0"))

let is_case prefix path =
  String.starts_with ~prefix path && Filename.check_suffix path ".toml"

(* The cases that only TOML 1.1 allows. Each one uses a form that TOML
   1.0.0 does not have: a time with no seconds, the escape \e or \x, or
   a line break or a trailing comma in an inline table. *)
let needs_toml_1_1 =
  [
    "valid/datetime/no-seconds.toml";
    "valid/inline-table/newline.toml";
    "valid/inline-table/newline-comment.toml";
    "valid/spec-1.1.0/common-12.toml";
    "valid/spec-1.1.0/common-29.toml";
    "valid/spec-1.1.0/common-31.toml";
    "valid/spec-1.1.0/common-34.toml";
    "valid/spec-1.1.0/common-47.toml";
    "valid/string/escape-esc.toml";
    "valid/string/hex-escape.toml";
  ]

(* The value of a TOML document in the JSON form of toml-test. *)

let typed kind text = `Assoc [ ("type", `String kind); ("value", `String text) ]
let pad width number = Printf.sprintf "%0*d" width number

let date_text (date : Toml.date) =
  pad 4 date.year ^ "-" ^ pad 2 date.month ^ "-" ^ pad 2 date.day

let time_text (time : Toml.time) =
  pad 2 time.hour ^ ":" ^ pad 2 time.minute ^ ":" ^ pad 2 time.second ^ "."
  ^ pad 9 time.nanosecond

let offset_text = function
  | Toml.Utc -> "Z"
  | Toml.Minutes minutes ->
      let sign = if minutes < 0 then "-" else "+" in
      sign ^ pad 2 (abs minutes / 60) ^ ":" ^ pad 2 (abs minutes mod 60)

let datetime_json (datetime : Toml.datetime) =
  match (datetime.date, datetime.time, datetime.offset) with
  | Some date, Some time, Some offset ->
      typed "datetime"
        (date_text date ^ "T" ^ time_text time ^ offset_text offset)
  | Some date, Some time, None ->
      typed "datetime-local" (date_text date ^ "T" ^ time_text time)
  | Some date, None, _ -> typed "date-local" (date_text date)
  | None, Some time, _ -> typed "time-local" (time_text time)
  | None, None, _ -> `Null

let rec json_of_value = function
  | Toml.String text -> typed "string" text
  | Toml.Integer number -> typed "integer" (Int64.to_string number)
  | Toml.Float number -> typed "float" (Printf.sprintf "%.17g" number)
  | Toml.Boolean flag -> typed "bool" (string_of_bool flag)
  | Toml.Datetime datetime -> datetime_json datetime
  | Toml.Array nodes ->
      `List (List.map (fun node -> json_of_value (Toml.value node)) nodes)
  | Toml.Table table -> json_of_table table
  | Toml.Array_of_tables tables -> `List (List.map json_of_table tables)

and json_of_table table =
  `Assoc
    (List.map
       (fun ((key : Toml.key), node) ->
         (key.name, json_of_value (Toml.value node)))
       table)

(* The comparison of toml-test, from its file json.go. *)

let float_of_text text =
  match String.lowercase_ascii text with
  | "inf" | "+inf" -> Some Float.infinity
  | "-inf" -> Some Float.neg_infinity
  | lower -> float_of_string_opt lower

let same_float want have =
  let want = String.lowercase_ascii want
  and have = String.lowercase_ascii have in
  if String.ends_with ~suffix:"nan" want || String.ends_with ~suffix:"nan" have
  then
    let unsigned text =
      if String.length text > 0 && (text.[0] = '+' || text.[0] = '-') then
        String.sub text 1 (String.length text - 1)
      else text
    in
    String.equal (unsigned want) (unsigned have)
  else
    match (float_of_text want, float_of_text have) with
    | Some want, Some have -> Float.equal want have
    | _ -> false

(* A date and a time as a number: the seconds from the start of year 0
   in UTC, and the nanoseconds. The days come from the civil calendar. *)
let days_from_civil year month day =
  let year = if month <= 2 then year - 1 else year in
  let era = (if year >= 0 then year else year - 399) / 400 in
  let year_of_era = year - (era * 400) in
  let day_of_year =
    (((153 * if month > 2 then month - 3 else month + 9) + 2) / 5) + day - 1
  in
  let day_of_era =
    (year_of_era * 365) + (year_of_era / 4) - (year_of_era / 100) + day_of_year
  in
  (era * 146097) + day_of_era

(* Read a date and time of toml-test, after its replacements of " " by
   "T", "t" by "T", and "z" by "Z", into the date, the time, and the
   offset in minutes. *)
let read_datetime text =
  let text =
    String.map (function ' ' | 't' -> 'T' | 'z' -> 'Z' | char -> char) text
  in
  let number from length = int_of_string (String.sub text from length) in
  let date_at from =
    (number from 4, number (from + 5) 2, number (from + 8) 2)
  in
  let time_at from =
    let hour = number from 2 and minute = number (from + 3) 2 in
    let second = number (from + 6) 2 in
    let after = from + 8 in
    let fraction_end =
      if after < String.length text && text.[after] = '.' then (
        let stop = ref (after + 1) in
        while
          !stop < String.length text
          && text.[!stop] >= '0'
          && text.[!stop] <= '9'
        do
          incr stop
        done;
        !stop)
      else after
    in
    let nanosecond =
      if fraction_end = after then 0
      else
        let digits = String.sub text (after + 1) (fraction_end - after - 1) in
        let digits =
          if String.length digits >= 9 then String.sub digits 0 9
          else digits ^ String.make (9 - String.length digits) '0'
        in
        int_of_string digits
    in
    ((hour, minute, second, nanosecond), fraction_end)
  in
  let offset_at from =
    if from >= String.length text then None
    else if text.[from] = 'Z' then Some 0
    else
      let sign = if text.[from] = '-' then -1 else 1 in
      Some (sign * ((number (from + 1) 2 * 60) + number (from + 4) 2))
  in
  if String.length text >= 10 && text.[4] = '-' then
    let date = date_at 0 in
    if String.length text = 10 then (Some date, None, None)
    else
      let time, stop = time_at 11 in
      (Some date, Some time, offset_at stop)
  else
    let time, _ = time_at 0 in
    (None, Some time, None)

let instant (date, time, offset) =
  match (date, time) with
  | Some (year, month, day), Some (hour, minute, second, nanosecond) ->
      let minutes = Option.value offset ~default:0 in
      let seconds =
        (days_from_civil year month day * 86400)
        + (hour * 3600) + (minute * 60) + second - (minutes * 60)
      in
      Some (seconds, nanosecond)
  | _ -> None

let same_datetime kind want have =
  let want = read_datetime want and have = read_datetime have in
  if String.equal kind "datetime" then
    Option.equal ( = ) (instant want) (instant have)
  else want = have

let is_value fields =
  List.length fields = 2
  && List.mem_assoc "type" fields
  && List.mem_assoc "value" fields

let rec same (want : Yojson.Safe.t) (have : Yojson.Safe.t) =
  match (want, have) with
  | `Assoc want_fields, `Assoc have_fields when is_value want_fields ->
      is_value have_fields && same_value want_fields have_fields
  | `Assoc want_fields, `Assoc have_fields ->
      (not (is_value have_fields))
      && List.length want_fields = List.length have_fields
      && List.for_all
           (fun (key, want_value) ->
             match List.assoc_opt key have_fields with
             | Some have_value -> same want_value have_value
             | None -> false)
           want_fields
  | `List want_items, `List have_items ->
      List.length want_items = List.length have_items
      && List.for_all2 same want_items have_items
  | _ -> false

and same_value want have =
  match
    ( List.assoc "type" want,
      List.assoc "type" have,
      List.assoc "value" want,
      List.assoc "value" have )
  with
  | `String want_kind, `String have_kind, want_value, have_value -> (
      String.equal want_kind have_kind
      &&
      match (want_kind, want_value, have_value) with
      | "array", _, _ -> same want_value have_value
      | "float", `String want, `String have -> same_float want have
      | ( ("datetime" | "datetime-local" | "date-local" | "time-local"),
          `String want,
          `String have ) ->
          same_datetime want_kind want have
      | "bool", `String want, `String have ->
          String.equal
            (String.lowercase_ascii want)
            (String.lowercase_ascii have)
      | _, `String want, `String have -> String.equal want have
      | _ -> false)
  | _ -> false

(* The checks of the three tests. Each returns the description of a
   failure, or None. *)

let decodes_to_its_json path =
  match Toml.parse (read path) with
  | Error error ->
      Some (Printf.sprintf "%s: rejected: %s" path (Toml.error_message error))
  | Ok table ->
      let expected =
        Yojson.Safe.from_string
          (read (Filename.chop_suffix path ".toml" ^ ".json"))
      in
      if same expected (json_of_table table) then None
      else Some (path ^ ": the value differs from the JSON file")

let is_rejected_with_a_known_message path =
  match Toml.parse (read path) with
  | Ok _ -> Some (path ^ ": accepted")
  | Error (Toml.Unrecognized _) ->
      Some (path ^ ": the message is not a known form")
  | Error _ -> None

let check_all paths check () =
  match List.filter_map check paths with
  | [] -> ()
  | failures -> Alcotest.fail (String.concat "\n" failures)

let every_valid_case_decodes_to_its_json () =
  let paths = List.filter (is_case "valid/") (Lazy.force toml_1_0) in
  Alcotest.(check int) "the number of valid cases" 205 (List.length paths);
  check_all paths decodes_to_its_json ()

let every_invalid_case_is_rejected_with_a_known_message () =
  let paths = List.filter (is_case "invalid/") (Lazy.force toml_1_0) in
  Alcotest.(check int) "the number of invalid cases" 474 (List.length paths);
  check_all paths is_rejected_with_a_known_message ()

let every_form_of_toml_1_1_is_rejected () =
  let paths = List.filter (is_case "") (Lazy.force only_toml_1_1) in
  Alcotest.(check int)
    "the number of cases only TOML 1.1 lists" 67 (List.length paths);
  check_all paths
    (fun path ->
      if List.mem path needs_toml_1_1 || is_case "invalid/" path then
        is_rejected_with_a_known_message path
      else decodes_to_its_json path)
    ()

let tests =
  [
    Alcotest.test_case "every valid case decodes to its JSON" `Quick
      every_valid_case_decodes_to_its_json;
    Alcotest.test_case "every invalid case is rejected with a known message"
      `Quick every_invalid_case_is_rejected_with_a_known_message;
    Alcotest.test_case "every form of TOML 1.1 is rejected" `Quick
      every_form_of_toml_1_1_is_rejected;
  ]
