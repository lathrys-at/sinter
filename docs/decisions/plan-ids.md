<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Give each plan an id, and free a plan's slug when it closes
@decision plan-ids
@cites plans-span-branches
A plan's slug is reserved only while the plan is open, and each plan carries an id from its creation, written `@plan upkeep@3f2a9c`, so that a closed plan and a new one with the same slug never mix.

## Context

A plan slug was permanent, so a general name such as `upkeep` was taken
for ever by the first plan that used it. Work of the same kind comes
back, and its natural name comes back with it. But the ledger files
every entry about a plan under the plan's name, so a new plan with an
old name would inherit the old plan's entries, and a diff could not
tell an old plan file from a new one.

## Decision

- A plan's slug is reserved while the plan is open. Two open plans
  with one slug are a `duplicate`.
- When the plan closes, its slug is free again. Its file and journal
  may leave `.plans/`; moving or deleting them is tidying.
- Each plan has an id from the moment it is created: six hex digits
  that the tool or the plan skill generates. The plan file writes it
  in its first tag line, after the slug and an `@`:
  `@plan upkeep@3f2a9c`. A plan line without an id is a finding whose
  fix supplies one. Two files with one full form are a `duplicate`.
- The bare slug means the open plan, in tags, in commands, and in
  conversation. The ledger names a plan by the full form, and the tool
  prints the full form for a closed plan.

## Alternatives considered

- **Keep slugs permanent, and check for a taken slug earlier.** Not
  chosen: it finds a collision sooner but leaves every general name
  taken for ever.
- **A date in every slug**, such as `2026-10-upkeep`. Not chosen:
  every mention of every plan is longer for ever, and done plans still
  pile up in `.plans/`.
- **A sequence number in every slug**, as many decision-record systems
  use. Not chosen: two branches that start at once take the same
  number.
- **Take the id from the ledger entry that opens the plan.** Chosen
  first, then replaced: a new plan has no id until that entry exists,
  and reads as its closed predecessor until then; a repository that
  does not require approval of plans writes no such entry; and the
  tree alone cannot tell an old plan file from a new one.

## Consequences

The tree names every plan exactly, without the ledger, and a short
general name can return each time its kind of work does. The tag
target of `@plan` gains the form `slug@id`, and the specifications of
plans and of the ledger must define it, its parse rule, and the ids of
leases.
