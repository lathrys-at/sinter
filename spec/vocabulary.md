<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: doctag vocabulary

Status: draft. The five specifications share one version; see [docs/versioning.md](../docs/versioning.md).

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
- In markdown, the tag-bearing nodes are the first paragraph of a
  section and the first paragraph of a list item. A section is a
  heading plus the text below it, up to the next heading of the same
  or higher level. Only an ATX heading, a line that starts with one to
  six `#` characters, opens a section; a setext heading, a line of
  text underlined with `=` or `-`, does not. The text before the first
  heading of a file is a section of level 0, with no heading. A **list
  item** is one item of a markdown list, ordered or not. It holds its
  own text and its **sub-items**: the items of the lists inside it.

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

`@word` is the tag name. `target` is the **tag target**: it names the
thing the tag declares or points at. `vN` is a revision (section 5). A
description can follow on the same line and on later lines (section
3.2).

### 3.1 Tag lines and blocks

The scanner finds a **tag line** as follows. Take a line inside a
tag-bearing node. In code, remove the comment sigil and the
indentation before it. On the first line of a list item, remove the
list marker, such as `-`, `*`, or `1.`, and the indentation before it.
Then remove the spaces and tabs at the start of the line. The line is
a tag line when the remaining text starts with `@`.

Every such line is a tag line, whether or not its word is in this
vocabulary. Unknown words are not part of this vocabulary and have no
meaning here. Other toolchains own some tag words, for example
`@param` and `@returns`. A language pack lists the tag words that
other toolchains own. That list is the pack's **foreign vocabulary**.

A **block** is a sequence of tag lines inside one tag-bearing node,
plus the trailing prose that follows those tag lines (section 3.2).

### 3.2 Descriptions

A tag's **inline description** is the rest of its own line, after the
tag target and the revision.

A block's **trailing prose** is the sequence of lines that follow the
last tag line and that do not start with `@`. The sequence ends at a
blank line or at the end of the tag-bearing node. Trailing prose
belongs to the block's declaration when the block contains one. When
the block contains no declaration, the trailing prose belongs to the
block's first tag.

Descriptions are part of the extent (section 6). Tools use them when
they compile human-facing documents. Descriptions have no other
machine meaning.

## 4. Tag targets

A tag target is a **slug** or a **ref**.

### 4.1 Slugs

A slug must match this pattern:

```
[A-Za-z0-9]+([-_.][A-Za-z0-9]+)*
```

A slug keeps its case. Two slugs are equal only when they are equal
byte for byte, so `Auth-Lockout` and `auth-lockout` are two slugs.

Slugs name declared items. There are three separate slug namespaces:

1. **Citable declarations.** The kinds `req`, `design`, and `decision`
   share one namespace. A citation never names a kind, so a slug must
   be unique across these three kinds.
2. **Plans.** Plan slugs have their own namespace. A plan can share
   its slug with a requirement. Plan slugs are permanent: a closed
   plan keeps its slug, and no later plan can reuse it.
3. **Steps.** Step slugs are scoped to their plan (section 10.3).

Two declarations in one namespace are an error (finding class
`duplicate`) when their slugs are equal, or when their slugs differ
only in case. A slug that fails the pattern is an error (finding class
`bad-target`).

A citation whose tag target differs from a declared slug only in case
does not resolve, so the citation is dangling (section 7.2). The `fix`
of its finding ([jsonl.md](jsonl.md) section 8) names the declared
spelling.

The slug is the identity of an item. There are no hidden machine
identifiers. To rename an item, delete it and declare a new one.
Decision slugs are also permanent: a decision is never deleted
(section 8.3).

A citable declaration can take the slug of a declaration that was
deleted. The new declaration then continues the old item. Its revision
must be higher than every revision of the slug that the ledger holds,
and the ledger's entries for the slug apply to the new declaration.

### 4.2 Refs

A ref points at something outside the repository, for example an issue.
A ref must match `<ns>/<id>`, where `ns` is a namespace that the
repository's manifest declares, and `id` matches the pattern that the
namespace declares ([manifest.md](manifest.md) section 8.3). Example:
`gh/42`.

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
| declarations (`@req`, `@design`, `@decision`, `@rule`) | optional; `v1` when omitted |
| promises in a plan file (section 10) | absent |

