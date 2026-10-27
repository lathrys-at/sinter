<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Record how each plan step was carried out in the plan's journal
@decision plan-journals
The agent that carries out a plan step writes brief entries in the plan's journal as it works, the entries are revised before the step's pull request opens, and the journal ships with the step.

## Context

The design notes (section 6.5) give each plan a journal,
`.plans/<slug>.log.md`, for what was tried and why it failed. Sinter
reads a journal as historical text: it makes no finding, and its
citations still resolve. The journals of Sinter's own plans held only
their title line. What happened while a step was carried out, such as
a rejected approach, a ruling, or a change to the fixed design, lived
only outside the repository and was lost when the work ended. A pull
request description holds only the step and the records it adds
(record `pull-request-descriptions`), so it does not carry this
either.

## Decision

- The agent that carries out a plan step appends entries to the
  journal of the step's plan as it works. Each entry is brief: a few
  lines that state one pertinent fact, such as a decision taken, an
  approach that failed and why, a deviation from the design that was
  fixed for the step, or an item left for later.
- Before the step's pull request opens, the entries are revised: wrong
  or superseded entries are corrected, and the entries are cut to what
  a later reader needs. The journal change ships in the step's pull
  request.
- Sinter joins each plan step with the journal entries for the step.
  A view of a plan shows the step and its promises, and shows the
  journal entries only on request. This part is on the roadmap and is
  not designed.

## Alternatives considered

None were put forward. The three parts were proposed together and
adopted together.

## Consequences

The account of how a step was carried out stays in the repository,
beside the plan, where a later reader finds it. Each step's pull
request carries a journal change, which the reviewer reads with the
code. Writing and revising the entries costs some time per step.
