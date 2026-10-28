(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The findings of a working tree in tree mode, from the facts of its markdown
    files and the manifest, when the ledger, the evidence, and the session are
    absent. *)

val tree :
  ?phases:Allocation.t ->
  Manifest.t ->
  (string * Markdown.t) list ->
  base:string ->
  not_text:(string * int) list ->
  Finding.t list
(** [tree manifest documents ~base ~not_text] is the findings of the working
    tree. [documents] is as {!Facts.make} takes it. [base] is the object id of
    the base commit in lowercase hexadecimal; the fix of [missing-plan-id]
    derives its plan id from it ({!Plan_target.derive}). [not_text] is each
    markdown file whose content is not UTF-8 text, by its path relative to the
    repository root, with the byte offset of its first sequence that is not
    well-formed. No path occurs twice in [documents] and [not_text] together.

    The result is sorted by {!Finding.compare}. It holds no finding whose place
    is under a historical path, and no finding that a live [@ack] accepts. The
    tiers of the gates do not change it.

    With [phases], it counts the phases [facts] ({!Facts.make}) and [findings]
    (the rest). *)

val of_facts :
  Facts.t -> base:string -> not_text:(string * int) list -> Finding.t list
(** [of_facts facts ~base ~not_text] is {!tree} of the manifest and the files of
    [facts], with no phase. It builds no facts. *)

(** {1 Fixes} *)

val nearest_word : string -> string option
(** [nearest_word word] is the tag word, without its [@], that the fix of
    [typo-tag] names for a tag line of the word [word]: the word of the
    vocabulary of sinter nearest to [word], as {!Edit_distance.nearest} gives
    it. It is [None] when [word] is in the vocabulary, and when no word of the
    vocabulary is within two edits of [word]. *)

val declared_spelling : Facts.t -> string -> string option
(** [declared_spelling facts target] is the tag target that the fix of
    [dangling] names for an edge of [facts] whose tag target is [target]: the
    first in byte order of the slugs of the declarations of the kinds [req],
    [design], and [decision] that are equal to [target] in ASCII lowercase. It
    is [None] when [target] resolves to something by {!Facts.resolve}, when
    [target] is not a valid slug, and when no such declaration exists.
    [declared_spelling facts] reads the declarations once, when the first tag
    target needs them, and gives a function that each tag target can share. *)
