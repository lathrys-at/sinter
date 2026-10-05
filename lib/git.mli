(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Read a git repository: the files of the working tree and of a commit, the
    target branch, the merge base, the diff, and the tree key. The functions run
    the [git] executable as a child process. They need git 2.30 or later.

    A path is relative to the root of the working tree, with [/] between its
    parts, as git prints it with the option [-z]. A path is a string of bytes,
    and it need not be valid UTF-8. An object id is the name of a git object in
    lowercase hexadecimal digits: 40 digits in a SHA-1 repository, 64 digits in
    a SHA-256 repository. *)

(** {1 Errors}

    Every function that runs git can give four errors that its own comment does
    not name again: [Git_not_found] when the child does not start, for example
    when an argument is longer than the system allows; [Command_failed];
    [Malformed_output]; and [File_error] when a temporary file does not open,
    read, or write. *)

type error =
  | Git_not_found of string
      (** the [git] executable did not start. The string says why. *)
  | Not_a_repository of { dir : string; detail : string }
      (** the directory [dir] is not in the working tree of a git repository.
          [detail] is the first part of what git wrote to its standard error. *)
  | Bad_revision of string
      (** the string names no commit, or no object of the kind that the function
          reads *)
  | Target_not_found of string
      (** no branch of the string's name gives a commit *)
  | No_merge_base of string * string
      (** the two revisions have no common ancestor *)
  | Command_failed of {
      args : string list;
      status : Unix.process_status;
      stderr : string;
    }
      (** git ran with the arguments [args] and did not exit with the status 0.
          [args] are the arguments after the program name. [stderr] is the first
          part of what git wrote to its standard error. *)
  | Malformed_output of { args : string list; detail : string }
      (** git ran with the arguments [args], and its output was not in the form
          that the function reads. [detail] says what did not decode. *)
  | File_error of string
      (** a file did not open, read, or write: a temporary file of this module,
          the index of the repository, or a path of the working tree. The string
          names the file and the failure. *)

(** {1 Repositories} *)

type t
(** A git repository with a working tree. The value holds the root of the
    working tree, the environment of the child processes, and the object format
    of the repository. It holds no open resource. *)

(** The hash function that names the objects of a repository. *)
type object_format = Sha1 | Sha256

val open_repo : env:string array -> string -> (t, error) result
(** [open_repo ~env dir] is the repository whose working tree holds the
    directory [dir]. A relative [dir] names a directory under the current
    directory of the process. [env] is the environment for each git child
    process, in the form of [Unix.environment ()].

    The function finds the [git] executable through the variable [PATH] of
    [env], and through no other place. It takes the first directory of [PATH]
    that holds an executable regular file named [git]. It skips an empty entry
    of [PATH], so it never looks in the current directory.

    Every git child process gets [env] with these changes:

    - [GIT_DIR], [GIT_WORK_TREE], [GIT_INDEX_FILE], [GIT_DIFF_OPTS], and
      [GIT_EXTERNAL_DIFF] are removed
    - [GIT_OPTIONAL_LOCKS] is [0], so that a read does not write the index
    - [GIT_TERMINAL_PROMPT] is [0], so that git asks no question

    Each child runs in the root of the working tree.

    The error is [Git_not_found] when [env] holds no [PATH], or when no
    directory of [PATH] holds an executable file named [git]. It is
    [Not_a_repository] when [dir] is empty, when it holds a NUL byte, when it is
    not a directory, or when git finds no working tree that holds it. *)

val root : t -> string
(** [root repo] is the absolute path of the root of the working tree, as git
    gives it. *)

val object_format : t -> object_format
(** [object_format repo] is the object format of [repo]. *)

(** {1 Files} *)

val files : t -> (string list, error) result
(** [files repo] is the set of files of the working tree, as it is on disk. A
    path is in the set when git tracks it, or when git does not track it and
    does not ignore it, and when [lstat] shows a regular file at the path. A
    tracked file stays in the set when [.gitignore] matches it.

    The set leaves out:

    - a path with nothing on disk, such as a tracked file that was deleted
    - a path that is a symbolic link, a directory, or another file that is not
      regular
    - a path whose index entry records a submodule or a symbolic link, also when
      a regular file is now on disk at that path. [git add -A], and so
      {!tree_key}, records that file as a regular file.
    - each file under a directory that git does not track and that holds a
      repository of its own

    The paths are sorted by byte order, with no path twice. A path with a
    conflict, which has up to three entries in the index, comes once. The result
    can change on each call while other processes change the working tree.

    The error is [File_error] when [lstat] of a path fails for a reason other
    than that nothing is at the path, for example when a directory on the way to
    the path is not readable. *)

val base_tree : t -> string -> ((string * string) list, error) result
(** [base_tree repo rev] is the set of files of the commit that the revision
    [rev] names. Each pair is a path and the object id of its content. The set
    leaves out submodules and symbolic links. The pairs are sorted by path, in
    byte order, with no path twice.

    The error is [Bad_revision rev] when [rev] names no commit, when [rev] is
    empty, when it starts with [-], or when it holds a NUL byte. Git never sees
    such a name. *)

val fold_blobs :
  t ->
  string list ->
  init:'a ->
  f:('a -> string -> string -> 'a) ->
  ('a, error) result
(** [fold_blobs repo ids ~init ~f] reads the content of each object of [ids], in
    order, with one git process for all of them. It calls [f acc id content] for
    each, and gives the last value of [acc].

    The error is [Bad_revision id] for the first id of [ids] that is not an
    object id of [repo]'s object format, or that names no blob. [f] sees no
    content when an id is not an object id of that format. When an id names no
    blob, [f] has seen each id in front of it. An exception that [f] raises
    passes through, after the git process ends. *)

(** {1 Target branch and merge base} *)

(** The rule that found the target branch. *)
type source =
  | Upstream  (** the branch that the local branch of the name tracks *)
  | Local_branch  (** the local branch of the name *)
  | Origin_branch  (** the branch of the name on the remote [origin] *)

type target = {
  source : source;
  refname : string;
      (** the full name of the ref that gave the commit, for example
          ["refs/remotes/origin/main"] *)
  commit : string;  (** the object id of the commit *)
}
(** The target branch, and the commit at its tip. *)

val resolve_target : t -> string -> (target, error) result
(** [resolve_target repo name] is the target branch of the name [name], for
    example ["main"]. The function looks at three refs, in order, and takes the
    first that points at a commit:

    + the upstream of the local branch [refs/heads/<name>], which
      [<name>@{upstream}] names: the ref that the configuration of the branch
      says the branch tracks
    + the local branch [refs/heads/<name>]
    + the branch [refs/remotes/origin/<name>] of the remote [origin]

    The function takes [name] as it is: revision syntax such as [~1], and glob
    characters such as [*], have no meaning in it. A ref that points at an
    object other than a commit, such as an annotated tag, does not count.

    The error is [Target_not_found name] when none of the three refs points at a
    commit, and when [name] holds a NUL byte. *)

val merge_base : t -> string -> string -> (string, error) result
(** [merge_base repo a b] is the object id of the merge base of the commits that
    the revisions [a] and [b] name: a common ancestor of the two commits that is
    not an ancestor of another common ancestor. When more than one commit is a
    merge base, the result is the one that [git merge-base] gives.

    The error is [Bad_revision] with the first of [a] and [b] that names no
    commit, that is empty, that starts with [-], or that holds a NUL byte. It is
    [No_merge_base (a, b)] when the two commits have no common ancestor. *)

(** {1 Diff} *)

type hunk = {
  line : int;  (** the first line of the change in the working tree, from 1 *)
  eline : int;  (** the last line of the change in the working tree *)
  added : int;  (** the number of lines of the run in the working tree *)
  removed : int;  (** the number of lines of the base that the run replaces *)
}
(** One run of changed lines, in the coordinates of the working tree. A run with
    lines added spans them: [eline] is [line + added - 1]. A pure deletion has
    [added = 0] and [line = eline =] the line after the deleted lines. A
    deletion at the end of a file has [line = eline =] the number of lines of
    the file plus 1, a line that the file does not hold. *)

(** How one path differs between the base and the working tree. *)
type change =
  | Added  (** the base does not hold the path, or git does not track it *)
  | Deleted  (** the working tree does not hold the path *)
  | Modified of hunk list
      (** both hold the path, and the content or the mode differs. The hunks are
          in the order of their lines. A change of the mode alone gives no hunk.
      *)
  | Binary  (** both hold the path, and git found the content to be binary *)

val diff : t -> base:string -> ((string * change) list, error) result
(** [diff repo ~base] is the change of each path that differs between the commit
    that the revision [base] names and the working tree as it is on disk. The
    two sets of files are {!base_tree} of [base] and {!files} of [repo]; a path
    that is in neither set is not in the result. The rules, in order:

    + A path that only the base holds is [Deleted].
    + A path that only the working tree holds is [Added].
    + A path that git does not track is [Added], also when the base holds it.
    + A path that both hold and that git tracks is [Binary] or [Modified] with
      the hunks of [git diff], or is not in the result when its content and its
      mode are the same.

    So a file that git does not track, or a new binary file, is [Added], and a
    rename is a deletion and an addition. The pairs are sorted by path, in byte
    order, with no path twice. The hunks do not depend on the git configuration
    of the repository or of the user.

    The error is [Bad_revision base] when [base] names no commit, is empty,
    starts with [-], or holds a NUL byte. *)

(** {1 Tree key} *)

val tree_key : t -> (string, error) result
(** [tree_key repo] is the object id of the tree that git would write for the
    working tree as it is on disk. That tree holds each file of the index that
    is still on disk, and each file that git does not track and does not ignore,
    as [git add -A] adds them.

    The function does not change the index of [repo]. It works on a copy of the
    index, in a temporary file that it removes before it returns. It writes the
    objects of the tree and of new content into the object store of [repo].

    The error is [Command_failed] when [git add -A] fails, and its [stderr]
    holds the message of git. Two causes are a file that git cannot read, and a
    directory that git does not track and that holds a repository of its own
    with no commit. The error is [File_error] when the index of [repo] does not
    read. *)

(** {1 Decoders}

    The functions below decode the output of git commands. Each takes the whole
    output of one command, and none runs a process. The error string says what
    did not decode. *)

module Decode : sig
  (** The type of a git object. *)
  type kind = Blob | Tree | Commit | Tag

  val is_object_id : string -> bool
  (** [is_object_id s] is [true] when [s] is 40 or 64 lowercase hexadecimal
      digits. *)

  val nul_list : string -> (string list, string) result
  (** [nul_list output] is the list of the records of [output], in order. Each
      record ends with a NUL byte, and the result holds the records without it.
      The error is for an [output] that does not end with a NUL byte. The empty
      string gives the empty list. *)

  val line : string -> (string, string) result
  (** [line output] is [output] without its last byte, which must be a line
      feed. The error is for an empty [output] and for an [output] that does not
      end with a line feed. *)

  val object_id : string -> (string, string) result
  (** [object_id output] is the object id on the one line of [output]. *)

  val repository : string -> (object_format * string, string) result
  (** [repository output] decodes the output of
      [git rev-parse --show-object-format --show-toplevel]: the object format on
      the first line, then the absolute path of the root of the working tree on
      the rest. The path can hold a line feed. *)

  type stage_entry = { mode : int; id : string; stage : int; path : string }
  (** One entry of the index, as [git ls-files -s -z] prints it. [mode] is the
      octal mode, for example [0o100644]. [stage] is 0 for a path with no
      conflict, and 1, 2, or 3 for one side of a conflict. *)

  val ls_files_stage : string -> (stage_entry list, string) result
  (** [ls_files_stage output] decodes the output of [git ls-files -s -z]: one
      record [<mode> <id> <stage>\t<path>] for each entry. *)

  type tree_entry = { mode : int; kind : kind; id : string; path : string }
  (** One entry of a tree, as [git ls-tree -z] prints it. *)

  val ls_tree : string -> (tree_entry list, string) result
  (** [ls_tree output] decodes the output of [git ls-tree -z]: one record
      [<mode> <kind> <id>\t<path>] for each entry. *)

  (** The header that [git cat-file --batch] prints for each object it reads. *)
  type batch_header =
    | Object of { id : string; kind : kind; size : int }
        (** the object [id] of type [kind] has [size] bytes, which follow the
            header, with one line feed after them *)
    | Missing of string
        (** the name names no object, or more than one object *)

  val batch_header : string -> (batch_header, string) result
  (** [batch_header line] decodes one header line, without its line feed:
      [<id> <kind> <size>], [<name> missing], or [<name> ambiguous]. *)

  (** {2 Refs} *)

  type ref_entry = {
    refname : string;  (** the full name of the ref *)
    kind : kind;  (** the type of the object that the ref points at *)
    id : string;  (** the object id of that object *)
    upstream : string;
        (** the full name of the ref that the branch tracks, or [""] when the
            ref is no branch with an upstream *)
  }
  (** One ref, as [git for-each-ref] prints it with the format
      [%(refname)%00%(objecttype)%00%(objectname)%00%(upstream)]. *)

  val refs : string -> (ref_entry list, string) result
  (** [refs output] decodes the output of [git for-each-ref] with that format:
      one line for each ref. The empty string gives the empty list. *)

  (** {2 Diff output} *)

  type header = {
    old_start : int;
    old_count : int;
    new_start : int;
    new_count : int;
  }
  (** The numbers of a hunk header
      [@@ -<old_start>,<old_count> +<new_start>,<new_count> @@]. A side with a
      count of 0 starts at the line in front of the change. *)

  val hunk_header : string -> (header, string) result
  (** [hunk_header line] decodes one hunk header line, without its line feed. A
      count that the line leaves out is 1. Text after the closing [@@] and a
      space does not count. The error is for a line of another form, for a
      number of more than 15 digits, and for a side that has lines and starts at
      line 0. *)

  val diff : string -> ((string * change) list, string) result
  (** [diff output] decodes the output of [git diff] with the options
      [--no-renames], [--src-prefix=a/], and [--dst-prefix=b/]. Each value is
      [Binary] for a path whose section says that the files are binary, and
      [Modified] with the runs of changed lines of the path's hunks otherwise. A
      context line in a hunk ends a run. Git writes two sections for a file
      whose type changed; such a path comes once, with the hunks of both
      sections, and is [Binary] when either section is. A quoted path is
      unquoted. The pairs are sorted by path, in byte order, with no path twice.
  *)
end
