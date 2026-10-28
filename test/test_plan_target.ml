(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let id text =
  match Plan_target.id_of_string text with
  | Some id -> id
  | None -> Alcotest.failf "%s is no plan id" text

let shown = function
  | Ok target -> "ok " ^ Plan_target.to_string target
  | Error (Plan_target.Invalid_slug slug) -> "invalid slug " ^ slug
  | Error (Plan_target.Invalid_id text) -> "invalid id " ^ text

let parses cases () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check string) text expected (shown (Plan_target.parse text)))
    cases

let reads_a_slug_and_a_full_form =
  parses
    [
      ("upkeep", "ok upkeep");
      ("upkeep@3f2a9c", "ok upkeep@3f2a9c");
      ("Auth_lock.out@000000", "ok Auth_lock.out@000000");
      ("x@ffffff", "ok x@ffffff");
    ]

let refuses_every_other_form =
  parses
    [
      ("", "invalid slug ");
      ("-x", "invalid slug -x");
      ("a b@3f2a9c", "invalid slug a b");
      ("@3f2a9c", "invalid slug ");
      ("x@3F2A9C", "invalid id 3F2A9C");
      ("x@3f2a9", "invalid id 3f2a9");
      ("x@3f2a9c0", "invalid id 3f2a9c0");
      ("x@3f2a9c@012345", "invalid id 3f2a9c@012345");
      ("x@", "invalid id ");
      ("x@3f2a9g", "invalid id 3f2a9g");
      ("x/y@3f2a9c", "invalid slug x/y");
    ]

let keeps_the_parts () =
  match Plan_target.parse "upkeep@3f2a9c" with
  | Ok { slug; id = Some id } ->
      Alcotest.(check string) "the slug" "upkeep" slug;
      Alcotest.(check string) "the id" "3f2a9c" (id :> string)
  | Ok { id = None; _ } | Error _ -> Alcotest.fail "no full form"

let a_slug_has_no_id () =
  match Plan_target.parse "upkeep" with
  | Ok { slug; id = None } -> Alcotest.(check string) "the slug" "upkeep" slug
  | Ok { id = Some _; _ } | Error _ -> Alcotest.fail "not a bare slug"

let prints_the_full_form () =
  Alcotest.(check (list string))
    "the forms"
    [ "upkeep"; "upkeep@3f2a9c" ]
    [
      Plan_target.to_string { slug = "upkeep"; id = None };
      Plan_target.to_string { slug = "upkeep"; id = Some (id "3f2a9c") };
    ]

let slug =
  let run =
    Gen.string_size
      ~gen:(Gen.oneof_list [ 'a'; 'Z'; '0'; '9'; 'q' ])
      (Gen.int_range 1 3)
  in
  Gen.map2
    (fun first rest ->
      first ^ String.concat "" (List.map (fun (sep, r) -> sep ^ r) rest))
    run
    (Gen.list_size (Gen.int_range 0 2)
       (Gen.pair (Gen.oneof_list [ "-"; "_"; "." ]) run))

let hex6 = Gen.map (Printf.sprintf "%06x") (Gen.int_bound 0xffffff)

let target =
  Gen.pair slug (Gen.option hex6)
  |> Gen.map (fun (slug, digits) ->
      { Plan_target.slug; id = Option.map id digits })

let parse_of_the_printed_form_is_the_target =
  property ~name:"parse of the printed form is the target"
    ~print:Plan_target.to_string target (fun target ->
      Plan_target.parse (Plan_target.to_string target) = Ok target)

let text =
  Gen.string_size
    ~gen:(Gen.oneof_list [ 'a'; 'f'; 'g'; 'A'; 'F'; '0'; '9'; '@'; '-'; ' ' ])
    (Gen.int_range 0 12)

let an_accepted_text_is_a_slug_or_a_slug_and_an_id =
  property ~count:2000 ~name:"an accepted text is a slug or a full form"
    ~print:String.escaped text (fun text ->
      match Plan_target.parse text with
      | Error _ -> true
      | Ok target -> (
          String.equal (Plan_target.to_string target) text
          && Slug.is_valid target.slug
          &&
          match target.id with
          | None -> not (String.contains text '@')
          | Some id ->
              let digits = (id :> string) in
              String.length digits = 6
              && Printf.sprintf "%06x" (int_of_string ("0x" ^ digits)) = digits))

let suffix =
  Gen.string_size
    ~gen:(Gen.oneof_list [ 'a'; 'f'; 'g'; 'A'; 'F'; '0'; '9'; '@'; ' ' ])
    (Gen.int_range 0 8)
  |> Gen.map (fun text -> if String.length text = 6 then text ^ "@" else text)

let a_slug_and_any_other_suffix_is_refused =
  property ~count:2000 ~name:"a slug and a suffix that is no id is refused"
    ~print:(fun (slug, suffix) -> String.escaped (slug ^ "@" ^ suffix))
    (Gen.pair slug suffix)
    (fun (slug, suffix) ->
      Plan_target.parse (slug ^ "@" ^ suffix)
      = Error (Plan_target.Invalid_id suffix))

let a_six_digit_suffix_is_refused_unless_lowercase_hex =
  property ~count:2000 ~name:"a suffix of six characters is an id only in hex"
    ~print:String.escaped
    (Gen.string_size
       ~gen:(Gen.oneof_list [ 'a'; 'f'; 'g'; 'A'; 'F'; '0'; '9'; '@' ])
       (Gen.return 6))
    (fun digits ->
      let lowercase_hex =
        String.for_all
          (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
          digits
      in
      Option.is_some (Plan_target.id_of_string digits) = lowercase_hex
      && Result.is_ok (Plan_target.parse ("x@" ^ digits)) = lowercase_hex)

let every_number_of_24_bits_is_an_id =
  property ~name:"every number of 24 bits in six lowercase hex digits is an id"
    ~print:string_of_int (Gen.int_bound 0xffffff) (fun n ->
      Option.map
        (fun (id : Plan_target.id) -> (id :> string))
        (Plan_target.id_of_string (Printf.sprintf "%06x" n))
      = Some (Printf.sprintf "%06x" n))

let any_bytes_parse_to_a_target_that_prints_them_or_to_an_error =
  property ~count:2000 ~name:"any bytes parse to a target that prints them"
    ~print:String.escaped
    (Gen.string_size ~gen:Gen.char (Gen.int_range 0 16))
    (fun text ->
      match Plan_target.parse text with
      | Ok target -> String.equal (Plan_target.to_string target) text
      | Error (Plan_target.Invalid_slug slug) -> not (Slug.is_valid slug)
      | Error (Plan_target.Invalid_id id) -> Plan_target.id_of_string id = None)

let tests =
  [
    any_bytes_parse_to_a_target_that_prints_them_or_to_an_error;
    Alcotest.test_case "reads a slug and a full form" `Quick
      reads_a_slug_and_a_full_form;
    Alcotest.test_case "refuses every other form" `Quick
      refuses_every_other_form;
    Alcotest.test_case "keeps the parts" `Quick keeps_the_parts;
    Alcotest.test_case "a slug has no id" `Quick a_slug_has_no_id;
    Alcotest.test_case "prints the full form" `Quick prints_the_full_form;
    parse_of_the_printed_form_is_the_target;
    an_accepted_text_is_a_slug_or_a_slug_and_an_id;
    a_slug_and_any_other_suffix_is_refused;
    a_six_digit_suffix_is_refused_unless_lowercase_hex;
    every_number_of_24_bits_is_an_id;
  ]
