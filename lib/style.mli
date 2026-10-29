(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The styles of the elements that the full and brief forms print, and the
    style renderer of each output stream. *)

(** An element of the output. *)
type element =
  | Block
      (** the tier [block], and the mark and its label of a finding at that tier
      *)
  | Warn
      (** the tier [warn], and the mark and its label of a finding at that tier
      *)
  | Headline
      (** the class in a headline with no tier, and the mark and its label of a
          finding at no tier *)
  | Frame
      (** the arrows [-->] and [:::], the gutter, the line numbers, the marks
          and the labels of related places *)
  | Help  (** the words [help:] and [fix:] *)
  | Inserted  (** an inserted line, and the sign [+] *)
  | Removed  (** a removed line, and the sign [-] *)
  | Note  (** the word [note:] *)
  | Plain  (** paths, details, and source lines *)

val of_tier : Finding_class.tier option -> element
(** [of_tier tier] is [Block] for [Some Block], [Warn] for [Some Warn], and
    [Headline] for [Some Off] and [None]. *)

val string : element -> string Fmt.t
(** [string element] prints a string with the style of [element]. With the style
    renderer [`None], it prints the string alone. *)

(** An output stream. *)
type stream = Output  (** standard output *) | Errors  (** standard error *)

val renderer : stream -> Fmt.style_renderer
(** [renderer stream] is the style renderer of [stream]. It is [`None] for both
    streams. *)

val prepare : Format.formatter -> Fmt.style_renderer -> unit
(** [prepare ppf renderer] gives [ppf] the style renderer [renderer], and a
    margin that no line reaches, so that [ppf] never breaks a line. *)

val formatter : out_channel -> stream -> Format.formatter
(** [formatter channel stream] is a new formatter that writes to [channel], with
    the style renderer {!renderer} of [stream], and with a margin that no line
    reaches, so that the formatter never breaks a line. The caller flushes it.
*)
