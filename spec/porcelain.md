<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: porcelain form

Status: draft. The seven specifications share one version; see [docs/versioning.md](../docs/versioning.md).

## 1. Introduction

`sinter check -o porcelain` prints the findings of a check for a
script: one line for each finding, with its fields at fixed positions,
and header lines. This document defines version 1 of the porcelain
form. It is normative, except for the parts that it marks as
informative.

The fields of a finding take their meaning from the finding record of
[jsonl.md](jsonl.md) section 8. The JSON form gives more about each
finding, such as its fix and its related places.

## 2. Version and stability

The name `porcelain` of the option `-o` names version 1 of the form.
The layout of version 1 never changes. The **layout** is all of these:

- the nine fields of a finding line, their order, and their meaning;
- the separators and the end of a line, with and without `-z`;
- the quoting rule;
- the words of the tier field;
- the order of the finding lines;
- the form of a header line, the version line `# porcelain 1`, the
  five header names of section 7, and the meaning of their values.

A layout that a reader of version 1 cannot read gets a new name for
the option `-o`. The name `porcelain` keeps version 1.

A later version of Sinter can do these things in version 1, and a
reader must accept them (section 8):

- add a finding class, which a finding line names in its field
  `class`;
- add a header name for `--headers`. The tool prints such a header
  only when `--headers` names it.

No setting, no environment variable, and no terminal changes the bytes
of the output. The output has no color, not even with
`--color=always`.

## 3. The output

Standard output holds the header lines first (section 7), and then
one finding line for each finding of the check (section 4). It holds
nothing else. A check with no findings prints the header lines only.

The finding lines are sorted by the fields `path`, `line`, `col`, and
`id` of the finding record ([jsonl.md](jsonl.md) section 8), each
string in byte order. A finding with no place comes after every
finding with a place, and two findings with no place are sorted by
`id`. Two runs on the same inputs print the lines in the same order.

Each finding has one line. The form never folds findings, with or
without `-v` or `--strict`. With `--gate`, the form prints the
findings that the check reports at that gate
([manifest.md](manifest.md) section 11.1); without `--gate`, it
prints every finding.

## 4. The finding line

A finding line holds nine fields, in this order:

| # | field | value |
|---|---|---|
| 1 | tier | `block` or `warn`: the field `tier` of the finding record, with `--gate`; `none` without `--gate` |
| 2 | class | the field `class`: the finding class ([algebra.md](algebra.md) section 9) |
| 3 | path | the field `path` |
| 4 | line | the field `line` |
| 5 | col | the field `col` |
| 6 | end line | the field `eline` |
| 7 | end col | the field `ecol`, the exclusive end column |
| 8 | subject | the field `subject`: the subject id |
| 9 | detail | the field `detail` |

Lines and columns count as [jsonl.md](jsonl.md) section 3 says: from
1, and a column counts Unicode code points. A number is written in
decimal, with no sign and no leading zero.

An empty field means that the finding has no value there. A finding
with no place has empty fields 3 to 7. A finding with no detail has an
empty field 9. The tier field is never empty.

One tab (0x09) stands between two fields, and a line feed (0x0A) ends
the line. No other byte separates two fields. A line therefore holds
eight tabs and one line feed.

The tier, the class, and the numbers never need quotes: a tier or a
class is lowercase ASCII letters and `-`.

## 5. Quoting

A field is **quoted** when it holds one of these bytes: a byte below
0x20, the byte 0x7F, `"` (0x22), or `\` (0x5C). Every other field is
written as it is. A space never causes quotes. Each byte from 0x80 up
is written as it is.

A quoted field is written as `"`, then each byte of the field as this
table gives it, then `"`:

| byte | written as |
|---|---|
| 0x22 `"` | `\"` |
| 0x5C `\` | `\\` |
| 0x07 | `\a` |
| 0x08 | `\b` |
| 0x09, the tab | `\t` |
| 0x0A, the line feed | `\n` |
| 0x0B | `\v` |
| 0x0C | `\f` |
| 0x0D, the carriage return | `\r` |
| every other byte below 0x20, and 0x7F | `\` and three octal digits of the byte, for example `\000`, `\033`, or `\177` |
| every other byte | the byte |

A quoted field therefore holds no tab and no line feed. A field that
is written as it is never starts with `"`.

