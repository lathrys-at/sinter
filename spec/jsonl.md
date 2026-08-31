<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: JSON Lines interchange schema

Status: draft.

## 1. Introduction

Sinter emits its facts — nodes, edges, promises, evidence, findings —
as JSON Lines (JSONL), so that other tools can read them. This
document defines the canonical form, the envelope that every fact
carries, each record type, and fact identity.

Anyone can implement this specification in any tool. See the
LICENSE-SPEC file at the repository root. The tags that produce these
facts are defined in [vocabulary.md](vocabulary.md). The kinds and
categories are listed in [algebra.md](algebra.md). Ledger entries are
also JSONL records; they are defined in [ledger.md](ledger.md).

The JSONL is always derived from the repository's text, the ledger,
and the evidence set. It is never a source of truth.

## 2. Canonical form

One fact per line. Each line is a JSON object canonicalized per RFC
8785 (JCS): keys sorted by UTF-16 code units, no insignificant
whitespace, strings escaped per JCS, UTF-8 encoding, LF terminated.
The schema restricts values so that JCS stays trivial to implement:

- **Value types:** string; integer in `[-(2^53-1), 2^53-1]`; boolean;
  or an array of those. No floats, no nulls, no nested objects. An
  absent value is an omitted key, never `null`.
- **Strings** that come from file text are NFC-normalized. Ids and
  paths are used as-is.
- **Paths** are repository-relative, with forward slashes and no
  leading `./`.
- **Hashes** are lowercase hex. An extent hash (`xh`) is 64 hex
  characters (SHA-256). A tree key or a git revision is 40 hex
  characters.

A file of facts is sorted by `(kind, path, line, col, id)`. Unlocated
facts sort after located ones, by `id`. The first line is the `index`
header (section 10). Two scans of the same inputs — tree, base,
ledger, evidence, session — produce byte-identical output.

The schema version is the integer `v` on every line. It is bumped only
for an incompatible change to a kind's required fields or identity.
Adding an optional field is not a bump.

## 3. Envelope

Every fact carries:

| field | type | meaning |
|---|---|---|
| `v` | int | schema version (`1`) |
| `kind` | string | a kind from [algebra.md](algebra.md) section 3, or `index`, `summary`, or a ledger kind |
| `id` | string | stable identity (section 9) |
| `pack` | string | for facts extracted from a governed file: the pack that produced the fact |

Located facts add:

| field | type | meaning |
|---|---|---|
| `path` | string | file |
| `line` `col` | int | 1-based start |
| `eline` `ecol` | int | inclusive end line; exclusive end column |

For a declaration in markdown, this span is the tag line only. The
extent — the whole section — is carried separately as `xline` and
`xeline`, so that a tool can highlight the tag without highlighting
pages of prose.

Fields marked *derived* below are computed from the ledger, the
evidence, the session, or the base — not from the file. They are
present so that consumers need not re-derive them. Derived fields are
included in conformance comparison, so conformance fixtures ship their
own ledger and evidence.

## 4. Node records

**`req` / `design` / `decision`**

| field | type | meaning |
|---|---|---|
| `slug` | string | |
| `rev` | int | `N` from `vN` |
| `xh` | string | extent hash ([vocabulary.md](vocabulary.md) section 6.1) |
| `xline` `xeline` | int | extent span |
| `title` | string | markdown: the heading text; code: omitted |
| `desc` | string | the description; omitted when empty |
| `status` | string | `deprecated`, `rejected`, or `deferred`; omitted when none |
| `inforce` | bool | *derived* |
| `approved` | bool | *derived* |
| `stamp` | string | *derived*: the ledger stamp id, when approved |
| `gated` | bool | whether the manifest gates this kind on approval |
| `declined` | bool | *derived*: a live decline exists for `(slug, xh)` |

Example:

