<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: language packs

Status: draft. The six specifications share one version; see [docs/versioning.md](../docs/versioning.md).

## 1. Introduction

A **pack** is the support for one language in Sinter. It holds one or
more grammars, the query files that find the places where tags stand,
a descriptor, license notices, and optional runner adapters. This
document defines the files of a pack and their formats. It says how
Sinter reads a file with a pack, how the tags of a file form blocks,
and how a block attaches to code. It defines the tests
that a pack finds, and how Sinter binds test results to those tests.
It also defines the interface of a runner adapter, the default
adapter, and the lock file `sinter.lock`.

Anyone can implement this specification in any tool. See the
LICENSE-SPEC file at the repository root. The tags are defined in
[vocabulary.md](vocabulary.md). The facts that Sinter takes from a
file use the schema of [jsonl.md](jsonl.md). The manifest names the
packs of a repository and the files of each pack
([manifest.md](manifest.md) section 8.1).

In this document, "must" states a requirement, "can" states a
permission, and a **bold** term is defined where it first appears.

## 2. Packs

### 2.1 What a pack holds

| content | what it does | section |
|---|---|---|
| grammars | parse the files of the pack | 3.3 |
| query files | find the comments that can carry tags, the definitions that a comment can attach to, and the tests and the groups of tests | 4 |
| descriptor | names the pack and its release, and lists its grammars, its comment sigils, its foreign vocabulary, and its test runners | 3 |
| license notices | the license texts and the notices of the grammars, of the adapters, and of the pack itself | 2.3 |
| runner adapters | optional: one WebAssembly module for each test runner that needs code of its own | 10 |

A **grammar** is a tree-sitter grammar compiled to WebAssembly. Sinter
identifies a grammar by the SHA-256 of its file. Sinter does not read
the release number that the file of a grammar can state inside
itself. The **ABI version** of a grammar is the version of the
tree-sitter language format that its file uses.

### 2.2 The markdown pack and fetched packs

The pack `markdown` is built into Sinter. It has no version of its
own: it changes with the tool. It has no descriptor file, no entry in
the lock file, and no runner. Section 7 gives the rules by which it
reads a file.

Every other pack is a **fetched pack**. The command `sinter pack add`
takes a fetched pack from the packs repository or from a folder on the
local machine, and it records the pack in the lock file `sinter.lock`.
Sinter keeps the files of each fetched pack in a cache of the user.
Section 12 gives the packs repository, the lock file, and the cache.

Trust in a fetched pack comes from the hash in the lock file. Before
Sinter loads a fetched pack, it computes the pack hash of the files in
the cache. It compares that hash with the hash that the lock file fixes
for the pack. When the two differ, the command stops with exit code 3
(finding class `pack-drift`, [algebra.md](algebra.md) section 9).

### 2.3 The files of a pack

A fetched pack is a folder. The **pack root** is that folder. The paths
in this table are relative to the pack root.

| path | content | required |
|---|---|---|
| `pack.toml` | the descriptor (section 3) | yes |
| `grammars/<grammar>.wasm` | the grammar `<grammar>` | one for each grammar of the descriptor |
| `queries/<grammar>/tags.scm` | the comments of the grammar `<grammar>` (section 4.2) | one for each grammar |
| `queries/<grammar>/definitions.scm` | the definitions (section 4.3) | no |
| `queries/<grammar>/tests.scm` | the tests and the groups (section 4.4) | no |
| `adapters/<runner>.wasm` | the adapter of the runner `<runner>` (section 10) | one for each runner that has an adapter |
| `licenses/` | the text of each license that the descriptor names, and the notices that those licenses require | yes |

A pack can hold other files, for example the files of a conformance
fixture ([jsonl.md](jsonl.md) section 11). Sinter does not read them,
but the pack hash covers them. A pack holds no symbolic link.

### 2.4 The pack hash

The **pack hash** is the SHA-256 of the **pack listing**. The pack
listing is a text with one line for each file of the pack, in the byte
order of the paths of the files. Each line holds, in this order:

1. the SHA-256 of the file, as 64 lowercase hex digits;
2. two spaces;
3. the path of the file, relative to the pack root, with `/` between
   names and with no `./` at the start;
4. a line feed.

Each line has the form of a line that the command `sha256sum` prints.
This example is informative. In the pack root, this command prints the
pack hash, when no path holds a space or a line feed:

```
find . -type f | sed 's|^\./||' | LC_ALL=C sort | xargs sha256sum | sha256sum
```

### 2.5 Releases

A **release** of a fetched pack has a number of the form
`MAJOR.MINOR.PATCH`: three decimal numbers with no leading zero,
joined by `.`. Example: `1.0.3`. The manifest key
`scan.packs.<name>.version` names a value of the form `MAJOR.MINOR`
([manifest.md](manifest.md) section 8.1). A release **meets** that
value when its first two numbers are equal to the two numbers of the
value. The lock file fixes one release that meets the value.

The number of a release says what the release can change, compared
with the release of the same pack before it:

- A **patch release** raises only the third number. It changes no fact
  and no extent hash of a file that the release before it parses
  without a parse failure. It can make a file parse that failed to
  parse before, fix a crash, or fix the bindings of an adapter.
- A **minor release** raises the second number. It changes no extent
  hash. It can add facts, for example the tests of a shape that the
  queries did not find before. It can add a runner adapter.
- A **major release** raises the first number. It can change anything.

The packs repository checks each release against the conformance
fixtures ([jsonl.md](jsonl.md) section 11) of the release before it.

## 3. The descriptor

### 3.1 The file

The descriptor is the file `pack.toml` at the pack root. It is a TOML
1.0.0 document. Sinter reads it by the rules of
[manifest.md](manifest.md) sections 2.2 and 2.3. A key that this
section does not define, a value of the wrong type, and a value that
breaks the rule of its key are errors. A descriptor with an error does
not load (section 3.6).

### 3.2 Top-level keys

| key | type | required | meaning |
|---|---|---|---|
| `spec` | string | yes | the oldest version of the specifications that the pack needs, in the form of [manifest.md](manifest.md) section 5 |
| `name` | string | yes | the name of the pack. It matches the pattern of a pack's name ([manifest.md](manifest.md) section 8.1) |
| `version` | string | yes | the release of the pack (section 2.5) |
| `license` | string | yes | an SPDX license expression for the descriptor and the query files |
| `name-separator` | string, not empty | yes | the text that joins the names of a name path (sections 6.5 and 8.3) |
| `foreign-tags` | array of strings | no; the default is empty | the foreign vocabulary of the pack ([vocabulary.md](vocabulary.md) section 3.1): tag words, each without its `@` |
| `comments` | table | yes | the comment sigils (section 3.4) |
| `grammar` | array of tables | yes, with one table or more | the grammars (section 3.3) |
| `runner` | table | no | the test runners (section 3.5) |

