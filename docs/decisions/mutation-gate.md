<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Fix the mutation gate at 95 percent, and aim for 100
@decision mutation-gate
@cites mutation-testing
The CI job that measures the mutation score fails below 95 percent; the number does not rise with the measurement and does not fall; 100 is the aim, not the gate.

## Context

The record `mutation-testing` set the gate as a minimum that starts at
the measured score rounded down and only rises. When the survivors of
the first runs were killed or marked, the measurement reached 100
percent, and that rule would have set the gate there. A gate at 100
fails a pull request on the first mutant that no test kills, until the
author writes the test or marks the place.

## Decision

- `MUTATION_MINIMUM` in the CI job is 95. It is fixed: a higher
  measurement does not raise it, and no pull request lowers it.
- The score to aim for is 100. The job's summary names every mutant
  that survived, and each one is a test to write or a place to mark
  with a reason. Review reads the survivors as it reads the rest of a
  change.
- The rule in `mutation-testing` that the gate starts at the measured
  score and only rises no longer applies. The rest of that record
  stands.

## Alternatives considered

- **The measured score rounded down, rising with each measurement**,
  the rule of the earlier record — not kept. With the measurement at
  100, it becomes the gate below, and the maintainer chose room
  instead.
- **A gate of 100 percent, with every survivor killed or marked** —
  not chosen. It is what the measurement gave and what two of the
  surveyed tools ship as their default. The maintainer preferred a gate
  that does not stop a sound pull request for one unkilled mutant, with
  100 as the standard that review holds a change to.

## Consequences

A pull request may merge with a survivor, and the survivor stays on the
job's summary until someone kills or marks it. The number in the job is
a floor, not a record of where the project stands; the summary is.
