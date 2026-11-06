(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let step scope promises = { Commitment_set.scope; promises }

let lockout =
  [
    step [ "src/auth/**" ]
      [ ("req", "auth-lockout"); ("verifies", "auth-lockout") ];
    step [ "src/**" ] [ ("decision", "lockout-policy") ];
  ]

let lockout_bytes =
  {|{"promises":[{"scope":["src/**"],"target":"lockout-policy","word":"decision"},{"scope":["src/auth/**"],"target":"auth-lockout","word":"req"},{"scope":["src/auth/**"],"target":"auth-lockout","word":"verifies"}],"scope":["src/**"]}|}

let the_example_of_the_specification () =
  Alcotest.(check string)
    "the bytes" lockout_bytes
    (Commitment_set.bytes ~scope:[ "src/**" ] lockout);
  Alcotest.(check string)
    "the hash" (Sha256.hex lockout_bytes)
    (Commitment_set.hash ~scope:[ "src/**" ] lockout);
  Alcotest.(check int)
    "the size"
    (String.length lockout_bytes)
    (Commitment_set.size ~scope:[ "src/**" ] lockout)

let an_empty_set () =
  Alcotest.(check string)
    "the bytes" {|{"promises":[],"scope":[]}|}
    (Commitment_set.bytes ~scope:[] []);
  Alcotest.(check int) "the size" 26 (Commitment_set.size ~scope:[] []);
  Alcotest.(check int)
    "the size with a step without promises" 26
    (Commitment_set.size ~scope:[] [ step [ "a" ] [] ])

let equal_promises_stay_two () =
  Alcotest.(check string)
    "the bytes"
    {|{"promises":[{"scope":["a"],"target":"t","word":"req"},{"scope":["a"],"target":"t","word":"req"}],"scope":[]}|}
    (Commitment_set.bytes ~scope:[]
       [ step [ "a" ] [ ("req", "t") ]; step [ "a"; "a" ] [ ("req", "t") ] ])

let promises_sort_by_word_target_and_scope () =
  Alcotest.(check string)
    "the bytes"
    {|{"promises":[{"scope":["a"],"target":"t","word":"req"},{"scope":["b"],"target":"t","word":"req"},{"scope":["a"],"target":"u","word":"req"},{"scope":["a"],"target":"a","word":"verifies"}],"scope":["x","y"]}|}
    (Commitment_set.bytes ~scope:[ "y"; "x"; "y" ]
       [
         step [ "a" ] [ ("verifies", "a"); ("req", "u"); ("req", "t") ];
         step [ "b" ] [ ("req", "t") ];
       ])

let escapes_count_in_the_size () =
  let scope = [ "a\"b"; "c\\d"; "e\001f"; "\xc3\xa9" ] in
  let steps = [ step [ "\t" ] [ ("w\"", "t\n") ] ] in
  Alcotest.(check int)
    "the size"
    (String.length (Commitment_set.bytes ~scope steps))
    (Commitment_set.size ~scope steps)

let text_that_is_not_utf_8 () =
  let error =
    Invalid_argument
      "Sinter_core.Commitment_set.hash: a glob, a word, or a target is not \
       UTF-8"
  in
  Alcotest.check_raises "the hash" error (fun () ->
      ignore (Commitment_set.hash ~scope:[ "\xff" ] []));
  Alcotest.check_raises "the bytes" error (fun () ->
      ignore (Commitment_set.bytes ~scope:[] [ step [ "\xff" ] [] ]));
  Alcotest.check_raises "the size" error (fun () ->
      ignore (Commitment_set.size ~scope:[] [ step [] [ ("\xff", "t") ] ]))

let text =
  Gen.oneof
    [
      Gen.oneof_list [ "a"; "b"; "c"; "src/**"; "a\"b"; "\\" ];
      Generators.utf_8_string;
    ]

let steps =
  Gen.(
    pair
      (list_size (int_range 0 4) text)
      (list_size (int_range 0 4)
         (map2 step
            (list_size (int_range 0 3) text)
            (list_size (int_range 0 3) (pair text text)))))

let print (scope, steps) =
  Printf.sprintf "scope [%s], %d steps" (String.concat "; " scope)
    (List.length steps)

let property name check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count:300 ~name ~print steps check)

let order_changes_nothing =
  property "the order of the scope, the steps, and the globs changes nothing"
    (fun (scope, steps) ->
      String.equal
        (Commitment_set.hash ~scope steps)
        (Commitment_set.hash ~scope:(List.rev scope)
           (List.rev_map
              (fun (s : Commitment_set.step) ->
                step (List.rev s.scope) (List.rev s.promises))
              steps)))

let the_size_is_the_length_of_the_bytes =
  property "the size is the length of the bytes" (fun (scope, steps) ->
      Commitment_set.size ~scope steps
      = String.length (Commitment_set.bytes ~scope steps))

let the_hash_is_the_hash_of_the_bytes =
  property "the hash is the SHA-256 of the bytes" (fun (scope, steps) ->
      String.equal
        (Commitment_set.hash ~scope steps)
        (Sha256.hex (Commitment_set.bytes ~scope steps)))

let tests =
  [
    Alcotest.test_case "the example of the specification" `Quick
      the_example_of_the_specification;
    Alcotest.test_case "an empty set" `Quick an_empty_set;
    Alcotest.test_case "equal promises stay two" `Quick equal_promises_stay_two;
    Alcotest.test_case "promises sort by word, target, and scope" `Quick
      promises_sort_by_word_target_and_scope;
    Alcotest.test_case "escapes count in the size" `Quick
      escapes_count_in_the_size;
    Alcotest.test_case "a text that is not UTF-8" `Quick text_that_is_not_utf_8;
    order_changes_nothing;
    the_size_is_the_length_of_the_bytes;
    the_hash_is_the_hash_of_the_bytes;
  ]
