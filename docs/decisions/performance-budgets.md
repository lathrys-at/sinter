<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Check peak memory and the growth of allocation per phase in CI
@decision performance-budgets
A CI job runs `sinter scan` and `sinter check` on generated trees and fails when the peak memory, or the growth of the memory that a phase allocates, exceeds its budget; at first the job does not block a merge.

## Context

Sinter had no benchmark and no performance budget. On a shared
machine, the wall time of one command varied by a factor of two
between sessions, and by more under load; CPU time varied by up to a
third. The peak memory of the same command varied by under one
percent. The GitHub Linux runners report peak memory, but `perf`
cannot count instructions there ("The instructions:u event is not
supported"), and the macOS runners report no instruction count either.

A whole-run measure also hides a step whose cost grows faster than
the tree. Before its fix, the step `Facts.records` grew 22 times from
a tree of 1,000 declarations to one of 10,000, while the whole run of
`sinter check` grew 10 times: at 10,000 declarations the step was
about 7 percent of the run. It became two thirds of the run only at
100,000 declarations, which is too large for every pull request.

## Decision

- A benchmark makes trees of 1,000 and 10,000 declarations from a
  fixed seed, and runs `sinter scan` and `sinter check` on each tree.
- On request, through a setting that ordinary runs never see, Sinter
  reports the words of memory that the OCaml runtime allocates in each
  phase of a run. This count is the same in every run of the same
  input at the same path; two phases grow slightly with the length of
  the path of the tree.
- Two budgets apply to each command:
  - **Memory:** the peak resident memory on the tree of 10,000
    declarations, measured on Linux, stays under its budget.
  - **Growth:** for each phase, the words allocated on the tree of
    10,000 declarations, divided by the words allocated on the tree
    of 1,000 declarations, stays under a limit. This budget is checked
    on every platform.
- The runner reports instruction counts where the platform gives
  them, as information only.
- A file in the repository holds the budgets. A change of a budget is
  a change of that file, in the pull request that needs it.
- The job runs on a pull request that changes `lib/`, `bin/`,
  `bridge/`, the benchmark, or a dependency. It does not block a merge
  until a revision of this record makes it required.
- No budget applies to wall time or to CPU time.

## Alternatives considered

- **A growth ratio of instructions over the whole run.** Not chosen:
  the CI runners cannot count instructions, and a whole-run ratio
  hides a phase that grows faster than the tree until the phase
  dominates.
- **A growth ratio of CPU time over the whole run.** Not chosen: CPU
  time on shared machines varies too much for a tight limit, the fixed
  cost of a run lowers the ratio on small trees, and a whole-run ratio
  hides a fast-growing phase.
- **The tree of 100,000 declarations in CI, with a whole-run ratio.**
  Not chosen: it adds minutes and about 0.7 GiB of memory to each pull
  request in scope.
- **A memory budget only.** Not chosen: it cannot catch a step whose
  time grows faster than the tree.
- **No check in CI.** A scheduled job writes the numbers to the job
  summary. Not chosen: a regression shows only when someone reads the
  numbers.

## Consequences

Each pull request in scope takes a few more minutes of CI. A change
that raises the peak memory, or that adds a phase whose allocation
grows faster than the tree, fails the job; the pull request then fixes
the cause or raises the budget, where the reviewer sees it. The growth
budget does not see work that allocates nothing, or work in the Rust
parser bridge. The memory budget is a Linux number; a pair that
measures on macOS reads its own numbers against its own baseline.
