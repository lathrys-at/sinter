<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Move a citation of a superseded item to its successor
@decision cite-the-successor
@cites supersession-chains
A citation of an item that another item supersedes moves to that successor, and the citing declaration takes a revision bump; no `@ack` discharges the finding.

## Context

Sinter reports a citation of a retired item as a `disendorsed` finding
(`spec/vocabulary.md` section 8.2), and an `@ack` line can accept the
finding. `sinter check` printed that `@ack` line as the fix of every
such finding. When `rust-bridge` superseded `parser-bridge`, four
records cited `parser-bridge`. An `@ack` in each would have kept their
text and their revisions, and left each one citing a record that no
longer holds.

## Decision

- When a live `@supersedes` edge retires an item, a citation of the
  item is repaired by citing its successor. The extent of the citing
  declaration changes, so it takes a revision bump, as section 9 of
  the vocabulary requires.
- No `@ack` discharges the finding of such a citation, and such an
  `@ack` is void. The finding stays until the citation moves.
- The fix of the finding names the successor. When several items
  supersede the item, the finding names each, and a person chooses.
- An item that a status tag retires has no successor. A citation of it
  takes an edit or an `@ack`, as a person decides.
- An author who supersedes an item moves its citations in the same
  change. The decision skill and `CONTRIBUTING.md` say so.

## Alternatives considered

- **An `@ack` on each citation**, the fix that `sinter check` printed.
  Not chosen: it keeps a citation of a record that no longer holds, and
  a reader who follows the citation reaches reasons that were replaced.
- **The same rule as guidance only:** the fix names the successor, and
  an `@ack` still discharges the finding. Not chosen: the shortcut
  stays, and the rule holds only where people remember it.

## Consequences

Superseding an item costs a revision bump in each declaration that
cites it. `sinter patch` (design notes, section 11.10) is the way to
make that change by machine: it prints the change as a diff for
`git apply`, and Sinter itself writes no file.