```json
{"approved":true,"col":1,"desc":"Five consecutive failures within ten minutes freeze the account.","ecol":21,"eline":13,"gated":true,"id":"req:auth-lockout","inforce":true,"kind":"req","line":13,"pack":"markdown","path":"docs/auth.md","rev":2,"slug":"auth-lockout","stamp":"s-41","title":"Lock account after 5 failed attempts","v":1,"xeline":29,"xh":"9f3a…","xline":12}
```

**`plan`**

| field | type | meaning |
|---|---|---|
| `slug` `title` | string | |
| `scope` | array of string | plan-level globs |
| `approved` | bool | *derived*: the current commitment set is approved against the last stamp ([ledger.md](ledger.md)) |
| `stamp` | string | *derived* |
| `active` | bool | *derived* from the session |
| `live` | bool | *derived*: no `discharged` or `abandoned` ledger entry exists for the plan |
| `csh` | string | commitment-set hash: SHA-256 over a canonical form with no step names — the sorted `(word, target, effective step scope)` triples plus the plan scope. Free step renames leave it unchanged, so a decline bound to it survives them |
| `declined` | bool | *derived* |

**`step`**

| field | type | meaning |
|---|---|---|
| `plan` | string | plan slug |
| `slug` `title` | string | slug derived per [vocabulary.md](vocabulary.md) section 10.3 |
| `scope` | array of string | the *effective* scope |
| `own_scope` | bool | whether the step declared its own `@scope` |
| `refactor` | bool | the step has no promises |
| `met` `total` | int | *derived* promise counts |
| `done` | bool | *derived* |
| `active` | bool | *derived* |

**`test`**

| field | type | meaning |
|---|---|---|
| `name` | string | the ID the pack's strategy produced — the same string the test runner reports |
| `parents` | array of string | `describe`-style ancestry where the language has it, outermost first |
| `dline` `deline` | int | span of the test's body |

**`site`**

| field | type | meaning |
|---|---|---|
| `name` | string | name of the attached definition, when the pack captured one — qualified (impl, class, or module path) where the language nests |
| `node` | string | the tree-sitter node type of the attached definition, for example `function_item` |
| `dline` `deline` | int | span of the attached definition's body — the frame coverage is measured against |
| `ch` | string | code hash ([vocabulary.md](vocabulary.md) section 6.2) |

## 5. Edge, ref, and promise records

**edge** — `kind` is `satisfies`, `verifies`, `refines`, `cites`, or
`supersedes`.

| field | type | meaning |
|---|---|---|
| `src` | string | id of the source fact (a node or a rule) |
| `target` | string | the target as written: a slug or `ns/id` |
| `dst` | string | *derived*: id of the resolved target; omitted when dangling |
| `rev` | int | the pinned revision; omitted when unpinned |
| `desc` | string | inline description; omitted when empty |
| `suspect` `dangling` | bool | *derived* |
| `rung` | string | `verifies` only, *derived*: `orphan`, `never-ran`, `failed`, `disconnected`, `unattributed`, or `passing` |
| `live` | bool | `supersedes` only, *derived* |

Tags inside plan files never produce edge records. They produce
promise records.

Example:

```json
{"col":5,"dst":"req:auth-lockout","ecol":31,"eline":40,"id":"verifies:test:auth::lockout::tests::locks_after_five_failures->auth-lockout","kind":"verifies","line":40,"pack":"rust","path":"src/auth/lockout.rs","rev":2,"rung":"passing","src":"test:auth::lockout::tests::locks_after_five_failures","target":"auth-lockout","v":1}
```

**`ref`** — unlocated; one record per distinct target.

| field | type | meaning |
|---|---|---|
| `ns` | string | namespace |
| `ref` | string | id within the namespace |

**`promise`**

| field | type | meaning |
|---|---|---|
| `plan` `step` | string | slugs |
| `word` | string | `req`, `design`, `decision`, `satisfies`, `verifies`, `refines`, `cites`, or `supersedes` |
| `target` | string | as written |
| `met` | bool | *derived* |
| `by` | string | *derived*: id of the discharging fact, when met |
| `out_of_scope` | bool | *derived*: residue that would discharge the promise exists only outside the step's scope; `met` stays false |

