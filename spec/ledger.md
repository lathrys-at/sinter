<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: approval-ledger format

Status: draft. The seven specifications share one version; see [docs/versioning.md](../docs/versioning.md).

## 1. Introduction

The ledger is Sinter's append-only record of judgments about a
repository: approvals, refusals, the entries that record the delivery
of a step, and the entry that closes each plan.
This document defines where the ledger lives, how entries get their
ids, each entry kind, and the rules that give entries their meaning.

Anyone can implement this specification in any tool. See the
LICENSE-SPEC file at the repository root. Entries are JSONL records in
the canonical form of [jsonl.md](jsonl.md) section 2. The items the
ledger judges are defined in [vocabulary.md](vocabulary.md).

## 2. Storage

### 2.1 The file and the ref

@req ledger-storage

The ledger is a JSONL file, `ledger.jsonl`, in the tree of a dedicated
git ref: `refs/sinter/ledger`. This ref is not a checkout path. No
editor and no file tool reaches the ledger without a git plumbing
command. Sinter imposes this restriction on purpose, so that only a
deliberate act writes the ledger.

### 2.2 Append only

@req ledger-append-only

Each write appends lines to the file and commits, with the previous
tip as the parent. The ref moves by fast-forward only. Every commit's
ledger file must be a byte-prefix extension of its parent's: old lines
never change and never move.

### 2.3 History, not a derivation

Unlike the derived JSONL of a scan, ledger entries carry timestamps
and authorship. The ledger is history, not a derivation.

## 3. Entry identity

### 3.1 The id of an entry

@req ledger-entry-id

An entry's id is `e-` plus the first twelve hex digits of a SHA-256
hash. The hash covers the entry's canonical bytes with the `id` key
absent. Two writers can never produce one id for two different
entries.

### 3.2 Recovery from a failed push

@req ledger-push-recovery

Two writers can push to the ledger ref at the same time, and one of
the two pushes then fails. Ids come from the entry's content, so
recovery from a failed push is a set union. The writer that lost takes
these three actions in order:

1. Fetch the ledger ref.
2. Append again the local entries that the upstream file does not
   hold, in timestamp order.
3. Push again.

### 3.3 Unique ids

@req ledger-unique-ids

Ids never repeat within the ledger.

### 3.4 The order of entries

@req ledger-entry-order v2

Where order matters — for example a decline superseded by a later
approval — the `ts` field decides the order, and not the position in
the file.

## 4. Common fields

### 4.1 The fields of every entry

@req ledger-common-fields v3

Every entry carries:

| field | meaning |
|---|---|
| `id` | entry id (section 3) |
| `kind` | `approval`, `approved-scope`, `approved-promise`, `decline`, `delivered`, `completed`, or `abandoned` |
| `v` | schema version |
| `by` | who wrote the entry |
| `ts` | RFC 3339 timestamp, UTC |
| `head` | the commit the writer stood on |
| `branch` | the branch the writer stood on |
| `tool` | tool version |

### 4.2 The writers

@req ledger-writers v6

Four writers exist. The approval command writes `approval` entries:
of a declaration, of a plan, and of a step. The approval of a plan
comes with its `approved-scope` and `approved-promise` lines. The
decline command writes `decline`. The abandon command writes
`abandoned`. A person runs these three commands. The fourth writer is
the job on the default branch, which writes `delivered` and
`completed` (section 8).

## 5. `approval`

### 5.1 The fields of an approval entry

@req ledger-approval-entry v3

An `approval` entry records that a person approved a subject. The
subject is a declaration, a plan, or a step.

| field | meaning |
|---|---|
| `subject` | for example `req:auth-lockout`, `plan:auth-lockout@3f2a9c`, or `step:auth-lockout@3f2a9c/tidy` |
| `rev` `xh` | declarations only: the revision and extent hash approved |
| `csh` | plans and steps only: the commitment-set hash of a plan, or the step hash of a step ([jsonl.md](jsonl.md) section 4) |
| `note` | omitted when none |

The subject of a plan is the fact id of the plan, which holds the full
form of the plan ([vocabulary.md](vocabulary.md) section 4.3). The
approval command refuses to approve a plan that has no plan id. So the
full form of every approved plan holds a plan id, and the id of a
claim can be read ([jsonl.md](jsonl.md) section 9).

