<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: query algebra

Status: draft. The seven specifications share one version; see [docs/versioning.md](../docs/versioning.md).

## 1. Introduction

The query algebra is a small language. Sinter uses it for three jobs:
to write queries, to write rules, and to define finding classes. A
query selects a subset of the facts that a scan produced. This
document defines the universe of facts, the syntax of expressions, the
type discipline, every function, and the built-in finding classes.

Anyone can implement this specification in any tool. See the
LICENSE-SPEC file at the repository root. The facts themselves are
defined in the JSONL specification, [jsonl.md](jsonl.md); the tags they
come from are defined in [vocabulary.md](vocabulary.md).

Notation used in this document: `∈` means "is a member of", `⊆` means
"is a subset of", `∅` is the empty set, `⋃` is a union over a family of
sets, `→` gives a function's result, and `⊥` means "unresolved". `S`
and `T` range over fact sets, `E` over edge sets, `P` over promises,
`R` over rules, `K` over kind lists, `n` over name patterns, and `g`
over globs.

## 2. Universe

A query is evaluated against a **universe** `U`. Sinter produces the
universe by scanning one working tree `T` against one base `B`. The
scan also reads one ledger `L`, one evidence set `E`, and one session
`S`. The evidence set `E` is the set held for the tree key of `T`.
Every fact is an immutable record with a `kind` and a stable `id` (see
[jsonl.md](jsonl.md), section "Identity").

A query denotes a subset of `U` and nothing else. There are no
scalars, no tuples, and no new facts. `U` is finite. Every closure is
a least fixpoint of a monotone function, so every closure terminates.

`U` is a function of `(T, B, L, E, S)`. Two evaluations with the same
five inputs see the same universe and produce the same output bytes.
The algebra has no access to time, to the environment, or to the
network. The tool sets `GIT_NO_LAZY_FETCH=1` in the environment of
every git child process. So in a **partial clone**, a clone that
leaves out some objects, git reports a missing object as an error and
never downloads it.

## 3. Kinds and categories

Every kind belongs to exactly one **category**. `kind(x)` accepts a
kind or a category.

