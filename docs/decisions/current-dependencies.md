<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Keep every dependency at its newest release
@decision current-dependencies
Sinter moves each of its dependencies to the newest release as soon as the release works for Sinter.

## Context

Sinter is an application. Nobody builds on its versions of its
dependencies, so it can move to a new release when the release
appears. In October 2026 the bridge still used tree-sitter 0.25.10 and
wasmtime 29.0.1. With these two versions, the store of the grammars
grew with each byte parsed: a scan of 100,000 declarations reached
2,163 MiB. Wasmtime 29 no longer got fixes, and two critical security
advisories covered it (GHSA-mghf-wjfp-p5xm and GHSA-897f-g5gm-fmxm).
Wasmtime had fixed the growth in version 34, and tree-sitter had moved
to newer versions of wasmtime in 0.26.6 and 0.27.0.

## Decision

- Sinter keeps each dependency at its newest release: the Rust crates,
  the Rust toolchain, the OCaml compiler and the OCaml packages of the
  lock file, the pins of the tools that measure the tests, the actions
  of the CI workflows, and the grammars.
- When a new release appears, a pull request or a plan step moves
  Sinter to it as soon as the release works for Sinter: the build and
  the checks pass, and the release has no known defect that Sinter
  would ship. A change that the release makes necessary is part of the
  move, not a reason to stay.
- The newest release that the other dependencies accept is the bound.
  For example, tree-sitter 0.27.1 accepts wasmtime 48 and not
  wasmtime 50.
- The first moves: tree-sitter 0.26.13 with wasmtime 36.0.19 now, and
  then the 0.27 line with wasmtime 48 when tree-sitter releases the
  fix of its issue 6032. In tree-sitter 0.27.1 that issue gives wrong
  supertypes for a grammar in WebAssembly.

## Alternatives considered

For the rule itself, nobody put forward an alternative. For the first
move, these options were put forward:

- **tree-sitter 0.27.1 with wasmtime 48 at once.** Not chosen now. It
  needs a newer Rust than the pinned 1.94.1, it changes the cost of
  fuel for an adapter, and it ships issue 6032. It is the next move.
- **Stay on tree-sitter 0.25.10 and replace the store of the grammars
  from time to time.** Not chosen: wasmtime 29 gets no fixes and falls
  under both advisories. On macOS, only a new store for each parse
  kept the memory low, at a cost of about 8 percent of the speed of
  parsing.

## Consequences

Moves are frequent and small, so each upstream change arrives alone
and early. Each move can change the measurements of performance, so a
move measures them again. Nothing checks yet that a dependency has a
newer release; a person or an agent looks.
