<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Print every failure as an error and a help line
@decision error-layout
@cites output-forms
@cites color-settings
Every run that fails before it can report findings prints `error:` with the fault and `= help:` with the action, a manifest error shows its source line, and usage errors from the command line library take the same layout.

## Context

A run fails with exit code 2 when the command line is wrong, and with
exit code 3 when Sinter cannot run in the environment. Sinter printed
its own errors as one line, `sinter: <fault>; <action>`, so the action
was hidden after a semicolon. A manifest error gave its place, but not
the line. Usage errors came from the library cmdliner, in its own
layout: a usage line, then `sinter: <fault>`, broken at 80 columns.
cmdliner 2.1.1 gives its error only as text, not as data. It writes
escape codes into its text when `TERM` is set and `NO_COLOR` is not,
also when its output is not a terminal, and Sinter cannot turn that
off. The full form of `output-forms` already prints `help:` and
`note:` lines in the layout of rustc, which prints `error:` with no
tool name.

## Decision

- Every failure prints on standard error a headline `error: <fault>`
  and a line `  = help: <action>`. No line starts with `sinter:`.
- An error at a place in the manifest shows the source line in the
  layout of the full form: the location, the line, and a mark under
  the key or the value at fault. Each error is a block, in the order
  of the places.
- For a usage error, Sinter collects the text of cmdliner on one line,
  removes its escape codes, and prints the message after `error:` and
  the usage line after `= help:`. A part that cmdliner made bold gets
  quotes, as cmdliner writes it without escape codes. The words of
  cmdliner stay.
- `error:` and `= help:` take their colors from `color-settings`.

## Alternatives considered

- **`sinter: <fault>; <action>` everywhere.** Not chosen: errors would
  not look like findings, and the action stays hidden after a
  semicolon.
- **The new layout for Sinter's own errors only, and cmdliner's layout
  for usage errors.** Not chosen: two layouts, `sinter: unknown option`
  beside `error: no sinter.toml`.
- **`sinter:` before `error:`**, so that a reader knows which tool
  spoke when a hook mixes the output of several tools. Not chosen: the
  help lines name Sinter's commands, and rustc, cargo, and git print
  `error:` alone.

## Consequences

Each error of Sinter has a fault and an action, and a test checks that
no error lacks the action. A new release of cmdliner can change its
text or its escape codes; the tests of the usage errors fail then, and
the layer that reads the text needs a change. `spec/manifest.md`
section 4 reports each manifest error as a block, not as one line.