| category | kinds | located? |
|---|---|---|
| `node` | `req` `design` `decision` `plan` `step` `test` `site` | yes |
| `edge` | `satisfies` `verifies` `refines` `cites` `supersedes` | yes |
| `external` | `external` | no |
| `promise` | `promise` | yes |
| `evidence` | `run` `cov` `judgment` | no |
| `config` | `rule` `gate` `setting` | see below |
| `ack` | `ack` | yes |
| `ledger` | `claim` `decline` | no |
| `hunk` | `hunk` | yes |
| `tombstone` | `tombstone` | yes (base coordinates) |
| `finding` | `finding` | yes (its subject's location) |

Notes on individual kinds:

- A `site` is an anonymous source: a source with no name. It is a code
  site, or a markdown section that holds a citation outside every
  declaration's extent ([vocabulary.md](vocabulary.md) section 7.2). A
  code site carries the code hash `ch`.
- A `test` is a test or a group of tests that a language pack finds
  ([packs.md](packs.md) section 8).
- A `rule` is located in its rule file ([manifest.md](manifest.md)
  section 14).
- A `setting` is one value of the manifest, and a `gate` is the tier
  that applies to one pair of a gate and a finding class
  ([manifest.md](manifest.md) section 13). A setting fact or a gate
  fact that the manifest writes is located in the manifest. A default,
  a built-in member, and every fact of a manifest outside the
  repository are unlocated.
- An edge's `src` is a node or a rule. An edge's `dst` is a node, an
  external id, or unresolved. A rule's origin is a `cites` edge whose
  `src` is the rule.
- A `hunk` is one hunk of `git diff B`, in new-side coordinates.
- A `tombstone` is a fact that is present in the fact set of `B` and
  absent from the fact set of `T`. It carries the old id, kind, and
  extent hash.

"Located" facts carry `path`, `line`, `col`, `eline`, and `ecol`. The
functions `path(…)`, `scope(…)`, `historical`, `exempt`, and `acked(…)`
return located facts only.

## 4. Syntax

```
query    := expr
expr     := term ( ws ('+' | '-') ws term )*
term     := atom ( ws '^' ws atom )*
atom     := '(' expr ')'
          | 'all'
          | word                    -- saved definition without parameters,
                                    -- or a keyword selector
          | word '(' args ')'       -- built-in or saved definition
args     := arg ( ',' ws? arg )*
arg      := expr | kinds | name | glob | revspec
kinds    := word ( '|' word )*
name     := slugpat | fullform | ( slugpat | fullform ) '/' slugpat
          | testpat
fullform := slugpat '@' hex6
slugpat  := [A-Za-z0-9*]+ ( [-_.] [A-Za-z0-9*]+ )*
hex6     := [0-9a-f]{6}
testpat  := any sequence of characters other than ',' and ')' ;
            quote with "…" otherwise; '*' globs
glob     := a glob of manifest.md section 7.1; quote with "…" if it
            contains whitespace or ','
revspec  := 'base' | any git revision
word     := [a-z][a-z0-9-]*
ws       := one or more spaces
```

Lexical rules:

- **Binary operators are whitespace-delimited.** `a - b` is a
  difference. `auth-lockout` is one slug. Without this rule, a parser
  could not tell a slug that contains a hyphen from a difference of
  two terms. `^` and `+` follow the same rule. Parentheses do not need
  whitespace.
- **Precedence.** `^` binds tighter than `+` and `-`. `+` and `-`
  share one level and associate left. So `a + b ^ c - d` means
  `(a + (b ^ c)) - d`.
- **Arguments are positional.** Each function declares the argument
  type that it accepts in each position (section 6). A `name` argument
  can contain `*` as a glob. A `name` matches a slug only when the
  case of each letter is equal ([vocabulary.md](vocabulary.md) section
  4.1). A `name` of the form `fullform` is the full form of a plan
  ([vocabulary.md](vocabulary.md) section 4.3); only `plan(n)` takes
  it, and `step(p/s)` takes it as `p`. A `kinds` argument can be a
  category name.
- **Names are resolved after substitution.** A saved definition's
  parameters are substituted as text before the expression is parsed
  (section 7). A parameter can therefore stand for an expression, a
  kind list, a name, or a glob.
- **Keywords.** `all`, `active`, `historical`, `exempt`, and `base`
  are reserved as bare words. A saved definition must not shadow a
  built-in name.

## 5. Categories as types

The tool assigns each expression a **category set** statically, before
evaluation:

- `all` → every category. `kind(K)` → the categories of the kinds in
  `K`. A name selector → its kind's category. `path`, `historical`,
  `exempt`, `acked` → every located category. `changed` → every
  category, tombstones and hunks included. `active` → `{node}`.
  `findings` → `{finding}`.
- `out`, `in` → `{edge}`. `src`, `dst`, `deps`, `rdeps`, `paths` →
  `{node, external, config}` (the `src` of a rule's origin edge is a
  rule). `subject` → every category a finding can be about. `scope` → the
  located categories plus `hunk`; its argument also accepts `claim`.
  `promises`, `met` → `{promise}`. `done` → `{node}`. A predicate →
  the category set of its argument, intersected with what it accepts.
  `obligations`, `judged` → every category. `triggered` →
  `{config}`.
- `S + T` → the union of the two category sets. `S ^ T` → the
  intersection. `S - T` → the left side's set.

Each function declares which categories it accepts for each argument.
The tool silently drops facts of other categories in an argument:
`src(all)` is valid and means "the sources of every edge". The tool
raises a static error only when an argument's category set does not
intersect the accepted set. Example: the tool rejects `src(kind(req))`
before evaluation with the message `src() accepts edge; argument has
category {node}`.

## 6. Function reference

There are 46 names. In the tables, `src(e)`, `dst(e)`, and `rev(e)`
are fields of an edge; `rev(d)` and `xh(d)` are fields of a
declaration. "Declaration" means a `req`, `design`, or `decision`.

### 6.1 Selectors

| function | denotes |
|---|---|
| `all` | `U` |
| `kind(K)` | facts whose kind or category is in `K` |
| `req(n)` `design(n)` `decision(n)` `rule(n)` | facts of that kind whose slug or name matches `n` |
| `plan(n)` | when `n` is a full form `<slug>@<id>`: the plan with that full form, open or closed. Otherwise: the open plans whose slug matches `n` ([vocabulary.md](vocabulary.md) section 4.3) |
| `step(p/s)` | steps whose step slug matches `s`, of the plans that `plan(p)` gives |
| `test(n)` | test nodes whose full name matches `n` ([packs.md](packs.md) section 8.3) |
| `external(ns/id)` | external facts matching |
| `path(g)` | located facts whose `path` matches `g` |
| `changed(b)` | see section 8; `b` is `base` or a revision |
| `active` | the active plan and, when the session declares one, the active step; only open plans are candidates; `∅` when no plan is active |
| `historical` | located facts under a historical path: a path of `paths.historical`, its built-in member included ([manifest.md](manifest.md) section 9.2) |
| `exempt` | located facts under an exempt path: a path of `paths.exempt`, its built-in members included (each plan file, the manifest, and the lock file `sinter.lock`; [manifest.md](manifest.md) section 9.1) |
| `acked(t)` | the located facts `f` whose tag-bearing block carries a live `@ack` with the tag target `t`, where `t` applies to `f`. The tag target `t` applies to `f` when both of these conditions hold: the class name or rule name in `t` matches, and the ack's subject, when the ack gives one, equals `f` in the form that [vocabulary.md](vocabulary.md) section 7.4 gives |
| `findings(C)` | finding facts whose class is in `C` |

### 6.2 Traversal (one hop, typed)

| function | accepts | denotes |
|---|---|---|
| `out(K, S)` | `S`: node, config | edges `e` with `kind(e) ∈ K` and `src(e) ∈ S` |
| `in(K, S)` | `S`: node, external | edges `e` with `kind(e) ∈ K` and `dst(e) ∈ S` |
| `src(E)` | edge | the sources of the edges in `E` |
| `dst(E)` | edge | the facts that the tag targets of the edges in `E` resolve to; an edge whose tag target resolves to nothing contributes nothing |
| `subject(F)` | finding | the subjects of the findings in `F`; a subject that is no fact ([jsonl.md](jsonl.md) section 9) contributes nothing |

### 6.3 Closures

Closures are least fixpoints. The tool ignores the edges whose tag
target resolves to nothing. It follows suspect edges, because a stale
citation is still a citation.

| function | accepts | denotes |
|---|---|---|
| `deps(K, S)` | node, config | the least `X ⊇ S` with `dst(out(K, X)) ⊆ X` |
| `rdeps(K, S)` | node, external | the least `X ⊇ S` with `src(in(K, X)) ⊆ X` |
| `paths(S, T)` | node, external, config | `deps(edge, S) ^ rdeps(edge, T)`: every node on some path from `S` to `T` over any edge kind |

### 6.4 Plan functions

| function | accepts | denotes |
|---|---|---|
| `scope(S)` | plan, step, rule, claim | located facts and hunks whose `path` matches the effective scope of some member of `S`. A step's effective scope is the step's own `@scope` when the step declares one; otherwise it is the plan's scope. A plan's effective scope is the union of the effective scopes of its steps. A rule's scope is its `scope` field. `∅` when `S` holds no scope-bearing fact |
| `promises(S)` | plan, step | promise facts whose step or plan is in `S` |
| `met(P)` | promise | the promises in `P` that are met, as defined in [vocabulary.md](vocabulary.md) section 10.5 |
| `done(S)` | plan, step | A step is in the result when both conditions hold. First: all of the step's promises are met. For a step with no promises, the first condition depends on `proof.step` ([manifest.md](manifest.md) section 10.4): under `"delivered"`, the step has a mark that counts ([vocabulary.md](vocabulary.md) section 10.8); under `"approval"`, the step is approved (section 6.5); under `"promises"`, the condition never holds. Second: every `verifies` edge in the step's scope is at rung `passing`, or at rung `unmeasured` when `proof.verifies` is `"whole-run"` ([manifest.md](manifest.md) section 10.3). A plan is in the result when all of its steps are in the result and the second condition holds for the plan's scope |

### 6.5 Status predicates

A predicate filters its argument: `pred(S) ⊆ S`.

| function | accepts | keeps `f ∈ S` iff |
|---|---|---|
| `inforce(S)` | any | For a declaration: `f` carries no status tag and no effective `@supersedes` edge points at `f` ([vocabulary.md](vocabulary.md) section 8.1). A member of a cycle of `@supersedes` edges that carries no status tag is in force, and the tool reports the `cycle` finding. For a plan, for its steps, and for its promises: the plan is open — the ledger holds no `completed` entry and no `abandoned` entry for its full form. The predicate keeps every fact of every other kind |
| `approved(S)` | any | A kind needs approval when its key `proof.<kind>` is `"approval"` ([manifest.md](manifest.md) section 10.1). The predicate keeps `f` when any one of these conditions holds: `f` is a declaration of a kind that needs approval, and the ledger holds an approval for `f`'s `(slug, rev, xh)`; `f` is a declaration of a kind that does not need approval; `f` is a plan, the kind `plan` needs approval, and `f`'s current commitment set is approved against the plan's latest approved set ([ledger.md](ledger.md) section 11); `f` is a plan, and the kind `plan` does not need approval; `f` is a step without promises, `proof.step` is `"approval"` ([manifest.md](manifest.md) section 10.4), and the ledger holds an approval of `f` that matches its current step hash ([ledger.md](ledger.md) section 5.1); `f` is a step, the plan of `f` is approved, and `f` has promises or `proof.step` is not `"approval"`; `f` is a fact of any other kind |
| `bumped(S)` | node | `f` is a declaration, and the fact set of `B` holds no declaration with the slug of `f`, or holds one with a smaller revision. The compare is by slug, across the kinds that share the namespace ([vocabulary.md](vocabulary.md) section 9) |
| `declined(S)` | node | `f` is a declaration or a plan with a live decline: one whose recorded hash equals `f`'s current extent hash (declarations) or commitment-set hash (plans) |
| `waiting(P)` | promise | The tag target of the promise is a slug that no declaration in `T` declares, and that some claim promises to declare. A claim is an open plan that the ledger holds an approval of, and whose full form `T` does not hold ([ledger.md](ledger.md) section 10.2). This case means that the work of the claim comes first, not that the promise is broken. The tool reports `waiting-on` for it, and not `dangling` |

### 6.6 Edge predicates

| function | keeps `e ∈ E` iff |
|---|---|
| `suspect(E)` | `rev(e) ≠ ⊥`, `dst(e) ≠ ⊥`, `dst(e)` is a declaration, and `rev(dst(e)) ≠ rev(e)` |
| `dangling(E)` | `dst(e) = ⊥`, and the tag target of `e` is well formed: no declaration has the slug. A tag target that fails its pattern, or an external id whose namespace is undeclared, is not dangling: it is `invalid-target` only ([vocabulary.md](vocabulary.md) section 4) |

### 6.7 Evidence predicates

The evidence predicates partition `kind(verifies)`. Every `verifies`
edge satisfies exactly one of them. The tool tests the predicates in
the order below. The **rung** of an edge is the name of the predicate
it satisfies.

Definitions used: `t = src(e)`. `sites(e)` is the set of code sites
with an attachment target ([packs.md](packs.md) section 6.5) in
`src(in(satisfies, dst(e)))` — a test's own `@satisfies` never
connects the test to itself, a code site with no attachment target
has no code to cover, and a markdown site has no coverage. `tests(t)`
is the set of tests that `t` stands for: `{t}` when `t` is a test, and
the tests that `t` holds, those of nested groups included, when `t` is
a group ([packs.md](packs.md) section 8.4). `runs(u)` is the set of
run facts for `u` at the tree key of `T`.

The **status** of `t` is the worst of these statuses, in the order of
[jsonl.md](jsonl.md) section 6 (`pass`, `skip`, `fail`, `error`): the
status of each run in `runs(t)`; the status of each run in `runs(u)`
for each `u ∈ tests(t)`; `skip` for each `u ∈ tests(t)` with
`runs(u) = ∅`; and `skip` when `tests(t)` and `runs(t)` are both
empty. So a test that did not run counts as skipped, and a skipped
test counts as a test that did not run.

`cov(t, s)` is the set of facts of the coverage of each test for
`(u, s)` with `u ∈ tests(t)`. The coverage of each test exists for `t`
when the evidence set holds a fact of the coverage of each test for
some `u ∈ tests(t)`. `agg(s)` is the fact of the coverage of the whole
run for `s`.

| function | keeps `e ∈ E` iff |
|---|---|
| `wrong-source(E)` | `kind(t) ≠ test`: the source of the `@verifies` edge is not a test, so the edge has the wrong source ([vocabulary.md](vocabulary.md) section 7.2) |
| `never-ran(E)` | the status of `t` is `skip`: a test of `t` did not run or was skipped, and no test of `t` failed |
| `failed(E)` | the status of `t` is `fail` or `error` |
| `unexercised(E)` | The status of `t` is `pass`, and `sites(e) ≠ ∅`, and one of these two holds: the coverage of each test exists for `t` and each fact in `cov(t, s)` has `hit = 0`, for every site `s`; or only the coverage of the whole run exists and `agg(s).hit = 0` for every site `s`. In both cases the whole run executed no line in the sites, so the tests of `t` executed no line in the sites either |
| `unmeasured(E)` | All three of these conditions hold: the status of `t` is `pass`; `sites(e) ≠ ∅`; the coverage of each test does not exist for `t`. And one of these two conditions holds: some `agg(s).hit > 0`; or the evidence set holds no coverage data at all |
| `passing(E)` | the status of `t` is `pass`, and either `sites(e) = ∅` or some fact in some `cov(t, s)` has `hit > 0` |

### 6.8 Rule functions

| function | accepts | denotes |
|---|---|---|
| `obligations(R)` | config | `⋃` over `r ∈ R` of `eval(trigger(r)) - eval(expect(r))`: the obligation subjects of each rule. Rule expressions are evaluated in the same universe. A rule whose trigger or `expect` mentions `obligations` is an error in its rule file ([manifest.md](manifest.md) section 14); no rule depends on another rule through `obligations` |
| `triggered(R)` | config | the rules in `R` whose trigger evaluates to a non-empty set |
| `judged(n)` | — | subjects with a `judgment` evidence fact for rule `n` whose verdict is `pass` and whose recorded hash matches the subject's current extent hash (or commitment-set hash) |

For a rule whose `expect` is `acked(<rule>)`, an ack is live when
`subject ∈ eval(trigger)`. The `expect` expression never evaluates
the trigger a second time, so the rule has no circular definition.

### 6.9 Set operators

`S + T` is union. `S ^ T` is intersection. `S - T` is difference. All
three operate over fact identity.

A user cannot add a new built-in function. Saved definitions (section
7) only combine the functions above. Recursion exists in the three
closures (`deps`, `rdeps`, `paths`) and in the supersession fixpoint
inside `inforce`, and nowhere else. The algebra has no arithmetic, and
no strings other than names and globs.

## 7. Saved definitions

A saved definition is a name, an optional parameter list, and an
expression. Two built-in definitions ship with the tool, and section 9
uses both:

- `untraced(e)` is `kind(req|design) ^ inforce(all) - dst(in($e, all))`:
  the requirements and design items in force that no edge of kind `e`
  points at.
- `unmet(p)` is `promises($p) - met(promises($p))`: the promises of
  `p` that are not met.

A finding class that a repository defines is also a saved definition.
It lives in a rule file ([manifest.md](manifest.md) section 14), and
the front matter of the rule file holds its expression.

A call looks like `untraced(verifies)`, or a bare name for a
definition without parameters. The tool substitutes parameters as text
for `$name` tokens before it parses the expression. It then parses and
category-checks the substituted expression as a whole.

Definitions can reference other definitions. A cycle among definitions
is an error. A definition with tiers is a **finding class**: `check`
evaluates it. A finding class can also say whether its findings are
ackable, give their detail, and name the mechanical fix that repairs a
finding.

## 8. `changed(b)` and diff mode

### 8.1 `changed(b)`

`changed(b)` is the fact set touched by `git diff b` against the
working tree. In this specification, `git diff b` is the diff that git
makes with these options:

- no rename detection: a moved file is a deleted file and an added
  file;
- the Myers algorithm;
- the indent heuristic;
- no context lines;
- no effect of the user's git configuration on these options.

The diff compares the file set of the working tree with the file set
of the base ([manifest.md](manifest.md) section 7.3), by content. The
content of a file on disk is the content that git stores for it: git
applies the clean filter and the end-of-line conversion of the file,
as `git add` does. So a file that differs from its blob only by such a
conversion has no change. A
path of the working tree that the base holds is compared with its blob
in the base, whether git tracks the file or not, and whatever the
index of git holds. A tool can do this with a temporary index in which
git tracks every file of the file set. A path that the base does not
hold is wholly added, and a path that only the base holds is wholly
deleted. So the diff depends only on the files on disk, on the base
commit, and on the conversions that git applies when it stores a file.
[jsonl.md](jsonl.md) section 7 gives the hunks of the diff.

An end-of-line conversion keeps the number of lines of a file. A clean
filter or a working-tree encoding can change it. In such a file, the
line numbers of the hunks are line numbers of the stored content, not
of the file on disk. So the positions that diff mode moves through the
hunks (section 8.2) can be wrong in that file.

The table below defines "touched" for each category:

| category | `f ∈ changed(b)` iff |
|---|---|
| `req` `design` `decision` | the fact set of `b` holds no declaration with the slug of `f`, or holds one of another kind or with another normalized extent hash ([vocabulary.md](vocabulary.md) section 9) |
| `plan` `step` `promise` | the plan's commitment set differs from the one in the fact set of `b`, or the fact is new |
| other located facts | the fact is new, or its line span intersects a hunk's new-side span |
| `hunk` | always |
| `tombstone` | always |
| `edge` | the edge is new, or its line intersects a hunk, or `dst(e)` is a tombstone — a citation of a declaration that vanished is changed even when its bytes are not |
| `evidence` `external` | never |

`b` can be `base` (the `--base` value) or a git revision. To evaluate
`changed(x)` for another revision, the tool needs a second fact set
for `x`. It builds that fact set on demand.

### 8.2 Diff mode

Diff mode is baseline subtraction. `check --diff` reports
`F(T) - F(b)`, where `F(x)` is the finding set of tree `x` and the
subtraction compares finding identities ([jsonl.md](jsonl.md), section
"Identity").

The tool evaluates `F(b)` on the base tree. It reads that tree from
git objects without a checkout. It uses the configuration of the working tree
([manifest.md](manifest.md) section 2.5), the same ledger, and an
**empty evidence set**. So at the base, every finding that comes from an
evidence predicate is `never-ran`. A test that was already
`unexercised` at the base therefore appears as a new finding on the
first change that measures it. This cost happens once for each such
test, and Sinter accepts it.

Before the compare, the tool moves each finding of `F(b)` whose id
holds a position in a file: a line, or a line and a column
([jsonl.md](jsonl.md) section 9). The tool moves each such position
through the hunks of the diff to the position that its line has in the
working tree. A line that no hunk changed keeps its column. Take the
hunks that lie before the line in the base. The line number in the
working tree is the line number in the base, plus the lines that these
hunks added, minus the lines that they removed. A finding on a line
that the diff changed has no position in the working tree, so it
matches no finding of `F(T)`. An id that holds a path compares as it
is. So when a file moves, each of its findings is reported again.

The subtraction removes each finding of `F(T)` whose id is the id of a
finding of `F(b)` after the move. When two findings of `F(T)` have one
id, it removes both.

A finding that exists at the base and still exists in the working tree
is pre-existing; diff mode does not report it. A finding absent at the
base is what the diff introduced. The diff-relative classes —
`unbumped`, `unplanned-change`, `config-changed`, `code-drift`,
`renamed`, `promise-collision` — have `F(b) = ∅` by construction and
appear in both modes. So a check in tree mode also reads the base, and
reports these classes.

## 9. Built-in finding classes

`check` is the union of the finding classes below. In the table, the
definition column holds an algebra expression when the class is
expressible in the algebra. Two components can emit a class directly,
without an algebra expression: the **scanner**, which parses the
files, and the **adjudicator**, which compares the working tree with
the base tree. The mark *engine* means one of these two components
emits the class. A class carries this mark when it concerns malformed
input, or when it compares two trees in a way the algebra does not
model. Engine findings are still ordinary finding facts.

Four global rules apply after evaluation. They are never written into
definitions:

1. Historical facts generate no findings of any class, except
   `config-changed` ([manifest.md](manifest.md) section 13.4).
2. A live `@ack` accepts the ackable findings that it names: the
   findings of a class that column `A` marks, and the findings of a
   class that column `A*` marks when the condition of its row holds.
   The tool judges liveness before it removes the acked findings.
3. The tool evaluates the classes `never-ran`, `failed`,
   `unexercised`, and `unmeasured` only when an evidence set exists
   for the tree. For a tree with no evidence set, the tool reports that
   the tree has no evidence; it must not report these classes as
   failures there. The `rung` field on edges reads `never-ran` either
   way; the tool withholds only the finding.
4. Facts that belong to a closed plan — the plan, its steps, its
   promises — generate no findings. A closed plan is a record, not an
   agreement.

A finding is **ackable** when a live `@ack` can accept it. Column `A`
marks the classes whose findings are all ackable. `A*` means that a
finding of the class is ackable only when the condition that the row
states holds.

A finding can carry a **fix**: a help message, and one alternative or
more ([jsonl.md](jsonl.md) section 8). An alternative is a set of
edits of the text. When a tool makes all the edits of one
alternative, Sinter no longer reports the finding: the edits repair
the finding or, for an inserted `@ack` line, accept it. A fix
is of one of three kinds:

- A fix with more than one alternative needs a choice: a person
  chooses one alternative.
- A fix that inserts an `@ack` line is a judgment: it accepts the
  finding and does not repair it.
- Every other fix is mechanical.

Column `F` marks classes with a mechanical fix. A class that column
`F` does not mark can still give a fix, such as the `@ack` line for a
finding. The `tiers` column gives each class's built-in tier at the
gates `(turn, review, merged)` ([manifest.md](manifest.md) section
11.1). A `—` means that the class takes no tier at that gate. The `mode`
column gives `diff` for the classes that compare the working tree with
the base (section 8.2), and `tree` for every other class.
While `check.warn-only` is `true`, Sinter lowers each `block` of the
column to `warn`, at every gate. `sinter init` writes
`warn-only = true`, so a new repository starts with it. A tier that
`check.tiers` writes still applies ([manifest.md](manifest.md) section
11.3).

| class | subject | definition | mode | A | F | tiers |
|---|---|---|---|---|---|---|
| `parse-error` | file | *engine*: a governed file with a parse failure ([packs.md](packs.md) section 5.2). In a file of a fetched pack, the file's facts are absent. In a markdown file, the facts stay, one finding sits at each error, and the tier of such a finding is `warn` where the class's tier is `block` | tree | · | · | warn, block, block |
| `typo-tag` | line | *engine*: a tag line whose tag word ([vocabulary.md](vocabulary.md) section 3.1) is not in the vocabulary and lies within Damerau–Levenshtein distance 2 of a word of the vocabulary. The pack's foreign vocabulary is exempt. The fix writes the nearest word of the vocabulary in place of the tag word. When two words are equally near, it writes the first in byte order, as [manifest.md](manifest.md) section 4.2 does for keys | tree | · | F | warn, warn, warn |
| `ignored-tag` | line | *engine*: in markdown, a paragraph that a section or a list item holds directly, that is not the first paragraph of that section or list item, that no block quote holds, and whose first line is a tag line. The scanner reads no tag in it ([packs.md](packs.md) section 7.2) | tree | · | · | warn, warn, warn |
| `invalid-target` | tag | *engine*: a tag target that fails its pattern: a slug that fails the slug pattern, an external id whose namespace is undeclared or whose id fails the pattern of its namespace, a tag target of `@plan` that fails the rules of the full form, or a tag target of `@delivered` that is not a mark hash, or a `@delivered` tag with no tag target ([vocabulary.md](vocabulary.md) sections 4.1, 4.2, 4.3, and 4.4). Such a tag target is never `dangling` | tree | · | · | block, block, block |
| `duplicate` | tag or line | *engine*: two slugs in one namespace that are equal, or that differ only in case ([vocabulary.md](vocabulary.md) section 4.1): two declarations; two open plans; or two steps of one plan. Two plans of any state with one full form ([vocabulary.md](vocabulary.md) section 4.3) are also a group. Order the facts of one such group by the byte order of their paths, and then by their lines. Each fact after the first gives one finding. Its subject is the tag of that fact or, for a step, the line of the step's heading ([jsonl.md](jsonl.md) section 9). A plan that both rules of plans report gives one finding, by the rule of the full form. The `@delivered` tags of the tag block of one step are also a group, in the order of their lines: the first is the mark of the step, and each later one gives one finding, whose subject is its tag ([vocabulary.md](vocabulary.md) section 10.8). The `detail` names the rule that applies | tree | · | · | block, block, block |
| `scope-outside-plan` | step | *engine*: a step whose `@scope` is not contained in its plan's `@scope`. The tool decides containment on the plain globs ([manifest.md](manifest.md) section 7.2), by the rule of glob containment of [ledger.md](ledger.md) section 11: each plain glob of the step must be contained in a plain glob of the plan. A `!` glob of the step only narrows the step's scope, so it never breaks containment | tree | · | · | block, block, — |
| `step-without-promises` | step | *engine*: a step without promises of an open plan, while `proof.step` is `"promises"` ([manifest.md](manifest.md) section 10.4). The finding sits at the heading of the step. It has no fix | tree | · | · | block, block, block |
| `stale-mark` | step | *engine*: a step of an open plan whose mark does not count: its mark hash is not the first six hex digits of the current step hash ([vocabulary.md](vocabulary.md) section 10.8). A mark whose tag target is not a mark hash is `invalid-target` only. The finding sits at the mark. The fix writes the first six hex digits of the step hash in place of the mark hash | tree | · | F | block, block, block |
| `misplaced-plan` | tag | *engine*: a `@plan` tag outside the first tag block of a file under `.plans/`, or a `@delivered` tag outside the tag block of a step. A `@plan` outside `.plans/**` and a `@plan` in a later block of a file under `.plans/` are misplaced ([vocabulary.md](vocabulary.md) section 10.1). A `@delivered` tag in a file that is not a plan file, in the first tag block of a plan file, or in a block of a step other than its tag block is misplaced ([vocabulary.md](vocabulary.md) section 10.8) | tree | · | · | block, block, block |
| `missing-plan-id` | plan | *engine*: a plan whose `@plan` tag has no plan id ([vocabulary.md](vocabulary.md) section 4.3). The fix inserts `@` and a plan id at the end of the tag target. That plan id is the first six hex digits of the SHA-256 of three parts, as UTF-8 bytes: the object id of the base commit in lowercase hex (the field `base` of the `index` record, [jsonl.md](jsonl.md) section 10), one LF, and the path of the plan file, relative to the repository root | tree | · | F | block, block, block |
| `unpinned` | edge | *engine*: a `satisfies`, `verifies`, `refines`, or `supersedes` edge without a revision | tree | · | F | block, block, block |
| `dangling` | edge | `dangling(kind(edge))`, minus edges whose tag target a claim promises to declare — those surface as `waiting-on` instead — and minus the edges that `renamed` reports (*engine* performs these subtractions). When the tag target differs from a declared slug only in case, the fix of the finding writes the declared spelling in place of the tag target | tree | · | · | block, block, block |
| `renamed` | edge | *engine*: a dangling edge whose slug has the tombstone of a declaration in `B`, when both of these conditions hold. First: exactly one tombstone of a declaration and exactly one new declaration have the extent hash of that tombstone. A new declaration is a declaration of `T` that the fact set of `B` does not hold. Second: the new declaration has the kind of the tombstone. When a condition fails, the edge is only `dangling`. `renamed` is reported in place of `dangling` on the edge. The fix writes the slug of the new declaration in place of the tag target. When the edge carries a revision, the fix also writes the revision of the new declaration in place of that revision | diff | · | F | block, block, block |
| `suspect` | edge | `suspect(kind(edge))` | tree | · | F | block, block, block |
| `unbumped` | node | `kind(req\|design\|decision) ^ changed(base) - bumped(all)` | diff | · | F | block, block, block |
| `cycle` | node | *engine*: a cycle of `supersedes` and `refines` edges. Two facts belong to one cycle when each reaches the other along these edges. A fact with such an edge to itself is a cycle by itself. Each cycle gives one finding. Its subject is the member of the cycle with the smallest id in byte order, and its `detail` names the other members, in the byte order of their ids | tree | · | · | block, block, block |
| `code-drift` | site | *engine*: the `ch` of a code site changed since the base while the site's comment hash did not. This class is not ackable: it is diff-relative, so an ack for it would become void when the branch merges | diff | · | · | warn, warn, — |
| `declined` | node | `declined(kind(req\|design\|decision\|plan))`; the detail is the reason | tree | · | · | warn, block, — |
| `unapproved-req` | edge | `in(satisfies\|verifies, kind(req) - approved(all))`. A kind that does not need approval counts as approved, so in a repository where `proof.req` is not `"approval"` this class reports nothing | tree | · | · | block, block, block |
| `unapproved-design` | edge | `in(satisfies\|verifies, kind(design) - approved(all))` | tree | · | · | warn, warn, warn |
| `awaiting-approval` | node | `kind(req\|design\|decision) ^ inforce(all) - approved(all)` | tree | · | · | —, warn, warn |
| `unapproved-plan` | plan | `kind(plan) ^ inforce(all) - approved(all)`. The engine writes the difference between the current commitment set and the approved commitment set into the finding's `detail` field | tree | · | · | warn, block, — |
| `retired` | edge | `in(cites, all) - in(cites, inforce(all))`: the `cites` edges whose tag target resolves to a fact that is not in force — a rule's origin edge included. When the cited fact has successors ([vocabulary.md](vocabulary.md) section 8.2), the `detail` names the cited fact and then its successors, in the byte order of their ids, for example `decision:a is superseded by decision:b, decision:c`. The fix then cites a successor in place of the cited fact: it writes the slug of the successor in place of the tag target and, when the edge carries a revision, the current revision of the successor in place of that revision. With several successors, the fix has one alternative for each, in the same order. Ackable only when the cited fact has no successor; the fix then inserts the `@ack` line for the finding after the last tag line of the block | tree | A* | · | warn, block, block |
| `stale-ack` | ack | *engine*: an `@ack` whose hash no longer matches its block, or whose tag target names neither an ackable finding nor an obligation of a rule in that block ([vocabulary.md](vocabulary.md) section 7.4) | tree | · | F | block, block, block |
| `wrong-source` | edge | `wrong-source(kind(verifies)) + (kind(refines\|supersedes) - out(refines\|supersedes, kind(req\|design\|decision\|rule)))`: a citation whose kind needs a certain source and that does not have one ([vocabulary.md](vocabulary.md) section 7.2). A `@verifies` needs a test; a `@refines` or a `@supersedes` needs an enclosing declaration | tree | · | · | block, block, block |
| `never-ran` | edge | `never-ran(kind(verifies)) ^ scope(inforce(kind(plan)))` at `turn`; `never-ran(kind(verifies))` at `review` and `merged` | tree | · | · | warn, block, block |
| `failed` | edge | `failed(kind(verifies))` | tree | · | · | block, block, block |
| `unexercised` | edge | `unexercised(kind(verifies))` | tree | A | · | warn, block, block |
| `unmeasured` | edge | `unmeasured(kind(verifies))` | tree | · | · | off, warn, warn |
| `ambiguous-result` | node | *engine*: a test or a group that a test result binds to, when the same result also binds to a test or a group of another file or another name path ([packs.md](packs.md) section 9.2) | tree | · | · | warn, block, block |
| `untraced` | node | `untraced(verifies) + untraced(satisfies)` — incompleteness | tree | · | · | —, warn, warn |
| `unmet-promise` | promise | `unmet(active)` where `unmet(p) = promises($p) - met(promises($p))` — incompleteness | tree | · | · | —, off, — |
| `promise-out-of-scope` | promise | *engine*: a promise met only by facts outside its step's scope | tree | · | · | warn, warn, — |
| `unverified-promise` | promise | *engine*: a promised `req` or `design` with no promised `verifies` of it in the same plan | tree | · | · | warn, warn, — |
| `promise-collision` | promise | *engine*: a promised declaration whose slug a claim promises to declare, or a new promised declaration whose slug exists in the fact set of `B`. A promise is new when the fact set of `B` holds no promise of the same plan with the same step, word, and target. A plan of `B` and a plan of `T` are the same plan when their full forms are equal ([vocabulary.md](vocabulary.md) section 4.3), or when the plan of `B` has no plan id and the two have the same slug and the same path. So a promise that `B` also holds does not collide, for example a promise that an earlier merge of the same plan delivered, and a plan id added to a plan makes none of its promises new. A tool that does not read the ledger has no claims, so it reports only the second case | diff | · | · | block, block, — |
| `scope-overlap` | step | *engine*: two steps of one plan with intersecting scopes and intersecting promise sets. Two scopes intersect when a plain glob of one contains a plain glob of the other, or is contained in it, by the rule of glob containment of [ledger.md](ledger.md) section 11 | tree | · | · | warn, warn, — |
| `waiting-on` | promise | `waiting(promises(kind(plan)))` — reported in place of `dangling`, with the claim and step named | tree | · | · | off, warn, — |
| `branch-overlap` | step | *engine*: a step's scope intersects the scope of a claim | tree | · | · | warn, warn, — |
| `unplanned-change` | hunk | `kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - scope(triggered(kind(rule))) - exempt`. The engine also exempts each hunk that is a mechanical repair (section 9.1). The detail is `no step of an open plan, no rule, and no exempt path covers <path>`. The finding has no fix | diff | · | · | block, block, — |
| `unmet-rule` | any | `obligations(kind(rule))`, one finding per `(rule, subject)`; ackable only when the rule's `expect` is `acked`; a rule's own `tiers` overrides the class's `tiers` | tree | A* | · | warn, block, block |
| `config-changed` | config or tombstone | *engine*: a change to the manifest between the base tree and the working tree, one finding for each change ([manifest.md](manifest.md) section 13.4). `check.tiers` cannot set its tier, and nothing turns it off; it always reports and never blocks | diff | · | · | warn, warn, warn |
| `merged-incomplete` | step | *engine*: a step of an open plan with some of its promises met and some not: a step merged in part. A promise counts as met by the rule of section 9.2. The finding sits at the heading of the step, and its related places are the promises that are not met. It has no fix | tree | · | · | —, block, block |
| `ledger-broken` | ledger | *engine*: ledger verification fails | tree | · | · | —, —, block |
| `pack-mismatch` | pack | *engine*: the hash of a fetched pack in the cache does not match the hash that the lock file `sinter.lock` fixes for it. The built-in pack `markdown` is not in the lock file. The class takes no tier at any gate: the tool stops with exit code 3 | tree | · | · | — |

`untraced`, `unmet-promise`, and `awaiting-approval` are the
incompleteness classes. They take no tier at the gate `turn`, so a
check at that gate never reports them. A manifest cannot give them a
tier there ([manifest.md](manifest.md) section 11.2). `sinter status`
reports them. `status --done` exits 0 when the steps that the branch
delivers ([vocabulary.md](vocabulary.md) section 10.7) are done. The
job that closes plans checks the completion condition of
[ledger.md](ledger.md) section 8. Every other class is a violation, or
a signal about the health of the repository's checking machinery.

### 9.1 Mechanical repairs

A hunk is a **mechanical repair** when every change in it is a change
that the edits of a fix of Sinter make. `unplanned-change` does not
report such a hunk. These are the changes:

- a re-pin: a new revision on a citation (the fix of `suspect`);
- an `@ack` line added or removed (the fix of `stale-ack`, and the
  `@ack` line that the edits of the fix of an ackable finding insert);
- a revision added to a citation that has none (the fix of
  `unpinned`);
- a higher revision on a declaration (the fix of `unbumped`);
- a change of case of the tag target of a `dangling` edge to the
  declared spelling (the fix of `dangling`);
- the new tag target and revision of a citation that the edits of the
  fix of `renamed` write;
- the citation of a successor in place of a citation of a retired
  declaration (the fix of `retired`);
- the corrected tag word of a `typo-tag` line (the fix of `typo-tag`);
- a plan id added to the tag target of a `@plan` line (the fix of
  `missing-plan-id`).

When Sinter adds a fix, the change that its edits make joins this
list. A fix that edits only plan files, such as the fix of
`stale-mark`, need not join the list: each plan file is an exempt
path, so a hunk of a plan file is never an unplanned change.

A hunk that holds no line is not a mechanical repair. Examples are
the hunk of a binary file and the hunk of an added empty file.

The tool decides by tags, not by text. It reads the tags of the
removed lines in the base tree, and the tags of the added lines in the
working tree. Each removed line and each added line of the hunk must
be a tag line. Each removed or added `@ack` line is one change. The
other removed lines and added lines must be equal in number. The first
removed line pairs with the first added line, and so on. The two tags
of each pair must differ by exactly one of the changes above. The
added tag must be the tag that the edits of the fix of that change
write, by the facts of
the working tree and, for `renamed`, of the base tree. For example, a
re-pin and a revision added to a citation must write the current
revision of the target, and the retarget of `renamed` must name the
declaration that has the extent hash of the tombstone. Two exceptions:
a bump of a declaration can write any higher revision, and an added
plan id can be any six lowercase hex digits. The column of
the `@` and the rest of each line of the pair, the inline description,
must be equal.

### 9.2 Promises without evidence

The class `merged-incomplete` reads a promised `@verifies` in one more
way. When no evidence set exists for the tree (global rule 3), a
promised `@verifies` counts as met for the class when a `verifies` edge
with its tag target exists inside the effective scope of the step, its
source is a test, its tag target resolves, and it is not suspect. A
`verifies` edge whose source is not a test is at rung `wrong-source`
(section 6.7), and it never counts. When an evidence set exists, the
rung decides, as [vocabulary.md](vocabulary.md) section 10.5 says. The
rule applies to this class alone: `done()` and the completion
condition of [ledger.md](ledger.md) section 8 read every promise as
section 10.5 says.

## 10. Evaluation, ordering, and errors

- Evaluation is bottom-up over the parse tree. The tool answers
  selectors from per-kind lookup structures. It answers traversals
  from adjacency maps, which it builds once per scan. It computes
  fixpoints with a worklist. It expands a saved definition once per
  invocation site.
- Results print in the order `(kind, path, line, col, id)`. Unlocated
  facts come after located ones, ordered by `id`. Reordering never
  changes the set.
- The static errors are a category mismatch, an unknown function, a
  wrong arity, an unknown saved definition, and a wrong parameter
  count. The tool reports them before evaluation, and names the
  offending subexpression.
- A name selector that matches nothing is not an error. It denotes
  `∅`, because that is what `req(auth-lockout)` should mean on a
  branch where nobody declared `auth-lockout` yet.
- When git cannot resolve the revision `x`, `changed(x)` is an
  **environment error**, not a static error: the tool cannot read what
  it needs from git.

## 11. Example

This example is informative. It uses a plan whose implementation step
is complete and whose tests do not exist yet:

```
$ sinter query 'promises(active) - met(promises(active))'
.plans/auth-lockout.md:19:1: promise auth-lockout@3f2a9c/verify-against-the-reqs verifies auth-lockout
.plans/auth-lockout.md:20:1: promise auth-lockout@3f2a9c/verify-against-the-reqs verifies lockout-notify

$ sinter query 'untraced(verifies)'
docs/auth.md:12:1: req auth-lockout v2
docs/auth.md:31:1: req lockout-notify v1
```

The first query lists the promises that are not met. The second query
lists the in-force requirements that no test verifies.
