(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Mechanical repairs: the hunks of a diff whose every change is an edit that a
    fix of sinter makes. The test reads the tags of the lines of a hunk, and not
    their text: the tags of the removed lines in the base tree, and the tags of
    the added lines in the working tree. *)

(** {1 Tags} *)

type tag = {
  column : int;  (** the column of the [@] *)
  word : string;  (** the tag word without its [@]; it can be empty *)
  target : string option;  (** the tag target *)
  rev : int option;  (** the revision *)
  desc : string;  (** the inline description, as it stands *)
}
(** The parts of one tag line that the test compares. *)

val of_markdown : Markdown.tag -> tag
(** [of_markdown tag] is the parts of [tag]. *)

val tags : Markdown.t -> first:int -> count:int -> tag list option
(** [tags document ~first ~count] is the tags of the lines [first] to
    [first + count - 1] of [document], in the order of the lines. It is [None]
    when one of these lines is not a line of {!Markdown.t.tags}, that is, not a
    tag line of a tag-bearing node. [count = 0] gives [Some []]. *)

(** {1 Fixes} *)

type fixes = {
  revision : string -> int option;
      (** the revision that the fixes of [suspect] and [unpinned] write for a
          tag target: the revision of the declaration that the tag target
          resolves to *)
  spelling : string -> string option;
      (** the tag target that the fix of [dangling] writes for a tag target *)
  renamed : string -> (string * int) option;
      (** the slug and the revision of the new declaration that the fix of
          [renamed] names for a tag target *)
  successors : string -> (string * int) list;
      (** the slug and the revision of each successor that the fix of [retired]
          names for the tag target of a [@cites] *)
  word : string -> string option;
      (** the tag word, without its [@], that the fix of [typo-tag] writes for a
          tag word *)
}
(** What the fixes of sinter write, by the facts of the working tree and, for
    [renamed], of the base. *)

val fixes : ?same:(string -> bool) -> base:Facts.t -> Facts.t -> fixes
(** [fixes ~same ~base facts] is what the fixes write in the working tree of
    [facts], with [base] the facts of the base tree. [same] and [base] are as
    {!Adjudicator.tombstones} takes them. Each function reads the facts that it
    needs once, on its first call, and keeps them:

    - [revision]: the revision of the declaration that {!Facts.resolve} gives;
      [None] when the tag target resolves to no declaration.
    - [spelling]: {!Findings.declared_spelling}.
    - [renamed]: the new declaration of {!Adjudicator.renamed_to}.
    - [successors]: {!Facts.successors} of the declaration that the tag target
      resolves to, in their order; [[]] when it resolves to no declaration.
    - [word]: {!Findings.nearest_word}. *)

(** {1 The test} *)

val is_repair : fixes -> removed:tag list -> added:tag list -> bool
(** [is_repair fixes ~removed ~added] is [true] when a hunk whose removed lines
    have the tags [removed], and whose added lines have the tags [added], in the
    order of the lines, is a mechanical repair. These conditions must all hold:

    + [removed] and [added] are not both empty.
    + Each tag of the word [ack] is one edit. Without them, [removed] and
      [added] have the same length. The first removed tag pairs with the first
      added tag, and so on.
    + In each pair of an old tag [o] and a new tag [n], the columns of the [@]
      are equal, and the inline descriptions are equal.
    + Each pair differs by exactly one of these edits:

    - a re-pin: [o] and [n] have one citation word, one tag target, and two
      different revisions, and the revision of [n] is [fixes.revision] of the
      tag target;
    - an added revision: as a re-pin, for the words [satisfies], [verifies],
      [refines], and [supersedes], when [o] has no revision;
    - a bump: [o] and [n] have one word of [req], [design], and [decision], one
      tag target, and the revision of [n] is higher than that of [o]. A tag with
      no revision has the revision 1;
    - a case fix: [o] and [n] have one citation word and one revision, and the
      tag target of [n] is [fixes.spelling] of the tag target of [o];
    - the retarget of [renamed]: [o] and [n] have one citation word, the tag
      target of [n] is the slug of [fixes.renamed] of the tag target of [o], and
      [n] has its revision when [o] has a revision, and no revision otherwise;
    - the successor of [retired]: as the retarget of [renamed], for the word
      [cites], with a member of [fixes.successors] in place of [fixes.renamed];
    - a corrected tag word: [o] and [n] have one tag target and one revision,
      two different words, and the word of [n] is [fixes.word] of the word of
      [o];
    - an added plan id: [o] and [n] have the word [plan] and one revision, the
      tag target of [o] is a slug with no plan id, and the tag target of [n] is
      that slug, [@], and any plan id, by {!Plan_target.parse}.

    The citation words are [satisfies], [verifies], [refines], [cites], and
    [supersedes]. Two tags that a re-pin, a bump, or a retarget compares have a
    tag target. *)

val hunk :
  fixes -> base:Markdown.t option -> Markdown.t option -> Git.hunk -> bool
(** [hunk fixes ~base document h] is {!is_repair} of the tags of the lines that
    [h] removes from [base], the document of the file in the base tree, and of
    the tags of the lines that [h] adds to [document], the document of the file
    in the working tree. A document is [None] when the tree holds no such
    document. It is [false] when a removed line or an added line is not a tag
    line, by {!tags}, or when its tree has no document. *)
