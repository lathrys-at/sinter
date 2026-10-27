(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The findings of a working tree in tree mode, from the facts of its markdown
    files and the manifest, when the ledger, the evidence, and the session are
    absent. *)

val tree :
  ?phases:Allocation.t ->
  Manifest.t ->
  (string * Markdown.t) list ->
  not_text:(string * int) list ->
  Finding.t list
(** [tree manifest documents ~not_text] is the findings of the working tree.
    [documents] is as {!Facts.make} takes it. [not_text] is each markdown file
    whose content is not UTF-8 text, by its path relative to the repository
    root, with the byte offset of its first sequence that is not well-formed. No
    path occurs twice in [documents] and [not_text] together.

    The result is sorted by {!Finding.compare}. It holds no finding whose place
    is under a historical path, and no finding that a live [@ack] discharges.
    The tiers of the gates do not change it.

    With [phases], it counts the phases [facts] ({!Facts.make}) and [findings]
    (the rest). *)
