(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The styles of the elements that the full and brief forms and the messages on
    standard error print, and the choice of color for each output stream. *)

(** An element of the output. *)
type element =
  | Block
      (** the tier [block], and the mark and its label of a finding at that
          tier; the word [error:], and the mark of an error *)
  | Warn
      (** the tier [warn], and the mark and its label of a finding at that tier;
          the word [warning:] *)
  | Headline
      (** the class in a headline with no tier, and the mark and its label of a
          finding at no tier *)
  | Frame
      (** the arrows [-->] and [:::], the gutter, the line numbers, the marks
          and the labels of related places, and the sign [=] before [note:] and
          [help:] *)
  | Help  (** the words [help:] and [fix:] *)
  | Inserted  (** an inserted line, and the sign [+] *)
  | Removed  (** a removed line, and the sign [-] *)
  | Note  (** the word [note:] *)
  | Plain  (** paths, details, faults, actions, and source lines *)

val of_tier : Finding_class.tier option -> element
(** [of_tier tier] is [Block] for [Some Block], [Warn] for [Some Warn], and
    [Headline] for [Some Off] and [None]. *)

val string : element -> string Fmt.t
(** [string element] prints a string with the style of [element]. With the style
    renderer [`None], it prints the string alone. *)

(** The value of the option [--color]. *)
type setting =
  | Auto  (** color by the environment and by the stream *)
  | Always  (** color *)
  | Never  (** no color *)

val color : setting -> getenv:(string -> string option) -> terminal:bool -> bool
(** [color setting ~getenv ~terminal] is [true] when an output stream gets
    color. [getenv name] is the value of the environment variable [name], or
    [None] when it is not set. [terminal] is [true] when the stream is a
    terminal. The first rule that matches decides:

    + [setting] is [Always]: color. [setting] is [Never]: no color.
    + [NO_COLOR] is set and not empty: no color.
    + [CLICOLOR_FORCE] is set and not ["0"], or [FORCE_COLOR] is set and not
      empty: color.
    + [TERM] is ["dumb"], or [CLICOLOR] is ["0"]: no color.
    + Otherwise: color when [terminal] is [true]. *)

val renderer : bool -> Fmt.style_renderer
(** [renderer color] is [`Ansi_tty] when [color] is [true], and [`None]
    otherwise. *)

val prepare : Format.formatter -> Fmt.style_renderer -> unit
(** [prepare ppf renderer] gives [ppf] the style renderer [renderer], and a
    margin that no line reaches, so that [ppf] never breaks a line. *)

val formatter : out_channel -> color:bool -> Format.formatter
(** [formatter channel ~color] is a new formatter that writes to [channel], with
    the style renderer {!renderer} of [color], and with a margin that no line
    reaches, so that the formatter never breaks a line. The caller flushes it.
*)
