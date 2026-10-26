(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let raises_error f =
  try
    ignore (f ());
    false
  with Sinter_bridge.Error _ -> true

let gives_a_value_or_an_error f =
  match f () with _ -> true | exception Sinter_bridge.Error _ -> true

let decode_tree_gives_back_what_was_encoded =
  property ~name:"decode_tree gives back the tree that was encoded"
    ~print:(fun (text, buffer) ->
      Printf.sprintf "%S %s" text (Generators.print_buffer buffer))
    Generators.tree_buffer
    (fun (text, buffer) -> String.equal (Sinter_bridge.Decode.tree buffer) text)

let decode_digest_gives_back_what_was_encoded =
  property ~name:"decode_digest gives back the digest that was encoded"
    ~print:(fun (digest, buffer) ->
      Generators.print_buffer digest ^ " " ^ Generators.print_buffer buffer)
    Generators.digest_buffer
    (fun (digest, buffer) ->
      String.equal (Sinter_bridge.Decode.digest buffer) digest)

let decode_digest_rejects_a_damaged_buffer =
  property ~name:"decode_digest raises Error on a damaged digest buffer"
    ~print:Generators.print_damaged Generators.damaged_digest_buffer
    (fun (_, buffer) ->
      raises_error (fun () -> Sinter_bridge.Decode.digest buffer))

let decode_digest_is_total =
  property ~count:2000
    ~name:"decode_digest gives a digest or an Error for any bytes"
    ~print:Generators.print_buffer Generators.buffer_bytes (fun buffer ->
      gives_a_value_or_an_error (fun () -> Sinter_bridge.Decode.digest buffer))

let decode_digest_refuses_a_parse_tree_buffer =
  property ~name:"decode_digest raises Error on a parse tree buffer"
    ~print:Generators.print_buffer (QCheck2.Gen.map snd Generators.tree_buffer)
    (fun buffer -> raises_error (fun () -> Sinter_bridge.Decode.digest buffer))

let decode_tree_refuses_a_digest_buffer =
  property ~name:"decode_tree raises Error on a digest buffer"
    ~print:Generators.print_buffer
    (QCheck2.Gen.map snd Generators.digest_buffer) (fun buffer ->
      raises_error (fun () -> Sinter_bridge.Decode.tree buffer))

let decode_tree_rejects_a_damaged_buffer =
  property ~name:"decode_tree raises Error on a damaged parse tree buffer"
    ~print:Generators.print_damaged Generators.damaged_tree_buffer
    (fun (_, buffer) ->
      raises_error (fun () -> Sinter_bridge.Decode.tree buffer))

let decode_tree_is_total =
  property ~count:2000
    ~name:"decode_tree gives a tree or an Error for any bytes"
    ~print:Generators.print_buffer Generators.buffer_bytes (fun buffer ->
      gives_a_value_or_an_error (fun () -> Sinter_bridge.Decode.tree buffer))

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

let rejects_a_parse_tree_that_is_not_utf_8 () =
  let buffer = of_hex "5342523101000000010000000000000001000000ff" in
  Alcotest.(check string)
    "the message names the parse tree" "the parse tree is not UTF-8 text"
    (error_message (fun () -> Sinter_bridge.Decode.tree buffer))

let names_the_count_of_a_digest_buffer_with_two_records () =
  let one = Generators.encode_digest (String.make 32 '\001') in
  let buffer = Bytes.of_string (one ^ String.make 32 '\002') in
  Bytes.set_int32_le buffer 8 2l;
  Alcotest.(check string)
    "the message names two records"
    "the bridge returned a malformed buffer: a digest buffer holds 2 records, \
     and 1 was expected"
    (error_message (fun () ->
         Sinter_bridge.Decode.digest (Bytes.to_string buffer)))

let names_the_end_of_a_digest_that_is_one_byte_short () =
  let whole = Generators.encode_digest (String.make 32 '\001') in
  let buffer = String.sub whole 0 (String.length whole - 1) in
  Alcotest.(check string)
    "the message names byte 48 and a buffer of 47 bytes"
    "the bridge returned a malformed buffer: the records end at byte 48 and \
     the buffer holds 47 bytes"
    (error_message (fun () -> Sinter_bridge.Decode.digest buffer))

let rejects_a_buffer_one_byte_shorter_than_the_header () =
  let whole = Bridge_buffers.encode_captures [] in
  let buffer = String.sub whole 0 (String.length whole - 1) in
  Alcotest.(check int) "the buffer is fifteen bytes" 15 (String.length buffer);
  Alcotest.(check string)
    "the message says the buffer is shorter than the header"
    "the bridge returned a malformed buffer: the buffer is shorter than the \
     header"
    (error_message (fun () -> Sinter_bridge.Decode.captures buffer))

let names_the_length_of_a_buffer_with_bytes_after_its_records () =
  let buffer = Bridge_buffers.encode_captures [] ^ "\000" in
  Alcotest.(check string)
    "the message names byte 16 and a buffer of 17 bytes"
    "the bridge returned a malformed buffer: the records end at byte 16 and \
     the buffer holds 17 bytes"
    (error_message (fun () -> Sinter_bridge.Decode.captures buffer))

let tests =
  [
    Alcotest.test_case "rejects a parse tree that is not UTF-8" `Quick
      rejects_a_parse_tree_that_is_not_utf_8;
    Alcotest.test_case "rejects a buffer one byte shorter than the header"
      `Quick rejects_a_buffer_one_byte_shorter_than_the_header;
    Alcotest.test_case
      "names the length of a buffer with bytes after its records" `Quick
      names_the_length_of_a_buffer_with_bytes_after_its_records;
    Alcotest.test_case "names the count of a digest buffer with two records"
      `Quick names_the_count_of_a_digest_buffer_with_two_records;
    Alcotest.test_case "names the end of a digest that is one byte short" `Quick
      names_the_end_of_a_digest_that_is_one_byte_short;
    decode_tree_gives_back_what_was_encoded;
    decode_tree_rejects_a_damaged_buffer;
    decode_tree_is_total;
    decode_digest_gives_back_what_was_encoded;
    decode_digest_rejects_a_damaged_buffer;
    decode_digest_is_total;
    decode_digest_refuses_a_parse_tree_buffer;
    decode_tree_refuses_a_digest_buffer;
  ]