The subject of a step is the fact id of the step,
`step:<plan>/<step>`, which holds the full form of its plan. The
approval command refuses to approve a step that has promises, and a
step of a plan that has no plan id. An approval of a step matches the
step while its `csh` equals the current step hash of the step. While
`proof.step` is `"approval"` ([manifest.md](manifest.md) section
10.4), a matching approval approves a step without promises, and so
meets the first condition of `done()` ([algebra.md](algebra.md)
section 6.4).

### 5.2 Approval

@req ledger-approval v3

Approval attaches to the `(slug, rev, xh)` triple, never to a
document. A declaration of a kind that needs approval
([manifest.md](manifest.md) section 10.1) is **approved** if and only
if the ledger holds an approval for its current `(slug, rev, xh)`. A
revision bump therefore removes approval until the item is approved
again. A declaration of a kind that does not need approval counts as
approved.

### 5.3 Revision reservation

@req ledger-revision-reservation v2

A writer must refuse to write an approval for `(slug, rev)` when the
ledger already holds an approval for that pair with a different `xh`.
The refusal message names the earlier entry and the branch that entry
was written from. To resolve the refusal, the author must increase the
declaration's revision again. When the ledger already holds an
approval for the same `(slug, rev)` with the same `xh`, the writer
writes no new entry.

## 6. `approved-scope` and `approved-promise`

@req ledger-approved-commitment-set

The approval entry of a plan holds the approved commitment set as
entries, not only as a hash. A hash shows only that two sets differ.
It does not show which promises or scopes differ, and the comparison
in section 11 needs that detail. Two entry kinds carry the set.

**`approved-scope`** — one per glob. When `step` is omitted, the glob
is plan-level.

| field | meaning |
|---|---|
| `approval` | the approval entry this belongs to |
| `step` | step slug; omitted for the plan scope |
| `glob` | one scope glob |

**`approved-promise`** — one per promise.

| field | meaning |
|---|---|
| `approval` | the approval entry this belongs to |
| `step` | step slug |
| `word` `target` | the promise |

## 7. `decline`

### 7.1 The fields of a decline

@req ledger-decline

A decline records a refusal by a person, bound to the exact text
refused.

| field | meaning |
|---|---|
| `subject` | fact id |
| `hash` | the subject's extent hash (`xh`) or commitment-set hash (`csh`) at the moment of refusal |
| `reason` | required |

### 7.2 A live decline

@req ledger-live-decline v2

A decline is **live** while the subject's current hash equals `hash`
and no later approval of the subject exists. A decline is never deleted.
A later approval of the subject ends the decline's effect. That later
approval can be at a different hash. It can also be at the same hash,
when the person overrides their own earlier refusal.

## 8. The job on the default branch

### 8.1 The job and the `completed` entry

@req ledger-completed v6

The **job on the default branch** writes the `delivered` and the
`completed` entries. The job runs on the default branch, in CI or by a
person's hand. It runs the same command either way, and it makes no
judgment of its own. In CI, it runs on each push to the default
branch. The job takes these actions in order:

1. Find the range of its run (section 8.4). When the clone does not
   hold the commits of the range, fetch them. A clone in CI is often
   shallow.
2. Import the test evidence of its run.
3. Append one `delivered` entry for each delivery line of the range
   that section 8.4 names.
4. Find the open plans on the default branch.
5. Check each of those plans against the completion condition below.
6. Append one `completed` entry for each plan that passes the
   condition.

A `completed` entry closes a plan whose steps are all done
([algebra.md](algebra.md) section 6.4).

| field | meaning |
|---|---|
| `subject` | `plan:<slug>@<id>`: the fact id of the plan, with its full form |
| `approval` | the id of the latest `approval` entry whose subject is the plan, at the time the plan closed; omitted when the plan has no approval |
| `merge` | the merge commit that delivered the last step of the plan ([vocabulary.md](vocabulary.md) section 10.8) |
| `report` | SHA-256 of the report compiled when the plan closed |

### 8.2 The completion condition

@req ledger-completion-condition v5

