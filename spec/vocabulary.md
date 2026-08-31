<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: doctag vocabulary

Status: draft.

## 1. Introduction

Sinter traces requirements, designs, decisions, plans, and tests through
a repository. It does this with **doctags**: tags that live in the
repository's own text files. This document defines the doctag
vocabulary. It says where tags can appear, how a tag is written, what
each tag means, and how tags relate to each other.

This document has two audiences: people who write doctags, and people
who build tools that read doctags. Anyone can implement this
specification in any tool. See the LICENSE-SPEC file at the repository
root.

In this document, "must" states a requirement, "can" states a
permission, and a **bold** term is defined where it first appears. The
program that reads doctags is called the **scanner**.

## 2. Where tags are read

The scanner must parse each file with a parser for the file's language.
It must not search raw text for tags.

Each language defines a set of **tag-bearing nodes**. The scanner reads
tags only inside these nodes:

- In code, the tag-bearing nodes are comments.
- In markdown, the tag-bearing node is the first paragraph of a
  section. A section is a heading plus the text below it, up to the
  next heading of the same or higher level.

The scanner must not read tags inside string literals, code fences, or
any other node. In Sinter, each language's tag-bearing nodes are
declared by that language's pack.

A comment in code **attaches** to the next named definition after it:
for example a function, a struct, or a test. The language pack defines
which kinds of definition can carry a comment. Attachment is what
connects a tag to a piece of code or to a test.

## 3. Tag syntax

Every tag has one shape:

```
@word target [vN]
```

`@word` is the tag name. `target` names the thing the tag declares or
points at. `vN` is a revision (section 5). A description can follow on
the same line and on later lines (section 3.2).

### 3.1 Tag lines and blocks

A **tag line** is a line inside a tag-bearing node that starts with
`@`, after the comment sigil and indentation are removed. Every such
line is a tag line, whether or not its word is in this vocabulary.
Unknown words are not part of this vocabulary and have no meaning here.
Other toolchains own some tag words, for example `@param` and
`@returns`; a language pack lists these as its **foreign vocabulary**.

A **block** is a run of tag lines inside one tag-bearing node, plus the
trailing prose that follows them (section 3.2).

### 3.2 Descriptions

A tag's **inline description** is the rest of its own line, after the
target and the revision.

A block's **trailing prose** is the run of lines after the last tag
line that do not start with `@`. It ends at a blank line or at the end
of the tag-bearing node. Trailing prose belongs to the block's
declaration when the block contains one. When the block contains no
declaration, the trailing prose belongs to the block's first tag.

Descriptions are part of the extent (section 6). Tools use them when
they compile human-facing documents. Descriptions have no other
machine meaning.

## 4. Targets

A target is a **slug** or a **ref**.

### 4.1 Slugs

A slug must match this pattern:

```
[a-z0-9]+(-[a-z0-9]+)*
```

Slugs name declared items. There are three separate slug namespaces:

1. **Citable declarations.** The kinds `req`, `design`, and `decision`
   share one namespace. A citation never names a kind, so a slug must
   be unique across these three kinds.
2. **Plans.** Plan slugs have their own namespace. A plan can share
   its slug with a requirement. Plan slugs are permanent: a dead plan
   keeps its slug, and no later plan can reuse it.
3. **Steps.** Step slugs are scoped to their plan (section 10.3).

Two declarations of one slug in a shared namespace are an error
(finding class `duplicate`). A slug that fails the pattern is an error
(finding class `bad-target`).

The slug is the identity of an item. There are no hidden machine
identifiers. To rename an item is to delete it and to declare a new
one. Decision slugs are also permanent: a decision is never deleted
(section 8.3).

### 4.2 Refs

A ref points at something outside the repository, for example an issue.
A ref must match `<ns>/<id>`, where `ns` is a namespace that the
repository's manifest declares, and `id` matches the pattern that the
namespace declares. Example: `gh/42`.

A ref is a pointer, not a declared item. It has no revision, no
extent, and no approval. A ref whose namespace is not declared, or
whose id fails the namespace's pattern, is an error (finding class
`bad-target`).

## 5. Revisions

A revision is `v` followed by a positive integer. The first revision of
a declaration is `v1`.

| tag kind | revision |
|---|---|
| `@satisfies`, `@verifies`, `@refines`, `@supersedes` | required |
| `@cites` | optional |
| declarations (`@req`, `@design`, `@decision`) | optional; `v1` when omitted |
| promises in a plan file (section 10) | absent |

On a citation, the revision **pins** the citation to one revision of
its target. A pinned citation whose target now has a different revision
is **suspect** (section 9).

When a declaration's extent changes, its revision must increase. The
new revision must be strictly greater than the revision at the diff
base (section 9).

## 6. Extent

An item's **extent** is the text that its revision covers.

- In code, the extent is the comment block. The attached code is not
  part of the extent.
- In markdown, a declaration in the first paragraph of a section claims
  the whole section as its extent, up to the next heading of the same
  or higher level.

Two boundary rules apply in markdown:

1. Adjacency never merges. An extent ends where the next declaration
   begins.
2. A declaration in a nested section removes that section from the
   enclosing extent.

Prose outside every extent is not governed by any revision.

### 6.1 The extent hash

The **extent hash** (`xh`) is SHA-256 over the extent's normalized
text. To normalize, apply these steps in order:

1. Take the extent's content lines. Remove comment sigils (`///`, `#`,
   `*`) and the indentation before them. Markdown has no sigils; skip
   this step there.
2. Remove trailing whitespace from every line.
3. Use LF as the line ending.
4. Drop every `@ack` line.
5. On the declaration's own tag line, drop the `@word slug vN` prefix.
6. On every citation line, drop the `vN` token.
7. End the text with one final LF.

The same normalization, applied to any block, gives the **block hash**
that `@ack` pins (section 7.4). One hash function and one rule set
serve both uses.

The effect of steps 5 and 6: a rename, a bare revision bump with no
text change, and a re-pin of a citation all leave the hash equal.
Reformatting a comment also leaves the hash equal. Every other byte
change changes the hash.

### 6.2 The code hash

Each code site also carries a **code hash** (`ch`): SHA-256 over the
attached definition's body, normalized with the same steps. The code
hash is not part of the extent. Tools use it to detect code that
changed while its comment did not.

## 7. The vocabulary

The vocabulary has fourteen words. One more word, `@pin`, is designed
but deferred (section 7.4).

### 7.1 Declarations

A declaration says: this text defines a thing.

| tag | where it appears |
|---|---|
| `@req <slug> [vN]` | requirements documents |
| `@design <slug> [vN]` | design documents |
| `@decision <slug> [vN]` | decision records |
| `@plan <slug>` | plan files (section 10) |

`@design` differs from `@req` only in purpose and in how strictly it is
approved. The kind lives on the tag, not on a file path, so these
documents can live anywhere in the repository.

### 7.2 Citations

A citation says: this relates to that.

| tag | source → target |
|---|---|
| `@satisfies <slug> vN` | a code site → a `req` or `design` |
| `@verifies <slug> vN` | a test → a `req` or `design` |
| `@refines <slug> vN` | a `req` or `design` → a `req` or `design` |
| `@cites <slug or ref> [vN]` | anything → any declaration or ref |
| `@supersedes <slug> vN` | a declaration → a declaration of the same kind |

The source of a citation depends on its kind:

- `@satisfies` and `@cites` in code have an anonymous source: the file
  and the extent of the block. No declaration is needed at the source.
- `@verifies` has the attached test as its source. The test's identity
  comes from the language's abstract syntax tree, so no declaration is
  needed there either.
- `@refines` and `@supersedes` have the enclosing declaration as their
  source.

A `@supersedes` edge whose source and target have different kinds is an
error. A live `@supersedes` edge retires its target (section 8).

### 7.3 Status tags

A status tag says: we no longer stand behind this. A status tag has no
target. It has effect only inside a declaration's extent. Outside an
extent it is inert. There is no "done" status.

| tag | applies to | meaning |
|---|---|---|
| `@deprecated` | `req`, `design`, `decision` | no longer applies; nothing replaces it |
| `@rejected` | `decision` | considered and declined; the record stays |
| `@deferred` | `decision` | not decided; the description says what would settle it |

### 7.4 Directives

A directive records a judgment at a site.

**`@ack <target> <hash>`** records that a person or an agent accepted a
finding, or satisfied a rule, for the text as hashed. The grammar:
`<hash>` is the last token, and `<target>` is everything between `@ack`
and the hash. The target is one of:

- a finding class, with an optional subject, exactly as the checking
  tool reported it — for example `disendorsed cache-ttl` or
  `disconnected`;
- a rule name — for example `ste-docs`.

The hash is the first eight or more hex digits of the block hash
(section 6.1).

An ack is **live** if and only if both conditions hold:

1. The hash matches the block's current block hash.
2. The target still names something at this site: a finding of that
   class (with that subject, when one is given), or an obligation of
   that rule.

Condition 2 is judged against the state before ack subtraction. A
rule's obligations are computed from its trigger alone, and a finding
class is computed from its raw definition. So an ack cannot void
itself by succeeding.

When either condition fails, the ack is **void**. A void ack is itself
a finding (`stale-ack`). Only some finding classes accept an ack; the
checking tool defines which (see the query algebra specification,
[algebra.md](algebra.md)).

**`@pin <ref>`** is deferred. It will arm a drift check on external
content: a human endorses the content's current hash through the
approval flow, and the tool reports upstream drift until the hash is
endorsed again.

### 7.5 Plan-only tags

**`@scope <globs>`** declares the file scope of a plan or of a step
(section 10.4). It is valid only in plan files.

## 8. In force, supersession, and retirement

### 8.1 In force

An item is **in force** if and only if it carries no status tag and no
live `@supersedes` edge targets it.

A `@supersedes` edge is **live** if and only if its source is itself in
force and — when the source's kind is approval-gated — the source is
approved at its current revision (see the ledger specification,
[ledger.md](ledger.md)). An edge whose source is not approved retires
nothing yet.