On a citation, the revision **pins** the citation to one revision of
the declaration that its tag target names. A pinned citation is
**suspect** (section 9) when that declaration now has a different
revision.

The **diff base** is the git revision that a check compares the
working tree against ([algebra.md](algebra.md) section 8). When a
declaration's extent changes, its revision must increase. The new
revision must be strictly greater than the revision that the
declaration had at the diff base (section 9).

## 6. Extent

An item's **extent** is the text that its revision covers.

- In code, the extent is the comment block. The attached code is not
  part of the extent.
- In markdown, a declaration in the first paragraph of a section claims
  the whole section as its extent, up to the next heading of the same
  or higher level.
- In markdown, a declaration in the first paragraph of a list item
  claims the list item, with its sub-items, as its extent.
- In a rule file, the extent of the `@rule` declaration is the whole
  file ([manifest.md](manifest.md) section 15).

Two boundary rules apply in markdown:

1. Two extents that touch never merge into one extent. An extent ends
   where the next declaration begins.
2. A declaration in a nested section removes that section from the
   enclosing extent. A declaration in a list item removes that list
   item, with its sub-items, from the enclosing extent.

A list item that declares nothing is plain text of the section or the
list item that holds it. The scanner still reads the tags in its first
paragraph, and section 7.2 gives the source of each citation there.
Prose outside every extent is not governed by any revision.

### 6.1 The extent hash

The **extent hash** (`xh`) is SHA-256 over the extent's normalized
text. To normalize, apply these steps in order:

1. Take the extent's content lines. In code, remove the comment sigils
   (`///`, `#`, `*`) and the indentation before each sigil. Markdown
   has no comment sigils, so in markdown keep the lines as they are.
2. Remove trailing whitespace from every line.
3. Use LF as the line ending.
4. Drop every `@ack` line.
5. On the declaration's own tag line, drop the text `@word slug vN`.
6. On every citation line, drop the `vN` token.
7. End the text with one final LF.

The same normalization, applied to any block, gives the **block hash**
that an `@ack` records (section 7.4). One hash function and one rule
set serve both uses.

Steps 5 and 6 have this effect. Three edits do not change the extent
hash:

- a rename;
- a bare revision bump with no other text change;
- a re-pin of a citation.

Reformatting a comment also does not change the extent hash. Every
other byte change changes the extent hash.

### 6.2 The code hash

Each code site also carries a **code hash** (`ch`): SHA-256 over the
attached definition's body, normalized with steps 2, 3, and 7 of
section 6.1. The other steps concern comment sigils and tag lines,
and a definition body holds neither. Indentation stays, because
indentation can be significant in code.

The code hash is not part of the extent. Tools use it to detect code
that changed while its comment did not.

## 7. The vocabulary

The vocabulary has fifteen words. One more word, `@pin`, is designed
but deferred (section 7.4).

### 7.1 Declarations

A declaration says: this text defines a thing.

| tag | where it appears |
|---|---|
| `@req <slug> [vN]` | requirements documents |
| `@design <slug> [vN]` | design documents |
| `@decision <slug> [vN]` | decision records |
| `@plan <slug>` | plan files (section 10) |
| `@rule <slug> [vN]` | rule files ([manifest.md](manifest.md) section 15) |

`@rule` declares a rule. Its extent is the whole rule file (section
6).

`@design` and `@req` differ in two ways only. They differ in purpose:
a design item describes architecture between the requirements and the
code. They also differ in the default strictness of their approval
checks — see the finding classes `unratified-req` and
`unratified-design` in [algebra.md](algebra.md) section 9. The kind
lives on the tag, not on a file path, so these documents can live
anywhere in the repository.

### 7.2 Citations

A citation says: this relates to that.

