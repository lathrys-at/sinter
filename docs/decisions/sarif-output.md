<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Write the findings as SARIF at a gate, for code scanning
@decision sarif-output
@cites output-forms
@cites exit-codes-by-gate
@cites related-places
@cites structured-fixes
@cites json-handling
`sinter check -o sarif` writes the findings of one gate as one SARIF 2.1.0 run, with a rule and a sentence for each finding class and the finding id as a fingerprint of its own.

## Context

SARIF 2.1.0, the Static Analysis Results Interchange Format, is the
OASIS standard that GitHub code scanning and other tools read. A
SARIF result needs a level, `warning` or `error`, and a finding has a
tier only at a gate. GitHub requires three texts for each rule, and
Sinter had no text for people for its finding classes. GitHub matches
the results of two uploads by a hash of about 100 characters from the
start of the result's line, which its upload action computes. GitHub
compares each upload with the last one of the same tool and category,
and on a pull request it shows an alert only when all of its lines
are in the diff. The design notes mapped a finding to SARIF before the
structured fixes and the related places existed.

## Decision

- `-o sarif` writes one SARIF 2.1.0 run on standard output. It needs
  `--gate`; without a gate, the command stops with exit code 2.
- The level of a result is its tier at the gate: `warn` is `warning`,
  and `block` is `error`. `--strict` changes the exit code and not the
  level.
- Each finding class is a rule, in the order of the classes, with one
  sentence for people in all three texts that GitHub requires. The
  sentence is in the code, and a test checks that every class has one.
  The same sentence is what `sinter explain --short <class>` will
  print.
- `partialFingerprints["sinterFindingId/v1"]` holds the finding id.
  Sinter writes no `primaryLocationLineHash`; GitHub's upload action
  adds it.
- SARIF is written in tree mode and in diff mode. The help says that
  an upload to GitHub is a run in tree mode.
- The mapping lives in the interface of the writer and in the help,
  not in a specification of its own. The design notes give it in
  short.

## Alternatives considered

- **Without a gate, every result is `warning`, or the result has no
  level.** Not chosen: the difference between `warn` and `block` is
  lost, and nothing shows it.
- **Under `--strict`, every result is `error`.** Not chosen: the level
  then no longer shows the tier. The job fails on the exit code in
  any case.
- **`primaryLocationLineHash` from the finding id, or computed with
  GitHub's algorithm.** Not chosen: the first is not how GitHub
  documents the key, and its upload action warns on every result; the
  second reads every file and gives the same identity on GitHub.
- **SARIF in tree mode only, or in diff mode with every finding of the
  tree and a `baselineState`.** Not chosen: the first drops a form
  that other readers can use; GitHub documents no use of
  `baselineState`.
- **The sentence of each class in `spec/algebra.md`, or a generated
  text with a link.** Not chosen: the first needs a change of the
  specifications for this step; the second tells the reader of an
  alert nothing, and no stable URL exists yet.
- **A specification of its own for the SARIF mapping, as for the
  porcelain form.** Not chosen: the rules of the format belong to
  OASIS and GitHub.

## Consequences

CI uploads one file and gets an alert for each finding, with its
place, its related places, and its fixes. An edit of the text after a
tag line can close an alert and open a new one, because GitHub
matches by its own hash. Each branch that adds a finding class adds
its sentence. A renamed class closes its alerts and opens new ones.
The mapping has no version of its own; only the fingerprint key
carries one.
