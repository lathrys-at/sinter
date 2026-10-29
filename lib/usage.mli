(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The error of a command line that the library cmdliner refuses, read from the
    text that cmdliner writes. *)

val error : string -> Error_text.t
(** [error text] is the error that [text] reports. [text] is what cmdliner
    writes to its error formatter, with a margin that no line reaches.

    When [text], without its last line feed, is two lines, the first
    [Usage: <usage>] and the second [<name>: <message>], where [<name>] is not
    empty and holds no space and no escape code: the fault is [<message>], and
    the help is [usage: <usage>]. In the message, a part that the escape code
    [ESC\[01m] opens and [ESC\[m] closes stands in single quotes; in the usage,
    it stands as it is. Every other escape code is left out of both.

    For any other [text], the fault is the lines of [text], each with no escape
    code and with no white space at its two ends, without the lines that are
    then empty, joined by one space; and the help is empty.

    The error has no place. *)
