(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let check_valid expected cases () =
  List.iter
    (fun text -> Alcotest.(check bool) text expected (Slug.is_valid text))
    cases

let accepts_slugs =
  check_valid true
    [ "a"; "auth-lockout"; "Auth_Lockout"; "v1.2"; "a-b_c.d"; "0"; "x9" ]

let refuses_other_texts =
  check_valid false
    [
      "";
      "-a";
      "a-";
      "a--b";
      "a-_b";
      "a b";
      "a/b";
      "gh/42";
      "\xC3\xA9";
      "a.";
      "._";
    ]

let of_heading_gives cases () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check string) text expected (Slug.of_heading text))
    cases

let makes_the_slug_of_a_heading =
  of_heading_gives
    [
      ("Verify against the reqs", "verify-against-the-reqs");
      ("Scan **markdown**", "scan-markdown");
      ("  --Hello, World!--  ", "hello-world");
      ("Caf\xC3\xA9 au lait", "caf-au-lait");
      ("!!!", "");
      ("", "");
      ("A1_b2", "a1-b2");
    ]

let heading =
  Gen.map (String.concat "")
    (Gen.list_size (Gen.int_range 0 10)
       (Gen.oneof_list [ "A"; "b"; "7"; " "; "-"; "_"; "."; "*"; "\xC3\xA9" ]))

let slug_of_a_heading_is_empty_or_valid =
  property ~name:"the slug of a heading is empty, or lowercase and valid"
    ~print:String.escaped heading (fun text ->
      let slug = Slug.of_heading text in
      slug = ""
      || Slug.is_valid slug
         && String.equal slug (String.lowercase_ascii slug)
         && not (String.contains slug '_' || String.contains slug '.'))

let slug_of_a_heading_keeps_its_letters_and_digits =
  property ~name:"the slug of a heading keeps its letters and digits in order"
    ~print:String.escaped heading (fun text ->
      let keep text =
        String.concat ""
          (List.filter_map
             (fun byte ->
               match byte with
               | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' ->
                   Some (String.make 1 (Char.lowercase_ascii byte))
               | _ -> None)
             (List.of_seq (String.to_seq text)))
      in
      String.equal (keep text) (keep (Slug.of_heading text)))

let tests =
  [
    Alcotest.test_case "accepts slugs" `Quick accepts_slugs;
    Alcotest.test_case "refuses other texts" `Quick refuses_other_texts;
    Alcotest.test_case "makes the slug of a heading" `Quick
      makes_the_slug_of_a_heading;
    slug_of_a_heading_is_empty_or_valid;
    slug_of_a_heading_keeps_its_letters_and_digits;
  ]
