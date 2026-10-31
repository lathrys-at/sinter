<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Print the porcelain form as fields separated by tabs, with headers by request
@decision porcelain-format
@cites output-forms
@cites color-settings
`check -o porcelain` prints one line for each finding, with its fields separated by tabs and quoted by a fixed rule, or ended by NUL with `-z`; it prints the header `# porcelain 1` and only the other headers that `--headers` names; and `spec/porcelain.md` specifies it.

## Context

The record `output-forms` gives `check` a full form and a brief form
for people, and JSON for programs. It promises a fourth form,
`porcelain`, for scripts: a status code first, fields at fixed
positions, no color, and a layout that never changes. A finding has
two fields of free text: the path and the detail. A path can hold a
space, a tab, or a new line. A detail always holds spaces and can hold
a tab. `git status --porcelain=v2` puts the path last, quotes an
unusual path with C escapes, and has a mode `-z` with NUL in the place
of each separator. It prints its header lines only when an option asks
for them, and its readers must ignore a header line that they do not
know. A setting of git changes how git quotes some paths.

## Decision

- `-o porcelain` prints version 1 of the porcelain form. Its layout
  never changes. A layout that a reader of version 1 cannot read gets a
  new name, and `porcelain` keeps version 1.
- Each finding is one line. The form never folds findings, and it has
  no color, not even with `--color=always`.
- A tab separates two fields. A field that holds a control character,
  `"`, or `\` is written in double quotes with C escapes. A space never
  causes quotes. The rule is fixed in Sinter, and no setting changes
  the bytes. An empty field means that the finding has no value there.
- With `-z`, a NUL ends each field and each line. A field that holds
  a NUL or starts with `"` is quoted by the same rule; every other
  field is written as it is.
- By default the only header line is `# porcelain 1`, and it comes
  first. The option `--headers=<names>` adds the named header lines,
  in the order of the specification. `--no-headers` prints no header
  line, not even `# porcelain 1`. The names of version 1 are `base`,
  `ledger`, `gate`, `mode`, and `tool`. A later version of Sinter adds a
  header as a new name for `--headers`, and that is not a new porcelain
  version. A reader ignores a header line that it does not know.
- `spec/porcelain.md`, a seventh specification, gives the fields, the
  quoting, the headers, and what a reader must accept.

## Alternatives considered

- **A space between fields, with the detail last**, as in
  `git status --porcelain=v2`, and quotes on every path that holds a
  space. Not chosen: many real paths hold spaces, so quoted paths would
  be common, and every reader would have to handle quotes.
- **No `-z` mode in version 1.** Not chosen: with `-z` in the first
  version, a script never has to find out whether its Sinter has it.
- **With `-z`, every field as it is, a NUL included.** Not chosen: a
  field that holds a NUL would read as two fields, so the line could
  not be read. A manifest string can hold `\u0000`, and a
  `config-changed` subject holds that string.
- **A manifest error for a string with a NUL.** Not chosen: the form
  must print every finding that the scan makes, whatever the
  manifest holds.
- **An environment error when `-z` would write a NUL in a field.**
  Not chosen: the run could not print its findings.
- **With `-z`, quotes only on a field that holds a NUL.** Not chosen:
  a field written as it is can start with `"` and hold `\`, so a
  reader could not tell it from a quoted field.
- **Two headers, `base` and `ledger`, always printed after
  `# porcelain 1`.** Not chosen: each run would look up the ledger, and
  a script that reads only findings would have to skip lines that it
  did not ask for.
- **More headers always printed**: `base`, `ledger`, `gate`, `mode`,
  and `tool`. Not chosen: the value of `tool` changes with each build,
  and `gate` and `mode` repeat the command line.
- **All headers only on request, as in git.** Not chosen: the version
  line would not be there by default, so a script could not check it.
- **The porcelain form as a section of `spec/jsonl.md`.** Not chosen:
  the name and the title of that file say JSON lines, and its stability
  rule, the field `v`, does not apply to the porcelain form.

## Consequences

A script reads a line with `IFS=$'\t' read -r` or `awk -F'\t'`, and it
must undo the quotes only on the rare field that has them. A script
that asks for a header that its version of Sinter does not know gets a
usage error, not less output. The count of the specifications becomes
seven. The tests fix the bytes of the form, so a change to the layout
fails them.
