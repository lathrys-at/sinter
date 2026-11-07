(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The delivery lines of commit messages. A delivery line is one line of a
    commit message, [Delivers: <plan>/<step> <hash>]: [<plan>] is the full form
    of a plan, [<step>] the slug of one of its steps, and [<hash>] the first six
    hexadecimal digits of the step hash. One space stands between the parts.
    Spaces, tabs, and carriage returns at the end of the line do not count. *)

type t = private {
  plan : string;
  step : string;
  hash : string;  (** six lowercase hexadecimal digits *)
}
(** A line that matches the pattern. *)

val prefix : string
(** [prefix] is [Delivers: ], with one space after the colon. *)

val make : plan:string -> step:string -> hash:string -> t option
(** [make ~plan ~step ~hash] is the delivery line of these parts. It is [None]
    when {!Plan_target.parse} does not read [plan], when [step] is not a slug of
    {!Slug.is_valid}, or when [hash] is not six lowercase hexadecimal digits. *)

val to_string : t -> string
(** [to_string line] is the text of [line]: {!prefix}, the plan, [/], the step,
    a space, and the hash. [of_string (to_string line)] is [Some line]. *)

val of_string : string -> t option
(** [of_string text] reads one line, without its line feed. The spaces, tabs,
    and carriage returns at the end of [text] do not count. It is [None] when
    [text] does not start with {!prefix}, or when the text after {!prefix} is
    not a plan, [/], a step, one space, and a hash, as {!make} takes them. The
    plan ends at the first [/]. *)

type found = private {
  commit : string;  (** the object id of the commit *)
  number : int;  (** the number of the line in the message, from 1 *)
  text : string;
      (** the line, without its line feed and without the spaces, tabs, and
          carriage returns at its end *)
  line : t option;  (** the line, as {!of_string} reads [text] *)
}
(** One line of a commit message that starts with {!prefix}. *)

val read : commit:string -> string -> found list
(** [read ~commit message] is each line of [message] that starts with {!prefix},
    in the order of the lines. A line ends at a line feed, or at the end of
    [message]. Each paragraph counts: the subject, the body, and the trailers.
    [commit] is the object id of the commit of [message]. *)
