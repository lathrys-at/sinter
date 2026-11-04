<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Compare a pack release with the release before it by its kind
@decision pack-release-comparison
@cites pack-delivery
The packs repository checks a release against its own fixtures byte for byte, and against the fixtures of the release before it by a rule for each kind of release.

## Context

`spec/packs.md` section 2.5 lets a minor release add facts, and checks
each release against the fixtures of the release before it.
`spec/jsonl.md` section 11 compared a fixture byte for byte. The two
contradicted each other: a minor release that adds a fact can never
equal the old output. Sinter v0.1 cannot yet produce every part of a
fixture that section 11 names: the fixture ledger waits for the ledger
steps, and the coverage of each test is not designed.

## Decision

- The content of a fixture stays as section 11 gives it. The plan of
  the packs repository says which part waits for which step.
- The fixtures live in the packs repository, at
  `fixtures/<pack>/<case>/`, outside the pack root.
- A release is checked against its own fixtures, byte for byte,
  without the header line.
- A release is checked against the fixtures of the release before it,
  as that release's tag holds them. The same tool scans each such
  fixture once with each of the two releases, and it compares the two
  outputs by the kind of the new release:
  - a patch release: when the two releases fail to parse the same
    files, the located facts of each file are equal byte for byte.
    When the new release makes a file of the fixture parse that failed
    before, the rule of a minor release applies to that fixture;
  - a minor release: every node fact of the release before it is
    present with the same id, position, and extent hash;
  - a major release: no comparison.

## Alternatives considered

- **Cut the content of a fixture in section 11 to what v0.1 can
  produce.** Not chosen: the specifications describe the system that
  Sinter is meant to be. A part that v0.1 cannot produce belongs in a
  plan, not out of the specification.
- **For a patch release, keep the byte comparison of each file that
  parses in both releases.** Not chosen: when a patch release makes one
  file parse, an edge or a finding of another file can change, so the
  check refuses a correct release.
- **For a patch release, compare only the node facts.** Not chosen: a
  patch release could then change an edge with no check.

## Consequences

The minor and patch rules of section 2.5 can be checked by a program.
A fixture can change without a release of its pack. The fixtures grow
as the steps that produce each part are done.
