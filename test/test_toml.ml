(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let property ?(count = 300) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let parse_ok text =
  match Toml.parse text with
  | Ok table -> table
  | Error error ->
      Alcotest.failf "the text was rejected at %d:%d: %s"
        (Toml.error_position error).line (Toml.error_position error).column
        (Toml.error_message error)

let parse_error text =
  match Toml.parse text with
  | Ok _ -> Alcotest.fail "the text was accepted"
  | Error error -> error

(* The node at a path of names. *)
let rec find table = function
  | [] -> invalid_arg "find: an empty path"
  | [ name ] -> (
      match
        List.find_opt (fun ((key : Toml.key), _) -> key.name = name) table
      with
      | Some (_, node) -> node
      | None -> Alcotest.failf "no key %s" name)
  | name :: rest -> (
      match Toml.value (find table [ name ]) with
      | Toml.Table inner -> find inner rest
      | _ -> Alcotest.failf "%s is not a table" name)

let key_of table name =
  match List.find_opt (fun ((key : Toml.key), _) -> key.name = name) table with
  | Some (key, _) -> key
  | None -> Alcotest.failf "no key %s" name

let position =
  Alcotest.testable
    (fun formatter (p : Toml.position) ->
      Format.fprintf formatter "%d:%d" p.line p.column)
    ( = )

let span =
  Alcotest.testable
    (fun formatter (s : Toml.span) ->
      Format.fprintf formatter "%d:%d-%d:%d" s.start.line s.start.column
        s.stop.line s.stop.column)
    ( = )

let at line column = { Toml.line; column }
let from (l1, c1) (l2, c2) = { Toml.start = at l1 c1; stop = at l2 c2 }

(* The byte offset of a place in [text]. A byte order mark at the start
   is not a column. *)
let offset_of text (place : Toml.position) =
  let line_start =
    ref (if String.starts_with ~prefix:"\xEF\xBB\xBF" text then 3 else 0)
  in
  for _ = 2 to place.line do
    line_start := String.index_from text !line_start '\n' + 1
  done;
  let offset = ref !line_start in
  for _ = 2 to place.column do
    offset :=
      !offset + Uchar.utf_decode_length (String.get_utf_8_uchar text !offset)
  done;
  !offset

let slice text first last =
  let first = offset_of text first and last = offset_of text last in
  String.sub text first (last - first)

let text_of text (s : Toml.span) = slice text s.start s.stop

(* Positions *)

let gives_the_span_of_a_key_and_of_its_value () =
  let table = parse_ok "a = 1\n" in
  Alcotest.check span "the key" (from (1, 1) (1, 2)) (key_of table "a").at;
  Alcotest.check span "the value"
    (from (1, 5) (1, 6))
    (Toml.span (find table [ "a" ]))

let counts_columns_in_code_points () =
  let table = parse_ok "\"\xC3\xA9\" = \"\xF0\x9F\x98\x80x\"\n" in
  Alcotest.check span "the key"
    (from (1, 1) (1, 4))
    (key_of table "\xC3\xA9").at;
  Alcotest.check span "the value"
    (from (1, 7) (1, 11))
    (Toml.span (find table [ "\xC3\xA9" ]))

let counts_lines_from_1 () =
  let table = parse_ok "\n# a comment\n  b = true\n" in
  Alcotest.check span "the key" (from (3, 3) (3, 4)) (key_of table "b").at

let a_byte_order_mark_is_not_a_column () =
  let table = parse_ok "\xEF\xBB\xBFa = 1\nb = 2\n" in
  Alcotest.check span "the key on line 1"
    (from (1, 1) (1, 2))
    (key_of table "a").at;
  Alcotest.check span "the key on line 2"
    (from (2, 1) (2, 2))
    (key_of table "b").at

let a_carriage_return_ends_no_line () =
  let table = parse_ok "a = 1\r\nb = 2\r\n" in
  Alcotest.check span "the key" (from (2, 1) (2, 2)) (key_of table "b").at

let a_value_over_lines_stops_on_its_last_line () =
  let table = parse_ok "a = \"\"\"\nxy\n\"\"\"\nb = [\n  1,\n]\n" in
  Alcotest.check span "the string"
    (from (1, 5) (3, 4))
    (Toml.span (find table [ "a" ]));
  Alcotest.check span "the array"
    (from (4, 5) (6, 2))
    (Toml.span (find table [ "b" ]))

let an_inline_table_spans_its_braces () =
  let table = parse_ok "t = { a = 1 }\n" in
  Alcotest.check span "the table"
    (from (1, 5) (1, 14))
    (Toml.span (find table [ "t" ]))

let a_table_takes_the_span_of_its_key () =
  let table = parse_ok "x.y = 1\n[t]\na = 1\n[[s]]\n" in
  Alcotest.check span "a dotted table"
    (from (1, 1) (1, 2))
    (Toml.span (find table [ "x" ]));
  Alcotest.check span "a header table"
    (from (2, 2) (2, 3))
    (Toml.span (find table [ "t" ]));
  Alcotest.check span "an array of tables"
    (from (4, 3) (4, 4))
    (Toml.span (find table [ "s" ]))

let each_part_of_a_key_has_its_span () =
  let table = parse_ok "[a.\"b c\".d]\nx . 'y' . z = 1\n" in
  Alcotest.check span "a" (from (1, 2) (1, 3)) (key_of table "a").at;
  let a =
    match Toml.value (find table [ "a" ]) with Toml.Table t -> t | _ -> []
  in
  Alcotest.check span "b c" (from (1, 4) (1, 9)) (key_of a "b c").at;
  let d =
    match Toml.value (find table [ "a"; "b c"; "d" ]) with
    | Toml.Table t -> t
    | _ -> []
  in
  Alcotest.check span "x" (from (2, 1) (2, 2)) (key_of d "x").at;
  let x =
    match Toml.value (find d [ "x" ]) with Toml.Table t -> t | _ -> []
  in
  Alcotest.check span "y" (from (2, 5) (2, 8)) (key_of x "y").at

let a_header_that_names_a_table_gives_its_span () =
  let table = parse_ok "[a.b]\n[a]\n" in
  Alcotest.check span "the header [a]"
    (from (2, 2) (2, 3))
    (key_of table "a").at

let a_dotted_table_takes_the_place_it_is_first_written () =
  let table = parse_ok "x.y = 1\nx.z = 2\n" in
  Alcotest.check span "the first x" (from (1, 1) (1, 2)) (key_of table "x").at

let keys_come_in_the_order_of_their_spans () =
  let names table = List.map (fun ((key : Toml.key), _) -> key.name) table in
  Alcotest.(check (list string))
    "the order of the text" [ "b"; "a" ]
    (names (parse_ok "b = 1\na = 2\n"));
  Alcotest.(check (list string))
    "the header [a] comes last" [ "c"; "a" ]
    (names (parse_ok "[a.b]\n[c]\n[a]\n"))

(* The start of a dotted key *)

let key_start_of text path = Toml.key_start (find (parse_ok text) path)

let key_start_is_the_first_part_of_a_dotted_key () =
  Alcotest.check position "a.b.c" (at 1 1)
    (key_start_of "a.b.c = 1\n" [ "a"; "b"; "c" ]);
  Alcotest.check position "blanks around the dots" (at 1 3)
    (key_start_of "  a . b\t.\tc = 1\n" [ "a"; "b"; "c" ]);
  Alcotest.check position "one part" (at 2 1) (key_start_of "\nx = 1\n" [ "x" ])

let key_start_reads_back_over_quoted_parts () =
  Alcotest.check position "a quote and a backslash" (at 1 1)
    (key_start_of "\"x\\\"y\" . 'z' . w = 1\n" [ "x\"y"; "z"; "w" ]);
  Alcotest.check position "a backslash before the closing quote" (at 1 1)
    (key_start_of "\"a\\\\\" . b = 1\n" [ "a\\"; "b" ]);
  Alcotest.check position "a literal part" (at 1 1)
    (key_start_of "'a\\' . b = 1\n" [ "a\\"; "b" ]);
  Alcotest.check position "an escape before a quote and a dot inside" (at 1 2)
    (key_start_of " \"a.\\\\\\\"\" . b = 1\n" [ "a.\\\""; "b" ])

let key_start_inside_an_inline_table () =
  let text = "t = { a.b = 1, c . d = 2 }\n" in
  Alcotest.check position "a.b" (at 1 7) (key_start_of text [ "t"; "a"; "b" ]);
  Alcotest.check position "c . d" (at 1 16)
    (key_start_of text [ "t"; "c"; "d" ])

let key_start_of_a_table_or_a_member_is_its_span () =
  let table = parse_ok "a.b = [1, 2]\n[t]\n" in
  Alcotest.check position "the table a" (at 1 1)
    (Toml.key_start (find table [ "a" ]));
  Alcotest.check position "the table t" (at 2 2)
    (Toml.key_start (find table [ "t" ]));
  match Toml.value (find table [ "a"; "b" ]) with
  | Toml.Array [ _; second ] ->
      Alcotest.check position "the member 2" (at 1 11) (Toml.key_start second)
  | _ -> Alcotest.fail "no array of two members"

(* Strings *)

let string_node text = find (parse_ok ("s = " ^ text ^ "\n")) [ "s" ]

let string_position_counts_code_points () =
  let node = string_node "'a\xC3\xA9b'" in
  Alcotest.(check (option position))
    "byte 0"
    (Some (at 1 6))
    (Toml.string_position node 0);
  Alcotest.(check (option position))
    "byte 3"
    (Some (at 1 8))
    (Toml.string_position node 3);
  Alcotest.(check (option position))
    "one past the end"
    (Some (at 1 9))
    (Toml.string_position node 4)

let string_position_of_a_basic_string_with_no_escape () =
  Alcotest.(check (option position))
    "byte 1"
    (Some (at 1 7))
    (Toml.string_position (string_node "\"ab\"") 1);
  Alcotest.(check (option position))
    "a multi-line string on one line"
    (Some (at 1 9))
    (Toml.string_position (string_node "'''ab'''") 1)

let string_position_of_an_empty_string () =
  Alcotest.(check (option position))
    "byte 0 of ''"
    (Some (at 1 6))
    (Toml.string_position (string_node "''") 0)

let string_position_is_none_when_the_text_differs () =
  Alcotest.(check (option position))
    "an escape" None
    (Toml.string_position (string_node "\"a\\tb\"") 1);
  Alcotest.(check (option position))
    "a line break" None
    (Toml.string_position (string_node "'''\nab'''") 1);
  Alcotest.(check (option position))
    "a line break inside" None
    (Toml.string_position (string_node "'''a\nb'''") 1);
  Alcotest.(check (option position))
    "a carriage return inside" None
    (Toml.string_position (string_node "\"\"\"a\r\nb\"\"\"") 1);
  Alcotest.(check (option position))
    "not a string" None
    (Toml.string_position (string_node "12") 0)

let string_position_refuses_an_offset_outside_the_string () =
  let node = string_node "\"a\\tb\"" in
  let refused =
    Invalid_argument "Toml.string_position: the offset is outside the string"
  in
  Alcotest.check_raises "below 0" refused (fun () ->
      ignore (Toml.string_position node (-1)));
  Alcotest.check_raises "past the end" refused (fun () ->
      ignore (Toml.string_position node 4))

(* Values *)

let reads_every_kind_of_value () =
  let table =
    parse_ok
      "s = 'x'\n\
       i = -9223372036854775808\n\
       j = 9223372036854775807\n\
       f = 1.5\n\
       n = nan\n\
       p = -inf\n\
       b = false\n\
       d = 1979-05-27\n\
       t = 07:32:00.5\n\
       l = 1979-05-27T07:32:00\n\
       o = 1979-05-27T07:32:00-07:00\n\
       z = 1979-05-27 07:32:00Z\n\
       a = [1, [true]]\n\
       [[r]]\n\
       x = 1\n\
       [[r]]\n"
  in
  let value name = Toml.value (find table [ name ]) in
  Alcotest.(check bool) "a string" true (value "s" = Toml.String "x");
  Alcotest.(check bool)
    "the least integer" true
    (value "i" = Toml.Integer Int64.min_int);
  Alcotest.(check bool)
    "the greatest integer" true
    (value "j" = Toml.Integer Int64.max_int);
  Alcotest.(check bool) "a float" true (value "f" = Toml.Float 1.5);
  Alcotest.(check bool)
    "nan" true
    (match value "n" with Toml.Float f -> Float.is_nan f | _ -> false);
  Alcotest.(check bool) "-inf" true (value "p" = Toml.Float Float.neg_infinity);
  Alcotest.(check bool) "a boolean" true (value "b" = Toml.Boolean false);
  let date = Some { Toml.year = 1979; month = 5; day = 27 } in
  let time = Some { Toml.hour = 7; minute = 32; second = 0; nanosecond = 0 } in
  Alcotest.(check bool)
    "a date" true
    (value "d" = Toml.Datetime { date; time = None; offset = None });
  Alcotest.(check bool)
    "a time" true
    (value "t"
    = Toml.Datetime
        {
          date = None;
          time =
            Some { hour = 7; minute = 32; second = 0; nanosecond = 500_000_000 };
          offset = None;
        });
  Alcotest.(check bool)
    "a local date and time" true
    (value "l" = Toml.Datetime { date; time; offset = None });
  Alcotest.(check bool)
    "an offset" true
    (value "o"
    = Toml.Datetime { date; time; offset = Some (Toml.Minutes (-420)) });
  Alcotest.(check bool)
    "UTC" true
    (value "z" = Toml.Datetime { date; time; offset = Some Toml.Utc });
  (match value "a" with
  | Toml.Array [ one; inner ] ->
      Alcotest.(check bool)
        "the first member" true
        (Toml.value one = Toml.Integer 1L);
      Alcotest.(check bool)
        "the inner array" true
        (match Toml.value inner with
        | Toml.Array [ member ] -> Toml.value member = Toml.Boolean true
        | _ -> false)
  | _ -> Alcotest.fail "no array of two members");
  match value "r" with
  | Toml.Array_of_tables [ first; second ] ->
      Alcotest.(check int) "the first table" 1 (List.length first);
      Alcotest.(check int) "the second table" 0 (List.length second)
  | _ -> Alcotest.fail "no array of two tables"

let every_kind_has_a_name () =
  let table =
    parse_ok
      "s = ''\ni = 1\nf = 1.0\nb = true\nd = 07:00:00\na = []\nt = {}\n[[r]]\n"
  in
  Alcotest.(check (list string))
    "the names"
    [
      "a string";
      "an integer";
      "a float";
      "a boolean";
      "a date or a time";
      "an array";
      "a table";
      "an array of tables";
    ]
    (List.map
       (fun name ->
         Toml.Kind.name (Toml.Kind.of_value (Toml.value (find table [ name ]))))
       [ "s"; "i"; "f"; "b"; "d"; "a"; "t"; "r" ])

(* Errors *)

let check_error ~name text expected_position expected_message =
  let error = parse_error text in
  Alcotest.check position (name ^ ": the place") expected_position
    (Toml.error_position error);
  Alcotest.(check string)
    (name ^ ": the message") expected_message (Toml.error_message error)

let gives_the_place_of_the_first_byte_that_is_not_utf_8 () =
  check_error ~name:"not UTF-8" "a = 1\nb = \"\xC3\xA9\xFF\"\n" (at 2 7)
    "the text is not UTF-8"

let names_a_dotted_key_into_a_table_that_a_header_made () =
  check_error ~name:"the example of the specification"
    "[a.b.c]\nz = 9\n[a]\nb.ct = 1\n" (at 4 1)
    "the dotted key 'b.ct' adds a key to the table 'a.b', which a table header \
     made; write 'ct' under the header [a.b]";
  check_error ~name:"an array of tables" "[[tab.arr]]\n[tab]\n  arr . val1=1\n"
    (at 3 3)
    "the dotted key 'arr . val1' adds a key to the table 'tab.arr', which a \
     table header made; write 'val1' under the header [[tab.arr]]";
  check_error ~name:"through a named table" "[a.b]\n[a]\nb.\"c d\".e = 1\n"
    (at 3 1)
    "the dotted key 'b.\"c d\".e' adds a key to the table 'a.b', which a table \
     header made; write '\"c d\".e' under the header [a.b]"

let messages =
  [
    ("a = 1 b = 2\n", (1, 7), "expected the end of the line or a comment");
    ("[a\n", (1, 3), "the table header is not valid; expected '.' or ']'");
    ("[[a]\n", (1, 4), "the table header is not valid; expected '.' or ']]'");
    ( "a = x\n",
      (1, 5),
      "the value is not valid; write a string in quotes, a number, true, \
       false, a date, a time, an array, or an inline table" );
    ( "a = \"\\e\"\n",
      (1, 8),
      "the escape sequence is not valid; expected 'b', 'f', 'n', 'r', 't', \
       'u', 'U', '\\', or '\"'" );
    ("a = \"abc\n", (1, 9), "the basic string is not valid");
    ("a = [1 2]\n", (1, 8), "the array is not valid; expected ']'");
    ("a = { b = 1\n", (1, 12), "the inline table is not valid; expected '}'");
    ("a = 1\na = 2\n", (2, 1), "the key 'a' is already defined");
    ("[t]\n[t]\n", (2, 1), "the key 't' is already defined");
    ( "a = 1\na.b = 2\n",
      (2, 1),
      "'a' holds an integer, not a table, so it cannot hold more keys" );
    ( "a = 1.5\na.b = 2\n",
      (2, 1),
      "'a' holds a float, not a table, so it cannot hold more keys" );
    ( "a = 's'\na.b = 2\n",
      (2, 1),
      "'a' holds a string, not a table, so it cannot hold more keys" );
    ( "a = true\na.b = 2\n",
      (2, 1),
      "'a' holds a boolean, not a table, so it cannot hold more keys" );
    ( "a = 07:00:00\na.b = 2\n",
      (2, 1),
      "'a' holds a date or a time, not a table, so it cannot hold more keys" );
    ( "a = []\n[a.b]\n",
      (2, 1),
      "'a' holds an array, not a table, so it cannot hold more keys" );
    ( "a = {}\na.b = 1\n",
      (2, 1),
      "'a' is an inline table, and no other line can add keys to it" );
    ("a = 1979-02-30\n", (1, 13), "the date or time is out of range");
    ("a = \"\\uD800\"\n", (1, 8), "the \\u escape is out of range");
    ( "a = 9223372036854775808\n",
      (1, 5),
      "the integer is larger than 9223372036854775807" );
    ( "a = -9223372036854775809\n",
      (1, 5),
      "the integer is smaller than -9223372036854775808" );
    ("a = 1__2\n", (1, 7), "the integer is not valid; expected a digit");
    ( "a = _1\n",
      (1, 5),
      "the integer is not valid; expected a digit at the start of the number" );
    ("a = 1\r\n\r", (2, 1), "the text is not valid TOML here");
  ]

let gives_the_message_and_the_place_of_each_form () =
  let wrong =
    List.filter_map
      (fun (text, (line, column), message) ->
        let error = parse_error text in
        let place = Toml.error_position error in
        if
          place = at line column
          && String.equal (Toml.error_message error) message
        then None
        else
          Some
            (Printf.sprintf "%S: %d:%d %S" text place.line place.column
               (Toml.error_message error)))
      messages
  in
  if wrong <> [] then Alcotest.fail (String.concat "\n" wrong)

let a_document_that_nests_too_deep_is_refused () =
  check_error ~name:"deep arrays"
    ("a = " ^ String.make 100 '[')
    (at 1 84) "the keys, arrays, or inline tables nest too deep"

let all_constructs =
  Toml.
    [
      ("string", A_value, "value");
      ("basic string", A_basic_string, "basic string");
      ("literal string", A_literal_string, "literal string");
      ( "multiline basic string",
        A_multiline_basic_string,
        "multi-line basic string" );
      ( "multiline literal string",
        A_multiline_literal_string,
        "multi-line literal string" );
      ("escape sequence", An_escape, "escape sequence");
      ("unicode 4-digit hex code", A_short_unicode_escape, "\\u escape");
      ("unicode 8-digit hex code", A_long_unicode_escape, "\\U escape");
      ("integer", An_integer, "integer");
      ("hexadecimal integer", A_hexadecimal_integer, "hexadecimal integer");
      ("octal integer", An_octal_integer, "octal integer");
      ("binary integer", A_binary_integer, "binary integer");
      ("floating-point number", A_float, "float");
      ("date-time", A_date_or_time, "date or time");
      ("time", A_time, "time");
      ("time offset", A_time_offset, "time offset");
      ("array", An_array, "array");
      ("inline table", An_inline_table, "inline table");
      ("key", A_key, "key");
      ("table header", A_table_header, "table header");
    ]

let read_message_knows_every_construct () =
  List.iter
    (fun (label, construct, _) ->
      Alcotest.(check bool)
        label true
        (Toml.read_message ("invalid " ^ label)
        = Some (Some construct, [], None)))
    all_constructs

let error_message_names_every_construct () =
  List.iter
    (fun (_, construct, name) ->
      let at = at 1 1 in
      Alcotest.(check string)
        name
        (if construct = Toml.A_value then
           "the value is not valid; write a string in quotes, a number, true, \
            false, a date, a time, an array, or an inline table"
         else "the " ^ name ^ " is not valid")
        (Toml.error_message
           (Toml.Syntax
              { at; construct = Some construct; expected = []; cause = None })))
    all_constructs

let read_message_knows_every_expected_form () =
  Alcotest.(check bool)
    "every form" true
    (Toml.read_message
       "expected newline, `#`, `]]`, digit, leading digit, `.`, `=`, `]`, `}`, \
        `\"`, `'`, `b`, `f`, `n`, `r`, `t`, `u`, `U`, `\\`"
    = Some
        ( None,
          Toml.
            [
              End_of_line;
              Comment;
              Double_bracket;
              Digit;
              Leading_digit;
              Character '.';
              Character '=';
              Character ']';
              Character '}';
              Character '"';
              Character '\'';
              Character 'b';
              Character 'f';
              Character 'n';
              Character 'r';
              Character 't';
              Character 'u';
              Character 'U';
              Character '\\';
            ],
          None ))

let read_message_reads_all_three_parts () =
  Alcotest.(check bool)
    "a construct, a list, and a cause" true
    (Toml.read_message
       "invalid table header\nexpected `.`\nduplicate key `a\nb` in table `x`"
    = Some
        ( Some Toml.A_table_header,
          [ Toml.Character '.' ],
          Some (Toml.Duplicate_key "a\nb") ))

let read_message_reads_each_duplicate_key () =
  List.iter
    (fun (message, key) ->
      Alcotest.(check bool)
        message true
        (Toml.read_message message
        = Some (None, [], Some (Toml.Duplicate_key key))))
    [
      ("duplicate key `a`", "a");
      ("duplicate key `a` in document root", "a");
      ("duplicate key `a` in table `b.c`", "a");
      ("duplicate key `` in table `b`", "");
      ("duplicate key `x` in table `y` in table `z`", "x");
      ("duplicate key ``", "");
      ("duplicate key `x` in table ``", "x");
      ("duplicate key `abcdefghijk`", "abcdefghijk");
      ("duplicate key `abcdefghijkl`", "abcdefghijkl");
    ]

let read_message_reads_a_dotted_key_with_an_empty_name () =
  Alcotest.(check bool)
    "an empty name" true
    (Toml.read_message
       "dotted key `` attempted to extend non-table type (boolean)"
    = Some
        ( None,
          [],
          Some (Toml.Not_a_table { key = ""; found = Toml.Kind.Boolean }) ))

let read_message_refuses_an_unknown_form () =
  List.iter
    (fun message ->
      Alcotest.(check bool) message true (Toml.read_message message = None))
    [
      "invalid widget";
      "expected `?`";
      "expected newline, `?`";
      "invalid string\nexpected `\"`, something";
      "invalid digit found in string";
      "dotted key `a` attempted to extend non-table type (table)";
      "dotted key `a` attempted to extend non-table type (integer";
      "dotted key `a` tried to extend (integer)";
      "duplicate key";
      "duplicate key `";
      "duplicate key `a";
      "dotted key `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)";
      "value is out of range\nmore";
    ]

let error_message_of_an_unrecognized_form () =
  Alcotest.(check string)
    "the message" "the text is not valid TOML here"
    (Toml.error_message (Toml.Unrecognized { at = at 3 4 }));
  Alcotest.check position "the place" (at 3 4)
    (Toml.error_position (Toml.Unrecognized { at = at 3 4 }))

let error_message_of_a_cause_out_of_range_with_no_construct () =
  Alcotest.(check string)
    "the message" "the value is out of range"
    (Toml.error_message
       (Toml.Syntax
          {
            at = at 1 1;
            construct = None;
            expected = [];
            cause = Some Toml.Out_of_range;
          }))

(* render_path *)

let render_path_quotes_only_what_it_must () =
  Alcotest.(check string)
    "the path"
    "a.B-9_x.\"\".\"a \
     b\".\"q\\\"\\\\\".\"\\b\\t\\n\\f\\r\\u001F\\u007F\".\"\xC3\xA9\""
    (Toml.render_path
       [ "a"; "B-9_x"; ""; "a b"; "q\"\\"; "\b\t\n\012\r\031\127"; "\xC3\xA9" ])

(* Properties *)

(* A document of the generator: a table of entries with distinct names.
   A sub-table is written with a table header or with dotted keys; a
   table written with dotted keys holds only values and tables written
   with dotted keys, and at least one entry. *)
type style = Basic | Literal | Multiline_basic | Multiline_literal

type gvalue =
  | G_string of string * style
  | G_integer of int64
  | G_float of float
  | G_boolean of bool
  | G_date of Toml.date
  | G_array of gvalue list
  | G_inline of (string * gvalue) list

type gentry = G_value of gvalue | G_header of gtable | G_dotted of gtable
and gtable = (string * gentry) list

let names =
  [
    "a";
    "b";
    "key-1";
    "_x";
    "a b";
    "q\"t";
    "x'y";
    "a'b\"c";
    "x\\";
    "\xC3\xA9";
    "";
    "dot.ted";
    "t\tab";
  ]

let is_bare name =
  name <> ""
  && String.for_all
       (function
         | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true | _ -> false)
       name

let render_name name =
  if is_bare name then name
  else if
    String.contains name '\''
    || String.exists (fun c -> Char.code c < 0x20 && c <> '\t') name
  then Toml.render_path [ name ]
  else "'" ^ name ^ "'"

let escape_basic ~keep_newline text =
  let buffer = Buffer.create (String.length text) in
  String.iter
    (function
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\n' when keep_newline -> Buffer.add_char buffer '\n'
      | c when Char.code c < 0x20 || c = '\127' ->
          Buffer.add_string buffer (Printf.sprintf "\\u%04X" (Char.code c))
      | c -> Buffer.add_char buffer c)
    text;
  Buffer.contents buffer

let literal_fits text =
  not
    (String.contains text '\''
    || String.exists
         (fun c -> (Char.code c < 0x20 && c <> '\t') || c = '\127')
         text)

let rec render_value = function
  | G_string (text, Basic) ->
      "\"" ^ escape_basic ~keep_newline:false text ^ "\""
  | G_string (text, Literal) ->
      if literal_fits text then "'" ^ text ^ "'"
      else render_value (G_string (text, Basic))
  | G_string (text, Multiline_basic) ->
      let escaped = escape_basic ~keep_newline:true text in
      let escaped =
        if String.starts_with ~prefix:"\n" escaped then
          "\\n" ^ String.sub escaped 1 (String.length escaped - 1)
        else escaped
      in
      "\"\"\"" ^ escaped ^ "\"\"\""
  | G_string (text, Multiline_literal) ->
      if literal_fits text && text <> "" then "'''" ^ text ^ "'''"
      else render_value (G_string (text, Basic))
  | G_integer number -> Int64.to_string number
  | G_float number ->
      if Float.is_nan number then "nan"
      else if number = Float.infinity then "inf"
      else if number = Float.neg_infinity then "-inf"
      else
        let text = Printf.sprintf "%.17g" number in
        if String.exists (fun c -> c = '.' || c = 'e') text then text
        else text ^ ".0"
  | G_boolean flag -> string_of_bool flag
  | G_date { year; month; day } ->
      Printf.sprintf "%04d-%02d-%02d" year month day
  | G_array items ->
      "[" ^ String.concat ", " (List.map render_value items) ^ "]"
  | G_inline entries ->
      "{"
      ^ String.concat ", "
          (List.map
             (fun (name, value) ->
               " " ^ render_name name ^ " = " ^ render_value value)
             entries)
      ^ " }"

let distinct entries =
  let rec keep seen = function
    | [] -> []
    | (name, entry) :: rest ->
        if List.mem name seen then keep seen rest
        else (name, entry) :: keep (name :: seen) rest
  in
  keep [] entries

let gvalue =
  let open QCheck2.Gen in
  let text =
    oneof
      [
        Generators.utf_8_string;
        Generators.ascii_string;
        oneof_list [ "a\nb"; "\"'"; "\\"; "" ];
      ]
  in
  let style =
    oneof_list [ Basic; Literal; Multiline_basic; Multiline_literal ]
  in
  sized_size (int_range 0 2)
  @@ fix (fun self depth ->
      let scalar =
        oneof
          [
            map2 (fun text style -> G_string (text, style)) text style;
            map
              (fun n -> G_integer n)
              (oneof [ int64; oneof_list [ Int64.min_int; Int64.max_int ] ]);
            map
              (fun f -> G_float f)
              (oneof
                 [
                   float;
                   oneof_list [ Float.nan; Float.infinity; Float.neg_infinity ];
                 ]);
            map (fun b -> G_boolean b) bool;
            map3
              (fun year month day -> G_date { year; month; day })
              (int_range 0 9999) (int_range 1 12) (int_range 1 28);
          ]
      in
      if depth = 0 then scalar
      else
        oneof
          [
            scalar;
            map
              (fun items -> G_array items)
              (list_size (int_range 0 3) (self (depth - 1)));
            map
              (fun entries -> G_inline (distinct entries))
              (list_size (int_range 0 3)
                 (pair (oneof_list names) (self (depth - 1))));
          ])

let gtable =
  let open QCheck2.Gen in
  let entry_list entry =
    map distinct (list_size (int_range 0 4) (pair (oneof_list names) entry))
  in
  let rec dotted depth =
    let entry =
      if depth = 0 then map (fun v -> G_value v) gvalue
      else
        oneof
          [
            map (fun v -> G_value v) gvalue;
            map (fun t -> G_dotted t) (dotted (depth - 1));
          ]
    in
    map distinct (list_size (int_range 1 3) (pair (oneof_list names) entry))
  in
  let rec header depth =
    let entry =
      if depth = 0 then map (fun v -> G_value v) gvalue
      else
        oneof
          [
            map (fun v -> G_value v) gvalue;
            map (fun t -> G_dotted t) (dotted 1);
            map (fun t -> G_header t) (header (depth - 1));
          ]
    in
    entry_list entry
  in
  header 2

(* The text of a document, with blanks drawn around each "=" and each
   "." of a dotted key. *)
let render table =
  let open QCheck2.Gen in
  let blank = oneof_list [ ""; " "; "\t"; " \t" ] in
  let dotted_key parts =
    let+ blanks = list_size (return (List.length parts)) (pair blank blank) in
    String.concat "."
      (List.map2
         (fun part (before, after) -> before ^ render_name part ^ after)
         parts blanks)
  in
  let line parts value =
    let* indent = oneof_list [ ""; "  " ] in
    let* key = dotted_key parts in
    let+ equals = oneof_list [ "="; " = "; "\t=  " ] in
    indent ^ key ^ equals ^ render_value value ^ "\n"
  in
  let rec dotted_lines prefix table =
    flatten_list
      (List.map
         (fun (name, entry) ->
           match entry with
           | G_value value -> line (prefix @ [ name ]) value
           | G_dotted inner ->
               map (String.concat "") (dotted_lines (prefix @ [ name ]) inner)
           | G_header _ -> return "")
         table)
  in
  let rec section path table =
    let* own =
      dotted_lines []
        (List.filter
           (fun (_, e) -> match e with G_header _ -> false | _ -> true)
           table)
    in
    let+ children =
      flatten_list
        (List.filter_map
           (fun (name, entry) ->
             match entry with
             | G_header inner ->
                 Some
                   (let path = path @ [ name ] in
                    let* header = dotted_key path in
                    let+ body = section path inner in
                    "[" ^ header ^ "]\n" ^ body)
             | _ -> None)
           table)
    in
    String.concat "" own ^ String.concat "" children
  in
  section [] table

let generated_document =
  QCheck2.Gen.(
    let* table = gtable in
    let+ text = render table in
    (table, text))

let rec same_value text (g : gvalue) node =
  (match (g, Toml.value node) with
    | G_string (s, _), Toml.String t -> String.equal s t
    | G_integer a, Toml.Integer b -> Int64.equal a b
    | G_float a, Toml.Float b -> Float.equal a b
    | G_boolean a, Toml.Boolean b -> a = b
    | G_date d, Toml.Datetime { date = Some e; time = None; offset = None } ->
        d = e
    | G_array items, Toml.Array nodes ->
        List.length items = List.length nodes
        && List.for_all2 (same_value text) items nodes
    | G_inline entries, Toml.Table table ->
        List.length entries = List.length table
        && List.for_all2
             (fun (name, g) ((key : Toml.key), node) ->
               String.equal name key.name
               && String.equal (text_of text key.at) (render_name name)
               && same_value text g node
               && Toml.key_start node = key.at.start)
             entries table
    | _ -> false)
  && String.equal (text_of text (Toml.span node)) (render_value g)

let without_blanks_and_dots text =
  String.concat "" (String.split_on_char '.' text)
  |> String.split_on_char ' ' |> String.concat "" |> String.split_on_char '\t'
  |> String.concat ""

(* [prefix] is the parts of the dotted key that the line writes before
   the entries of [table]. *)
let rec same_table text ~prefix (g : gtable) table =
  List.length g = List.length table
  && List.for_all
       (fun (name, entry) ->
         match
           List.find_opt
             (fun ((key : Toml.key), _) -> String.equal key.name name)
             table
         with
         | None -> false
         | Some (key, node) -> (
             String.equal (text_of text key.at) (render_name name)
             &&
             match (entry, Toml.value node) with
             | G_value g, _ ->
                 same_value text g node
                 && String.equal
                      (without_blanks_and_dots
                         (slice text (Toml.key_start node) key.at.start))
                      (without_blanks_and_dots
                         (String.concat "" (List.map render_name prefix)))
             | G_header inner, Toml.Table parsed ->
                 same_table text ~prefix:[] inner parsed
             | G_dotted inner, Toml.Table parsed ->
                 same_table text ~prefix:(prefix @ [ name ]) inner parsed
             | _ -> false))
       g

let a_generated_document_reads_back =
  property ~name:"a generated document reads back with its places"
    ~print:(fun (_, text) -> text)
    generated_document
    (fun (g, text) ->
      match Toml.parse text with
      | Ok table -> same_table text ~prefix:[] g table
      | Error error ->
          QCheck2.Test.fail_reportf "rejected at %d:%d: %s"
            (Toml.error_position error).line (Toml.error_position error).column
            (Toml.error_message error))

let line_lengths text =
  String.split_on_char '\n' text
  |> List.map (fun line ->
      let count = ref 0 in
      String.iter
        (fun c -> if Char.code c land 0xC0 <> 0x80 then incr count)
        line;
      !count)

(* The place of an error is inside the text, or one past the end of a
   line. *)
let place_is_inside text (place : Toml.position) =
  let lengths = Array.of_list (line_lengths text) in
  place.line >= 1
  && place.line <= Array.length lengths
  && place.column >= 1
  && place.column <= lengths.(place.line - 1) + 1

let damaged_document =
  let open QCheck2.Gen in
  let piece =
    oneof_list
      [
        "[";
        "]";
        "=";
        ".";
        "\"";
        "'";
        "\n";
        " ";
        "{";
        "}";
        ",";
        "#";
        "\\";
        "a";
        "1";
        "\xC3\xA9";
        "\r";
        "\000";
        "\xC3";
        "[[";
        "\"\"\"";
        "e";
        "-";
      ]
  in
  let edit text =
    let length = String.length text in
    let* at = int_range 0 length in
    oneof
      [
        (let+ piece = piece in
         String.sub text 0 at ^ piece ^ String.sub text at (length - at));
        (let+ cut = int_range 0 (min 4 (length - at)) in
         String.sub text 0 at ^ String.sub text (at + cut) (length - at - cut));
      ]
  in
  let* _, text = generated_document in
  let* edits = int_range 1 4 in
  let rec apply count text =
    if count = 0 then return text
    else
      let* text = edit text in
      apply (count - 1) text
  in
  apply edits text

let a_damaged_document_gives_a_document_or_an_error_inside_it =
  property ~count:500
    ~name:"a damaged document gives a table or an error inside the text"
    ~print:String.escaped damaged_document (fun text ->
      match Toml.parse text with
      | Ok _ -> true
      | Error error -> place_is_inside text (Toml.error_position error))

let any_bytes_give_a_document_or_an_error =
  property ~count:500 ~name:"any bytes give a table or an error inside the text"
    ~print:String.escaped Generators.any_text (fun text ->
      match Toml.parse text with
      | Ok _ -> true
      | Error error -> place_is_inside text (Toml.error_position error))

let render_path_reads_back =
  property ~name:"render_path gives a key path that reads back"
    ~print:QCheck2.Print.(list string)
    QCheck2.Gen.(
      list_size (int_range 1 4)
        (oneof [ oneof_list names; Generators.utf_8_string ]))
    (fun path ->
      let rec names_of table =
        match table with
        | [ ((key : Toml.key), node) ] ->
            key.name
            ::
            (match Toml.value node with
            | Toml.Table inner -> names_of inner
            | _ -> [])
        | _ -> []
      in
      match Toml.parse (Toml.render_path path ^ " = 1") with
      | Ok table -> names_of table = path
      | Error _ -> false)

let string_position_points_at_each_character =
  property ~name:"string_position points at each character of a literal string"
    ~print:String.escaped
    QCheck2.Gen.(
      map
        (String.map (function
          | '\'' | '\n' | '\r' -> 'x'
          | c -> if Char.code c < 0x20 || c = '\127' then 'x' else c))
        Generators.utf_8_string)
    (fun content ->
      let text = "\n  s = '" ^ content ^ "'" in
      let node = find (parse_ok text) [ "s" ] in
      let rec check offset =
        offset >= String.length content
        ||
        let length =
          Uchar.utf_decode_length (String.get_utf_8_uchar content offset)
        in
        match Toml.string_position node offset with
        | Some place ->
            String.equal
              (String.sub text (offset_of text place) length)
              (String.sub content offset length)
            && check (offset + length)
        | None -> false
      in
      check 0)

let tests =
  [
    Alcotest.test_case "gives the span of a key and of its value" `Quick
      gives_the_span_of_a_key_and_of_its_value;
    Alcotest.test_case "counts columns in code points" `Quick
      counts_columns_in_code_points;
    Alcotest.test_case "counts lines from 1" `Quick counts_lines_from_1;
    Alcotest.test_case "a byte order mark is not a column" `Quick
      a_byte_order_mark_is_not_a_column;
    Alcotest.test_case "a carriage return ends no line" `Quick
      a_carriage_return_ends_no_line;
    Alcotest.test_case "a value over lines stops on its last line" `Quick
      a_value_over_lines_stops_on_its_last_line;
    Alcotest.test_case "an inline table spans its braces" `Quick
      an_inline_table_spans_its_braces;
    Alcotest.test_case "a table takes the span of its key" `Quick
      a_table_takes_the_span_of_its_key;
    Alcotest.test_case "each part of a key has its span" `Quick
      each_part_of_a_key_has_its_span;
    Alcotest.test_case "a header that names a table gives its span" `Quick
      a_header_that_names_a_table_gives_its_span;
    Alcotest.test_case "a dotted table takes the place it is first written"
      `Quick a_dotted_table_takes_the_place_it_is_first_written;
    Alcotest.test_case "keys come in the order of their spans" `Quick
      keys_come_in_the_order_of_their_spans;
    Alcotest.test_case "key_start is the first part of a dotted key" `Quick
      key_start_is_the_first_part_of_a_dotted_key;
    Alcotest.test_case "key_start reads back over quoted parts" `Quick
      key_start_reads_back_over_quoted_parts;
    Alcotest.test_case "key_start inside an inline table" `Quick
      key_start_inside_an_inline_table;
    Alcotest.test_case "key_start of a table or a member is its span" `Quick
      key_start_of_a_table_or_a_member_is_its_span;
    Alcotest.test_case "string_position counts code points" `Quick
      string_position_counts_code_points;
    Alcotest.test_case "string_position of a basic string with no escape" `Quick
      string_position_of_a_basic_string_with_no_escape;
    Alcotest.test_case "string_position of an empty string" `Quick
      string_position_of_an_empty_string;
    Alcotest.test_case "string_position is None when the text differs" `Quick
      string_position_is_none_when_the_text_differs;
    Alcotest.test_case "string_position refuses an offset outside the string"
      `Quick string_position_refuses_an_offset_outside_the_string;
    Alcotest.test_case "reads every kind of value" `Quick
      reads_every_kind_of_value;
    Alcotest.test_case "every kind has a name" `Quick every_kind_has_a_name;
    Alcotest.test_case "gives the place of the first byte that is not UTF-8"
      `Quick gives_the_place_of_the_first_byte_that_is_not_utf_8;
    Alcotest.test_case "names a dotted key into a table that a header made"
      `Quick names_a_dotted_key_into_a_table_that_a_header_made;
    Alcotest.test_case "gives the message and the place of each form" `Quick
      gives_the_message_and_the_place_of_each_form;
    Alcotest.test_case "a document that nests too deep is refused" `Quick
      a_document_that_nests_too_deep_is_refused;
    Alcotest.test_case "read_message knows every construct" `Quick
      read_message_knows_every_construct;
    Alcotest.test_case "error_message names every construct" `Quick
      error_message_names_every_construct;
    Alcotest.test_case "read_message knows every expected form" `Quick
      read_message_knows_every_expected_form;
    Alcotest.test_case "read_message reads all three parts" `Quick
      read_message_reads_all_three_parts;
    Alcotest.test_case "read_message reads each duplicate key" `Quick
      read_message_reads_each_duplicate_key;
    Alcotest.test_case "read_message reads a dotted key with an empty name"
      `Quick read_message_reads_a_dotted_key_with_an_empty_name;
    Alcotest.test_case "read_message refuses an unknown form" `Quick
      read_message_refuses_an_unknown_form;
    Alcotest.test_case "error_message of an unrecognized form" `Quick
      error_message_of_an_unrecognized_form;
    Alcotest.test_case "error_message of a cause out of range with no construct"
      `Quick error_message_of_a_cause_out_of_range_with_no_construct;
    Alcotest.test_case "render_path quotes only what it must" `Quick
      render_path_quotes_only_what_it_must;
    a_generated_document_reads_back;
    a_damaged_document_gives_a_document_or_an_error_inside_it;
    any_bytes_give_a_document_or_an_error;
    render_path_reads_back;
    string_position_points_at_each_character;
  ]
