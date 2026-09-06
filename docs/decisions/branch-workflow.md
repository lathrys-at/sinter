<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Develop through branches and pull requests
@decision branch-workflow
@cites licensing
Every change reaches `main` through a pull request; every commit is signed off; the build and licensing workflows must pass; the maintainer reviews and squash-merges.

## Context

The bootstrap commits went to `main` directly, before any review
existed. Coding agents write most changes, and the human who runs an
agent is the contributor of record. The DCO requires a sign-off on
every commit. Two CI workflows exist: `build` and `licensing`.

## Decision

- No commit goes to `main` directly. Every change lives on a branch
  and reaches `main` through a pull request. Branch names carry a
  prefix: `feat/`, `docs/`, `spike/`, or `fix/`.
- Every commit is signed off with `git commit -s`, and a commit that
  an agent wrote carries an `Assisted-by:` or `Co-Authored-By:`
  trailer that names the agent.
- A pull request states what changed and how it was verified. All
  jobs of both workflows must pass before a merge.
- The maintainer reviews and merges. Merges are squash merges, so
  `main` holds one commit per reviewed change.
- The repository setting that adds a sign-off to commits made in the
  GitHub web interface is on, so merge commits satisfy the DCO check.

## Alternatives considered

- **Direct commits to `main`** — rejected. There is no review
  boundary. The project used this only for the bootstrap, before the
  first pull request.
- **Merge commits or rebase merges** — not chosen. A squash merge
  keeps one commit per reviewed change on `main`, and the pull request
  keeps the full history.
- **A merge queue** — deferred. It pays off when several pull
  requests are open at once; one at a time needs no queue.

## Consequences

CI runs on every pull request. An agent can open a pull request but
cannot merge one. A change that needs a fast fix still takes the
branch-and-review path.
