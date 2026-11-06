<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Run on a push to main only the jobs that later runs need
@decision ci-main-runs
@cites branch-workflow
@cites performance-budgets
A push to `main` runs only the build and test jobs and the performance job; the daily run on `main` runs every job; a new run of a pull request or of `main` stops the older run of the same event.

## Context

Each push to a pull request, each push to `main`, and the daily
schedule started the same jobs: about seventeen in the workflows
`build` and `licensing`. On `main` the mutation job ran the full set,
four jobs of two to three hours each. On 2026-11-06 four merges each
started that full run, the runs stacked up, and the runs of pull
requests waited in the queue of GitHub Actions.

The ruleset of `main` requires a pull request to be up to date with
`main` before it merges. So the run of the pull request has already
tested the tree that the merge puts on `main`. A run on `main` gives
later runs three things: the caches, which a pull request can read
only from `main`; the upload to code scanning; and the artifact
`performance`, which the performance job of a pull request reads as
its baseline.

## Decision

- A push to `main` runs the jobs "Build and test" on each platform
  and "Measure performance". They save the caches, upload the
  findings to code scanning, and keep the artifact `performance`.
- A job added later runs on a push to `main` only when later runs or
  the repository need what it gives there, as the job of the default
  branch for the ledger (design notes, section 6.3) will.
- The daily scheduled run on `main` runs every job of `build`, the
  full set of mutants included, so that `main` is measured whole once
  a day.
- The workflow `licensing` runs on pull requests only.
- The check of the plugin manifests runs on pull requests only.
- Each workflow has a concurrency group for each event and each pull
  request or branch, and a new run cancels the older run of its
  group. A push to `main` never cancels the daily run, because the
  two are in different groups.

## Alternatives considered

- **Run no job on a push to `main`, and let the daily run do all of
  it** — not chosen. The baseline of the performance job could be a
  day old, so a pull request would carry the cost of every change
  merged that day. After a change to a lock file, every pull request
  would build its dependencies again until the next daily run, and
  code scanning would update once a day.
- **Stop only the full set of mutants on a push to `main`, and keep
  the other jobs** — not chosen. It saves most of the runner time, but
  each merge still runs about twelve jobs whose result the pull
  request already gave.

## Consequences

A survivor that a merge leaves on `main` shows in the daily run, up
to a day after the merge, and not a few hours after it. The mutation
job of the pull request still runs the mutants on the lines that it
changed. A test that a pull request removes can still leave a
survivor that only the daily run finds. A force-push to a pull
request stops the run of the older head, so its partial results are
lost; the new run gives the results of the new head. Each merge saves
about ten hours of runner time.
