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

(* [verbatim] is the place of the first character inside the quotes,
   when the text writes the string as it is on one line. *)
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

(* The number of code points in [text] from [first] to [last],
   exclusive. A byte that is not a continuation byte starts a code
   point. *)
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

(* The start of each line of a text, as byte offsets. A byte order
   mark at the start is no part of the first line. *)
type lines = { text : string; starts : int array }

let byte_order_mark = "\xEF\xBB\xBF"

let lines_of text =
  let first =
    if String.starts_with ~prefix:byte_order_mark text then 3 else 0
  in
  let starts = ref [ first ] in
  String.iteri
    (fun index char -> if char = '\n' then starts := (index + 1) :: !starts)
    text;
  { text; starts = Array.of_list (List.rev !starts) }

(* The place of the byte at [offset]. The line is the last line that
   starts at or before [offset]. *)
let position lines offset =
  let rec search low high =
    (* The line [low] starts at or before [offset], and the line [high]
       starts after it, or does not exist. *)
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
    column = 1 + code_points lines.text start (max start offset);
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

(* The character before [at], or a line feed at the start of the text. *)
let char_before text at = if at > 0 then text.[at - 1] else '\n'

(* The offset of the first of the blanks that end just before [at]. *)
let rec back_over_blanks text at =
  if is_blank (char_before text at) then back_over_blanks text (at - 1) else at

(* The number of backslashes that end just before [at]. *)
let backslashes_before text at =
  let rec count at found =
    if char_before text at = '\\' then count (at - 1) (found + 1) else found
  in
  count at 0

(* The start of the key part that ends just before [stop]. A double
   quote that an odd number of backslashes precede is inside a basic
   string; the first one that an even number precede opens it. *)
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

(* The start of the dotted key whose part starts at [at]. *)
let rec dotted_key_start text at =
  let before = back_over_blanks text at in
  if char_before text before = '.' then
    dotted_key_start text (part_start text (back_over_blanks text (before - 1)))
  else at

(* The place of the first character inside the quotes of the string
   at [start_byte] to [end_byte], when the text between the quotes is
   [decoded] and holds no line break. *)
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

(* [key_byte] is the start of the key that writes the item, or None
   for a member of an array. *)
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

(* Errors *)

type construct =
  | A_value
  | A_basic_string
  | A_literal_string
  | A_multiline_basic_string
  | A_multiline_literal_string
  | An_escape
  | A_short_unicode_escape
  | A_long_unicode_escape
  | An_integer
  | A_hexadecimal_integer
  | An_octal_integer
  | A_binary_integer
  | A_float
  | A_date_or_time
  | A_time
  | A_time_offset
  | An_array
  | An_inline_table
  | A_key
  | A_table_header

type expected =
  | End_of_line
  | Comment
  | Character of char
  | Double_bracket
  | Digit
  | Leading_digit

type cause =
  | Duplicate_key of string
  | Not_a_table of { key : string; found : Kind.t }
  | Inline_table of string
  | Out_of_range
  | Too_deep
  | Integer_too_large
  | Integer_too_small

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
(* The messages of the reader. A message is up to three lines: the
   construct ("invalid <label>"), what could come next ("expected <list>"),
   and a cause. The words below are the whole vocabulary of the reader at
   its pinned version; a message with any other word is unrecognized. *)

let constructs =
  [
    ("string", A_value);
    ("basic string", A_basic_string);
    ("literal string", A_literal_string);
    ("multiline basic string", A_multiline_basic_string);
    ("multiline literal string", A_multiline_literal_string);
    ("escape sequence", An_escape);
    ("unicode 4-digit hex code", A_short_unicode_escape);
    ("unicode 8-digit hex code", A_long_unicode_escape);
    ("integer", An_integer);
    ("hexadecimal integer", A_hexadecimal_integer);
    ("octal integer", An_octal_integer);
    ("binary integer", A_binary_integer);
    ("floating-point number", A_float);
    ("date-time", A_date_or_time);
    ("time", A_time);
    ("time offset", A_time_offset);
    ("array", An_array);
    ("inline table", An_inline_table);
    ("key", A_key);
    ("table header", A_table_header);
  ]

let expected_words =
  [
    ("newline", End_of_line);
    ("`#`", Comment);
    ("`]]`", Double_bracket);
    ("digit", Digit);
    ("leading digit", Leading_digit);
  ]
  @ List.map
      (fun char -> (Printf.sprintf "`%c`" char, Character char))
      [ '.'; '='; ']'; '}'; '"'; '\''; 'b'; 'f'; 'n'; 'r'; 't'; 'u'; 'U'; '\\' ]

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

(* The offset of the first [marker] in [text], or None. *)
let find_marker marker text =
  let last = String.length text - String.length marker in
  let rec find at =
    if at > last then None
    else if String.equal (String.sub text at (String.length marker)) marker then
      Some at
    else find (at + 1)
  in
  find 0

let duplicate_key text =
  match between ~prefix:"duplicate key `" ~suffix:"` in document root" text with
  | Some key -> Some key
  | None -> (
      match between ~prefix:"duplicate key `" ~suffix:"`" text with
      | None -> None
      | Some inside -> (
          (* "duplicate key `K` in table `T`" *)
          match find_marker "` in table `" inside with
          | Some at -> Some (String.sub inside 0 at)
          | None -> Some inside))

let not_a_table text =
  let marker = "` attempted to extend non-table type (" in
  match between ~prefix:"dotted key `" ~suffix:")" text with
  | None -> None
  | Some inside -> (
      match find_marker marker inside with
      | None -> None
      | Some at -> (
          let key = String.sub inside 0 at in
          let after = at + String.length marker in
          let type_name =
            String.sub inside after (String.length inside - after)
          in
          if String.equal type_name "inline table" then Some (Inline_table key)
          else
            match List.assoc_opt type_name kinds with
            | Some found -> Some (Not_a_table { key; found })
            | None -> None))

