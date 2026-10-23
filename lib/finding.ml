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

type t = {
  finding_class : Finding_class.t;
  subject : subject;
  place : place option;
  detail : string option;
  fix : string option;
}

let is_control c = (c < ' ' && c <> '\t') || c = '\x7f'

let escape text =
  String.concat ""
    (List.map
       (function
         | '\r' -> "\\r"
         | '\n' -> "\\n"
         | c when is_control c -> Printf.sprintf "\\x%02x" (Char.code c)
         | c -> String.make 1 c)
       (List.of_seq (String.to_seq text)))

let one_line name = function
  | Some text when String.equal text "" ->
      invalid_arg (Printf.sprintf "Finding.make: the %s is empty" name)
  | text -> Option.map escape text

let make finding_class subject ?place ?detail ?fix () =
  let detail = one_line "detail" detail in
  let fix = one_line "fix" fix in
  { finding_class; subject; place; detail; fix }

let id finding =
  "finding:"
  ^ Finding_class.name finding.finding_class
  ^ ":" ^ subject_id finding.subject

let ackable finding =
  match finding.finding_class with
  | Finding_class.Disendorsed | Finding_class.Disconnected -> true
  | _ -> false

(* The key of order of a finding: [false] before [true] puts a finding
   with a place first. Stdlib.compare orders strings in byte order. *)
let key finding =
  ( Option.is_none finding.place,
    Option.map
      (fun { path; span } -> (path, span.start.line, span.start.column))
      finding.place,
    id finding )

let compare a b = Stdlib.compare (key a) (key b)
