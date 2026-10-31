(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The fix of a finding. A finding holds its fix in the compact form {!t}: the
    tag line that the fix changes, and the new parts. The help message, the
    edits, and the text of the fix are derived from it when the output is
    written. *)

type t
(** One fix. A value holds the tag that it changes. Two fixes compare with [=].
*)

(** {1 Fixes} *)

val word : Markdown.tag -> string -> t
(** [word tag word] is the fix of [typo-tag]: [@] and [word] in place of the tag
    word of [tag]. *)

val pin : Markdown.tag -> int -> t
(** [pin tag rev] is the fix of [suspect] and of [unpinned]: the revision [rev]
    on the citation [tag], in place of its revision, or after its target when it
    has none.

    @raise Invalid_argument
      if [tag] has no target, or if the revision of [tag] is [rev]. *)

val bump : Markdown.tag -> int -> t
(** [bump tag rev] is the fix of [unbumped]: the revision [rev] on the
    declaration [tag], in place of its revision, or after its target when it has
    none.

    @raise Invalid_argument
      if [tag] has no target, or if [rev] is not above the revision of [tag], 1
      when [tag] has none. *)

val spelling : Markdown.tag -> string -> t
(** [spelling tag target] is the fix of [dangling]: the tag target [target] in
    place of the target of [tag].

    @raise Invalid_argument if [tag] has no target. *)

val rename : Markdown.tag -> string -> int -> t
(** [rename tag target rev] is the fix of [renamed]: the tag target [target] in
    place of the target of [tag], and the revision [rev] in place of its
    revision when [tag] has one.

    @raise Invalid_argument if [tag] has no target. *)

val successors : Markdown.tag -> string * int -> (string * int) list -> t
(** [successors tag first others] is the fix of [retired] when the cited item
    has successors: one alternative for each successor, [first] and then
    [others], each a slug and a revision. An alternative writes the slug in
    place of the target of [tag], and the revision in place of the revision of
    [tag] when [tag] has one.

    @raise Invalid_argument if [tag] has no target. *)

val plan_id : Markdown.tag -> Plan_target.id -> t
(** [plan_id tag id] is the fix of [missing-plan-id]: [@] and [id] after the
    target of the [@plan] tag [tag].

    @raise Invalid_argument if [tag] has no target. *)

val mark_hash : Markdown.tag -> string -> t
(** [mark_hash tag hash] is the fix of [stale-mark]: the mark hash [hash] in
    place of the target of the [@delivered] tag [tag].

    @raise Invalid_argument if [tag] has no target. *)

val ack : Markdown.t -> block:int -> target:string -> t
(** [ack document ~block ~target] is the fix of [retired] when the cited item
    has no successor: the line [@ack retired <target> <hash>] after the last tag
    line of the block at index [block] of [document], where [<hash>] is the
    first eight digits of the block hash.

    @raise Invalid_argument
      if [block] is not an index of {!Markdown.t.blocks} of [document]. *)

val mark_line : Markdown.t -> block:int -> hash:string -> t
(** [mark_line document ~block ~hash] is the fix of [unmarked-step]: the line
    [@delivered <hash>] after the last tag line of the block at index [block] of
    [document].

    @raise Invalid_argument
      if [block] is not an index of {!Markdown.t.blocks} of [document]. *)

(** {1 Output} *)

type edit = { line : int; col : int; eline : int; ecol : int; text : string }
(** One edit of the file of a finding: [text] in place of the span from column
    [col] of line [line] to column [ecol] of line [eline], with the lines and
    the columns of {!Markdown}, and [ecol] one past the last character. A span
    of no character inserts [text]; an empty [text] deletes the span. *)

val alternatives : t -> edit list list
(** [alternatives fix] is the alternatives of [fix], each a list of edits: one
    alternative, or one for each successor of {!successors}, in their order. The
    edits of one alternative are sorted by their spans, do not overlap, and are
    never none. Each edit of one alternative starts and stops on one line, the
    line of the first edit of the alternative. An edit covers only the part of
    the tag line that changes:

    - {!word}: the tag word, with [@] and the word.
    - {!pin} and {!bump}: the revision of the tag, with [v] and the revision;
      or, when the tag has no revision, the empty span at the end of its target,
      with a space, [v], and the revision.
    - {!spelling}: the target, with the new target.
    - {!mark_hash}: the target, with the new mark hash.
    - {!plan_id}: the empty span at the end of the target, with [@] and the plan
      id.
    - {!rename} and each successor of {!successors}: the target, with the slug;
      and, when the tag has a revision that differs from the new revision, the
      revision, with [v] and the new revision.
    - {!ack}: the empty span at the end of the last tag line of the block,
      before its line ending, with {!Markdown.block.new_line} of the block and
      then the [@ack] line.
    - {!mark_line}: the same empty span, with {!Markdown.block.new_line} of the
      block and then the [@delivered] line. *)

val help : t -> string
(** [help fix] is the help message of [fix], one line for the person who reads
    the finding. The message is one constant string for each function that makes
    a fix, and for {!pin} and {!successors} one for each form: a tag with a
    revision or none, and one successor or more. *)

val text : t -> string
(** [text fix] is the fix in one string: [@] and the word for {!word}; the head
    of the new tag line, [@<word> <target>] with [ v<rev>] when the new line has
    a revision, for {!pin}, {!bump}, {!spelling}, {!rename}, {!plan_id}, and
    {!mark_hash}; that head for each successor, joined by [" or "], for
    {!successors}; the [@ack] line for {!ack}; and the [@delivered] line for
    {!mark_line}. *)