### 3.3 Grammars

Each table of the array `grammar` describes one grammar:

| key | type | meaning |
|---|---|---|
| `name` | string | the name of the grammar. It matches `[a-z][a-z0-9_]*`. The file of the grammar is `grammars/<name>.wasm`, and the file exports the function `tree_sitter_<name>` |
| `sha256` | string | the SHA-256 of the file of the grammar, as 64 lowercase hex digits |
| `license` | string | an SPDX license expression for the grammar |
| `names` | array of globs | the names of the files that the grammar reads |

All four keys are required. No two grammars of a pack have one name.

The ABI version of each grammar must lie in the range that the
tree-sitter library of the tool accepts. A tool that uses tree-sitter
0.25 accepts the ABI versions 13 to 15.

Each member of `names` is a glob of [manifest.md](manifest.md) section
7.1. It is matched against the name of a file, which is the last name
of the file's path, and not against the whole path. Example:
`names = ["*.tsx"]`.

Sinter reads each file of the pack with the first grammar of the array
whose `names` match the name of the file. When the `names` of no
grammar match the name of a file of the pack, a command that reads the
repository stops with exit code 3 ([manifest.md](manifest.md) section
8.2).

### 3.4 Comment sigils

A **comment sigil** is a text that opens a comment, closes a comment,
or starts an inner line of a comment. The table `comments` lists the
comment sigils of the pack:

| key | type | meaning |
|---|---|---|
| `line` | array of strings | the sigils that open a comment that ends at the end of its line, for example `//` and `///` |
| `block` | array of arrays of two strings | the pairs of an opening sigil and a closing sigil, for example `["/*", "*/"]` and `["(*", "*)"]` |
| `inner` | array of strings | the sigils that can start an inner line of a block comment, for example `*` |

Each key is optional, and its default is empty. Section 6.3 gives the
use of the sigils.

### 3.5 Runners

A **test runner** is a program that runs tests and writes a report of
the results, for example vitest or cargo-nextest. The table
`runner.<runner>` describes the test runner `<runner>`. The name of a
runner matches the pattern of a pack's name, and it is not `files`,
`version`, or `runners`.

| key | type | meaning |
|---|---|---|
| `adapter.sha256` | string | the SHA-256 of the file `adapters/<runner>.wasm`, as 64 lowercase hex digits. Given when the runner has an adapter of its own |
| `adapter.license` | string | an SPDX license expression for the adapter. Given with `adapter.sha256` |
| `match` | table | the data of the default adapter (section 11.3). Given when the runner has no adapter of its own |
| `settings` | table | the runner settings and their default values |

A runner has exactly one of `adapter` and `match`.

A **runner setting** is a key that a repository can set for a runner
in its manifest, with the manifest key
`scan.packs.<name>.<runner>.<key>` ([manifest.md](manifest.md) section
8.1). Each key of the table `settings` names one runner setting, and
its value is the default value of the setting. The type of the default
value is the type of the setting: a string, a boolean, or an array of
strings. The value of a runner setting is the value that the manifest
gives, or else its default value.

Sinter gives the value of every runner setting to the adapter of the
runner (section 10.3). For a runner that uses the default adapter,
the name of each runner setting must be a key that section 11.3
defines for the table `match`, and the value of the setting takes the
place of that key in `match`. A key that `settings` names does not
also stand in `match`.

### 3.6 Loading a pack

Sinter loads a fetched pack before it reads a file of the pack. In
each of these cases, the pack does not load, and the command stops
with exit code 3:

- the pack hash of the files in the cache differs from the hash that
  the lock file fixes (`pack-drift`);
- the descriptor holds an error (section 3.1);
- the `name` of the descriptor differs from the name that the manifest
  gives the pack;
- the `version` of the descriptor differs from the release that the
  lock file fixes, or the release does not meet
  `scan.packs.<name>.version`;
- the tool implements an older version of the specifications than
  `spec`, by the comparison of [manifest.md](manifest.md) section 5;
- a file that section 2.3 requires is missing, or the SHA-256 of a
  grammar or an adapter differs from the descriptor;
- a grammar does not load, or its ABI version lies outside the range
  that the tool accepts (section 3.3);
- a query file does not compile against its grammar, or it breaks a
  rule of section 4, for example with a predicate that section 4.1
  does not list.

The message names the pack and the cause. Section 10.6 gives the
rules for an adapter.

## 4. Query files

### 4.1 Queries and matches

A query file holds a tree-sitter query. A query is a list of
**patterns**. Sinter runs each query over the syntax tree of a file. A
**match** is one place in the tree where one pattern matches. A match
holds the nodes that the pattern captures, each under a **capture
name**.

A pattern can use these **predicates**, which test the text of the
nodes that it captures:

| predicate | the match holds when |
|---|---|
| `#eq?` `#not-eq?` | the text of each node of a capture is, or is not, equal to a string or to the text of another capture |
| `#any-eq?` `#any-not-eq?` | the same test holds for at least one node of the capture |
| `#match?` `#not-match?` | the text of each node of a capture matches, or does not match, a regular expression |
| `#any-match?` `#any-not-match?` | the same test holds for at least one node of the capture |
| `#any-of?` `#not-any-of?` | the text of a capture is, or is not, one of a list of strings |

These are the predicates that tree-sitter's Rust library applies to
each match. The regular expression of a `match` predicate follows the
syntax of the Rust crate `regex`, which that library uses. A query
that uses any other predicate, or a directive such as `#set!`, is an
error.

Sinter ignores a capture whose name starts with `_`. A pattern can use
such a capture for a predicate, for example `#eq?`. Any other capture
name that section 4 does not define for the query file is an error.

Two matches can give one node the same role, for example when two
patterns of `definitions.scm` capture one node as `@definition`. Then
Sinter takes the match of the pattern that comes first in the query
file, and it ignores the other match.

### 4.2 `tags.scm`: comments

| capture | meaning |
|---|---|
| `@comment` | a comment |
| `@untagged` | a comment that carries no tags |

