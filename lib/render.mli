(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The full form of a finding: a headline, the location, and the source lines
    of the place with a mark under the part at fault. *)

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
    + The snippet of the place, when {!Source.line} gives the first line of the
      place and the mark falls inside that line: an empty gutter line ([W + 1]
      spaces and [|]), the source line (its number right-aligned in [W], [ | ],
      and its text), the mark line, and an empty gutter line. A place of more
      than one line adds a line [...] after its mark line.

    The mark line is [W + 1] spaces, [| ], spaces up to the mark, the mark, and
    a space and the label when the mark has one. The mark is [^] under
    {!Finding.t.mark} with its label; with no mark, it is [^] under the place on
    its first line, to the end of that line when the place goes on, with no
    label. A mark starts at the {!Display.column_width} of its first column, and
    is as wide as the display width of the text that it marks, and at least 1. A
    mark falls outside its line when it starts or stops after the column past
    the last character of the line. *)
