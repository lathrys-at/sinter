(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

module Gen = QCheck2.Gen

let sh = "/bin/sh"

let rec make_folder path =
  if not (Sys.file_exists path) then (
    make_folder (Filename.dirname path);
    Sys.mkdir path 0o755)

let write_at root path text =
  let full = Filename.concat root path in
  make_folder (Filename.dirname full);
  Out_channel.with_open_bin full (fun channel ->
      Out_channel.output_string channel text)

let read path = In_channel.with_open_bin path In_channel.input_all

let summary_of pages =
  String.concat ""
    (List.map
       (fun (page, _) -> Printf.sprintf "- [%s](<%s>)\n" page page)
       pages)

let with_book ?summary ?(files = []) pages f =
  Fixture.with_temporary_folder (fun book ->
      let summary = Option.value summary ~default:(summary_of pages) in
      write_at book "src/SUMMARY.md" summary;
      List.iter
        (fun (page, text) -> write_at book (Filename.concat "src" page) text)
        pages;
      List.iter (fun (path, text) -> write_at book path text) files;
      f book)

let error =
  Alcotest.testable
    (fun formatter error ->
      Format.pp_print_string formatter (Book.message error))
    ( = )

let outcome = Alcotest.(result (list string) error)
let located line problem = { Book.file = "src/p.md"; line = Some line; problem }

let run_text ?files ?(binary = sh) ?(mode = Book.Compare) text =
  with_book ?files
    [ ("p.md", text) ]
    (fun book -> Book.run_page ~binary mode ~book "p.md")

let passes name text () = Alcotest.check outcome name (Ok []) (run_text text)

let fails name text line problem () =
  Alcotest.check outcome name (Error (located line problem)) (run_text text)

let test name f = Alcotest.test_case name `Quick f

let check_links_of ?summary ?files pages =
  with_book ?summary ?files pages Book.check_links

let links = Alcotest.list error

let in_page ?(file = "src/p.md") line problem =
  { Book.file; line = Some line; problem }

let run_rules =
  [
    test "a block with the right output passes"
      (passes "the output matches" "```console,run\n$ echo hello\nhello\n```\n");
    test "a block with wrong output fails"
      (fails "the output differs" "```console,run\n$ echo hello\nbye\n```\n" 2
         (Book.Differs
            { command = "echo hello"; expected = "bye\n"; actual = "hello\n" }));
    test "a block with no output line fails when the command writes"
      (fails "the output is missing" "```console,run\n$ echo hello\n```\n" 2
         (Book.Differs
            { command = "echo hello"; expected = ""; actual = "hello\n" }));
    test "a block with an extra output line fails"
      (fails "the output is shorter" "```console,run\n$ true\nextra\n```\n" 2
         (Book.Differs { command = "true"; expected = "extra\n"; actual = "" }));
    test "a space at the end of an output line fails"
      (fails "the comparison is byte for byte"
         "```console,run\n$ echo hello\nhello \n```\n" 2
         (Book.Differs
            {
              command = "echo hello";
              expected = "hello \n";
              actual = "hello\n";
            }));
    test "output with no last line feed fails"
      (fails "the comparison holds the line feed"
         "```console,run\n$ printf hello\nhello\n```\n" 2
         (Book.Differs
            { command = "printf hello"; expected = "hello\n"; actual = "hello" }));
    test "standard error is part of the output, in order"
      (passes "both streams are one"
         "```console,run\n\
          $ echo one; echo two >&2; echo three\n\
          one\n\
          two\n\
          three\n\
          ```\n");
    test "each command compares with the lines below it"
      (fails "the second command is wrong"
         "```console,run\n$ echo one\none\n$ echo two\nthree\n```\n" 4
         (Book.Differs
            { command = "echo two"; expected = "three\n"; actual = "two\n" }));
    test "a last command with the exit of the label passes"
      (passes "the code matches" "```console,run,exit=3\n$ exit 3\n```\n");
    test "a last command with another exit code fails"
      (fails "the code differs" "```console,run,exit=3\n$ exit 4\n```\n" 2
         (Book.Wrong_exit
            { command = "exit 4"; expected = 3; actual = 4; output = "" }));
    test "the default exit code is 0"
      (fails "the code is not 0" "```console,run\n$ exit 1\n```\n" 2
         (Book.Wrong_exit
            { command = "exit 1"; expected = 0; actual = 1; output = "" }));
    test "exit=0 asks for 0"
      (fails "the code is not 0" "```console,run,exit=0\n$ exit 1\n```\n" 2
         (Book.Wrong_exit
            { command = "exit 1"; expected = 0; actual = 1; output = "" }));
    test "a command before the last one must exit with 0"
      (fails "the first command fails"
         "```console,run,exit=2\n$ exit 2\n$ exit 2\n```\n" 2
         (Book.Wrong_exit
            { command = "exit 2"; expected = 0; actual = 2; output = "" }));
    test "a last command that exits with 0 fails under exit=1"
      (fails "the label promises a failure"
         "```console,run,exit=1\n$ true\n```\n" 2
         (Book.Wrong_exit
            { command = "true"; expected = 1; actual = 0; output = "" }));
    test "a run block with no line fails"
      (fails "the block is empty" "```console,run\n```\n" 2 Book.No_command);
    test "a run block that starts with output fails"
      (fails "output before any command" "```console,run\nhello\n$ true\n```\n"
         2 Book.No_command);
    test "a command with no text fails"
      (fails "the line is only the prompt" "```console,run\n$ true\n$  \n```\n"
         3 Book.No_command);
    test "a line \"$\" with no space is output"
      (passes "the prompt needs its space"
         "```console,run\n$ echo '$'\n$\n```\n");
    test "a command that runs past its bound fails" (fun () ->
        Alcotest.check outcome "the run is killed"
          (Error (located 2 (Book.Harness (Fixture.Did_not_end 0.05))))
          (with_book
             [ ("p.md", "```console,run\n$ sleep 5\n```\n") ]
             (fun book ->
               Book.run_page ~bound:0.05 ~binary:sh Book.Compare ~book "p.md")));
    test "a relative binary raises" (fun () ->
        Alcotest.check_raises "the path is relative"
          (Invalid_argument "Book.run_page: the binary is not an absolute path")
          (fun () ->
            ignore
              (Book.run_page ~binary:"sinter" Book.Compare ~book:"." "p.md")));
    test "a missing page fails" (fun () ->
        with_book [] (fun book ->
            match Book.run_page ~binary:sh Book.Compare ~book "gone.md" with
            | Error
                { problem = Book.Harness (Fixture.System _); line = None; _ } ->
                ()
            | _ -> Alcotest.fail "a missing page gave no system error"));
  ]

let shell_state_rules =
  List.map
    (fun command ->
      test
        (Printf.sprintf "the command %S fails" command)
        (fails "it keeps state in its shell"
           (Printf.sprintf "```console,run\n$ %s\n```\n" command)
           2 (Book.Keeps_shell_state command)))
    [
      "cd docs";
      "cd";
      "cd docs && ls";
      "cd docs; ls";
      "export FOO=1";
      "export";
      "FOO=1";
      "FOO=1 BAR=2";
      "FOO=\"a b\"";
      "FOO='a b' BAR=c";
      "FOO=";
      "FOO=1; true";
      "_foo9=a\\ b";
    ]
  @ [
      test "a variable in front of a command is allowed"
        (passes "the command sees it"
           "```console,run\n$ FOO=1 sh -c 'echo $FOO'\n1\n```\n");
      test "two variables in front of a command are allowed"
        (passes "the command sees both"
           "```console,run\n$ A=1 B=\"2 3\" sh -c 'echo $A $B'\n1 2 3\n```\n");
      test "a word that starts with cd is allowed"
        (passes "the word is not cd"
           "```console,run\n$ cdd=1 true\n$ export_it() { :; }; true\n```\n");
      test "each command runs in a new shell"
        (passes "the variable is gone"
           "```console,run\n$ FOO=1 true\n$ echo \"[$FOO]\"\n[]\n```\n");
      test "each command starts at the root of the repository"
        (passes "the folder does not carry over"
           "```console,run\n\
            $ mkdir sub && (cd sub && pwd >/dev/null)\n\
            $ ls\n\
            sub\n\
            ```\n");
    ]

