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
  | Unparsed_base_file of { file : string; error : Sinter_bridge.Tree.error }
      (** the parse of the content that the base holds for a file of the pack
          [markdown] gives no tree *)
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

val base_note : base -> string
(** [base_note base] names the base for the person who runs the tool, as the
    text of a note: [base <commit>, the merge base of HEAD and <ref>] for a
    merge base, where [<ref>] is the ref without a leading [refs/remotes/] or
    [refs/heads/]; and [base <commit>, from --base <revision>] for a base that
    the caller named. [<commit>] is the first 7 hexadecimal digits of the
    commit. The ref and the revision print as {!Display.clean} gives them. The
    text ends with no full stop. *)

type tree = private {
  repo : Git.t;
  file_set : Git.file_set;
      (** the file set of the working tree, as {!Git.files} gives it *)
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
          absent. After {!load_with_base}, the file set of the base counts too,
          and a path of both file sets has one line. *)
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

(** {1 The base} *)

(** The file at the path of the manifest in the base tree. *)
type base_manifest =
  | Outside  (** the manifest is outside the repository *)
  | Absent  (** the base tree holds no file at the path of the manifest *)
  | Unchanged
      (** the base tree holds the file, and {!field-diff} lists no change of its
          content *)
  | Changed of string
      (** the base tree holds the file, and {!field-diff} lists a change of its
          content: the content of the file in the base tree *)

type compared = private {
  diff : (string * Git.change) list;
      (** the change of each path between the base and the working tree, as
          {!Git.diff} gives it *)
  base_documents : (string * Markdown.t) list;
      (** each file of the file set of the base that the pack [markdown] reads
          and whose content at the base is UTF-8 text, with its document, in the
          order of the paths *)
  base_not_text : (string * int) list;
      (** each file of the file set of the base that the pack [markdown] reads
          and whose content at the base is not UTF-8 text, in the order of the
          paths, with the byte offset of its first sequence that is not
          well-formed *)
  base_manifest : base_manifest;
      (** the file at the path of the manifest in the base tree. Its content is
          read only when the diff lists a change of it. *)
}
(** The base tree as a scan reads it, and the diff between the base and the
    working tree. The base tree is read with the manifest of the working tree.

    A file that {!field-diff} does not list with a change of content, and that
    the working tree reads, takes the document of the working tree, the same
    value. Every other file is read from the blob of the base commit. A change
    of the mode alone is no change of content. *)

val load_with_base :
  ?phases:Allocation.t ->
  env:string array ->
  dir:string ->
  manifest:string option ->
  base:string option ->
  unit ->
  (tree * compared, error) result
(** [load_with_base ~env ~dir ~manifest ~base ()] is {!load} with the same
    arguments, and the base tree that it compares the working tree with.

    The error is [Unparsed_base_file] when the parse of a blob gives no tree.
    With [phases], it counts the phases of {!load}, and the phase [base-read]
    (the diff, the files of the base, and the read and the parse of each blob).

    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)

val index : ?mode:Mode.t -> tree -> tool:string -> (Jsonl.record, error) result
(** [index tree ~tool] is the index record of [tree]. [tool] is the version of
    the tool. [mode] is the mode of the run; the default is [Tree]. *)

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
