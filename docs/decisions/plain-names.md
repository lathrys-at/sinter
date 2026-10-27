<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Give the finding classes and the words under them plain names
@decision plain-names
@cites ste-adoption
Twenty finding classes and seven words of the specifications take plain names, so that each name says what it means and each word has one meaning.

## Context

The first line of every finding names its class, so a person reads
the class names more often than any other words of Sinter. A review
of all 41 names found three problems. Some names were private
coinages that a new user cannot read, such as `disendorsed` and
`rev-owed`. Some used a word that had another meaning in Sinter: one
act of approval had three words ("approve", "stamp", and "ratify"),
"discharge" had four meanings, and "uncovered" also means code
coverage, which Sinter reads too. One name, `blocked-on`, held the
tier word `block`. Some of the names were bad only because the words
of the specifications under them were bad, so the review covered
those words too.

## Decision

The finding classes take these names:

| before | after |
|---|---|
| `disendorsed` | `retired` |
| `unratified-req` | `unapproved-req` |
| `unratified-design` | `unapproved-design` |
| `unstamped` | `awaiting-approval` |
| `amendment` | `unapproved-plan` |
| `uncovered` | `untraced` |
| `blocked-on` | `waiting-on` |
| `rev-owed` | `unbumped` |
| `rule-owed` | `unmet-rule` |
| `unmet` | `unmet-promise` |
| `undischarged-plan` | `merged-incomplete` |
| `disconnected` | `unexercised` |
| `unread-tag` | `ignored-tag` |
| `unmapped-work` | `unplanned-change` |
| `lease-overlap` | `branch-overlap` |
| `bad-scope` | `scope-outside-plan` |
| `bad-target` | `invalid-target` |
| `orphan` | `wrong-source` |
| `unattributed` | `unmeasured` |
| `pack-drift` | `pack-mismatch` |

The other 21 classes keep their names.

The words of the specifications change as follows:

- "Approval" is the one word for the act, the state, and the ledger
  entry. "Stamp" and "ratify" go. The ledger entry kinds become
  `approval`, `approved-scope`, and `approved-promise`.
- "Obligation" replaces "owed": the function `owed(R)` becomes
  `obligations(R)`, and the JSON field `owed` becomes `obligations`.
- "Discharge" goes. A plan that closes with its work done is
  `completed`, under the "completion condition". Facts "meet" a
  promise. The part of a rule that clears its obligation is `expect`.
  An `@ack` "accepts" a finding.
- "Claim" replaces "lease": the claim of another branch on a scope.
- "Residue" goes. The specifications say "the facts that meet the
  promise".
- `@rejected` means "considered and not chosen", because "decline" is
  a ledger entry.
- A `@supersedes` edge that takes effect is "effective". "Live" and
  "void" keep their meaning for an ack, a decline, and a judgment.

The words "dead", "death", "born", and "die" for the life of a plan
stay only in the design notes. The specifications, the help, and the
messages of the tool say "open" and "closed".

## Alternatives considered

- **`stale-rev` for `rev-owed`.** Not chosen: a stale revision is
  what a `suspect` finding reports about a citation, so the name would
  point at the wrong thing. `unbumped` names the declaration whose
  text changed while its revision did not.
- **`unapproved` for `unstamped`.** Not chosen: it is too close to
  `unapproved-req`, which reports a citation of an item, not the item.
- **`met-when` for the part of a rule that clears its obligation.**
  Not chosen in favor of `expect`, which pairs with `trigger`.

## Consequences

The class names are part of the JSON form and of the target of an
`@ack`, so the change breaks every reader of the old names. No
repository outside Sinter used them. The records written before this
one keep the old names, because they record what was decided then.
