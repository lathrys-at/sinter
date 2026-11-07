(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Sinter_core

let write folder name content =
  Out_channel.with_open_bin (Filename.concat folder name) (fun channel ->
      output_string channel content)

let lines source path numbers = List.map (Source.line source path) numbers
let case name f = Alcotest.test_case name `Quick f

let names =
  [ "a.md"; "empty.md"; "bytes.md"; "folder"; "missing.md"; "later.md" ]

let create ~root = Source.create ~root ~manifest:"sinter.toml" ~files:names
let lines_testable = Alcotest.(list (option string))

let a_line_is_its_content_without_its_line_ending () =
  Fixture.with_temporary_folder (fun root ->
      write root "a.md" "\xef\xbb\xbfone\r\ntwo\n\nlast";
      Alcotest.check lines_testable "the lines"
        [ Some "one"; Some "two"; Some ""; Some "last" ]
        (lines (create ~root) "a.md" [ 1; 2; 3; 4 ]))

let a_line_outside_the_file_is_none () =
  Fixture.with_temporary_folder (fun root ->
      write root "a.md" "one\ntwo\n";
      write root "empty.md" "";
      let source = create ~root in
      Alcotest.check lines_testable
        "line 0, line 3, and a line of an empty file" [ None; None; None ]
        (lines source "a.md" [ 0; 3 ] @ lines source "empty.md" [ 1 ]))

let a_file_that_gives_no_text_has_no_line () =
  Fixture.with_temporary_folder (fun root ->
      write root "bytes.md" "one\n\xff\n";
      Unix.mkdir (Filename.concat root "folder") 0o755;
      let source = create ~root in
      Alcotest.check lines_testable
        "a file that is not UTF-8, a folder, and a missing file"
        [ None; None; None ]
        (List.map
           (fun path -> Source.line source path 1)
           [ "bytes.md"; "folder"; "missing.md" ]))

let a_path_with_a_link_has_no_line () =
  Fixture.with_temporary_folder (fun scratch ->
      let root = Filename.concat scratch "root" in
      let outside = Filename.concat scratch "outside" in
      Unix.mkdir root 0o755;
      Unix.mkdir outside 0o755;
      write outside "secret.md" "hidden-value\n";
      Unix.symlink
        (Filename.concat outside "secret.md")
        (Filename.concat root "file.md");
      Unix.symlink outside (Filename.concat root "folder");
      let source =
        Source.create ~root ~manifest:"sinter.toml"
          ~files:[ "file.md"; "folder/secret.md" ]
      in
      Alcotest.check lines_testable "a link at the end and a link on the way"
        [ None; None ]
        [
          Source.line source "file.md" 1;
          Source.line source "folder/secret.md" 1;
        ])

let a_file_outside_the_set_has_no_line () =
  Fixture.with_temporary_folder (fun root ->
      write root "ignored.env" "hidden-value\n";
      write root "a.md" "one\n";
      let source =
        Source.create ~root ~manifest:"sinter.toml" ~files:[ "a.md" ]
      in
      Alcotest.check lines_testable
        "the file outside the set, and the file in it" [ None; Some "one" ]
        [ Source.line source "ignored.env" 1; Source.line source "a.md" 1 ])

let a_manifest_outside_the_set_has_lines () =
  Fixture.with_temporary_folder (fun root ->
      write root "m.toml" "one\n";
      Alcotest.check lines_testable "the line" [ Some "one" ]
        (lines
           (Source.create ~root ~manifest:"m.toml" ~files:[])
           "m.toml" [ 1 ]))

let an_absolute_path_names_no_file () =
  Fixture.with_temporary_folder (fun root ->
      write root "m.toml" "one\n";
      write root "secret.env" "hidden-value\n";
      Unix.mkfifo (Filename.concat root "pipe") 0o644;
      let path name = Filename.concat root name in
      Alcotest.check lines_testable
        "the manifest, a file of the set, a file, and a pipe that no read \
         waits for"
        [ None; None; None; None ]
        (List.map
           (fun name ->
             Source.line
               (Source.create ~root ~manifest:(path "m.toml")
                  ~files:[ path "secret.env" ])
               (path name) 1)
           [ "m.toml"; "secret.env"; "secret.env"; "pipe" ]);
      Alcotest.check lines_testable "a manifest that is the pipe" [ None ]
        (lines
           (Source.create ~root ~manifest:(path "pipe") ~files:[])
           (path "pipe") [ 1 ]))

let a_file_is_read_once () =
  Fixture.with_temporary_folder (fun root ->
      write root "a.md" "one\ntwo\n";
      let source = create ~root in
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
    case "a path with a link has no line" a_path_with_a_link_has_no_line;
    case "a file outside the set has no line" a_file_outside_the_set_has_no_line;
    case "a manifest outside the set has lines"
      a_manifest_outside_the_set_has_lines;
    case "an absolute path names no file" an_absolute_path_names_no_file;
    case "a file is read once" a_file_is_read_once;
  ]
