(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Raw = Sinter_bridge.Toml_raw

let property ?(count = 300) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

(* The layout that the bridge writes, for the tests. Each writer
   records the offset of each length field of a string, and the length
   it holds, so that a damaged buffer can aim at one. *)

let add_u32 buffer value = Buffer.add_int32_le buffer (Int32.of_int value)

let add_string buffer runs text =
  runs := (Buffer.length buffer, String.length text) :: !runs;
  add_u32 buffer (String.length text);
  Buffer.add_string buffer text

let add_header buffer ~kind =
  Buffer.add_string buffer "SBR1";
  add_u32 buffer kind;
  add_u32 buffer 1;
  add_u32 buffer 0

let add_datetime buffer (datetime : Raw.datetime) =
  let parts =
    (if Option.is_some datetime.date then 1 else 0)
    lor (if Option.is_some datetime.time then 2 else 0)
    lor if Option.is_some datetime.offset then 4 else 0
  in
  add_u32 buffer parts;
  let year, month, day = Option.value datetime.date ~default:(0, 0, 0) in
  List.iter (add_u32 buffer) [ year; month; day ];
  let hour, minute, second, nanosecond =
    Option.value datetime.time ~default:(0, 0, 0, 0)
  in
  List.iter (add_u32 buffer) [ hour; minute; second; nanosecond ];
  match datetime.offset with
  | Some (Raw.Minutes minutes) ->
      add_u32 buffer 1;
      add_u32 buffer (minutes land 0xFFFFFFFF)
  | Some Raw.Utc | None ->
      add_u32 buffer 0;
      add_u32 buffer 0

let rec add_item buffer runs (item : Raw.item) =
  let tag =
    match item.value with
    | Raw.String _ -> 0
    | Raw.Integer _ -> 1
    | Raw.Float _ -> 2
    | Raw.Boolean _ -> 3
    | Raw.Datetime _ -> 4
    | Raw.Array _ -> 5
    | Raw.Table _ -> 6
    | Raw.Array_of_tables _ -> 7
    | Raw.Inline_table _ -> 8
  in
  add_u32 buffer tag;
  add_u32 buffer item.start_byte;
  add_u32 buffer item.end_byte;
  match item.value with
  | Raw.String text -> add_string buffer runs text
  | Raw.Integer number -> Buffer.add_int64_le buffer number
  | Raw.Float number -> Buffer.add_int64_le buffer (Int64.bits_of_float number)
  | Raw.Boolean flag -> add_u32 buffer (Bool.to_int flag)
  | Raw.Datetime datetime -> add_datetime buffer datetime
  | Raw.Array items ->
      add_u32 buffer (List.length items);
      List.iter (add_item buffer runs) items
  | Raw.Table table | Raw.Inline_table table -> add_table buffer runs table
  | Raw.Array_of_tables tables ->
      add_u32 buffer (List.length tables);
      List.iter (add_table buffer runs) tables

and add_table buffer runs table =
  add_u32 buffer (List.length table);
  List.iter
    (fun (entry : Raw.entry) ->
      add_string buffer runs entry.name;
      add_u32 buffer entry.key_start;
      add_u32 buffer entry.key_end;
      add_item buffer runs entry.item)
    table

let document_bytes table =
  let buffer = Buffer.create 256 and runs = ref [] in
  add_header buffer ~kind:3;
  add_table buffer runs table;
  (Buffer.contents buffer, List.rev !runs)

let error_bytes (error : Raw.error) =
  let buffer = Buffer.create 256 and runs = ref [] in
  add_header buffer ~kind:4;
  (match error with
  | Raw.Crate_error { start_byte; end_byte; message } ->
      List.iter (add_u32 buffer) [ 0; start_byte; end_byte ];
      add_string buffer runs message
  | Raw.Header_table { start_byte; end_byte; key; table; array; rest } ->
      List.iter (add_u32 buffer) [ 1; start_byte; end_byte ];
      add_string buffer runs key;
      add_u32 buffer (List.length table);
      List.iter (add_string buffer runs) table;
      add_u32 buffer (Bool.to_int array);
      add_u32 buffer (List.length rest);
      List.iter (add_string buffer runs) rest);
  (Buffer.contents buffer, List.rev !runs)

(* Generators. Every span lies inside a text of [length] bytes. *)

let length = 64

let span =
  QCheck2.Gen.(
    let* start = int_range 0 length in
    let+ stop = int_range start length in
    (start, stop))

let datetime =
  let open QCheck2.Gen in
  let date = triple (int_range 0 9999) (int_range 1 12) (int_range 1 31) in
  let time =
    quad (int_range 0 23) (int_range 0 59) (int_range 0 60)
      (int_range 0 999_999_999)
  in
  let offset =
    oneof
      [
        return Raw.Utc;
        map (fun minutes -> Raw.Minutes minutes) (int_range (-1439) 1439);
      ]
  in
  oneof
    [
      map
        (fun date -> { Raw.date = Some date; time = None; offset = None })
        date;
      map
        (fun time -> { Raw.date = None; time = Some time; offset = None })
        time;
      map2
        (fun date time ->
          { Raw.date = Some date; time = Some time; offset = None })
        date time;
      map3
        (fun date time offset ->
          { Raw.date = Some date; time = Some time; offset = Some offset })
        date time offset;
    ]

let name =
  QCheck2.Gen.oneof [ Generators.utf_8_string; Generators.ascii_string ]

let raw_table =
  let open QCheck2.Gen in
  sized_size (int_range 0 3)
  @@ fix (fun self depth ->
      let scalar =
        oneof
          [
            map (fun text -> Raw.String text) Generators.utf_8_string;
            map (fun number -> Raw.Integer number) int64;
            map (fun number -> Raw.Float number) float;
            map (fun flag -> Raw.Boolean flag) bool;
            map (fun datetime -> Raw.Datetime datetime) datetime;
          ]
      in
      let item value =
        let+ value = value and+ start_byte, end_byte = span in
        { Raw.value; start_byte; end_byte }
      in
      let value =
        if depth = 0 then scalar
        else
          oneof
            [
              scalar;
              map
                (fun items -> Raw.Array items)
                (list_size (int_range 0 3) (item scalar));
              map (fun table -> Raw.Table table) (self (depth - 1));
              map (fun table -> Raw.Inline_table table) (self (depth - 1));
              map
                (fun tables -> Raw.Array_of_tables tables)
                (list_size (int_range 0 2) (self (depth - 1)));
            ]
      in
      list_size (int_range 0 3)
        (let+ name = name
         and+ key_start, key_end = span
         and+ item = item value in
         { Raw.name; key_start; key_end; item }))

let raw_error =
  let open QCheck2.Gen in
  let names = list_size (int_range 0 3) name in
  oneof
    [
      (let+ start_byte, end_byte = span
       and+ message = Generators.utf_8_string in
       Raw.Crate_error { start_byte; end_byte; message });
      (let+ start_byte, end_byte = span
       and+ key = name
       and+ table = names
       and+ array = bool
       and+ rest = names in
       Raw.Header_table { start_byte; end_byte; key; table; array; rest });
    ]

(* Floats compare by their bits, so that two NaN are equal. *)
let rec same_value (a : Raw.value) (b : Raw.value) =
  match (a, b) with
  | Raw.Float a, Raw.Float b ->
      Int64.equal (Int64.bits_of_float a) (Int64.bits_of_float b)
  | Raw.Array a, Raw.Array b ->
      List.length a = List.length b && List.for_all2 same_item a b
  | Raw.Table a, Raw.Table b | Raw.Inline_table a, Raw.Inline_table b ->
      same_table a b
  | Raw.Array_of_tables a, Raw.Array_of_tables b ->
      List.length a = List.length b && List.for_all2 same_table a b
  | _ -> a = b

and same_item (a : Raw.item) (b : Raw.item) =
  a.start_byte = b.start_byte
  && a.end_byte = b.end_byte && same_value a.value b.value

and same_table a b =
  List.length a = List.length b
  && List.for_all2
       (fun (a : Raw.entry) (b : Raw.entry) ->
         String.equal a.name b.name && a.key_start = b.key_start
         && a.key_end = b.key_end && same_item a.item b.item)
       a b

let print_buffer = Generators.print_buffer

let raises_error f =
  match f () with _ -> false | exception Sinter_bridge.Error _ -> true

let error_message f =
  match f () with
  | _ -> "no failure"
  | exception Sinter_bridge.Error message -> message

let decode = Raw.decode ~length

let decode_gives_back_the_document_that_was_encoded =
  property ~name:"decode gives back the document that was encoded"
    ~print:(fun table -> print_buffer (fst (document_bytes table)))
    raw_table
    (fun table ->
      match decode (fst (document_bytes table)) with
      | Ok decoded -> same_table decoded table
      | Error _ -> false)

let decode_gives_back_the_error_that_was_encoded =
  property ~name:"decode gives back the error that was encoded"
    ~print:(fun error -> print_buffer (fst (error_bytes error)))
    raw_error
    (fun error -> decode (fst (error_bytes error)) = Error error)

let decode_rejects_a_damaged_document =
  property ~name:"decode raises Error on a damaged document buffer"
    ~print:Generators.print_damaged
    QCheck2.Gen.(
      let* table = raw_table in
      Generators.damaged (document_bytes table) ~kind:3 ~count:1)
    (fun (_, buffer) -> raises_error (fun () -> decode buffer))

let decode_rejects_a_damaged_error =
  property ~name:"decode raises Error on a damaged error buffer"
    ~print:Generators.print_damaged
    QCheck2.Gen.(
      let* error = raw_error in
      Generators.damaged (error_bytes error) ~kind:4 ~count:1)
    (fun (_, buffer) -> raises_error (fun () -> decode buffer))

let decode_is_total =
  property ~count:2000 ~name:"decode gives a result or an Error for any bytes"
    ~print:print_buffer
    QCheck2.Gen.(
      oneof
        [
          Generators.buffer_bytes;
          map (fun table -> fst (document_bytes table)) raw_table;
          (let* table = raw_table in
           let buffer = fst (document_bytes table) in
           let* at = int_range 0 (String.length buffer) in
           let+ piece = string_size (int_range 1 6) in
           let at = min at (String.length buffer) in
           String.sub buffer 0 at ^ piece
           ^
           let after = min (String.length buffer) (at + String.length piece) in
           String.sub buffer after (String.length buffer - after));
        ])
    (fun buffer ->
      match decode buffer with
      | _ -> true
      | exception Sinter_bridge.Error _ -> true)

(* One whole buffer, with one field written over. *)
let with_u32 buffer offset value =
  let bytes = Bytes.of_string buffer in
  Bytes.set_int32_le bytes offset (Int32.of_int value);
  Bytes.to_string bytes

let one_string_entry =
  [
    {
      Raw.name = "a";
      key_start = 0;
      key_end = 1;
      item = { value = Raw.String "x"; start_byte = 4; end_byte = 7 };
    };
  ]

(* The header is 16 bytes, and the count of the table 4 more. The entry
   starts with the key "a" (4 + 1 bytes) and its span (8 bytes), so the
   tag of its value sits at byte 33, and the span of the value at 37. *)
let names_a_span_that_runs_past_the_text () =
  let buffer = fst (document_bytes one_string_entry) in
  Alcotest.(check string)
    "the message names the span"
    "the bridge returned a malformed buffer: a span runs past the end of the \
     text"
    (error_message (fun () -> decode (with_u32 buffer 41 (length + 1))))

let names_a_span_that_ends_before_it_starts () =
  let buffer = fst (document_bytes one_string_entry) in
  Alcotest.(check string)
    "the message names the span"
    "the bridge returned a malformed buffer: a span ends before it starts"
    (error_message (fun () -> decode (with_u32 buffer 37 8)))

let accepts_a_span_that_ends_at_the_end_of_the_text () =
  let buffer = fst (document_bytes one_string_entry) in
  match decode (with_u32 buffer 41 length) with
  | Ok [ { item = { end_byte; _ }; _ } ] ->
      Alcotest.(check int) "the end of the span" length end_byte
  | _ -> Alcotest.fail "the buffer did not decode to one entry"

let names_an_unknown_tag () =
  let buffer = fst (document_bytes one_string_entry) in
  Alcotest.(check string)
    "the message names the tag"
    "the bridge returned a malformed buffer: a TOML value has the tag 9"
    (error_message (fun () -> decode (with_u32 buffer 33 9)))

let boolean_buffer flag =
  let buffer =
    fst
      (document_bytes
         [
           {
             Raw.name = "a";
             key_start = 0;
             key_end = 1;
             item = { value = Raw.Boolean true; start_byte = 4; end_byte = 8 };
           };
         ])
  in
  with_u32 buffer 45 flag

let names_a_boolean_that_is_not_0_or_1 () =
  Alcotest.(check string)
    "the message names the value"
    "the bridge returned a malformed buffer: a boolean is 2, not 0 or 1"
    (error_message (fun () -> decode (boolean_buffer 2)))

let reads_a_boolean_of_0_as_false () =
  match decode (boolean_buffer 0) with
  | Ok [ { item = { value = Raw.Boolean false; _ }; _ } ] -> ()
  | _ -> Alcotest.fail "the boolean is not false"

let datetime_buffer (datetime : Raw.datetime) =
  fst
    (document_bytes
       [
         {
           Raw.name = "a";
           key_start = 0;
           key_end = 1;
           item =
             { value = Raw.Datetime datetime; start_byte = 4; end_byte = 8 };
         };
       ])

let a_date = { Raw.date = Some (1979, 5, 27); time = None; offset = None }

(* The parts of the date sit at byte 45, and the kind of the offset at
   77. *)
let names_the_parts_of_a_datetime_it_does_not_know () =
  List.iter
    (fun parts ->
      Alcotest.(check string)
        (Printf.sprintf "the parts %d" parts)
        (Printf.sprintf
           "the bridge returned a malformed buffer: a date or time holds the \
            parts %d"
           parts)
        (error_message (fun () ->
             decode (with_u32 (datetime_buffer a_date) 45 parts))))
    [ 0; 4; 5; 6; 8 ]

let names_an_offset_kind_it_does_not_know () =
  Alcotest.(check string)
    "the message names the kind"
    "the bridge returned a malformed buffer: the offset kind is 2"
    (error_message (fun () -> decode (with_u32 (datetime_buffer a_date) 77 2)))

let reads_a_negative_offset () =
  let datetime =
    {
      Raw.date = Some (1979, 5, 27);
      time = Some (7, 32, 0, 0);
      offset = Some (Raw.Minutes (-1));
    }
  in
  match decode (datetime_buffer datetime) with
  | Ok [ { item = { value = Raw.Datetime decoded; _ }; _ } ] ->
      Alcotest.(check bool) "the offset is -1 minute" true (decoded = datetime)
  | _ -> Alcotest.fail "the date and time did not decode"

let names_an_error_form_it_does_not_know () =
  let buffer =
    fst
      (error_bytes
         (Raw.Crate_error { start_byte = 0; end_byte = 1; message = "m" }))
  in
  Alcotest.(check string)
    "the message names the form"
    "the bridge returned a malformed buffer: a TOML error has the form 2"
    (error_message (fun () -> decode (with_u32 buffer 16 2)))

let names_an_array_flag_that_is_not_0_or_1 () =
  let buffer =
    fst
      (error_bytes
         (Raw.Header_table
            {
              start_byte = 0;
              end_byte = 1;
              key = "k";
              table = [];
              array = false;
              rest = [];
            }))
  in
  (* form, span, the key (4 + 1), and the count of the table: the flag
     sits at byte 16 + 12 + 5 + 4. *)
  Alcotest.(check string)
    "the message names the flag"
    "the bridge returned a malformed buffer: the array flag is 3, not 0 or 1"
    (error_message (fun () -> decode (with_u32 buffer 37 3)))

let names_a_kind_that_is_not_a_toml_kind () =
  Alcotest.(check string)
    "the message names the kinds"
    "the bridge returned a malformed buffer: the kind is 2, and 3 or 4 was \
     expected"
    (error_message (fun () ->
         decode (Generators.encode_digest (String.make 32 'x'))))

let names_a_buffer_shorter_than_the_header () =
  Alcotest.(check string)
    "the message names the header"
    "the bridge returned a malformed buffer: the buffer is shorter than the \
     header"
    (error_message (fun () ->
         decode "SBR1\003\000\000\000\001\000\000\000\000\000\000"))

let names_a_document_buffer_with_two_records () =
  let buffer = fst (document_bytes []) in
  Alcotest.(check string)
    "the message names the count"
    "the bridge returned a malformed buffer: a TOML buffer holds 2 records, \
     and 1 was expected"
    (error_message (fun () -> decode (with_u32 buffer 8 2)))

(* Through the bridge. *)

let parse_gives_the_keys_and_their_byte_spans () =
  match Raw.parse "a = \"x\"\n[t]\nb.c = 1\n" with
  | Ok
      [
        {
          name = "a";
          key_start = 0;
          key_end = 1;
          item = { value = Raw.String "x"; start_byte = 4; end_byte = 7 };
        };
        {
          name = "t";
          key_start = 9;
          key_end = 10;
          item =
            {
              value =
                Raw.Table
                  [
                    {
                      name = "b";
                      key_start = 12;
                      key_end = 13;
                      item =
                        {
                          value =
                            Raw.Table
                              [
                                {
                                  name = "c";
                                  key_start = 14;
                                  key_end = 15;
                                  item =
                                    {
                                      value = Raw.Integer 1L;
                                      start_byte = 18;
                                      end_byte = 19;
                                    };
                                };
                              ];
                          start_byte = 12;
                          end_byte = 13;
                        };
                    };
                  ];
              start_byte = 9;
              end_byte = 10;
            };
        };
      ] ->
      ()
  | Ok _ -> Alcotest.fail "the document differs"
  | Error _ -> Alcotest.fail "the document was rejected"

let parse_gives_the_error_of_the_reader () =
  match Raw.parse "a = \n" with
  | Error (Raw.Crate_error { start_byte = 4; end_byte = 5; message }) ->
      Alcotest.(check string)
        "the message of the reader" "invalid string\nexpected `\"`, `'`" message
  | _ -> Alcotest.fail "no error of the reader"

let parse_finds_a_dotted_key_into_a_header_table () =
  Alcotest.(check bool)
    "the error names the table" true
    (Raw.parse "[a.b.c]\nz = 9\n[a]\nb.ct = 1\n"
    = Error
        (Raw.Header_table
           {
             start_byte = 18;
             end_byte = 22;
             key = "b.ct";
             table = [ "a"; "b" ];
             array = false;
             rest = [ "ct" ];
           }))

let parse_refuses_text_that_is_not_utf_8 () =
  Alcotest.(check string)
    "the message of the bridge" "the TOML text is not UTF-8"
    (error_message (fun () -> Raw.parse "a = \"\xff\""))

let tests =
  [
    Alcotest.test_case "names a span that runs past the text" `Quick
      names_a_span_that_runs_past_the_text;
    Alcotest.test_case "names a span that ends before it starts" `Quick
      names_a_span_that_ends_before_it_starts;
    Alcotest.test_case "accepts a span that ends at the end of the text" `Quick
      accepts_a_span_that_ends_at_the_end_of_the_text;
    Alcotest.test_case "names an unknown tag" `Quick names_an_unknown_tag;
    Alcotest.test_case "names a boolean that is not 0 or 1" `Quick
      names_a_boolean_that_is_not_0_or_1;
    Alcotest.test_case "reads a boolean of 0 as false" `Quick
      reads_a_boolean_of_0_as_false;
    Alcotest.test_case "names the parts of a datetime it does not know" `Quick
      names_the_parts_of_a_datetime_it_does_not_know;
    Alcotest.test_case "names an offset kind it does not know" `Quick
      names_an_offset_kind_it_does_not_know;
    Alcotest.test_case "reads a negative offset" `Quick reads_a_negative_offset;
    Alcotest.test_case "names an error form it does not know" `Quick
      names_an_error_form_it_does_not_know;
    Alcotest.test_case "names an array flag that is not 0 or 1" `Quick
      names_an_array_flag_that_is_not_0_or_1;
    Alcotest.test_case "names a kind that is not a TOML kind" `Quick
      names_a_kind_that_is_not_a_toml_kind;
    Alcotest.test_case "names a buffer shorter than the header" `Quick
      names_a_buffer_shorter_than_the_header;
    Alcotest.test_case "names a document buffer with two records" `Quick
      names_a_document_buffer_with_two_records;
    Alcotest.test_case "parse gives the keys and their byte spans" `Quick
      parse_gives_the_keys_and_their_byte_spans;
    Alcotest.test_case "parse gives the error of the reader" `Quick
      parse_gives_the_error_of_the_reader;
    Alcotest.test_case "parse finds a dotted key into a header table" `Quick
      parse_finds_a_dotted_key_into_a_header_table;
    Alcotest.test_case "parse refuses text that is not UTF-8" `Quick
      parse_refuses_text_that_is_not_utf_8;
    decode_gives_back_the_document_that_was_encoded;
    decode_gives_back_the_error_that_was_encoded;
    decode_rejects_a_damaged_document;
    decode_rejects_a_damaged_error;
    decode_is_total;
  ]
