(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let line_of fields = Yojson.Safe.to_string (`Assoc fields)

(* One line for a parse request. Each argument replaces one field, and
   [?query] and [?tree] add a field that is otherwise absent. *)
let parse_line ?(id = `String "r1") ?(op = `String "parse")
    ?(grammar = `String "g.wasm") ?query ?tree ?(files = `List [ `String "a" ])
    () =
  let named name = function None -> [] | Some value -> [ (name, value) ] in
  line_of
    ([ ("id", id); ("op", op); ("grammar", grammar) ]
    @ named "query" query @ named "tree" tree
    @ [ ("files", files) ])

let cause_of line =
  match Request.of_line line with
  | Ok _ -> None
  | Error error -> Some error.cause

let tag_of line =
  match Request.of_line line with Ok _ -> None | Error error -> error.id

let holds name condition = Alcotest.(check bool) name true condition
let gives name expected line = holds name (cause_of line = Some expected)

(* Generators. *)

let json_of_id = function
  | Request.Text text -> `String text
  | Request.Number number -> `Int number

let fields_of (request : Request.t) ~spell_out =
  match request.op with
  | Request.Parse { grammar; output; files } ->
      [
        ("id", json_of_id request.id);
        ("op", `String "parse");
        ("grammar", `String grammar);
      ]
      @ (match output with
        | Request.Captures query ->
            ("query", `String query)
            :: (if spell_out then [ ("tree", `Bool false) ] else [])
        | Request.Tree -> [ ("tree", `Bool true) ])
      @ [ ("files", `List (List.map (fun file -> `String file) files)) ]

(* A well-formed request, and one line that says the same thing. The
   order of the fields in the line is generated too. *)
let request_and_line =
  let open Gen in
  let text = string_printable in
  let* id =
    oneof
      [
        map (fun text -> Request.Text text) text;
        map
          (fun number -> Request.Number number)
          (int_range (-9007199254740991) 9007199254740991);
      ]
  in
  let* grammar = text in
  let* output =
    oneof
      [ map (fun query -> Request.Captures query) text; return Request.Tree ]
  in
  let* files = list_size (int_range 1 4) text in
  let* spell_out = bool in
  let request = { Request.id; op = Request.Parse { grammar; output; files } } in
  let* fields = shuffle_list (fields_of request ~spell_out) in
  return (request, line_of fields)

(* A request line with one byte cut, changed, or added. *)
let corrupted_line =
  let open Gen in
  let* _, line = request_and_line in
  let length = String.length line in
  oneof
    [
      map (fun cut -> String.sub line 0 cut) (int_range 0 length);
      map2
        (fun at byte ->
          let bytes = Bytes.of_string line in
          if length > 0 then Bytes.set bytes (at mod length) byte;
          Bytes.to_string bytes)
        (int_range 0 length) char;
      map2
        (fun at byte ->
          String.sub line 0 at ^ String.make 1 byte
          ^ String.sub line at (length - at))
        (int_range 0 length) char;
    ]

(* Property tests. *)

let reads_any_string =
  QCheck2.Test.make ~count:2000 ~name:"the reader answers for any string"
    ~print:String.escaped Gen.string (fun line ->
      match Request.of_line line with Ok _ | Error _ -> true)

let reads_any_corrupted_request =
  QCheck2.Test.make ~count:2000
    ~name:"the reader answers for any corrupted request" ~print:String.escaped
    corrupted_line (fun line ->
      match Request.of_line line with Ok _ | Error _ -> true)

let reads_back_a_well_formed_request =
  QCheck2.Test.make ~count:500
    ~name:"a well-formed request reads back to itself"
    ~print:(fun (_, line) -> String.escaped line)
    request_and_line
    (fun (request, line) -> Request.of_line line = Ok request)

(* Tests of one fact each. *)

let a_line_that_is_not_json_is_not_a_request () =
  gives "an open brace alone" Request.Not_json "{"

let an_empty_line_is_not_a_request () =
  gives "the empty line" Request.Not_json ""

let a_line_of_spaces_is_not_a_request () =
  gives "three spaces" Request.Not_json "   "

let a_json_value_that_is_not_an_object_is_not_a_request () =
  gives "an array" Request.Not_an_object "[1,2]"

let a_request_without_an_id_is_an_error () =
  gives "no id" Request.No_id
    {|{"op":"parse","grammar":"g.wasm","tree":true,"files":["a"]}|}

let an_id_of_the_wrong_type_is_an_error () =
  gives "a boolean id" Request.Bad_id
    (parse_line ~id:(`Bool true) ~tree:(`Bool true) ())

let an_id_above_the_allowed_range_is_an_error () =
  gives "2^53" Request.Bad_id
    (parse_line ~id:(`Int 9007199254740992) ~tree:(`Bool true) ())

let an_id_that_is_not_utf_8_is_an_error () =
  gives "one byte that no code point starts" Request.Bad_id
    "{\"id\":\"\xff\",\"op\":\"parse\",\"grammar\":\"g\",\"tree\":true,\"files\":[\"a\"]}"

let an_error_without_a_readable_id_carries_no_tag () =
  holds "the error names no tag"
    (tag_of (parse_line ~id:(`Bool true) ~tree:(`Bool true) ()) = None)

let an_error_after_the_id_carries_the_tag () =
  holds "the error names the tag"
    (tag_of (parse_line ~id:(`String "r7") ~op:(`String "scan") ())
    = Some (Request.Text "r7"))

let an_id_given_twice_is_an_error () =
  gives "two id fields" (Request.Repeated_field "id")
    {|{"id":1,"id":2,"op":"parse","grammar":"g","tree":true,"files":["a"]}|}

let a_field_given_twice_is_an_error () =
  gives "two grammar fields" (Request.Repeated_field "grammar")
    {|{"id":1,"op":"parse","grammar":"g","grammar":"h","tree":true,"files":["a"]}|}

let a_request_without_an_op_is_an_error () =
  gives "no op" Request.No_op
    {|{"id":1,"grammar":"g","tree":true,"files":["a"]}|}

let an_op_of_the_wrong_type_is_an_error () =
  gives "a numeric op" Request.Bad_op
    (parse_line ~op:(`Int 1) ~tree:(`Bool true) ())

let an_op_that_does_not_exist_is_an_error () =
  gives "the op scan" (Request.Unknown_op "scan")
    (parse_line ~op:(`String "scan") ~tree:(`Bool true) ())

let a_field_that_does_not_belong_is_an_error () =
  gives "the field depth" (Request.Unknown_field "depth")
    {|{"id":1,"op":"parse","grammar":"g","tree":true,"files":["a"],"depth":2}|}

let a_request_without_a_grammar_is_an_error () =
  gives "no grammar" (Request.Missing_field "grammar")
    {|{"id":1,"op":"parse","tree":true,"files":["a"]}|}

let a_request_without_files_is_an_error () =
  gives "no files" (Request.Missing_field "files")
    {|{"id":1,"op":"parse","grammar":"g","tree":true}|}

let wrong_type_of field line =
  match cause_of line with
  | Some (Request.Wrong_type wrong) -> String.equal wrong.field field
  | _ -> false

let a_grammar_of_the_wrong_type_is_an_error () =
  holds "the error names the grammar field"
    (wrong_type_of "grammar"
       (parse_line ~grammar:(`Int 1) ~tree:(`Bool true) ()))

let a_tree_field_of_the_wrong_type_is_an_error () =
  holds "the error names the tree field"
    (wrong_type_of "tree" (parse_line ~tree:(`String "yes") ()))

let a_files_field_that_is_not_an_array_is_an_error () =
  holds "the error names the files field"
    (wrong_type_of "files"
       (parse_line ~tree:(`Bool true) ~files:(`String "a") ()))

let a_file_that_is_not_a_string_is_an_error () =
  holds "the error names the files field"
    (wrong_type_of "files"
       (parse_line ~tree:(`Bool true) ~files:(`List [ `Int 1 ]) ()))

let an_empty_list_of_files_is_an_error () =
  gives "no file at all" (Request.Empty_field "files")
    (parse_line ~tree:(`Bool true) ~files:(`List []) ())

let a_grammar_that_is_not_utf_8_is_an_error () =
  gives "one byte that no code point starts" (Request.Not_text "grammar")
    "{\"id\":1,\"op\":\"parse\",\"grammar\":\"\xff\",\"tree\":true,\"files\":[\"a\"]}"

let a_file_that_is_not_utf_8_is_an_error () =
  gives "one byte that no code point starts" (Request.Not_text "files")
    "{\"id\":1,\"op\":\"parse\",\"grammar\":\"g\",\"tree\":true,\"files\":[\"\xff\"]}"

let a_query_and_a_tree_together_are_an_error () =
  gives "both" Request.Both_query_and_tree
    (parse_line ~query:(`String "q.scm") ~tree:(`Bool true) ())

let neither_a_query_nor_a_tree_is_an_error () =
  gives "neither" Request.Neither_query_nor_tree (parse_line ())

let a_query_beside_a_false_tree_asks_for_captures () =
  holds "the request asks for captures"
    (Request.of_line
       (parse_line ~query:(`String "q.scm") ~tree:(`Bool false) ())
    = Ok
        {
          Request.id = Request.Text "r1";
          op =
            Request.Parse
              {
                grammar = "g.wasm";
                output = Request.Captures "q.scm";
                files = [ "a" ];
              };
        })

(* A line that holds many fields must not cost more than the fields
   are worth: the reader sorts the names and does not compare every
   pair of them. This line takes about a second with a search over
   pairs, and no time at all without one. *)
let a_line_of_many_fields_is_read_at_once () =
  let count = 50000 in
  let fields =
    [ ("id", `Int 1); ("op", `String "parse") ]
    @ List.init count (fun index -> (Printf.sprintf "f%d" index, `Int index))
  in
  gives "fifty thousand fields" (Request.Unknown_field "f0") (line_of fields)

let every_cause =
  [
    Request.Not_json;
    Request.Not_an_object;
    Request.No_id;
    Request.Bad_id;
    Request.No_op;
    Request.Bad_op;
    Request.Unknown_op "scan";
    Request.Unknown_field "depth";
    Request.Repeated_field "id";
    Request.Missing_field "grammar";
    Request.Wrong_type { field = "files"; wanted = "an array" };
    Request.Empty_field "files";
    Request.Not_text "grammar";
    Request.Both_query_and_tree;
    Request.Neither_query_nor_tree;
  ]

let every_cause_has_a_message_of_one_line () =
  List.iter
    (fun cause ->
      let message = Request.message cause in
      holds "the message is not empty" (String.length message > 0);
      holds "the message holds no line feed"
        (not (String.contains message '\n')))
    every_cause

let a_text_id_becomes_a_string_value () =
  Alcotest.(check string)
    "the value is a string" {|{"req":"r1"}|}
    (Jsonl.to_string [ ("req", Request.value_of_id (Request.Text "r1")) ])

let a_number_id_becomes_an_integer_value () =
  Alcotest.(check string)
    "the value is an integer" {|{"req":7}|}
    (Jsonl.to_string [ ("req", Request.value_of_id (Request.Number 7)) ])

let case name test = Alcotest.test_case name `Quick test

let tests =
  List.map
    (QCheck_alcotest.to_alcotest ~speed_level:`Quick)
    [
      reads_any_string;
      reads_any_corrupted_request;
      reads_back_a_well_formed_request;
    ]
  @ [
      case "a line that is not JSON is not a request"
        a_line_that_is_not_json_is_not_a_request;
      case "an empty line is not a request" an_empty_line_is_not_a_request;
      case "a line of spaces is not a request" a_line_of_spaces_is_not_a_request;
      case "a JSON value that is not an object is not a request"
        a_json_value_that_is_not_an_object_is_not_a_request;
      case "a request without an id is an error"
        a_request_without_an_id_is_an_error;
      case "an id of the wrong type is an error"
        an_id_of_the_wrong_type_is_an_error;
      case "an id above the allowed range is an error"
        an_id_above_the_allowed_range_is_an_error;
      case "an id that is not UTF-8 is an error"
        an_id_that_is_not_utf_8_is_an_error;
      case "an error without a readable id carries no tag"
        an_error_without_a_readable_id_carries_no_tag;
      case "an error after the id carries the tag"
        an_error_after_the_id_carries_the_tag;
      case "an id given twice is an error" an_id_given_twice_is_an_error;
      case "a field given twice is an error" a_field_given_twice_is_an_error;
      case "a request without an op is an error"
        a_request_without_an_op_is_an_error;
      case "an op of the wrong type is an error"
        an_op_of_the_wrong_type_is_an_error;
      case "an op that does not exist is an error"
        an_op_that_does_not_exist_is_an_error;
      case "a field that does not belong is an error"
        a_field_that_does_not_belong_is_an_error;
      case "a request without a grammar is an error"
        a_request_without_a_grammar_is_an_error;
      case "a request without files is an error"
        a_request_without_files_is_an_error;
      case "a grammar of the wrong type is an error"
        a_grammar_of_the_wrong_type_is_an_error;
      case "a tree field of the wrong type is an error"
        a_tree_field_of_the_wrong_type_is_an_error;
      case "a files field that is not an array is an error"
        a_files_field_that_is_not_an_array_is_an_error;
      case "a file that is not a string is an error"
        a_file_that_is_not_a_string_is_an_error;
      case "an empty list of files is an error"
        an_empty_list_of_files_is_an_error;
      case "a grammar that is not UTF-8 is an error"
        a_grammar_that_is_not_utf_8_is_an_error;
      case "a file that is not UTF-8 is an error"
        a_file_that_is_not_utf_8_is_an_error;
      case "a query and a tree together are an error"
        a_query_and_a_tree_together_are_an_error;
      case "neither a query nor a tree is an error"
        neither_a_query_nor_a_tree_is_an_error;
      case "a query beside a false tree asks for captures"
        a_query_beside_a_false_tree_asks_for_captures;
      case "a line of many fields is read at once"
        a_line_of_many_fields_is_read_at_once;
      case "every cause has a message of one line"
        every_cause_has_a_message_of_one_line;
      case "a text id becomes a string value" a_text_id_becomes_a_string_value;
      case "a number id becomes an integer value"
        a_number_id_becomes_an_integer_value;
    ]
