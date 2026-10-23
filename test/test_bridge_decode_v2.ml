(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module B = Sinter_bridge
module Decode = Sinter_bridge.Decode

let property ?(count = 300) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let raises_error f = match f () with _ -> false | exception B.Error _ -> true

let gives_a_value_or_an_error f =
  match f () with _ -> true | exception B.Error _ -> true

let error_message f =
  match f () with _ -> "no failure" | exception B.Error message -> message

let malformed reason = "the bridge returned a malformed buffer: " ^ reason

(* The five family decoders of a failure, each as a function that
   gives back a failure of the test's own type. *)
let families =
  [
    ("language", fun b -> Bridge_buffers.Language (Decode.language_error b));
    ("tree", fun b -> Bridge_buffers.Tree (Decode.tree_error b));
    ("query", fun b -> Bridge_buffers.Query (Decode.query_error b));
    ("run", fun b -> Bridge_buffers.Run (Decode.run_error b));
    ("adapter", fun b -> Bridge_buffers.Adapter (Decode.adapter_error b));
  ]

let family_of = function
  | Bridge_buffers.Internal _ -> "internal"
  | Language _ -> "language"
  | Tree _ -> "tree"
  | Query _ -> "query"
  | Run _ -> "run"
  | Adapter _ -> "adapter"

let captures_come_back =
  property ~name:"Decode.captures gives back the captures that were encoded"
    ~print:Bridge_buffers.print_captures Bridge_buffers.captures
    (fun (captures, buffer) -> Decode.captures buffer = captures)

let a_report_comes_back =
  property ~name:"Decode.report gives back the report that was encoded"
    ~print:Bridge_buffers.print_report Bridge_buffers.report
    (fun (report, buffer) -> Decode.report buffer = report)

let a_response_comes_back =
  property ~name:"Decode.response gives back the bytes that were encoded"
    ~print:(fun (bytes, _) -> String.escaped bytes)
    Bridge_buffers.response
    (fun (bytes, buffer) -> String.equal (Decode.response buffer) bytes)

(* The decoder of the family of a failure gives it back, and the
   decoder of every other family raises Error. *)
let a_failure_comes_back_from_its_own_family =
  property ~name:"a failure comes back from the decoder of its family only"
    ~print:Bridge_buffers.print_failure Bridge_buffers.failure
    (fun (failure, buffer) ->
      List.for_all
        (fun (family, decode) ->
          if String.equal family (family_of failure) then
            decode buffer = failure
          else raises_error (fun () -> decode buffer))
        families)

let an_internal_fault_raises_its_message =
  property
    ~name:"an internal fault raises Error with its message in every family"
    ~print:(fun (message, _) -> String.escaped message)
    Bridge_buffers.internal
    (fun (message, buffer) ->
      List.for_all
        (fun (_, decode) ->
          String.equal (error_message (fun () -> decode buffer)) message)
        families)

let rejects property_name generator decode =
  property ~name:property_name ~print:Generators.print_damaged generator
    (fun (_, buffer) -> raises_error (fun () -> decode buffer))

let damaged_failure_is_refused_by_every_family =
  property ~name:"a damaged failure raises Error in every family"
    ~print:Generators.print_damaged Bridge_buffers.damaged_failure
    (fun (_, buffer) ->
      List.for_all
        (fun (_, decode) -> raises_error (fun () -> decode buffer))
        families)

let every_decoder_is_total =
  property ~count:1000
    ~name:"every decoder gives a value or an Error for any bytes"
    ~print:Generators.print_buffer Bridge_buffers.any_buffer (fun buffer ->
      gives_a_value_or_an_error (fun () -> Decode.captures buffer)
      && gives_a_value_or_an_error (fun () -> Decode.report buffer)
      && gives_a_value_or_an_error (fun () -> Decode.response buffer)
      && List.for_all
           (fun (_, decode) ->
             gives_a_value_or_an_error (fun () -> decode buffer))
           families)

(* A header of [kind] for one record, and then the 32-bit words of
   [words]. *)
let buffer ~kind words =
  let b = Buffer.create 64 in
  Buffer.add_string b "SBR1";
  List.iter
    (fun word -> Buffer.add_int32_le b (Int32.of_int word))
    (kind :: 1 :: 0 :: words);
  Buffer.contents b

let with_text words text =
  String.concat ""
    [
      String.concat ""
        (List.map
           (fun w ->
             let b = Bytes.create 4 in
             Bytes.set_int32_le b 0 (Int32.of_int w);
             Bytes.to_string b)
           words);
      (let b = Bytes.create 4 in
       Bytes.set_int32_le b 0 (Int32.of_int (String.length text));
       Bytes.to_string b);
      text;
    ]

let range_words = [ 0; 1; 0; 0; 0; 1 ]

let refuses_a_lowest_node_without_the_error_flag () =
  let b = buffer ~kind:7 [] ^ with_text ([ 0; 0; 1 ] @ range_words) "x" in
  Alcotest.(check string)
    "the message says the two disagree"
    (malformed "the lowest error node and the error flag of the root disagree")
    (error_message (fun () -> Decode.report b))

let refuses_an_error_flag_without_a_lowest_node () =
  let b = buffer ~kind:7 [ 1; 0; 0 ] in
  Alcotest.(check string)
    "the message says the two disagree"
    (malformed "the lowest error node and the error flag of the root disagree")
    (error_message (fun () -> Decode.report b))

let refuses_an_error_flag_of_two () =
  let b = buffer ~kind:7 [ 2; 0; 0 ] in
  Alcotest.(check string)
    "the message names the flag and its value"
    (malformed "the error flag of the root is 2, not 0 or 1")
    (error_message (fun () -> Decode.report b))

let refuses_an_error_node_of_form_two () =
  let b = buffer ~kind:7 [] ^ with_text ([ 0; 1; 2 ] @ range_words) "ERROR" in
  Alcotest.(check string)
    "the message names the form"
    (malformed "an error node has the form 2")
    (error_message (fun () -> Decode.report (b ^ with_text [] "")))

let names_a_node_type_that_is_not_utf_8 () =
  let b = buffer ~kind:7 [] ^ with_text ([ 1; 0; 1 ] @ range_words) "\xff" in
  Alcotest.(check string)
    "the message names the type of a node"
    "the type of a node is not UTF-8 text"
    (error_message (fun () -> Decode.report b))

let a_capture_text_need_not_be_utf_8 () =
  let capture =
    {
      B.Query.match_number = 0;
      pattern = 0;
      name = "s";
      node_type = "string";
      range =
        {
          start_byte = 0;
          end_byte = 1;
          start_row = 0;
          start_column = 0;
          end_row = 0;
          end_column = 1;
        };
      text = "\xff";
    }
  in
  Alcotest.(check bool)
    "the capture comes back" true
    (Decode.captures (Bridge_buffers.encode_captures [ capture ]) = [ capture ])

let failure words text = buffer ~kind:5 [] ^ with_text words text

let refuses_an_unknown_code () =
  Alcotest.(check string)
    "the message names the code"
    (malformed "a failure has the code 14")
    (error_message (fun () -> Decode.adapter_error (buffer ~kind:5 [ 14 ])))

let refuses_an_unknown_wasm_kind () =
  Alcotest.(check string)
    "the message names the kind"
    (malformed "a grammar error has the kind 4")
    (error_message (fun () -> Decode.language_error (failure [ 1; 4 ] "m")))

let refuses_an_unknown_query_kind () =
  Alcotest.(check string)
    "the message names the kind"
    (malformed "a query error has the kind 7")
    (error_message (fun () ->
         Decode.query_error (failure [ 5; 7; 0; 0; 0 ] "m")))

let refuses_an_unknown_input () =
  let b = buffer ~kind:5 [ 12; 2; 0; 0; 0; 0 ] in
  Alcotest.(check string)
    "the message names the input"
    (malformed "an allocation names the input 2")
    (error_message (fun () -> Decode.adapter_error b))

let refuses_an_unknown_cause () =
  Alcotest.(check string)
    "the message names the cause"
    (malformed "an adapter error has the cause 4")
    (error_message (fun () -> Decode.adapter_error (failure [ 8; 4; 1 ] "m")))

let refuses_an_import_error_with_no_import () =
  Alcotest.(check string)
    "the message says no import is named"
    (malformed "an adapter error names no import")
    (error_message (fun () -> Decode.adapter_error (buffer ~kind:5 [ 8; 1; 0 ])))

let refuses_a_missing_export_with_two_names () =
  let b = failure [ 8; 2; 2 ] "a" ^ with_text [] "b" in
  Alcotest.(check string)
    "the message names the cause and the count"
    (malformed "an adapter error of cause 2 holds 2 names")
    (error_message (fun () -> Decode.adapter_error b))

(* A size of 2^63 or more reads as a negative int64, and a size above
   max_int does not fit an int. *)
let refuses_a_size_that_does_not_fit_an_int () =
  let with_size size =
    let b = Bytes.of_string (buffer ~kind:5 [ 11; 0; 0 ]) in
    Bytes.set_int64_le b 20 size;
    Bytes.to_string b
  in
  let expected = malformed "a size does not fit an integer" in
  Alcotest.(check string)
    "2^63" expected
    (error_message (fun () -> Decode.adapter_error (with_size Int64.min_int)));
  Alcotest.(check string)
    "max_int + 1" expected
    (error_message (fun () ->
         Decode.adapter_error (with_size (Int64.succ (Int64.of_int max_int)))));
  Alcotest.(check bool)
    "max_int fits" true
    (Decode.adapter_error (with_size (Int64.of_int max_int))
    = B.Adapter.Memory_limit max_int)

let names_a_failure_of_another_family () =
  Alcotest.(check string)
    "the message says the failure does not belong"
    (malformed "the failure does not belong to the call")
    (error_message (fun () -> Decode.tree_error (buffer ~kind:5 [ 7 ])))

let names_the_count_of_a_report_buffer_with_two_records () =
  let b = Bytes.of_string (buffer ~kind:7 [ 0; 0; 0 ]) in
  Bytes.set_int32_le b 8 2l;
  Alcotest.(check string)
    "the message names two records"
    (malformed "an error report buffer holds 2 records, and 1 was expected")
    (error_message (fun () -> Decode.report (Bytes.to_string b)))

let tests =
  [
    Alcotest.test_case "refuses a lowest node without the error flag" `Quick
      refuses_a_lowest_node_without_the_error_flag;
    Alcotest.test_case "refuses an error flag without a lowest node" `Quick
      refuses_an_error_flag_without_a_lowest_node;
    Alcotest.test_case "refuses an error flag of two" `Quick
      refuses_an_error_flag_of_two;
    Alcotest.test_case "refuses an error node of form two" `Quick
      refuses_an_error_node_of_form_two;
    Alcotest.test_case "names a node type that is not UTF-8" `Quick
      names_a_node_type_that_is_not_utf_8;
    Alcotest.test_case "a capture text need not be UTF-8" `Quick
      a_capture_text_need_not_be_utf_8;
    Alcotest.test_case "refuses an unknown code" `Quick refuses_an_unknown_code;
    Alcotest.test_case "refuses an unknown wasm kind" `Quick
      refuses_an_unknown_wasm_kind;
    Alcotest.test_case "refuses an unknown query kind" `Quick
      refuses_an_unknown_query_kind;
    Alcotest.test_case "refuses an unknown input" `Quick
      refuses_an_unknown_input;
    Alcotest.test_case "refuses an unknown cause" `Quick
      refuses_an_unknown_cause;
    Alcotest.test_case "refuses an import error with no import" `Quick
      refuses_an_import_error_with_no_import;
    Alcotest.test_case "refuses a missing export with two names" `Quick
      refuses_a_missing_export_with_two_names;
    Alcotest.test_case "refuses a size that does not fit an int" `Quick
      refuses_a_size_that_does_not_fit_an_int;
    Alcotest.test_case "names a failure of another family" `Quick
      names_a_failure_of_another_family;
    Alcotest.test_case "names the count of a report buffer with two records"
      `Quick names_the_count_of_a_report_buffer_with_two_records;
    captures_come_back;
    a_report_comes_back;
    a_response_comes_back;
    a_failure_comes_back_from_its_own_family;
    an_internal_fault_raises_its_message;
    rejects "Decode.captures raises Error on a damaged buffer"
      Bridge_buffers.damaged_captures Decode.captures;
    rejects "Decode.report raises Error on a damaged buffer"
      Bridge_buffers.damaged_report Decode.report;
    rejects "Decode.response raises Error on a damaged buffer"
      Bridge_buffers.damaged_response Decode.response;
    damaged_failure_is_refused_by_every_family;
    every_decoder_is_total;
  ]
