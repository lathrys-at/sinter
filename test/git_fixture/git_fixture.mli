(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Git repositories for the tests of {!Sinter_core.Git} and for the benchmark.

    A repository of {!init} lives in a new directory under the temporary
    directory, and the process removes that directory when it exits. A
    repository of {!init_in} lives in a directory that the caller gives and
    owns. Every git child gets the environment {!env}, which reads no git
    configuration of the machine. A function that runs git raises [Failure] with
    git's standard error when git does not exit with the status 0. *)

type t
(** A repository with a working tree. *)

val temp_dir : unit -> string
(** [temp_dir ()] makes a new empty directory under the temporary directory,
    with a name from [Filename.temp_dir]. The process removes it when it exits.
*)

val init : ?object_format:string -> unit -> t
(** [init ()] makes a new repository with no commit and no index, on the branch
    [main]. [object_format] is ["sha1"], the default, or ["sha256"]. *)

val init_in : ?object_format:string -> string -> t
(** [init_in dir] is {!init} in the directory [dir] and not in a new temporary
    directory. [dir] must exist and hold no entry named [repo] or [home]. The
    working tree is [dir/repo], and {!env} names [dir/home] as [HOME] and [dir]
    as [GIT_CEILING_DIRECTORIES]. The process does not remove [dir].

    @raise Invalid_argument
      if [dir] is not a directory, or if it holds an entry named [repo] or
      [home]. *)

val root : t -> string
(** [root repo] is the absolute path of the working tree, with no symbolic link
    in it, as git prints it. *)

val env : t -> string array
(** [env repo] is the environment of every git child that runs in [repo]. It is
    the environment of the process without each variable whose name starts with
    [GIT_], without [HOME], and without [XDG_CONFIG_HOME], with:

    - [PATH] with the directory of the programs of git in front
    - [GIT_CEILING_DIRECTORIES], the directory that holds the working tree: git
      looks for a repository in no directory above it
    - [GIT_CONFIG_GLOBAL=/dev/null] and [GIT_CONFIG_NOSYSTEM=1]
    - [HOME], a directory beside the working tree
    - fixed names, e-mail addresses, and dates of the author and the committer
    - the settings [init.defaultBranch=main]; [fastimport.unpackLimit=0]:
      [git fast-import] keeps its objects in one pack; and
      [core.logAllRefUpdates=false]: git keeps no log of references. *)

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

val git_dir_state : t -> string list
(** [git_dir_state repo] describes each directory and each file under [.git] of
    [repo], in the byte order of their paths. A file has its inode, its size,
    and the digest of its content, and, outside [.git/objects], its modification
    time. Two equal states mean that no file under [.git] was made, removed, or
    written, and that no time outside [.git/objects] changed. *)

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
(** [break repo] removes the [.git] directory of [repo]. Each git command in the
    working tree then fails with the exit status 128. Break only a {!copy}. *)