A plan passes the condition when every step of the plan is done
(`done()`, [algebra.md](algebra.md) section 6.4). The job imports the
test evidence of its run before it checks the condition. Without
evidence, a `verifies` edge is at rung `never-ran`
([algebra.md](algebra.md) section 6.7), and the step that holds the
edge in its scope is not done. So a plan with a `verifies` edge in the
scope of a step does not close without evidence.

Under `proof.step = "delivered"`, a step without promises is done when
the ledger holds a `delivered` entry that matches its current step
hash (section 8.4). So the job appends the `delivered` entries of its
run before it checks the condition.

An open plan that fails this condition is normal while its work goes
on. A step merged in part, with some of its promises met and some not,
is the finding `merged-incomplete` ([algebra.md](algebra.md) section
9).

### 8.3 A repeated run

@req ledger-completion-idempotent v3

The writes of the job are idempotent. A second run adds no second
`completed` entry for a plan. It adds no `delivered` entry whose
subject and `csh` are those of a `delivered` entry that the ledger
holds. The approvals of a plan, the repository tree, the messages of
its commits, and the test evidence of the run hold the facts that
prove delivery and completion. A run reads every commit from the
start of section 8.4, so a run of the job that does not finish costs
one repeat run and loses no facts.

### 8.4 The `delivered` entry

@req ledger-delivered

A `delivered` entry records that a commit of the default branch
delivered a step ([vocabulary.md](vocabulary.md) section 10.8). An
entry **matches** a step when its subject is the step and its `csh` is
the current step hash of the step.

| field | meaning |
|---|---|
| `subject` | `step:<plan>/<step>`: the fact id of the step, with the full form of its plan |
| `csh` | the step hash of the step in the tree of the head of the run, all 64 hex digits ([jsonl.md](jsonl.md) section 4) |
| `merge` | the commit of the range whose message holds the delivery line. After a squash merge, it is the merge commit. After another kind of merge, it can be a commit of the merged branch |

The **range** of a run is the set of commits that the head of the
default branch reaches and that the **start** of the run does not
reach. The start is the first of these that exists:

1. The `head` of the latest `delivered` or `completed` entry of the
   ledger. The job alone writes these two kinds, so this is the head of
   the latest run that appended an entry.
2. The `head` of the first entry of the ledger whose `branch` is the
   default branch.

When the ledger holds no such entry, the run has no start, and the
range holds every commit that the head reaches. A run that appends no
entry leaves the start where it was, so the next run reads the same
commits again.

The job reads the message of each commit of the range, in the order
that `git rev-list ^<start> <head>` gives them, and reads the delivery
lines of each message as [vocabulary.md](vocabulary.md) section 10.8
says. It appends one `delivered` entry for each step for which a
delivery line of the range meets both of these conditions, in the
tree of the head and with the test evidence of the run:

1. The line counts for the step.
2. Each promise of the step is met ([vocabulary.md](vocabulary.md)
   section 10.5). A step without promises meets this condition.

The `merge` of the entry is the commit of the first such line in that
order. The job appends no entry for another line.

A line whose step has a promise that is not met at a run gives no
entry. When a later run appends an entry, the start moves past the
commit of that line, and no run reads the line again. The step is
then done when its promises are met, as for every step with promises,
and it is started by its met promises.

## 9. `abandoned`

### 9.1 The fields of an abandoned entry

@req ledger-abandoned v4

An `abandoned` entry closes a plan whose remaining steps no branch
will deliver ([vocabulary.md](vocabulary.md) section 10.8). A person
runs the abandon command; the tool never writes this entry on its own.

| field | meaning |
|---|---|
| `subject` | `plan:<slug>@<id>`: the fact id of the plan, with its full form |
| `reason` | required |

### 9.2 The end of the claim

@req ledger-abandoned-claim

An `abandoned` entry ends the plan's claim. It also releases every
`waiting-on` promise that depended on that claim.

## 10. Open and closed plans

### 10.1 Open and closed

@req ledger-open-plans v3

A plan is **open** until the ledger holds a `completed` or an
`abandoned` entry for its full form ([vocabulary.md](vocabulary.md)
section 4.3). A plan with such an entry is **closed**. Only a ledger
entry closes a plan. No change to the plan file — an edit, a move, or
a deletion — closes a plan.

