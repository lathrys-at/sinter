(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The full form and the brief form of a finding. The full form shows a
    headline, the location, the source lines of the place with a mark under the
    part at fault, the related places with their labels, and the fix as a diff.
    The brief form shows one line, and one more for a fix. *)

val full :
  Format.formatter ->
  Source.t ->
  tier:Finding_class.tier option ->
  Finding.t ->
  unit
(** [full ppf source ~tier finding] prints the block of [finding] to [ppf], one
    line at a time, each line with its line feed. [tier] is the tier of the
    finding at the gate of the check, [None] with no gate. Each text that comes
    from the repository prints as {!Display.clean} gives it, and no line ends in
    a space.

    The lines, in order:

    + The headline: [<tier>[<class>]: <detail>] with a tier, [<class>: <detail>]
      without one, and no [": <detail>"] when the finding has no detail.
    + With a place, the location: [W] spaces, [-->], a space, and
      [<path>:<line>:<column>] of the start of the place. [W] is the number of
      digits of the largest line number that the block prints, 1 when it prints
      none.
    + The snippet of the place and of the related places in its file.
    + For each run of consecutive related places in one other file, in the order
      of {!Finding.t.related}: [W] spaces, [:::], a space, and
      [<path>:<line>:<column>] of the first place of the run; then the snippet
      of the places of the run.
    + For each related place in no file: [W + 1] spaces, [= note: ], and its
      label.
    + With a fix, the line [help: ] and {!Fix.help} of the fix, at column 0.
      Then, when each alternative of {!Fix.alternatives} has a diff, the diff of
      each alternative after an empty gutter line, and an empty gutter line
      after the last. Otherwise the line [  fix: ] and {!Fix.text} of the fix.

    The diff of one alternative takes the line of its first edit, the anchor
    line, applies the edits to it, and splits the result at its line endings. An
    alternative has no diff when {!Source.line} does not give the anchor line,
    when an edit starts or stops on another line, when a column of an edit falls
    after the column past the last character of the line, or when two edits
    overlap. The lines of the diff, with each number right-aligned in [W]:

    - when the first line of the result is the anchor line, each further line as
      an inserted line: its number from the anchor line plus 1, [ + ], and its
      text;
    - otherwise, when every edit has an empty span and the result is one line:
      [N | ] and the new line, then [W + 1] spaces, [| ], and [+] under each
      column of the inserted text;
    - otherwise: [N - ] and the anchor line, then [N + ] and each line of the
      result, numbered from [N].

    A snippet holds the first line of each of its places that {!Source.line}
    gives and whose mark falls inside that line; with no such line, the snippet
    prints nothing. It is an empty gutter line ([W + 1] spaces and [|]), then
    each line in ascending order, and an empty gutter line. A line prints its
    number right-aligned in [W], [ | ], and its text, and then one mark line for
    each mark on it: the mark of the finding first, then the marks of related
    places in their order. A line [...] stands between two lines that are not
    adjacent, and after the last line when a place on it goes on to the next
    line.

    The mark line is [W + 1] spaces, [| ], spaces up to the mark, the mark, and
    a space and the label when the mark has one. The mark is [^] under
    {!Finding.t.mark} with its label; with no mark, it is [^] under the place on
    its first line, to the end of that line when the place goes on, with no
    label. The mark of a related place is [-] under the place on its first line,
    to the end of that line when the place goes on, with its label. A mark
    starts at the {!Display.column_width} of its first column, and is as wide as
    the display width of the text that it marks, and at least 1. A mark falls
    outside its line when it starts or stops after the column past the last
    character of the line. *)

val brief :
  Format.formatter -> tier:Finding_class.tier option -> Finding.t -> unit
(** [brief ppf ~tier finding] prints the brief form of [finding] to [ppf]: the
    line [<path>:<line>:<column>: <tier>[<class>] <detail>] with a tier, and
    [<path>:<line>:<column>: <class> <detail>] without one, with the start of
    the place, and with no [" <detail>"] when the finding has no detail. A
    finding with no place starts [-:-:-: ]. A finding with a fix adds the line
    [  fix: ] and {!Fix.text} of the fix. Each line ends with a line feed. Each
    text that comes from the repository prints as {!Display.clean} gives it, and
    no line ends in a space. *)

val folded_full :
  Format.formatter -> tier:Finding_class.tier option -> Finding.t -> int -> unit
(** [folded_full ppf ~tier finding count] prints the full form of [count]
    findings of the class of [finding] in its file, folded into one line:
    [<tier>[<class>]: <count> findings in <path>] with a tier, and
    [<class>: <count> findings in <path>] without one, where [<path>] is the
    path of the place of [finding], as {!Display.clean} gives it. With no place,
    the line ends after [findings]. *)

val folded_brief :
  Format.formatter -> tier:Finding_class.tier option -> Finding.t -> int -> unit
(** [folded_brief ppf ~tier finding count] prints the brief form of [count]
    findings of the class of [finding] in its file, folded into one line at the
    place of [finding]:
    [<path>:<line>:<column>: <tier>[<class>] <count> findings in this file], or
    without the tier as {!brief} does. *)
