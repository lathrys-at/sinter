(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The fixture harness. It runs a case folder and compares the output of the
    run, byte for byte, with the expected files of the case.

    A case folder holds these entries, and no other:

    - [args]: a file. Each line is one argument of the run, with no shell.
    - [tree/]: a folder, the files of the working tree.
    - [base/]: a folder, optional. When it exists, the case is a diff case: the
      run starts in a git repository whose one commit holds [base/] and whose
      working tree holds [tree/].
    - [stdin]: a file, optional, the bytes on standard input. Without it,
      standard input is empty.
    - [expected/stdout], [expected/stderr], [expected/exit]: files. [exit] holds
      the exit code in decimal and one line feed.
    - [ledger.jsonl] and [evidence/]: reserved names. A case that holds one of
      them fails. *)

(** {1 Errors} *)

type difference = {
  file : string;
      (** The name of the expected file: [stdout], [stderr], or [exit]. *)
  line : int;  (** The number of the first line that differs, from 1. *)
  expected : string option;
      (** That line in the expected file, with its line feed; [None] when the
          file has fewer lines. *)
  actual : string option;
      (** That line in the output of the run, with its line feed; [None] when
          the output has fewer lines. *)
}
(** The first difference between an expected file and the output of a run. *)

type error =
  | Not_a_folder  (** The case is not a folder. *)
  | Unknown_entry of string
      (** The case holds an entry that the harness does not know, named by its
          path in the case. *)
  | Missing_entry of string
      (** A required entry is missing, named by its path in the case. *)
  | Wrong_kind of { entry : string; folder : bool }
      (** The entry is a file where a folder belongs ([folder] is [true]), or a
          folder where a file belongs. *)
  | Reserved_entry of string
      (** The case holds [ledger.jsonl] or [evidence], which the harness does
          not read yet. *)
  | Did_not_end of float
      (** The run was still going after this many seconds, and was killed. *)
  | Ended_by_signal of int
      (** A signal ended the run. The number is OCaml's number of the signal. *)
  | Git_failed of { arguments : string list; output : string }
      (** A git command failed. [output] is what it wrote to standard output and
          standard error. *)
  | System of string
      (** An operation of the file system or of a process failed. *)
  | Differs of difference list
      (** The output differs from the expected files: one item for each file
          that differs, in the order [stdout], [stderr], [exit]. *)

val message : case:string -> error -> string
(** [message ~case error] is the text that a failed test shows for the case
    named [case]. It names the case, and for [Differs], each file and its first
    line that differs, from both texts. *)

(** {1 Runs} *)

type mode =
  | Compare
      (** Compare the output with the expected files. A difference is an error.
      *)
  | Promote_into of string
      (** [Promote_into folder]: write the output of the case named [name] into
          [folder/name/expected/], where it differs from the file there or the
          file is missing. A missing expected file is then no error. *)

val mode_of_environment :
  promote:string option -> source_root:string option -> (mode, string) result
(** [mode_of_environment ~promote ~source_root] reads the values of the
    variables [SINTER_PROMOTE] and [DUNE_SOURCEROOT]. It is
    [Promote_into (source_root ^ "/test/cases")] when [promote] is [Some "1"],
    and [Compare] for any other value of [promote]. It is [Error] with a message
    when [promote] is [Some "1"] and [source_root] is [None]. *)

val run :
  ?bound:float -> binary:string -> mode -> string -> (string list, error) result
(** [run ~binary mode case] runs the case folder [case] once and compares or
    promotes its output, as [mode] says. [binary] is the absolute path of the
    executable that the run starts, with the arguments of [args].

    The run copies [tree/] into a new folder under the temporary folder of
    [Filename.get_temp_dir_name], and starts [binary] in that copy. The copy
    leaves out every file named [.gitkeep]. The output of the run holds the real
    path of the copy as [<root>]. The run is killed after [bound] seconds; the
    default is 10.

    The result is the list of the files that a promotion wrote, by their paths;
    it is empty in the mode [Compare]. The run removes every file it made under
    the temporary folder before it returns. It writes into no folder but the
    temporary folder, except the expected files that a promotion writes.

    The run changes the working folder of the process while it starts a process,
    and changes it back. No other thread or domain may run meanwhile. *)

val tests :
  binary:string ->
  mode ->
  on_write:(string -> unit) ->
  string ->
  unit Alcotest.test_case list
(** [tests ~binary mode ~on_write folder] is one test for each entry of
    [folder], named after the entry, in the order of the names. Each test calls
    {!run} on its entry and fails with {!message} on an error. It calls
    [on_write] with each file that a promotion wrote. When [folder] cannot be
    read, the list holds one test that fails. *)

val with_temporary_folder : (string -> 'a) -> 'a
(** [with_temporary_folder f] calls [f] with the real path of a new, empty
    folder under the temporary folder of [Filename.get_temp_dir_name], and
    removes the folder and everything in it when [f] returns or raises. An
    exception that [f] raises passes through. [Sys_error] or [Unix.Unix_error]
    passes through when the folder cannot be made or removed. *)

(** {1 Diff cases} *)

type repository
(** A temporary git repository, as a diff case builds it. It is valid only
    inside the function that {!with_repository} calls. *)

val with_repository :
  base:string -> tree:string -> (repository -> 'a) -> ('a, error) result
(** [with_repository ~base ~tree f] builds a repository under the temporary
    folder and calls [f] with it. The repository is on the branch [main]. Its
    one commit holds the files of the folder [base], and its working tree holds
    the files of the folder [tree], uncommitted: a file only in [base] is
    deleted, and a file only in [tree] is untracked. Every git command runs with
    a fixed configuration, home folder, author, committer, and date, so the
    commit has the same id on every machine. The repository is removed when [f]
    returns or raises. The rule of {!run} on the working folder of the process
    holds here too.

    An exception that [f] raises passes through. [Sys_error] passes through when
    the temporary folder cannot be made or removed. *)

val root : repository -> string
(** The real path of the root of the repository. *)

val git : repository -> string list -> (string, error) result
(** [git repository arguments] runs git in the root of [repository] with the
    same environment as the builder, and returns what git wrote to standard
    output. The rule of {!run} on the working folder of the process holds here
    too. *)