On a `@supersedes` cycle, every member of the cycle is treated as in
force, and the cycle is an error (finding class `cycle`).

### 8.2 Retirement

An item that is not in force is **retired**. Two triggers retire an
item: a status tag, or a live `@supersedes` edge. Retirement does not
cascade. A citation of a retired item is a finding (`disendorsed`),
never an automatic retirement of the citing item. Only a judgment can
say whether the citing item stands on other grounds.

### 8.3 Decisions are never deleted

A decision record must not be deleted. The allowed moves are:
supersede it, reject it, or defer it. The old text stays, because the
old reasoning is the record of why the new decision exists.

### 8.4 Historical paths

The manifest can declare paths as **historical**, for example a devlog.
In historical files, citations resolve and render, but they generate no
findings.

## 9. Revision discipline

Citations pin revisions by hand; there are no stored fingerprints and
no write path into governed text. Two rules make this work:

1. **Every extent edit owes a bump.** When a declaration's extent
   changes relative to the diff base and its revision does not
   increase, that is an error (finding class `rev-owed`). There is no
   editorial escape hatch: "this edit did not change the meaning" is
   not accepted, because it cannot be checked.
2. **A bump makes pinned citations suspect.** A citation pinned to
   `v2` becomes suspect when its target moves to `v3`. Suspect
   citations are findings until they are re-pinned.

A bump also removes the item's approval until it is stamped again (see
[ledger.md](ledger.md)).

## 10. Plan files

### 10.1 What a plan is

A **plan** is a branch-scoped agreement: a set of steps, where each
step promises tags that will exist when the step is done. A plan file
is a markdown file under `.plans/`, committed on its branch, and never
deleted. A plan's life ends by a ledger entry (`discharged` or
`abandoned`), never by a file event; see [ledger.md](ledger.md).

A file is a plan if and only if it lives under `.plans/` and its first
tag block carries `@plan`. A `@plan` tag anywhere else is an error
(finding class `misplaced-plan`).

### 10.2 Promissory reading

Inside a plan file, tags are read as promises, not as facts:

- A promised declaration (`@req x`) means: this step will declare `x`.
- A promised citation (`@verifies x`) means: this step will produce
  such a citation, with the properties section 10.5 requires.

Tags in plan files never produce declarations or edges. Revisions are
absent on promises; a promise is checked against the revision that is
current when it is discharged.

### 10.3 Steps

Every `##` heading that carries at least one plan tag — a `@scope` or a
promise — is a **step**. A `##` section with no plan tags is prose, not
a step.

A step's slug is derived from its heading text: lowercase the text,
collapse every run of non-alphanumeric characters into one hyphen, and
trim hyphens at both ends. Example: `## Verify against the reqs`
becomes `verify-against-the-reqs`. Two steps of one plan with the same
slug are an error (`duplicate`).

Steps are unordered facts. The order of steps in the document is
advice, not a constraint.

### 10.4 Scope

A `@scope` line holds comma-separated globs, relative to the
repository root, in gitignore style:

- `*` matches within one path segment.
- `**` matches across segments.
- `!` negates.
- A trailing `/` means the directory and everything under it.

A step with no `@scope` inherits the plan's scope. A step's `@scope`
must be contained in its plan's scope (finding class `bad-scope`). A
step's **effective scope** is its own scope when it has one, otherwise
the plan's.

### 10.5 Discharge

A promise is **met** as follows:

- A promised declaration is met if and only if a declaration with that
  slug exists inside the step's effective scope.
- A promised `@satisfies`, `@refines`, `@cites`, or `@supersedes` is
  met if and only if at least one such edge exists inside the step's
  effective scope, and that edge is neither dangling nor suspect.
- A promised `@verifies` is met if and only if such an edge exists
  inside the step's effective scope at evidence rung `passing`. When
  the manifest sets `evidence.require_attribution = false` (the
  default), rung `unattributed` also meets it. Rungs are defined in
  [algebra.md](algebra.md).

Residue that would discharge a promise, but sits outside the step's
scope, does not discharge it. It is a finding
(`promise-out-of-scope`).

A step is **done** if and only if all its promises are met and all
`@verifies` edges in its scope are at an allowed rung. A step with a
scope and no promises is a **refactor** step: it is done when its scope
was touched and existing evidence stays green. A plan is **done** if
and only if all its steps are done.

### 10.6 Amendment

Plans are exempt from revision discipline. A plan is judged by its
**commitment set** — the promises and scopes per step — never by its
text. The rules for comparing commitment sets, and for which
amendments need a new approval, are in [ledger.md](ledger.md).

## 11. Rename

To rename a declared item, delete the old declaration and write a new
one. The citations of the old slug then dangle. When the new
declaration has an extent hash equal to the old one, the rename is
mechanical: a tool can retarget the citations (finding class
`renamed`, which carries a mechanical fix). A renamed approved item is
unapproved until it is stamped again, even when its text is unchanged.
