<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Count an agent's statement only as a line of the diff tied to its text
@decision agent-statements
A statement that an agent writes in a file changes a state only when it is a line of the diff, tied by a hash or a revision to the text that it is about.

## Context

The design notes, the README, and `CLAUDE.md` said that Sinter never
reads the state of the work from an agent's report about its own work.
A study of what settles each question that Sinter answers found that
this was false in four places, by design. An agent can write each of
these statements, and each one changes a state:

- an `@ack`, which accepts a finding or clears a rule;
- a re-pin, which makes a citation current with no approval;
- a `@verifies` of an item that no `@satisfies` cites, which any
  passing test then meets;
- `@deprecated`, which takes a requirement out of `untraced`.

Also, under `proof.step = "change"`, a step without promises is done
when a change lands in its scope. Each of these is a line of the diff.
Each statement is tied to its text by a hash or a revision, and it
stops counting when that text changes. The thesis of the design notes
holds: the person who merges a change must be able to check every
state that Sinter reports from the repository and its test results
alone.

## Decision

The design notes, the README, and `CLAUDE.md` state this rule: a
statement that an agent writes in a file changes a state only when it
is a line of the diff, tied by a hash or a revision to the text that it
is about. So the person who merges the change sees each such statement
and can check it. A claim that exists only outside the files, such as
an agent's message that its work is done, changes no state.

## Alternatives considered

- **Keep the sentence "never an agent's report" as it was written.**
  Not chosen: it is false in four places, and a reader who checks it
  finds the gap.

## Consequences

The rule describes Sinter as it is, so no code changes. A new kind of
statement that an agent can write changes a state only if it is a line
of the diff tied to its text. The design notes call an `@ack` a
statement of the agent, not a report.