let labels =
  List.map
    (fun label ->
      test
        (Printf.sprintf "the label %S fails" label)
        (fails "the label is not known"
           (Printf.sprintf "```%s\n$ true\n```\n" label)
           1 (Book.Unknown_label label)))
    [
      "console,";
      "console,foo";
      "console,run,";
      "console,run,exit";
      "console,run,exit=";
      "console,run,exit=-1";
      "console,run,exit=256";
      "console,run,exit=1000";
      "console,run,exit=a";
      "console,run,exit=1,run";
      "console,exit=1";
      "console,exit=1,run";
      "console,planned,exit=1";
      "console,planned,run";
      "console,run,planned";
      "console,run,run";
      "console run";
      "console, run";
      "console,file=a";
      "CONSOLE,foo";
      ",run";
      "toml,run";
      "toml,planned";
      "toml,file=";
      "toml,foo";
      "toml,file=a,file=b";
      "toml,file=a,run";
      "toml,file=a b";
      "toml title";
    ]
  @ [
      test "a console block with neither label fails"
        (fails "the block says nothing" "```console\n$ true\n```\n" 1
           Book.Console_without_label);
      test "a Console block with neither label fails"
        (fails "the case of letters does not hide it"
           "```Console\n$ true\n```\n" 1 Book.Console_without_label);
      test "a tilde console block with neither label fails"
        (fails "the other fence counts too" "~~~console\n$ true\n~~~\n" 1
           Book.Console_without_label);
      test "exit=255 is the largest code"
        (passes "the code is in range"
           "```console,run,exit=255\n$ exit 255\n```\n");
      test "a shown block with a command fails"
        (fails "the command would go untested" "```sh\ntext\n$ rm x\n```\n" 3
           Book.Command_outside_block);
      test "a block with no label and a command fails"
        (fails "the command would go untested" "```\n$ rm x\n```\n" 2
           Book.Command_outside_block);
      test "a shown block with no command passes"
        (passes "nothing runs" "```text\nexit 3\n```\n\n```\nanything\n```\n");
      test "a file block may hold a line that starts with the prompt"
        (passes "the file holds the line"
           "```text,file=a.txt\n\
            $ text\n\
            ```\n\n\
            ```console,run\n\
            $ wc -l <a.txt | tr -d ' '\n\
            1\n\
            ```\n");
    ]

let files =
  List.map
    (fun path ->
      test
        (Printf.sprintf "the path %S fails" path)
        (fails "the path is not allowed"
           (Printf.sprintf "```text,file=%s\nx\n```\n" path)
           1 (Book.Path_outside path)))
    [
      "../x";
      "/tmp/x";
      "a/../../x";
      "a/../b";
      "./a";
      "a/./b";
      "a//b";
      "a/";
      "..";
      ".";
      ".git/config";
      ".GIT/config";
      "a/.git/config";
    ]
  @ [
      test "a file block writes its text"
        (passes "the file holds the text"
           "```text,file=a.txt\n\
            one\n\n\
            two\n\
            ```\n\n\
            ```console,run\n\
            $ cat a.txt\n\
            one\n\n\
            two\n\
            ```\n");
      test "a file block makes missing folders"
        (passes "the folders exist"
           "```text,file=a/b/c.txt\n\
            x\n\
            ```\n\n\
            ```console,run\n\
            $ cat a/b/c.txt\n\
            x\n\
            ```\n");
      test "an empty file block writes an empty file"
        (passes "the file is empty"
           "```text,file=a.txt\n\
            ```\n\n\
            ```console,run\n\
            $ wc -c <a.txt | tr -d ' '\n\
            0\n\
            ```\n");
      test "a later file block replaces the text"
        (passes "the second text stands"
           "```text,file=a.txt\n\
            one\n\
            ```\n\n\
            ```text,file=a.txt\n\
            two\n\
            ```\n\n\
            ```console,run\n\
            $ cat a.txt\n\
            two\n\
            ```\n");
      test "a path through a symbolic link fails"
        (fails "the link leaves the repository"
           "```console,run\n\
            $ ln -s /tmp out\n\
            ```\n\n\
            ```text,file=out/x\n\
            x\n\
            ```\n"
           5 (Book.Path_outside "out/x"));
      test "a path that is a symbolic link fails"
        (fails "the link would be followed"
           "```console,run\n\
            $ ln -s /tmp/gone out\n\
            ```\n\n\
            ```text,file=out\n\
            x\n\
            ```\n"
           5 (Book.Path_outside "out"));
      test "a path under a file fails" (fun () ->
          match
            run_text "```text,file=a\nx\n```\n\n```text,file=a/b\nx\n```\n"
          with
          | Error { problem = Book.Harness (Fixture.System _); _ } -> ()
          | _ -> Alcotest.fail "the write under a file did not fail");
    ]