Duplicate promissory tags within one step collapse into one promise
record.

## 6. Evidence records

**`run`** — unlocated.

| field | type | meaning |
|---|---|---|
| `test` | string | test fact id. A run that binds to no test fact is not emitted as a fact; the import step reports it |
| `status` | string | `pass`, `fail`, `error`, or `skip`. Several artifacts for one test merge to the worst status |
| `tree` | string | tree key |
| `sources` | array of string | artifact paths, as imported |
| `ms` | int | duration, when the artifact reports one |

**`cov`** — unlocated. This is the site-level join, not raw line data.

| field | type | meaning |
|---|---|---|
| `test` | string | test fact id, or `*` for aggregate coverage |
| `site` | string | site fact id |
| `hit` `of` | int | executable lines inside the site's attached definition that were hit / that exist |
| `attributed` | bool | `false` if and only if `test` is `*` |
| `tree` | string | tree key |

**`judgment`** — unlocated. Written by a judge or an external checker
into the evidence directory, never into the tree.

| field | type | meaning |
|---|---|---|
| `rule` | string | rule name |
| `subject` | string | id of the fact judged |
| `verdict` | string | `pass` or `fail` |
| `judge` | string | model or program identifier |
| `hash` | string | the subject's extent hash (or commitment-set hash) at judgment time. The judgment is live while the hash matches, so unrelated edits do not void it |
| `reason` | string | one line |

## 7. Ledger-projection, law, ack, hunk, and tombstone records

**`lease`** — unlocated. Projected from the ledger, one per stamped
plan on another branch that is neither discharged nor abandoned and
whose branch existed on the remote at the last fetch.

| field | type | meaning |
|---|---|---|
| `plan` | string | plan slug |
| `branch` | string | the branch the stamp was written from |
| `stamp` | string | latest stamp id |
| `scope` | array of string | union of the stamped step scopes |
| `declares` | array of string | slugs the lease promises to declare |
| `stamped` | string | RFC 3339 timestamp |

**`decline`** — unlocated. Projected from the ledger; live entries
only.

| field | type | meaning |
|---|---|---|
| `subject` | string | fact id |
| `hash` | string | the extent or commitment-set hash the refusal was bound to |
| `reason` | string | |
| `by` `ts` | string | |
| `entry` | string | ledger entry id |

**`rule`** — located in the manifest.

| field | type | meaning |
|---|---|---|
| `name` `origin` `trigger` `discharge` | string | as declared |
| `via` | string | `checked`, `judged`, or `acked` — inferred from the discharge expression |
| `scope` | array of string | |
| `triggered` | bool | *derived* |
| `owed` | int | *derived* obligation count |

**`gate`** — located in the manifest; one record per `(gate, class)`
pair, with defaults materialized.

| field | type | meaning |
|---|---|---|
| `gate` | string | `turn`, `pr`, or `main` |
| `class` | string | finding class |
| `tier` | string | `off`, `warn`, or `block` |
| `default` | bool | `true` when the manifest does not set this pair |

**`ack`**

| field | type | meaning |
|---|---|---|
| `block` | string | id of the block's primary fact: the declaration, site, or test the block belongs to |
| `target` | string | as written, for example `disendorsed cache-ttl` or `ste-docs` |
| `hash` | string | as written |
| `live` | bool | *derived* |
| `void` | string | *derived*: `hash` or `target`, naming the failed condition; omitted when live |
| `for` | string | *derived*: id of the finding discharged, or of the rule, when live |

**`hunk`** — diff mode only; new-side coordinates. A pure deletion has
`line = eline =` the line after the deletion, and `added = 0`.

| field | type | meaning |
|---|---|---|
| `added` `removed` | int | |
| `ambient` | bool | *derived* |
| `mapped` | array of string | *derived*: ids of the steps or rules whose scope covers the hunk; empty when unmapped |

**`tombstone`** — base coordinates.