let cause_of text =
  match text with
  | "value is out of range" -> Some Out_of_range
  | "recursion limit exceeded" -> Some Too_deep
  | "number too large to fit in target type" -> Some Integer_too_large
  | "number too small to fit in target type" -> Some Integer_too_small
  | _ -> (
      match duplicate_key text with
      | Some key -> Some (Duplicate_key key)
      | None -> not_a_table text)

let expected_of text =
  let words = String.split_on_char ',' text in
  let found =
    List.map
      (fun word -> List.assoc_opt (String.trim word) expected_words)
      words
  in
  if List.for_all Option.is_some found then Some (List.filter_map Fun.id found)
  else None

let construct_of line =
  if String.starts_with ~prefix:"invalid " line then
    List.assoc_opt (String.sub line 8 (String.length line - 8)) constructs
  else None

(* Read a message of the reader into its parts, or None when a part is
   not a known form. *)
let read_message message =
  let lines = String.split_on_char '\n' message in
  let construct, lines =
    match lines with
    | first :: rest when Option.is_some (construct_of first) ->
        (construct_of first, rest)
    | _ -> (None, lines)
  in
  let expected, lines =
    match lines with
    | first :: rest when String.starts_with ~prefix:"expected " first ->
        (expected_of (String.sub first 9 (String.length first - 9)), rest)
    | _ -> (Some [], lines)
  in
  let cause =
    match String.concat "\n" lines with
    | "" -> Some None
    | text -> Option.map Option.some (cause_of text)
  in
  match (expected, cause) with
  | Some expected, Some cause -> Some (construct, expected, cause)
  | _ -> None

let render_path names =
  let escape = function
    | '"' -> "\\\""
    | '\\' -> "\\\\"
    | '\b' -> "\\b"
    | '\t' -> "\\t"
    | '\n' -> "\\n"
    | '\012' -> "\\f"
    | '\r' -> "\\r"
    | char when Char.code char < 0x20 || char = '\x7F' ->
        Printf.sprintf "\\u%04X" (Char.code char)
    | char -> String.make 1 char
  in
  let quote name =
    "\""
    ^ String.concat "" (List.map escape (List.of_seq (String.to_seq name)))
    ^ "\""
  in
  String.concat "."
    (List.map
       (fun name ->
         if name <> "" && String.for_all is_bare_key_char name then name
         else quote name)
       names)

let construct_name = function
  | A_value -> "value"
  | A_basic_string -> "basic string"
  | A_literal_string -> "literal string"
  | A_multiline_basic_string -> "multi-line basic string"
  | A_multiline_literal_string -> "multi-line literal string"
  | An_escape -> "escape sequence"
  | A_short_unicode_escape -> "\\u escape"
  | A_long_unicode_escape -> "\\U escape"
  | An_integer -> "integer"
  | A_hexadecimal_integer -> "hexadecimal integer"
  | An_octal_integer -> "octal integer"
  | A_binary_integer -> "binary integer"
  | A_float -> "float"
  | A_date_or_time -> "date or time"
  | A_time -> "time"
  | A_time_offset -> "time offset"
  | An_array -> "array"
  | An_inline_table -> "inline table"
  | A_key -> "key"
  | A_table_header -> "table header"

let expected_name = function
  | End_of_line -> "the end of the line"
  | Comment -> "a comment"
  | Character '\'' -> "\"'\""
  | Character char -> Printf.sprintf "'%c'" char
  | Double_bracket -> "']]'"
  | Digit -> "a digit"
  | Leading_digit -> "a digit at the start of the number"

(* "a", "a or b", "a, b, or c" *)
let one_of words =
  match List.rev words with
  | [] -> ""
  | [ only ] -> only
  | [ last; first ] -> first ^ " or " ^ last
  | last :: others -> String.concat ", " (List.rev others) ^ ", or " ^ last

let cause_message construct = function
  | Duplicate_key key -> Printf.sprintf "the key '%s' is already defined" key
  | Not_a_table { key; found } ->
      Printf.sprintf "'%s' holds %s, not a table, so it cannot hold more keys"
        key (Kind.name found)
  | Inline_table key ->
      Printf.sprintf
        "'%s' is an inline table, and no other line can add keys to it" key
  | Out_of_range ->
      Printf.sprintf "the %s is out of range"
        (Option.fold ~none:"value" ~some:construct_name construct)
  | Too_deep -> "the keys, arrays, or inline tables nest too deep"
  | Integer_too_large -> "the integer is larger than 9223372036854775807"
  | Integer_too_small -> "the integer is smaller than -9223372036854775808"

let error_message = function
  | Not_utf_8 _ -> "the text is not UTF-8"
  | Header_table { key; table; array; rest; _ } ->
      let path = render_path table in
      Printf.sprintf
        "the dotted key '%s' adds a key to the table '%s', which a table \
         header made; write '%s' under the header %s"
        key path (render_path rest)
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
          Printf.sprintf "the %s is not valid; expected %s"
            (construct_name construct) expected
      | None, None, "" -> "the text is not valid TOML here"
      | None, None, _ -> "expected " ^ expected)

(* The offset of the first byte of [text] that does not start a valid
   UTF-8 sequence, or None when the whole text is valid. *)
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
      | Error (Raw.Crate_error { start_byte; message; _ }) -> (
          let at = position lines start_byte in
          match read_message message with
          | Some (construct, expected, cause) ->
              Error (Syntax { at; construct; expected; cause })
          | None -> Error (Unrecognized { at })))
