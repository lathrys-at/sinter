(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let commit = "0123456789abcdef0123456789abcdef01234567"

let line ~plan ~step ~hash =
  match Delivery_line.make ~plan ~step ~hash with
  | Some line -> line
  | None -> Alcotest.failf "no line of %s/%s %s" plan step hash

let shown = function
  | Some (line : Delivery_line.t) ->
      Printf.sprintf "%s | %s | %s" line.plan line.step line.hash
  | None -> "none"

let reads cases () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check string)
        (Printf.sprintf "%S" text) expected
        (shown (Delivery_line.of_string text)))
    cases

let reads_a_line_of_the_pattern =
  reads
    [
      ("Delivers: p/s 0a1b2c", "p | s | 0a1b2c");
      ( "Delivers: sinter-v0.1@097ce8/check-a-tree 05ef56",
        "sinter-v0.1@097ce8 | check-a-tree | 05ef56" );
      ("Delivers: p/s 0a1b2c  \t ", "p | s | 0a1b2c");
      ("Delivers: p/s 0a1b2c\r", "p | s | 0a1b2c");
      ( "Delivers: Auth_lock.out/Step.One 000000",
        "Auth_lock.out | Step.One | 000000" );
    ]

let refuses_every_other_form =
  reads
    [
      ("", "none");
      ("Delivers:", "none");
      ("Delivers: ", "none");
      ("Delivers:p/s 0a1b2c", "none");
      ("Delivers:  p/s 0a1b2c", "none");
      (" Delivers: p/s 0a1b2c", "none");
      ("delivers: p/s 0a1b2c", "none");
      ("Delivers: p/s  0a1b2c", "none");
      ("Delivers: p/s\t0a1b2c", "none");
      ("Delivers: p/s 0a1b2c extra", "none");
      ("Delivers: p/s", "none");
      ("Delivers: ps 0a1b2c", "none");
      ("Delivers: p/s 0A1B2C", "none");
      ("Delivers: p/s 0a1b2", "none");
      ("Delivers: p/s 0a1b2c3", "none");
      ("Delivers: /s 0a1b2c", "none");
      ("Delivers: p/ 0a1b2c", "none");
      ("Delivers: p@0a1b2/s 0a1b2c", "none");
      ("Delivers: p@/s 0a1b2c", "none");
      ("Delivers: p/s/t 0a1b2c", "none");
      ("Delivers: p/-s 0a1b2c", "none");
      ("Delivers: p/s 0a1b2c\r\n", "none");
      ("Delivers: p/s 0a\x001b2c", "none");
      ("Delivers: p\xff/s 0a1b2c", "none");
    ]

let make_refuses_parts_that_fail_their_patterns () =
  List.iter
    (fun (plan, step, hash) ->
      Alcotest.(check bool)
        (Printf.sprintf "%S %S %S" plan step hash)
        true
        (Option.is_none (Delivery_line.make ~plan ~step ~hash)))
    [
      ("", "s", "0a1b2c");
      ("p@0A1B2C", "s", "0a1b2c");
      ("p", "", "0a1b2c");
      ("p", "s t", "0a1b2c");
      ("p", "s", "0a1b2");
      ("p", "s", "0a1b2g");
    ]

let to_string_writes_the_pattern () =
  Alcotest.(check string)
    "the text" "Delivers: p@0a1b2c/do-it 3e1f0a"
    (Delivery_line.to_string
       (line ~plan:"p@0a1b2c" ~step:"do-it" ~hash:"3e1f0a"));
  Alcotest.(check string) "the prefix" "Delivers: " Delivery_line.prefix

let found_text (found : Delivery_line.found) =
  Printf.sprintf "%s:%d %S %s" found.commit found.number found.text
    (shown found.line)

let read_gives_each_line_that_starts_with_the_prefix () =
  let message =
    "Delivers: p/s 0a1b2c\n\n\
     The body.\n\
     Delivers: p/t 000000\r\n\
    \  Delivers: p/u 000000\n\
     Delivers:p/v 000000\n\
     Delivers:  p/w 000000  \n\n\
     Step: p/s\n\
     Delivers: p/s 0a1b2c"
  in
  Alcotest.(check (list string))
    "the lines"
    [
      commit ^ ":1 \"Delivers: p/s 0a1b2c\" p | s | 0a1b2c";
      commit ^ ":4 \"Delivers: p/t 000000\" p | t | 000000";
      commit ^ ":7 \"Delivers:  p/w 000000\" none";
      commit ^ ":10 \"Delivers: p/s 0a1b2c\" p | s | 0a1b2c";
    ]
    (List.map found_text (Delivery_line.read ~commit message))