A closed plan generates no findings, holds no claim, contributes no
scope, and is not a candidate for the active plan. Its slug is free: a
later plan can take the slug, with a new plan id. The file and the
journal of a closed plan can leave `.plans/`.

### 10.2 Claims

A **claim** is an open plan that the ledger holds an approval of, and
whose full form the current tree does not hold
([vocabulary.md](vocabulary.md) section 4.3). A claim
does not depend on a branch. It ends when the plan closes. Sinter
projects each claim from the ledger as a `claim` record
([jsonl.md](jsonl.md) section 7). An open plan that the current tree
holds is no claim, so a branch that delivers a step of a plan on the
default branch sees that plan as a plan, not as a claim.

### 10.3 An absent ledger ref

@req ledger-absent-ref v3

When the ledger ref is absent, a tool sees no `completed` and no
`abandoned` entries, so it treats every plan as open. A tool in this
state, on a tree that holds at least one plan, must warn the user that
it found no ledger, so every plan counts as open. The help of the tool
must say how to fetch the ledger.

## 11. Plan approval: commitment-set comparison

### 11.1 The comparison of commitment sets

@req ledger-plan-approval v4

A plan reaches the default branch in a pull request of its own
([vocabulary.md](vocabulary.md) section 10.1). When the kind `plan`
needs approval, a person approves the plan in the ledger before that
pull request merges. The merge alone does not approve the plan.

A plan's **commitment set** is the set of canonical facts about the
plan: the promises of each step, the scope of each step, and the plan
scope. When the kind `plan` does not need approval
([manifest.md](manifest.md) section 10.1), every plan counts as
approved, and this section does not apply. Otherwise the tool compares
the current set `C` against the approved set `C₀`. The plan is
approved if and only if all three clauses hold:

1. The multiset of `(word, target)` over all promises is equal in `C`
   and `C₀`.
2. The plan scope is contained: `scope(C) ⊆ scope(C₀)`.
3. Match each promise in `C` to a promise in `C₀` by `(word,
   target)`. When several promises share one `(word, target)` pair,
   first match the pairs whose step slugs are equal; then match the
   remaining promises in the order of their step slugs, sorted on both
   sides. For each matched pair, the effective scope of the step in
   `C` must be contained in the effective scope of the step in `C₀`.

### 11.2 Glob containment

@req ledger-glob-containment v2

**Glob containment** `G' ⊆ G` is decided structurally and
conservatively. Every glob in `G'` must satisfy one of these three
cases:

- it appears verbatim in `G`;
- it is a literal path, or a literal path prefix, that some glob in
  `G` matches;
- it is `<g>/<segments>` for some `<g>/**` in `G`.

When the checker cannot prove that a glob satisfies one of these three
cases, the checker treats the new scope as wider than the approved
scope. The rule is decidable and deterministic. When the checker
cannot prove containment, the checker asks a person for a new approval,
which is the safe result for approval.

### 11.3 Free amendments

An amendment is **free** when the plan stays approved after it and no
new approval is needed. The consequences of the three clauses:

- Renaming a step is free, because clause 3 matches by promise and not
  by step name. A delivered step keeps its slug all the same
  ([vocabulary.md](vocabulary.md) section 10.3).
- Reordering steps is free.
- Splitting a step is free when each new step keeps or narrows the
  scope of the original step.
- Merging steps is free only when the scope of the merged step is
  contained in the scope of each original step, for example when the
  original steps have one scope. A merged step that takes the union of
  different scopes widens the scope of some promise, fails clause 3,
  and needs an approval.
- Any promise added or removed fails clause 1 and needs an approval.

## 12. `pin` (deferred)

A `pin` entry will endorse the current hash of external content. It
adds three fields to the common fields of section 4: `approval`,
`external`, and `hash`. The example shows only the fields of the
entry's own:

```json
{"approval":"…","external":"gh/42","hash":"…","kind":"pin"}
```

It is designed but deferred, together with the `@pin` directive.

## 13. Verification

@req ledger-verification

A verifier must check:

1. Every commit on the ref is a fast-forward of its parent.
2. Every commit's ledger file is a byte-prefix extension of its
   parent's.
3. No entry id repeats.

Against a remote, the local ref must also be an ancestor of the
remote's ref, or equal to it.
