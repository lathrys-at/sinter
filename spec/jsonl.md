<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: JSON Lines interchange schema

Status: draft. The six specifications share one version; see [docs/versioning.md](../docs/versioning.md).

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

Sinter always derives the JSONL from the repository's text, the
ledger, and the evidence set. The JSONL is never a source of truth.

## 2. Canonical form

One fact per line. Each line is a JSON object in the canonical form of
RFC 8785 (JCS). Each line must meet all of these conditions:

- The keys are sorted by UTF-16 code units.
- The line holds no insignificant whitespace.
- The strings are escaped as JCS requires.
- The line is encoded as UTF-8.
- The line ends with LF.

The schema restricts values so that JCS stays trivial to implement:

- **Value types:** string; integer in `[-(2^53-1), 2^53-1]`; boolean;
  or an array of those. No floats, no nulls, no nested objects. An
  absent value is an omitted key, never `null`.
- **Strings:** Sinter writes a string that comes from the text of a
  file as the file holds it. It does not normalize Unicode in a string
  of a governed file, of the manifest, or of the front matter of a
  rule file ([manifest.md](manifest.md) sections 2.2 and 15). Tools
  compare strings by their bytes: two strings are equal only when
  their bytes are equal.
- **Paths** are repository-relative, with forward slashes and no
  leading `./`.
- **Hashes** are lowercase hex. An extent hash (`xh`) is 64 hex
  characters (SHA-256). A tree key or a git revision is 40 hex
  characters, or 64 in a repository that uses git's SHA-256 object
  format.

A fact is **located** when it carries a path and a line span (section
3); otherwise it is **unlocated**. Sinter sorts a file of facts by
`(kind, path, line, col, id)`. Unlocated facts sort after located
facts, by `id`. The first line is the `index` header (section 10). Two
scans of the same inputs — tree, base, ledger, evidence, session —
produce byte-identical output.

The schema version is the integer `v` on every line. Sinter increases
`v` only for an incompatible change to a kind's required fields or to
a kind's identity. A new optional field does not increase `v`.

## 3. Envelope

Every fact carries:

| field | type | meaning |
|---|---|---|
| `v` | int | schema version (`1`) |
| `kind` | string | a kind from [algebra.md](algebra.md) section 3, or `index`, `summary`, or a ledger kind |
| `id` | string | stable identity (section 9) |
| `pack` | string | for facts extracted from a governed file: the pack that produced the fact; omitted on the facts of the manifest |

Located facts add:

| field | type | meaning |
|---|---|---|
| `path` | string | file |
| `line` `col` | int | start |
| `eline` `ecol` | int | inclusive end line; exclusive end column |

Lines and columns count from 1. A column counts Unicode code points
(characters), not bytes. A line ends at a line feed (LF). A carriage
return (CR) right before an LF is part of the line ending. The
characters of a line ending count in no column. A byte order mark at
the start of a file is part of no line, and it counts in no column. A
span ends at its last character that is not part of a line ending
([packs.md](packs.md) section 5.3).

The span of a tag line starts at its `@`. On the first line of a list
item, the list marker and the task marker are no part of the span.

For a declaration in markdown, this span is the tag line only. The
record carries the extent separately, in `xline` and `xeline`: the
first and the last line of the extent ([vocabulary.md](vocabulary.md)
section 6). The last line of an extent is never a blank line. A tool
can therefore highlight the tag without highlighting the whole extent.

Sinter computes the fields marked *derived* below from the ledger, the
evidence, the session, or the base — not from the file. Sinter emits
derived fields so that a tool that reads the JSONL does not have to
compute them again. Conformance comparison includes derived fields, so
conformance fixtures ship their own ledger and evidence.

## 4. Node records

**`req` / `design` / `decision`**

