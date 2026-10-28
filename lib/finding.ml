(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type place = { path : string; span : Markdown.span }

type subject =
  | Fact of { id : string; ack_name : string }
  | File of string
  | Error_node of { path : string; position : Markdown.position }
  | Line of { path : string; line : int }
  | Tag of { path : string; position : Markdown.position }

let subject_id = function
  | Fact { id; _ } -> id
  | File path -> "file:" ^ path
  | Error_node { path; position } ->
      Printf.sprintf "file:%s@L%dC%d" path position.line position.column
  | Line { path; line } -> Printf.sprintf "line:%s@L%d" path line
  | Tag { path; position } ->
      Printf.sprintf "tag:%s@L%dC%d" path position.line position.column

let ack_subject = function
  | Fact { ack_name; _ } -> ack_name
  | (File _ | Error_node _ | Line _ | Tag _) as subject -> subject_id subject

type mark = { start : int; stop : int; label : string }
type related = { label : string; place : place option }

let part tag part label =
  Option.map
    (fun (start, stop) -> { start; stop; label })
    (Markdown.columns tag part)

type t = {
  finding_class : Finding_class.t;
  subject : subject;
  place : place option;
  detail : string option;
  fix : Fix.t option;
  ackable : bool;
  mark : mark option;
  related : related list;
}

let is_control c = (c < ' ' && c <> '\t') || c = '\x7f'

let escape text =
  if String.exists is_control text then (
    let buffer =
      Buffer.create
        (String.length text
         [@mutaml.skip
           "the number is only the first size of a buffer that grows as it \
            needs, and no output reads it"])
    in
    String.iter
      (function
        | '\r' -> Buffer.add_string buffer "\\r"
        | '\n' -> Buffer.add_string buffer "\\n"
        | c when is_control c ->
            Buffer.add_string buffer (Printf.sprintf "\\x%02x" (Char.code c))
        | c -> Buffer.add_char buffer c)
      text;
    Buffer.contents buffer)
  else text

let checked name text =
  if String.equal text "" then
    invalid_arg (Printf.sprintf "Finding.make: the %s is empty" name)
  else escape text

let one_line name = Option.map (checked name)

let checked_mark place (mark : mark) =
  let fail reason =
    invalid_arg (Printf.sprintf "Finding.make: the mark %s" reason)
  in
  match place with
  | None -> fail "has no place"
  | Some { span; _ } ->
      if mark.start < span.start.column then fail "starts before the place"
      else if span.stop.line = span.start.line && mark.stop > span.stop.column
      then fail "stops after the place"
      else if mark.stop <= mark.start then fail "holds no character"
      else { mark with label = checked "label of the mark" mark.label }

let checked_fix place fix =
  match place with
  | Some _ -> fix
  | None -> invalid_arg "Finding.make: the fix has no place"

let place_key { path; span } =
  (path, span.start.line, span.start.column, span.stop.line, span.stop.column)

let compare_related (a : related) (b : related) =
  match (a.place, b.place) with
  | Some first, Some second -> (
      match Stdlib.compare (place_key first) (place_key second) with
      | 0 -> String.compare a.label b.label
      | order -> order)
  | Some _, None -> -1
  | None, Some _ -> 1
  | None, None -> String.compare a.label b.label

let sorted_related related =
  let sorted =
    List.sort compare_related
      (List.map
         (fun (related : related) ->
           {
             related with
             label = checked "label of a related place" related.label;
           })
         related)
  in
  let rec check_unique = function
    | first :: (second :: _ as rest) ->
        if compare_related first second = 0 then
          invalid_arg
            (Printf.sprintf "Finding.make: the related place %S comes twice"
               first.label);
        check_unique rest
    | [ _ ] | [] -> ()
  in
  check_unique sorted;
  sorted

let make finding_class subject ?place ?detail ?fix ?ackable ?mark
    ?(related = []) () =
  let detail = one_line "detail" detail in
  let fix = Option.map (checked_fix place) fix in
  let mark = Option.map (checked_mark place) mark in
  let related = sorted_related related in
  let ackable =
    match (finding_class, ackable) with
    | (Finding_class.Retired | Finding_class.Unmet_rule), ackable ->
        Option.value ackable ~default:false
    | Finding_class.Unexercised, None -> true
    | _, None -> false
    | _, Some _ ->
        invalid_arg
          (Printf.sprintf
             "Finding.make: the class %s alone decides whether an ack accepts \
              a finding"
             (Finding_class.name finding_class))
  in
  { finding_class; subject; place; detail; fix; ackable; mark; related }

let id_of finding_class subject =
  "finding:" ^ Finding_class.name finding_class ^ ":" ^ subject_id subject

let id finding = id_of finding.finding_class finding.subject

let key finding =
  ( Option.is_none finding.place,
    Option.map
      (fun { path; span } -> (path, span.start.line, span.start.column))
      finding.place,
    id finding )

let compare a b = Stdlib.compare (key a) (key b)
