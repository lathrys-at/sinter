(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The scan of a repository in tree mode: the records of the facts of the
    working tree, with the index record first. *)

(** Why a scan does not run. Each error is a fault of the environment. *)
type error =
  | Repository of Git.error
      (** git fails, or the folder is in no git repository *)
  | No_manifest
      (** no manifest is named, and the root holds no [sinter.toml] *)
  | Missing_manifest of string
      (** nothing is at the path of the manifest that the caller named *)
  | Unreadable_manifest of { path : string; reason : string }
      (** the manifest does not open or read *)
  | Invalid_manifest of { path : string; errors : Manifest.error list }
      (** the manifest holds errors, in the order of their places *)
  | Two_packs of { file : string; pack : string; other : string }
      (** a file is in the files of two packs; [pack] comes before [other] in
          byte order *)
  | Plan_not_read of string
      (** a file under [.plans/] whose name ends in [.md] is not in the files of
          the pack [markdown] *)
  | Pack_not_available of string
      (** the manifest names a fetched pack, and this tool reads none *)
  | Bad_base of string  (** the revision of the base names no commit *)
  | Default_branch_not_found of string
      (** no branch of the name of the default branch gives a commit *)
  | No_merge_base of string
      (** [HEAD] and the default branch of this name have no common ancestor *)
  | Shallow_clone of string
      (** the repository is a shallow clone, and it holds no default branch of
          this name or no merge base of [HEAD] and that branch *)
  | No_head  (** [HEAD] names no commit *)
  | Unreadable_file of { file : string; error : Text_file.error }
      (** a file of the pack [markdown] does not read *)
  | Unparsed_file of { file : string; error : Sinter_bridge.Tree.error }
      (** the parse of a file of the pack [markdown] gives no tree *)
  | Reader of Markdown.load_error  (** the built-in grammar does not load *)

val messages : error -> string list
(** [messages error] says what is wrong and, when it can, what to do, for the
    person who runs the tool: one line for each error of an invalid manifest,
    and one line otherwise. No line ends with a full stop. *)

val escape_path : string -> string
(** [escape_path path] is [path] with each byte that is not part of a valid
    UTF-8 character written as [\x] and two lowercase hexadecimal digits, for
    example [docs/caf\xe9.md]. A path that is valid UTF-8 comes back as it is.
*)

(** {1 The tree} *)

(** The base commit, and the revision or the ref that gave it. *)
type base =
  | Given of { revision : string; commit : string }
      (** the commit of the revision that the caller named *)
  | Merge_base of { refname : string; commit : string }
      (** the merge base of [HEAD] and the commit of the default branch, which
          the ref of the full name [refname] gave *)

val base_commit : base -> string
(** [base_commit base] is the object id of the base commit. *)

val base_message : base -> string
(** [base_message base] names the base for the person who runs the tool: the
    revision or the ref that gave it, and its commit. The line ends with no full
    stop. *)

type tree = private {
  repo : Git.t;
  manifest : Manifest.t;
  location : string;
      (** the path of the manifest: relative to the root of the working tree
          when the manifest is under it, otherwise absolute *)
  base : base;
  documents : (string * Markdown.t) list;
      (** each file of the file set that the pack [markdown] reads and that is
          UTF-8 text, with its document, in the order of the paths *)
  not_text : (string * int) list;
      (** each file of the file set that the pack [markdown] reads and that is
          not UTF-8 text, in the order of the paths, with the byte offset of its
          first sequence that is not well-formed *)
  warnings : string list;
      (** one line for each file of the file set whose path is not UTF-8, in the
          order of the paths, and then one line that says that the ledger ref is
          absent *)
}
(** The working tree of a repository as a scan reads it. *)

val load :
  ?phases:Allocation.t ->
  env:string array ->
  dir:string ->
  manifest:string option ->
  base:string option ->
  unit ->
  (tree, error) result
(** [load ~env ~dir ~manifest ~base ()] reads the working tree of the git
    repository that holds the folder [dir]. [env] is the environment of each git
    child process, as {!Git.open_repo} takes it.

    [manifest] is the path of the manifest, relative to [dir] when it is
    relative; [None] names [sinter.toml] at the root of the working tree. [base]
    is the revision of the base commit; [None] takes the merge base of [HEAD]
    and the default branch of the manifest.

    With [phases], it counts the words of the phases [repository] (the
    repository, the manifest, the list of files, and the base), [read] (the
    reading of each file), and [parse] (the parse of each file).

    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)

val index : tree -> tool:string -> (Jsonl.record, error) result
(** [index tree ~tool] is the index record of [tree]. [tool] is the version of
    the tool. *)

(** {1 The scan} *)

type outcome = {
  warnings : string list;  (** the warnings of the {!tree} *)
  records : Jsonl.record list;
      (** the index record, and then the records of the facts in their order *)
}
(** What a scan gives. *)

val run :
  ?phases:Allocation.t ->
  env:string array ->
  dir:string ->
  manifest:string option ->
  base:string option ->
  tool:string ->
  unit ->
  (outcome, error) result
(** [run ~env ~dir ~manifest ~base ~tool ()] scans the working tree that {!load}
    reads with the same arguments. [tool] is the version of the tool, for the
    index record. A file that is not UTF-8 text gives no fact.

    With [phases], it counts the phases of {!load}, and adds to [repository] the
    index record and the paths that the diff changes, and counts the phases
    [facts] ({!Facts.make}) and [records] ({!Facts.records}).

    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)
