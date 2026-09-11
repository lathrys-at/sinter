(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let line = Alcotest.(check string)

let sorts_keys () =
  line "keys are sorted" {|{"a":1,"b":2,"c":3}|}
    (Jsonl.to_string
       [ ("c", Jsonl.int 3); ("a", Jsonl.int 1); ("b", Jsonl.int 2) ])

(* UTF-16 order and UTF-8 byte order disagree for this pair. A code
   point at U+10000 or above starts with a high surrogate, and a high
   surrogate is below U+E000. *)
let sorts_keys_by_utf16_code_units () =
  (* "\xf0\x90\x80\x80" is U+10000; "\xee\x80\x80" is U+E000. *)
  let astral = "\xf0\x90\x80\x80" in
  let private_use = "\xee\x80\x80" in
  Alcotest.(check bool)
    "U+10000 sorts before U+E000" true
    (Jsonl.compare_keys astral private_use < 0)

let sorts_a_whole_record_by_utf16_code_units () =
  let astral = "\xf0\x90\x80\x80" in
  let private_use = "\xee\x80\x80" in
  line "the astral key comes first"
    ("{\"" ^ astral ^ "\":1,\"" ^ private_use ^ "\":2}")
    (Jsonl.to_string [ (private_use, Jsonl.int 2); (astral, Jsonl.int 1) ])

(* A code point at U+10000 or above becomes two UTF-16 code units. Take
   the point less 0x10000; its ten upper bits make the high unit, which
   is that number and 0xD800; its ten lower bits make the low unit,
   which is that number and 0xDC00. So U+1F600 becomes 0xD83D and
   0xDE00.

   The two tests below each hold a pair of code points that differ in
   one of the two units only. A pair of that shape tells the two units
   apart; a pair of independent points does not. *)

(* "\xf0\x9f\x98\x80" is U+1F600 and "\xf0\x9f\x98\x81" is U+1F601.
   They share the high unit 0xD83D, and their low units are 0xDE00 and
   0xDE01. "\xf0\x90\x80\x80" is U+10000 and "\xf0\x90\x80\x81" is
   U+10001, with the high unit 0xD800 and the low units 0xDC00 and
   0xDC01. *)
let orders_two_astral_keys_by_their_low_unit () =
  Alcotest.(check bool)
    "U+1F600 sorts before U+1F601" true
    (Jsonl.compare_keys "\xf0\x9f\x98\x80" "\xf0\x9f\x98\x81" < 0);
  Alcotest.(check bool)
    "U+10000 sorts before U+10001" true
    (Jsonl.compare_keys "\xf0\x90\x80\x80" "\xf0\x90\x80\x81" < 0)

(* "\xf0\x9f\x88\x80" is U+1F200 and "\xf0\x9f\x98\x80" is U+1F600.
   They share the low unit 0xDE00, and their high units are 0xD83C and
   0xD83D. *)
let orders_two_astral_keys_by_their_high_unit () =
  Alcotest.(check bool)
    "U+1F200 sorts before U+1F600" true
    (Jsonl.compare_keys "\xf0\x9f\x88\x80" "\xf0\x9f\x98\x80" < 0)

let writes_every_value_type () =
  line "all four value types"
    {|{"empty":[],"flag":false,"n":-7,"names":["x","y"],"s":"t","sizes":[1,2]}|}
    (Jsonl.to_string
       [
         ("s", Jsonl.string "t");
         ("n", Jsonl.int (-7));
         ("flag", Jsonl.bool false);
         ("names", Jsonl.strings [ "x"; "y" ]);
         ("sizes", Jsonl.ints [ 1; 2 ]);
         ("empty", Jsonl.strings []);
       ])

let escapes_as_rfc_8785_requires () =
  line "the seven short escapes and the \\u00xx form"
    {|{"s":"\"\\\b\f\n\r\t\u0000\u001f"}|}
    (Jsonl.to_string [ ("s", Jsonl.string "\"\\\b\012\n\r\t\000\031") ])

(* RFC 8785 escapes no code point at U+0020 or above, except the
   quotation mark and the reverse solidus. *)
let keeps_text_above_the_ascii_range () =
  let text = "\xc3\xa9 \xe2\x82\xac \xf0\x9f\x94\xa5 / \x7f" in
  line "text passes through unescaped"
    ("{\"s\":\"" ^ text ^ "\"}")
    (Jsonl.to_string [ ("s", Jsonl.string text) ])

let rejects_a_repeated_field () =
  Alcotest.check_raises "the same field twice"
    (Invalid_argument
       "Sinter_core.Jsonl: the record holds the field \"a\" twice") (fun () ->
      ignore (Jsonl.to_string [ ("a", Jsonl.int 1); ("a", Jsonl.int 2) ]))

let rejects_an_integer_that_is_too_large () =
  let too_large = 9007199254740992 in
  Alcotest.check_raises "2^53 is out of range"
    (Invalid_argument
       "Sinter_core.Jsonl: an integer value is outside the range -(2^53-1) to \
        2^53-1") (fun () ->
      ignore (Jsonl.to_string [ ("n", Jsonl.int too_large) ]))

let accepts_the_largest_integer () =
  line "2^53-1 is in range" {|{"n":9007199254740991}|}
    (Jsonl.to_string [ ("n", Jsonl.int 9007199254740991) ]);
  line "-(2^53-1) is in range" {|{"n":-9007199254740991}|}
    (Jsonl.to_string [ ("n", Jsonl.int (-9007199254740991)) ])

let rejects_text_that_is_not_utf_8 () =
  Alcotest.check_raises "a lone continuation byte"
    (Invalid_argument "Sinter_core.Jsonl: a string value is not valid UTF-8")
    (fun () -> ignore (Jsonl.to_string [ ("s", Jsonl.string "\xff") ]))

let writes_one_line_with_lf () =
  let file = Filename.temp_file "sinter-jsonl" ".jsonl" in
  let channel = open_out_bin file in
  Jsonl.output channel [ ("a", Jsonl.int 1) ];
  close_out channel;
  let channel = open_in_bin file in
  let contents = really_input_string channel (in_channel_length channel) in
  close_in channel;
  Sys.remove file;
  line "the line ends with LF" "{\"a\":1}\n" contents

(* Properties. *)

module Gen = QCheck2.Gen

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let same_scalar (expected : Jsonl.scalar) (json : Yojson.Safe.t) =
  match (expected, json) with
  | Jsonl.String a, `String b -> String.equal a b
  | Jsonl.Int a, `Int b -> Int.equal a b
  | Jsonl.Bool a, `Bool b -> Bool.equal a b
  | _ -> false

let same_value (expected : Jsonl.value) (json : Yojson.Safe.t) =
  match (expected, json) with
  | Jsonl.Scalar scalar, _ -> same_scalar scalar json
  | Jsonl.Array items, `List parsed ->
      List.length items = List.length parsed
      && List.for_all2 same_scalar items parsed
  | Jsonl.Array _, _ -> false

let fields_of_line line =
  match Yojson.Safe.from_string line with
  | `Assoc fields -> Some fields
  | _ -> None

(* The bytes of a string in UTF-16, big-endian. Comparing two of these
   byte for byte gives the order of the two code unit sequences, so
   this is a second way to reach the order that compare_keys promises. *)
let utf_16be text =
  let buffer = Buffer.create (2 * String.length text) in
  let offset = ref 0 in
  while !offset < String.length text do
    let decoded = String.get_utf_8_uchar text !offset in
    offset := !offset + Uchar.utf_decode_length decoded;
    Buffer.add_utf_16be_uchar buffer (Uchar.utf_decode_uchar decoded)
  done;
  Buffer.contents buffer

let sign n = compare n 0

(* A line is a JSON object with the fields of the record. *)
let a_line_parses_to_the_same_fields_and_values =
  property ~name:"a line parses to an object with the same fields and values"
    ~print:Generators.print_record Generators.record (fun record ->
      match fields_of_line (Jsonl.to_string record) with
      | None -> false
      | Some fields ->
          List.length fields = List.length record
          && List.for_all
               (fun (name, value) ->
                 match List.assoc_opt name fields with
                 | None -> false
                 | Some json -> same_value value json)
               record)

let a_line_holds_its_keys_in_compare_keys_order =
  property ~name:"a line holds its keys in compare_keys order"
    ~print:Generators.print_record Generators.record (fun record ->
      match fields_of_line (Jsonl.to_string record) with
      | None -> false
      | Some fields ->
          let names = List.map fst fields in
          List.equal String.equal names (List.sort Jsonl.compare_keys names))

(* Whitespace between the tokens is insignificant, and a canonical
   line holds none of it. Whitespace inside a string is part of the
   value. *)
let a_line_holds_no_whitespace_outside_a_string =
  property ~name:"a line holds no whitespace outside a string"
    ~print:Generators.print_record Generators.record (fun record ->
      let line = Jsonl.to_string record in
      let rec scan offset ~inside ~escaped =
        if offset >= String.length line then true
        else
          let c = line.[offset] in
          let next = scan (offset + 1) in
          if inside then
            if escaped then next ~inside:true ~escaped:false
            else if c = '\\' then next ~inside:true ~escaped:true
            else if c = '"' then next ~inside:false ~escaped:false
            else next ~inside:true ~escaped:false
          else if c = '"' then next ~inside:true ~escaped:false
          else if c = ' ' || c = '\t' || c = '\n' || c = '\r' then false
          else next ~inside:false ~escaped:false
      in
      scan 0 ~inside:false ~escaped:false)

(* RFC 8785 escapes the quotation mark, the reverse solidus, and every
   code point below U+0020, and nothing else. *)
let a_line_holds_no_byte_below_u_0020 =
  property ~name:"a line holds no byte below U+0020"
    ~print:Generators.print_record Generators.record (fun record ->
      String.for_all (fun c -> Char.code c >= 0x20) (Jsonl.to_string record))

let a_line_escapes_only_what_rfc_8785_escapes =
  property ~name:"a line holds only the escapes that RFC 8785 asks for"
    ~print:Generators.print_record Generators.record (fun record ->
      let line = Jsonl.to_string record in
      let length = String.length line in
      let is_hex c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') in
      let rec scan offset ~inside =
        if offset >= length then true
        else
          let c = line.[offset] in
          if not inside then scan (offset + 1) ~inside:(c = '"')
          else if c = '"' then scan (offset + 1) ~inside:false
          else if c <> '\\' then scan (offset + 1) ~inside:true
          else if offset + 1 >= length then false
          else
            match line.[offset + 1] with
            | '"' | '\\' | 'b' | 'f' | 'n' | 'r' | 't' ->
                scan (offset + 2) ~inside:true
            | 'u' ->
                offset + 6 <= length
                && String.equal (String.sub line (offset + 2) 2) "00"
                && is_hex line.[offset + 4]
                && is_hex line.[offset + 5]
                && int_of_string ("0x" ^ String.sub line (offset + 2) 4) < 0x20
                && scan (offset + 6) ~inside:true
            | _ -> false
      in
      scan 0 ~inside:false)

let raises_invalid_argument f =
  try
    ignore (f ());
    false
  with Invalid_argument _ -> true

let to_string_accepts_every_well_formed_record =
  property ~name:"to_string raises on no well-formed record"
    ~print:Generators.print_record Generators.record (fun record ->
      not (raises_invalid_argument (fun () -> Jsonl.to_string record)))

let to_string_rejects_a_repeated_field_name =
  property ~name:"to_string raises on a repeated field name"
    ~print:Generators.print_record Generators.record_with_a_repeated_field
    (fun record -> raises_invalid_argument (fun () -> Jsonl.to_string record))

let to_string_rejects_an_integer_outside_the_range =
  property ~name:"to_string raises on an integer outside the range"
    ~print:Generators.print_record
    Generators.record_with_an_integer_out_of_range (fun record ->
      raises_invalid_argument (fun () -> Jsonl.to_string record))

let to_string_rejects_a_string_that_is_not_utf_8 =
  property ~name:"to_string raises on a string that is not UTF-8"
    ~print:Generators.print_record
    Generators.record_with_a_string_that_is_not_utf_8 (fun record ->
      raises_invalid_argument (fun () -> Jsonl.to_string record))

(* compare_keys takes any string, so the order properties below run
   over strings that are not UTF-8 as well. *)
let name =
  Gen.oneof
    [ Generators.key; Generators.utf_8_string; Generators.not_utf_8_string ]

let utf_8_name = Gen.oneof [ Generators.key; Generators.utf_8_string ]
let two_names = Gen.pair name name
let three_names = Gen.triple name name name
let print_two = QCheck2.Print.(pair string string)
let print_three = QCheck2.Print.(triple string string string)

let compare_keys_agrees_with_utf_16_code_unit_order =
  property ~name:"compare_keys agrees with UTF-16 code unit order"
    ~print:print_two two_names (fun (a, b) ->
      sign (Jsonl.compare_keys a b)
      = sign (String.compare (utf_16be a) (utf_16be b)))

let compare_keys_is_reflexive =
  property ~name:"compare_keys gives 0 for a name and itself"
    ~print:QCheck2.Print.string name (fun a -> Jsonl.compare_keys a a = 0)

let compare_keys_is_antisymmetric =
  property ~name:"compare_keys reverses when its two names swap"
    ~print:print_two two_names (fun (a, b) ->
      sign (Jsonl.compare_keys a b) = -sign (Jsonl.compare_keys b a))

let compare_keys_is_transitive =
  property ~name:"compare_keys is transitive" ~print:print_three three_names
    (fun (a, b, c) ->
      let ab = Jsonl.compare_keys a b and bc = Jsonl.compare_keys b c in
      if ab <= 0 && bc <= 0 then Jsonl.compare_keys a c <= 0
      else if ab >= 0 && bc >= 0 then Jsonl.compare_keys a c >= 0
      else true)

(* Two strings of valid UTF-8 that differ hold different code points,
   so their code unit sequences differ as well. *)
let compare_keys_separates_two_names_that_differ =
  property
    ~name:"compare_keys gives 0 for two names of UTF-8 only when they are equal"
    ~print:print_two (Gen.pair utf_8_name utf_8_name) (fun (a, b) ->
      Jsonl.compare_keys a b = 0 = String.equal a b)

let a_line_is_valid_utf_8 =
  property ~name:"a line is valid UTF-8" ~print:Generators.print_record
    Generators.record (fun record ->
      let line = Jsonl.to_string record in
      let rec walk offset =
        offset >= String.length line
        ||
        let decoded = String.get_utf_8_uchar line offset in
        Uchar.utf_decode_is_valid decoded
        && walk (offset + Uchar.utf_decode_length decoded)
      in
      walk 0)

(* The writer sorts the fields, so the order in which a caller gives
   them does not reach the line. *)
let to_string_ignores_the_order_of_the_fields =
  property ~name:"to_string gives one line for a record in any order"
    ~print:(fun (record, _) -> Generators.print_record record)
    (Gen.bind Generators.record (fun record ->
         Gen.pair (Gen.return record) (Gen.shuffle_list record)))
    (fun (record, shuffled) ->
      String.equal (Jsonl.to_string record) (Jsonl.to_string shuffled))

let output_writes_the_line_and_one_lf =
  property ~count:200 ~name:"output writes the line of to_string and one LF"
    ~print:Generators.print_record Generators.record (fun record ->
      let file = Filename.temp_file "sinter-jsonl" ".jsonl" in
      Fun.protect
        ~finally:(fun () -> Sys.remove file)
        (fun () ->
          let channel = open_out_bin file in
          Fun.protect
            ~finally:(fun () -> close_out_noerr channel)
            (fun () -> Jsonl.output channel record);
          let channel = open_in_bin file in
          let written =
            Fun.protect
              ~finally:(fun () -> close_in_noerr channel)
              (fun () ->
                really_input_string channel (in_channel_length channel))
          in
          String.equal written (Jsonl.to_string record ^ "\n")))

let properties =
  [
    a_line_parses_to_the_same_fields_and_values;
    a_line_holds_its_keys_in_compare_keys_order;
    a_line_holds_no_whitespace_outside_a_string;
    a_line_holds_no_byte_below_u_0020;
    a_line_escapes_only_what_rfc_8785_escapes;
    to_string_accepts_every_well_formed_record;
    to_string_rejects_a_repeated_field_name;
    to_string_rejects_an_integer_outside_the_range;
    to_string_rejects_a_string_that_is_not_utf_8;
    compare_keys_agrees_with_utf_16_code_unit_order;
    compare_keys_is_reflexive;
    compare_keys_is_antisymmetric;
    compare_keys_is_transitive;
    compare_keys_separates_two_names_that_differ;
    a_line_is_valid_utf_8;
    to_string_ignores_the_order_of_the_fields;
    output_writes_the_line_and_one_lf;
  ]

(* The runtime refuses a write to a closed channel in the call. The
   message of that failure comes from the C library, so the test reads
   the class of the exception and not its words. *)
let reports_a_channel_that_cannot_be_written () =
  let file = Filename.temp_file "sinter-jsonl" ".jsonl" in
  let channel = open_out_bin file in
  close_out channel;
  let failed =
    Fun.protect
      ~finally:(fun () -> Sys.remove file)
      (fun () ->
        try
          Jsonl.output channel [ ("a", Jsonl.int 1) ];
          false
        with Sys_error _ -> true)
  in
  Alcotest.(check bool) "a closed channel raises Sys_error" true failed

let accepts_text_that_is_utf_8 () =
  Alcotest.(check bool)
    "one code point of each length" true
    (Jsonl.is_utf_8 "a\xc3\xa9\xe2\x82\xac\xf0\x9f\x92\xa1")

let refuses_text_that_is_not_utf_8 () =
  Alcotest.(check bool)
    "a lone continuation byte" false (Jsonl.is_utf_8 "a\xff")

let tests =
  [
    Alcotest.test_case "reports a channel that cannot be written" `Quick
      reports_a_channel_that_cannot_be_written;
    Alcotest.test_case "sorts keys" `Quick sorts_keys;
    Alcotest.test_case "sorts keys by UTF-16 code units" `Quick
      sorts_keys_by_utf16_code_units;
    Alcotest.test_case "sorts a whole record by UTF-16 code units" `Quick
      sorts_a_whole_record_by_utf16_code_units;
    Alcotest.test_case "orders two astral keys by their low unit" `Quick
      orders_two_astral_keys_by_their_low_unit;
    Alcotest.test_case "orders two astral keys by their high unit" `Quick
      orders_two_astral_keys_by_their_high_unit;
    Alcotest.test_case "writes every value type" `Quick writes_every_value_type;
    Alcotest.test_case "escapes as RFC 8785 requires" `Quick
      escapes_as_rfc_8785_requires;
    Alcotest.test_case "keeps text above the ASCII range" `Quick
      keeps_text_above_the_ascii_range;
    Alcotest.test_case "rejects a repeated field" `Quick
      rejects_a_repeated_field;
    Alcotest.test_case "rejects an integer that is too large" `Quick
      rejects_an_integer_that_is_too_large;
    Alcotest.test_case "accepts the largest integer" `Quick
      accepts_the_largest_integer;
    Alcotest.test_case "rejects text that is not UTF-8" `Quick
      rejects_text_that_is_not_utf_8;
    Alcotest.test_case "writes one line with LF" `Quick writes_one_line_with_lf;
    Alcotest.test_case "accepts text that is UTF-8" `Quick
      accepts_text_that_is_utf_8;
    Alcotest.test_case "refuses text that is not UTF-8" `Quick
      refuses_text_that_is_not_utf_8;
  ]
  @ properties