| field | type | meaning |
|---|---|---|
| `slug` | string | |
| `rev` | int | `N` from `vN` |
| `xh` | string | extent hash ([vocabulary.md](vocabulary.md) section 6.1) |
| `xline` `xeline` | int | extent span |
| `title` | string | a declaration in a markdown section: the heading text of the section ([vocabulary.md](vocabulary.md) section 10.3); otherwise omitted |
| `desc` | string | the description, as the text after this table gives it; omitted when empty |
| `status` | string | `deprecated`, `rejected`, or `deferred`; omitted when none |
| `inforce` | bool | *derived* |
| `approved` | bool | *derived* |
| `approval` | string | *derived*: the id of the `approval` entry of the ledger that approves the declaration; omitted when none |
| `approval_required` | bool | whether the kind needs approval: `ledger.approval-required` lists it ([manifest.md](manifest.md) section 11.1) |
| `declined` | bool | *derived*: a live decline exists for `(slug, xh)` |

Sinter makes the field `desc` in three steps:

1. Take the inline description of the declaration's tag, and then each
   line of the trailing prose of its block
   ([vocabulary.md](vocabulary.md) section 3.2).
2. Remove the spaces and tabs at both ends of each of these parts.
   Leave out the inline description when it is then empty.
3. Join the parts, with one LF between each two parts.

When the result is empty, the record omits `desc`.

Example:

```json
{"approval":"s-41","approval_required":true,"approved":true,"col":1,"desc":"Five consecutive failures within ten minutes freeze the account.","ecol":21,"eline":13,"id":"req:auth-lockout","inforce":true,"kind":"req","line":13,"pack":"markdown","path":"docs/auth.md","rev":2,"slug":"auth-lockout","title":"Lock account after 5 failed attempts","v":1,"xeline":29,"xh":"9f3a…","xline":12}
```

**`plan`**

| field | type | meaning |
|---|---|---|
| `slug` | string | |
| `title` | string | the heading text of the section that holds the `@plan` tag ([vocabulary.md](vocabulary.md) section 10.3); omitted for the section of level 0 |
| `scope` | array of string | plan-level globs |
| `approved` | bool | *derived*: the plan is approved ([algebra.md](algebra.md) section 6.5) |
| `approval` | string | *derived* |
| `active` | bool | *derived* from the session; `false` when there is no session |
| `open` | bool | *derived*: the plan is open — the ledger holds no `completed` entry and no `abandoned` entry for it ([ledger.md](ledger.md) section 10) |
| `csh` | string | the commitment-set hash, as the text after this table gives it |
| `declined` | bool | *derived* |

The **commitment-set hash** (`csh`) is SHA-256 over canonical bytes
that hold the plan's commitment set ([vocabulary.md](vocabulary.md)
section 10.6): the promises, each with the effective scope of its
step, and the plan scope. The canonical bytes are one JSON object in
the canonical form of RFC 8785 (JCS) that section 2 uses, with no LF
at the end. The object has two keys:

- `promises`: an array with one object for each promise record of the
  plan (section 5). Each object has three keys: `word` and `target`,
  as the promise record gives them, and `scope`, the effective scope
  of the promise's step. Two promises of two steps can give two equal
  objects. Then the array holds both objects.
- `scope`: the globs of the plan's own `@scope` line, or an empty
  array when the plan has no `@scope` line.

Each array of globs holds each glob once, sorted in byte order. The
promise objects are sorted by `word`, then by `target`, then by the
canonical bytes of their `scope` array, each in byte order. The rules
of section 2 for the values of a record do not apply to this object.

The object holds no step slug, and a step with no promise adds nothing
to it. So a step rename does not change `csh`, and a decline bound to
`csh` stays live after a step rename.

Example: this plan file gives the canonical bytes below it.

```
# Auth lockout

@plan auth-lockout
@scope src/**

## Lock the account

@scope src/auth/**
@req auth-lockout
@verifies auth-lockout

## Record the policy

@decision lockout-policy
```

```
{"promises":[{"scope":["src/**"],"target":"lockout-policy","word":"decision"},{"scope":["src/auth/**"],"target":"auth-lockout","word":"req"},{"scope":["src/auth/**"],"target":"auth-lockout","word":"verifies"}],"scope":["src/**"]}
```

**`step`**

| field | type | meaning |
|---|---|---|
| `plan` | string | plan slug |
| `slug` `title` | string | the slug and the heading text of the step's heading, per [vocabulary.md](vocabulary.md) section 10.3 |
| `scope` | array of string | the *effective* scope |
| `own_scope` | bool | whether the step declared its own `@scope` |
| `refactor` | bool | the step has no promises |
| `met` `total` | int | *derived* promise counts |
| `done` | bool | *derived* |
| `active` | bool | *derived* from the session; `false` when there is no session |