Every pattern captures `@comment` or `@untagged`. Sinter reads tags
only in a comment that `@comment` captures and that `@untagged` does
not capture. A comment that `@untagged` captures is still a comment for
the rules of section 6.

This example is informative. In OCaml, a doc comment `(** *)` carries
no tags, and a plain comment `(* *)` carries them:

```scheme
((comment) @untagged (#match? @untagged "^\\(\\*\\*[^*]"))
(comment) @comment
```

### 4.3 `definitions.scm`: definitions

A **definition** is a node of the code that a tag block can attach
to, for example a function, a type, a module, or a class. A
**decoration** is a node that can stand between a tag block and its
definition, for example a Rust attribute (section 6.4).

| capture | meaning |
|---|---|
| `@definition` | a definition |
| `@name` | the node whose text is the name of the definition |
| `@body` | the body of the definition. Without `@body`, the body of the definition is the definition node |
| `@decoration` | a decoration |

A pattern captures `@definition` once, with `@name` once or not at
all and `@body` once or not at all. Or it captures `@decoration`, and
no other capture of this table.

The body is the span of the code hash ([vocabulary.md](vocabulary.md)
section 6.2) and of coverage ([jsonl.md](jsonl.md) section 4).

This example is informative. In Rust:

```scheme
(function_item name: (identifier) @name body: (block) @body) @definition
(attribute_item) @decoration
```

### 4.4 `tests.scm`: tests and groups

A **test** is a test as the source declares it, for example a Rust
function with the attribute `#[test]`, or a call `it("adds", ...)` in
TypeScript. A **group** is a node that holds tests, for example a
vitest `describe`, a Rust `mod tests`, or a test class.

| capture | meaning |
|---|---|
| `@test` | a test |
| `@group` | a group |
| `@name` | a node whose text is a piece of the name of the test or the group |
| `@placeholder` | a node whose text the runner replaces at run time, for example a template substitution `${n}`, or a title that is not a literal |
| `@label.<word>` | any node; the capture adds the **label** `<word>` to the test or the group. `<word>` matches `[a-z][a-z0-9-]*` |

A pattern captures exactly one of `@test` and `@group`, once. Section
8 gives the meaning of the other captures. Sinter gives the labels of
each test and each group to the adapter (section 10.3). A label can
mark a kind of test, for example a test that the runner runs once for
each row of a table.

This example is informative. In TypeScript, for vitest:

```scheme
(call_expression
  function: [(identifier) @_fn
             (member_expression object: (identifier) @_fn)
             (call_expression function: (member_expression object: (identifier) @_fn))]
  arguments: (arguments .
    [(string [(string_fragment) @name (escape_sequence) @placeholder]*)
     (template_string [(string_fragment) @name (escape_sequence) @placeholder
                       (template_substitution) @placeholder]*)])
  (#any-of? @_fn "it" "test")) @test

(call_expression
  function: [(identifier) @_fn
             (member_expression object: (identifier) @_fn)]
  arguments: (arguments . (string [(string_fragment) @name (escape_sequence) @placeholder]*))
  (#eq? @_fn "describe")) @group
```

## 5. Reading a file

### 5.1 The text

Sinter reads each file as UTF-8 text. A file that is not valid UTF-8
has no syntax tree. Sinter takes no fact from it, and it reports one
`parse-error` finding at line 1, column 1 of the file.

Before Sinter parses a file, it adds a line feed at the end of the
text when the text does not end with one.

### 5.2 Parse failures

A **parse failure** is a syntax tree that holds an `ERROR` node or a
`MISSING` node. A `MISSING` node can have no text, and then only the
error flag of the root node shows it. So Sinter reads a parse failure
from the error flag of the root node.

The **error flag** of a node is set when the node, or a node below it,
is an `ERROR` node or a `MISSING` node. A **lowest error node** is a
node whose error flag is set, when no child of the node that the tree
shows has its error flag set. When a `MISSING` node has no text, the
tree does not show it, and the lowest error node is near its place.

In a file of a fetched pack, a parse failure means that the file
yields no fact. Sinter reports one `parse-error` finding for the
file. The finding sits at the first `ERROR` or `MISSING` node
in the order of the text. When the tree shows no such node, the
finding sits at the first lowest error node in the order of the
text.

In a markdown file, Sinter takes the facts of the file from the tree,
as it does for a file with no parse failure. It reports one
`parse-error` finding at each `ERROR` node and each `MISSING` node
that no other `ERROR` node holds. So an `ERROR` node inside an `ERROR`
node gives no finding of its own, and one place of error gives one
finding. When the flag of the root shows a failure
and the tree shows no such node, Sinter reports one finding at the
first lowest error node in the order of the text. At a gate where the tier that applies to the class
`parse-error` is `block` ([manifest.md](manifest.md) section 9.3), the
tier of such a finding is `warn`. At every other gate, the tier is the
tier that applies.

### 5.3 Positions

Sinter gives each position as a line and a column, both counted from
1 ([jsonl.md](jsonl.md) section 3). These rules apply:

- A line ends at a line feed (LF). A carriage return (CR) right before
  an LF is part of the line ending.
- A column counts Unicode code points (characters), not bytes. The
  characters of a line ending count in no column.
- A byte order mark at the start of a file is part of no line, and it
  counts in no column.
- A span ends at its last character that is not part of a line ending.

The parser gives each column in bytes, and it counts a byte order
mark. Sinter converts each column with the text of its line.

## 6. Tags in code

This section applies to the files of every fetched pack.

### 6.1 Comments and code

A **comment** is a node that `tags.scm` captures (section 4.2).
**Code** is each character of a file that is not inside a comment,
that is not a space or a tab, and that is not part of a line ending
(section 5.3). A **blank line** is a line that holds only spaces and
tabs.

The **first line** of a node is the line of its first character. The
**last line** of a node is the line of its last character that is not
part of a line ending.

### 6.2 Runs

A **run** is a sequence of comments that Sinter reads as one unit. The
run is the tag-bearing node of code ([vocabulary.md](vocabulary.md)
section 2). Sinter forms the runs of a file in the order of the text:

1. A comment that starts on a line that holds code is a run by
   itself. No other comment joins its run.
2. Any other comment joins the run of the comment right before it when
   two conditions hold. First, it starts on the last line of that
   comment or on the next line. Second, only spaces, tabs, and line
   endings stand between the two comments.
3. Otherwise, the comment starts a new run.

So a blank line or a line of code ends a run. The kind of a comment
does not matter: line comments, block comments, and doc comments join
one run.

