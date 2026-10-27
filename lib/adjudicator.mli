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

val tombstones : base:Facts.t -> Facts.t -> tombstone list
(** [tombstones ~base facts] is one tombstone for each identity of
    {!Facts.identities} [base] whose id no identity of [facts] has, in the order
    of {!Facts.identities} [base]. Two facts of the base with one id give one
    tombstone, from the first. *)

val classes : base:Facts.t -> Facts.t -> Finding.t list -> Finding.t list
(** [classes ~base facts findings] is [findings] with the findings of the
    classes that compare the working tree with the base, sorted by
    {!Finding.compare}. The classes are:

    - [unbumped]: a declaration of the kind [req], [design], or [decision] whose
      slug a declaration of the base of one of these kinds has, with another
      kind or another extent hash, and whose revision is not above the revision
      of that declaration of the base. When the base has two declarations of the
      slug, the first in the order of {!Facts.declarations} counts. The fix is
      the tag line of the declaration with the revision of the base plus 1.

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
      the base of one of these kinds, when the base has no promise with the same
      plan, step, word, and tag target. The ledger is absent, so no claim
      counts.

    No finding of these classes sits under a historical path. *)