| tag | source → tag target |
|---|---|
| `@satisfies <slug> vN` | a site → a `req` or `design` |
| `@verifies <slug> vN` | a test → a `req` or `design` |
| `@refines <slug> vN` | a `req` or `design` → a `req` or `design` |
| `@cites <slug or ref> [vN]` | anything → any declaration or ref |
| `@supersedes <slug> vN` | a declaration → a declaration of the same kind |

The source of a citation depends on its kind and on its place:

- In code, `@satisfies` and `@cites` have an **anonymous source**: a
  source with no name. It is the file and the extent of the block,
  and it is called a **code site**. No declaration is needed at the
  source.
- In code, `@verifies` has the attached test as its source. The
  test's identity comes from the language's abstract syntax tree, so
  no declaration is needed there either.
- In code, `@refines` and `@supersedes` have the enclosing declaration
  as their source: the declaration whose extent holds the tag line.
- In markdown, a citation of any kind has as its source the innermost
  declaration whose extent holds the citation's tag line. When no
  declaration's extent holds the tag line, the source is the anonymous
  source of the innermost section that holds the tag line.

A markdown section is an anonymous source when it holds a citation
outside every declaration's extent. Its block is its first paragraph,
and its extent is the whole section (section 6). Its id comes from the
path of the file and the slug of the section's heading
([jsonl.md](jsonl.md) section 9). A list item is never an anonymous
source. A code site and such a section are both **sites**.

The slug of a heading comes from the heading's text by the three
changes of section 10.3. When two or more headings of one file give the
same slug, the first heading keeps the slug. Each later heading adds
`-1`, `-2`, and so on, in the order of the file, as GitHub numbers the
anchors of headings. Example: `example`, `example-1`. Only a heading
that opens a section counts (section 2).

A citation is an **orphan** (finding class `orphan`) when its kind
needs a certain source and the citation does not have one. A
`@verifies` needs a test. A `@refines` or a `@supersedes` needs an
enclosing declaration.

A citation is **dangling** when its tag target does not resolve: no
declaration has the slug, or the ref's namespace is not declared, or
the ref's id fails the namespace's pattern.

A `@supersedes` edge whose source and tag target have different kinds
is an error. A live `@supersedes` edge retires the declaration that
its tag target names (section 8).

### 7.3 Status tags

A status tag records that the authors no longer endorse the
declaration that carries it. A status tag has no tag target. It has
effect only in the tag block of a declaration: the block whose tag
lines hold the declaration. Anywhere else it is inert. In markdown the
extent of a declaration is its whole section or its whole list item,
but only the first paragraph is tag-bearing, so a status tag must
stand in that paragraph. There is no "done" status.

| tag | applies to | meaning |
|---|---|---|
| `@deprecated` | `req`, `design`, `decision` | no longer applies; nothing replaces it |
| `@rejected` | `decision` | considered and declined; the record stays |
| `@deferred` | `decision` | not decided; the description says what would settle it |

### 7.4 Directives

A directive records a judgment in a block.

**`@ack <target> <hash>`** records one judgment about one block of
text. The judgment is one of two: someone accepted a finding, or
someone satisfied a rule. The judgment covers the block as it was when
that person read it. In the grammar, `<hash>` is the last token, and
`<target>` is everything between `@ack` and the hash. This tag target
is one of:

- a finding class, with an optional subject — for example
  `disendorsed cache-ttl` or `disconnected`;
- a rule name — for example `ste-docs`.

The **subject** of a finding is the fact that the finding is about. An
ack names the subject in the form that the checking tool reports in
the field `ack_subject` of the finding ([jsonl.md](jsonl.md) section
8):

- for an edge, the tag target of the edge, as written;
- for a fact that has a slug (a declaration, a plan, or a step), its
  slug;
- for any other fact, its id.

The hash is the first eight or more hex digits of the block hash
(section 6.1) at the time of the judgment.

An ack is **live** if and only if both conditions hold:

1. The hash matches the block's current block hash.
2. The tag target of the ack still names something in this block: a
   finding of that class, or an obligation of that rule. When the ack
   gives a subject, the finding must also have that subject.

The checking tool removes acked findings at the end of a check. It
judges condition 2 against the findings and obligations that exist
before that removal. It computes a rule's obligations from the rule's
trigger alone. It computes a finding class from the class's raw
definition. An ack therefore cannot make itself void by removing the
finding it names.

