(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Tag lines and their parts.

    A tag line is a line of a tag-bearing node whose text, after the prefixes
    that the language removes and after the spaces and tabs at its start, starts
    with [@]. Its tag word is the [@] and the longest run of ASCII letters,
    ASCII digits, and [-] right after the [@]. A token is a run of characters
    that are neither a space nor a tab. *)

type t = {
  word : string;  (** the tag word without its [@]; it can be empty *)
  rest : string;  (** the text of the line after the tag word *)
}
(** One tag line. *)

val read : string -> (int * t) option
(** [read text] is the tag line that [text] holds, and the byte offset of its
    [@] in [text]: [Some] when [text], after the spaces and tabs at its start,
    starts with [@]. [text] holds no line ending. *)

type parts = {
  target : string option;  (** the first token, when there is one *)
  revision : int option;
      (** [N] when the second token is [vN]: [v] and a decimal number from 1 to
          2^53 - 1 with no leading zero *)
  description : string;
      (** the text after the target and the revision, as it stands, with the
          spaces and tabs at its start; [""] when there is none *)
}
(** The parts of the text after a tag word, read as [target [vN] description].
*)

val parts : string -> parts
(** [parts rest] reads the text [rest] after a tag word. *)

val without_revision : string -> string
(** [without_revision rest] is [rest] without its revision token and the spaces
    and tabs in front of that token. It is [rest] when {!parts} finds no
    revision in it. *)