A reader undoes the quotes of a field in these steps:

1. When the field does not start with `"`, its value is the field.
2. Otherwise, remove the first and the last byte, which are both `"`.
3. Read the rest from left to right. A `\` and one of the characters
   `"`, `\`, `a`, `b`, `t`, `n`, `v`, `f`, or `r` stand for the byte
   of the table. A `\` and three octal digits stand for the byte of
   that value. Every other byte stands for itself.

The detail is quoted from the text that the finding record holds in
its field `detail`.

This paragraph is informative. The rule is the C-style quoting that
git uses for a path when its setting `core.quotePath` is `false`.
Sinter fixes the rule, and no setting of git changes it.

## 6. The mode `-z`

With the option `-z`, a NUL byte (0x00) ends each field, the last
field of a line included. No tab and no line feed separate the fields
or end the line. Each header line ends with a NUL byte in the place of
its line feed.

With `-z`, a field that holds a NUL byte or starts with `"` is quoted
as section 5 says. Every other field is written as it is, so it can
hold a tab or a line feed. A reader undoes the quotes of a field
exactly when the field starts with `"`, in the steps of section 5.

A reader reads the output as a sequence of items, each ended by a NUL
byte. An item that starts with `#` is a header line. Any other item is
the tier field of a finding, and the next eight items are the other
fields of that finding. The tier never starts with `#`.

`-z` without `-o porcelain` is an error of the command line.

## 7. Headers

A **header line** is `#`, a space, the name of the header, a space,
and the value, and then a line feed, or a NUL byte with `-z`. No value
holds a space, a tab, or a line feed, so a header line is never
quoted.

By default, the output holds one header line, `# porcelain 1`, and
it comes first. Its value is the version of the form.

The option `--headers=<names>` names more headers. `<names>` is a list
of header names separated by commas. The option can be given more than
once, and the lists join. Each named header prints once, after
`# porcelain 1`, in the order of this table, whatever the order of the
command line:

| name | line | value |
|---|---|---|
| `base` | `# base <commit>` | the object id of the base commit, as the field `base` of the `index` record ([jsonl.md](jsonl.md) section 10) |
| `ledger` | `# ledger <commit>` | the object id of the commit that the ref `refs/sinter/ledger` names ([ledger.md](ledger.md)), or `none` when the ref names no commit |
| `gate` | `# gate <gate>` | `turn`, `review`, or `merged`, as `--gate` names it; `none` without `--gate` |
| `mode` | `# mode <mode>` | `tree` or `diff`, as the field `mode` of the `index` record |
| `tool` | `# tool <version>` | the version of the tool, as the field `tool` of the `index` record |

An object id is lowercase hex: 40 characters, or 64 in a repository
that uses git's SHA-256 object format. The tool reads the ledger ref
only when `--headers` names `ledger`. When git fails to read the ref,
the command stops with exit code 3.

The option `--no-headers` prints no header line, not even
`# porcelain 1`.

These are errors of the command line:

- `--headers` and `--no-headers` together;
- `--headers`, `--no-headers`, or `-z` without `-o porcelain`;
- a name in `--headers` that is not a header name of the table. No
  name stands for all the headers.

## 8. Readers

A reader of version 1 must accept these:

- a header line whose name it does not know. The reader ignores the
  line;
- a finding class that it does not know;
- a later version of Sinter that adds a header name.

A reader of version 1 can rely on these:

- the nine fields of a finding line, in their order;
- the tier words `block`, `warn`, and `none`;
- the quoting rule of section 5, and the items of section 6;
- the order of the finding lines;
- the line `# porcelain 1` first, unless `--no-headers` is given.

A reader that asks for a header with `--headers` gets that header, or
an error of the command line from a version of Sinter that does not
know the name.

## 9. Streams and exit codes

Standard output holds only the header lines and the finding lines.
Standard error holds what it holds for `-o json`: the warnings and the
errors. It never holds the summary, the note on folded findings, or
the note that names the base, with or without `-v` and `-q`.

The form does not change the exit code: `sinter check -o porcelain`
exits with the code that `sinter check` gives in its other forms. For
example, a finding that blocks at the gate gives code 1
([manifest.md](manifest.md) section 11.1).