When either condition fails, the ack is **void**. A void ack is itself
a finding (`stale-ack`). Only some finding classes accept an ack; the
finding-class table in [algebra.md](algebra.md) section 9 marks them.

**`@pin <ref>`** is deferred. A future version will use it to watch
external content for changes. A person endorses the content's current
hash through the approval flow. The tool then reports a finding
whenever the content's hash differs from the endorsed hash. The
finding stays until a person endorses the new hash.

### 7.5 Plan-only tags

**`@scope <globs>`** declares the file scope of a plan or of a step
(section 10.4). It is valid only in plan files.

## 8. In force, supersession, and retirement

### 8.1 In force

An item is **in force** if and only if it carries no status tag and no
live `@supersedes` edge points at it.

A `@supersedes` edge is **live** if and only if both conditions hold.
First: the edge's source is a declaration, and that declaration is
itself in force. Second: when the source's kind needs approval, the
source is approved at its current revision. The manifest key
`ledger.approval-required` lists the kinds that need approval
([manifest.md](manifest.md) section 11.1). The ledger specification,
[ledger.md](ledger.md), defines approval. An edge whose source is not
approved retires nothing yet.

On a `@supersedes` cycle, every member of the cycle counts as in
force, and the cycle is an error (finding class `cycle`).

### 8.2 Retirement

An item that is not in force is **retired**. Two triggers retire an
item: a status tag, or a live `@supersedes` edge. Retirement does not
cascade. A citation of a retired item is a finding (`disendorsed`),
never an automatic retirement of the citing item. Only a person can
decide whether the citing item is still correct for other reasons.

### 8.3 Decisions are never deleted

A decision record must not be deleted. The allowed moves are:
supersede it, reject it, or defer it. The old text stays, because the
old reasoning is the record of why the new decision exists. An edit of
a decision record is allowed: like every extent edit, it owes a
revision bump (section 9).

### 8.4 Historical paths

The manifest can declare paths as **historical**, for example a devlog
(the key `check.historical`, [manifest.md](manifest.md) section 9.4).
In a historical file, a citation still resolves to its tag target, and
compiled documents still show it as a link. No fact in a historical
file generates a finding of any class ([algebra.md](algebra.md)
section 9, global rule 1).

## 9. Revision discipline

A person writes every revision pin by hand. Sinter stores no hash of a
declaration's text outside the repository. Sinter also never writes
into a governed file. Two rules make hand-written pins work:

1. **Every extent edit owes a bump.** When a declaration's extent
   changes relative to the diff base and its revision does not
   increase, that is an error (finding class `rev-owed`). A writer
   cannot claim an exception: Sinter does not accept the claim "this
   edit did not change the meaning", because no tool can check that
   claim.
2. **A bump makes pinned citations suspect.** A citation pinned to
   `v2` becomes suspect when the declaration that it names moves to
   `v3`. Suspect citations are findings until they are re-pinned.

A bump also removes the item's approval until it is stamped again (see
[ledger.md](ledger.md)).

## 10. Plan files

### 10.1 What a plan is

A **plan** is an agreement that belongs to one branch. A plan holds a
set of steps. Each step promises that certain tags will exist in the
repository when the step is done.

A plan file is a markdown file under `.plans/`, committed on its
branch, and never deleted. A plan is **open** until the ledger holds a
`discharged` or `abandoned` entry for it; then it is **closed**. Only
a ledger entry closes a plan. No change to the plan file — an edit, a
move, or a deletion — closes a plan. See [ledger.md](ledger.md).

A file is a plan if and only if it lives under `.plans/` and its first
tag block carries `@plan`. A `@plan` tag anywhere else is an error
(finding class `misplaced-plan`).

### 10.2 Promissory reading

Inside a plan file, the scanner reads tags as promises, not as facts:

- A promised declaration (`@req x`) means: this step will declare `x`.
- A promised citation (`@verifies x`) means: this step will produce a
  `@verifies` citation of `x`. That citation must have the properties
  that section 10.5 requires.