let planned_rules =
  let note = "> [!NOTE]\n> Sinter does not have this command yet.\n\n" in
  [
    test "a planned block under a note does not run"
      (passes "the marker is not there"
         (note
        ^ "```console,planned\n\
           $ touch marker\n\
           $ exit 3\n\
           wrong\n\
           ```\n\n\
           Text.\n\n\
           ```console,run\n\
           $ ls\n\
           ```\n"));
    test "a planned block with text below the note passes"
      (passes "text may lie between"
         (note ^ "Some text.\n\n## A heading\n\n```console,planned\n$ x\n```\n"));
    test "a broken link in a note fails" (fun () ->
        Alcotest.check links "the note holds text"
          [ in_page 2 (Book.Missing_target "gone.md") ]
          (check_links_of
             [
               ( "p.md",
                 "> [!NOTE]\n> Sinter does not have this [x](gone.md) yet.\n" );
             ]));
    test "a planned block with no note fails"
      (fails "the note is missing" "```console,planned\n$ x\n```\n" 1
         Book.Planned_without_note);
    test "a planned block with a shown block between fails"
      (fails "the block is between"
         (note ^ "```text\nx\n```\n\n```console,planned\n$ x\n```\n")
         8 Book.Planned_without_note);
    test "a planned block with a file block between fails"
      (fails "the block is between"
         (note ^ "```text,file=a\nx\n```\n\n```console,planned\n$ x\n```\n")
         8 Book.Planned_without_note);
    test "a planned block with a run block between fails"
      (fails "the block is between"
         (note
        ^ "Text.\n\n\
           ```console,run\n\
           $ true\n\
           ```\n\n\
           ```console,planned\n\
           $ x\n\
           ```\n")
         10 Book.Planned_without_note);
    test "a second planned block under one note fails"
      (fails "each planned block needs a note"
         (note
        ^ "```console,planned\n$ x\n```\n\n```console,planned\n$ y\n```\n")
         8 Book.Planned_without_note);
    test "a run block right under a note fails"
      (fails "no text lies between"
         (note ^ "```console,run\n$ true\n```\n")
         4 Book.Run_under_note);
    test "a run block under a note with a block between and no text fails"
      (fails "a block is not text"
         (note ^ "```text,file=a\nx\n```\n\n```console,run\n$ true\n```\n")
         8 Book.Run_under_note);
    test "a run block under a planned block with no text fails"
      (fails "the note still stands above it"
         (note ^ "```console,planned\n$ x\n```\n\n```console,run\n$ true\n```\n")
         8 Book.Run_under_note);
    test "a run block under a note with later text passes"
      (passes "the text ends the reach of the note"
         (note ^ "Text.\n\n```console,run\n$ true\n```\n"));
    test "a comment is not text under a note"
      (fails "the comment does not count"
         (note ^ "<!-- text -->\n\n```console,run\n$ true\n```\n")
         6 Book.Run_under_note);
    test "a note with no block below passes"
      (passes "a note can stand alone" (note ^ "Text.\n"));
    test "a note at the end of the file with no line feed passes"
      (passes "the end of the file is enough"
         "> [!NOTE]\n> Sinter does not have this thing yet.");
  ]
  @ List.map
      (fun (name, text, line) ->
        test name (fails "the note is not exact" text line Book.Bad_note))
      [
        ("a note with other words fails", "> [!NOTE]\n> This is not built.\n", 1);
        ("a note with no text fails", "> [!NOTE]\n", 1);
        ( "a note with an empty thing fails",
          "> [!NOTE]\n> Sinter does not have this  yet.\n",
          1 );
        ( "a note with only spaces for its thing fails",
          "> [!NOTE]\n> Sinter does not have this    yet.\n",
          1 );
        ( "a note with no thing fails",
          "> [!NOTE]\n> Sinter does not have this yet.\n",
          1 );
        ( "a note with no full stop fails",
          "> [!NOTE]\n> Sinter does not have this thing yet\n",
          1 );
        ( "a note with more quote lines fails",
          "> [!NOTE]\n> Sinter does not have this thing yet.\n> More.\n",
          1 );
        ( "a note with text right below fails",
          "> [!NOTE]\n> Sinter does not have this thing yet.\nMore.\n",
          1 );
        ( "a note in lower case fails",
          "> [!note]\n> Sinter does not have this thing yet.\n",
          1 );
        ( "a note with no space after the mark fails",
          ">[!NOTE]\n> Sinter does not have this thing yet.\n",
          1 );
        ( "a note with its text on the first line fails",
          "> [!NOTE] Sinter does not have this thing yet.\n",
          1 );
        ( "a note in a list fails",
          "- > [!NOTE]\n  > Sinter does not have this thing yet.\n",
          1 );
      ]

let structure_rules =
  [
    test "a fence in a list fails"
      (fails "the fence is nested"
         "1. Step:\n\n   ```console,run\n   $ x\n   ```\n" 3 Book.Nested_fence);
    test "a fence with a list marker on its line fails"
      (fails "the fence is nested" "- ```console,run\n  $ x\n  ```\n" 1
         Book.Nested_fence);
    test "a fence in a block quote fails"
      (fails "the fence is nested" "> ```console,run\n> $ x\n> ```\n" 1
         Book.Nested_fence);
    test "an indented fence fails"
      (fails "the fence is nested" "  ```console,run\n  $ x\n  ```\n" 1
         Book.Nested_fence);
    test "a fence with no end fails"
      (fails "the block never closes" "```console,run\n$ x\n" 1
         Book.Unclosed_fence);
    test "a shorter fence does not close a block"
      (fails "the block never closes" "````text\n```\n" 1 Book.Unclosed_fence);
    test "a fence of the other mark does not close a block"
      (fails "the block never closes" "```text\n~~~\n" 1 Book.Unclosed_fence);
    test "a fence with text after it does not close a block"
      (fails "the block never closes" "```text\n``` more\n" 1
         Book.Unclosed_fence);
    test "a longer fence holds a shorter one"
      (passes "the inner fence is text"
         "````text,file=a\n```\n````\n\n````console,run\n$ cat a\n```\n````\n");
    test "an indented closing fence closes a block"
      (passes "up to three spaces are allowed"
         "```console,run\n$ true\n   ```\n");
    test "a fence with four spaces does not close a block"
      (fails "the block never closes" "```text\n    ```\n" 1 Book.Unclosed_fence);
    test "a tilde fence runs too"
      (fails "the output differs" "~~~console,run\n$ echo a\nb\n~~~\n" 2
         (Book.Differs { command = "echo a"; expected = "b\n"; actual = "a\n" }));
    test "a backtick line with a backtick in its info is not a fence"
      (passes "it is a code span" "``` a ``` b\n");
    test "a command in text fails"
      (fails "the command is not in a block" "Text.\n\n$ sinter check\n" 3
         Book.Command_outside_block);
    test "an indented command fails"
      (fails "the command is in an indented block"
         "Text.\n\n    $ sinter check\n" 3 Book.Command_outside_block);
    test "a command in a list fails"
      (fails "the command is not in a block" "- $ sinter check\n" 1
         Book.Command_outside_block);
    test "a command in a block quote fails"
      (fails "the command is not in a block" "> $ sinter check\n" 1
         Book.Command_outside_block);
    test "a comment with no end fails"
      (fails "the comment never closes" "Text.\n\n<!-- open\n\nmore\n" 3
         Book.Unclosed_comment);
    test "a block in a comment does not run"
      (passes "the comment hides it"
         "<!--\n```console,run\n$ exit 3\n```\n-->\n");
    test "a code span with a comment mark opens no comment"
      (passes "the span is text" "Use `<!--` here.\n\nMore.\n");
    test "a comment on one line leaves the text around it"
      (passes "the text stays"
         "> [!NOTE]\n\
          > Sinter does not have this x yet.\n\n\
          <!-- c --> Text.\n\n\
          ```console,run\n\
          $ true\n\
          ```\n");
    test "check_page reports the line of the problem" (fun () ->
        Alcotest.(check (option int))
          "the line" (Some 3)
          (match Book.check_page "Text.\n\n```console\n```\n" with
          | Error (line, _) -> Some line
          | Ok () -> None));
    test "check_page passes a good page" (fun () ->
        Alcotest.(check bool)
          "no problem" true
          (Book.check_page "# Title\n\n```console,run\n$ true\n```\n" = Ok ()));
  ]

