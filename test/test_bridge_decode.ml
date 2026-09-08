(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let same_capture (a : Sinter_bridge.capture) (b : Sinter_bridge.capture) =
  a.pattern = b.pattern && String.equal a.name b.name
  && String.equal a.node_type b.node_type
  && a.start_byte = b.start_byte
  && a.end_byte = b.end_byte && a.start_row = b.start_row
  && a.start_column = b.start_column
  && a.end_row = b.end_row
  && a.end_column = b.end_column
  && String.equal a.text b.text

let raises_error f =
  try
    ignore (f ());
    false
  with Sinter_bridge.Error _ -> true

(* Every input gives a value or an Error, so anything else that comes
   out of the decoder reaches QCheck as an error of the test. *)
let gives_a_value_or_an_error f =
  match f () with _ -> true | exception Sinter_bridge.Error _ -> true

let decode_captures_gives_back_what_was_encoded =
  property ~name:"decode_captures gives back the captures that were encoded"
    ~print:(fun (captures, buffer) ->
      Generators.print_captures captures ^ " " ^ Generators.print_buffer buffer)
    Generators.captures_buffer
    (fun (captures, buffer) ->
      let decoded = Sinter_bridge.decode_captures buffer in
      List.length decoded = List.length captures
      && List.for_all2 same_capture decoded captures)

let decode_tree_gives_back_what_was_encoded =
  property ~name:"decode_tree gives back the tree that was encoded"
    ~print:(fun (text, buffer) ->
      Printf.sprintf "%S %s" text (Generators.print_buffer buffer))
    Generators.tree_buffer
    (fun (text, buffer) -> String.equal (Sinter_bridge.decode_tree buffer) text)

let decode_captures_rejects_a_damaged_buffer =
  property ~name:"decode_captures raises Error on a damaged capture buffer"
    ~print:Generators.print_damaged Generators.damaged_captures_buffer
    (fun (_, buffer) ->
      raises_error (fun () -> Sinter_bridge.decode_captures buffer))

let decode_tree_rejects_a_damaged_buffer =
  property ~name:"decode_tree raises Error on a damaged parse tree buffer"
    ~print:Generators.print_damaged Generators.damaged_tree_buffer
    (fun (_, buffer) ->
      raises_error (fun () -> Sinter_bridge.decode_tree buffer))

let decode_captures_is_total =
  property ~count:2000
    ~name:"decode_captures gives captures or an Error for any bytes"
    ~print:Generators.print_buffer Generators.buffer_bytes (fun buffer ->
      gives_a_value_or_an_error (fun () -> Sinter_bridge.decode_captures buffer))

let decode_tree_is_total =
  property ~count:2000
    ~name:"decode_tree gives a tree or an Error for any bytes"
    ~print:Generators.print_buffer Generators.buffer_bytes (fun buffer ->
      gives_a_value_or_an_error (fun () -> Sinter_bridge.decode_tree buffer))

(* A capture buffer and a parse tree buffer carry different kinds, so
   neither decoder reads the other's buffer. *)
let neither_decoder_reads_the_other_kind =
  property ~name:"neither decoder reads a buffer of the other kind"
    ~print:(fun (captures, tree) ->
      Generators.print_buffer captures ^ " " ^ Generators.print_buffer tree)
    (QCheck2.Gen.pair
       (QCheck2.Gen.map snd Generators.captures_buffer)
       (QCheck2.Gen.map snd Generators.tree_buffer))
    (fun (captures, tree) ->
      raises_error (fun () -> Sinter_bridge.decode_captures tree)
      && raises_error (fun () -> Sinter_bridge.decode_tree captures))

(* The bytes of a counterexample, as the property printed them. *)
let of_hex text =
  String.init
    (String.length text / 2)
    (fun index ->
      Char.chr (int_of_string ("0x" ^ String.sub text (2 * index) 2)))

let error_message f =
  try
    ignore (f ());
    "no failure"
  with Sinter_bridge.Error message -> message

(* The counterexample of "decode_captures raises Error on a damaged
   capture buffer": one capture, every integer 0, an empty name, an
   empty node type, and a text of the one byte 0xFF. *)
let rejects_a_capture_whose_text_is_not_utf_8 () =
  let buffer =
    of_hex
      "5342523100000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000ff"
  in
  Alcotest.(check string)
    "the message names the text of a node"
    "the text of a node is not UTF-8 text"
    (error_message (fun () -> Sinter_bridge.decode_captures buffer))

(* The counterexample of "decode_tree raises Error on a damaged parse
   tree buffer": one record whose text is the one byte 0xFF. *)
let rejects_a_parse_tree_that_is_not_utf_8 () =
  let buffer = of_hex "5342523101000000010000000000000001000000ff" in
  Alcotest.(check string)
    "the message names the parse tree" "the parse tree is not UTF-8 text"
    (error_message (fun () -> Sinter_bridge.decode_tree buffer))

let tests =
  [
    Alcotest.test_case "rejects a capture whose text is not UTF-8" `Quick
      rejects_a_capture_whose_text_is_not_utf_8;
    Alcotest.test_case "rejects a parse tree that is not UTF-8" `Quick
      rejects_a_parse_tree_that_is_not_utf_8;
    decode_captures_gives_back_what_was_encoded;
    decode_tree_gives_back_what_was_encoded;
    decode_captures_rejects_a_damaged_buffer;
    decode_tree_rejects_a_damaged_buffer;
    decode_captures_is_total;
    decode_tree_is_total;
    neither_decoder_reads_the_other_kind;
  ]
