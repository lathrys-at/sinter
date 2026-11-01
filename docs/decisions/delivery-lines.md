<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Name each delivered step in a commit message, and record it at the merge
@decision delivery-lines
@supersedes delivery-marks v1
@cites plans-span-branches
@cites agent-statements
@cites commit-messages
A commit that delivers a step carries the line `Delivers: <plan>/<step> <hash>`, and the job on the default branch writes a `delivered` entry in the ledger for each such line that a merge brings.

## Context

Record `delivery-marks` put a mark `@delivered <hash>` in the plan
file for each delivered step. The plan file then held its agreement
and also the state of its delivery, so it became a second ledger. A
delivery is an event of a change, and the commits of the change and
the job that runs at each merge see that event. Two problems of the
marks remained: a mark added in a later branch, with no change in the
step's scope, blocked with no way to clear it; and Sinter printed the
line to add only for a step with promises.

## Decision

- A commit that delivers a step carries a **delivery line**, one line
  of its message: `Delivers: <plan>/<step> <hash>`. `<plan>` is the
  full form of the plan, `<step>` the slug of the step, and `<hash>`
  the first 6 hexadecimal digits of the step hash. Sinter gives the
  line for each step.
- The **step hash** covers the agreement of the step: its effective
  scope, its promises, and its text, as record `delivery-marks` fixed
  it.
- On a branch, Sinter reads the delivery lines in the messages of the
  commits of the change, from the base to the head. It never reads the
  history of the default branch.
- At each push to the default branch, the job that runs there, in CI
  or by a person's hand, reads the commits that the push brings. For
  each delivery line that passes the checks, it writes a `delivered`
  entry in the ledger with the step, its step hash, and the merge. The
  job makes no judgment of its own.
- Under `proof.step = "delivered"`, a step without promises is done
  when the ledger holds a `delivered` entry that matches its current
  step hash.
- Sinter checks each delivery line of a branch. A line whose hash does
  not match, a line on a step whose promises are not met, and a step
  whose promises the branch meets with no delivery line are findings
  that block. A line on a step whose scope the branch did not change
  is a warning: the work can be in an earlier branch, and the person
  who merges reads the line.
- The plan file holds the agreement only. The tag `@delivered` goes
  away.

## Alternatives considered

- **A mark `@delivered <hash>` in the plan file** (record
  `delivery-marks`). Not chosen: the plan file becomes a second
  ledger.
- **Sinter reads the delivery lines from the history of the default
  branch.** Not chosen: the history becomes an input of every check, a
  check slows as the history grows, and a rewritten history changes
  the answer. The job reads each merge once, and the ledger keeps the
  result.
- **A delivery line on a step whose scope the branch did not change
  blocks, and an `@ack` can accept it.** Not chosen: the ack would
  need a new kind of line in a plan file or a commit, for a line that
  a person reads anyway.
- **Such a line is exempt when the base already shows the step as
  delivered.** Not chosen: it helps only steps with promises.

## Consequences

The plan file stays the agreement, and the ledger alone records what
happened. Until the job and the ledger reader exist, no step without
promises counts as done on the default branch; the checks of a branch
work now. A squash merge keeps the messages of the branch's commits in
the body of the new commit, so the job reads the delivery lines there;
a host that drops those messages from a squash loses the lines. The
inputs of a check on a branch gain the messages of the commits of the
change.