let fake_tool book =
  let path = Filename.concat book "fake-sinter" in
  write_at book "fake-sinter" "#!/bin/sh\nprintf 'fake %s\\n' \"$*\"\n";
  Unix.chmod path 0o755;
  path

let repository_rules =
  [
    test "sinter on the path is the binary" (fun () ->
        with_book
          [ ("p.md", "```console,run\n$ sinter one two\nfake one two\n```\n") ]
          (fun book ->
            Alcotest.check outcome "the fake tool ran" (Ok [])
              (Book.run_page ~binary:(fake_tool book) Book.Compare ~book "p.md")));
    test "the commands run in a repository on main with no commit"
      (passes "no commit, no file"
         "```console,run\n\
          $ git symbolic-ref HEAD\n\
          refs/heads/main\n\
          $ git rev-list --all\n\
          $ ls -A\n\
          .git\n\
          ```\n");
    test "a listing is committed before the first block" (fun () ->
        Alcotest.check outcome "the listing is the one commit" (Ok [])
          (run_text
             ~files:[ ("listings/p/docs/a.txt", "from the listing\n") ]
             "```console,run\n\
              $ cat docs/a.txt\n\
              from the listing\n\
              $ git status --short\n\
              $ git rev-list --count HEAD\n\
              1\n\
              ```\n"));
    test "a page takes the listing of its stem, in any folder" (fun () ->
        with_book
          ~files:[ ("listings/p/a.txt", "x\n") ]
          [ ("guide/p.md", "```console,run\n$ cat a.txt\nx\n```\n") ]
          (fun book ->
            Alcotest.check outcome "the listing is there" (Ok [])
              (Book.run_page ~binary:sh Book.Compare ~book "guide/p.md")));
    test "the listing of another page stays out" (fun () ->
        Alcotest.check outcome "the file is not there" (Ok [])
          (run_text
             ~files:[ ("listings/other/a.txt", "x\n") ]
             "```console,run\n$ ls\n```\n"));
    test "commits have a fixed identity and date, so a fixed id"
      (passes "the commit is the same on each run"
         "```console,run\n\
          $ git commit --quiet --allow-empty --message x\n\
          $ git log --date=raw --format='%an <%ae> %ad, %cn <%ce> %cd'\n\
          Sinter Fixture <fixture@sinter.invalid> 1767225600 +0000, Sinter \
          Fixture <fixture@sinter.invalid> 1767225600 +0000\n\
          $ git rev-parse HEAD\n\
          357820a382ed1ad15e952f32c386f8a0db4c673d\n\
          ```\n");
    test "a variable of the caller's git reaches no command" (fun () ->
        Alcotest.check outcome "the fixed values win" (Ok [])
          (with_book
             [
               ( "p.md",
                 "```console,run\n\
                  $ echo \"$GIT_AUTHOR_NAME/$HOME_IS_KEPT/$NO_COLOR/$LC_ALL\"\n\
                  Sinter Fixture/kept//C\n\
                  ```\n" );
             ]
             (fun book ->
               Book.run_page
                 ~caller:
                   [|
                     "GIT_AUTHOR_NAME=Someone";
                     "HOME_IS_KEPT=kept";
                     "NO_COLOR=1";
                     "LC_ALL=de_DE";
                   |]
                 ~binary:sh Book.Compare ~book "p.md")));
    test "two pages run in two repositories" (fun () ->
        with_book
          [
            ("a.md", "```text,file=x\nx\n```\n");
            ("b.md", "```console,run\n$ ls\n```\n");
          ]
          (fun book ->
            Alcotest.check outcome "the first page" (Ok [])
              (Book.run_page ~binary:sh Book.Compare ~book "a.md");
            Alcotest.check outcome "the second page sees no file" (Ok [])
              (Book.run_page ~binary:sh Book.Compare ~book "b.md")));
    test "the program leaves the book as it found it" (fun () ->
        with_book
          [ ("p.md", "```text,file=x\nx\n```\n") ]
          (fun book ->
            ignore (Book.run_page ~binary:sh Book.Compare ~book "p.md");
            Alcotest.(check (list string))
              "nothing new" [ "src" ]
              (Array.to_list (Sys.readdir book))));
  ]

