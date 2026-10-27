(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core
module Gen = QCheck2.Gen

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let removes cases () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check string) text expected (Section_number.remove text))
    cases

let removes_a_section_number =
  removes
    [
      ("2.1 The file", "The file");
      ("3. Storage", "Storage");
      ("1.2.3 Deep", "Deep");
      ("1.2.3. Deep", "Deep");
      ("10.\tTab", "Tab");
      ("4.5 \t  Blanks", "Blanks");
      ("1. 2. Twice", "2. Twice");
      ("1.2. x", "x");
    ]

let keeps_a_text_without_one =
  removes
    [
      ("2026 targets", "2026 targets");
      ("v2.1 notes", "v2.1 notes");
      ("1..2 x", "1..2 x");
      ("1.2.x", "1.2.x");
      ("1.", "1.");
      ("2.1", "2.1");
      (".1 x", ".1 x");
      ("1 x", "1 x");
      ("1.2.3.4.x y", "1.2.3.4.x y");
      ("", "");
      ("1.a b", "1.a b");
    ]

let length_counts_the_number_and_its_blanks () =
  Alcotest.(check int) "2.1 and two spaces" 5 (Section_number.length "2.1  X");
  Alcotest.(check int) "no number" 0 (Section_number.length "X 2.1 Y");
  Alcotest.(check int) "all blanks" 4 (Section_number.length "3. \t")

let number =
  let open Gen in
  let digits = string_size ~gen:(char_range '0' '9') (int_range 1 3) in
  let* first = digits in
  let* more = list_size (int_bound 3) digits in
  let* final_dot = bool in
  let body =
    match more with
    | [] -> first ^ "."
    | _ -> first ^ "." ^ String.concat "." more ^ if final_dot then "." else ""
  in
  let* blanks = string_size ~gen:(oneof_list [ ' '; '\t' ]) (int_range 1 3) in
  pure (body ^ blanks)

let rest =
  Gen.(
    let* first = oneof_list [ 'A'; 'z'; '#'; '-'; '('; '\xc3' ] in
    let* tail = string_size ~gen:printable (int_bound 12) in
    pure (String.make 1 first ^ tail))

let a_number_and_its_blanks_go =
  property ~name:"a section number and the blanks after it leave the text"
    ~print:(fun (n, r) -> Printf.sprintf "%S %S" n r)
    (Gen.pair number rest)
    (fun (number, rest) ->
      Section_number.length (number ^ rest) = String.length number
      && String.equal (Section_number.remove (number ^ rest)) rest)

let a_text_that_starts_otherwise_stays =
  property ~name:"a text that does not start with a digit keeps every byte"
    ~print:(Printf.sprintf "%S")
    Gen.(
      let* text = string_size ~gen:printable (int_bound 20) in
      pure
        (if text <> "" && text.[0] >= '0' && text.[0] <= '9' then "x" ^ text
         else text))
    (fun text -> String.equal (Section_number.remove text) text)

let remove_is_a_suffix =
  property ~name:"remove gives a suffix of the text, and removes at most once"
    ~print:(Printf.sprintf "%S")
    Gen.(
      string_size
        ~gen:(oneof_list [ '1'; '2'; '.'; ' '; '\t'; 'a' ])
        (int_bound 12))
    (fun text ->
      let removed = Section_number.remove text in
      String.ends_with ~suffix:removed text
      && String.length removed = String.length text - Section_number.length text)

let tests =
  [
    Alcotest.test_case "removes a section number" `Quick
      removes_a_section_number;
    Alcotest.test_case "keeps a text without one" `Quick
      keeps_a_text_without_one;
    Alcotest.test_case "length counts the number and its blanks" `Quick
      length_counts_the_number_and_its_blanks;
    a_number_and_its_blanks_go;
    a_text_that_starts_otherwise_stays;
    remove_is_a_suffix;
  ]
