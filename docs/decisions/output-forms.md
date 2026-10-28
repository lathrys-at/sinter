<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Print findings in a full form, a brief form, and JSON
@decision output-forms
@cites related-places
@cites structured-fixes
`check` prints its findings in the full form by default, in the brief form with `-o brief`, and as JSON with `-o json`; a summary, and only the warnings that change the result, go to standard error.

## Context

`check` printed one line for each finding, and a second `fix:` line
when it knew the repair. The line named the place, the tier, the class,
the subject id, and the detail. It did not show the source, which part
of the tag was at fault, or the places that explain the finding. A run
ended with no summary, and a run with no findings printed nothing.
Every run printed the base on standard error, and a warning about a
missing ledger with a `git fetch` command that fails when the remote
has no ledger either. Sinter's own repository printed 24 `untraced`
warnings for `spec/ledger.md` on every pull request. Two kinds of
reader use the text: people at a terminal, and the hooks, scripts, and
agents that read short lines. rustc and ruff serve both with a full
form and a short form.

## Decision

- `check` has the forms `full`, `brief`, and `json`. The option
  `-o`/`--output` selects one, and `full` is the default. The form
  never depends on whether the output is a terminal. `-o json` takes
  the place of `--json`, and its records do not change. A later step
  adds `porcelain`, a form for programs that never changes.
- The full form follows the layout of rustc. The headline is
  `tier[class]: detail` at a gate, and `class: detail` without a gate.
  Under it come the location, the source lines, a mark under the part
  of the tag at fault with its label, the related places with their
  labels, and the fix as a help line and a diff of the edits.
- The brief form is one line for each finding,
  `path:line:col: tier[class] detail`, and an indented second line
  `  fix: <text>` for a finding with a fix. It shows no related places.
  It is for people, and it can change between versions.
- The text forms do not show the subject id. The JSON form keeps it.
  A detail names the item it is about.
- A summary goes to standard error, for example
  `8 findings in 2 files: 7 block, 1 warn; 4 have a fix`. Without a
  gate it gives no counts by tier. A run with no findings prints
  `no findings in N files`. `-q` removes the summary. The JSON form has
  no summary.
- The base shows only with `-v`, with a short hash. The warning about
  the ledger shows only when the ledger is absent and a plan exists,
  and it gives no command; the help says how to fetch the ledger.
- In the full and brief forms, the findings of the classes `untraced`,
  `unmet-promise`, and `awaiting-approval` fold into one line for each
  class and file, with a count. A class does not fold when it blocks
  at the gate, or under `--strict`. A note on standard error says how
  many findings are folded and ends "use -v to list each one". `-v`
  lists each finding. The JSON form gives every finding.

## Alternatives considered

- **One text form, one line for each finding.** Not chosen: a person
  never sees the source line or the part that is wrong.
- **The full form on a terminal, and the brief form elsewhere.** Not
  chosen: one command would print different text in a terminal and in
  a script, which surprises people and makes reports hard to compare.
- **Findings grouped under each file name.** Not chosen: a line no
  longer starts with its path, so an editor cannot jump to it, and the
  form shows no source.
- **A status code first in the brief form**, as git's short status
  does. Not chosen for the brief form: that layout became the
  porcelain form, a separate contract, and the brief form keeps the
  location first so that editors read it with no setup.
- **A `[*]` marker on the brief line in place of the fix line**, as
  ruff does. Not chosen: the brief form would not show what the fix
  is.
- **The fix at the end of the brief line.** Not chosen: the lines get
  long, and a fix with alternatives makes them longer.
- **The summary on standard output.** Not chosen: `grep` and `wc -l`
  would see it, and standard output would no longer hold only
  findings.
- **The base and the ledger lines on every run, shorter.** Not chosen:
  the base is nearly always the one a person expects, so the line is
  noise.
- **Neither line without `-v`.** Not chosen: a person would not learn
  why a finished plan still reports findings.
- **One line for each finding of every class.** Not chosen: a long
  list of warnings that never changes teaches readers to skip
  warnings.
- **Fold any class above a threshold.** Not chosen: the output changes
  shape at the threshold, and it can fold findings that block.
- **Group the findings by class without folding.** Not chosen: the
  lines get shorter, but there are as many.

## Consequences

The hooks, the help, and the design notes name `-o brief` and
`-o json`. The fixtures of `check` change on standard output and on
standard error. The full form needs the source lines of the findings
and of their related places, so it reads those files again when it
prints. A finding that blocks never folds, so a fold never hides the
reason for exit code 1. Programs read `-o json`, and later
`-o porcelain`, and never parse the full or the brief form.