let promote_rules =
  let promote ?(files = []) text check =
    with_book ~files
      [ ("p.md", text) ]
      (fun book ->
        Fixture.with_temporary_folder (fun source ->
            write_at source "p.md" text;
            let result =
              Book.run_page ~binary:sh (Book.Promote_into source) ~book "p.md"
            in
            check ~source ~text:(read (Filename.concat source "p.md")) result))
  in
  [
    test "promotion rewrites the output of a run block" (fun () ->
        promote "Before.\n\n```console,run\n$ echo new\nold\n```\n\nAfter.\n"
          (fun ~source ~text result ->
            Alcotest.check outcome "it names the page"
              (Ok [ Filename.concat source "p.md" ])
              result;
            Alcotest.(check string)
              "only the output changed"
              "Before.\n\n```console,run\n$ echo new\nnew\n```\n\nAfter.\n" text));
    test "promotion rewrites each command of a block and each block" (fun () ->
        promote
          "```console,run\n\
           $ echo a\n\
           x\n\
           y\n\
           $ echo b\n\
           ```\n\n\
           ```console,run\n\
           $ echo c\n\
           ```" (fun ~source:_ ~text _ ->
            Alcotest.(check string)
              "each output changed"
              "```console,run\n\
               $ echo a\n\
               a\n\
               $ echo b\n\
               b\n\
               ```\n\n\
               ```console,run\n\
               $ echo c\n\
               c\n\
               ```"
              text));
    test "promotion writes nothing when no output changed" (fun () ->
        promote "```console,run\n$ echo a\na\n```\n"
          (fun ~source:_ ~text result ->
            Alcotest.check outcome "no path" (Ok []) result;
            Alcotest.(check string)
              "the page stands" "```console,run\n$ echo a\na\n```\n" text));
    test "promotion does not touch a planned block or a file block" (fun () ->
        let text =
          "> [!NOTE]\n\
           > Sinter does not have this x yet.\n\n\
           ```console,planned\n\
           $ echo a\n\
           old\n\
           ```\n\n\
           ```text,file=a\n\
           old\n\
           ```\n"
        in
        promote text (fun ~source:_ ~text:after result ->
            Alcotest.check outcome "no path" (Ok []) result;
            Alcotest.(check string) "the page stands" text after));
    test "promotion keeps a wrong exit code an error" (fun () ->
        let text = "```console,run\n$ echo a; exit 2\nold\n```\n" in
        promote text (fun ~source:_ ~text:after result ->
            Alcotest.check outcome "the code differs"
              (Error
                 (located 2
                    (Book.Wrong_exit
                       {
                         command = "echo a; exit 2";
                         expected = 0;
                         actual = 2;
                         output = "a\n";
                       })))
              result;
            Alcotest.(check string) "the page stands" text after));
    test "an error in a later block writes nothing" (fun () ->
        let text =
          "```console,run\n\
           $ echo a\n\
           old\n\
           ```\n\n\
           Text.\n\n\
           ```console,run\n\
           $ exit 2\n\
           ```\n"
        in
        promote text (fun ~source:_ ~text:after result ->
            Alcotest.(check bool) "an error" true (Result.is_error result);
            Alcotest.(check string) "the page stands" text after));
    test "a command that the block cannot hold does not promote" (fun () ->
        List.iter
          (fun (command, output) ->
            let text = Printf.sprintf "```console,run\n$ %s\n```\n" command in
            promote text (fun ~source:_ ~text:after result ->
                Alcotest.check outcome "the block cannot hold it"
                  (Error (located 2 (Book.Cannot_promote { command; output })))
                  result;
                Alcotest.(check string) "the page stands" text after))
          [
            ("printf 'no feed'", "no feed");
            ("printf '$ looks like a command\\n'", "$ looks like a command\n");
            ("printf 'x\\n```\\n'", "x\n```\n");
            ("printf '   ````  \\n'", "   ````  \n");
          ]);
    test "a promoted page passes the comparison" (fun () ->
        let text =
          "```console,run\n\
           $ printf 'a\\n\\nb c \\n'\n\
           ```\n\n\
           ```console,run\n\
           $ true\n\
           old\n\
           ```\n"
        in
        promote text (fun ~source:_ ~text:after _ ->
            Alcotest.check outcome "the new page passes" (Ok [])
              (run_text after)));
    test "mode_of_environment reads SINTER_PROMOTE" (fun () ->
        let show = function
          | Ok Book.Compare -> "compare"
          | Ok (Book.Promote_into folder) -> "promote " ^ folder
          | Error _ -> "error"
        in
        Alcotest.(check string)
          "1 with a root" "promote /r/docs/book/src"
          (show
             (Book.mode_of_environment ~promote:(Some "1")
                ~source_root:(Some "/r")));
        Alcotest.(check string)
          "1 with no root" "error"
          (show
             (Book.mode_of_environment ~promote:(Some "1") ~source_root:None));
        Alcotest.(check string)
          "another value" "compare"
          (show
             (Book.mode_of_environment ~promote:(Some "0")
                ~source_root:(Some "/r")));
        Alcotest.(check string)
          "no value" "compare"
          (show (Book.mode_of_environment ~promote:None ~source_root:None)));
  ]

let link_passes name text ?(files = []) () =
  Alcotest.check links name [] (check_links_of ~files [ ("p.md", text) ])

let link_fails name text line problem () =
  Alcotest.check links name
    [ in_page line problem ]
    (check_links_of [ ("p.md", text); ("other.md", "# Other\n\n## A part\n") ])

