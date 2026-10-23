(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

(* Put [content] in a file of its own, and run [use] on the path of
   that file. The file is gone when [use] returns. *)
let in_a_file content use =
  let path = Filename.temp_file "sinter-text-file" ".txt" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      Out_channel.with_open_bin path (fun channel ->
          output_string channel content);
      use path)

let error =
  Alcotest.testable
    (fun formatter error ->
      Format.pp_print_string formatter (Text_file.message "p" error))
    ( = )

let content = Alcotest.(result string error)

let read_gives_the_bytes_of_a_file =
  property ~count:50 ~name:"read gives the bytes of a file"
    ~print:String.escaped
    QCheck2.Gen.(string_size ~gen:char (int_bound 64))
    (fun bytes -> in_a_file bytes Text_file.read = Ok bytes)

let read_text_gives_the_text_of_a_file =
  property ~count:50 ~name:"read_text gives the text of a UTF-8 file"
    ~print:String.escaped Generators.utf_8_string (fun text ->
      in_a_file text Text_file.read_text = Ok text)

let read_text_names_the_first_byte_that_is_not_utf_8 =
  property ~count:50
    ~name:"read_text names the first byte of a file that is not UTF-8"
    ~print:(fun (offset, text) -> Printf.sprintf "%d %S" offset text)
    Generators.not_utf_8_string_at
    (fun (offset, text) ->
      in_a_file text Text_file.read_text = Error (Text_file.Not_utf_8 offset)
      && in_a_file text Text_file.read = Ok text)

let refuses_a_directory () =
  Alcotest.check content "read" (Error Text_file.Is_a_directory)
    (Text_file.read ".");
  Alcotest.check content "read_text" (Error Text_file.Is_a_directory)
    (Text_file.read_text ".")

let gives_the_message_of_the_system_for_a_file_that_does_not_open () =
  Alcotest.check content "the message names the file"
    (Error (Text_file.Cannot_open "no-such-file.txt: No such file or directory"))
    (Text_file.read_text "no-such-file.txt")

let names_the_file_in_every_message () =
  let check expected error =
    Alcotest.(check string) expected expected (Text_file.message "f.txt" error)
  in
  check "f.txt: is a directory" Text_file.Is_a_directory;
  check "f.txt: No such file" (Text_file.Cannot_open "f.txt: No such file");
  check "f.txt: Input/output error" (Text_file.Cannot_read "Input/output error");
  check "f.txt: the file ended sooner than its length says"
    Text_file.Shorter_than_its_length;
  check "f.txt: the file is not UTF-8 text, at byte 7" (Text_file.Not_utf_8 7)

let a_final_line_feed_ends_the_text =
  property ~name:"with_final_line_feed gives a text that ends with a line feed"
    ~print:String.escaped Generators.source_text (fun text ->
      let result = Text_file.with_final_line_feed text in
      String.ends_with ~suffix:"\n" result
      && String.starts_with ~prefix:text result
      && String.length result
         = String.length text
           + if String.ends_with ~suffix:"\n" text then 0 else 1)

let a_text_that_ends_with_a_line_feed_does_not_change =
  property ~name:"with_final_line_feed keeps a text that ends with a line feed"
    ~print:String.escaped Generators.source_text (fun text ->
      let text = text ^ "\n" in
      String.equal (Text_file.with_final_line_feed text) text)

let the_empty_text_gives_one_line_feed () =
  Alcotest.(check string)
    "one line feed" "\n"
    (Text_file.with_final_line_feed "");
  Alcotest.(check string)
    "a line feed after a carriage return" "a\r\n"
    (Text_file.with_final_line_feed "a\r")

let tests =
  [
    Alcotest.test_case "refuses a directory" `Quick refuses_a_directory;
    Alcotest.test_case
      "gives the message of the system for a file that does not open" `Quick
      gives_the_message_of_the_system_for_a_file_that_does_not_open;
    Alcotest.test_case "names the file in every message" `Quick
      names_the_file_in_every_message;
    Alcotest.test_case "the empty text gives one line feed" `Quick
      the_empty_text_gives_one_line_feed;
    read_gives_the_bytes_of_a_file;
    read_text_gives_the_text_of_a_file;
    read_text_names_the_first_byte_that_is_not_utf_8;
    a_final_line_feed_ends_the_text;
    a_text_that_ends_with_a_line_feed_does_not_change;
  ]
