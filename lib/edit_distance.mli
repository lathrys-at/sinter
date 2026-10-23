(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The edit distance between two names, and the nearest name of a list.

    An edit is one insertion, one deletion, or one substitution of a character,
    or one swap of two characters next to each other. A character is one code
    point of UTF-8. A byte that is not part of a valid UTF-8 sequence counts as
    one character of its own, different from every code point. *)

val distance : string -> string -> int
(** [distance a b] is the smallest number of edits that turns [a] into [b]. An
    edit can change a character that an earlier edit inserted or moved, so this
    is the Damerau–Levenshtein distance, and not the restricted distance of
    optimal string alignment. ["ca"] and ["abc"] are two edits apart.

    The distance is [0] only for equal strings. It is symmetric, and it obeys
    the triangle inequality. It is at least the difference of the two lengths in
    characters, and at most the greater of the two lengths. *)

val nearest : string -> string list -> string option
(** [nearest name candidates] is the member of [candidates] nearest to [name],
    when one is within two edits of it. Of two members at the same distance, the
    first in byte order wins. It is [None] when no member is within two edits. A
    member equal to [name] is at distance [0], so it is its own nearest name. *)
