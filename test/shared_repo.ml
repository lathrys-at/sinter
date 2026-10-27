(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

open Git_fixture

let submodule_commit = String.make 40 'c'

let first_files =
  [
    File (".gitignore", "*.log\nbuild/\n");
    File ("README.md", "hello\n");
    File ("src/main.ml", "let () = ()\n");
    File ("tracked.log", "kept although ignored\n");
    File ("gone.txt", "deleted on disk\n");
    File ("bytes.bin", "\000\001\n\255");
    Executable ("run.sh", "#!/bin/sh\n");
    Link ("link", "README.md");
    Link ("link-as-file", "README.md");
    Submodule ("sub", submodule_commit);
    Submodule ("sub-as-file", submodule_commit);
  ]

let quoted_name = "caf\xc3\xa9\tdoc one.txt"

let second_changes =
  [
    File ("mod.txt", "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n");
    File ("head.txt", "a\nb\nc\n");
    File ("tail.txt", "a\nb\nc\n");
    File ("bin.dat", "\000binary\000\n");
    File ("mode.sh", "#!/bin/sh\n");
    File ("removed.txt", "removed from the index\n");
    File ("old-name.txt", "renamed\n");
    File ("unstaged.txt", "removed from the index, kept on disk\n");
    File ("typed.txt", "becomes a link\n");
    File (quoted_name, "before\n");
  ]

let origin_changes = [ File ("origin.txt", "origin\n") ]
let lonely_files = [ File ("lonely.txt", "lonely\n") ]

let shared_config =
  "[remote \"origin\"]\n\
   \turl = /dev/null\n\
   \tfetch = +refs/heads/*:refs/remotes/origin/*\n\
   [branch \"main\"]\n\
   \tremote = origin\n\
   \tmerge = refs/heads/main\n\
   [branch \"loc\"]\n\
   \tremote = .\n\
   \tmerge = refs/heads/both\n\
   [branch \"gone\"]\n\
   \tremote = origin\n\
   \tmerge = refs/heads/missing\n"

let change_working_tree repo =
  remove repo "gone.txt";
  remove repo "link-as-file";
  write repo "link-as-file" "README.md";
  remove repo "sub-as-file";
  write repo "sub-as-file" "a file\n";
  write repo "untracked.txt" "new\n";
  write repo "ignored.log" "ignored\n";
  write repo "build/out.o" "ignored\n";
  symlink repo ~target:"README.md" "untracked-link";
  write repo "nested/.git/HEAD" (submodule_commit ^ "\n");
  write repo "nested/.git/objects/.keep" "";
  write repo "nested/.git/refs/.keep" "";
  write repo "nested/inner.txt" "inner\n";
  write repo "mod.txt" "1\n2\nthree\n4\n5\n8\n9\nnine and a half\n10\n";
  write repo "head.txt" "c\n";
  write repo "tail.txt" "a\n";
  write repo "bin.dat" "\000binary, changed\000\n";
  make_executable repo "mode.sh";
  remove repo "removed.txt";
  remove repo "old-name.txt";
  write repo "new-name.txt" "renamed\n";
  write repo "added.txt" "added\n";
  remove repo "typed.txt";
  symlink repo ~target:"README.md" "typed.txt";
  write repo quoted_name "after\n";
  ignore
    (git repo
       [
         "update-index";
         "--add";
         "--remove";
         "added.txt";
         "new-name.txt";
         "old-name.txt";
         "removed.txt";
         "--force-remove";
         "unstaged.txt";
       ])

let shared_repo =
  lazy
    (let repo = init () in
     import repo
       [
         commit ~ref:"refs/heads/main" ~mark:1 ~message:"first" first_files;
         commit ~parents:[ 1 ] ~ref:"refs/heads/main" ~mark:2 ~message:"second"
           second_changes;
         commit ~parents:[ 1 ] ~ref:"refs/remotes/origin/main" ~mark:3
           ~message:"origin" origin_changes;
         commit ~ref:"refs/heads/lonely" ~mark:4 ~message:"lonely" lonely_files;
         reset ~ref:"refs/heads/loc" ~mark:2;
         reset ~ref:"refs/remotes/origin/orig" ~mark:3;
         reset ~ref:"refs/heads/both" ~mark:2;
         reset ~ref:"refs/remotes/origin/both" ~mark:3;
         reset ~ref:"refs/heads/gone" ~mark:2;
         reset ~ref:"refs/heads/deep/branch" ~mark:2;
       ];
     append_config repo shared_config;
     checkout repo;
     change_working_tree repo;
     repo)

let shared () = Lazy.force shared_repo
