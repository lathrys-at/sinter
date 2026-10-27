<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Name the plan step and its promises in each commit message
@decision commit-messages v3
@cites pull-request-descriptions
@cites plain-names
Each commit message ends with git trailers that name the plan step, the record, or the issue that allows the change, and each promise of the step that the commit meets.

## Context

A commit message had an imperative subject, a short body in free
form, and the sign-off. Nothing in it tied the commit to the plan. A
pull request description names the plan step (record
`pull-request-descriptions`), but a branch often holds several
commits, and each does one part of the step. A reviewer who reads a
branch commit by commit had to infer which promise each commit claims
to meet.

## Decision

The last paragraph of each commit message holds git trailers, lines
of the form `Key: value` that `git interpret-trailers` reads, in this
order:

1. One line that names what allows the change:
   - `Step: <plan>/<step>`: a plan step, by the slug of its plan and
     the slug of the step (`spec/vocabulary.md` section 10.3).
     Example: `Step: sinter-v0.1/check-a-diff`.
   - `Record: <slug>`: a decision record that allows the change with
     no plan step. Example: `Record: current-dependencies` for the
     move of a dependency.
   - `Issue: <ns>/<id>`: an issue, as an external id
     (`spec/vocabulary.md` section 4.2). Example: `Issue: gh/12`.

   A commit that does work of a plan step names the step.
2. One `Meets: <tag> <slug>` line for each promise of the step
   that the commit carries out, with no revision. Example:
   `Meets: @satisfies diff-mode`. A commit that does a part of a
   step and meets no promise has no `Meets:` line.
3. The trailer that names an agent, then the `Signed-off-by:` line
   that `git commit -s` adds.

A change that no plan step, record, or issue allows gets one of them
first.

## Alternatives considered

- **A sentence in the body, in free form.** Not chosen: no tool can
  check it, and its words drift from commit to commit.
- **A prefix in the subject line**, such as `[check-a-diff]`. Not
  chosen: it makes the subject long, it has no room for the promises,
  and a squash merge keeps only the title of the pull request.

## Consequences

A reviewer checks each `Meets:` line against the diff and the
plan, and finds a commit that claims a promise it does not deliver,
or work that no promise names. A tool can read the trailers; a check
of them by Sinter is on the roadmap. Each commit message has two or
three more lines. Commits written before revision 2 carry the same
trailer under the name `Discharges:`.