**Residue** is the set of facts in the tree that a promise asked for:
the declarations and the edges that discharge it. Tags in plan files
never produce declarations or edges themselves. Revisions are absent
on promises; a promise is checked against the revision that is current
when it is discharged.

### 10.3 Steps

Every `##` heading that carries at least one plan tag — a `@scope` or a
promise — is a **step**. A `##` section with no plan tags is prose, not
a step.

The scanner derives a step's slug from the step's heading text: the
source text of the heading line, after the `#` characters and the
spaces that follow them, and without any closing `#` characters. A
letter or a digit here is an ASCII letter or digit; every other
character counts as non-alphanumeric. The scanner makes these three
changes in order:

1. Change every letter to lowercase.
2. Replace each sequence of non-alphanumeric characters with one
   hyphen.
3. Remove hyphens at the start and at the end.

Example: `## Verify against the reqs` becomes
`verify-against-the-reqs`. Two steps of one plan with the same slug
are an error (`duplicate`).

Steps are unordered facts. The order of steps in the document is
advice, not a constraint.

### 10.4 Scope

A `@scope` line holds comma-separated globs in the glob language of
[manifest.md](manifest.md) section 7.1. The globs of one line give a
set of paths by the rule of a path set ([manifest.md](manifest.md)
section 7.2): a glob that starts with `!` leaves paths out.

A step with no `@scope` inherits the plan's scope. A step's `@scope`
must be contained in its plan's scope (finding class `bad-scope`). A
step's **effective scope** is its own scope when it has one, and
otherwise the plan's scope.

The manifest key `plan.shared` ([manifest.md](manifest.md) section
10.3) names paths that every step of every plan can change, for
example the dependency and license files at the repository root. A
change under a shared path is never work outside the plan. A shared
path does not widen the discharge location of any promise: a promised
item is met only inside the step's effective scope or inside the
default location of its kind (section 10.5).

### 10.5 Discharge

A promise is **met** as follows:

- A promised declaration is met if and only if a declaration with that
  slug exists inside the step's effective scope, or inside the default
  location of its kind. The manifest key `plan.locations.<kind>` gives
  the default location of a kind as a path set
  ([manifest.md](manifest.md) section 10.4), for example
  `locations.decision = ["docs/decisions/"]` under `[plan]`. A kind
  without an entry has no default location.
- A promised `@satisfies`, `@refines`, `@cites`, or `@supersedes` is
  met if and only if at least one such edge exists inside the step's
  effective scope, and that edge is neither dangling nor suspect.
- A promised `@verifies` is met if and only if such an edge exists
  inside the step's effective scope at evidence rung `passing`. When
  `evidence.coverage-attribution` is `"optional"`, the default, an
  edge at rung `unattributed` also meets the promise
  ([manifest.md](manifest.md) section 12). Rungs are defined in
  [algebra.md](algebra.md) section 6.7.

Residue that would discharge a promise, but that sits outside both
the step's scope and the default location of its kind, does not
discharge that promise. The scanner reports this case as a finding
(`promise-out-of-scope`).

A step is **done** if and only if all its promises are met and all
`@verifies` edges in its scope are at an allowed rung. A step with a
scope and no promises is a **refactor** step. A refactor step is done
when both conditions hold: a hunk of the diff changes a file inside
its scope, and every `@verifies` edge in its scope is at an allowed
rung. A plan is **done** if and only if all its steps are done.

### 10.6 Amendment

Plans are exempt from revision discipline. Sinter judges a plan by its
**commitment set** — the promises and the scopes of each step — never
by its text. The rules for comparing commitment sets, and for which
amendments need a new approval, are in [ledger.md](ledger.md) section
11.

## 11. Rename

To rename a declared item, delete the old declaration and write a new
one. The citations of the old slug then dangle. When the new
declaration has an extent hash equal to the old one, the rename is
mechanical: a tool can retarget the citations (finding class
`renamed`, which carries a mechanical fix). A rename removes an item's
approval. A renamed item stays unapproved until it is stamped again,
even when its text is unchanged.
