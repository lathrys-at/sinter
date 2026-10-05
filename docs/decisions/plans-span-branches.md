<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# A plan can span several branches and pull requests
@decision plans-span-branches
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
  merge is the approval.
- A later branch delivers one or more of the plan's steps. The merge
  gate checks the steps that the branch delivers.
- An open plan on the target branch is normal while its work goes on.
  The plan closes when every step is done.
- A step that promises nothing (a refactor step) is done when a merged
  change touched its scope.
- A delivered step keeps its slug: renaming the heading of a delivered
  step is a finding. A step that no branch has delivered can still be
  renamed freely.
- The specifications of plans, the ledger, and the algebra hold the
  rules.

## Alternatives considered

- **Keep one plan per branch.** Not chosen: work of several pull
  requests would become several plans, and no one document would show
  the whole piece of work that was approved.

## Consequences

The specifications of plans need about a page of change: what a branch
delivers, what the finding for an incomplete plan means now, and when a
refactor step is done after its merge. Leases, which assumed one branch
per plan, change with it.
