(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Text from the repository as a terminal shows it: the printed form of a
    string, and the display width of each character, in columns of a terminal.

    A character is what one call of [String.get_utf_8_uchar] decodes: a
    well-formed UTF-8 sequence, or a maximal part of a sequence that is not
    well-formed, which can be one byte or more. *)

val clean : string -> string
(** [clean text] is the printed form of [text]. A tab becomes 4 spaces. Each of
    these characters becomes U+FFFD: a C0 control character other than the tab
    (U+0000 to U+001F), DEL (U+007F), a C1 control character (U+0080 to U+009F),
    a bidirectional formatting character (U+202A to U+202E and U+2066 to
    U+2069), and each character that is not well-formed. Every other character
    stays as it is. The result is UTF-8, and holds no control character and no
    bidirectional formatting character. When [text] holds no character that
    changes, the result is [text] itself, not a copy. *)

val width : string -> int
(** [width text] is the display width of [clean text]: the sum of the widths of
    its characters. The width of a character is {!Uucp.Break.tty_width_hint},
    and 0 where that is negative. A tab counts 4, and a character that {!clean}
    replaces counts as U+FFFD, 1. *)

val column_width : string -> int -> int
(** [column_width line column] is the display width of the characters of [line]
    before the column [column], with columns counted from 1: the {!width} of the
    first [column - 1] characters. A column past the end of [line] gives the
    {!width} of [line]. A column of 1 or less gives 0. *)

val length : string -> int
(** [length line] is the number of characters of [line]. *)
