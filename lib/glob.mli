(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Globs: patterns that match the paths of a repository.

    A path is relative to the repository root. It is a sequence of names joined
    by [/], with no [/] at the start or at the end.

    A glob is a sequence of segments joined by [/]. A segment is [**], or a
    sequence of characters in which [*] matches any sequence of characters
    inside one name, the empty sequence included. A glob matches the whole path,
    from the repository root:

    - a segment [**] that is not the last segment matches any number of names,
      zero included;
    - a segment [**] that is the last segment matches one or more names;
    - a glob that ends with [/] means the same as the glob with [**] added;
    - [*] and [**] match names that start with [.];
    - every other character matches itself, and case always matters. *)

type t
(** A valid glob. *)

(** Why a string is not a valid glob. Each offset is the offset, in bytes from
    0, of the first byte of the string that the error names. *)
type error =
  | Empty  (** the string is empty *)
  | Leading_slash  (** the string starts with [/] *)
  | Empty_segment of int
      (** two [/] stand together; the offset is that of the second *)
  | Dot_segment of { offset : int; segment : string }
      (** a segment is [.] or [..]; the offset is that of the segment *)
  | Double_star_in_segment of { offset : int; segment : string }
      (** a segment holds [**] and other characters too, such as [**.ts]; the
          offset is that of the segment *)
  | Forbidden_character of { offset : int; character : char }
      (** the string holds a question mark, a bracket, a brace, or a backslash
      *)

val of_string : string -> (t, error) result
(** [of_string text] is the glob that [text] writes. When [text] holds more than
    one error, the error is the one at the smallest offset. *)

val to_string : t -> string
(** [to_string glob] is the text that {!of_string} read, as it was written. *)

val matches : t -> string -> bool
(** [matches glob path] is [true] when [glob] matches [path]. The function
    splits [path] into names at each [/]. A string that is not a path, such as
    one with an empty name, gets the answer for the names that the split gives.
    The time is at most the product of the number of segments and the length of
    [path], times the length of the longest segment. *)

val error_offset : error -> int
(** [error_offset error] is the offset that [error] names. It is [0] for [Empty]
    and [Leading_slash]. *)

val message : error -> string
(** [message error] says what is wrong with the glob and, when it can, what to
    write instead. It is one line, without the glob itself and without a full
    stop at the end. *)