**`test`** — a test, or a group of tests, that a language pack finds
([packs.md](packs.md) section 8). The span of the record is the node
of the test or the group.

| field | type | meaning |
|---|---|---|
| `name` | string | the test's own name, as the source writes it ([packs.md](packs.md) section 8.3) |
| `parents` | array of string | the names of the groups that hold the test, outermost first |
| `group` | bool | `true` for a group of tests; omitted for a test |
| `dline` `deline` | int | the first and the last line of the node of the test |

**`site`** — an anonymous source: a code site, or a markdown section
that holds a citation outside every declaration's extent
([vocabulary.md](vocabulary.md) section 7.2). For a markdown section,
the span of the record is the first paragraph of the section.

| field | type | meaning |
|---|---|---|
| `name` | string | code: the name path of the attached definition, when the pack captured a name ([packs.md](packs.md) section 6.5). In a language that nests definitions, the name path carries the names of the containing impls, classes, or modules. Markdown: the slug of the section's heading, numbered as [vocabulary.md](vocabulary.md) section 7.2 says; omitted for the section of level 0 |
| `node` | string | code only: the tree-sitter node type of the attachment target, for example `function_item`; omitted when the block attaches to nothing |
| `dline` `deline` | int | code only: the span of the body of the attachment target. Coverage for this site is measured over this span. Omitted when the block attaches to nothing |
| `ch` | string | code only: code hash ([vocabulary.md](vocabulary.md) section 6.2); omitted when the block attaches to nothing |
| `xline` `xeline` | int | markdown only: the first and the last line of the extent of the section ([vocabulary.md](vocabulary.md) section 6) |

## 5. Edge, ref, and promise records

**edge** — `kind` is `satisfies`, `verifies`, `refines`, `cites`, or
`supersedes`.

| field | type | meaning |
|---|---|---|
| `src` | string | id of the source fact (a node or a rule) |
| `target` | string | the tag target as written: a slug or `ns/id` |
| `dst` | string | *derived*: id of the fact that the tag target resolves to; omitted when the tag target resolves to nothing |
| `rev` | int | the pinned revision; omitted when unpinned |
| `desc` | string | inline description, without the spaces and tabs at both ends; omitted when empty |
| `suspect` `dangling` | bool | *derived* |
| `rung` | string | `verifies` only, *derived*: `wrong-source`, `never-ran`, `failed`, `unexercised`, `unmeasured`, or `passing` |
| `effective` | bool | `supersedes` only, *derived*: whether the edge is effective ([vocabulary.md](vocabulary.md) section 8.1) |

Tags inside plan files never produce edge records. These tags produce
promise records instead.

Example:

```json
{"col":5,"dst":"req:auth-lockout","ecol":31,"eline":40,"id":"verifies:test:src/auth/lockout.rs#tests::locks_after_five_failures->auth-lockout","kind":"verifies","line":40,"pack":"rust","path":"src/auth/lockout.rs","rev":2,"rung":"passing","src":"test:src/auth/lockout.rs#tests::locks_after_five_failures","target":"auth-lockout","v":1}
```

**`ref`** — unlocated; one record per distinct ref.

| field | type | meaning |
|---|---|---|
| `ns` | string | namespace |
| `ref` | string | id within the namespace |

**`promise`**

| field | type | meaning |
|---|---|---|
| `plan` `step` | string | slugs |
| `word` | string | `req`, `design`, `decision`, `satisfies`, `verifies`, `refines`, `cites`, or `supersedes` |
| `target` | string | the tag target, as written |
| `met` | bool | *derived* |
| `by` | string | *derived*: id of the fact that meets the promise, when met |
| `out_of_scope` | bool | *derived*: `true` when facts that would meet the promise exist, but every such fact sits outside the step's scope. In this case `met` stays `false` ([vocabulary.md](vocabulary.md) section 10.5) |

Duplicate promissory tags within one step collapse into one promise
record.

## 6. Evidence records

**`run`** — unlocated.