let read_of_a_message_with_no_line_is_empty () =
  Alcotest.(check int)
    "no line" 0
    (List.length (Delivery_line.read ~commit "Fix it\n\nStep: p/s\n"));
  Alcotest.(check int)
    "the empty message" 0
    (List.length (Delivery_line.read ~commit ""))

let letter_or_digit =
  Gen.oneof_list (String.to_seq "abcdefxyz0129ABZ" |> List.of_seq)

let run = Gen.(string_size ~gen:letter_or_digit (int_range 1 4))

let slug =
  Gen.(
    map
      (fun (first, rest) ->
        String.concat "" (first :: List.map (fun (sep, run) -> sep ^ run) rest))
      (pair run
         (list_size (int_range 0 3) (pair (oneof_list [ "-"; "_"; "." ]) run))))

let hex = Gen.oneof_list (String.to_seq "0123456789abcdef" |> List.of_seq)
let hash = Gen.(string_size ~gen:hex (return 6))

let full_form =
  Gen.(oneof [ slug; map2 (fun slug id -> slug ^ "@" ^ id) slug hash ])

let parts = Gen.triple full_form slug hash

let blanks =
  Gen.(
    map (String.concat "")
      (list_size (int_range 0 3) (oneof_list [ " "; "\t"; "\r" ])))

let print_parts (plan, step, hash) = Printf.sprintf "%S %S %S" plan step hash

let a_line_reads_back_from_its_text =
  property
    ~name:"a delivery line reads back from its text, with any blanks at its end"
    ~print:QCheck2.Print.(pair print_parts string)
    (Gen.pair parts blanks)
    (fun ((plan, step, hash), blanks) ->
      match Delivery_line.make ~plan ~step ~hash with
      | None -> false
      | Some line ->
          Delivery_line.of_string (Delivery_line.to_string line ^ blanks)
          = Some line)

let paragraph =
  Gen.(
    map (String.concat "\n")
      (list_size (int_range 1 3)
         (oneof_list
            [
              "Fix the reader.";
              "Step: p/s";
              "* Write it";
              "Delivers";
              "  Delivers: p/s 000000";
              "";
            ])))

let a_line_in_any_paragraph_is_read =
  property ~name:"a delivery line in any paragraph of a message is read"
    ~print:QCheck2.Print.(triple (list string) int print_parts)
    Gen.(triple (list_size (int_range 1 5) paragraph) (int_range 0 5) parts)
    (fun (paragraphs, at, (plan, step, hash)) ->
      let at = at mod (List.length paragraphs + 1) in
      let text = Delivery_line.to_string (line ~plan ~step ~hash) in
      let before = List.filteri (fun index _ -> index < at) paragraphs
      and after = List.filteri (fun index _ -> index >= at) paragraphs in
      let message = String.concat "\n\n" (before @ [ text ] @ after) ^ "\n" in
      let number =
        1
        + List.length
            (String.split_on_char '\n'
               (String.concat "\n\n" before ^ if before = [] then "" else "\n\n"))
        - 1
      in
      match Delivery_line.read ~commit message with
      | [ found ] ->
          found.number = number
          && String.equal found.text text
          && found.line = Delivery_line.make ~plan ~step ~hash
      | _ -> false)

let any_bytes =
  Gen.(string_size ~gen:(map Char.chr (int_range 0 255)) (int_range 0 60))

let read_takes_any_bytes =
  property
    ~name:"read gives each line that starts with the prefix, for any bytes"
    ~print:QCheck2.Print.string
    Gen.(map2 (fun a b -> a ^ "\nDelivers: " ^ b) any_bytes any_bytes)
    (fun message ->
      let found = Delivery_line.read ~commit message in
      List.length found
      = List.length
          (List.filter
             (String.starts_with ~prefix:Delivery_line.prefix)
             (String.split_on_char '\n' message))
      && List.for_all
           (fun (found : Delivery_line.found) ->
             String.starts_with ~prefix:"Delivers:" found.text
             && found.line = Delivery_line.of_string found.text)
           found)

let case name f = Alcotest.test_case name `Quick f

let tests =
  [
    case "reads a line of the pattern" reads_a_line_of_the_pattern;
    case "refuses every other form" refuses_every_other_form;
    case "make refuses parts that fail their patterns"
      make_refuses_parts_that_fail_their_patterns;
    case "to_string writes the pattern" to_string_writes_the_pattern;
    case "read gives each line that starts with the prefix"
      read_gives_each_line_that_starts_with_the_prefix;
    case "read of a message with no line is empty"
      read_of_a_message_with_no_line_is_empty;
    a_line_reads_back_from_its_text;
    a_line_in_any_paragraph_is_read;
    read_takes_any_bytes;
  ]