The **tag-bearing text** of a run is the lines of its comments that
carry tags (section 4.2). The tag lines and the blocks of a run are
the tag lines and the blocks of its tag-bearing text
([vocabulary.md](vocabulary.md) section 3.1). The extent of a block in
code is the tag-bearing text of its run ([vocabulary.md](vocabulary.md)
section 6).

### 6.3 Comment sigils

Before Sinter reads the lines of a comment, it changes each line in
these steps, with the comment sigils of the pack (section 3.4):

1. Remove the spaces and tabs at the start of the line.
2. On the first line of the comment, remove the longest sigil of
   `line`, or the longest opening sigil of `block`, that the line
   starts with. On every other line of a block comment, remove the
   longest sigil of `inner` that the line starts with, when one
   exists.
3. On the last line of a block comment, remove the closing sigil of
   its pair from the end of the comment.

The rule for tag lines ([vocabulary.md](vocabulary.md) section 3.1)
and step 1 of the extent hash ([vocabulary.md](vocabulary.md) section
6.1) take the lines that these steps give.

### 6.4 Attachment

An **attachment target** is a definition (section 4.3), a test, or a
group (section 4.4). One node can be a definition and a test, or a
definition and a group. A run attaches to the attachment target `T`
when these three conditions hold:

1. `T` is the first attachment target that starts after the end of the
   run. When two targets start at one place, `T` is the one that ends
   last.
2. No code stands before the first comment of the run on the first
   line of that comment.
3. Each line after the last line of the run and before the first line
   of `T` holds code of a decoration, and no other code.

So a blank line between the run and `T` breaks attachment, and a
decoration does not. When no target meets the conditions, the run is
**unattached**. The blocks of a run attach where the run attaches.

The effect on each tag of a block ([vocabulary.md](vocabulary.md)
section 7.2):

| tag | attached to a test or a group | attached to a definition only | unattached |
|---|---|---|---|
| `@verifies` | the source is the test or the group | an orphan (finding class `orphan`) | an orphan |
| `@satisfies`, `@cites` | the source is a code site attached to `T` | the source is a code site attached to `T` | the source is a code site with no attachment target |

### 6.5 Sites

A code site ([vocabulary.md](vocabulary.md) section 7.2) takes these
fields of its record ([jsonl.md](jsonl.md) section 4) from its
attachment target:

| field | attached to `T` | unattached |
|---|---|---|
| `name` | the name path of `T`, when `T` is a definition with a name; otherwise omitted | omitted |
| `node` | the node type of `T` | omitted |
| `dline` `deline` | the first and the last line of the body of `T` | omitted |
| `ch` | the code hash of the body of `T` | omitted |

The body of a test or a group that is not a definition is its node.

A definition **holds** another node when the range of the definition
holds the range of the other node. The **name path** of a definition
is the names of the definitions that hold it, outermost first, and
then its own name, joined with the `name-separator` of the pack. A
definition with no `@name` adds no name.

The id of a site with a name is `site:<path>#<name>`. Two or more
sites of one file can have one name. Then the first of them in the
order of the file keeps that id. Each later one adds `#2`, `#3`, and
so on, in the order of the file. A site with no name has the
positional id `site:<path>@L<line>C<column>`, where `<line>` and
`<column>` give the position where its run starts
([jsonl.md](jsonl.md) section 9).

## 7. Tags in markdown

This section applies to the pack `markdown`. It reads the structure
that CommonMark gives a file: headings, paragraphs, lists, block
quotes, code blocks, HTML blocks, and tables.

### 7.1 Sections

Only an ATX heading opens a section ([vocabulary.md](vocabulary.md)
section 2). A heading inside a block quote or inside a list item opens
no section. Its text belongs to the block quote or the list item.

### 7.2 First paragraphs

[vocabulary.md](vocabulary.md) section 2 makes two paragraphs
tag-bearing: the first paragraph of a section and the first paragraph
of a list item. The first paragraph is the block right after the
heading or the list marker, when that block is a paragraph. So when
that block is a list, a code block, an HTML block, a table, a block
quote, or a thematic break, the section or the list item has no first
paragraph.

Nothing inside a block quote is tag-bearing
([vocabulary.md](vocabulary.md) section 2). A list item inside a block
quote has no tag-bearing paragraph.

Sinter reads tags in no other paragraph. A section or a list item
holds a paragraph **directly** when no list item and no block quote
inside it holds the paragraph. Take a paragraph that a section or a
list item holds directly, and that is not its first paragraph. When
the first line of that paragraph is a tag line, Sinter reports one
finding of the class `unread-tag` at that line
([algebra.md](algebra.md) section 9). Sinter reports no `unread-tag`
inside a block quote.

### 7.3 Tag lines

Each line of a tag-bearing paragraph is a tag line when its text,
after the spaces and tabs at its start, starts with `@`
([vocabulary.md](vocabulary.md) section 3.1). This rule also holds for
a line inside a code span or inside inline HTML that crosses lines:
Sinter does not parse the inline content of a paragraph.

### 7.4 Front matter

A file can start with **front matter**: a first line that holds only
`+++` or only `---`, then lines of text, then the next line that holds
only the same three characters. Spaces and tabs can follow the three
characters on the first and on the last line of the front matter.

Only front matter that starts with `+++` holds TOML. A rule file starts
with front matter of this form ([manifest.md](manifest.md) section
15). Front matter that starts with `---` has no meaning for Sinter.

The front matter is one node. It holds no tag line, and it is not a
block for the rules of section 7.2.

## 8. Tests

### 8.1 Tests and groups

Sinter finds the tests and the groups of a file with the query file
`tests.scm` of its grammar (section 4.4). A group **holds** a test or
another group when the range of the group holds the range of the
other node. When a test holds another test, Sinter reads the outer
test as a group.

Each test and each group is a fact of the kind `test`
([jsonl.md](jsonl.md) section 4). The record of a group carries
`"group":true`. The span of the fact is its node.

### 8.2 Names

The **name** of a test or a group is a sequence of **pieces**. Each
node that its match captures as `@name` or as `@placeholder` gives one
piece, in the order of the text:

- A `@name` node gives a **text piece**: the text of the node, as the
  source writes it.
- A `@placeholder` node gives a **placeholder**: text of the name that
  the runner fills in at run time. A placeholder matches any
  text, the empty text included.

Sinter decodes nothing in a name: it removes no quote, and it reads no
escape sequence. A pack that captures each escape sequence of a title
as `@placeholder` lets the escape match the text that the runner
reports. The data of a runner can also mark placeholders inside the
text pieces, for example `%i` (section 11.3).