| field | type | meaning |
|---|---|---|
| `test` | string | test fact id: a test or a group ([packs.md](packs.md) section 9.2). When a result binds to no test fact, the scanner emits no `run` fact for that result; the evidence import reports the unbound result instead |
| `status` | string | `pass`, `fail`, `error`, or `skip`. When several results bind to one test, the fact carries the worst status among them. The order, from best to worst, is: `pass`, `skip`, `fail`, `error` |
| `tree` | string | tree key |
| `sources` | array of string | artifact paths, as imported |
| `ms` | int | duration, when the artifact reports one |

**`cov`** — unlocated. A `cov` fact reports coverage for one whole
site. It does not report coverage for single lines.

| field | type | meaning |
|---|---|---|
| `test` | string | test fact id, or `*` for aggregate coverage |
| `site` | string | site fact id |
| `hit` `of` | int | executable lines inside the site's attached definition that were hit / that exist |
| `attributed` | bool | `false` if and only if `test` is `*` |
| `tree` | string | tree key |

**`judgment`** — unlocated. A judge or an external checker writes it
into the evidence directory, never into the tree.

| field | type | meaning |
|---|---|---|
| `rule` | string | rule name |
| `subject` | string | id of the fact judged |
| `verdict` | string | `pass` or `fail` |
| `judge` | string | model or program identifier |
| `hash` | string | the subject's extent hash (or commitment-set hash) at judgment time. The judgment is live while the hash matches, so unrelated edits do not void it |
| `reason` | string | one line |

## 7. Ledger-projection, rule, gate, setting, ack, hunk, and tombstone records

**`claim`** — unlocated. Sinter projects claim records from the
ledger. It emits one record for each approved plan that meets all three
conditions:

- The plan's approval was written from a branch other than the current
  one.
- The plan is open ([ledger.md](ledger.md) section 10).
- That branch existed on the remote at the last fetch.

| field | type | meaning |
|---|---|---|
| `plan` | string | plan slug |
| `branch` | string | the branch the approval was written from |
| `approval` | string | the id of the latest `approval` entry |
| `scope` | array of string | union of the approved step scopes |
| `declares` | array of string | slugs the claim promises to declare |
| `ts` | string | RFC 3339 timestamp of the approval |

**`decline`** — unlocated. Sinter projects decline records from the
ledger. It emits live entries only.

| field | type | meaning |
|---|---|---|
| `subject` | string | fact id |
| `hash` | string | the extent or commitment-set hash the refusal was bound to |
| `reason` | string | |
| `by` `ts` | string | |
| `entry` | string | ledger entry id |

**`rule`** — located in its rule file ([manifest.md](manifest.md)
section 15).

| field | type | meaning |
|---|---|---|
| `name` `origin` `trigger` `expect` | string | as declared |
| `via` | string | `checked`, `judged`, or `acked` — inferred from the `expect` expression |
| `scope` | array of string | |
| `triggered` | bool | *derived* |
| `obligations` | int | *derived* obligation count |

**`gate`** — Sinter emits one record for each pair of a gate and a
finding class that takes a tier at that gate ([manifest.md](manifest.md)
section 14.2). A record whose pair `check.tiers` writes is located at
that entry of the manifest. A record whose pair the manifest does not
write is unlocated. Every fact of a manifest outside the repository
is unlocated.

| field | type | meaning |
|---|---|---|
| `gate` | string | `turn`, `merge`, or `target` |
| `class` | string | finding class |
| `tier` | string | the tier that applies ([manifest.md](manifest.md) section 9.3): `off`, `warn`, or `block` |
| `default` | bool | `true` when `check.tiers` does not write this pair |
| `capped` | bool | `true` when the rollout cap lowered the tier |

**`setting`** — one value of the manifest ([manifest.md](manifest.md)
section 14.1). A setting fact that the manifest writes is located in
the manifest ([manifest.md](manifest.md) section 14.3). A default fact
and a built-in fact are unlocated. Every fact of a manifest outside
the repository is unlocated.

| field | type | meaning |
|---|---|---|
| `key` | string | the key path |
| `value` | string | a string as TOML decodes it; `true` or `false` for a boolean; for a built-in member, its glob or its path |
| `member` | bool | `true` when the fact is one member of an array |
| `default` | bool | `true` when the manifest does not write the key, and the fact holds the default value |
| `builtin` | bool | `true` when the fact is a built-in member |

