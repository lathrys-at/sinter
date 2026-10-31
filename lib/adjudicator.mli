(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The comparison of the working tree with the base: the tombstones, and the
    finding classes that compare the two trees. The facts of both trees come
    from {!Facts.make} with the manifest of the working tree. *)

type declared = { slug : string; rev : int; xh : string }
(** The slug, the revision, and the extent hash of a declaration. *)

type tombstone = private {
  kind : string;  (** the kind of the fact of the base *)
  was : string;  (** the id of the fact at the base *)
  place : (string * Markdown.span) option;
      (** the path and the span of the fact in the base tree; [None] for an
          [external] *)
  declared : declared option;  (** for a declaration *)
}
(** A fact of the base that the working tree lacks. *)

val tombstones :
  ?same:(string -> bool) -> base:Facts.t -> Facts.t -> tombstone list
(** [tombstones ~same ~base facts] is one tombstone for each identity of
    {!Facts.identities} [base] whose id no identity of [facts] has, in the order
    of {!Facts.identities} [base]. Two facts of the base with one id give one
    tombstone, from the first.

    [same path] is [true] when the file at [path] has the same content in the
    base and in the working tree. [base] may leave out the facts of such a file:
    the facts of [facts] at that path stand for them. [same] is [false] for
    every path when absent. A wrong [true] gives a wrong result. *)

val classes :
  ?same:(string -> bool) ->
  ?changed:string list ->
  base:Facts.t ->
  Facts.t ->
  Finding.t list ->
  Finding.t list
(** [classes ~same ~changed ~base facts findings] is [findings] with the
    findings of the classes that compare the working tree with the base, sorted
    by {!Finding.compare}. [same] and [base] are as {!tombstones} takes them.
    [changed] is the path of each file to which the diff between the base and
    the working tree gives a hunk; it is empty when absent. The classes are:

    - [unbumped]: a declaration of the kind [req], [design], or [decision] whose
      slug the base declares, in one of these kinds, when no such declaration of
      the base has the kind and the extent hash of the declaration, and none has
      a lower revision than the declaration. The fix is the tag line of the
      declaration with the highest revision of these declarations of the base
      plus 1. The detail names the first of them in the order of their paths and
      lines that has the highest revision.
    - [renamed]: an edge whose tag target is a valid slug that no declaration
      has, when the slug is the slug of exactly one tombstone of a declaration,
      exactly one tombstone of a declaration has the extent hash of that
      tombstone, exactly one new declaration has that extent hash, and the new
      declaration has the kind of the tombstone. A new declaration is a
      declaration of the working tree whose id no declaration of the base has.
      The fix is the citation with the slug of the new declaration, and with its
      revision when the edge has a revision. Each [dangling] finding of
      [findings] about such an edge leaves the result.
    - [promise-collision]: a promise of a declaration of the kind [req],
      [design], or [decision] whose tag target is the slug of a declaration of
      the base of one of these kinds, when the base has no promise of the same
      plan with the same step slug, word, and tag target. A plan of the base is
      the same plan as a plan of the working tree when their {!Facts.full_form}s
      are equal, or when the plan of the base has no plan id and the two have
      the same slug and the same path. The detail names the first such
      declaration of the base in the order of their paths and lines. The ledger
      is absent, so no claim counts.

    - [mark-without-change]: a step of a plan of the working tree whose mark the
      diff adds, when no path of [changed] other than the path of the plan file
      is in the effective scope of the step. The diff adds the mark when the
      step has a mark, and the same plan of the base, by the rule of
      [promise-collision], has no step of the same slug, or that step has no
      mark, or its mark does not count in the base and names another hash. The
      finding sits at the mark.

    No finding of these classes sits under a historical path. *)

val renamed_to :
  ?same:(string -> bool) ->
  base:Facts.t ->
  Facts.t ->
  string ->
  Facts.declaration option
(** [renamed_to ~same ~base facts target] is the new declaration that the fix of
    [renamed] names for an edge of [facts] whose tag target is [target], by the
    conditions of the class [renamed] in {!classes}. It is [None] when such an
    edge is not [renamed]. [same] and [base] are as {!tombstones} takes them.
    [renamed_to ~same ~base facts] makes the tombstones once, when the first tag
    target needs them, and gives a function that each tag target can share. *)
