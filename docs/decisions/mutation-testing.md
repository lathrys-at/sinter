<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Measure the tests with mutation testing, through a fork of mutaml
@decision mutation-testing
@cites test-rigor
@cites gh/25
@cites gh/27
Sinter runs mutation testing over `lib/` and `bin/` with a fork of `mutaml` that the project maintains; the score gates a merge and only rises; timeouts count as killed; an equivalent mutant is marked in the source with a reason.

## Context

Coverage reports which lines the tests ran. It cannot tell a test
that checks a result from a test that only runs code, so a coverage
number rises with tests that check nothing. Mutation testing measures
the tests: a tool makes one small change to the source, a mutant, and
runs the suite against it; a mutant that no test fails on shows a
behaviour no test checks. The first run over Sinter's code found 23
such gaps behind a coverage number of 91 percent.

OCaml has one mutation testing tool, `mutaml`. Its release does not
build on the compiler Sinter uses, it loses its working files under
current dune, its set of mutations omits the comparison operators, and
its upstream is quiet. Eleven tools in other languages were surveyed
for the choices below.

## Decision

- Sinter maintains a fork of `mutaml` at `lathrys-at/mutaml`. The fork
  keeps upstream's layout, names, and test style, so that a change can
  go upstream. Changes that upstream would take are offered there.
- A mutant that makes the suite exceed its time limit counts as
  killed. The limit derives from the unmutated baseline run, with a
  floor.
- An equivalent mutant, one that no input could distinguish from the
  original, is marked in the source on the expression, with a reason
  that the report prints. The marked mutant is not generated. No list
  of mutants lives outside the source.
- The runner passes fixed seeds to the property tests, several per
  mutant, and a mutant is killed when any seed kills it. The baseline
  runs twice with different seeds, and a disagreement stops the run.
- The gate is a minimum score in the CI job. It starts at the measured
  score rounded down to a whole percent and only rises. A score equal
  to the minimum passes.
- Every pull request runs the full set of mutants while a pass takes a
  few minutes.
- A mutant is named by its file, its enclosing top-level binding, the
  kind of mutation, the original and replacement text, and an ordinal
  among identical mutants in that binding, so that the name survives
  moved and reformatted code.
- The report writes the JSON format that Stryker, Infection, and Mull
  share.
- The mutations on by default preserve the type of the expression they
  change: comparisons, equality, boolean connectives, `not`, arithmetic,
  literals, and `Some` to `None`. Forcing a condition to a constant and
  changing string literals are off by default.

## Alternatives considered

- **A mutation testing tool of the project's own** — rejected. Days of
  work and a tool to maintain, while a working tool exists.
- **Wait for upstream to support the compiler** — rejected. The last
  upstream change was in September 2025, and there is no date.
- **A timeout counted as a survivor, or as its own outcome outside the
  score** — not chosen. One surveyed tool counts it as a survivor and
  one keeps it apart; nearly all count it as killed, because the tests
  noticed the change in the only way a hang can be noticed.
- **A list file of equivalent mutants** — rejected. After any edit that
  changes a mutant's name, the list silently excuses the wrong
  mutants. The marker in the source stays with the code.
- **No seed, or one fixed seed** — not chosen. No surveyed tool seeds
  its tests; all assume a deterministic suite. Sinter's property tests
  draw random inputs by rule. One seed lost two kills in the first run;
  no seed makes the gate move between runs.
- **A fixed percentage as the gate** — not chosen. Every surveyed tool
  does this, and none remembers its last score. The rule that the
  number only rises is the rule the project set for coverage.
- **A gate of 100 percent with every survivor fixed or marked** —
  not chosen now. Two surveyed tools do this. It needs the known gaps
  closed first, and marking a real test gap as equivalent would be a
  false record.
- **Mutants named by position** — rejected. Most surveyed tools do
  this, and the name breaks when an unrelated line moves, which breaks
  the gate's comparison and the markers with it.

## Consequences

The project maintains a fork, with the cost of keeping it alive until
upstream takes its changes or forever. A pull request that adds
untested behaviour fails until a test kills the mutants it creates.
Some survivors need a person's judgment, and each judgment is recorded
in the source as a marker with its reason. The known gaps are a chunk
of work of their own, after which the minimum rises.