The **name path** of a test is the names of the groups that hold it,
outermost first, and then its own name. The name path of a group is
formed in the same way. Two name paths are equal when they have the
same names, piece for piece.

Sinter reads no tag and no requirement id in the name of a test. A
test verifies a declaration only through a `@verifies` tag in a block
that attaches to the test (section 6.4).

### 8.3 Test facts

The record of a test fact ([jsonl.md](jsonl.md) section 4) gives each
name as text: the text of its pieces, each placeholder as the source
writes it. Its field `name` is the own name of the test or the group.
Its field `parents` holds the names of the groups that hold it,
outermost first.

The **full name** of a test or a group is the names of its name path,
as text, joined with the `name-separator` of the pack. The id of a
test fact is `test:<path>#<full name>`. Two or more tests or groups of
one file can have one full name. Then the first of them in the order
of the file keeps that id. Each later one adds `#2`, `#3`, and so on,
in the order of the file ([jsonl.md](jsonl.md) section 9).

### 8.4 `@verifies` on a group

A `@verifies` tag whose source is a group stands for every test that
the group holds, the tests of nested groups included. The edge takes
the worst status of those tests ([algebra.md](algebra.md) section
6.7).

## 9. Test results

### 9.1 Runners and reports

A **report** is a file that a test runner writes, for example a JUnit
XML file. A **result** is the outcome of one test, or of one group, in
a report. A result has a status: `pass`, `fail`, `error`, or `skip`. A
result can also give a file and a line.

The manifest key `scan.packs.<name>.runners` names the runners of the
pack `<name>` ([manifest.md](manifest.md) section 8.1). A runner name
stands in the `runners` of one pack at most.

`sinter evidence import` reads the reports that its command line
names. For each report:

1. Sinter gives the report to the adapter of each runner that the
   manifest names, with the call `recognise` (section 10.4). The
   default adapter answers for each runner that has no adapter of its
   own (section 11.1).
2. When exactly one runner recognises the report, Sinter gives the
   report to the adapter of that runner, with the call `bind` (section
   10.5), together with the tests and the groups of the files of the
   runner's pack.
3. When two or more runners recognise the report, the command stops
   with exit code 3. The message names the report and the runners, and
   it asks for `--runner <name>`.
4. When no runner recognises the report, the command stops with exit
   code 3. The message names the report and the runners that the
   manifest names.

The option `--runner <name>` names one runner of the manifest. With
the option, Sinter makes no call `recognise`: it gives each report of
the command to the adapter of that runner, with the call `bind`.

When the command stops for a reason of this section or of section
10.6, it imports no result of any report.

### 9.2 The meaning of results

An adapter reads the results of a report, and it **binds** each result
to tests and groups: it says which test or group each result is about,
and why. Sinter keeps the meaning of the results. These rules apply
to the bindings of every adapter:

1. **Status.** The status of a test is the worst status of the results
   that bind to it, in the order of [jsonl.md](jsonl.md) section 6:
   `pass`, `skip`, `fail`, `error`. A test that no result binds to did
   not run, and a skipped test counts as a test that did not run
   ([algebra.md](algebra.md) section 6.7).
2. **Groups.** The status of a group is the worst status of the tests
   that it holds and of the results that bind to the group itself
   ([algebra.md](algebra.md) section 6.7).
3. **One full name.** Tests and groups of one file with equal name
   paths share their results: each of them takes every result that
   binds to any of them.
4. **One result, two tests.** One result can bind to two tests or
   groups that differ in their file or in their name path. Then each
   of them gets one finding of the class `ambiguous-result`
   ([algebra.md](algebra.md) section 9), and each of them still takes
   the result.
5. **Files.** When a result gives a file, a binding of the result is
   valid only when the file matches the path of its test or group
   (section 9.3).
6. **Unbound results.** When more than half of the results of a report
   bind to nothing, the command prints a warning. The warning names
   the report, the runner, the number of results, and the number of
   results that bind to nothing. The command also prints each result
   with the status `fail` or `error` that binds to nothing.

No adapter can make a failure pass. An adapter only reads results and
binds them. A binding adds a result to a test or a group, and nothing
removes a result from one. Sinter computes each status from the
results by the rules above.

Sinter keeps the results and their bindings in the evidence set of the
tree key ([algebra.md](algebra.md) section 2). For each test and each
group that a result binds to, the scan yields one `run` fact
([jsonl.md](jsonl.md) section 6), with the worst status of its
results.

### 9.3 Files in a report

To compare the file of a result with the path of a test, Sinter first
**normalizes** the file:

