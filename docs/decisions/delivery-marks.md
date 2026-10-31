<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Mark a delivered step in the plan file
@decision delivery-marks
@cites plans-span-branches
@cites agent-statements
A branch that delivers a step adds the line `@delivered <hash>` to the step in the plan file, tied by the step hash to the step's scope, promises, and text.

## Context

A plan spans several branches (record `plans-span-branches`). Sinter
must know which steps a branch delivers, and on the default branch it
must know which steps are delivered. For a step with promises, the
promises show it. A step without promises states its work only in its
text. The rule "a step without promises is done when a change touched
its scope" worked on a branch, where Sinter sees the diff. On the
default branch, Sinter sees no diff, so it needed a memory of each
merge. A step with a broad scope, such as `lib/**`, also read as done
after any unrelated merge. "Release the binaries" would have read as
done after about 20 merges that released nothing. The question was not
how to guess delivery from a change, but what the evidence of a
delivery is.

## Decision

- A branch that delivers a step adds one tag line to the step in the
  plan file: `@delivered <hash>`. `<hash>` is the first 6 hexadecimal
  digits of the step hash. Sinter prints the line to add.
- The **step hash** covers the agreement of the step: its effective
  scope, its promises, and its text, normalized as for an extent hash.
  It does not cover the heading, the `@delivered` line, or the text of
  other steps. The same hash binds an approval of a step in the ledger.
- A mark counts while its hash matches the step hash. When the scope,
  the promises, or the text of the step change, the mark no longer
  counts, and Sinter reports it. The person who merges sees each mark
  and each new mark in the diff (record `agent-statements`).
- `@delivered` is a status tag, not a promise. Adding it does not
  change the plan's commitment set hash and is not an unplanned
  change.
- `proof.step` takes `"delivered"`, the default, `"approval"`, or
  `"promises"`. Under `"delivered"`, a step without promises is done
  when it has a mark that counts. The value `"change"` goes away.
- Sinter checks each mark that a branch adds: a mark on a step whose
  scope the branch did not change is a finding, and so is a mark on a
  step whose promises are not met.

## Alternatives considered

- **The completion job writes a ledger entry for each step without
  promises whose scope a merge touched.** Not chosen: it needs a new
  kind of entry, and a step with a broad scope still reads as done
  after an unrelated merge.
- **Sinter reads the git history of the default branch since the step
  appeared.** Not chosen: the history becomes a sixth input of the
  algebra, a check slows as the history grows, a rewritten history
  changes the answer, and the weakness of a broad scope remains.
- **Sinter reads the `Step:` lines of the commit messages.** Not
  chosen: the lines are not designed as input, a squash merge turns
  them into body text, and a turn has no commit yet.
- **The mark in the plan's journal.** Not chosen: the journal is the
  agent's own account, and Sinter reports no findings on it.
- **A mark with no hash.** Not chosen: a later change of the step's
  scope or text would keep the step delivered with no signal.
- **A hash of git data or of the delivered work.** Not chosen: the
  merge commit does not exist when the branch writes the mark, a
  squash merge or a rebase changes commit ids, and a hash of the files
  in the scope breaks at the next unrelated edit.
- **A step hash of the scope alone.** Not chosen: for a step without
  promises, the text is the only statement of the work, so a change of
  the text changes the agreement.

## Consequences

A plan file holds its agreement and the state of its delivery. A
reader sees which steps are delivered without running Sinter. The
memory of a delivery is in the tree, so the inputs of the algebra do
not change. An edit of a delivered step's text, even a typo, voids its
mark, and someone adds the new line that Sinter prints. The vocabulary
gains a tag word.
