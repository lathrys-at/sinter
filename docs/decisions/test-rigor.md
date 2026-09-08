<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Prove interfaces with property-based tests and measure coverage
@decision test-rigor
@cites implementation-language
@cites json-handling
Every exported function has a test through its interface, every stated invariant and every decoder has a property-based test with `qcheck`, and CI measures coverage with `bisect_ppx` under a threshold that only rises.

## Context

Sinter is written to be depended on: by the hooks and the CI jobs
that gate a repository on its verdict, and by the projects that read
its JSONL. The specifications state universal rules about its
output. `spec/jsonl.md` fixes a canonical form for every line, and a
conformance fixture fails on one wrong byte. A test that feeds a
function the inputs its author thought of cannot show that such a
rule holds for every input.

Data from outside the process crosses three boundaries today: a file
on disk, a wasm module, and the result buffer of the parser bridge.
The serve mode adds a fourth, the request line. A decoder that
crashes on an input it did not expect crashes the tool inside a hook,
where nobody sees the message. The review of the parser bridge found
one such crash by hand, a stack overflow on a deeply nested tree.

The code so far has unit tests with chosen inputs and no measure of
what they reach.

## Decision

- The "Code" and "Tests" sections of `CONTRIBUTING.md` hold the
  rules. In short: every module has an `.mli` that states what can go
  wrong; a failure a caller handles is a `result` value; a function is
  total over its declared input or checks its stated precondition;
  data from outside the process is decoded in one module; every
  exported function has a test through the interface; every stated
  invariant and every decoder has a property-based test.
- `qcheck` writes the property-based tests, through `qcheck-alcotest`,
  so that the suite stays one alcotest runner. Both are test-only
  dependencies. A generator lives in one shared module under `test/`.
  A counterexample that `qcheck` shrinks to becomes a unit test with
  that exact input, beside the property.
- `bisect_ppx` measures coverage, as a test-only dependency, under a
  dune profile named `coverage` that instruments `lib/` and `bin/`.
  A CI job runs the suite under that profile and fails when the
  total is below a threshold. The threshold starts at the measured
  number, rounded down to a whole percent. A pull request may raise
  it. No pull request lowers it.
- A fuzz target for the bridge boundary, `crowbar` under AFL, is on
  the roadmap. It is not part of the test suite, because AFL needs
  its own build and runs for hours, not seconds.

## Alternatives considered

None were put forward.

## Consequences

Three test-only dependencies: `qcheck`, `qcheck-alcotest`, and
`bisect_ppx`. The suite takes longer, bounded by the count each
property generates. An interface is designed so that a test can
reach it: a decoder is a function from bytes to a `result`, not a
side effect inside a larger call. The coverage job adds one CI run
on Linux. The threshold moves only upward, and only in the pull
request that raises it, so the number in the workflow file is a
record of where the project stands.
