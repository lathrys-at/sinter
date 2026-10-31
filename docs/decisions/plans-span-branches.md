<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# A plan can span several branches and pull requests
@decision plans-span-branches v2
A plan reaches the main branch on its own, later branches each deliver some of its steps, and the plan closes when every step is done.

## Context

The specifications said that a plan belongs to one branch, and they
read an open plan on the main branch as merged before its work was
done. Every plan of this repository spans pull requests: the plan
`upkeep` reached `main` in one pull request and its seven steps in
seven more. Projects that use Sinter run work of the same size. A
reader approves such a plan once and reads it as one document.

## Decision

- A plan reaches the target branch in a pull request of its own. Its
  merge is the approval. When `proof.plan` is `"approval"`, a person
  also approves the plan in the ledger before the merge.
- A later branch delivers one or more of the plan's steps, and marks
  each one in the plan file (record `delivery-marks`). The gates
  `review` and `merged` check the steps that the branch delivers.
- A step with some of its promises met and some not is the finding
  `merged-incomplete`: a step merged in part. It is computed from the
  tree alone.
- An open plan on the target branch is normal while its work goes on.
  The plan closes when every step is done (`done()`). The job that
  closes plans imports the test evidence of its run first, so a plan
  with a `@verifies` edge in the scope of a step does not close
  without evidence. The job runs in CI or by a person's hand. It runs
  the same command either way and makes no judgment of its own.
- A delivered step keeps its slug: renaming, splitting, merging, or
  removing a delivered step is a finding. A step that no branch has
  delivered can still be renamed freely.
- A claim is an approved, open plan whose full form the current tree
  does not hold. It does not depend on a branch, and it ends when the
  plan closes.
- The specifications of plans, the ledger, and the algebra hold the
  rules.

## Alternatives considered

- **Keep one plan per branch.** Not chosen: work of several pull
  requests would become several plans, and no one document would show
  the whole piece of work that was approved.
- **Remove `merged-incomplete`.** Not chosen: no gate would then hold
  a step that is merged half done.
- **`merged-incomplete` as a delivered step that is not done, at the
  gate `merged`.** Not chosen: it reports after the merge, which is
  late.
- **A merged plan counts as approved, also when `proof.plan` is
  `"approval"`.** Not chosen: it removes the approved commitment set
  that the ledger compares a plan against.
- **A claim also needs a ledger entry when a branch starts a step.**
  Not chosen: one more approval for each branch adds to approval
  fatigue.
- **A closed plan need not be done when the job imports no evidence.**
  Not chosen: a plan whose promised test failed could close.

## Consequences

The specifications of plans need about a page of change: what a branch
delivers, what the finding for an incomplete plan means now, and when a
step without promises is done after its merge. Leases, which assumed
one branch per plan, change with it. A project that closes plans needs
a CI job that imports test evidence, a person who runs the job, or
both. Two branches that deliver steps of one plan at the same time are
not reported as an overlap; the roadmap notes it.
