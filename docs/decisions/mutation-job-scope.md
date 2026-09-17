<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Measure a pull request on the lines it changed, and main whole
@decision mutation-job-scope
@cites mutation-testing
@cites mutation-gate
On a pull request the mutation job runs only the mutants on the lines the pull request changed and never holds the merge; the full set runs on every push to main and once a day; an author runs the pass on the branch before opening the pull request.

## Context

The record `mutation-testing` said that every pull request runs the
full set of mutants "while a pass takes a few minutes". By
2026-09-17 the set held 380 mutants, each run under three seeds, and
the job took about seven and a half minutes on a pull request. Six
minutes of that was the mutant run itself, and the number grows with
every mutant. The maintainer found the wait too long for each pull
request. The fork of `mutaml` already had the switch that tests only
the mutants on changed lines, `--changed-since`, built for this use.

## Decision

- On a pull request, the `mutation` job runs the mutants that sit on
  a line the pull request changed since its base, with the same three
  seeds and the same gate. Every other mutant is recorded as not run
  and stays outside the score.
- A pull request that changed no file under `lib/` or `bin/` runs no
  mutant. The job ends at once and passes.
- The full set runs on every push to `main` and once a day on a
  schedule, so that `main` is always measured whole.
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

## Alternatives considered

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
run on `main` reports. A survivor found on `main` is then a fix to
make, with no pull request to attach it to. The gate is harsher on a
small set than on the whole, because one survivor in a file with few
mutants is a large share of that file's set; since `main` stands at
100 percent with every unkillable mutant marked, a survivor in a
changed file is the thing the author should see. GitHub sends the
notice of a failed scheduled run to the person who last changed the
workflow file, and it stops a schedule after sixty days without a
commit to the repository.
