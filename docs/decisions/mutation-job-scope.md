<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Measure a pull request on the lines it changed, a dependency move whole, and main whole
@decision mutation-job-scope v4
@cites gh/158
@cites ci-main-runs
@cites mutation-testing
@cites mutation-gate
On a pull request the mutation job runs only the mutants on the lines the pull request changed, or the full set when the pull request changes a dependency, and never holds the merge; the full set runs once a day on main; an author runs the pass on the branch before opening the pull request; the job runs as four jobs that each test a share of the mutants, under two seeds that each job draws at random.

## Context

The record `mutation-testing` said that every pull request runs the
full set of mutants "while a pass takes a few minutes". By
2026-09-17 the set held 380 mutants, each run under three seeds, and
the job took about seven and a half minutes on a pull request. Six
minutes of that was the mutant run itself, and the number grows with
every mutant. The maintainer found the wait too long for each pull
request. The fork of `mutaml` already had the switch that tests only
the mutants on changed lines, `--changed-since`, built for this use.
On 2026-10-26 the move to OCaml 5.5.2 changed no line under `lib/` or
`bin/`, so its pull request ran no mutant, and nothing showed that the
mutation build worked on the new compiler.

On 2026-11-01 the full set held 4,726 mutants. Its pass on `main`
stopped at the time limit of a GitHub job, six hours, after 4,041
mutants. Until 2026-11-01 a benchmark test failed under every mutant
(issue gh/158), so each mutant stopped at that first failure, and the
pass looked short. With that test fixed, a mutant that survives runs
the whole suite once for each seed.

## Decision

- On a pull request, the `mutation` job runs the mutants that sit on
  a line the pull request changed since its base, with the same seeds
  and the same gate as the full set. Every other mutant is recorded as not run
  and stays outside the score.
- A pull request that changes a dependency runs the full set: the
  lock file or the package files of the OCaml build, the CI workflow
  that pins the compiler and the mutation tool, the crate files or the
  toolchain file of the bridge, the embedded grammar, or the script
  that runs a mutant. A dependency can change the behavior of lines
  that the pull request did not change.
- A pull request that changed no dependency and no file under `lib/`
  or `bin/` runs no mutant. The job ends at once and passes.
- The full set runs once a day on `main`, in the scheduled run of the
  workflow, so that `main` is measured whole each day. A push to
  `main` runs no mutant (record `ci-main-runs`).
- The job is not a required check. It never holds a merge. A failure
  stays red on the pull request, with the survivors in the job's
  summary, for the author and the reviewer to read.
- Before opening a pull request that touches `lib/` or `bin/`, the
  author runs the pass on the branch with `--changed-since` and reads
  every survivor. `CONTRIBUTING.md` gives the command. A brief to an
  implementer pair says the same.
- The sentence in `mutation-testing` that every pull request runs the
  full set no longer applies. The rest of that record stands, and the
  gate of `mutation-gate` applies to whichever set ran.
- The job runs as four jobs at the same time. Each job tests a share
  of the source files, and the shares hold about the same number of
  mutants. A last job joins the four reports and applies the gate to
  the joined score.
- Each mutant runs under two seeds of the property tests, not three.
  Each job draws its two seeds at random and prints them, so that a
  survivor can run again under the same seeds. The sentence in
  `mutation-testing` that the runner passes fixed seeds no longer
  applies.

## Alternatives considered

- **Split the full set over several jobs, with three seeds** — taken
  in part. The split is kept, with two seeds in place of three, so
  that each job has more time to spare.
- **Run each mutant under one seed** — taken in part. One seed would
  save the most time, but a property test can miss under one seed a
  change that another seed finds. Two seeds keep the second chance.
- **Run the full set once a night on a runner of the project's own,
  with a longer time limit** — not chosen. It needs a machine to set
  up and keep, and a gap shows a day later.
- **Split the mutants in the runner, with an option `--shard K/N` in
  the fork of `mutaml`** — deferred, not rejected (lathrys-at/mutaml
  issue 10). It balances the jobs better and runs the suite without a
  mutant once for each job, not once for each file. The split in the
  workflow comes first because it needs no change to the fork.

- **Run the full set only when the OCaml toolchain or its packages
  change** — not chosen. The move to tree-sitter 0.26 changed the
  bridge's crates and changed parse results across Sinter; such a
  move needs the full set as much.
- **Run the full set once a day against `main`, and not on pull
  requests** — the maintainer's first proposal. Not taken alone. The
  check would then run after a merge and not before it, a pull
  request that lowers the score would merge unseen, and the failure
  would appear the next day with no author attached. The daily run is
  kept, as the measurement of `main` whole.
- **Keep the full set on every pull request, but stop waiting for
  it** — taken as a part of the decision, not alone. On its own the
  seven minutes still run on every pull request and the result still
  arrives after the merge in every case where the maintainer merged
  first.

## Consequences

A pull request that only adds, changes, or removes tests runs no
mutant, so a test removed there can leave a survivor that the next
daily run on `main` reports. A survivor found on `main` is then a fix
to make, with no pull request to attach it to. The gate is harsher on a
small set than on the whole, because one survivor in a file with few
mutants is a large share of that file's set; a survivor in a changed
file is still the thing the author should see. GitHub sends the
notice of a failed scheduled run to the person who last changed the
workflow file, and it stops a schedule after sixty days without a
commit to the repository.

The seeds change from run to run, so the score can move between two
runs of the same tree: a mutant that only some seeds kill survives in
one run and not in another. Such a mutant is a gap in the tests, and
the printed seeds let an author run it again. The four jobs use more
runner time at one time than one job. Each job runs the suite twice
without a mutant for each of its source files, which costs time that
the option `--shard` of the fork would save.
