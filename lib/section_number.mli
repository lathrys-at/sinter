(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The section number at the start of the text of a heading.

    A section number is a run of ASCII digits and a [.], then optionally more
    runs of digits joined by [.], with an optional final [.]. A space or a tab
    follows it. As a pattern: [[0-9]+\.([0-9]+(\.[0-9]+)*\.?)?[ \t]]. *)

val length : string -> int
(** [length text] is the number of bytes of the section number at the start of
    [text], with every space and tab after it. It is [0] when [text] does not
    start with a section number. *)

val remove : string -> string
(** [remove text] is [text] without the first {!length} [text] bytes. *)
