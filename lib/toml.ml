(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Raw = Sinter_bridge.Toml_raw

type position = { line : int; column : int }
type span = { start : position; stop : position }
type key = { name : string; at : span }
type date = { year : int; month : int; day : int }
type time = { hour : int; minute : int; second : int; nanosecond : int }
type offset = Utc | Minutes of int

type datetime = {
  date : date option;
  time : time option;
  offset : offset option;
}

type node = {
  value : value;
  span : span;
  key_start : position;
  verbatim : position option;
}

and value =
  | String of string
  | Integer of int64
  | Float of float
  | Boolean of bool
  | Datetime of datetime
  | Array of node list
  | Table of table
  | Array_of_tables of table list

and table = (key * node) list

let value node = node.value
let span node = node.span
let key_start node = node.key_start

module Kind = struct
  type t =
    | String
    | Integer
    | Float
    | Boolean
    | Datetime
    | Array
    | Table
    | Array_of_tables

  let of_value : value -> t = function
    | String _ -> String
    | Integer _ -> Integer
    | Float _ -> Float
    | Boolean _ -> Boolean
    | Datetime _ -> Datetime
    | Array _ -> Array
    | Table _ -> Table
    | Array_of_tables _ -> Array_of_tables

  let name = function
    | String -> "a string"
    | Integer -> "an integer"
    | Float -> "a float"
    | Boolean -> "a boolean"
    | Datetime -> "a date or a time"
    | Array -> "an array"
    | Table -> "a table"
    | Array_of_tables -> "an array of tables"
end

let code_points text first last =
  let count = ref 0 in
  for index = first to last - 1 do
    if Char.code text.[index] land 0xC0 <> 0x80 then incr count
  done;
  !count

let string_position node i =
  match node.value with
  | String text ->
      if i < 0 || i > String.length text then
        invalid_arg "Toml.string_position: the offset is outside the string";
      Option.map
        (fun first ->
          { first with column = first.column + code_points text 0 i })
        node.verbatim
  | _ -> None

type lines = { text : string; starts : int array; marks : int array }

let byte_order_mark = "\xEF\xBB\xBF"

let mark_every =
  (64
  [@mutaml.skip
    "any step gives the same columns: a column is read from the nearest mark \
     before it, and only the cost of that read depends on the step"])

let lines_of text =
  let first =
    if String.starts_with ~prefix:byte_order_mark text then 3 else 0
  in
  let length = String.length text in
  let starts = ref [ first ]
  and marks = ref []
  and count =
    ref
      (0
      [@mutaml.skip
        "a column is the difference of two counts, so a start value that every \
         count shares cancels out"])
  in
  for index = 0 to length - 1 do
    if index mod mark_every = 0 then marks := !count :: !marks;
    let char = text.[index] in
    if Char.code char land 0xC0 <> 0x80 then incr count;
    if char = '\n' then starts := (index + 1) :: !starts
  done;
  if length mod mark_every = 0 then marks := !count :: !marks;
  {
    text;
    starts = Array.of_list (List.rev !starts);
    marks = Array.of_list (List.rev !marks);
  }

let code_points_before lines offset =
  let mark = offset / mark_every in
  lines.marks.(mark) + code_points lines.text (mark * mark_every) offset

let position lines offset =
  let rec search low high =
    if high - low <= 1 then low
    else
      let middle = (low + high) / 2 in
      if lines.starts.(middle) <= offset then search middle high
      else search low middle
  in
  let line = search 0 (Array.length lines.starts) in
  let start = lines.starts.(line) in
  {
    line = line + 1;
    column =
      1
      + code_points_before lines (max start offset)
      - code_points_before lines start;
  }

let span_of lines ~start_byte ~end_byte =
  { start = position lines start_byte; stop = position lines end_byte }

(* @cites toml-reader *)
(* The reader gives the span of the last part of a dotted key only. The
   functions below walk back from that part, over the earlier parts of
   the key on the same line, to the first. Each runs on a text that the
   reader accepted: an opening quote stands before each closing quote
   of a key, and no key part starts the text with a backslash. *)

let is_blank char = char = ' ' || char = '\t'

let is_bare_key_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true
  | _ -> false

let char_before text at = if at > 0 then text.[at - 1] else '\n'

let rec back_over_blanks text at =
  if is_blank (char_before text at) then back_over_blanks text (at - 1) else at

let backslashes_before text at =
  let rec count at found =
    if char_before text at = '\\' then count (at - 1) (found + 1) else found
  in
  count at 0

let part_start text stop =
  match char_before text stop with
  | '"' ->
      let rec opening at =
        if text.[at - 1] = '"' && backslashes_before text (at - 1) mod 2 = 0
        then at - 1
        else opening (at - 1)
      in
      opening (stop - 1)
  | '\'' ->
      let rec opening at =
        if text.[at - 1] = '\'' then at - 1 else opening (at - 1)
      in
      opening (stop - 1)
  | _ ->
      let rec bare at =
        if is_bare_key_char (char_before text at) then bare (at - 1) else at
      in
      bare stop

let rec dotted_key_start text at =
  let before = back_over_blanks text at in
  if char_before text before = '.' then
    dotted_key_start text (part_start text (back_over_blanks text (before - 1)))
  else at

let verbatim lines ~start_byte ~end_byte decoded =
  let raw = String.sub lines.text start_byte (end_byte - start_byte) in
  let quotes =
    if
      String.starts_with ~prefix:"\"\"\"" raw
      || String.starts_with ~prefix:"'''" raw
    then 3
    else 1
  in
  let inside = String.length raw - (2 * quotes) in
  if
    String.equal (String.sub raw quotes inside) decoded
    && not (String.contains decoded '\n' || String.contains decoded '\r')
  then Some (position lines (start_byte + quotes))
  else None

let datetime_of (raw : Raw.datetime) =
  {
    date = Option.map (fun (year, month, day) -> { year; month; day }) raw.date;
    time =
      Option.map
        (fun (hour, minute, second, nanosecond) ->
          { hour; minute; second; nanosecond })
        raw.time;
    offset =
      Option.map
        (function Raw.Utc -> Utc | Raw.Minutes minutes -> Minutes minutes)
        raw.offset;
  }

let rec node_of lines ~key_byte (item : Raw.item) =
  let { Raw.start_byte; end_byte; _ } = item in
  let span = span_of lines ~start_byte ~end_byte in
  let written_by_key =
    match (item.value, key_byte) with
    | (Raw.Table _ | Raw.Array_of_tables _), _ | _, None -> None
    | _, Some at -> Some (dotted_key_start lines.text at)
  in
  let key_start =
    match written_by_key with
    | Some at -> position lines at
    | None -> span.start
  in
  let value, verbatim_at =
    match item.value with
    | Raw.String text -> (String text, verbatim lines ~start_byte ~end_byte text)
    | Raw.Integer number -> (Integer number, None)
    | Raw.Float number -> (Float number, None)
    | Raw.Boolean flag -> (Boolean flag, None)
    | Raw.Datetime raw -> (Datetime (datetime_of raw), None)
    | Raw.Array items ->
        (Array (List.map (node_of lines ~key_byte:None) items), None)
    | Raw.Table entries | Raw.Inline_table entries ->
        (Table (table_of lines entries), None)
    | Raw.Array_of_tables tables ->
        (Array_of_tables (List.map (table_of lines) tables), None)
  in
  { value; span; key_start; verbatim = verbatim_at }

and table_of lines entries =
  entries
  |> List.stable_sort (fun (a : Raw.entry) (b : Raw.entry) ->
      Int.compare a.key_start b.key_start)
  |> List.map (fun (entry : Raw.entry) ->
      ( {
          name = entry.name;
          at = span_of lines ~start_byte:entry.key_start ~end_byte:entry.key_end;
        },
        node_of lines ~key_byte:(Some entry.key_start) entry.item ))

type construct =
  | A_value
  | A_basic_string
  | A_literal_string
  | A_multiline_basic_string
  | A_multiline_literal_string
  | An_escape
  | An_integer
  | A_hexadecimal_integer
  | An_octal_integer
  | A_binary_integer
  | A_float
  | A_number
  | A_date
  | A_date_or_time
  | A_time
  | A_time_offset
  | An_array
  | An_inline_table
  | A_key
  | A_table_header
  | A_comment

type expected =
  | End_of_line
  | Comment
  | Literal of string
  | Digit
  | Hexadecimal_digit
  | Key
  | Value

type cause =
  | Duplicate_key of string
  | Not_a_table of { key : string; found : Kind.t }
  | Inline_table of string
  | Out_of_range
  | Too_deep
  | Lone_carriage_return
  | Misplaced_underscore

type error =
  | Not_utf_8 of { at : position }
  | Syntax of {
      at : position;
      construct : construct option;
      expected : expected list;
      cause : cause option;
    }
  | Header_table of {
      at : position;
      key : string;
      table : string list;
      array : bool;
      rest : string list;
    }
  | Unrecognized of { at : position }

let error_position = function
  | Not_utf_8 { at }
  | Syntax { at; _ }
  | Header_table { at; _ }
  | Unrecognized { at } ->
      at

(* @cites toml-reader *)
(* The messages of the reader. A message is a description, and then
   ", expected " and a list of what could come next, or "nothing". The tables
   below hold the whole vocabulary of the reader at its pinned version; a
   message with any other word is unrecognized. *)

type list_rule = Drop | Keep | Replace of expected list

let construct construct = (Some construct, None, Drop)
let listing construct = (construct, None, Keep)
let out_of_range construct = (Some construct, Some Out_of_range, Drop)
let cause cause = (None, Some cause, Drop)

let escapes =
  List.map
    (fun text -> Literal text)
    [ "b"; "t"; "n"; "f"; "r"; "e"; "\""; "\\"; "x"; "u"; "U" ]

let descriptions =
  [
    ("invalid literal string", construct A_literal_string);
    ("invalid multi-line literal string", construct A_multiline_literal_string);
    ("invalid basic string", construct A_basic_string);
    ("invalid multi-line basic string", construct A_multiline_basic_string);
    ("carriage return must be followed by newline", cause Lone_carriage_return);
    ("missing escaped value", (Some An_escape, None, Replace escapes));
    ("too few unicode value digits", listing (Some An_escape));
    ("invalid value", out_of_range An_escape);
    ("keys cannot be multi-line literal strings", construct A_key);
    ("keys cannot be multi-line basic strings", construct A_key);
    ("unquoted keys cannot be empty", construct A_key);
    ("invalid unquoted key", construct A_key);
    ("invalid key", listing (Some A_key));
    ("invalid key-value pair", listing (Some A_key));
    ("invalid table", listing (Some A_table_header));
    ("key with no value", listing None);
    ("missing value for key", listing None);
    ("missing value", construct A_value);
    ("string values must be quoted", construct A_value);
    ("invalid string", construct A_value);
    ("invalid boolean", construct A_value);
    ("missing opening quote", construct A_value);
    ("invalid float", listing (Some A_float));
    ("invalid fraction", listing (Some A_float));
    ("invalid exponent", listing (Some A_float));
    ("invalid mantissa", listing (Some A_float));
    ("floating-point number overflowed", out_of_range A_float);
    ("invalid integer number", listing (Some An_integer));
    ("invalid hexadecimal number", listing (Some A_hexadecimal_integer));
    ("invalid octal number", listing (Some An_octal_integer));
    ("invalid binary number", listing (Some A_binary_integer));
    ("integers with a radix cannot be signed", construct An_integer);
    ("radix must be lowercase", listing (Some An_integer));
    ("redundant integer number prefix", construct An_integer);
    ("integer number overflowed", out_of_range An_integer);
    ("redundant numeric sign", construct A_number);
    ("unexpected leading zero", construct A_number);
    ("unexpected sign", construct A_number);
    ("`_` may only go between digits", cause Misplaced_underscore);
    ("missing comment start", listing None);
    ("invalid comment character", construct A_comment);
    ("cannot recurse further; max recursion depth met", cause Too_deep);
    ("recursion limit", cause Too_deep);
    ("unclosed array table", listing (Some A_table_header));
    ("unclosed table", listing (Some A_table_header));
    ("missing table open", listing (Some A_table_header));
    ("extra `=`", construct A_value);
    ("unexpected content", listing None);
    ("unexpected key or value", listing None);
    ("unexpected content between comment and newline", listing None);
    ("missing array opening", listing (Some An_array));
    ("extra comma in array", listing (Some An_array));
    ("unexpected `=` in array", listing (Some An_array));
    ("missing comma between array elements", listing (Some An_array));
    ("unclosed array", listing (Some An_array));
    ("missing inline table opening", listing (Some An_inline_table));
    ("extra comma in inline table", listing (Some An_inline_table));
    ("extra assignment between key-value pairs", listing (Some An_inline_table));
    ("missing key for inline table element", listing (Some An_inline_table));
    ( "missing assignment between key-value pairs",
      listing (Some An_inline_table) );
    ("invalid inline table element", listing (Some An_inline_table));
    ("missing comma between key-value pairs", listing (Some An_inline_table));
    ("unclosed inline table", listing (Some An_inline_table));
  ]

let datetime_constructs =
  [
    ("invalid date", A_date);
    ("invalid time", A_time);
    ("invalid offset", A_time_offset);
    ("invalid datetime", A_date_or_time);
    ("invalid date-time", A_date_or_time);
  ]

let datetime_ranges =
  [
    "month between 01 and 12";
    "day between 01 and 28";
    "day between 01 and 29";
    "day between 01 and 30";
    "day between 01 and 31";
    "hour between 00 and 23";
    "minute between 00 and 59";
    "second between 00 and 60";
    "nanoseconds overflowed";
    "hours between 00 and 23";
    "minutes between 00 and 59";
  ]

let datetime_forms =
  [
    "year or hour";
    "`-` (YYYY-MM) or `:` (HH:MM)";
    "month";
    "`-` (MM-DD)";
    "day";
    "a four-digit year (YYYY)";
    "a two-digit month (MM)";
    "a two-digit day (DD)";
    "`T` between date and time";
    "hour";
    "`:` (HH:MM)";
    "minute";
    "second";
    "nanosecond";
    "a two-digit hour (HH)";
    "a two-digit minute (MM)";
    "a two-digit second (SS)";
    "`Z`, +OFFSET, -OFFSET";
  ]

let literals =
  [
    "'";
    "\"";
    ",";
    "-";
    "=";
    "[";
    "]";
    "]]";
    "{";
    "}";
    "\\";
    "_";
    "b";
    "e";
    "f";
    "n";
    "r";
    "u";
    "U";
    "x";
    "0x";
    "0o";
    "0b";
    "true";
    "false";
    "inf";
    "nan";
    "'''";
    "\"\"\"";
  ]

let expected_words =
  [
    ("newline", Some End_of_line);
    ("`#`", Some Comment);
    ("digits", Some Digit);
    ("unicode hexadecimal value", Some Hexadecimal_digit);
    ("key", Some Key);
    ("value", Some Value);
    ("letters", None);
    ("numbers", None);
    ("literal string", None);
    ("basic string", None);
    ("unquoted string", None);
    ("multi-line basic string", None);
    ("non-double-quote visible characters", None);
    ("non-single-quote characters", None);
    ("non-single-quote visible characters", None);
    ("characters", None);
    ("printable characters", None);
  ]
  @ List.map (fun text -> ("`" ^ text ^ "`", Some (Literal text))) literals

let kinds =
  [
    ("string", Kind.String);
    ("integer", Kind.Integer);
    ("float", Kind.Float);
    ("boolean", Kind.Boolean);
    ("datetime", Kind.Datetime);
    ("array", Kind.Array);
  ]

let between ~prefix ~suffix text =
  let inside =
    String.length text - String.length prefix - String.length suffix
  in
  if
    inside >= 0
    && String.starts_with ~prefix text
    && String.ends_with ~suffix text
  then Some (String.sub text (String.length prefix) inside)
  else None

let find_marker marker text =
  let last = String.length text - String.length marker in
  let rec find at =
    if at > last then None
    else if String.equal (String.sub text at (String.length marker)) marker then
      Some at
    else find (at + 1)
  in
  find 0

let rec split_list text =
  match find_marker ", " text with
  | None -> [ text ]
  | Some at ->
      String.sub text 0 at
      :: split_list (String.sub text (at + 2) (String.length text - at - 2))

let expected_of = function
  | None | Some "nothing" -> Some []
  | Some text ->
      let found =
        List.map
          (fun word -> List.assoc_opt word expected_words)
          (split_list text)
      in
      if List.for_all Option.is_some found then
        Some (List.filter_map Option.join found)
      else None

let extension ~key description =
  match
    between ~prefix:"cannot extend value of type " ~suffix:" with a dotted key"
      description
  with
  | Some "inline table" -> Some (None, Some (Inline_table key), Drop)
  | Some type_name ->
      Option.map
        (fun found -> (None, Some (Not_a_table { key; found }), Drop))
        (List.assoc_opt type_name kinds)
  | None -> None

let reading_of ~path description =
  match (List.assoc_opt description descriptions, path) with
  | Some reading, _ -> Some reading
  | None, None -> None
  | None, Some path -> (
      match List.rev path with
      | [] -> None
      | last :: _ ->
          if String.equal description "duplicate key" then
            Some (None, Some (Duplicate_key last), Drop)
          else extension ~key:(String.concat "." path) description)

let datetime_reading construct = function
  | None -> Some (Some construct, [], None)
  | Some text when List.mem text datetime_ranges ->
      Some (Some construct, [], Some Out_of_range)
  | Some text when List.mem text datetime_forms ->
      Some (Some construct, [], None)
  | Some _ -> None

let read_message ~path message =
  let marker = ", expected " in
  let description, rest =
    match find_marker marker message with
    | Some at ->
        let after = at + String.length marker in
        ( String.sub message 0 at,
          Some (String.sub message after (String.length message - after)) )
    | None -> (message, None)
  in
  match List.assoc_opt description datetime_constructs with
  | Some construct -> datetime_reading construct rest
  | None -> (
      match (expected_of rest, reading_of ~path description) with
      | Some expected, Some (construct, cause, rule) ->
          let expected =
            match rule with
            | Drop -> []
            | Keep -> expected
            | Replace replacement -> replacement
          in
          Some (construct, expected, cause)
      | _ -> None)

let radix_constructs =
  [
    ("0x", A_hexadecimal_integer);
    ("0o", An_octal_integer);
    ("0b", A_binary_integer);
  ]

let without_digits written reading =
  match (reading, List.assoc_opt written radix_constructs) with
  | Some (Some An_integer, [], Some Out_of_range), Some construct ->
      Some (Some construct, [], None)
  | _ -> reading

let is_control code = code < 0x20 || (code >= 0x7F && code <= 0x9F)

let fold_code_points f text init =
  let length = String.length text in
  let rec walk offset acc =
    if offset >= length then acc
    else
      let decoded = String.get_utf_8_uchar text offset in
      if Uchar.utf_decode_is_valid decoded then
        let size = Uchar.utf_decode_length decoded in
        let code = Uchar.to_int (Uchar.utf_decode_uchar decoded) in
        walk (offset + size) (f acc (Ok (code, String.sub text offset size)))
      else walk (offset + 1) (f acc (Error text.[offset]))
  in
  walk 0 init

let basic_string text =
  let escape = function
    | Ok (0x22, _) -> "\\\""
    | Ok (0x5C, _) -> "\\\\"
    | Ok (0x08, _) -> "\\b"
    | Ok (0x09, _) -> "\\t"
    | Ok (0x0A, _) -> "\\n"
    | Ok (0x0C, _) -> "\\f"
    | Ok (0x0D, _) -> "\\r"
    | Ok (code, _) when is_control code -> Printf.sprintf "\\u%04X" code
    | Ok (_, piece) -> piece
    | Error byte -> String.make 1 byte
  in
  let pieces =
    fold_code_points (fun pieces piece -> escape piece :: pieces) text []
  in
  "\"" ^ String.concat "" (List.rev pieces) ^ "\""

let quote name =
  let control =
    fold_code_points
      (fun found piece ->
        found
        || match piece with Ok (code, _) -> is_control code | Error _ -> false)
      name false
  in
  if control then basic_string name else "'" ^ name ^ "'"

let render_path names =
  String.concat "."
    (List.map
       (fun name ->
         if name <> "" && String.for_all is_bare_key_char name then name
         else basic_string name)
       names)

let construct_name = function
  | A_value -> "value"
  | A_basic_string -> "basic string"
  | A_literal_string -> "literal string"
  | A_multiline_basic_string -> "multi-line basic string"
  | A_multiline_literal_string -> "multi-line literal string"
  | An_escape -> "escape sequence"
  | An_integer -> "integer"
  | A_hexadecimal_integer -> "hexadecimal integer"
  | An_octal_integer -> "octal integer"
  | A_binary_integer -> "binary integer"
  | A_float -> "float"
  | A_number -> "number"
  | A_date -> "date"
  | A_date_or_time -> "date or time"
  | A_time -> "time"
  | A_time_offset -> "time offset"
  | An_array -> "array"
  | An_inline_table -> "inline table"
  | A_key -> "key"
  | A_table_header -> "table header"
  | A_comment -> "comment"

let expected_name = function
  | End_of_line -> "the end of the line"
  | Comment -> "a comment"
  | Literal "'" -> "\"'\""
  | Literal text -> "'" ^ text ^ "'"
  | Digit -> "a digit"
  | Hexadecimal_digit -> "a hexadecimal digit"
  | Key -> "a key"
  | Value -> "a value"

let one_of words =
  match List.rev words with
  | [] -> ""
  | [ only ] -> only
  | [ last; first ] -> first ^ " or " ^ last
  | last :: others -> String.concat ", " (List.rev others) ^ ", or " ^ last

let cause_message construct = function
  | Duplicate_key key ->
      Printf.sprintf "the key %s is already defined" (quote key)
  | Not_a_table { key; found } ->
      Printf.sprintf "%s holds %s, not a table, so it cannot hold more keys"
        (quote key) (Kind.name found)
  | Inline_table key ->
      Printf.sprintf
        "%s is an inline table, and no other line can add keys to it"
        (quote key)
  | Out_of_range ->
      Printf.sprintf "the %s is out of range"
        (Option.fold ~none:"value" ~some:construct_name construct)
  | Too_deep -> "the keys, arrays, or inline tables nest too deep"
  | Lone_carriage_return -> "the carriage return is not followed by a line feed"
  | Misplaced_underscore ->
      "an underscore in a number must stand between two digits"

let error_message = function
  | Not_utf_8 _ -> "the text is not UTF-8"
  | Header_table { key; table; array; rest; _ } ->
      let path = render_path table in
      Printf.sprintf
        "the dotted key %s adds a key to the table '%s', which a table header \
         made; write '%s' under the header %s"
        (quote key) path (render_path rest)
        (if array then "[[" ^ path ^ "]]" else "[" ^ path ^ "]")
  | Unrecognized _ -> "the text is not valid TOML here"
  | Syntax { construct; expected; cause; _ } -> (
      let expected = one_of (List.map expected_name expected) in
      match (cause, construct, expected) with
      | Some cause, _, _ -> cause_message construct cause
      | None, Some A_value, _ ->
          "the value is not valid; write a string in quotes, a number, true, \
           false, a date, a time, an array, or an inline table"
      | None, Some construct, "" ->
          Printf.sprintf "the %s is not valid" (construct_name construct)
      | None, Some construct, _ ->
          Printf.sprintf "the %s is not valid; write %s here"
            (construct_name construct) expected
      | None, None, "" -> "the text is not valid TOML here"
      | None, None, _ ->
          Printf.sprintf "the text is not valid TOML here; write %s here"
            expected)

let first_invalid_byte text =
  let length = String.length text in
  let rec walk offset =
    if offset >= length then None
    else
      let decoded = String.get_utf_8_uchar text offset in
      if Uchar.utf_decode_is_valid decoded then
        walk (offset + Uchar.utf_decode_length decoded)
      else Some offset
  in
  walk 0

let parse text =
  let lines = lines_of text in
  match first_invalid_byte text with
  | Some offset -> Error (Not_utf_8 { at = position lines offset })
  | None -> (
      match Raw.parse text with
      | Ok entries -> Ok (table_of lines entries)
      | Error (Raw.Header_table { start_byte; key; table; array; rest; _ }) ->
          Error
            (Header_table
               { at = position lines start_byte; key; table; array; rest })
      | Error (Raw.Crate_error { start_byte; end_byte; message; path }) -> (
          let at = position lines start_byte in
          let written = String.sub text start_byte (end_byte - start_byte) in
          match without_digits written (read_message ~path message) with
          | Some (construct, expected, cause) ->
              Error (Syntax { at; construct; expected; cause })
          | None -> Error (Unrecognized { at })))
