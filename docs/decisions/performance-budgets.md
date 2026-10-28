<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Check the growth of allocation per phase in CI, and report the peak memory
@decision performance-budgets v2
A CI job runs `sinter scan` and `sinter check` on generated trees, fails when the growth of the memory that a phase allocates exceeds its budget, and reports the peak memory next to the peak memory of `main`; the job does not block a merge.

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

Version 1 of this record also set a fixed budget for the peak memory
of each command. Each new feature adds some memory, so the margin
under a fixed budget gets smaller with each feature, even when nothing
is wrong. In October 2026 the margin of `sinter check` was 2.5
percent, and each pull request that crossed it stopped for a decision
to raise the budget. The performance work was not meant to set fixed
limits for ever. The growth budget found the real defect, and it does
not get tighter as Sinter grows.

## Decision

- A benchmark makes trees of 1,000 and 10,000 declarations from a
  fixed seed, and runs `sinter scan` and `sinter check` on each tree.
- On request, through a setting that ordinary runs never see, Sinter
  reports the words of memory that the OCaml runtime allocates in each
  phase of a run. This count is the same in every run of the same
  input at the same path; two phases grow slightly with the length of
  the path of the tree.
- **Growth budget:** for each phase of each command, the words
  allocated on the tree of 10,000 declarations, divided by the words
  allocated on the tree of 1,000 declarations, stays under a limit.
  This budget is checked on every platform. A file in the repository
  holds the limits. A change of a limit is a change of that file, in
  the pull request that needs it.
- **Peak memory:** the job measures the peak resident memory of each
  command on the tree of 10,000 declarations, on Linux, and writes it
  in the job summary next to the peak memory of the newest measured
  run on `main`. No fixed budget applies to it.
- The runner reports instruction counts where the platform gives
  them, as information only.
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
- **Keep the fixed memory budgets as they are** (version 1), and raise
  a budget in the pull request that crosses it. Not chosen: the limits
  need a raise again and again, and each raise stops the work for a
  decision.
- **Keep both budgets, as warnings only.** Not chosen: when nobody has
  to raise the numbers, they grow old and stop meaning anything, and a
  warning on every pull request is noise.
- **Remove all budgets, and only report the numbers.** Not chosen: a
  phase that grows too fast would no longer fail the job, and version 1
  rejected a job that only reports for the same reason.

## Consequences

Each pull request in scope takes a few more minutes of CI. A change
that adds a phase whose allocation grows faster than the tree fails
the job; the pull request then fixes the cause or raises the limit,
where the reviewer sees it. A change in peak memory fails nothing: the
reviewer sees it in the job summary, next to the number of `main`. A
slow rise of memory over many pull requests shows only to a person who
reads the summaries. The growth budget does not see work that
allocates nothing, or work in the Rust parser bridge. The peak memory
is a Linux number; a pair that measures on macOS reads its own numbers
against its own baseline.
