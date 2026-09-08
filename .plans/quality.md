# Quality: property tests and coverage
@plan quality
@scope test/**, lib/**, bin/dune, docs/decisions/**, docs/roadmap.md, .plans/**, .github/workflows/**, dune-project, sinter.opam, sinter.opam.locked, THIRD_PARTY.md, CONTRIBUTING.md
Record the code and test rules, bring the existing interfaces under
property-based tests, and measure coverage in CI.

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
@scope .github/workflows/**, test/**, lib/dune, bin/dune, dune-project, sinter.opam, sinter.opam.locked, CONTRIBUTING.md
Add the `coverage` profile with `bisect_ppx`, a CI job that reports
the summary and fails below the threshold, and the local commands in
`CONTRIBUTING.md`.