**`ack`**

| field | type | meaning |
|---|---|---|
| `block` | string | id of the block's primary fact: the declaration, site, or test the block belongs to |
| `target` | string | the tag target, as written, for example `retired cache-ttl` or `ste-docs` |
| `hash` | string | as written |
| `live` | bool | *derived* |
| `void` | string | *derived*: `hash` or `target`, naming the failed condition ([vocabulary.md](vocabulary.md) section 7.4); omitted when live |
| `for` | string | *derived*: id of the finding accepted, or of the rule, when live |

**`hunk`** — diff mode only; new-side coordinates. A pure deletion has
`line = eline =` the line after the deletion, and `added = 0`.

| field | type | meaning |
|---|---|---|
| `added` `removed` | int | |
| `ambient` | bool | *derived* |
| `shared` | bool | *derived*: the hunk is under a shared path (`plan.shared`, [manifest.md](manifest.md) section 10.3) |
| `mapped` | array of string | *derived*: ids of the steps or rules whose scope covers the hunk; empty when unmapped |

**`tombstone`** — base coordinates.

| field | type | meaning |
|---|---|---|
| `of` | string | the kind of the vanished fact |
| `was` | string | its id at the base |
| `slug` `rev` `xh` | | for declarations, so that a tool can compute renames |

## 8. Finding records

**`finding`** — located at its subject. A `config-changed` finding takes
the position that [manifest.md](manifest.md) section 14.4 gives.

| field | type | meaning |
|---|---|---|
| `class` | string | a class from [algebra.md](algebra.md) section 9 |
| `subject` | string | the subject id: the id of the fact that the finding is about, or a positional subject id (section 9) |
| `ack_subject` | string | the subject in the form that an `@ack` names it ([vocabulary.md](vocabulary.md) section 7.4) |
| `rule` | string | `unmet-rule` findings only |
| `detail` | string | one line, human-facing, deterministic |
| `fix` | string | the repair of the finding, on one line; omitted when none. It is a line to paste, or an instruction. A line to paste is, for example, an `@ack` line, a tag line with a corrected word or revision, or, for a `retired` finding, the citation of a successor that replaces the edge. With several successors, the fix gives the citation of each, and a person chooses one ([algebra.md](algebra.md) section 9) |
| `ackable` | bool | whether a live `@ack` can accept this finding ([algebra.md](algebra.md) section 9, column `A`). For a class that the column marks `A*`, the value depends on the finding |
| `acked` | bool | present only when acked findings are requested |
| `tier` `gate` | string | the gate that the check ran with, and the tier that applies to the class at that gate ([manifest.md](manifest.md) section 9.3); present only when the command runs with `--gate` |
| `mode` | string | `tree` or `diff` |

## 9. Identity

A fact keeps its id when lines move in the file. Three operations
depend on this: baseline subtraction ([algebra.md](algebra.md) section
8.2), `@ack` targeting, and the stable finding identifiers in report
output. Sinter derives an id from content wherever content exists. It
uses a position in the file only when no content can name the fact.

| kind | id | notes |
|---|---|---|
| `req` `design` `decision` `plan` | `<kind>:<slug>` | |
| `step` | `step:<plan>/<step>` | |
| `test` | `test:<path>#<full name>` | the full name joins the names of the test's name path with the pack's name separator ([packs.md](packs.md) section 8.3). When two tests of one file have one full name, each later one in the order of the file adds `#2`, `#3`, and so on. The full name can contain spaces |
| `site` | `site:<path>#<name>` | code: `<name>` is the name path of the attached definition; when two sites of one file have one name, each later one in the order of the file adds `#2`, `#3`, and so on ([packs.md](packs.md) section 6.5). A code site with no name has the positional id `site:<path>@L<line>C<column>`, from the position where its run starts, and its record carries `"positional":true`. Markdown: `<name>` is the slug of the section's heading; the section of level 0 has the id `site:<path>` |
| edges | `<kind>:<src-id>-><target>` | `<target>` is the tag target. Parse from the right: a tag target cannot contain `->` |
| `ref` | `ref:<ns>/<id>` | |
| `promise` | `promise:<step-id>:<word>:<target>` | parse from the right |
| `run` | `run:<test-id>@<tree>` | |
| `cov` | `cov:<test-id or *>@<site-id>` | |
| `judgment` | `judgment:<rule>:<subject-id>@<hash>` | |
| `claim` | `claim:<plan>@<branch>` | |
| `decline` | `decline:<entry-id>` | |
| `rule` | `rule:<name>` | |
| `gate` | `gate:<gate>/<class>` | |
| `setting` | `setting:<key path>` for one value; `setting:<key path>=<member>` for one member of an array | parse from the left: a key path cannot contain `=` |
| `ack` | `ack:<block-id>:<target>` | anchored to the block, not to a line |
| `hunk` | `hunk:<path>:<line>-<eline>` | positional by nature |
| `tombstone` | `tombstone:<was>` | |
| `finding` | `finding:<class>:<subject-id>[:<rule>]` | `<subject-id>` is the id of the fact that the finding is about, or a positional subject id (below) |