| field | type | meaning |
|---|---|---|
| `of` | string | the kind of the vanished fact |
| `was` | string | its id at the base |
| `slug` `rev` `xh` | | for declarations, so that renames can be computed |

## 8. Finding records

**`finding`** — located at its subject.

| field | type | meaning |
|---|---|---|
| `class` | string | a class from [algebra.md](algebra.md) section 9 |
| `subject` | string | id of the fact the finding is about |
| `rule` | string | `rule-owed` findings only |
| `detail` | string | one line, human-facing, deterministic |
| `fix` | string | the exact `@ack` line to paste, or a one-line instruction; omitted when none |
| `ackable` | bool | |
| `acked` | bool | present only when acked findings are requested |
| `tier` `gate` | string | the tier under the gate the check ran with |
| `mode` | string | `tree` or `diff` |

## 9. Identity

Ids make baseline subtraction, `@ack` targeting, and fingerprints work
across line shifts. An id is content-derived wherever content exists,
and positional only as a last resort.

| kind | id | notes |
|---|---|---|
| `req` `design` `decision` `plan` | `<kind>:<slug>` | |
| `step` | `step:<plan>/<step>` | |
| `test` | `test:<name>` | `name` can contain spaces |
| `site` | `site:<path>#<name>` | fallback `site:<path>@L<line>` is positional and carries `"positional":true` |
| edges | `<kind>:<src-id>-><target>` | parse from the right: a target cannot contain `->` |
| `ref` | `ref:<ns>/<id>` | |
| `promise` | `promise:<step-id>:<word>:<target>` | parse from the right |
| `run` | `run:<test-id>@<tree>` | |
| `cov` | `cov:<test-id or *>@<site-id>` | |
| `judgment` | `judgment:<rule>:<subject-id>@<hash>` | |
| `lease` | `lease:<plan>@<branch>` | |
| `decline` | `decline:<entry-id>` | |
| `rule` | `rule:<name>` | |
| `gate` | `gate:<gate>/<class>` | |
| `ack` | `ack:<block-id>:<target>` | anchored to the block, not to a line |
| `hunk` | `hunk:<path>:<line>-<eline>` | positional by nature |
| `tombstone` | `tombstone:<was>` | |
| `finding` | `finding:<class>:<subject-id>[:<rule>]` | |

An id is stable under re-indentation, reformatting, line shifts, and
re-pinning. It changes under a slug rename (rename is deletion plus
declaration), under moving a site to a different named definition, and
under retargeting an edge.

## 10. Header and summary records

**`index`** — the first line of every scan. Excluded from conformance
comparison.

| field | type | meaning |
|---|---|---|
| `tree` | string | tree key |
| `base` | string | resolved base revision |
| `target` | string | target branch |
| `ledger` | string | ledger tip commit; omitted when the ref is absent |
| `evidence` | bool | whether evidence exists for `tree` |
| `packs` | array of string | `name@version#hash`, from the lockfile |
| `tool` | string | tool version |
| `mode` | string | `tree` or `diff` |

**`summary`** — the first line of `status --json`.

| field | type |
|---|---|
| `plan` `step` | string; omitted when none |
| `done` | bool |
| `steps_done` `steps_total` | int |
| `block` `warn` | int (finding counts under the turn tier set) |
| `unmapped` | int (hunks) |
| `owed` | int (rule obligations) |
| `evidence_fresh` | bool |
| `bumps` | int (declarations bumped since the base) |
| `acks_live` `acks_void` | int |
| `declines` | int (live, in scope) |
| `leases` `blocked` | int |
| `code_drift` | int |
| `law_touched` | bool |

## 11. Conformance

A language pack's fixture directory contains a small project, an
`expected.jsonl` file, a fixture ledger, and real runner and coverage
artifacts with attribution. Verification scans the fixture with the
fixture ledger and evidence, drops the header line, and requires byte
equality with `expected.jsonl`. Because derived fields are included,
the fixture exercises evidence binding end to end, not only parsing. A
tool release that changes any derived field's semantics must
regenerate every pack's fixture.
