(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The facts of the markdown files of one tree, as JSON Lines records.

    A file is a plan file when its path starts with [.plans/] and its first tag
    block holds a tag of the word [plan]. A plan file gives a [plan] record, a
    [step] record for each step, and a [promise] record for each promise. Every
    other file gives a record for each declaration of the kinds [req], [design],
    and [decision], each edge, each site, and each ack. Each distinct ref that
    an edge names and that resolves gives one [ref] record.

    The records take the values that hold when the ledger, the evidence, and the
    session are absent: every plan is open, no plan and no step is active,
    nothing is declined, and an item of a kind that needs approval is not
    approved. *)

type t
(** The facts of one tree. *)

val make : Manifest.t -> (string * Markdown.t) list -> t
(** [make manifest files] is the facts of [files]. Each pair is the path of one
    file, relative to the repository root, and the document that
    {!Markdown.read} gave for the file. No path occurs twice. The manifest gives
    the ref namespaces, the kinds that need approval, and the default locations
    of the kinds. *)

val needs_changes : t -> bool
(** [needs_changes facts] is [true] when a step of a plan has no promise. Only
    then does {!records} read its argument [changed]. *)

val records : t -> changed:string list -> Jsonl.record list
(** [records facts ~changed] is every record of [facts], in the order of
    [(kind, path, line, col, id)], with each record that has no path after the
    others, in the order of their ids. [changed] is the paths of the files that
    the diff between the base and the working tree changes, of every pack and of
    no pack; a step with no promise is done only when a path of [changed] is in
    its scope.

    Every string of the result is valid UTF-8 when every path of [make] is. *)

val index :
  tree:string ->
  base:string ->
  target_branch:string ->
  manifest:string ->
  tool:string ->
  Jsonl.record
(** [index ~tree ~base ~target_branch ~manifest ~tool] is the header record of a
    scan in tree mode, for a repository with no ledger ref, no evidence, and no
    fetched pack. [tree] is the tree key, [base] the object id of the base
    commit, [manifest] the path of the manifest, and [tool] the version of the
    tool. *)
