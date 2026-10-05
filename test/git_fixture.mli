(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Temporary git repositories for the tests of {!Sinter_core.Git}.

    Every repository lives in a new directory under the temporary directory, and
    the process removes that directory when it exits. Every git child gets the
    environment {!env}, so that no test depends on the git configuration of the
    machine. A function that runs git raises [Failure] with git's standard error
    when git does not exit with the status 0. *)

type t
(** A repository with a working tree. *)

val temp_dir : unit -> string
(** [temp_dir ()] makes a new empty directory under the temporary directory,
    with a name from [Filename.temp_dir]. The process removes it when it exits.
*)

val init : ?object_format:string -> unit -> t
(** [init ()] makes a new repository with no commit and no index, on the branch
    [main]. [object_format] is ["sha1"], the default, or ["sha256"]. *)

val root : t -> string
(** [root repo] is the absolute path of the working tree, with no symbolic link
    in it, as git prints it. *)

val env : t -> string array
(** [env repo] is the environment of every git child of the tests of [repo]. It
    is the environment of the test process without each variable whose name
    starts with [GIT_], without [HOME], and without [XDG_CONFIG_HOME], with:

    - [GIT_CONFIG_GLOBAL=/dev/null] and [GIT_CONFIG_NOSYSTEM=1]
    - [HOME], a directory beside the working tree
    - fixed names, e-mail addresses, and dates of the author and the committer
    - the setting [init.defaultBranch=main] *)

val git : t -> string list -> string
(** [git repo args] runs git with [args] in the root of [repo], and gives its
    standard output. *)

val git_input : t -> string list -> string -> string
(** [git_input repo args input] is {!git} with [input] on the standard input of
    git. *)

val git_status : t -> string list -> int
(** [git_status repo args] runs git with [args] in the root of [repo], and gives
    its exit status. It does not raise when the status is not 0. *)

(** {1 The working tree} *)

val write : t -> string -> string -> unit
(** [write repo path content] writes [content] to the file at [path] under the
    root, and makes the directories in front of it. *)

val make_executable : t -> string -> unit
(** [make_executable repo path] gives the file at [path] under the root the mode
    [0o755]. *)

val symlink : t -> target:string -> string -> unit
(** [symlink repo ~target path] makes a symbolic link at [path] under the root
    that points to [target]. *)

val remove : t -> string -> unit
(** [remove repo path] removes the file, link, or directory tree at [path] under
    the root. *)

val append_config : t -> string -> unit
(** [append_config repo text] appends [text] to the file [.git/config] of
    [repo]. *)

val copy : t -> t
(** [copy repo] is a copy of the whole folder of [repo], [.git] included, in a
    new temporary directory. *)

val index_state : t -> string
(** [index_state repo] describes the file [.git/index] of [repo]: its inode,
    size, modification time, and the digest of its content, or ["absent"]. Two
    equal states mean that the file did not change. *)

(** {1 History}

    A history is a [git fast-import] stream, made from the commands below. One
    process writes every commit and every reference of the stream. *)

(** One change of a commit. *)
type change =
  | File of string * string  (** a regular file: the path and the content *)
  | Executable of string * string
      (** an executable file: the path and the content *)
  | Link of string * string
      (** a symbolic link: the path and the target of the link *)
  | Submodule of string * string
      (** a submodule: the path and the object id of its commit *)
  | Delete of string  (** the path is removed *)

val commit :
  ?parents:int list ->
  ref:string ->
  mark:int ->
  message:string ->
  change list ->
  string
(** [commit ~ref ~mark ~message changes] is a command that makes a commit on the
    reference [ref], for example ["refs/heads/main"]. [mark] is a number for the
    commit, by which a later command names it. The first of [parents] is the
    commit that the new one starts from; the rest are merged. With no parents,
    the commit starts from the tip of [ref], or is a root commit when [ref] has
    no commit yet in the stream. The changes start from the tree of the first
    parent. Author and committer dates are fixed. *)

val reset : ref:string -> mark:int -> string
(** [reset ~ref ~mark] is a command that points [ref] at the commit [mark]. *)

val import : t -> string list -> unit
(** [import repo commands] runs [git fast-import] with the commands in order. It
    does not change the index or the working tree. *)

val checkout : t -> unit
(** [checkout repo] makes the index and the working tree equal to the commit of
    [HEAD]. *)

(** {1 Fake executables} *)

val fake_git : string -> string array * string
(** [fake_git script] is an environment and the path of a file that holds the
    shell script [script]. The [PATH] of the environment holds one directory,
    and its [git] is a symbolic link to [/bin/sh]. A test gives the path of the
    script to [Git.open_repo] as the directory. The library then starts
    [git -C <path> <args>]: the shell reads [-C] as its option [noclobber] and
    [<path>] as the script to run, with [<args>] as the arguments of the script.
    The script reads its own path in [$0]. When it prints that path as the root
    of the working tree, each later call of the library on the repository runs
    the script again. *)

val break : t -> unit
(** [break repo] removes the [.git] directory of [repo], so that each git
    command in the working tree fails with the exit status 128. Break only a
    {!copy}. *)

(** {1 The shared repository} *)

val quoted_name : string
(** The name of a file of the shared repository that git quotes in its diff
    output: it holds a byte above 0x7F, a tab, and a space. *)

val shared : unit -> t
(** [shared ()] is one repository for every test that only reads a repository.
    The first call makes it; later calls give the same one. A test must not
    change it; a test that changes a repository works on a {!copy}.

    The history:

    + commit 1, on [refs/heads/main], with no parent: the files of commit 1
      below
    + commit 2, on [refs/heads/main], from commit 1: adds the files of commit 2
      below
    + commit 3, on [refs/remotes/origin/main], from commit 1: adds [origin.txt]
    + commit 4, on [refs/heads/lonely], with no parent: holds only [lonely.txt]

    The branches [loc], [both], and [gone] point at commit 2. The remote
    branches [origin/orig] and [origin/both] point at commit 3. The upstream of
    [main] is [origin/main]. The upstream of [gone] is [origin/missing], which
    does not exist. [HEAD] is [main], commit 2.

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
