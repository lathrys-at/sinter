<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: approval-ledger format

Status: draft.

## 1. Introduction

The ledger is Sinter's append-only record of judgments about a
repository: approvals, refusals, and the end of each plan's life. This
document defines where the ledger lives, how entries are identified,
each entry kind, and the rules that give entries their meaning.

Anyone can implement this specification in any tool. See the
LICENSE-SPEC file at the repository root. Entries are JSONL records in
the canonical form of [jsonl.md](jsonl.md) section 2. The items the
ledger judges are defined in [vocabulary.md](vocabulary.md).

## 2. Storage

The ledger is a JSONL file, `ledger.jsonl`, in the tree of a dedicated
git ref: `refs/sinter/ledger`. This ref is not a checkout path. No
editor or file tool reaches it without git plumbing, which is the
point: writing the ledger is a deliberate act.

Each write appends lines to the file and commits, with the previous
tip as the parent. The ref only moves by fast-forward. Every commit's
ledger file must be a byte-prefix extension of its parent's: old lines
never change and never move.

Unlike the derived JSONL of a scan, ledger entries carry timestamps
and authorship. The ledger is history, not a derivation.

When the repository's manifest sets `ledger.sign`, every ledger commit
is signed, and verification can enforce an allowlist of signer keys.
A deployment that wants the host's push restrictions to protect the
ledger can place the ref under `refs/heads/sinter/ledger` instead.

## 3. Entry identity

An entry's id is `e-` plus the first twelve hex digits of SHA-256 over
the entry's canonical bytes with the `id` key absent. Two writers can
never mint one id for two different entries. So recovery after a lost
push race is a set union: fetch, re-append the local entries absent
upstream, in timestamp order, and push again.

Ids never repeat within the ledger. Where order matters — for example
a decline superseded by a later stamp — the `ts` field decides, never
file position.

## 4. Common fields

Every entry carries:

| field | meaning |
|---|---|
| `id` | entry id (section 3) |
| `kind` | `stamp`, `stamped-scope`, `stamped-promise`, `decline`, `discharged`, or `abandoned` |
| `v` | schema version |
| `by` | who wrote the entry |
| `ts` | RFC 3339 timestamp, UTC |
| `head` | the commit the writer stood on |
| `branch` | the branch the writer stood on |
| `tool` | tool version |

Four writers exist. The approval command writes `stamp` entries, with
their `stamped-scope` and `stamped-promise` lines. The decline command
writes `decline`. The abandon command writes `abandoned`. These three
are human verbs. The fourth writer is the main-branch CI job, which
writes `discharged` (section 8).

## 5. `stamp`

A stamp records an approval.

| field | meaning |
|---|---|
| `subject` | for example `req:auth-lockout` or `plan:auth-lockout` |
| `rev` `xh` | declarations only: the revision and extent hash approved |
| `csh` | plans only: the commitment-set hash ([jsonl.md](jsonl.md) section 4) |
| `note` | omitted when none |

Approval attaches to the `(slug, rev, xh)` triple, never to a
document. A declaration of a gated kind is **approved** if and only if
the ledger holds a stamp for its current `(slug, rev, xh)`. A revision
bump therefore removes approval until the item is stamped again.

**Revision reservation.** A writer must refuse to write a stamp for
`(slug, rev)` when the ledger already holds a stamp for that pair with
a different `xh`. The refusal names the earlier entry and its branch;
the resolution is a further bump. A stamp with an equal `xh` is
idempotent and is skipped.

## 6. `stamped-scope` and `stamped-promise`

A plan stamp embeds the approved commitment set, because a hash cannot
be diffed against. Two entry kinds carry it.

**`stamped-scope`** — one per glob. When `step` is omitted, the glob is
plan-level.

| field | meaning |
|---|---|
| `stamp` | the stamp entry this belongs to |
| `step` | step slug; omitted for the plan scope |
| `glob` | one scope glob |

**`stamped-promise`** — one per promise.

| field | meaning |
|---|---|
| `stamp` | the stamp entry this belongs to |
| `step` | step slug |
| `word` `target` | the promise |

## 7. `decline`