1. Replace each `\` with `/`.
2. When the file is an absolute path inside the repository root, make
   it relative to the repository root.
3. Split the file into names at each `/`. Remove each empty name, each
   name `.`, and each name `..` at the start.

The file **matches** a path when the shorter of the two lists of names
is equal to the end of the longer list. Examples: the files
`src/math.test.ts`, `./src/math.test.ts`, and `math.test.ts` all match
the path `src/math.test.ts`. So does a file
`/home/ci/work/src/math.test.ts` that is outside the repository root.

## 10. Runner adapters

### 10.1 The module

A **runner adapter** is a WebAssembly module that reads the reports of
one test runner and binds their results. A pack carries at most one
adapter for each runner. The module imports nothing: no function, no
memory, no table, and no global. So it reads no file, it uses no
network, and it sees no clock. It exports these five names:

| export | type | meaning |
|---|---|---|
| `memory` | memory | the linear memory of the module |
| `sinter_interface` | `() -> i32` | the version of the interface that the module implements |
| `sinter_alloc` | `(i32) -> i32` | reserves the given number of bytes in `memory`, and returns the address of the first byte, or `0` when it cannot |
| `sinter_recognise` | `(i32, i32, i32, i32) -> i64` | the call `recognise` (section 10.4) |
| `sinter_bind` | `(i32, i32, i32, i32) -> i64` | the call `bind` (section 10.5) |

The module can export other names, and Sinter does not use them. For
example, a module that the Rust compiler builds also exports the
globals `__data_end` and `__heap_base`.

This section defines version `1` of the interface.

### 10.2 A call

Sinter makes each call in a new instance of the module, so no state
passes from one call to the next. For a call, Sinter takes these
steps:

1. It calls `sinter_alloc` for the size of the request, and it writes
   the request (section 10.3) at the address: a JSON document in
   UTF-8, in the canonical form of RFC 8785.
2. It calls `sinter_alloc` for the size of the report, and it writes
   the bytes of the report file, unchanged, at the address.
3. It calls the function with four arguments: the address and the
   length of the request, then the address and the length of the
   report.
4. It reads the result of the function. The high 32 bits are the
   address and the low 32 bits are the length of the **response**: a
   JSON document in UTF-8 in `memory`.

Sinter reads each address and each length as an unsigned number.

Sinter runs each call under two limits. The limit of **fuel** bounds
the number of WebAssembly instructions that the call runs, in the
calls of `sinter_alloc` and in the call of the function together. The
limit of memory bounds the size of `memory`. Fuel does not depend on the
speed of the machine, so a call that exceeds the limit on one machine
exceeds it on every machine. The tool fixes both limits. Neither a
pack nor a manifest can change them.

### 10.3 The request

The request is a JSON object:

| field | type | meaning |
|---|---|---|
| `interface` | integer | the version of the interface: `1` |
| `runner` | string | the name of the runner |
| `settings` | object | one member for each runner setting (section 3.5), with its value: a string, a boolean, or an array of strings |
| `report` | string | the path of the report, as the command line gives it |
| `root` | string | `bind` only: the absolute path of the repository root, with `/` between names |
| `tests` | array of objects | `bind` only: the tests and the groups of the files of the pack, in the byte order of their ids |

Each object of `tests` has these fields:

| field | type | meaning |
|---|---|---|
| `id` | string | the id of the test fact (section 8.3) |
| `path` | string | the path of its file, relative to the repository root |
| `line` `eline` | integer | the first and the last line of its node |
| `group` | boolean | `true` for a group, `false` for a test |
| `names` | array of arrays of objects | the name path: one array for each name, outermost first. Each object is one piece: `{"text": <text>}` for a text piece, `{"placeholder": <text>}` for a placeholder, with the text of the node |
| `labels` | array of strings | the labels of the test or the group (section 4.4), in byte order |

### 10.4 The call `recognise`

The call `recognise` says whether the report is a report of the
adapter's runner. The response is `{"recognised": true}` or
`{"recognised": false}`.

### 10.5 The call `bind`

The call `bind` reads the results of the report and binds them. The
response is a JSON object with these fields:

| field | type | meaning |
|---|---|---|
| `results` | array of objects | each result that the adapter read, in the order of the report |
| `bindings` | array of objects | each binding of a result to a test or a group |
| `warnings` | array of strings | messages for the person who runs the command, for example about a kind of result that the adapter cannot bind. The array can be empty |

Each object of `results`:

| field | type | meaning |
|---|---|---|
| `name` | string | the name of the result, as the report writes it |
| `status` | string | `pass`, `fail`, `error`, or `skip` |
| `file` | string | the file of the result, as the report writes it; omitted when the report gives none |
| `line` | integer | the line of the result, counted from 1; omitted when the report gives none |
| `ms` | integer | the duration of the result in whole milliseconds; omitted when the report gives none |

Each object of `bindings`:

| field | type | meaning |
|---|---|---|
| `result` | integer | the index of the result in `results`, counted from 0 |
| `test` | string | the id of a test or a group of the request |
| `reason` | string | one line: why the result binds to the test or the group |

When the adapter cannot read the report, the response is
`{"error": <message>}` instead.

### 10.6 Errors

An adapter is **valid** when it imports nothing, exports the five
names of section 10.1 with their types, and its `sinter_interface`
returns a version that the tool implements. `sinter pack add` does not
add a pack that holds an adapter that is not valid.

A call **fails** in each of these cases:

- the adapter is not valid;
- the module traps;
- the call exceeds its limit of fuel, or the module asks to grow
  `memory` past its limit of memory;
- `sinter_alloc` returns `0`, or an address whose bytes do not lie
  inside `memory`;
- the bytes of the response do not lie inside `memory`;
- the response is not a JSON document in UTF-8;
- the response breaks section 10.4 or 10.5: a missing field, a field
  that the section does not define, a value of the wrong type, an
  index outside `results`, a test id that the request does not hold,
  or one pair of a result and a test that occurs twice;
- a binding breaks rule 5 of section 9.2;
- the response is an `error` object.

When a call fails, `sinter evidence import` stops with exit code 3,
and it imports no result of any report. The message names the pack,
the runner, the report, and the cause. For an `error` response, the
message also gives the message of the adapter.

## 11. The default adapter

A runner that has no adapter of its own uses the **default adapter**,
which is built into Sinter. The default adapter reads JUnit XML reports.
It binds their results with the data of the runner: the table
`runner.<runner>.match` of the descriptor and the runner settings
(section 3.5).

### 11.1 Reports

A **JUnit XML report** is an XML 1.0 document whose root element is
`testsuites` or `testsuite`. A `testsuite` element holds `testcase`
elements and other `testsuite` elements.

The default adapter recognises no file other than a JUnit XML report.
It recognises a JUnit XML report for a runner in one of two cases:

1. The data of the runner has no `recognise` key, or the key is empty.
2. One member of `recognise` holds for the root element of the report
   (section 11.3).

### 11.2 Results

Each `testcase` element is a result. When the key `suite-match` is
`true`, each `testsuite` element is also a result.

The status of a `testcase` element is the first of these that holds:

1. `error`, when the element holds an `error` element;
2. `fail`, when the element holds a `failure` element;
3. `skip`, when the element meets a condition of the key `not-run`;
4. `pass`.

The status of a `testsuite` element is the worst status of the
`testcase` elements that it holds, at any depth. A `testsuite` element
that holds no `testcase` element has the status `skip`.

The name of a result is its parts (section 11.3), joined with a
space. The attribute `time` of the element, a number of
seconds, gives the duration: the whole milliseconds, rounded down.

### 11.3 The data of a runner

The table `runner.<runner>.match` of the descriptor holds these keys:

| key | type | default | meaning |
|---|---|---|---|
| `path` | array of strings | none: required | the **path sources**: the places in the report that hold the name path of a result, in order. A member is `suites`, which gives one **part** for each `testsuite` element that holds the element, outermost first; or the name of an attribute of the element, which gives one part: the value of the attribute |
| `anchor` | string | `"whole"` | `"whole"`: each name of the pattern stands in the parts. `"tail"`: the pattern can leave out names of its prefix, from its start |
| `prefix` | string | `"none"` | `"none"`: the pattern has no prefix. `"path"`: the prefix is the names of the folders of the file of the test, then the name of the file without its last extension |
| `prefix-separator` | string | absent | the text between two names of the prefix, and between the prefix and the first group |
| `group-separator` | string | absent | the text between two groups |
| `test-separator` | string | absent | the text between the last group, or the prefix, and the own name of a test |
| `lead` | array of affix patterns | empty | the text that can stand before the pattern, in the first part |
| `group-suffixes` | array of affix patterns | empty | the text that can stand after the name of a group |
| `name-suffixes` | array of affix patterns | empty | the text that can stand after the own name of a test |
| `placeholders` | array of id patterns | empty | the patterns that mark placeholders inside the text pieces of names |
| `rewrite` | array of arrays of two strings | empty | the replacements in the text pieces of names: each pair is a text and the text that replaces it |
| `file` | array of strings | empty | the **file sources** of a result, in the order that the default adapter tries them. A member is the name of an attribute of the element; `suite:<attribute>`, the attribute of the nearest `testsuite` element that holds the element and has the attribute; or `document:<attribute>`, the attribute of the first `testsuite` element of the document that has it |
| `line` | string | absent | the name of the attribute of the element that holds the line of the result |
| `line-base` | integer | `1` | `0` or `1`: the number that the attribute `line` gives the first line of a file |
| `not-run` | array of strings | `["skipped"]` | the conditions under which a `testcase` element did not run. A member is `skipped`, which holds when the element holds a `skipped` element; or `<attribute>=<value>`, which holds when the attribute of the element has the value |
| `suite-match` | boolean | `false` | when `true`, each `testsuite` element is a result too, and it can bind to a test or a group |
| `recognise` | array of strings | empty | the shapes of the root element of a report of the runner (section 11.1). A member is `<element>`, which holds when the root element has that name; or `<element>@<attribute>=<value>`, which holds when the root element has that name and its attribute has exactly that value. Example: `testsuites@name=vitest tests` |

An absent separator is a **part boundary**: the names on its two
sides stand in two parts.

An **affix pattern** is a text in which `*` matches any text, the
empty text included. Every other character matches itself. An **id
pattern** is a pattern of [manifest.md](manifest.md) section 8.4.

### 11.4 Patterns

The default adapter builds a **pattern** from the name path of each
test or group of the request, in these steps:

1. **Rewrite.** In each text piece, replace each occurrence of the
   first text of each pair of `rewrite` with the second text, pair by
   pair, in the order of the array.
2. **Placeholders.** Read each text piece from its start. At each
   place, take the longest text that an id pattern of `placeholders`
   matches, and make that text a placeholder. Where no id pattern
   matches, keep the character as text, and go on at the next
   character.
3. **Names.** The names of the pattern are the names of the prefix,
   then the **groups**, then, for a test, its own name. For a test, the
   groups are the names of the groups that hold it. For a group, the
   groups are the names of the groups that hold it, and then its own
   name.
4. **Separators.** Join two names of the prefix, and the prefix and
   the first group, with `prefix-separator`. Join two groups with
   `group-separator`. Join the last group, or the prefix when there is
   no group, and the own name of a test with `test-separator`. An
   absent separator is a part boundary.
5. **Affixes.** After the name of each group, one text that a
   `group-suffixes` pattern matches can stand. After the own name of a
   test, one text that a `name-suffixes` pattern matches can stand.
   Before the first name, one text that a `lead` pattern matches can
   stand. Each of these texts can also be empty.

The pattern **matches** the parts of a result when two conditions
hold. First, the pattern and the result have the same number of parts.
Second, some choice of affixes, of a text for each placeholder, and of
a text for each `*` makes each part of the pattern equal to the part
of the result. With `anchor = "tail"`, the pattern can first leave out
any number of names of its prefix, from its start.

### 11.5 Binding

For each result, the default adapter takes these steps:

1. **Parts.** It reads the parts of the result from the path
   sources. When an attribute that `path` names is absent, the result
   binds to nothing.
2. **Candidates.** The candidates of a `testcase` result are the tests
   of the request. The candidates of a `testsuite` result are the tests
   and the groups of the request.
3. **File.** It takes the file of the result from the first file
   source that gives one. When the result has a file, the adapter
   keeps only the candidates whose path the file matches (section
   9.3).
4. **Line.** It takes the line of the result from the attribute that
   `line` names, and it adds 1 when `line-base` is `0`. When the result
   has a file and a line, and the lines of a candidate test hold the
   line, the result binds to that test, and step 5 does not apply.
   When the lines of two such tests hold the line, the result binds to
   the test whose node starts last.
5. **Names.** Otherwise, the result binds to each candidate whose
   pattern matches the parts of the result.

The reason of each binding names the step that made it and the parts
or the line that it compared.

### 11.6 Example

This example is informative. It is the data of the runner vitest in
a TypeScript pack:

```toml
[runner.vitest.match]
path = ["name"]
group-separator = " > "
test-separator = " > "
placeholders = ["%[sdifjoOc#$]", "[$][A-Za-z_][A-Za-z0-9_.]*"]
file = ["classname"]

