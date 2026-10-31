<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Cut the tables of the manifest by the question that each answers
@decision manifest-questions v2
@cites manifest-names
Each table of the manifest answers one question about the project, and the table `[proof]` holds what settles each item.

## Context

The manifest had five tables, one for each part of Sinter that reads
its keys: `[scan]`, `[check]`, `[plan]`, `[ledger]`, and `[evidence]`.
A person who writes a key answers a question about the project, not
about the parts of Sinter. So the keys that answer one question were
in several tables. The roles of paths were in `[check]` and in
`[plan]`, and section 10.1 of the manifest specification had to join
them in prose. The keys that decide what counts as settled were in
`[plan]`, `[ledger]`, and `[evidence]`. A key for steps without
promises was due, and it would have been in a fourth place. A study of
what settles each question that Sinter answers listed the questions,
and the evidence and the key for each one.

## Decision

Each table answers one question:

| table | question |
|---|---|
| top level | Which version of the specifications applies, and which branch is the default? |
| `[scan]` | What does Sinter read? |
| `[paths]` | What does each path mean? |
| `[proof]` | What settles each item? |
| `[check]` | How hard does each gap bite? |

The keys move:

| before | after |
|---|---|
| `check.historical` | `paths.historical` |
| `plan.exempt` | `paths.exempt` |
| `plan.locations.<kind>` | `paths.<kind>` |
| `ledger.approval-required`, a list of kinds | `proof.<kind> = "approval"` for each kind |
| `ledger.agent-markers` | `proof.agent-markers` |
| `evidence.test-coverage = "optional"` | `proof.verifies = "whole-run"` |
| `evidence.test-coverage = "required"` | `proof.verifies = "each-test"` |

The tables `[plan]`, `[ledger]`, and `[evidence]` go away. `[scan]`
and `[check]` keep their keys.

Each value in `[proof]` names the evidence that settles the item:

- `proof.req`, `proof.design`, `proof.decision`, and `proof.plan` are
  `"declaration"`, the default, or `"approval"`. Under `"approval"`,
  an item of the kind is approved only when a person's approval in the
  ledger matches it.
- `proof.verifies` is `"whole-run"`, the default, or `"each-test"`. It
  names the coverage that lets a passing `@verifies` edge meet a
  promise: the coverage of the whole run, or the coverage of each
  test.
- `proof.step` applies to a step without promises. It is
  `"delivered"`, the default, `"approval"`, or `"promises"`. Under
  `"delivered"`, the step is done when the plan file marks it as
  delivered (record `delivery-marks`). Under `"approval"`, the step is
  done when a person approves it in the ledger. Under `"promises"`,
  every step must have promises, and a step without promises is the
  finding `step-without-promises`.

The tiers stay in `[check]`. What counts as settled, and how hard a
gap bites, stay apart: a project can change either one without the
other.

## Alternatives considered

- **One section of the specifications, "What settles each question",
  with every key in its present table.** Not chosen: a reader still
  finds the keys that answer one question in three tables.
- **One table `[proof]`, with the other tables unchanged.** Not
  chosen: the roles of paths stay split between `[check]` and
  `[plan]`, and the manifest follows two rules, with one table cut by
  question and the others cut by the part of Sinter.

## Consequences

The names are part of every manifest, of the setting facts, and of
the finding `config-changed`, so the change breaks every reader of the
old names. No repository outside Sinter used them. Sinter's own
manifest moves two keys. The rule that each table holds the settings
of one part of Sinter ends: a part of Sinter can read keys from more
than one table. A step that `proof.step = "approval"` covers needs an
approval in the ledger, so the ledger takes a step as the subject of
an approval. The records written before this one keep the old names,
because they record what was decided then.
