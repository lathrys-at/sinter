(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** One finding: a finding class that fires on one subject. *)

type place = { path : string; span : Markdown.span }
(** A piece of one file of the working tree. [path] is relative to the
    repository root. *)

(** What a finding is about: a fact, or a file, a line, or a tag that is no
    fact. *)
type subject =
  | Fact of { id : string; ack_name : string }
      (** a fact: its id, and the name that an [@ack] gives it. The name is the
          tag target of an edge as the text writes it, or the slug of a
          declaration, a plan, or a step. *)
  | File of string  (** a file that yields no fact, by its path *)
  | Error_node of { path : string; position : Markdown.position }
      (** an error node of a markdown file, by the position where it starts *)
  | Line of { path : string; line : int }  (** a line of a file *)
  | Tag of { path : string; position : Markdown.position }
      (** a tag, by the position of its [@] *)

val subject_id : subject -> string
(** [subject_id subject] is the id of the fact, or the positional subject id:
    [file:<path>] for a file, [file:<path>@L<line>C<column>] for an error node,
    [line:<path>@L<line>] for a line, and [tag:<path>@L<line>C<column>] for a
    tag. *)

val ack_subject : subject -> string
(** [ack_subject subject] is the subject in the form that an [@ack] names it:
    the name of a fact, and the positional subject id of anything else. *)

type t = private {
  finding_class : Finding_class.t;
  subject : subject;
  place : place option;
      (** where the finding sits: the place of its subject; [None] when the
          subject has no place *)
  detail : string option;
      (** one line for a person, with no control character but the tab *)
  fix : string option;
      (** one line, with no control character but the tab: the text to paste, or
          an instruction for a person *)
}
(** One finding. *)

val make :
  Finding_class.t ->
  subject ->
  ?place:place ->
  ?detail:string ->
  ?fix:string ->
  unit ->
  t
(** [make finding_class subject ?place ?detail ?fix ()] is the finding of
    [finding_class] about [subject]. Its detail and its fix are [detail] and
    [fix] as {!escape} writes them, so each is one line.

    @raise Invalid_argument if [detail] or [fix] is empty. *)

val escape : string -> string
(** [escape text] is [text] with each ASCII control character other than the tab
    written as two or four characters: [\r] for a carriage return, [\n] for a
    line feed, and [\x] and two lowercase hexadecimal digits for any other, for
    example [\x00] or [\x7f]. Every other byte stays as it is. The result holds
    no control character but the tab. *)

val id : t -> string
(** [id finding] is [finding:<class>:<subject id>]. *)

val ackable : t -> bool
(** [ackable finding] is [true] when an [@ack] can discharge the finding: its
    class is [disendorsed] or [disconnected]. *)

val compare : t -> t -> int
(** [compare a b] orders two findings by the path of their places, the line and
    the column where their places start, and their ids, each path and id in byte
    order. A finding with no place comes after every finding with a place, and
    two findings with no place are in the order of their ids. Two findings
    compare as equal only when their paths, their starts, and their ids are
    equal. *)
