<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: manifest format

Status: draft. The five specifications share one version; see [docs/versioning.md](../docs/versioning.md).

## 1. Introduction

The **manifest** is a TOML file that holds the settings of one
repository for Sinter. Its settings say which files Sinter reads and
which refs resolve. They set how hard each finding class bites. They
say which changes need a plan step, which kinds need approval, and
which test evidence completes a promise.

This document defines the file, its tables, and its keys. It says how
a tool reads the file, and which errors a manifest can hold. It also
defines the facts that the manifest yields, and the fixed parts of a
rule file.

Anyone can implement this specification in any tool. See the
LICENSE-SPEC file at the repository root. The facts that the manifest
yields use the schema of [jsonl.md](jsonl.md). The finding classes and
their tiers are in [algebra.md](algebra.md) section 9. The tags are
defined in [vocabulary.md](vocabulary.md).

In this document, "must" states a requirement, "can" states a
permission, and a **bold** term is defined where it first appears.

## 2. The file

### 2.1 Name and place

The manifest is the file `sinter.toml` at the repository root. The
**repository root** is the top folder of the git working tree.

The option `--manifest <path>` names another file as the manifest. The
path is relative to the current folder, as every path on the command
line is. The file can be inside or outside the repository. Every glob
in the manifest is relative to the repository root, wherever the file
is.

### 2.2 TOML

