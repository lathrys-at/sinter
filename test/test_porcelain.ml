(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let case name f = Alcotest.test_case name `Quick f

let property ?(count = 500) name gen print f =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print gen f)

let field text =
  let buffer = Buffer.create 16 in
  Porcelain.add_field buffer text;
  Buffer.contents buffer

let line ~nul ~tier finding =
  let buffer = Buffer.create 64 in
  Porcelain.add_finding buffer ~nul ~tier finding;
  Buffer.contents buffer

let header ~nul name value =
  let buffer = Buffer.create 16 in
  Porcelain.add_header buffer ~nul name value;
  Buffer.contents buffer

let simple_escape = function
  | '"' -> Some '"'
  | '\\' -> Some '\\'
  | 'a' -> Some '\x07'
  | 'b' -> Some '\b'
  | 't' -> Some '\t'
  | 'n' -> Some '\n'
  | 'v' -> Some '\x0b'
  | 'f' -> Some '\x0c'
  | 'r' -> Some '\r'
  | _ -> None

let is_octal byte = byte >= '0' && byte <= '7'

let unquote item =
  let length = String.length item in
  if length = 0 || item.[0] <> '"' then Ok item
  else if length < 2 || item.[length - 1] <> '"' then Error "no closing quote"
  else
    let buffer = Buffer.create length in
    let stop = length - 1 in
    let rec walk index =
      if index = stop then Ok (Buffer.contents buffer)
      else
        match item.[index] with
        | '"' -> Error "a quote inside the quotes"
        | '\\' when index + 1 < stop -> (
            match simple_escape item.[index + 1] with
            | Some byte ->
                Buffer.add_char buffer byte;
                walk (index + 2)
            | None ->
                if
                  index + 3 < stop
                  && is_octal item.[index + 1]
                  && is_octal item.[index + 2]
                  && is_octal item.[index + 3]
                then (
                  Buffer.add_char buffer
                    (Char.chr
                       (((Char.code item.[index + 1] - 48) * 64)
                       + ((Char.code item.[index + 2] - 48) * 8)
                       + (Char.code item.[index + 3] - 48)));
                  walk (index + 4))
                else Error "an unknown escape")
        | '\\' -> Error "a backslash at the end"
        | byte ->
            Buffer.add_char buffer byte;
            walk (index + 1)
    in
    walk 1

let special byte = byte < ' ' || byte = '\x7f' || byte = '"' || byte = '\\'

let values ((finding : Finding.t), tier) =
  [
    Option.fold ~none:"none" ~some:Finding_class.tier_name tier;
    Finding_class.name finding.finding_class;
  ]
  @ (match finding.place with
    | None -> [ ""; ""; ""; ""; "" ]
    | Some { path; span } ->
        [
          path;
          Int.to_string span.start.line;
          Int.to_string span.start.column;
          Int.to_string span.stop.line;
          Int.to_string span.stop.column;
        ])
  @ [
      Finding.subject_id finding.subject;
      Option.value finding.detail ~default:"";
    ]

let octal code = Printf.sprintf "\\%03o" code

let each_byte_takes_its_escape () =
  for code = 0 to 255 do
    let byte = Char.chr code in
    let expected =
      match byte with
      | '"' -> "\"\\\"\""
      | '\\' -> "\"\\\\\""
      | '\x07' -> "\"\\a\""
      | '\b' -> "\"\\b\""
      | '\t' -> "\"\\t\""
      | '\n' -> "\"\\n\""
      | '\x0b' -> "\"\\v\""
      | '\x0c' -> "\"\\f\""
      | '\r' -> "\"\\r\""
      | byte when byte < ' ' || byte = '\x7f' -> "\"" ^ octal code ^ "\""
      | byte -> String.make 1 byte
    in
    Alcotest.(check string)
      (Printf.sprintf "the byte 0x%02x" code)
      expected
      (field (String.make 1 byte))
  done

let a_field_is_quoted_only_where_it_needs_quotes () =
  Alcotest.(check (list string))
    "a space, UTF-8, a hash, an empty field, and quotes in the middle"
    [
      "docs/a space.md";
      "caf\xc3\xa9 \xe2\x80\xae";
      "# x";
      "";
      "\"a\\tb\\\\c\\\"d\\000e\\177\"";
      "\"\\033[1m\"";
    ]
    (List.map field
       [
         "docs/a space.md";
         "caf\xc3\xa9 \xe2\x80\xae";
         "# x";
         "";
         "a\tb\\c\"d\000e\x7f";
         "\x1b[1m";
       ])

let quoting_round_trips =
  property "undoing the quotes of a field gives the field back"
    Gen.(
      oneof
        [
          Generators.porcelain_field;
          map (( ^ ) "\"") Generators.porcelain_field;
        ])
    QCheck2.Print.string
    (fun text ->
      let written = field text in
      unquote written = Ok text
      && (not (String.contains written '\t'))
      && (not (String.contains written '\n'))
      && String.exists special text = String.starts_with ~prefix:"\"" written
      && (String.exists special text || String.equal written text))

let a_finding_with_no_place_and_no_detail_has_empty_fields () =
  let finding = Finding.make Finding_class.Cycle (Finding.File "a\tb") () in
  Alcotest.(check (list string))
    "the line, and the line with -z"
    [
      "none\tcycle\t\t\t\t\t\t\"file:a\\tb\"\t\n";
      "block\tcycle\t\t\t\t\t\t\"file:a\\tb\"\t\n";
      "warn\000cycle\000\000\000\000\000\000file:a\tb\000\000";
    ]
    [
      line ~nul:false ~tier:None finding;
      line ~nul:false ~tier:(Some Finding_class.Block) finding;
      line ~nul:true ~tier:(Some Finding_class.Warn) finding;
    ]

let a_finding_with_a_place_and_a_detail_fills_each_field () =
  let finding =
    Finding.make Finding_class.Dangling
      (Finding.Fact { id = "cites:site:a.md#a->x"; ack_name = "x" })
      ~place:
        {
          Finding.path = "\"a\".md";
          span =
            {
              Markdown.start = { line = 10; column = 2 };
              stop = { line = 102; column = 30 };
            };
        }
      ~detail:"no \"x\"\n" ()
  in
  Alcotest.(check (list string))
    "the line, and the line with -z"
    [
      "warn\tdangling\t\"\\\"a\\\".md\"\t10\t2\t102\t30\tcites:site:a.md#a->x\t\"no \
       \\\"x\\\"\\\\n\"\n";
      "none\000dangling\000\"\\\"a\\\".md\"\00010\0002\000102\00030\000cites:site:a.md#a->x\000no \
       \"x\"\\n\000";
    ]
    [
      line ~nul:false ~tier:(Some Finding_class.Warn) finding;
      line ~nul:true ~tier:None finding;
    ]

let split_line ~separator ~terminator text =
  let length = String.length text in
  if length = 0 || text.[length - 1] <> terminator then None
  else
    let body = String.sub text 0 (length - 1) in
    Some (String.split_on_char separator body)

let a_line_round_trips =
  property "splitting a line at tabs and undoing the quotes gives the fields"
    Generators.porcelain_finding Generators.print_porcelain_finding
    (fun ((finding, tier) as value) ->
      let text = line ~nul:false ~tier finding in
      String.index_opt text '\n' = Some (String.length text - 1)
      &&
      match split_line ~separator:'\t' ~terminator:'\n' text with
      | Some items ->
          List.length items = 9
          && List.map unquote items = List.map Result.ok (values value)
      | None -> false)

let a_line_with_nul_round_trips =
  property
    "splitting a line with -z at NUL bytes and undoing the quotes gives the \
     fields"
    Generators.porcelain_finding Generators.print_porcelain_finding
    (fun ((finding, tier) as value) ->
      let text = line ~nul:true ~tier finding in
      match split_line ~separator:'\000' ~terminator:'\000' text with
      | Some items ->
          let expected = values value in
          List.length items = 9
          && List.map unquote items = List.map Result.ok expected
          && List.for_all2
               (fun item value ->
                 String.equal item value
                 = not
                     (String.contains value '\000'
                     || String.starts_with ~prefix:"\"" value))
               items expected
      | None -> false)

let a_field_that_starts_with_a_quote_is_quoted_with_nul () =
  let subject id =
    line ~nul:true ~tier:None
      (Finding.make Finding_class.Parse_error
         (Finding.Fact { id; ack_name = "x" })
         ())
  in
  Alcotest.(check (list string))
    "a field that starts with a quote and holds an escape, one that holds a \
     NUL, and one with a quote inside"
    [
      "none\000parse-error\000\000\000\000\000\000\"\\\"a\\\\000b\\\"\"\000\000";
      "none\000parse-error\000\000\000\000\000\000\"a\\000b\"\000\000";
      "none\000parse-error\000\000\000\000\000\000a\"b\\\000\000";
    ]
    [ subject "\"a\\000b\""; subject "a\000b"; subject "a\"b\\" ]

let a_header_is_a_hash_a_name_and_a_value () =
  Alcotest.(check (list string))
    "with a line feed, and with NUL"
    [ "# base 0abc\n"; "# tool v0.1.0-dev+abc\000" ]
    [
      header ~nul:false "base" "0abc"; header ~nul:true "tool" "v0.1.0-dev+abc";
    ]

let a_header_refuses_what_needs_quotes () =
  List.iter
    (fun (name, value) ->
      Alcotest.check_raises (Printf.sprintf "%S %S" name value)
        (Invalid_argument
           "Porcelain.add_header: a name or a value that needs quotes")
        (fun () -> ignore (header ~nul:false name value)))
    [
      ("", "x");
      ("x", "");
      ("a b", "x");
      ("x", "a b");
      ("x", "a\tb");
      ("x", "a\nb");
      ("a\"", "x");
      ("x", "a\\");
      ("x", "\x7f");
      ("x", "\000");
      ("\x1f", "x");
    ]

let each_header_has_one_name () =
  Alcotest.(check (list string))
    "the names in order"
    [ "base"; "ledger"; "gate"; "mode"; "tool" ]
    (List.map Porcelain.header_name Porcelain.headers);
  List.iter
    (fun header ->
      Alcotest.(check bool)
        (Porcelain.header_name header)
        true
        (Porcelain.header_of_name (Porcelain.header_name header) = Some header))
    Porcelain.headers;
  Alcotest.(check bool)
    "no other name" true
    (List.for_all
       (fun name -> Porcelain.header_of_name name = None)
       [ ""; "Base"; "all"; "porcelain"; "base "; "tools" ])

let the_version_is_1 () = Alcotest.(check int) "the version" 1 Porcelain.version

let tests =
  [
    case "each byte takes its escape" each_byte_takes_its_escape;
    case "a field is quoted only where it needs quotes"
      a_field_is_quoted_only_where_it_needs_quotes;
    quoting_round_trips;
    case "a finding with no place and no detail has empty fields"
      a_finding_with_no_place_and_no_detail_has_empty_fields;
    case "a finding with a place and a detail fills each field"
      a_finding_with_a_place_and_a_detail_fills_each_field;
    a_line_round_trips;
    a_line_with_nul_round_trips;
    case "a field that starts with a quote is quoted with -z"
      a_field_that_starts_with_a_quote_is_quoted_with_nul;
    case "a header is a hash, a name, and a value"
      a_header_is_a_hash_a_name_and_a_value;
    case "a header refuses what needs quotes" a_header_refuses_what_needs_quotes;
    case "each header has one name" each_header_has_one_name;
    case "the version is 1" the_version_is_1;
  ]
