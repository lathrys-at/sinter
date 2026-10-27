(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** One finding: a finding class that fires on one subject. *)

type place = { path : string; span : Markdown.span }
(** A piece of one file of the working tree. [path] is relative to the
    repository root. The place of a finding that sits at a hunk of the diff,
    such as [unplanned-change] or a [config-changed] finding of a removed entry,
    is in the file of the hunk: the working tree can lack that file, and the
    place can start on the line after the last line of the file. *)

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

type mark = { start : int; stop : int; label : string }
(** A part of the first line of the place of a finding: the column of its first
    character, the column one past its last character, and a label for a person.
*)

val part : Markdown.tag -> Tag_line.part -> string -> mark option
(** [part tag part label] is the mark of [part] of [tag], with the columns that
    {!Markdown.columns} gives and the label [label]; [None] when [tag] has no
    such part. *)

type related = { label : string; place : place option }
(** A place that explains a finding, with a label for a person. [place] is
    [None] for a place in no file. *)

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
  ackable : bool;  (** [true] when an [@ack] can accept the finding *)
  mark : mark option;
      (** the part of the place at fault; its label is one line, with no control
          character but the tab *)
  related : related list;
      (** the places that explain the finding, sorted and each once, as {!make}
          gives them; each label is one line, with no control character but the
          tab *)
}
(** One finding. *)

val make :
  Finding_class.t ->
  subject ->
  ?place:place ->
  ?detail:string ->
  ?fix:string ->
  ?ackable:bool ->
  ?mark:mark ->
  ?related:related list ->
  unit ->
  t
(** [make finding_class subject ?place ?detail ?fix ?ackable ?mark ?related ()]
    is the finding of [finding_class] about [subject]. Its detail and its fix
    are [detail] and [fix] as {!escape} writes them, so each is one line. Its
    mark is [mark], and its related places are [related], with each label as
    {!escape} writes it. [related] is empty when absent.

    The related places are sorted by the path, the start line, the start column,
    the stop line, and the stop column of their places, and then by their
    labels, each path and label in byte order. The places in no file come after
    the others, sorted by their labels. Neither the mark nor the related places
    enter {!id} or {!compare}.

    A finding of [unexercised] is ackable. A finding of [retired] or
    [unmet-rule] is ackable only under a condition of its class: when [ackable]
    is [true]. [ackable] is [false] when absent. A finding of any other class is
    not ackable.

    @raise Invalid_argument
      if [detail] or [fix] is empty, or if [ackable] is given for a class other
      than [retired] and [unmet-rule]. It also raises on a mark when [place] is
      absent; when the start column of the mark is before the start column of
      [place]; when [place] starts and stops on one line and the stop column of
      the mark is after the stop column of [place]; when the stop column of the
      mark is not after its start column; and when the label of the mark is
      empty. It raises on an empty label of a related place, and on two related
      places that are equal after {!escape} writes their labels. *)

val escape : string -> string
(** [escape text] is [text] with each ASCII control character other than the tab
    written as two or four characters: [\r] for a carriage return, [\n] for a
    line feed, and [\x] and two lowercase hexadecimal digits for any other, for
    example [\x00] or [\x7f]. Every other byte stays as it is. The result holds
    no control character but the tab. When [text] holds no such character, the
    result is [text] itself, not a copy. *)

val id : t -> string
(** [id finding] is [finding:<class>:<subject id>]. *)

val id_of : Finding_class.t -> subject -> string
(** [id_of finding_class subject] is the {!id} of a finding of [finding_class]
    about [subject]. *)

val compare : t -> t -> int
(** [compare a b] orders two findings by the path of their places, the line and
    the column where their places start, and their ids, each path and id in byte
    order. A finding with no place comes after every finding with a place, and
    two findings with no place are in the order of their ids. Two findings
    compare as equal only when their paths, their starts, and their ids are
    equal. *)
