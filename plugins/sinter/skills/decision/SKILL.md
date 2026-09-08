---
name: decision
description: Write a decision record in docs/decisions/ with a @decision tag, from a decision the user made in conversation or in a plan. Use when the user says "record this decision", "write a decision record", "write an ADR", runs /sinter:decision, or when a plan step promises a @decision. Do not use for plan files (use /sinter:plan), for requirements or design items, or for changing the meaning of an existing record; a changed decision gets a new record that supersedes the old one.
user-invocable: true
argument-hint: "[slug or subject of the decision]"
---

# Write a decision record

A decision record captures one decision. The record states four
things: the situation, the choice, the alternatives, and what follows
from the choice. The tool reads the record through its `@decision`
tag. A rule or a later decision can cite the record. A person who
would otherwise re-argue the decision then finds the reasoning.
Never delete a decision record.

The tag rules are in `spec/vocabulary.md` of the Sinter repository
(sections 4, 7.1, and 8.3). The rules below are the parts this skill
needs.

## Input

The input is the decision. The user states the decision in
conversation, or a plan step promises it. If the choice is not clear from the conversation, ask before you
write. Never invent an alternative. An alternative belongs in the
record only when someone put it forward and it was deliberated: in
the conversation, in an issue, in a pull request, in a plan, or in
the design notes. When nobody put one forward, the record says so.

## Procedure

### 1. Derive the slug

Name the subject of the decision in two to four words, lowercase,
hyphen-separated. The slug must match `[a-z0-9]+(-[a-z0-9]+)*`. The
slug is permanent. You can never reuse it for another decision. The
slug shares one namespace with requirement slugs and design slugs.
Confirm the slug with the user.

### 2. Check for an existing record

Look in `docs/decisions/` for a record on the same subject.

- If none exists, write a new record.
- If one exists and the new decision replaces it, write a new record
  with a new slug. Add `@supersedes <old-slug> vN` to the tag block
  of the new record. `vN` is the current revision of the old record.
  Write `v1` when the old record shows no revision. Do not edit or
  delete the old record.
- If one exists and the decision is the same, stop and tell the user.

### 3. Write the record

Write `docs/decisions/<slug>.md` with this shape:

```markdown
<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright <year> The Sinter Authors -->

# <Title: the decision in one line>
@decision <slug>
<One sentence: what was decided.>

## Context

<The situation that needed a decision. What the constraints were.
Where the pressure came from. Two to five sentences.>

## Decision

<What was chosen, stated so that a reader can act on it. Include the
concrete rule, layout, or mechanism.>

## Alternatives considered

- **<Alternative>** — <why it was rejected, in one or two
  sentences>.
- **<Alternative>** — <...>.

## Consequences

<What follows from the decision: what becomes easier, what becomes
harder, what it commits the project to.>
```

Rules for the tag block:

- The tag block is the first paragraph after the title.
  `@decision <slug>` is its first line. Write no revision. A new
  record is `v1`.
- Add one `@cites <slug>` line for each existing record, requirement,
  or design item that the decision rests on. Add one
  `@cites <ns>/<id>` line for each external ref, such as an issue.
  Add no line for an item that the decision does not rest on.
- Add `@supersedes <slug> vN` only in the case from step 2.
- The one-sentence description follows the tag lines, on its own
  line.

The "Alternatives considered" section is mandatory. It lists only
the alternatives that someone put forward and that were deliberated.
Each entry names one option and the reason that the project did not
choose it. When nobody put an alternative forward, the section holds
one line: `None were put forward.` An alternative that nobody put
forward lends the decision a weight it did not earn; do not add one.

### 4. Show the result

Print the record. Tell the user the slug. List the records and the
refs that the record cites.

## Writing rules

All text in the record follows the project's writing rules in
`CONTRIBUTING.md`: short sentences, active voice, one meaning per
word, no invented terms, no notes that explain why the file exists.
The record explains the decision, not the document.

## Checks before you finish

- The file has the CC-BY-4.0 header and the copyright line.
- The tag block is the first paragraph after the title and starts
  with `@decision <slug>`.
- The slug matches the pattern and is not in use.
- All four sections exist. Every entry in "Alternatives considered"
  was put forward and deliberated, or the section holds
  `None were put forward.`
- Every `@cites` target exists in the repository or is a declared
  ref.