A decline records a human refusal, bound to the exact text refused.

| field | meaning |
|---|---|
| `subject` | fact id |
| `hash` | the subject's extent hash (`xh`) or commitment-set hash (`csh`) at the moment of refusal |
| `reason` | required |

A decline is **live** while the subject's current hash equals `hash`
and no later stamp of the subject exists. A decline is never deleted.
A later stamp supersedes it in effect — at a different hash, or at the
same hash when the human overrides their own refusal.

## 8. `discharged`

A discharge records the end of a plan whose promises all became fact.
The main-branch CI job writes it: on every push to the target branch,
the job finds in-force plans that are now on that branch, checks each
against the discharge condition, and appends an entry for each plan
that meets it.

| field | meaning |
|---|---|
| `subject` | `plan:<slug>` |
| `stamp` | the stamp the plan died under |
| `merge` | the merge commit |
| `report` | SHA-256 of the report compiled at discharge |

**The discharge condition.** Every promise of the plan has its
residue: promised declarations exist; promised edges exist and are
neither dangling nor suspect; promised `verifies` edges are at rung
`passing` (or `unattributed` where the manifest allows it) when the
job imports evidence, and at any rung when it does not. An in-force
plan on the target branch that fails this condition is the
`undischarged-plan` finding: someone merged half a plan. The honest
exits are a stamped shrink of the plan or a revert of the merge.

The writer is idempotent bookkeeping. The plan's stamps and the tree
are the evidence, so a lost CI run costs a retry, not truth.

## 9. `abandoned`

An abandonment records that a stamped plan will never merge. It is a
human verb.

| field | meaning |
|---|---|
| `subject` | `plan:<slug>` |
| `reason` | required |

Abandonment ends the plan's lease and every ordering fact that rested
on it.

## 10. Plan death and liveness

A plan is **live** until the ledger holds a `discharged` or
`abandoned` entry for it. Death is a ledger fact, never a file event:
the plan file stays in the tree. A dead plan generates no findings,
holds no lease, contributes no scope, and is not a candidate for the
active plan. Plan slugs are permanent; a successor plan needs a new
slug.

Without the ledger ref, every plan reads as live. A consumer should
say so loudly and suggest fetching the ref.

## 11. Plan approval: commitment-set comparison

A plan's **commitment set** is the canonical facts of its promises and
scopes per step. The current set `C` is compared against the stamped
set `C₀`. The plan is approved if and only if all three clauses hold:

1. The multiset of `(word, target)` over all promises is equal.
2. The plan scope is contained: `scope(C) ⊆ scope(C₀)`.
3. For each promise, matched by `(word, target)` — among duplicates,
   matched by step slug first, then arbitrarily — the effective scope
   of its step in `C` is contained in the effective scope of its step
   in `C₀`.

**Glob containment** `G' ⊆ G` is decided structurally and
conservatively. Every glob in `G'` must satisfy one of:

- it appears verbatim in `G`;
- it is a literal path, or a literal path prefix, that some glob in
  `G` matches;
- it is `<g>/<segments>` for some `<g>/**` in `G`.

Anything the checker cannot prove counts as widening. The rule is
decidable and deterministic, and it errs toward asking the human,
which is the correct direction for an approval gate.

The consequences: renaming steps is free, because clause 3 matches by
promise, not by step name. Reordering steps is free. Splitting a step
is free when each fragment keeps or narrows its scope. Merging steps
is free when the merged scope equals the originals', and needs a stamp
otherwise. Any promise added or removed fails clause 1 and needs a
stamp.

## 12. `pin` (deferred)

A `pin` entry will endorse the current hash of external content:

```json
{"kind":"pin","stamp":"…","ref":"gh/42","hash":"…"}
```

It is designed but deferred, together with the `@pin` directive.

## 13. Verification

A verifier must check:

1. Every commit on the ref is a fast-forward of its parent.
2. Every commit's ledger file is a byte-prefix extension of its
   parent's.
3. No entry id repeats.

Against a remote, the local ref must also be an ancestor of the
remote's ref, or equal to it. With a signer allowlist, every commit
must carry a valid signature from a listed key.
