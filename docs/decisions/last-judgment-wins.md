<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Let the last judgment on the current text count
@decision last-judgment-wins
@cites ledger-event-log
Of the approvals and declines of a subject at its current text, the one with the greatest `seq` decides whether the subject is approved.

## Context

The specification read approvals as a set: an approval of a text
counted for as long as the ledger held it. A decline at the same text
did not end it, so a person who approved a text and then declined it
could withdraw the approval only by raising the revision. Once the
ledger is an event log with one order (record `ledger-event-log`), a
later judgment can replace an earlier one.

## Decision

- For a declaration or a step, the approvals and the declines whose
  hash is the current hash of the subject are compared, and the one
  with the greatest `seq` counts. An approval counts when it is that
  entry.
- For a plan, a decline at the current commitment-set hash is compared
  with the latest approval of the plan, and the entry with the greater
  `seq` counts. A decline at X, an approval at Y that contains X, and
  then the text X again give "approved".
- A judgment at another hash counts for nothing in this comparison.

## Alternatives considered

- **Approvals stay, as in the specification.** Not chosen: a person
  could not withdraw an approval at the same text, and a decline that
  came after an approval was dead.

## Consequences

Whether a subject is approved now depends on the order of the
entries. A decline can make the finding `unapproved-req` block work
that was approved before. The writer of an approval checks the
current state first, so it asks before it approves over a live
decline.