[runner.vitest.settings]
recognise = ["testsuites@name=vitest tests"]
```

`recognise` is a runner setting. A repository that gives its reports
another name, with the vitest option `suiteName`, sets
`scan.packs.typescript.vitest.recognise` in its manifest.

vitest writes a test of the file `src/math.test.ts` in this form:

```xml
<testcase classname="src/math.test.ts" name="outer > each 1 + 2 = 3" time="0.001"/>
```

In that file, a test `it.each(...)('each %i + %i = %i', ...)` inside
`describe('outer', ...)` has the name path `outer`, `each %i + %i =
%i`. Step 2 of section 11.4 makes each `%i` a placeholder. The pattern
has one part, `outer > each … + … = …`, where each `…` is a
placeholder. It matches the attribute `name`. The file
`src/math.test.ts` matches the path of the test, so the result binds
to the test.

## 12. Fetching packs

### 12.1 The packs repository

Sinter's own packs live in the **packs repository**: the repository
`sinter-packs` on GitHub, `https://github.com/lathrys-at/sinter-packs`.
Each release of a pack is one GitHub release of that repository:

- Its tag is `<name>-v<version>`, for example `rust-v1.0.3`.
- It holds one asset, the **archive** `<name>-<version>.tar.gz`: a tar
  file, compressed with gzip, that holds the files of the pack. The
  path of each file in the archive is its path relative to the pack
  root.