let link_rules =
  let other = [ ("other.md", "# Other\n\n## A part\n") ] in
  let passes_with_other name text () =
    Alcotest.check links name [] (check_links_of (("p.md", text) :: other))
  in
  [
    test "a link to a page passes"
      (passes_with_other "the file exists" "[a](other.md)\n");
    test "a link with an anchor passes"
      (passes_with_other "the heading exists" "[a](other.md#a-part)\n");
    test "a link to an anchor of its own page passes"
      (link_passes "the heading exists" "# Title\n\n[a](#title)\n");
    test "an encoded # in a link is part of the name" (fun () ->
        Alcotest.check links "the name holds the mark" []
          (check_links_of ~summary:"- [p](p.md)\n- [x](a%23b.md)\n"
             [ ("p.md", "[a](a%23b.md)\n"); ("a#b.md", "x\n") ]));
    test "a link with a title passes"
      (passes_with_other "the title is not the path"
         "[a](other.md \"A title\")\n");
    test "a link in angle marks passes"
      (passes_with_other "the marks are not the path" "[a](<other.md>)\n");
    test "a percent-encoded link passes" (fun () ->
        Alcotest.check links "the name decodes" []
          (check_links_of
             [ ("p.md", "[a](my%20page.md)\n"); ("my page.md", "x\n") ]));
    test "a link to a file that is not a page passes" (fun () ->
        Alcotest.check links "the file exists" []
          (check_links_of
             ~files:[ ("src/a.png", "x") ]
             [ ("p.md", "![a](a.png)\n") ]));
    test "a link from a folder is relative to that folder" (fun () ->
        Alcotest.check links "the path climbs one folder" []
          (check_links_of
             [
               ("guide/p.md", "[a](../other.md)\n[b](q.md)\n");
               ("guide/q.md", "x\n");
               ("other.md", "x\n");
             ]));
    test "a broken link fails"
      (link_fails "no such file" "Text.\n\n[a](gone.md)\n" 3
         (Book.Missing_target "gone.md"));
    test "a broken image fails"
      (link_fails "no such file" "![a](gone.png)\n" 1
         (Book.Missing_target "gone.png"));
    test "a link with the wrong case fails"
      (link_fails "the case of letters counts" "[a](Other.md)\n" 1
         (Book.Missing_target "Other.md"));
    test "a link to a folder fails" (fun () ->
        Alcotest.check links "a folder is no file"
          [ in_page 1 (Book.Missing_target "guide/") ]
          (check_links_of [ ("p.md", "[a](guide/)\n"); ("guide/q.md", "x\n") ]));
    test "a broken anchor fails"
      (link_fails "no such heading" "[a](other.md#gone)\n" 1
         (Book.Missing_anchor { target = "other.md"; anchor = "gone" }));
    test "an anchor in the wrong case fails"
      (link_fails "ids are in lower case" "[a](other.md#A-Part)\n" 1
         (Book.Missing_anchor { target = "other.md"; anchor = "A-Part" }));
    test "a broken anchor of its own page fails" (fun () ->
        Alcotest.check links "no such heading"
          [
            in_page 1 (Book.Missing_anchor { target = "p.md"; anchor = "gone" });
          ]
          (check_links_of [ ("p.md", "[a](#gone)\n") ]));
    test "an empty anchor fails" (fun () ->
        Alcotest.check links "no heading has an empty id"
          [ in_page 1 (Book.Missing_anchor { target = "p.md"; anchor = "" }) ]
          (check_links_of [ ("p.md", "[a](#)\n") ]));
    test "an anchor on a file that is not a page fails" (fun () ->
        Alcotest.check links "the file has no headings"
          [ in_page 1 (Book.Missing_anchor { target = "a.png"; anchor = "x" }) ]
          (check_links_of
             ~files:[ ("src/a.png", "x") ]
             [ ("p.md", "[a](a.png#x)\n") ]));
    test "an anchor that is not ASCII fails" (fun () ->
        Alcotest.check links "the rule reads no such id"
          [
            in_page 3
              (Book.Missing_anchor { target = "p.md"; anchor = "caf\xc3\xa9" });
          ]
          (check_links_of [ ("p.md", "# Caf\xc3\xa9\n\n[a](#caf\xc3\xa9)\n") ]));
    test "a heading in a block is no anchor" (fun () ->
        Alcotest.check links "the fence hides it"
          [ in_page 5 (Book.Missing_anchor { target = "p.md"; anchor = "no" }) ]
          (check_links_of [ ("p.md", "```text\n# No\n```\n\n[a](#no)\n") ]));
    test "an empty link fails"
      (link_fails "no destination" "[a]()\n" 1 Book.Empty_link);
    test "a link that starts with a slash fails"
      (link_fails "it is not relative" "[a](/other.md)\n" 1
         (Book.Rooted_link "/other.md"));
    test "a link that leaves the book fails"
      (link_fails "it climbs out of src" "[a](../../README.md)\n" 1
         (Book.Link_leaves_book "../../README.md"));
    test "a reference definition is a link"
      (link_fails "the definition is broken" "[a][b]\n\n[b]: gone.md\n" 3
         (Book.Missing_target "gone.md"));
    test "a good reference passes"
      (passes_with_other "the definition holds" "[a][B c]\n\n[b  c]: other.md\n");
    test "a collapsed reference passes"
      (passes_with_other "the text is the label" "[a][]\n\n[a]: other.md\n");
    test "a reference with no definition fails"
      (link_fails "the label is unknown" "[a][b]\n" 1
         (Book.Undefined_reference "b"));
    test "a collapsed reference with no definition fails"
      (link_fails "the label is unknown" "[a][]\n" 1
         (Book.Undefined_reference "a"));
    test "a footnote is not a link"
      (link_passes "the definition is not read"
         "Text[^1].\n\n[^1]: not/a/link.md\n");
    test "an HTML link is a link"
      (link_fails "the href is broken" "<a href=\"gone.md\">a</a>\n" 1
         (Book.Missing_target "gone.md"));
    test "an HTML image is a link"
      (link_fails "the src is broken" "<img src='gone.png'>\n" 1
         (Book.Missing_target "gone.png"));
    test "a link in a code span is not a link"
      (link_passes "the span is text" "Write `[a](gone.md)` here.\n");
    test "a link in a block is not a link"
      (link_passes "the block is text" "```text\n[a](gone.md)\n```\n");
    test "a link in a comment is not a link"
      (link_passes "the comment is not text" "<!-- [a](gone.md) -->\n");
    test "an escaped bracket is not a link"
      (link_passes "the mark is text" "Write \\](gone.md) here.\n");
    test "addresses outside the book are not read"
      (link_passes "nothing reads them"
         "[a](https://gone.invalid/x)\n\
          [b](mailto:a@b.invalid)\n\
          [c](//gone.invalid/x)\n\
          [d](http://gone.invalid#x)\n");
    test "two links on a line are both read"
      (link_fails "the second one is broken" "[a](other.md) and [b](gone.md)\n"
         1 (Book.Missing_target "gone.md"));
    test "a page with no entry in the summary fails" (fun () ->
        Alcotest.check links "the page is missing"
          [
            {
              Book.file = "src/q.md";
              line = None;
              problem = Book.Not_in_summary;
            };
          ]
          (check_links_of ~summary:"- [p](p.md)\n"
             [ ("p.md", ""); ("q.md", "") ]));
    test "a page in a folder needs its entry" (fun () ->
        Alcotest.check links "the page is missing"
          [
            {
              Book.file = "src/guide/q.md";
              line = None;
              problem = Book.Not_in_summary;
            };
          ]
          (check_links_of ~summary:"- [q](q.md)\n"
             [ ("q.md", ""); ("guide/q.md", "") ]));
    test "an entry of the summary with no file fails" (fun () ->
        Alcotest.check links "the entry is broken"
          [ in_page ~file:"src/SUMMARY.md" 2 (Book.Missing_target "gone.md") ]
          (check_links_of ~summary:"- [p](p.md)\n- [g](gone.md)\n"
             [ ("p.md", "") ]));
    test "a draft entry of the summary fails" (fun () ->
        Alcotest.check links "the entry names no file"
          [ in_page ~file:"src/SUMMARY.md" 2 Book.Empty_link ]
          (check_links_of ~summary:"- [p](p.md)\n- [draft]()\n"
             [ ("p.md", "") ]));
    test "a commented entry of the summary does not count" (fun () ->
        Alcotest.check links "the page is missing"
          [
            {
              Book.file = "src/p.md";
              line = None;
              problem = Book.Not_in_summary;
            };
          ]
          (check_links_of ~summary:"<!-- [p](p.md) -->\n" [ ("p.md", "") ]));
    test "a book with no summary fails" (fun () ->
        Fixture.with_temporary_folder (fun book ->
            write_at book "src/p.md" "";
            Alcotest.check links "the summary is missing"
              [
                {
                  Book.file = "src/SUMMARY.md";
                  line = None;
                  problem = Book.No_summary;
                };
              ]
              (Book.check_links book)));
    test "a book with no src fails" (fun () ->
        Fixture.with_temporary_folder (fun book ->
            match Book.check_links book with
            | [ { problem = Book.Unreadable _; _ } ] -> ()
            | _ -> Alcotest.fail "a missing src gave no error"));
    test "pages lists the pages in order, without the summary" (fun () ->
        with_book
          [ ("b.md", ""); ("a/c.md", ""); ("a.md", "") ]
          ~files:[ ("src/x.png", "") ]
          (fun book ->
            Alcotest.(check (result (list string) error))
              "the names"
              (Ok [ "a.md"; "a/c.md"; "b.md" ])
              (Book.pages book)));
  ]

let listing_rules =
  let check name files expected =
    test name (fun () ->
        with_book ~files
          [ ("p.md", ""); ("guide/q.md", ""); ("other/q.md", "") ]
          (fun book ->
            Alcotest.check (Alcotest.list error) name expected
              (Book.check_listings book)))
  in
  [
    check "a listing with a page passes" [ ("listings/p/a", "") ] [];
    check "a book with no listings passes" [] [];
    check "a dot file in listings does not count"
      [ ("listings/.DS_Store", "") ]
      [];
    check "a listing with no page fails"
      [ ("listings/gone/a", "") ]
      [
        {
          Book.file = "listings/gone";
          line = None;
          problem = Book.Listing_without_page;
        };
      ];
    check "a file in listings fails"
      [ ("listings/p.txt", "") ]
      [
        {
          Book.file = "listings/p.txt";
          line = None;
          problem = Book.Listing_without_page;
        };
      ];
    check "a listing with two pages of its stem fails"
      [ ("listings/q/a", "") ]
      [
        {
          Book.file = "listings/q";
          line = None;
          problem = Book.Listing_for_two_pages [ "guide/q.md"; "other/q.md" ];
        };
      ];
  ]

