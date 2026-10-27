(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The lines of a text, and each place of the text as a line and a column.

    A line ends at a line feed (LF). A carriage return (CR) right before an LF
    is part of the line ending. When the text does not end with an LF, the bytes
    after the last LF form the last line. A byte order mark (the bytes EF BB BF)
    at the start of the text is part of no line.

    A column counts characters: each byte that does not continue a UTF-8
    sequence starts a character. The characters of a line ending count in no
    column, and neither does a byte order mark. *)

type position = { line : int; column : int }
(** A place in the text. [line] and [column] count from 1. *)

type t
(** The lines of one text. The value holds the text. *)

val make : string -> t
(** [make text] finds the lines of [text]. The time is linear in the length of
    [text]. *)

val text : t -> string
(** [text index] is the text that {!make} took. *)

val count : t -> int
(** [count index] is the number of lines of the text. It is [0] for the empty
    text. *)

val first : t -> int -> int
(** [first index line] is the byte offset of the first byte of [line]. For line
    1, it is the offset after the byte order mark when the text starts with one.

    @raise Invalid_argument if [line] is not from 1 to [count index]. *)

val content_end : t -> int -> int
(** [content_end index line] is the byte offset one past the last byte of [line]
    that is not part of its line ending. It is [first index line] for a line
    with no character.

    @raise Invalid_argument if [line] is not from 1 to [count index]. *)

val content : t -> int -> string
(** [content index line] is the bytes of [line], without its line ending.

    @raise Invalid_argument if [line] is not from 1 to [count index]. *)

val line_of : t -> int -> int
(** [line_of index offset] is the line that holds the byte at [offset]. A byte
    of the byte order mark is on line 1, and so is a byte of a line ending on
    the line that it ends. The offset can be the length of the text, the end of
    the text: it is on the last line.

    @raise Invalid_argument
      if [offset] is not from 0 to the length of the text, or if the text has no
      line. *)

val characters : string -> int -> int -> int
(** [characters text start stop] is the number of characters that start in the
    bytes of [text] from offset [start] to offset [stop - 1]: the number of
    those bytes that do not continue a UTF-8 sequence. It is the count that a
    column takes.

    @raise Invalid_argument
      if [start] is below 0, [stop] is below [start], or [stop] is past the
      length of [text]. *)

val position : t -> int -> position
(** [position index offset] is the place of the byte at [offset]: its line, and
    the column of the character that the byte belongs to. A byte of the byte
    order mark is at line 1, column 1. A byte of a line ending, and the end of
    the text, are in the column after the last character of their line.

    @raise Invalid_argument
      if [offset] is not from 0 to the length of the text, or if the text has no
      line. *)

val after : t -> int -> position
(** [after index stop] is the place one column past the character that holds the
    byte at [stop - 1]: the line of that character, and its column plus 1. It is
    the end of a span whose last character holds that byte.

    @raise Invalid_argument if [stop] is not from 1 to the length of the text.
*)
