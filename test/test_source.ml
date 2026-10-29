(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let write folder name content =
  Out_channel.with_open_bin (Filename.concat folder name) (fun channel ->
      output_string channel content)

let lines source path numbers = List.map (Source.line source path) numbers
let case name f = Alcotest.test_case name `Quick f
let lines_testable = Alcotest.(list (option string))

let a_line_is_its_content_without_its_line_ending () =
  Fixture.with_temporary_folder (fun root ->
      write root "a.md" "\xef\xbb\xbfone\r\ntwo\n\nlast";
      Alcotest.check lines_testable "the lines"
        [ Some "one"; Some "two"; Some ""; Some "last" ]
        (lines (Source.create ~root) "a.md" [ 1; 2; 3; 4 ]))

let a_line_outside_the_file_is_none () =
  Fixture.with_temporary_folder (fun root ->
      write root "a.md" "one\ntwo\n";
      write root "empty.md" "";
      let source = Source.create ~root in
      Alcotest.check lines_testable
        "line 0, line 3, and a line of an empty file" [ None; None; None ]
        (lines source "a.md" [ 0; 3 ] @ lines source "empty.md" [ 1 ]))

let a_file_that_gives_no_text_has_no_line () =
  Fixture.with_temporary_folder (fun root ->
      write root "bytes.md" "one\n\xff\n";
      Unix.mkdir (Filename.concat root "folder") 0o755;
      let source = Source.create ~root in
      Alcotest.check lines_testable
        "a file that is not UTF-8, a folder, and a missing file"
        [ None; None; None ]
        (List.map
           (fun path -> Source.line source path 1)
           [ "bytes.md"; "folder"; "missing.md" ]))

let an_absolute_path_names_itself () =
  Fixture.with_temporary_folder (fun root ->
      write root "a.md" "one\n";
      Alcotest.check lines_testable "the line" [ Some "one" ]
        (lines
           (Source.create ~root:"/nonexistent")
           (Filename.concat root "a.md")
           [ 1 ]))

let a_file_is_read_once () =
  Fixture.with_temporary_folder (fun root ->
      write root "a.md" "one\ntwo\n";
      let source = Source.create ~root in
      let missing = Source.line source "later.md" 1 in
      let first = Source.line source "a.md" 1 in
      Sys.remove (Filename.concat root "a.md");
      write root "later.md" "now\n";
      Alcotest.check lines_testable "the lines after the files change on disk"
        [ None; Some "one"; Some "two"; None ]
        [
          missing;
          first;
          Source.line source "a.md" 2;
          Source.line source "later.md" 1;
        ])

let tests =
  [
    case "a line is its content without its line ending"
      a_line_is_its_content_without_its_line_ending;
    case "a line outside the file is none" a_line_outside_the_file_is_none;
    case "a file that gives no text has no line"
      a_file_that_gives_no_text_has_no_line;
    case "an absolute path names itself" an_absolute_path_names_itself;
    case "a file is read once" a_file_is_read_once;
  ]