let id_rules =
  let check name text expected =
    test name (fun () ->
        Alcotest.(check (list string)) name expected (Book.heading_ids text))
  in
  [
    check "the ids equal those of mdBook 0.5.4"
      "# Plain Title\n\n\
       ## Plain Title\n\n\
       ## Plain Title\n\n\
       ## The `sinter check` command\n\n\
       ## *Em* and **strong** [link](x.md) text\n\n\
       ## Foo_bar-baz 1.2: why? (yes!)\n\n\
       ## Trailing hashes ##\n\n\
       Setext heading\n\
       ==============\n\n\
       Setext two\n\
       words\n\
       ---\n\n\
       ## With attr {#custom-id}\n\n\
       ## With <b>html</b> &amp; entity \\* escaped\n\n\
       ##   Lots   of   space  \n\n\
       > ## Quoted heading\n\n\
       - ## List heading\n\n\
       ## Plain Title-1\n\n\
       ## \n\n\
       ## ###\n\n\
       ## Use {x}\n\n\
       ## Use {.cls}\n\n\
       ## `_lit_` code\n\n\
       ## _em_ word\n\n\
       ## foo_bar_baz\n\n\
       ## \\_esc\\_\n\n\
       ## ![alt](x.png) image\n\n\
       ## <span>tag</span> kept\n\n\
       ## 1.2.3 Version!\n\n\
       ## A/B & C\n\n\
       ## Tab\tinside\n\n\
       ## UPPER Case\n\n\
       ## ~~strike~~ text\n\n\
       ## a@b.c\n"
      [
        "plain-title";
        "plain-title-1";
        "plain-title-2";
        "the-sinter-check-command";
        "em-and-strong-link-text";
        "foo_bar-baz-12-why-yes";
        "trailing-hashes";
        "setext-heading";
        "setext-two-words";
        "custom-id";
        "with-html--entity--escaped";
        "lots---of---space";
        "quoted-heading";
        "list-heading";
        "plain-title-1-1";
        "";
        "-1";
        "use";
        "use-1";
        "_lit_-code";
        "em-word";
        "foo_bar_baz";
        "_esc_";
        "image";
        "tag-kept";
        "123-version";
        "ab--c";
        "tab-inside";
        "upper-case";
        "strike-text";
        "abc";
      ];
    check "an attribute id does not count as a use"
      "## First {#my-id}\n\n\
       ## My id\n\n\
       ## My id\n\n\
       ## Other\n\n\
       ## Second {#other}\n\n\
       ## Other\n\n\
       ## H {#a b}\n\n\
       ## Ends } brace\n\n\
       ## Open { brace\n\n\
       ## {#only-id}\n"
      [
        "my-id";
        "my-id";
        "my-id-1";
        "other";
        "other";
        "other-1";
        "a";
        "ends--brace";
        "open--brace";
        "only-id";
      ];
    check "an entity counts as its character, as in mdBook 0.5.4"
      "## &#233;t&eacute;\n\n\
       ## A&#65;B\n\n\
       ## a&nbsp;b\n\n\
       ## x &amp; y\n\n\
       ## &#x41;c\n\n\
       ## q&quot;r&apos;s&lt;t&gt;u\n\n\
       ## &#32;sp\n"
      [ "\x80t\x80"; "aab"; "a-b"; "x--y"; "ac"; "qrstu"; "sp" ];
    check "an unknown entity gives an id that no link can name" "## &bogus; z\n"
      [ "\x80-z" ];
    check "a block holds no heading" "```text\n# No\n```\n" [];
    check "a comment holds no heading" "<!--\n# No\n-->\n" [];
    check "seven hashes are no heading" "####### No\n" [];
    check "a hash with no space is no heading" "#No\n" [];
    check "four spaces are no heading" "    # No\n" [];
    check "a dash line after a blank line is no heading" "Text\n\n---\n" [];
    check "a list line above a dash line is no heading" "- Item\n---\n" [];
    check "a page that breaks a rule has no ids" "# Yes\n\n```text\n" [];
  ]

let piece =
  Gen.oneof_list
    [
      "```";
      "````";
      "~~~";
      "console,run";
      "console,planned";
      "console";
      "text,file=a";
      "text,file=../a";
      "$ ";
      "$ true";
      "> [!NOTE]";
      "> Sinter does not have this x yet.";
      "<!--";
      "-->";
      "[a](";
      "](b)";
      "][";
      "`";
      "\\";
      "#";
      "\n";
      "\n";
      "\n\n";
      " ";
      "    ";
      "- ";
      "1. ";
      "text";
      "\xff";
      "\r";
    ]

let page_text =
  Gen.map (String.concat "") (Gen.list_size (Gen.int_bound 24) piece)

let property ?(count = 500) ~name ~print generator check =
  QCheck_alcotest.to_alcotest ~speed_level:`Quick
    (QCheck2.Test.make ~count ~name ~print generator check)

let print = Printf.sprintf "%S"

let properties =
  [
    property ~name:"check_page answers for every text" ~print page_text
      (fun text -> match Book.check_page text with Ok () | Error _ -> true);
    property ~name:"heading_ids answers for every text" ~print page_text
      (fun text ->
        ignore (Book.heading_ids text);
        true);
    property ~name:"check_links answers for every page" ~count:100 ~print
      page_text (fun text ->
        ignore (check_links_of [ ("p.md", text) ]);
        true);
    property ~name:"the ids of a page differ from each other"
      (Gen.list_size (Gen.int_bound 12)
         (Gen.oneof_list [ "a"; "a-1"; "a-1-1"; "A"; "a 1"; "b"; "_"; "" ]))
      ~print:(fun titles -> String.concat "|" titles)
      (fun titles ->
        let text =
          String.concat ""
            (List.map (fun title -> "## " ^ title ^ "\n\n") titles)
        in
        let ids = Book.heading_ids text in
        List.length ids = List.length titles
        && List.length (List.sort_uniq String.compare ids) = List.length ids);
    property ~name:"a promoted page then passes" ~count:20
      ~print:(fun lines -> String.concat "|" lines)
      (Gen.list_size (Gen.int_bound 4)
         (Gen.oneof_list
            [ ""; "a"; " b "; "\xc3\xa9"; "$"; "#"; "```x"; "<!--" ]))
      (fun lines ->
        let body =
          String.concat "" (List.map (fun line -> line ^ "\n") lines)
        in
        let text =
          Printf.sprintf
            "````text,file=out\n%s````\n\n````console,run\n$ cat out\n````\n"
            body
        in
        Fixture.with_temporary_folder (fun source ->
            write_at source "p.md" text;
            with_book
              [ ("p.md", text) ]
              (fun book ->
                ignore
                  (Book.run_page ~binary:sh (Book.Promote_into source) ~book
                     "p.md"));
            run_text (read (Filename.concat source "p.md")) = Ok []));
  ]

