<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Draw the text forms with Sinter's own renderer on `fmt` and `uucp`
@decision own-renderer
@cites output-forms
@cites current-dependencies
Sinter draws its full and brief forms with its own code, which writes styled text through the library `fmt` and measures the width of characters with the library `uucp`.

## Context

The full form of `output-forms` needs a renderer: code that draws the
source lines, the gutter, the marks, the labels of related places, and
the fix as a diff, with color when color is on. Sinter built its text
with `Printf` and `Buffer`, and depended at run time only on
`cmdliner`, `yojson`, and `unix`. One OCaml library, grace, draws this
kind of output. A mark must start under the first character of the
part at fault and be as wide as that part. A Chinese character or an
emoji takes two columns of a terminal, a combining accent takes none,
and a tab has no fixed width. rustc and ruff measure the width in
columns. The table of widths changes with each version of Unicode.
The reader of Markdown keeps no text of a file after it reads the
file.

## Decision

- Sinter writes its own renderer for the full and brief forms. The
  renderer writes through `fmt` (ISC), which gives styled text and
  writes no escape codes when its style renderer is `None`.
- The renderer measures the display width of a character with `uucp`
  (ISC). A tab prints as 4 spaces. The column in a location stays a
  count of characters.
- Sinter decides itself when to use color, because `fmt` does not read
  `NO_COLOR`.
- The renderer reads again the files that hold a finding or a related
  place, once each, when it prints. A file that is missing, a line
  past the end of a file, or text that is not UTF-8 gives the headline
  and the location with no source line.

## Alternatives considered

- **grace.** Not chosen: it brings four more packages and the `ppxlib`
  build stack, its layout is not the rustc layout, it draws no fix
  diffs, and each new release could change the bytes of Sinter's
  output, which the tests fix.
- **A renderer with no new library**, which writes the escape codes
  itself and tests for a terminal with `Unix.isatty`. Not chosen: `fmt`
  gives tested styled output for the cost of one small library.
- **A table of widths of Sinter's own.** Not chosen: each new version
  of Unicode would need a manual check, and an error would put a mark
  in the wrong place, where few readers would notice it.
- **One column for each code point.** Not chosen: on a line with wide
  or combining characters, the marks point to the wrong place.
- **Keep the text of every file from the scan until the output.** Not
  chosen: it holds about 3.5 MB at 10,000 declarations and about 35 MB
  at 100,000 for every run, while a second read costs only for the
  files that have findings, about 0.1 s at 10,000 declarations.

## Consequences

`fmt` and `uucp` are runtime dependencies of the package, with rows in
`THIRD_PARTY.md`, and they move to each new release under
`current-dependencies`. The binary grows by about 1.5 MB, most of it
the tables of `uucp`. A new release of `uucp` can change the width of
a character, and so the bytes of the output for that character. The
renderer is Sinter's own code, so the coverage and mutation checks
cover it. A clean run reads no file twice.
