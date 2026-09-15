# Quality: property tests and coverage
@plan quality
@scope test/**, lib/**, bin/dune, docs/decisions/**, docs/roadmap.md, .plans/**, .github/workflows/**, dune-project, sinter.opam, sinter.opam.locked, THIRD_PARTY.md, CONTRIBUTING.md, .gitignore
Record the code and test rules, bring the existing interfaces under
property-based tests, measure coverage and mutation score in CI, and
close the gaps the mutants find.

## Record the rules
@scope docs/decisions/**, docs/roadmap.md, .plans/**, CONTRIBUTING.md
@decision test-rigor
Add the "Code" and "Tests" sections to `CONTRIBUTING.md`, and the
record that fixes the tools: `qcheck` for properties, `bisect_ppx`
for coverage, `crowbar` under AFL for a later fuzz target.

## Add property tests over the existing interfaces
@scope test/**, lib/**, dune-project, sinter.opam, sinter.opam.locked, THIRD_PARTY.md
Write property-based tests for `Jsonl`, the result-buffer decoder of
the bridge, the pure functions of `Parse`, and the bridge through its
interface. Fix every defect the properties find, each in its own
commit with a unit test that holds the counterexample. Declare
`qcheck` and `qcheck-alcotest`.

## Measure coverage in CI
@scope .github/workflows/**, test/**, lib/dune, lib/bridge/dune, bin/dune, docs/decisions/**, CONTRIBUTING.md
@decision instrumented-tooling
Instrument `lib/` and `bin/` with `bisect_ppx`, add a CI job on the
project's compiler that reports the summary and fails below the
minimum, and document the local commands in `CONTRIBUTING.md`.

## Run mutation testing in CI
@scope .github/workflows/**, lib/dune, lib/bridge/dune, bin/dune, test/**, .gitignore, docs/decisions/**, docs/roadmap.md, CONTRIBUTING.md
@decision mutation-testing
Instrument `lib/` and `bin/` with the project's fork of `mutaml`, add
a CI job that reports the score and the survivors and fails below the
minimum, and document the local commands in `CONTRIBUTING.md`. The
runner starts the suite through a script under `test/`, because the
suite reads its fixtures from the build copy of `test/`, and
`.gitignore` covers what a run writes.

## Close the test gaps that the mutants found
@scope test/**, lib/**, .github/workflows/**
Write the tests that kill the surviving mutants of the first run, mark
the equivalent ones in the source with a reason, and raise the minimum
to the new measured score.
