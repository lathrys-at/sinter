(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type sample = {
  peak_kib : int;
  instructions : int option;
  footprint_kib : int option;
}

let lines text =
  List.filter
    (fun line -> not (String.equal line ""))
    (List.map String.trim (String.split_on_char '\n' text))

let decimal text =
  if
    String.length text > 0
    && String.for_all (function '0' .. '9' -> true | _ -> false) text
  then int_of_string_opt text
  else None

let gnu_time text =
  match List.rev (lines text) with
  | [] -> Error "the output of time is empty"
  | last :: _ -> (
      match decimal last with
      | Some kib -> Ok kib
      | None ->
          Error ("the last line of the output of time is not a number: " ^ last)
      )

let bsd_value lines name =
  List.find_map
    (fun line ->
      match String.index_opt line ' ' with
      | Some blank
        when String.equal
               (String.trim
                  (String.sub line blank (String.length line - blank)))
               name ->
          decimal (String.sub line 0 blank)
      | Some _ | None -> None)
    lines

let bsd_time text =
  let lines = lines text in
  match bsd_value lines "maximum resident set size" with
  | None -> Error "the output of time holds no maximum resident set size"
  | Some bytes ->
      Ok
        {
          peak_kib = bytes / 1024;
          instructions = bsd_value lines "instructions retired";
          footprint_kib =
            Option.map
              (fun bytes -> bytes / 1024)
              (bsd_value lines "peak memory footprint");
        }

let contains ~part text =
  let length = String.length part in
  let rec from index =
    index + length <= String.length text
    && (String.equal (String.sub text index length) part || from (index + 1))
  in
  from 0

let perf_stat text =
  let counts =
    List.filter_map
      (fun line ->
        match String.split_on_char ',' line with
        | first :: _ :: event :: _
          when (not (String.starts_with ~prefix:"#" line))
               && contains ~part:"instructions" event ->
            Some
              (match first with
              | "<not counted>" | "<not supported>" -> Ok None
              | _ -> (
                  match decimal first with
                  | Some count -> Ok (Some count)
                  | None -> Error ("the count of perf is not a number: " ^ first)
                  ))
        | _ -> None)
      (lines text)
  in
  match counts with
  | [] -> Error "the output of perf holds no count of instructions"
  | _ ->
      List.fold_left
        (fun total count ->
          match (total, count) with
          | (Error _ as error), _ | _, (Error _ as error) -> error
          | Ok total, Ok None -> Ok total
          | Ok None, Ok (Some count) -> Ok (Some count)
          | Ok (Some total), Ok (Some count) -> Ok (Some (total + count)))
        (Ok None) counts

let phase_words text =
  let lines =
    match List.rev (String.split_on_char '\n' text) with
    | "" :: lines -> Ok (List.rev lines)
    | [] | _ :: _ ->
        Error "the counts of the phases do not end with a line feed"
  in
  Result.bind lines (fun lines ->
      List.fold_left
        (fun found line ->
          Result.bind found (fun phases ->
              match String.split_on_char ' ' line with
              | [ name; words ] when name <> "" -> (
                  match decimal words with
                  | Some words when not (List.mem_assoc name phases) ->
                      Ok ((name, words) :: phases)
                  | Some _ -> Error ("the phase " ^ name ^ " occurs twice")
                  | None -> Error ("not a count of a phase: " ^ line))
              | _ -> Error ("not a count of a phase: " ^ line)))
        (Ok []) lines
      |> Result.map List.rev)

type summary = { median : float; min : float; max : float; spread : float }

let summary values =
  match List.sort Float.compare values with
  | [] -> invalid_arg "Measurement.summary: no value"
  | first :: _ as sorted ->
      let count = List.length sorted in
      let middle = List.nth sorted (count / 2) in
      let median =
        if count mod 2 = 1 then middle
        else (List.nth sorted ((count / 2) - 1) +. middle) /. 2.
      in
      let max = List.nth sorted (count - 1) in
      {
        median;
        min = first;
        max;
        spread = (if median = 0. then 0. else (max -. first) /. median *. 100.);
      }
