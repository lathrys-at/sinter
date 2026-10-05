(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let property ?(count = 200) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let check_hex ~name data expected () =
  Alcotest.(check string) name expected (Sha256.hex data)

(* The test values that NIST publishes for SHA-256. *)
let nist =
  [
    ( "the empty string",
      "",
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" );
    ( "abc",
      "abc",
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" );
    ( "the 448-bit message",
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" );
    ( "the 896-bit message",
      "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
      "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1" );
    ( "one million a",
      String.make 1_000_000 'a',
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0" );
  ]

(* The values below come from "shasum -a 256". *)
let with_nul_bytes =
  [
    ( "one NUL byte",
      "\000",
      "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d" );
    ( "a NUL byte between two letters",
      "a\000b",
      "59b271ae1bbcb1d31d41929817f4b16fb439eb4f31520b5ad1d5ce98920a7138" );
    ( "three NUL bytes",
      "\000\000\000",
      "709e80c88487a2411e1ee4dfb9f22a861492d20c4765150c0c794abd70f8147c" );
  ]

(* More than 16 MiB, and a length that is not a multiple of the 64-byte
   block of SHA-256. *)
let large =
  String.init ((1 lsl 24) + 3) (fun index -> Char.chr (index land 0xFF))

let hashes_a_string_of_more_than_16_mib () =
  Alcotest.(check string)
    "the digest of 2^24 + 3 bytes"
    "18a38005f8d075ef78597b4e16417c65ec9a823be88f9a7af1a69ea8bda9bb8e"
    (Sha256.hex large)

let digest_of_abc_is_the_32_bytes_of_its_hex_form () =
  Alcotest.(check string)
    "the raw digest of abc"
    "\xba\x78\x16\xbf\x8f\x01\xcf\xea\x41\x41\x40\xde\x5d\xae\x22\x23\xb0\x03\x61\xa3\x96\x17\x7a\x9c\xb4\x10\xff\x61\xf2\x00\x15\xad"
    (Sha256.digest "abc")

let any_bytes = QCheck2.Gen.(string_size (int_range 0 200))

let is_lowercase_hex_digit = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let hex_has_64_lowercase_hex_digits =
  property ~name:"hex gives 64 lowercase hexadecimal digits"
    ~print:QCheck2.Print.string any_bytes (fun data ->
      let hex = Sha256.hex data in
      String.length hex = 64 && String.for_all is_lowercase_hex_digit hex)

let digest_has_32_bytes =
  property ~name:"digest gives 32 bytes" ~print:QCheck2.Print.string any_bytes
    (fun data -> String.length (Sha256.digest data) = 32)

let hex_writes_the_digest =
  property ~name:"hex writes each byte of digest as two digits"
    ~print:QCheck2.Print.string any_bytes (fun data ->
      let digest = Sha256.digest data in
      String.equal (Sha256.hex data)
        (String.concat ""
           (List.init 32 (fun index ->
                Printf.sprintf "%02x" (Char.code digest.[index])))))

(* The copy is a string of its own, so a digest that depends on
   anything but the bytes shows here. *)
let equal_inputs_give_equal_digests =
  property ~name:"equal inputs give equal digests" ~print:QCheck2.Print.string
    any_bytes (fun data ->
      let copy = Bytes.to_string (Bytes.of_string data) in
      String.equal (Sha256.digest data) (Sha256.digest copy))

let different_inputs_give_different_digests =
  property ~name:"different inputs give different digests"
    ~print:QCheck2.Print.(pair string string)
    QCheck2.Gen.(pair any_bytes any_bytes)
    (fun (a, b) ->
      String.equal a b || not (String.equal (Sha256.digest a) (Sha256.digest b)))

let tests =
  List.map
    (fun (name, data, expected) ->
      Alcotest.test_case
        ("gives the published value for " ^ name)
        `Quick
        (check_hex ~name data expected))
    nist
  @ List.map
      (fun (name, data, expected) ->
        Alcotest.test_case ("hashes " ^ name) `Quick
          (check_hex ~name data expected))
      with_nul_bytes
  @ [
      Alcotest.test_case "hashes a string of more than 16 MiB" `Quick
        hashes_a_string_of_more_than_16_mib;
      Alcotest.test_case "digest of abc is the 32 bytes of its hex form" `Quick
        digest_of_abc_is_the_32_bytes_of_its_hex_form;
      hex_has_64_lowercase_hex_digits;
      digest_has_32_bytes;
      hex_writes_the_digest;
      equal_inputs_give_equal_digests;
      different_inputs_give_different_digests;
    ]