The manifest is a TOML 1.0.0 document (<https://toml.io/en/v1.0.0>),
encoded in UTF-8. These rules also apply:

1. A form that only TOML 1.1 allows is a syntax error. Two examples:
   an inline table over more than one line, and the escape `\e`.
2. Every TOML form that gives the same document has the same meaning.
   A table header such as `[check.tiers.merge]`, a dotted key such as
   `tiers.merge.dangling` under `[check]`, and an inline table are all
   valid. Basic strings and literal strings are both valid.
3. A dotted key must not add a key to a table that an earlier table
   header made (section 2.3).
4. The tool does not change a string of the manifest. It does not
   normalize Unicode, and it does not change case.

### 2.3 Dotted keys under a later header

A table header makes the table that it names and each table above
that table. For example, `[a.b.c]` makes the tables `a`, `a.b`, and
`a.b.c`.

A dotted key names a path of tables and then one key. Under the header
`[a]`, the dotted key `b.ct` names the path `b`, which ends at the
table `a.b`, and then the key `ct`. The table at the end of the path
**receives** the key.

When an earlier table header made the table that receives the key, the
file is an error. This file is an error at line 4, because the header
on line 1 made the table `a.b`:

```toml
[a.b.c]
z = 9
[a]
b.ct = 1
```

TOML 1.0.0 does not state this case directly. Sinter rejects it. To
write the key, put it under the header of the table that receives it:

```toml
[a.b.c]
z = 9
[a.b]
ct = 1
```

A dotted key can pass through a table that a header made, when the
key goes into a new table below it. Under `[a]` in the first file,
`b.x.y = 1` is valid, because no header made the table `a.b.x`.

### 2.4 Commands that need a manifest

A command that reads the repository needs a manifest. The command
stops with exit code 3 in each of these cases:

- `--manifest` is not given, and the repository root holds no
  `sinter.toml`.
- The file that `--manifest` names does not exist, or the tool cannot
  read it.
- The manifest names no pack (section 8.1).
- The manifest holds an error (section 4).

`sinter parse` and `sinter serve` need no manifest.

### 2.5 One law for both trees

The **law** of a repository is its manifest and its rule files
(section 15).

In diff mode, Sinter reads two trees: the working tree and the base
tree ([algebra.md](algebra.md) section 8). Sinter reads both trees
with one law: the law of the working tree. So Sinter reads the base
tree with the manifest, the rule files, and the packs of the working
tree. It reads
the manifest of the base tree only to compare the two laws (section
14.4).

A manifest that `--manifest` names applies to both trees. Its globs
stay relative to the repository root.

## 3. Layout

### 3.1 Tables and key paths

The top level of the manifest holds two keys, `spec` and `target`.
They act on every part of Sinter. Every other key is in one of five
tables, and each table holds the settings of one part of Sinter:

| table | part of Sinter | what its settings decide |
|---|---|---|
| top level | every part | the version of the specifications; the target branch |
| `[scan]` | the scanner | which files each pack reads; which refs resolve |
| `[check]` | findings | which facts can make findings; the tier of each built-in finding class |
| `[plan]` | the plan check and promise discharge | which changes need a plan step; where a promised declaration can be met |
| `[ledger]` | approval and the ledger | which kinds need approval; where the commands that write the ledger refuse |
| `[evidence]` | test evidence | which rung of a `@verifies` edge completes a promise |

The **plan check** compares the hunks of a diff with the scopes of the
open plans. It reports each hunk outside them as `unmapped-work`
([algebra.md](algebra.md) section 9). **Promise discharge** decides
when a promise of a plan step is met
([vocabulary.md](vocabulary.md) section 10.5).

No other top-level key and no other table exists.

A **key path** names one value. It is the names of the keys from the
top of the file down to the value, joined with `.`. Example:
`check.tiers.merge.dangling`. This document names each setting by its
key path.

This document fixes some names in a key path: the names of the tables,
and keys such as `rollout-cap`. Each fixed name occurs at one place in
the layout. Other names vary: the name of a pack, a ref namespace, a
gate, a finding class, or a kind. This document writes a name that
varies in angle brackets, for example `<name>`.

### 3.2 Every key

The column "since" gives the version of the specifications that added
the key (section 5).

| key path | type | default | acts on | section | since |
|---|---|---|---|---|---|
| `spec` | string | absent: no version check | reading the manifest | 5 | 1.0 |
| `target` | string | `"main"` | the base of a diff | 6 | 1.0 |
| `scan.packs.<name>.files` | path set | none: required for each pack | the scanner: the files of pack `<name>` | 8.1 | 1.0 |
| `scan.packs.<name>.version` | string | none: required for each fetched pack; an error on `markdown` | the scanner: the release of pack `<name>` | 8.1 | 1.0 |
| `scan.refs.<ns>` | string: an id pattern | absent: the namespace `<ns>` does not exist | the scanner and findings: which refs resolve | 8.3 | 1.0 |
| `check.rollout-cap` | boolean | `false` | findings: tiers | 9.3 | 1.0 |
| `check.historical` | path set | empty, with one built-in member | findings: which facts can make findings | 9.4 | 1.0 |
| `check.tiers.<gate>.<class>` | string: a tier | the tier in algebra.md section 9 | findings: tiers | 9.2 | 1.0 |
| `plan.ambient` | path set | empty, with built-in members | the plan check | 10.2 | 1.0 |
| `plan.shared` | path set | empty | the plan check | 10.3 | 1.0 |
| `plan.locations.<kind>` | path set | absent: the kind has no default location | promise discharge | 10.4 | 1.0 |
| `ledger.approval-required` | array of strings: kinds | empty: no kind needs approval | approval | 11.1 | 1.0 |
| `ledger.harness-markers` | array of strings | empty: the tool's built-in list only | the commands that write the ledger | 11.2 | 1.0 |
| `evidence.coverage-attribution` | string: `"optional"` or `"required"` | `"optional"` | promise discharge | 12 | 1.0 |

### 3.3 The canonical form

A tool that writes a manifest, such as `sinter init`, writes the
**canonical form**:

1. The top-level keys come first.
2. Then each table that holds a setting follows, in the order of the
   table in section 3.1, under one header line.
3. Under each header, each key is a dotted key that holds the whole
   key path below the table. Example: `tiers.merge.dangling = "block"`
   under `[check]`.

## 4. Reading the manifest

### 4.1 The order of the checks

The tool checks a manifest in five steps, in this order:

1. The TOML syntax (sections 2.2 and 2.3).
2. The key `spec` (section 5).
3. The names of the keys and the types of the values.
4. Each value, against the rules of its key.
5. The checks that need a tree (section 8.2), during the scan of each
   tree.

The tool stops at the first step that finds an error. It reports each
error of that step that it finds, one per line, in the order of their
positions in the file. Then the command stops with exit code 3.

Step 2 comes before step 3. So when `spec` states a version that is
newer than the version of the tool, the tool reports the version, and
not a key that it does not know.

### 4.2 Errors

Each error message gives the position of the error: the path of the
manifest, the line, and the column. Lines and columns count from 1, as
in [jsonl.md](jsonl.md) section 3. A column counts Unicode code points
(characters), not bytes. For a dotted key, the position is
the first part of the key that is in error.

**An unknown key.** A table, a key, or a name that varies is an error
when it is not valid at its place. The message suggests the nearest
valid name at that place, when one is within two edits. An edit is one
insertion, deletion, or substitution of a character, or one swap of
two characters next to each other. This is the distance that
`typo-tag` uses ([algebra.md](algebra.md) section 9). When two names
are equally near, the message suggests the first in byte order.

**A key at the wrong place.** When an unknown key is a fixed name of
another place in the layout, the message names that place. Example: a
line `target = "trunk"` under the header `[evidence]` gives the key
path `evidence.target`. The message says that `target` belongs at the
top level, above the first table header.

**A wrong type.** A value of the wrong TOML type is an error. The
message names the type that the key takes and the type that it found.
The manifest uses three types of value: strings, booleans, and arrays
of strings. Tables hold the keys. A value of any other type is a wrong
type at every key: an integer, a float, a date or a time, or an array
of tables.

**A wrong value.** A value of the right type that breaks a rule of its
key is an error. Sections 5 to 12 give the rules. When the value must
be one word of a fixed list, the message suggests the nearest word, by
the rule for an unknown key.

The front matter of a rule file follows the same rules (section 15).

### 4.3 Example messages

This list is informative.

```
sinter: no sinter.toml at the repository root; create one, or name one with --manifest
sinter: sinter.toml names no pack; add a line such as packs.markdown.files = ["**/*.md"] under [scan]
sinter: sinter.toml:9:1: unknown key 'historic' in [check]; did you mean 'historical'?
sinter: sinter.toml:14:1: 'target' belongs at the top level, above the first table header
sinter: sinter.toml:8:15: 'rollout-cap' takes true or false, not a string
sinter: sinter.toml:4:1: the dotted key 'b.ct' adds a key to the table 'a.b', which a table header made; write 'ct' under the header [a.b]
sinter: sinter.toml:1:8: this manifest needs specification 1.2, and this sinter implements 1.1; install a newer sinter
sinter: sinter.toml:5:1: the pack markdown is built into sinter and takes no version
sinter: sinter.toml:12:1: 'law-touched' takes no tier; it always reports and never blocks
sinter: sinter.toml:13:1: 'bad-scope' takes no tier at the gate 'target'
sinter: sinter.toml:6:12: '.' is not in the id pattern language; put it in a class, for example [.]
sinter: sinter.toml:6:12: the pattern matches an empty id
sinter: no branch 'main' exists here or on origin; set 'target' in sinter.toml
sinter: src/a.ts is in the files of two packs, typescript and javascript; add a '!' glob to one of them
sinter: .plans/auth.md is under .plans/, and the pack markdown does not read it; add ".plans/" to its files
```

## 5. The specification version: `spec`

`spec` states the oldest version of the specifications that the
manifest needs. The key is optional. With no `spec`, the tool makes no
version check. `sinter init` writes the version that the tool
implements.

The value has the form `MAJOR.MINOR`: two decimal numbers with no
leading zero, joined by `.`. Example: `"1.0"`. A value with a patch
number, such as `"1.0.0"`, is an error. A patch release changes no
meaning ([docs/versioning.md](../docs/versioning.md)).

A tool implements one version of the specifications. One version is
newer than another when its major number is greater, or when the
major numbers are equal and its minor number is greater. The tool
compares `spec` with its own version:

1. When `spec` is newer than the version that the tool implements, the
   tool stops with exit code 3. The message names both versions and
   says to install a newer tool.
2. When the major number of `spec` is less than the major number of
   the version that the tool implements, the tool stops with exit code
   3. A new major version can change the meaning of a key, so the tool
   does not read a manifest of an older major version. The message
   names both versions and points to the notes on the change between
   the two major versions.
3. When the manifest writes a key that a version newer than `spec`
   added, the tool stops with exit code 3. The column "since" of
   section 3.2 gives the version that added each key. The message
   names the key, the version that added it, and the line
   `spec = "<version>"` to write.

`spec` yields no fact (section 14.1).

## 6. The target branch: `target`

The **target branch** is the branch that work merges into. The key
`target` names it. The default is `"main"`. `sinter init` writes the
key only when the target branch is not `main`.

The value must be a branch name: `refs/heads/<value>` must pass
`git check-ref-format`, and the value must not start with `refs/`.

A command that needs a base, and that has no `--base`, resolves the
target branch to a commit. In the list below, `<branch>` is the value
of `target`. The command tries these refs in order, and it takes the
first that exists:

1. `<branch>@{upstream}`: the branch that the local branch `<branch>`
   tracks.
2. The local branch `refs/heads/<branch>`.
3. The remote branch `refs/remotes/origin/<branch>`.

When none of the three exists, the command stops with exit code 3. The
message says to set `target` in the manifest.

The base of the diff is the merge base of `HEAD` and the commit of the
target branch. When the two commits have no common ancestor, the
command stops with exit code 3.

The plain output of `sinter status` and of `sinter check` names the
base that the command used: the ref that resolved, and the commit of
the base. The `index` record carries the base and the target branch
([jsonl.md](jsonl.md) section 10).

## 7. Globs, path sets, and the file set

### 7.1 The glob language

A **glob** is a pattern that matches paths. Sinter uses one glob
language for every glob:

- the globs of a `@scope` line;
- the path sets of the manifest;
- the argument of `path()` in a query;
- the scope of a rule.

A **path** is relative to the repository root. It is a sequence of
names joined by `/`, with no `/` at the start or at the end. The last
name is the name of a file. Each other name is the name of a folder.

A glob is a sequence of segments joined by `/`. A segment is `**`, or
a sequence of characters in which `*` has a special meaning. These
rules give the meaning of a glob:

1. A glob always matches from the repository root. `Cargo.lock`
   matches only the file `Cargo.lock` at the root. To match the file
   at any depth, write `**/Cargo.lock`.
2. A glob matches the whole path.
3. `*` matches any sequence of characters inside one name, the empty
   sequence included. It never matches `/`.
4. A segment `**` that is not the last segment matches any number of
   folders, zero included. So `**/x.md` matches `x.md` and `a/b/x.md`,
   and `a/**/b` matches `a/b`.
5. A segment `**` that is the last segment matches one or more names:
   everything inside the folder before it. `docs/**` matches
   `docs/a.md` and `docs/a/b.md`. It does not match a file named
   `docs`.
6. A glob that ends with `/` means the same as the glob with `**`
   added. `docs/` means `docs/**`.
7. `*` and `**` match names that start with `.`.
8. Every other character matches itself. Case always matters, on every
   file system.

These are errors in a glob:

- an empty glob;
- a `/` at the start;
- two `/` together, which make an empty segment;
- a segment `.` or `..`;
- `**` in a segment that holds other characters too, such as
  `src/**.ts`; write `src/**/*.ts`;
- the characters `?`, `[`, `]`, `{`, `}`, and `\`.

### 7.2 Path sets

A **path set** is an array of globs. A member that starts with `!` is
a **`!` glob**: the rest of the member is a glob. Every other member is
a **plain glob**. A path is in a path set when a plain glob matches it
and no `!` glob matches it. The order of the members does not change
the set. The same rule gives the set of every list of globs in Sinter,
for example the globs of a `@scope` line.

A path set in the manifest must also meet these rules:

1. Each member is a valid glob, or `!` and then a valid glob.
2. No member occurs twice.
3. A path set that is not empty holds at least one plain glob.
4. An empty array means the same as an absent key.

A glob that matches no file is not an error. `sinter status` prints a
**health line** for each glob that the manifest writes, plain or `!`,
that matches no file of the file set of the working tree. A health line
reports the state of the setup of Sinter. It is not a finding.

### 7.3 The file set

The **file set** of a tree is the set of files that Sinter can read in
that tree.

- In the working tree, the file set is the set that
  `git ls-files -z --cached --others --exclude-standard` gives: the
  tracked files as they are on disk, and the untracked files that git
  does not ignore. A tracked file that is deleted on disk is not in the
  set.
- In the base tree, the file set is the set of files in the tree of the
  base commit.
- In both trees, Sinter does not read inside a submodule. It leaves
  each symbolic link out of the file set, and it does not follow a
  symbolic link.

Sinter reads a file only when the file is in the file set and in the
files of a pack (section 8.1). A `!` glob in the files of a pack is
the only way to leave a file of the file set out of reading. The
manifest holds no other list of paths to leave out.

## 8. `[scan]`: packs and refs

### 8.1 Packs

A **pack** is the support for one language that Sinter loads: a
grammar, and the queries that find the tag-bearing nodes in it
([vocabulary.md](vocabulary.md) section 2). The name of a pack matches
`[a-z][a-z0-9]*(-[a-z0-9]+)*`.

`scan.packs.<name>.files` is a path set. The **files of a pack** are
the files of the file set that this path set holds. The pack `<name>`
reads these files. The key is required for each pack that the manifest
names, and its path set must not be empty. The manifest must name at
least one pack.

The pack `markdown` is built into the tool. Every other pack is a
**fetched pack**: the command `sinter pack add` fetches it, and the
lock file `sinter.lock` at the repository root fixes its bytes by
their hash.

`scan.packs.<name>.version` names the release of a fetched pack that
the repository uses. The value has the form `MAJOR.MINOR` of section 5.
Each release `MAJOR.MINOR.x` of the pack meets it, and the lock file
fixes one of those releases. The key is required for each fetched
pack. The pack `markdown` takes no `version`, and the key on it is an
error.

When a pack that the manifest names is not available to the tool, a
command that reads the repository stops with exit code 3.

### 8.2 Checks on the tree

Two checks need the tree. Each check applies to every tree that a
command reads. When a check fails, the command stops with exit code 3.

1. **A file in two packs.** A file is in the files of two packs. The
   message names the file and both packs.
2. **A plan file that the pack `markdown` does not read.** A file of
   the file set matches `.plans/**/*.md`, and it is not in the files of
   the pack `markdown`. The message names the file.

### 8.3 Ref namespaces

A **ref** is a tag target that points outside the repository, written
`<ns>/<id>` ([vocabulary.md](vocabulary.md) section 4.2). `<ns>` is a
**ref namespace**, and `<id>` is the id inside it.

`scan.refs.<ns>` declares the ref namespace `<ns>`. Its value is an id
pattern (section 8.4). A ref `<ns>/<id>` resolves when the manifest
declares `<ns>` and `<id>` matches the pattern of `<ns>`. Otherwise the
ref does not resolve ([vocabulary.md](vocabulary.md) section 4.2).

The name of a namespace matches `[a-z][a-z0-9]*(-[a-z0-9]+)*`. No
namespace is built in. For the issues and the pull requests of a
project on GitHub, write `refs.gh = "[1-9][0-9]*"` under `[scan]`.

### 8.4 The id pattern language

An **id pattern** is a small regular expression that matches the whole
id of a ref. A pattern is built from these parts:

| part | form | matches |
|---|---|---|
| literal | one printable ASCII character, `!` to `~`, other than `\ . [ ] ( ) { } * + ? \| ^ $` | that character |
| class | `[`, one or more members, `]` | one character that a member matches |
| member | one printable ASCII character, `!` to `~`, other than `\`, `[`, `]`, and `^`; or a range `x-y` | that character; or each character from `x` to `y` |
| group | `(`, a pattern, `)` | what the pattern matches |
| sequence | parts one after another | what each part matches, one after another |
| alternation | `a\|b` | what `a` matches, or what `b` matches |
| quantifier | `?`, `*`, `+`, `{n}`, `{n,}`, or `{n,m}` after a literal, a class, or a group | the part 0 or 1 times; 0 or more times; 1 or more times; `n` times; `n` or more times; from `n` to `m` times |

Alternation binds loosest: `ab|c` means `(ab)|c`.

These rules apply:

1. A pattern matches an id only when it matches the whole id. `^` and
   `$` are errors.
2. Case always matters. There are no flags.
3. `.` and `\` are errors. To match one of the other characters that
   a literal leaves out, put it in a class: `[.]`, `[+]`. No pattern
   matches `\`, `[`, `]`, or `^`.
4. The two ends of a range are both digits, both upper-case letters,
   or both lower-case letters, and the first end does not come after
   the second. Examples: `0-9`, `A-F`, `a-z`. A `-` is a member when it
   is first or last in its class. Any other `-` must stand between the
   two ends of a range.
5. In a quantifier, `n` and `m` are decimal numbers from 0 to 255, and
   `n` is not greater than `m`.
6. A part takes one quantifier at most: `a**` and `a+?` are errors. An
   empty class, an empty group, and an empty alternative are errors.
7. A pattern that matches the empty id is an error. Example: `[0-9]*`.
8. An id that holds a space, or a character outside printable ASCII,
   matches no pattern.

A pattern in this language matches the same ids in POSIX extended
regular expressions, in RE2, and in ECMAScript, when each of them must
match the whole id. A pattern holds no `\`, so it reads the same in a
TOML basic string and in a TOML literal string.

| pattern | ids it matches |
|---|---|
| `[1-9][0-9]*` | the numbers of GitHub issues and pull requests, such as `42` |
| `[A-Z]+-[1-9][0-9]*` | Jira keys, such as `PROJ-1` |

## 9. `[check]`: findings and tiers

### 9.1 Gates and tiers

A **gate** is a point where Sinter checks a repository. There are three
gates:

| gate | where the check runs |
|---|---|
| `turn` | at the end of a turn of an agent, before the agent hands back its work |
| `merge` | on a change before the change merges into the target branch, for example on a pull request |
| `target` | on the target branch, after a merge |

A **tier** says how hard a finding class bites at one gate:

| tier | effect at the gate |
|---|---|
| `off` | `sinter check --gate <gate>` does not report the class |
| `warn` | the check reports each finding of the class; the finding does not change the exit code |
| `block` | the check reports each finding of the class; the finding makes the check exit with code 1 |

[algebra.md](algebra.md) section 9 gives the tier of each built-in
finding class at each gate. A `—` there means that the class takes no
tier at that gate.

### 9.2 Tiers in the manifest

`check.tiers.<gate>.<class>` sets the tier of the built-in finding
class `<class>` at the gate `<gate>`. The value is `"off"`, `"warn"`,
or `"block"`. One line sets one pair of a gate and a class. `tiers`
names built-in finding classes only.

These are errors:

- `<gate>` is not `turn`, `merge`, or `target`;
- `<class>` is not a built-in finding class;
- `<class>` takes no tier at `<gate>`;
- `<class>` is `law-touched`, which always reports and never blocks;
- `<class>` is `pack-drift`, which takes no tier at any gate.

### 9.3 The rollout cap and the tier that applies

`check.rollout-cap` is a boolean. The default is `false`. While the
value is `true`, the **rollout cap** lowers to `warn` each tier that
[algebra.md](algebra.md) section 9 sets to `block`, at every gate. The
cap does not change a tier that `check.tiers` writes. `sinter init`
writes `rollout-cap = true`.

The **tier that applies** to a pair of a gate and a class is the first
of these that holds:

1. When `check.tiers` writes the pair, the written tier.
2. When `check.rollout-cap` is `true` and algebra.md section 9 gives
   the pair `block`, `warn`.
3. The tier that algebra.md section 9 gives the pair.

So a class passes the cap at one gate when the manifest writes its
tier. Example: `tiers.merge.dangling = "block"` under `[check]`.

### 9.4 Historical paths

`check.historical` is a path set. A located fact under a
**historical** path makes no finding of any class
([algebra.md](algebra.md) section 9, global rule 1). Sinter still
reads a file under a historical path, and a citation in the file still
resolves to its tag target ([vocabulary.md](vocabulary.md) section
8.4). Use the key for text that records the past, such as a log of
development.

The path set has one built-in member: `.plans/**/*.log.md`, the
journals of plans. The members of the manifest add to it. A `!` glob
of the manifest leaves out paths of the manifest's own members only.
It never removes the built-in member.

## 10. `[plan]`: the plan check and promise discharge

### 10.1 Path roles

A **path role** is the meaning that a path set gives to each of its
paths: a historical path (section 9.4), an ambient path, a shared
path, or the default location of a kind. Each role has its own setting. A
path with two roles is written in two settings. Example: a folder of
generated documentation can be in `plan.ambient` and in
`check.historical`.

### 10.2 Ambient paths

`plan.ambient` is a path set. A hunk under an **ambient** path needs
no plan step: `unmapped-work` does not report it
([algebra.md](algebra.md) section 9). Use the key for files that tools
write, such as lock files and generated code.

The path set has these built-in members:

- each plan file ([vocabulary.md](vocabulary.md) section 10.1);
- the manifest, when it is inside the repository;
- the lock file `sinter.lock`.

The members of the manifest add to them. A `!` glob of the manifest
leaves out paths of the manifest's own members only. It never removes
a built-in member.

### 10.3 Shared paths

`plan.shared` is a path set. A **shared** path is a path that every
step of every plan can change, such as the dependency and license
files at the repository root. A hunk under a shared path is never work
outside a plan: `unmapped-work` does not report it. A shared path does
not widen the place where a promise can be met
([vocabulary.md](vocabulary.md) section 10.4).

### 10.4 Default locations

`plan.locations.<kind>` is a path set. `<kind>` is `req`, `design`, or
`decision`. The path set is the **default location** of the kind. A
promised declaration of the kind is met when a declaration with its
slug exists in one of two places ([vocabulary.md](vocabulary.md)
section 10.5): inside the effective scope of its step, or inside the
default location of the kind. A kind with no entry has no default
location.

`plan.locations.plan` is an error. Plan files always live under
`.plans/` ([vocabulary.md](vocabulary.md) section 10.1).

## 11. `[ledger]`: approval and the ledger

### 11.1 Approval

`ledger.approval-required` is an array of kinds. Each member is
`"req"`, `"design"`, `"decision"`, or `"plan"`, and no member occurs
twice. The default is empty: no kind needs approval.

A **stamp** is a ledger entry that records an approval
([ledger.md](ledger.md) section 5). An item of a kind in the list is
approved only when the ledger holds a stamp for it:

- a declaration of the kind `req`, `design`, or `decision` needs a
  stamp for its current slug, revision, and extent hash;
- a plan needs a stamp against which its current commitment set is
  approved ([ledger.md](ledger.md) section 11).

An item of a kind that is not in the list counts as approved. The
predicate `approved()` ([algebra.md](algebra.md) section 6.5), each
finding class that uses it, and the liveness of a `@supersedes` edge
([vocabulary.md](vocabulary.md) section 8.1) follow this rule.

### 11.2 Harness markers

A **harness marker** is an environment variable that an agent harness
sets. The commands `sinter approve`, `sinter decline`, and
`sinter ledger abandon` refuse with exit code 4 when the environment
holds a harness marker, whatever its value.

The tool holds a built-in list of harness markers.
`ledger.harness-markers` is an array of names that add to that list.
Each name matches `[A-Za-z_][A-Za-z0-9_]*`, and no name occurs twice.
The default is empty. The manifest can only add names. It cannot
remove a name from the built-in list of the tool. A name that is
already in that list is valid, and it changes nothing.

## 12. `[evidence]`: test evidence

`evidence.coverage-attribution` is `"optional"` or `"required"`. The
default is `"optional"`. The value decides which rungs of a
`@verifies` edge complete a promise. [algebra.md](algebra.md) section
6.7 defines the rungs. **Attributed coverage** is coverage that
Sinter measures for each test on its own. An edge is at rung
`unattributed` when its tests pass and the run covered its sites, but
no attributed coverage shows that the test ran them.

| value | rungs that complete a promise |
|---|---|
| `"required"` | `passing` |
| `"optional"` | `passing` and `unattributed` |

The rule applies in three places:

- when a promised `@verifies` is met ([vocabulary.md](vocabulary.md)
  section 10.5);
- when a step or a plan is done (`done()`,
  [algebra.md](algebra.md) section 6.4);
- when a plan meets the discharge condition ([ledger.md](ledger.md)
  section 8).

The tier of the class `unattributed` is a separate setting. It decides
how hard an edge at rung `unattributed` bites as a finding.

## 13. Built-ins

This specification fixes these values. The manifest cannot change
them, except as the last column says.

| built-in | value | what the manifest can do |
|---|---|---|
| the file set | section 7.3 | leave files out of the files of each pack, with `!` globs |
| the glob language | section 7.1 | nothing |
| the id pattern language | section 8.4 | nothing |
| the folder of plans | `.plans/` | nothing |
| the pack `markdown` | built into the tool | name it, and give its files |
| historical paths | `.plans/**/*.log.md` | add paths |
| ambient paths | each plan file, the manifest, `sinter.lock` | add paths |
| the tier of each pair of a gate and a built-in class | algebra.md section 9 | write another tier |
| the default of `target` | `"main"` | write another branch |
| the default of `check.rollout-cap` | `false` | write `true` |
| the default of `evidence.coverage-attribution` | `"optional"` | write `"required"` |

The list of harness markers is built into the tool, not into this
specification. The manifest can add names to it (section 11.2).

## 14. Facts from the manifest

### 14.1 Setting facts

The manifest yields facts of the kind `setting`, in the category `law`
([algebra.md](algebra.md) section 3):

- A key that the manifest writes with one value yields one setting
  fact.
- An array that the manifest writes yields one setting fact for each
  member.
- Each of `target`, `check.rollout-cap`, and
  `evidence.coverage-attribution` yields one setting fact with its
  default value when the manifest does not write it.
- Each built-in member of `check.historical` and of `plan.ambient`
  yields one setting fact. The value of the member for a plan file is
  the path of the plan file. The value of the member for the manifest
  is the path of the manifest.
- `spec` yields no fact.
- `check.tiers` yields gate facts (section 14.2), and no setting
  facts.
- The built-in list of harness markers of the tool yields no facts.

The `setting` record has these fields, in addition to the envelope of
[jsonl.md](jsonl.md) section 3:

| field | type | meaning |
|---|---|---|
| `key` | string | the key path |
| `value` | string | a string as TOML decodes it; `true` or `false` for a boolean; for a built-in member, its glob or its path |
| `member` | bool | `true` when the fact is one member of an array |
| `default` | bool | `true` when the manifest does not write the key, and the fact holds the default value |
| `builtin` | bool | `true` when the fact is a built-in member |

A setting fact that the manifest writes is located: it carries the
path of the manifest and a position (section 14.3). A default fact and
a built-in fact are unlocated. When the manifest writes a member that
is also built in, Sinter yields one fact. That fact is located at the
written member, and its `builtin` field is `true`. A setting fact has
no `pack` field.

**Identity.**

| setting fact | id |
|---|---|
| one value | `setting:<key path>` |
| one member of an array | `setting:<key path>=<member>` |

A key path holds no `=`, so an id parses from the left: the key path
ends at the first `=`. An id does not change when a line moves, or
when the TOML form of a key changes.

### 14.2 Gate facts

The manifest and [algebra.md](algebra.md) section 9 yield one fact of
the kind `gate` for each pair of a gate and a class that takes a tier
at that gate. The `gate` record ([jsonl.md](jsonl.md) section 7) has
these fields:

| field | type | meaning |
|---|---|---|
| `gate` | string | `turn`, `merge`, or `target` |
| `class` | string | the finding class |
| `tier` | string | the tier that applies (section 9.3) |
| `default` | bool | `true` when `check.tiers` does not write the pair |
| `capped` | bool | `true` when the rollout cap lowered the tier |

A gate fact whose pair `check.tiers` writes is located at that entry.
A gate fact whose pair the manifest does not write is unlocated. The id
of a gate fact is `gate:<gate>/<class>`.

### 14.3 Positions

| fact | position |
|---|---|
| a setting fact of one value | from the first character of the key, as its line writes it, to the last character of the value |
| a setting fact of one member | the string of the member, its quotes included |
| a written gate fact | the whole entry, as for a setting fact of one value |

A comment after a value is not part of a position. Lines and columns
follow [jsonl.md](jsonl.md) section 3: they count from 1, and a column
counts Unicode code points (characters). The `path` of a located fact is
the path of the manifest, relative to the repository root.

A manifest outside the repository has no path relative to the
repository root. Its facts are all unlocated.

### 14.4 `law-touched`

`law-touched` is the finding class that reports a change to the law in
diff mode. It is an *engine* class: the adjudicator emits it
([algebra.md](algebra.md) section 9). Its tier is `warn` at every gate.
`check.tiers` cannot set it, and nothing turns it off.

**The two sides.** The adjudicator compares the working manifest with
the **base manifest**: the file at the same path, relative to the
repository root, in the base tree. It reads the base manifest only for
this comparison, as a TOML document. It does not check the names, the
types, or the values of the base manifest. When the base tree has no
such file, or the file is not valid TOML 1.0.0, the base side is the
side of an empty manifest.

From each side, the adjudicator makes a **comparison set**. Each entry
of the set has an id and a value, by the rules of sections 14.1 and
14.2:

1. one entry for each of `target`, `check.rollout-cap`, and
   `evidence.coverage-attribution`: the written value, or the default;
2. one entry for each other key that the side writes with one value;
   for a pair that `check.tiers` writes, the id is `gate:<gate>/<class>`
   and the value is the written tier;
3. one entry for each member of an array that the side writes, except
   a member that is also built in.

`spec` has no entry. On the base side, only the key paths of section
3.2 count, and only the values of the type that each key takes.

**A change.** An id that is in one comparison set only is a change. An
id whose two values differ is a change. Comments, blank lines, the
order of lines and of members, and the TOML form are no change. Each
change gives one `law-touched` finding.

**The subject.** The subject of the finding is the fact of the working
tree that has the id of the change, when one exists. Such a fact can
be a default fact or a default gate fact. When no such fact exists,
the subject is a tombstone of the base fact
([algebra.md](algebra.md) section 3), with the position of the base
fact in the base manifest.

**The position.** When the subject is located in the working manifest,
the finding sits at the subject. Otherwise the finding sits at a hunk
of the diff of the manifest: the hunk that removed the line of the base
entry. The finding takes the position of that hunk
([jsonl.md](jsonl.md) section 7). When no such hunk exists, the
finding sits at line 1, column 1 of the working manifest.

**The detail.** The detail is one line in one of these forms:

- `<key path>: <old> -> <new> (<direction>)`, when both sides have a
  value. A side that does not write a key of rule 1 has the default
  value. For a pair of `check.tiers`, `<old>` and `<new>` are the
  tiers that apply on the two sides (section 9.3).
- `<key path>: added <new> (<direction>)`, or
  `<key path>: removed <old> (<direction>)`, in every other case.

The detail writes a string in double quotes, and a boolean as `true`
or `false`. When the base manifest exists and is not valid TOML 1.0.0,
each detail ends with `; the base manifest is not valid TOML`.

**The direction.** A change **tightens** when Sinter checks more after
it, and **loosens** when Sinter checks less. A change that has no
single direction **changes**. "Checks more" does not mean "reports
more findings".

| key path | tightens | loosens | changes |
|---|---|---|---|
| `target` | | | each change |
| `scan.packs.<name>.files` | a plain glob added; a `!` glob removed | a plain glob removed; a `!` glob added | |
| `scan.packs.<name>.version` | | | each change |
| `scan.refs.<ns>` | a namespace removed | a namespace added | a pattern changed |
| `check.rollout-cap` | `true` to `false` | `false` to `true` | |
| `check.tiers.<gate>.<class>` | the tier that applies rises | the tier that applies falls | the tier that applies stays the same |
| `check.historical`, `plan.ambient`, `plan.shared`, `plan.locations.<kind>` | a plain glob removed; a `!` glob added | a plain glob added; a `!` glob removed | |
| `ledger.approval-required` | a kind added | a kind removed | |
| `ledger.harness-markers` | a name added | a name removed | |
| `evidence.coverage-attribution` | `"optional"` to `"required"` | `"required"` to `"optional"` | |

A tier rises in the order `off`, `warn`, `block`.

Examples of details:

```
check.rollout-cap: false -> true (loosens)
check.historical: added "docs/devlog/" (loosens)
check.tiers.merge.dangling: "block" -> "warn" (loosens)
scan.refs.jira: added "[A-Z]+-[1-9][0-9]*" (loosens)
ledger.approval-required: added "req" (tightens)
```

**A manifest outside the repository.** A manifest that `--manifest`
names outside the repository has no file in the base tree to compare
with, so diff mode reports no `law-touched` finding for it. The `index`
record names the path of the manifest ([jsonl.md](jsonl.md) section
10), so a reader of the output sees where the law came from.

## 15. Rule files

A **rule file** holds law that a repository writes outside the
manifest: a rule, or a finding class that the repository defines.
These parts of a rule file are fixed:

1. A rule file is a markdown file that starts with **front matter**: a
   first line that holds only `+++`, then TOML text, then a line that
   holds only `+++`. The markdown after the front matter follows the
   rules of every markdown file ([vocabulary.md](vocabulary.md)
   section 2).
2. The front matter holds what Sinter evaluates. The markdown holds
   the reason, for people to read.
3. A tag line `@rule <slug> vN` declares the rule.
4. The extent of the rule is the whole file, the front matter
   included. An edit of the front matter is an edit of the extent
   ([vocabulary.md](vocabulary.md) section 9).
5. A finding class that a repository defines has the same form. Its
   front matter holds the expression of the class.
6. A rule retires as a decision retires
   ([vocabulary.md](vocabulary.md) section 8). A rule can cite the
   decision that it rests on with `@cites`.
7. The tool reads the front matter by the rules of sections 2.2, 2.3,
   and 4. The front matter is TOML 1.0.0. An unknown key or a value of
   the wrong type is an error. The message gives the line and the
   column in the rule file, and a suggestion of the nearest key. An
   error stops the command with exit code 3.

## 16. Examples

This section is informative.

### 16.1 The smallest useful manifest

```toml
[scan]
packs.markdown.files = ["**/*.md"]
```

Sinter reads every markdown file of the file set: plans, decision
records, and other documents. Every other setting has its default.

### 16.2 Sinter

```toml
spec = "1.0"

[scan]
packs.markdown.files = ["**/*.md"]
packs.ocaml.files = ["**/*.ml", "**/*.mli"]
packs.ocaml.version = "1.0"
packs.rust.files = ["**/*.rs"]
packs.rust.version = "1.0"
refs.gh = "[1-9][0-9]*"

[check]
rollout-cap = true

[plan]
ambient = [
  "bridge/Cargo.lock",
  "sinter.opam",
  "sinter.opam.locked",
]
shared = [
  ".gitignore",
  "LICENSES/",
  "REUSE.toml",
  "THIRD_PARTY.md",
  "bridge/Cargo.toml",
  "dune-project",
]
locations.decision = ["docs/decisions/"]
```

### 16.3 A TypeScript project

```toml
spec = "1.0"

[scan]
packs.markdown.files = ["**/*.md", "!test/fixtures/"]
packs.typescript.files = ["**/*.ts", "!**/*.d.ts"]
packs.typescript.version = "1.0"
refs.gh = "[1-9][0-9]*"
refs.jira = "[A-Z]+-[1-9][0-9]*"

[check]
rollout-cap = true
historical = ["docs/devlog/"]
tiers.merge.dangling = "block"
tiers.target.dangling = "block"

[plan]
ambient = ["package-lock.json"]
shared = [".gitignore", "LICENSE", "package.json", "tsconfig.json"]
locations.decision = ["docs/decisions/"]

[ledger]
approval-required = ["req"]

[evidence]
coverage-attribution = "required"
```

The markdown files under `test/fixtures/` are test data, so the pack
`markdown` leaves them out. The class `dangling` passes the rollout
cap at the gates `merge` and `target`.