A finding whose subject is no fact takes a **positional subject id**,
in the style of the positional id of a site. Lines and columns count
as section 3 says. Parse a positional subject id from the right: a
path can contain `@`.

| subject | positional subject id | findings |
|---|---|---|
| a file | `file:<path>` | `parse-error` in a file that yields no fact: a file that is not valid UTF-8, or a file of a fetched pack with a parse failure ([packs.md](packs.md) sections 5.1 and 5.2) |
| an error node of a markdown file | `file:<path>@L<line>C<column>`, from the position where the node starts | `parse-error` in a markdown file ([packs.md](packs.md) section 5.2) |
| a line | `line:<path>@L<line>` | `typo-tag` and `ignored-tag`, at the tag line; `duplicate` of a step, at the line of the step's heading |
| a tag | `tag:<path>@L<line>C<column>`, from the position of the `@` of the tag | `invalid-target`; `misplaced-plan`; `duplicate` of a declaration or a plan |

An id that is not positional is stable under re-indentation,
reformatting, line shifts, and re-pinning. It changes under a slug
rename (rename is deletion plus declaration), under moving a site to a
different named definition, and under a change of an edge's tag
target.

## 10. Header and summary records

**`index`** — the first line of every scan. Conformance comparison
excludes it.

| field | type | meaning |
|---|---|---|
| `tree` | string | tree key |
| `base` | string | resolved base revision |
| `target_branch` | string | the target branch |
| `manifest` | string | the path of the manifest: relative to the repository root when the manifest is in the repository, otherwise absolute |
| `ledger` | string | ledger tip commit; omitted when the ref is absent |
| `evidence` | bool | whether evidence exists for `tree` |
| `packs` | array of string | `name@version#hash` for each fetched pack, as the lock file `sinter.lock` fixes it. The built-in pack `markdown` is not in the lock file and has no entry |
| `tool` | string | tool version |
| `mode` | string | `tree` or `diff` |

**`summary`** — the first line of `status --json`. The finding counts
use the tiers of the `turn` gate.

| field | type |
|---|---|
| `plan` `step` | string; omitted when none |
| `done` | bool |
| `steps_done` `steps_total` | int |
| `block` `warn` | int (finding counts, under the `turn` gate's tiers) |
| `unmapped` | int (hunks) |
| `obligations` | int (rule obligations) |
| `evidence_fresh` | bool |
| `bumps` | int (declarations bumped since the base) |
| `acks_live` `acks_void` | int |
| `declines` | int (live, in scope) |
| `claims` `waiting` | int |
| `code_drift` | int |
| `config_changed` | bool (`true` when the diff changes the configuration: the check reports at least one `config-changed` finding, [manifest.md](manifest.md) section 14.4) |

## 11. Conformance

A language pack's fixture directory contains a small project, an
`expected.jsonl` file, a fixture ledger, and real artifacts from a
test runner and a coverage tool, with attribution. The verifier scans
the fixture with the fixture's own ledger and evidence. It drops the
header line from the output. It then compares the output with
`expected.jsonl`; the two must be equal byte for byte. Because the
comparison includes derived fields, the fixture tests the whole path
from artifact import to evidence binding, not only parsing. A tool
release that changes any derived field's semantics must regenerate
every pack's fixture.
