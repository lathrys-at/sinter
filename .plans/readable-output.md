# Readable output
@plan readable-output@222f5a
@scope spec/**, docs/**, lib/**, bin/**, test/**, bench/**, plugins/**, .claude-plugin/**, dune-project, sinter.opam, sinter.opam.locked, THIRD_PARTY.md, .plans/**, sinter.toml, .github/workflows/**, CLAUDE.md
Make the output of Sinter clear for people and stable for programs:
plain names for the finding classes, findings that show the source
and their fix, a full and a brief text form, errors in one layout,
color, and at the end a porcelain form for scripts.

## Rename the finding classes and their words
@scope spec/**, docs/**, lib/**, bin/**, test/**, bench/**, plugins/**, .claude-plugin/**
@decision plain-names
Rename 20 finding classes, for example `disendorsed` to `retired` and
`uncovered` to `untraced`, and the words under them: "stamp" becomes
"approval", "owed" becomes "obligation", "discharge" splits into
"completed", "meet", `expect`, and "accept", "lease" becomes "claim",
"residue" goes, and a `@supersedes` edge is "effective".

## Rename the settings of the manifest and the gates
@scope spec/**, docs/**, lib/**, bin/**, test/**, bench/**, plugins/**, .claude-plugin/**, sinter.toml, .github/workflows/**
@decision manifest-names
Give each setting of the manifest a name with one meaning: `spec`
becomes `sinter-spec`, `target` becomes `default-branch`, `scan.refs`
becomes `scan.namespaces`, `rollout-cap` becomes `warn-only`,
`harness-markers` becomes `agent-markers`, and `coverage-attribution`
becomes `test-coverage`. Merge `plan.ambient` and `plan.shared` into
`plan.exempt`, give each test runner one table under `runners`, call a
ref an "external id", and rename the gates `merge` and `target` to
`review` and `merged`.

## Show the parts of a tag and the related places
@scope lib/**, test/**, spec/**, docs/decisions/**
@decision related-places
Record the span of the tag word, the target, and the revision of each
tag, and let a finding carry related places, each with a label. The
JSON carries the related places.

## Structure the fixes
@scope lib/**, bin/**, test/**, spec/**, docs/decisions/**
@decision structured-fixes
Make each fix a help message and one or more edits, each a path, a
span, and the new text, with alternatives where a person chooses. The
JSON carries the edits.

## Render the full and brief forms
@scope lib/**, bin/**, test/**, spec/**, docs/**, dune-project, sinter.opam, sinter.opam.locked, THIRD_PARTY.md
@decision output-forms
@decision own-renderer
Render findings with Sinter's own renderer on `fmt`: the full form by
default, with source, labels, and fixes; `-o brief` with one line per
finding and an indented fix line; and `-o json`. Add the summary on
standard error, the warning about a missing ledger, and the folding of
the incompleteness classes.

## Print errors in one layout and in color
@scope spec/**, lib/**, bin/**, test/**, docs/**
@decision color-settings
@decision error-layout
Print every failure as `error:` and `help:`, usage errors included.
Color the output with the 16 base colors, under `--color`, `NO_COLOR`,
`CLICOLOR_FORCE`, `FORCE_COLOR`, and `TERM`. Name these variables and
the way to fetch the ledger in the help.

## Write the porcelain form
@scope spec/**, lib/**, bin/**, test/**, docs/**, CLAUDE.md
@decision porcelain-format
Specify and print `-o porcelain`: a status code first, fixed columns,
header lines, no color, and no change between versions.
