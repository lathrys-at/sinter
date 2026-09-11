<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Run the instrumented CI jobs on the project's compiler, with the tools pinned
@decision instrumented-tooling
@cites test-rigor
@cites mutation-testing
@cites gh/26
The CI jobs that measure coverage and mutation score build on the same compiler and the same locked dependencies as every other job, and the two measuring tools are pinned to fixed commits in the job itself.

## Context

Coverage and mutation testing both rewrite Sinter's code at build
time through preprocessors built on the `ppxlib` library. Neither tool
has a release that installs on the compiler Sinter builds with, OCaml
5.5, nor beside the locked version of the command line library. The
coverage tool's fix waits in an open upstream pull request since June
2025; the mutation tool's fix is in the project's fork.

## Decision

- The instrumented jobs use the compiler and the lock file of the
  `build` job.
- `bisect_ppx` is pinned to the head commit of upstream pull request
  448, and `mutaml` to a commit of the project's fork. The pins live
  in the CI job and in the documented local commands. They do not
  enter `dune-project` or the lock file, because the tools are not
  dependencies of the package.
- A pin moves only by a pull request that names the new commit. The
  pins go when upstream releases versions that install beside the lock
  file.

## Alternatives considered

- **A separate switch on an older compiler, OCaml 5.3, where the
  released coverage tool installs** — rejected. The coverage number
  then describes a build the project does not ship, the job's
  dependency versions float without the lock file, and coverage stops
  when the project's lower bound passes 5.3.
- **The community staging package of the same coverage code** —
  rejected. It adds a second package repository to CI, maintained
  outside the project, for the same unreleased code under a version
  number.

## Consequences

The measuring tools are unreleased code, pinned by commit hash and so
reproducible. Someone moves each pin when upstream moves. Both tools
share one instrumented switch on the compiler the project ships.
