---
name: decision
description: Write a decision record in docs/decisions/ with a @decision tag, from a decision the user made in conversation or in a plan. Use when the user says "record this decision", "write a decision record", "write an ADR", runs /sinter:decision, or when a plan step promises a @decision. Do not use for plan files (use /sinter:plan), for requirements or design items, or for changing the meaning of an existing record; a changed decision gets a new record that supersedes the old one.
user-invocable: true
argument-hint: "[slug or subject of the decision]"
---

# Write a decision record

A decision record captures one decision: what the situation was, what
was chosen, what else was considered, and what follows. Sinter reads
the record through its `@decision` tag. Rules and later decisions can
cite it, so the reasoning reaches the moment someone would otherwise
re-argue it. A decision record is never deleted.

The tag rules are in `spec/vocabulary.md` of the Sinter repository
(sections 4, 7.1, and 8.3). The rules below are the parts this skill
needs.

## Input

The decision, as the user stated it in conversation or as a plan step
promised it. If the choice or the alternatives are not clear from the
conversation, ask before you write. Never invent an alternative that
was not considered; if none was, ask the user what else could have
been done.

## Procedure

### 1. Derive the slug

Name the subject of the decision in two to four words, lowercase,
hyphen-separated. The slug must match `[a-z0-9]+(-[a-z0-9]+)*`. The
slug is permanent: it can never be reused for another decision, and it
shares a namespace with requirement and design slugs. Confirm the slug
with the user.

### 2. Check for an existing record

Look in `docs/decisions/` for a record on the same subject.

- If none exists, write a new record.
- If one exists and the new decision replaces it, write a new record
  with a new slug, and add `@supersedes <old-slug> vN` to its tag
  block, where `vN` is the old record's current revision (`v1` when
  the old record shows none). Do not edit or delete the old record.
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

- It is the first paragraph after the title. `@decision <slug>` is its
  first line. Write no revision; a new record is `v1`.
- Add one `@cites <slug>` line for each existing record, requirement,
  or design item the decision rests on, and `@cites <ns>/<id>` for an
  external ref such as an issue. Add nothing the decision does not
  rest on.
- Add `@supersedes <slug> vN` only in the case from step 2.
- The one-sentence description follows the tag lines, on its own
  line.

"Alternatives considered" is mandatory and must never be empty. It
is the section that stops re-argument. Each alternative names the
option and the reason it lost.

### 4. Show the result

Print the record. Tell the user the slug, and list the records or
refs it cites.

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
- All four sections exist, and "Alternatives considered" has at least
  one entry with a reason.
- Every `@cites` target exists in the repository or is a declared
  ref.