An archive holds regular files and folders only. Sinter refuses an
archive that holds any other entry, such as a link, and an archive
with a path that starts with `/` or that holds the name `..`. After
Sinter unpacks an archive, it computes the pack hash of the files
(section 2.4). So the pack hash does not depend on the archive.

### 12.2 The index

The **index** is the file `index.jsonl` on the branch `main` of the
packs repository. It lists each release of each pack. Sinter reads the
index from one fixed address:

```
https://raw.githubusercontent.com/lathrys-at/sinter-packs/main/index.jsonl
```

The option `--index <address>` of a command that reads the index names
another address, for example the address of the index of a mirror. The
manifest has no key for the index.

The index is a JSON Lines file. Each line is a JSON object in the
canonical form of [jsonl.md](jsonl.md) section 2, and it describes one
release:

| field | type | meaning |
|---|---|---|
| `v` | integer | the version of the format of the index: `1` |
| `name` | string | the name of the pack |
| `version` | string | the release number (section 2.5) |
| `url` | string | the `https` address of the archive of the release |
| `hash` | string | the pack hash of the release (section 2.4), as 64 lowercase hex digits |

The lines are in the byte order of the names of the packs. The lines
of one pack are in the order of the release numbers, from the oldest.
No two lines have one name and one release number. An index that
breaks a rule of this section is an error: the command that reads it
stops with exit code 3.

Example:

```json
{"hash":"5e0c…","name":"rust","url":"https://github.com/lathrys-at/sinter-packs/releases/download/rust-v1.0.3/rust-1.0.3.tar.gz","v":1,"version":"1.0.3"}
```

### 12.3 Adding a pack

`sinter pack add <name>` takes these steps:

1. It reads `scan.packs.<name>.version` from the manifest. When the
   manifest does not give the key, the command stops with exit code 3.
   The message says to add the key.
2. It reads the index, and it takes the newest release of the pack
   whose number meets that value (section 2.5). When no release meets
   the value, the command stops with exit code 3.
3. It downloads the archive of the release and unpacks it. It computes
   the pack hash of the files and compares it with the hash in the
   index. When the two differ, the command stops with exit code 3.
4. It checks the pack as section 3.6 says. It also checks each adapter
   (section 10.6).
5. It keeps the files of the pack in the cache (section 12.5), and it
   writes the line of the pack into the lock file. A line that the lock
   file holds for the pack already is replaced.

When the command stops, it changes neither the cache nor the lock
file.

`sinter pack add` can also take a pack from a folder on the local
machine. It then takes the name and the release from the descriptor of
the folder, and it checks that the release meets
`scan.packs.<name>.version`. It computes the pack hash of the files of
the folder, and steps 4 and 5 follow. On another machine,
`sinter pack fetch` finds such a pack only when the index holds its
release with the same pack hash.

### 12.4 The lock file

The lock file is the file `sinter.lock` at the repository root.
`sinter pack add` writes it. It holds one line for each fetched pack.
Each line is a JSON object in the canonical form of
[jsonl.md](jsonl.md) section 2. The lines are in the byte order of the
names of the packs.

| field | type | meaning |
|---|---|---|
| `v` | integer | the version of the format of the lock file: `1` |
| `name` | string | the name of the pack |
| `version` | string | the release of the pack (section 2.5) |
| `hash` | string | the pack hash (section 2.4), as 64 lowercase hex digits |

Example:

```json
{"hash":"5e0c…","name":"rust","v":1,"version":"1.0.3"}
{"hash":"a41d…","name":"typescript","v":1,"version":"1.0.0"}
```

These rules apply:

- The pack `markdown` has no line.
- When the manifest names no fetched pack, the lock file can be
  absent.
- When the manifest names a fetched pack that the lock file holds no
  line for, or when the release of the line does not meet
  `scan.packs.<name>.version`, a command that reads the repository
  stops with exit code 3. The message names the pack and says to run
  `sinter pack add`.
- A line for a pack that the manifest does not name has no effect.
- The lock file is an ambient path ([manifest.md](manifest.md) section
  10.2).
- The `index` record of a scan names each pack of the lock file
  ([jsonl.md](jsonl.md) section 10).

### 12.5 The cache and `sinter pack fetch`

Sinter keeps the files of each fetched pack in a **cache** of the
user, outside every repository, under the pack hash of the pack.

`sinter pack fetch` reads the lock file. For each line, when the cache
lacks the pack, the command finds the release of the line in the
index, downloads the archive, and unpacks it. It then compares the pack
hash of the files with the hash of the line. When the two are equal, it
keeps the files in the cache. The command also downloads again a pack
whose files in the cache no longer give its pack hash. It never changes
the lock file. When the index holds no such release, or when a hash
differs, the command keeps no file of that pack and stops with exit
code 3.

Only three commands use the network: `sinter pack add`,
`sinter pack fetch`, and `sinter init`, which can do what
`sinter pack fetch` does. Every other command takes the packs from the
cache. A command that needs a pack that the cache lacks stops with exit
code 3, and the message says to run `sinter pack fetch`.

## 13. Example

This example is informative. It is the descriptor of a TypeScript pack
with two grammars and one runner:

```toml
spec = "1.0"
name = "typescript"
version = "1.0.0"
license = "Apache-2.0"
name-separator = "."
foreign-tags = ["param", "returns", "throws", "example", "see", "type"]

[comments]
line = ["//"]
block = [["/*", "*/"], ["/**", "*/"]]
inner = ["*"]

[[grammar]]
name = "typescript"
sha256 = "778025db5a8be0e70f8ccc3671e486dfeddd048c25d9e8a70c26de2e1bf6f97d"
license = "MIT"
names = ["*.ts", "*.mts", "*.cts"]

[[grammar]]
name = "tsx"
sha256 = "79e5da75ea62855a0cd67177685f0164eac87d5f630b3cbe1e0a099751ad30f8"
license = "MIT"
names = ["*.tsx"]

[runner.vitest.match]
path = ["name"]
group-separator = " > "
test-separator = " > "
placeholders = ["%[sdifjoOc#$]", "[$][A-Za-z_][A-Za-z0-9_.]*"]
file = ["classname"]

[runner.vitest.settings]
recognise = ["testsuites@name=vitest tests"]
```

The pack root holds `pack.toml`, `grammars/typescript.wasm`,
`grammars/tsx.wasm`, the query files under `queries/typescript/` and
`queries/tsx/`, and the license texts under `licenses/`.