let message_rules =
  [
    test "a message names the file and the line" (fun () ->
        Alcotest.(check string)
          "the place comes first" "src/p.md:3: the block has no closing fence."
          (Book.message (located 3 Book.Unclosed_fence)));
    test "a wrong exit shows the output of the command" (fun () ->
        Alcotest.(check string)
          "the output follows"
          "src/p.md:2: \"x\" must exit with 0, and it exited with 1.\n\
          \  output: \"error: no file\\n\""
          (Book.message
             (located 2
                (Book.Wrong_exit
                   {
                     command = "x";
                     expected = 0;
                     actual = 1;
                     output = "error: no file\n";
                   }))));
    test "a change of folder says to give paths from the root" (fun () ->
        Alcotest.(check string)
          "the text names the root"
          "src/p.md:2: the command \"cd docs && ls\" only changes the folder \
           of its own shell, and each command runs in a new shell at the root \
           of the repository. Give each command its paths from the root."
          (Book.message (located 2 (Book.Keeps_shell_state "cd docs && ls"))));
    test "a lone variable says to put it in front of the command" (fun () ->
        Alcotest.(check string)
          "the text names the variables"
          "src/p.md:2: the command \"FOO=1\" only sets variables of its own \
           shell, and each command runs in a new shell. Put the variables in \
           front of the command that needs them."
          (Book.message (located 2 (Book.Keeps_shell_state "FOO=1"))));
    test "a message with no line names the file" (fun () ->
        Alcotest.(check string)
          "only the file" "src/p.md: no link of SUMMARY.md names this page."
          (Book.message
             { file = "src/p.md"; line = None; problem = Book.Not_in_summary }));
    test "a difference says how to accept the output" (fun () ->
        Alcotest.(check string)
          "both texts and the variable"
          "src/p.md:2: the output of \"x\" differs.\n\
          \  expected: \"a\\n\"\n\
          \  actual:   \"b\\n\"\n\
           To accept the output, run the suite with SINTER_PROMOTE=1."
          (Book.message
             (located 2
                (Book.Differs
                   { command = "x"; expected = "a\n"; actual = "b\n" }))));
    test "each problem has its own text" (fun () ->
        let problems =
          [
            Book.Nested_fence;
            Book.Unclosed_fence;
            Book.Unclosed_comment;
            Book.Unknown_label "l";
            Book.Console_without_label;
            Book.Path_outside "p";
            Book.No_command;
            Book.Command_outside_block;
            Book.Keeps_shell_state "c";
            Book.Bad_note;
            Book.Planned_without_note;
            Book.Run_under_note;
            Book.Differs { command = "c"; expected = "a"; actual = "b" };
            Book.Wrong_exit
              { command = "c"; expected = 0; actual = 1; output = "" };
            Book.Cannot_promote { command = "c"; output = "o" };
            Book.Harness (Fixture.System "s");
            Book.Empty_link;
            Book.Rooted_link "r";
            Book.Link_leaves_book "l";
            Book.Missing_target "m";
            Book.Missing_anchor { target = "t"; anchor = "a" };
            Book.Undefined_reference "u";
            Book.Not_in_summary;
            Book.No_summary;
            Book.Listing_without_page;
            Book.Listing_for_two_pages [ "a"; "b" ];
            Book.Unreadable "gone";
          ]
        in
        let texts =
          List.map
            (fun problem -> Book.message { file = "f"; line = None; problem })
            problems
        in
        Alcotest.(check int)
          "no two are alike" (List.length problems)
          (List.length (List.sort_uniq String.compare texts)));
  ]

let tests_rules =
  let names book =
    List.map
      (fun (name, _, _) -> name)
      (Book.tests ~binary:sh Book.Compare ~on_write:ignore book)
  in
  let run_all ?(mode = Book.Compare) ?(on_write = ignore) book =
    List.iter
      (fun (_, _, run) -> run ())
      (Book.tests ~binary:sh mode ~on_write book)
  in
  [
    test "tests gives a test for each page and for the book" (fun () ->
        with_book
          [ ("a.md", ""); ("b/c.md", "") ]
          (fun book ->
            Alcotest.(check (list string))
              "the names"
              [ "links and the summary"; "listings"; "a.md"; "b/c.md" ]
              (names book)));
    test "tests passes a good book" (fun () ->
        with_book [ ("a.md", "```console,run\n$ true\n```\n") ] run_all);
    test "tests fails a page with wrong output" (fun () ->
        with_book
          [ ("a.md", "```console,run\n$ true\nwrong\n```\n") ]
          (fun book ->
            Alcotest.(check bool)
              "the page fails" true
              (try
                 run_all book;
                 false
               with _ -> true)));
    test "tests fails a book with a broken link" (fun () ->
        with_book
          [ ("a.md", "[a](gone.md)\n") ]
          (fun book ->
            Alcotest.(check bool)
              "the link fails" true
              (try
                 run_all book;
                 false
               with _ -> true)));
    test "tests fails a book with a stray listing" (fun () ->
        with_book
          ~files:[ ("listings/gone/a", "") ]
          [ ("a.md", "") ]
          (fun book ->
            Alcotest.(check bool)
              "the listing fails" true
              (try
                 run_all book;
                 false
               with _ -> true)));
    test "tests gives one failing test when src is missing" (fun () ->
        Fixture.with_temporary_folder (fun book ->
            match Book.tests ~binary:sh Book.Compare ~on_write:ignore book with
            | [ (_, _, run) ] ->
                Alcotest.(check bool)
                  "the test fails" true
                  (try
                     run ();
                     false
                   with _ -> true)
            | _ -> Alcotest.fail "the list does not hold one test"));
    test "tests calls on_write with each path it wrote" (fun () ->
        with_book
          [ ("a.md", "```console,run\n$ echo new\n```\n") ]
          (fun book ->
            Fixture.with_temporary_folder (fun source ->
                write_at source "a.md" "";
                let written = ref [] in
                run_all ~mode:(Book.Promote_into source)
                  ~on_write:(fun path -> written := path :: !written)
                  book;
                Alcotest.(check (list string))
                  "the path"
                  [ Filename.concat source "a.md" ]
                  !written)));
  ]

let tests =
  run_rules @ shell_state_rules @ labels @ files @ planned_rules
  @ structure_rules @ repository_rules @ promote_rules @ link_rules
  @ listing_rules @ id_rules @ message_rules @ tests_rules @ properties
