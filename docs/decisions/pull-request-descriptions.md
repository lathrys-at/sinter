<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Keep a pull request description to what the change carries out
@decision pull-request-descriptions
A pull request description names the plan step or the issue that the change carries out, and the records or the rules that it adds, and nothing more.

## Context

The pull requests of Sinter had long descriptions: lists of changes,
choices to review, measurements, and test results. The maintainer
reviews each pull request and found that these descriptions did not
help. The plan step, the commits, and the checks already hold that
information, and the maintainer asks when more is needed.

## Decision

A pull request description has one or two sentences:

- the plan step, with its plan file, or the issue that the change
  carries out;
- each decision record or rule that the change adds, with what it
  decides in a few words.

It holds nothing else. It follows the writing rules of
`CONTRIBUTING.md`.

## Alternatives considered

None were put forward.

## Consequences

A description takes little time to write and to read. A reviewer who
wants the details reads the commits, the plan step, and the records,
or asks the author.
