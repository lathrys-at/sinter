(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Id patterns: small regular expressions that match the whole id of a ref.

    A pattern is built from these parts:

    {ul
     {- a literal: one printable ASCII character, from [!] to [~], other than
        the fourteen characters below. It matches itself.
        {v \ . [ ] ( ) { } * + ? | ^ $ v}
     }
     {- a class: an opening bracket, one or more members, and a closing bracket.
        A member is one printable ASCII character other than a bracket, a
        backslash, and [^]; or a range [x-y] whose two ends are both digits,
        both upper-case letters, or both lower-case letters, with [x] not after
        [y]. A [-] is a member when it is first or last in its class. The class
        matches one character that a member matches.
     }
     {- a group: [(], a pattern, [)]. }
     {- a sequence of parts, and an alternation [a|b], which binds loosest. }
     {- a quantifier after a literal, a class, or a group: [?], [*], [+], [{n}],
        [{n,}], or [{n,m}], with [n] and [m] from 0 to 255 and [n] not above
        [m]. A part takes one quantifier at most.
     }
    }

    A pattern matches an id only when it matches the whole id, and case always
    matters. A valid pattern does not match the empty id. *)

type t
(** A valid id pattern. *)

(** Why a string is not a valid id pattern. Each offset is the offset, in bytes
    from 0, of the first byte of the string that the error names. *)
type error =
  | Not_allowed of { offset : int; character : string }
      (** a character that the place does not allow: a space, a character
          outside printable ASCII, a backslash, or [^]; outside a class, also
          [.], [$], a closing bracket, and [}]; inside a class, also an opening
          bracket. [character] is the UTF-8 encoding of the character, or the
          one byte when the bytes at [offset] are not valid UTF-8. *)
  | Unclosed_class of int
      (** an opening bracket with no closing bracket after it *)
  | Empty_class of int  (** a class with no member *)
  | Bad_range of int
      (** the range that starts at the offset has ends of two kinds, ends that
          are not digits or letters, or a first end after the second *)
  | Misplaced_hyphen of int
      (** a [-] in a class that is not first, not last, and not between the two
          ends of a range *)
  | Unclosed_group of int  (** a [(] with no [)] after it *)
  | Unopened_group of int  (** a [)] with no [(] before it *)
  | Empty_group of int  (** [()] *)
  | Empty_alternative of int
      (** an alternative with no part, such as the second of [a|]; also the
          empty pattern *)
  | Quantifier_without_part of int
      (** a quantifier at the start of a pattern, of a group, or of an
          alternative *)
  | Two_quantifiers of int
      (** a second quantifier on one part; the offset is that of the second *)
  | Bad_count of int  (** a [{] that does not start [{n}], [{n,}], or [{n,m}] *)
  | Count_too_large of int
      (** a count of the quantifier at the offset is above 255 *)
  | Counts_out_of_order of int
      (** in the quantifier [{n,m}] at the offset, [n] is above [m] *)
  | Matches_empty  (** the pattern matches the empty id *)

val of_string : string -> (t, error) result
(** [of_string text] is the id pattern that [text] writes. The parser reads
    [text] from the start, and the error is the first that it meets. A pattern
    that matches the empty id gives [Matches_empty] only when it holds no other
    error. *)

val to_string : t -> string
(** [to_string pattern] is the text that {!of_string} read, as it was written.
*)

val matches : t -> string -> bool
(** [matches pattern id] is [true] when [pattern] matches the whole of [id]. An
    id that holds a space, or a character outside printable ASCII, matches no
    pattern.

    The function does not backtrack, so its time is polynomial in the lengths of
    [pattern] and [id]. It follows, part by part from the start of [id], the set
    of places where a match can stand. It computes the end places of the part of
    a quantifier at most once for each place in [id]. After the rounds that a
    quantifier needs, each round goes on only from the places that no earlier
    round reached, and stops at the upper count or when it reaches no new place.
    So a part such as [[0-9]*] takes time in proportion to the length of [id].
    An id that holds a space or a character outside printable ASCII gets its
    answer before any part is matched. *)

val error_offset : error -> int
(** [error_offset error] is the offset that [error] names. It is [0] for
    [Matches_empty]. *)

val message : error -> string
(** [message error] says what is wrong with the pattern and, when it can, what
    to write instead. It is one line, without the pattern itself and without a
    full stop at the end. *)
