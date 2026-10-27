(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The repository that the tests of {!Sinter_core.Git} share. *)

val quoted_name : string
(** The name of a file of the shared repository that git quotes in its diff
    output: it holds a byte above 0x7F, a tab, and a space. *)

val shared : unit -> Git_fixture.t
(** [shared ()] is one repository for every test that only reads a repository.
    The first call makes it; later calls give the same one. A test must not
    change it; a test that changes a repository works on a {!Git_fixture.copy}.

    The history:

    + commit 1, on [refs/heads/main], with no parent: the files of commit 1
      below
    + commit 2, on [refs/heads/main], from commit 1: adds the files of commit 2
      below
    + commit 3, on [refs/remotes/origin/main], from commit 1: adds [origin.txt]
    + commit 4, on [refs/heads/lonely], with no parent: holds only [lonely.txt]

    The branches [loc], [both], [gone], and [deep/branch] point at commit 2. The
    remote branches [origin/orig] and [origin/both] point at commit 3. The
    upstream of [main] is [origin/main]. The upstream of [loc] is the local
    branch [both]. The upstream of [gone] is [origin/missing], which does not
    exist. [HEAD] is [main], commit 2.

    Commit 1 holds:

    - [.gitignore], which ignores [*.log] and [build/]
    - [README.md], ["hello\n"]
    - [src/main.ml]
    - [tracked.log], which [.gitignore] matches
    - [gone.txt]
    - [bytes.bin], which holds NUL bytes
    - [run.sh], with the mode [100755]
    - [link] and [link-as-file], symbolic links to [README.md]
    - [sub] and [sub-as-file], submodules at a commit that the repository does
      not hold

    Commit 2 adds [mod.txt] (the lines 1 to 10), [head.txt] and [tail.txt] (the
    lines a, b, c), [bin.dat], which holds NUL bytes, [mode.sh], [removed.txt],
    [old-name.txt], [unstaged.txt], [typed.txt], and the file {!quoted_name}.

    The working tree is commit 2 with these changes: [gone.txt] is removed;
    [link-as-file] and [sub-as-file] are regular files; [untracked.txt] is new;
    [ignored.log] and [build/out.o] are new and ignored; [untracked-link] is a
    new symbolic link; and [nested/] holds a repository of its own, whose [HEAD]
    is the commit of the submodules, with the file [nested/inner.txt].

    For the diff, the working tree also changes these files of commit 2:
    [mod.txt] changes the line 3, loses the lines 6 and 7, and gains a line
    after the line 9; [head.txt] loses its first two lines; [tail.txt] loses its
    last two lines; [bin.dat] and {!quoted_name} change; [mode.sh] gets the mode
    [100755]; [removed.txt] is removed from the disk and the index;
    [old-name.txt] is renamed to [new-name.txt] in both; [unstaged.txt] is
    removed from the index only; and [typed.txt] is a symbolic link. [added.txt]
    is new, and the index holds it. *)
