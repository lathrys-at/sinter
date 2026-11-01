(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let astral = "\xf0\x90\x80\x80"
let private_use = "\xee\x80\x80"

let printed value =
  match Json.to_string value with
  | Ok text -> text
  | Error error ->
      Alcotest.failf "the printer refused %s"
        (Generators.print_json_error error)

let line = Alcotest.(check string)

let refused expected value =
  match Json.to_string value with
  | Ok text -> Alcotest.failf "the printer wrote %s" text
  | Error error ->
      Alcotest.(check string)
        "the error"
        (Generators.print_json_error expected)
        (Generators.print_json_error error)

let writes_every_kind_of_value () =
  line "a nested value"
    {|{"a":[null,true,false,-7,"s",[],{}],"b":{"c":{"d":[1]}}}|}
    (printed
       (Json.Object
          [
            ( "b",
              Json.Object
                [ ("c", Json.Object [ ("d", Json.Array [ Json.Int 1 ]) ]) ] );
            ( "a",
              Json.Array
                [
                  Json.Null;
                  Json.Bool true;
                  Json.Bool false;
                  Json.Int (-7);
                  Json.String "s";
                  Json.Array [];
                  Json.Object [];
                ] );
          ]))

let writes_a_value_that_is_not_an_object () =
  line "null" "null" (printed Json.Null);
  line "a string" {|"x"|} (printed (Json.String "x"));
  line "an array" "[1,2]" (printed (Json.Array [ Json.Int 1; Json.Int 2 ]))

let sorts_keys_by_utf16_code_units_where_utf8_disagrees () =
  line "U+10000 comes before U+E000, though its UTF-8 bytes come after"
    ("{\"" ^ astral ^ "\":1,\"" ^ private_use ^ "\":2}")
    (printed (Json.Object [ (private_use, Json.Int 2); (astral, Json.Int 1) ]));
  Alcotest.(check bool)
    "UTF-8 byte order puts U+E000 first" true
    (String.compare private_use astral < 0)

let sorts_keys_of_a_nested_object () =
  line "the inner keys are sorted" {|[{"a":{"x":1,"y":2},"b":0}]|}
    (printed
       (Json.Array
          [
            Json.Object
              [
                ("b", Json.Int 0);
                ("a", Json.Object [ ("y", Json.Int 2); ("x", Json.Int 1) ]);
              ];
          ]))

let escapes_as_rfc_8785_requires () =
  line "the seven short escapes and the \\u00xx form"
    {|"\"\\\b\f\n\r\t\u0000\u001f"|}
    (printed (Json.String "\"\\\b\012\n\r\t\000\031"))

let keeps_delete_and_text_above_ascii () =
  let text = "\x7f \xc3\xa9 \xe2\x82\xac \xf0\x9f\x94\xa5" in
  line "the text stays as it is"
    ("\"" ^ text ^ "\"")
    (printed (Json.String text))

let accepts_the_corners_of_the_range () =
  line "2^53-1" "9007199254740991" (printed (Json.Int 9007199254740991));
  line "-(2^53-1)" "-9007199254740991" (printed (Json.Int (-9007199254740991)))

let refuses_an_integer_past_each_corner () =
  refused
    (Json.Out_of_range { path = []; value = 9007199254740992 })
    (Json.Int 9007199254740992);
  refused
    (Json.Out_of_range { path = []; value = -9007199254740992 })
    (Json.Int (-9007199254740992))

let refuses_a_repeated_key_with_its_path () =
  refused
    (Json.Repeated_key { path = [ Json.Key "o"; Json.Index 1 ]; key = "a" })
    (Json.Object
       [
         ( "o",
           Json.Array
             [
               Json.Null;
               Json.Object
                 [ ("a", Json.Int 1); ("b", Json.Null); ("a", Json.Int 2) ];
             ] );
       ])

let refuses_a_key_that_is_not_utf_8 () =
  refused
    (Json.Not_utf_8 { path = [ Json.Key "\xff" ]; text = "\xff" })
    (Json.Object [ ("\xff", Json.Null) ])

let refuses_a_string_that_is_not_utf_8 () =
  refused
    (Json.Not_utf_8 { path = [ Json.Index 0; Json.Key "s" ]; text = "a\xc3" })
    (Json.Array [ Json.Object [ ("s", Json.String "a\xc3") ] ])

let checks_the_keys_before_the_members () =
  refused
    (Json.Repeated_key { path = []; key = "k" })
    (Json.Object
       [ ("a", Json.String "\xff"); ("k", Json.Null); ("k", Json.Null) ])

let finds_a_repeated_key_among_keys_that_are_not_utf_8 () =
  refused
    (Json.Repeated_key { path = []; key = "a\xff" })
    (Json.Object
       [ ("a\xff", Json.Null); ("a\xfe", Json.Null); ("a\xff", Json.Null) ])

let reports_the_first_fault_in_order () =
  refused
    (Json.Out_of_range { path = [ Json.Index 0 ]; value = max_int })
    (Json.Array [ Json.Int max_int; Json.String "\xff" ])

let orders_two_astral_keys () =
  Alcotest.(check bool)
    "U+1F600 before U+1F601" true
    (Json.compare_keys "\xf0\x9f\x98\x80" "\xf0\x9f\x98\x81" < 0);
  Alcotest.(check bool)
    "U+1F200 before U+1F600" true
    (Json.compare_keys "\xf0\x9f\x88\x80" "\xf0\x9f\x98\x80" < 0)

let orders_a_prefix_first () =
  Alcotest.(check bool) "a before ab" true (Json.compare_keys "a" "ab" < 0);
  Alcotest.(check bool) "ab after a" true (Json.compare_keys "ab" "a" > 0);
  Alcotest.(check int) "empty equals empty" 0 (Json.compare_keys "" "")

module Gen = QCheck2.Gen

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let rec same (value : Json.t) (json : Yojson.Safe.t) =
  match (value, json) with
  | Json.Null, `Null -> true
  | Json.Bool a, `Bool b -> Bool.equal a b
  | Json.Int a, `Int b -> Int.equal a b
  | Json.String a, `String b -> String.equal a b
  | Json.Array items, `List parsed ->
      List.length items = List.length parsed && List.for_all2 same items parsed
  | Json.Object members, `Assoc pairs ->
      List.length members = List.length pairs
      && List.for_all
           (fun (key, value) ->
             match List.assoc_opt key pairs with
             | Some json -> same value json
             | None -> false)
           members
  | _ -> false

let rec keys_sorted (json : Yojson.Safe.t) =
  match json with
  | `Assoc pairs ->
      let keys = List.map fst pairs in
      List.equal String.equal keys (List.sort Json.compare_keys keys)
      && List.for_all (fun (_, json) -> keys_sorted json) pairs
  | `List items -> List.for_all keys_sorted items
  | _ -> true

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

let output_parses_back_to_the_same_value =
  property ~name:"the output parses back to the same value"
    ~print:Generators.print_json Generators.json (fun value ->
      match Json.to_string value with
      | Error _ -> false
      | Ok text -> same value (Yojson.Safe.from_string text))

let output_holds_its_keys_in_utf_16_order =
  property ~name:"every object of the output holds its keys in UTF-16 order"
    ~print:Generators.print_json Generators.json (fun value ->
      match Json.to_string value with
      | Error _ -> false
      | Ok text -> keys_sorted (Yojson.Safe.from_string text))

let output_holds_no_whitespace_and_no_control_byte =
  property ~name:"the output holds no byte at or below U+0020 outside a string"
    ~print:Generators.print_json Generators.json (fun value ->
      match Json.to_string value with
      | Error _ -> false
      | Ok text ->
          let rec scan offset ~inside ~escaped =
            offset >= String.length text
            ||
            let c = text.[offset] in
            let next = scan (offset + 1) in
            if Char.code c < 0x20 then false
            else if inside then
              if escaped then next ~inside:true ~escaped:false
              else next ~inside:(c <> '"') ~escaped:(c = '\\')
            else if c = ' ' then false
            else next ~inside:(c = '"') ~escaped:false
          in
          scan 0 ~inside:false ~escaped:false)

let output_ignores_the_order_of_members =
  property ~name:"the order of the members of an object does not matter"
    ~print:(fun (value, _) -> Generators.print_json value)
    (Gen.bind Generators.json (fun value ->
         let rec shuffle = function
           | Json.Object members ->
               Gen.bind (Gen.shuffle_list members) (fun members ->
                   Gen.map
                     (fun members -> Json.Object members)
                     (Gen.flatten_list
                        (List.map
                           (fun (key, value) ->
                             Gen.map (fun value -> (key, value)) (shuffle value))
                           members)))
           | Json.Array items ->
               Gen.map
                 (fun items -> Json.Array items)
                 (Gen.flatten_list (List.map shuffle items))
           | leaf -> Gen.return leaf
         in
         Gen.pair (Gen.return value) (shuffle value)))
    (fun (value, shuffled) -> Json.to_string value = Json.to_string shuffled)

let a_fault_gives_its_error_and_path =
  property ~name:"a value with one fault gives the error of that fault"
    ~print:Generators.print_json_with_a_fault Generators.json_with_a_fault
    (fun (value, error) -> Json.to_string value = Error error)

let names =
  Gen.oneof
    [ Generators.key; Generators.utf_8_string; Generators.not_utf_8_string ]

let compare_keys_agrees_with_utf_16_order =
  property ~name:"compare_keys agrees with UTF-16 code unit order"
    ~print:QCheck2.Print.(pair string string)
    (Gen.pair names names)
    (fun (a, b) ->
      sign (Json.compare_keys a b)
      = sign (String.compare (utf_16be a) (utf_16be b)))

let compare_keys_is_zero_only_for_equal_keys =
  property
    ~name:"compare_keys gives 0 for two UTF-8 keys only when they are equal"
    ~print:QCheck2.Print.(pair string string)
    (Gen.pair
       (Gen.oneof [ Generators.key; Generators.utf_8_string ])
       (Gen.oneof [ Generators.key; Generators.utf_8_string ]))
    (fun (a, b) -> Json.compare_keys a b = 0 = String.equal a b)

let tests =
  [
    Alcotest.test_case "writes every kind of value" `Quick
      writes_every_kind_of_value;
    Alcotest.test_case "writes a value that is not an object" `Quick
      writes_a_value_that_is_not_an_object;
    Alcotest.test_case "sorts keys by UTF-16 code units where UTF-8 disagrees"
      `Quick sorts_keys_by_utf16_code_units_where_utf8_disagrees;
    Alcotest.test_case "sorts the keys of a nested object" `Quick
      sorts_keys_of_a_nested_object;
    Alcotest.test_case "escapes as RFC 8785 requires" `Quick
      escapes_as_rfc_8785_requires;
    Alcotest.test_case "keeps DEL and text above ASCII" `Quick
      keeps_delete_and_text_above_ascii;
    Alcotest.test_case "accepts the corners of the range" `Quick
      accepts_the_corners_of_the_range;
    Alcotest.test_case "refuses an integer past each corner" `Quick
      refuses_an_integer_past_each_corner;
    Alcotest.test_case "refuses a repeated key with its path" `Quick
      refuses_a_repeated_key_with_its_path;
    Alcotest.test_case "refuses a key that is not UTF-8" `Quick
      refuses_a_key_that_is_not_utf_8;
    Alcotest.test_case "refuses a string that is not UTF-8" `Quick
      refuses_a_string_that_is_not_utf_8;
    Alcotest.test_case "checks the keys before the members" `Quick
      checks_the_keys_before_the_members;
    Alcotest.test_case "finds a repeated key among keys that are not UTF-8"
      `Quick finds_a_repeated_key_among_keys_that_are_not_utf_8;
    Alcotest.test_case "reports the first fault in order" `Quick
      reports_the_first_fault_in_order;
    Alcotest.test_case "orders two astral keys" `Quick orders_two_astral_keys;
    Alcotest.test_case "orders a prefix first" `Quick orders_a_prefix_first;
    output_parses_back_to_the_same_value;
    output_holds_its_keys_in_utf_16_order;
    output_holds_no_whitespace_and_no_control_byte;
    output_ignores_the_order_of_members;
    a_fault_gives_its_error_and_path;
    compare_keys_agrees_with_utf_16_order;
    compare_keys_is_zero_only_for_equal_keys;
  ]
