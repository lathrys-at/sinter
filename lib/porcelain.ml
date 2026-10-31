(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let version = 1

type header = Base | Ledger | Gate | Mode | Tool

let headers = [ Base; Ledger; Gate; Mode; Tool ]

let header_name = function
  | Base -> "base"
  | Ledger -> "ledger"
  | Gate -> "gate"
  | Mode -> "mode"
  | Tool -> "tool"

let header_of_name name =
  List.find_opt (fun header -> String.equal (header_name header) name) headers

type header_lines = No_headers | Headers of header list

let needs_quotes byte = byte < ' ' || byte = '\x7f' || byte = '"' || byte = '\\'

let add_header buffer ~nul name value =
  let bad text =
    text = ""
    || String.exists (fun byte -> byte = ' ' || needs_quotes byte) text
  in
  if bad name || bad value then
    invalid_arg "Porcelain.add_header: a name or a value that needs quotes";
  Buffer.add_string buffer "# ";
  Buffer.add_string buffer name;
  Buffer.add_char buffer ' ';
  Buffer.add_string buffer value;
  Buffer.add_char buffer (if nul then '\000' else '\n')

let add_escaped buffer byte =
  match byte with
  | '"' -> Buffer.add_string buffer "\\\""
  | '\\' -> Buffer.add_string buffer "\\\\"
  | '\x07' -> Buffer.add_string buffer "\\a"
  | '\b' -> Buffer.add_string buffer "\\b"
  | '\t' -> Buffer.add_string buffer "\\t"
  | '\n' -> Buffer.add_string buffer "\\n"
  | '\x0b' -> Buffer.add_string buffer "\\v"
  | '\x0c' -> Buffer.add_string buffer "\\f"
  | '\r' -> Buffer.add_string buffer "\\r"
  | byte when needs_quotes byte ->
      let code = Char.code byte in
      Buffer.add_char buffer '\\';
      Buffer.add_char buffer (Char.chr (48 + (code lsr 6)));
      Buffer.add_char buffer (Char.chr (48 + ((code lsr 3) land 7)));
      Buffer.add_char buffer (Char.chr (48 + (code land 7)))
  | byte -> Buffer.add_char buffer byte

let rec first_to_quote field index =
  if index = String.length field || needs_quotes field.[index] then index
  else first_to_quote field (index + 1)

let add_field buffer field =
  let length = String.length field in
  let first = first_to_quote field 0 in
  if first = length then Buffer.add_string buffer field
  else (
    Buffer.add_char buffer '"';
    Buffer.add_substring buffer field 0 first;
    for index = first to length - 1 do
      add_escaped buffer field.[index]
    done;
    Buffer.add_char buffer '"')

let quoted_under_nul field =
  String.contains field '\000' || String.starts_with ~prefix:"\"" field

let add_finding buffer ~nul ~tier (finding : Finding.t) =
  let text field =
    if nul && not (quoted_under_nul field) then Buffer.add_string buffer field
    else add_field buffer field
  in
  let next () = Buffer.add_char buffer (if nul then '\000' else '\t') in
  let number value =
    Buffer.add_string buffer (Int.to_string value);
    next ()
  in
  text
    (match tier with
    | None -> "none"
    | Some tier -> Finding_class.tier_name tier);
  next ();
  text (Finding_class.name finding.finding_class);
  next ();
  (match finding.place with
  | None ->
      next ();
      next ();
      next ();
      next ();
      next ()
  | Some { path; span } ->
      text path;
      next ();
      number span.start.line;
      number span.start.column;
      number span.stop.line;
      number span.stop.column);
  text (Finding.subject_id finding.subject);
  next ();
  Option.iter text finding.detail;
  Buffer.add_char buffer (if nul then '\000' else '\n')
