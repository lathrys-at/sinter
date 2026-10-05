<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: query algebra

Status: draft. The five specifications share one version; see [docs/versioning.md](../docs/versioning.md).

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
network.

## 3. Kinds and categories

Every kind belongs to exactly one **category**. `kind(x)` accepts a
kind or a category.

| category | kinds | located? |
|---|---|---|
| `node` | `req` `design` `decision` `plan` `step` `test` `site` | yes |
| `edge` | `satisfies` `verifies` `refines` `cites` `supersedes` | yes |
| `ref` | `ref` | no |
| `promise` | `promise` | yes |
| `evidence` | `run` `cov` `judgment` | no |
| `config` | `rule` `gate` `setting` | see below |
| `ack` | `ack` | yes |
| `ledger` | `lease` `decline` | no |
| `hunk` | `hunk` | yes; diff mode only |
| `tombstone` | `tombstone` | yes (base coordinates) |
| `finding` | `finding` | yes (its subject's location) |

Notes on individual kinds:

- A `site` is an anonymous source: a source with no name. It is a code
  site, or a markdown section that holds a citation outside every
  declaration's extent ([vocabulary.md](vocabulary.md) section 7.2). A
  code site carries the code hash `ch`.
- A `test` is named by the language pack's ID strategy.
- A `rule` is located in its rule file ([manifest.md](manifest.md)
  section 15).
- A `setting` is one value of the manifest, and a `gate` is the tier
  that applies to one pair of a gate and a finding class
  ([manifest.md](manifest.md) section 14). A setting fact or a gate
  fact that the manifest writes is located in the manifest. A default,
  a built-in member, and every fact of a manifest outside the
  repository are unlocated.
- An edge's `src` is a node or a rule. An edge's `dst` is a node, a
  ref, or unresolved. A rule's origin is a `cites` edge whose `src` is
  the rule.
- A `hunk` is one hunk of `git diff B`, in new-side coordinates.
- A `tombstone` is a fact that is present in the fact set of `B` and
  absent from the fact set of `T`. It carries the old id, kind, and
  extent hash.

"Located" facts carry `path`, `line`, `col`, `eline`, and `ecol`. The
functions `path(…)`, `scope(…)`, `historical`, `ambient`, `shared`, and
`acked(…)` return located facts only.

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
name     := slugpat | slugpat '/' slugpat | testpat
slugpat  := [A-Za-z0-9*]+ ( [-_.] [A-Za-z0-9*]+ )*
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
  4.1). A `kinds` argument can be a category name.
- **Names are resolved after substitution.** A saved definition's
  parameters are substituted as text before the expression is parsed
  (section 7). A parameter can therefore stand for an expression, a
  kind list, a name, or a glob.
- **Keywords.** `all`, `active`, `historical`, `ambient`, `shared`,
  and `base` are reserved as bare words. A saved definition must not shadow a
  built-in name.

## 5. Categories as types

The tool assigns each expression a **category set** statically, before
evaluation:

- `all` → every category. `kind(K)` → the categories of the kinds in
  `K`. A name selector → its kind's category. `path`, `historical`,
  `ambient`, `shared`, `acked` → every located category. `changed` → every
  category, tombstones and hunks included. `active` → `{node}`.
  `findings` → `{finding}`.
- `out`, `in` → `{edge}`. `src`, `dst`, `deps`, `rdeps`, `paths` →
  `{node, ref, config}` (the `src` of a rule's origin edge is a rule).
  `subject` → every category a finding can be about. `scope` → the
  located categories plus `hunk`; its argument also accepts `lease`.
  `promises`, `met` → `{promise}`. `done` → `{node}`. A predicate →
  the category set of its argument, intersected with what it accepts.
  `owed`, `judged` → every category. `triggered` → `{config}`.
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
| `req(n)` `design(n)` `decision(n)` `plan(n)` `rule(n)` | facts of that kind whose slug or name matches `n` |
| `step(p/s)` | steps whose plan slug matches `p` and step slug matches `s` |
| `test(n)` | test nodes whose pack-assigned ID matches `n` |
| `ref(ns/id)` | ref facts matching |
| `path(g)` | located facts whose `path` matches `g` |
| `changed(b)` | see section 8; `b` is `base` or a revision |
| `active` | the active plan and, when the session declares one, the active step; only open plans are candidates; `∅` when no plan is active |
| `historical` | located facts under a historical path: a path of `check.historical`, its built-in member included ([manifest.md](manifest.md) section 9.4) |
| `ambient` | located facts under an ambient path: a path of `plan.ambient`, its built-in members included (each plan file, the manifest, and the lock file `sinter.lock`; [manifest.md](manifest.md) section 10.2) |
| `shared` | located facts under a shared path: a path of `plan.shared`, which every step of every plan can change ([manifest.md](manifest.md) section 10.3) |
| `acked(t)` | the located facts `f` whose tag-bearing block carries a live `@ack` with the tag target `t`, where `t` applies to `f`. The tag target `t` applies to `f` when both of these conditions hold: the class name or rule name in `t` matches, and the ack's subject, when the ack gives one, equals `f` in the form that [vocabulary.md](vocabulary.md) section 7.4 gives |
| `findings(C)` | finding facts whose class is in `C` |

### 6.2 Traversal (one hop, typed)

| function | accepts | denotes |
|---|---|---|
| `out(K, S)` | `S`: node, config | edges `e` with `kind(e) ∈ K` and `src(e) ∈ S` |
| `in(K, S)` | `S`: node, ref | edges `e` with `kind(e) ∈ K` and `dst(e) ∈ S` |
| `src(E)` | edge | the sources of the edges in `E` |
| `dst(E)` | edge | the facts that the tag targets of the edges in `E` resolve to; a dangling edge contributes nothing |
| `subject(F)` | finding | the subjects of the findings in `F` |

### 6.3 Closures

Closures are least fixpoints. The tool ignores dangling edges. It
follows suspect edges, because a stale citation is still a citation.

| function | accepts | denotes |
|---|---|---|
| `deps(K, S)` | node, config | the least `X ⊇ S` with `dst(out(K, X)) ⊆ X` |
| `rdeps(K, S)` | node, ref | the least `X ⊇ S` with `src(in(K, X)) ⊆ X` |
| `paths(S, T)` | node, ref, config | `deps(edge, S) ^ rdeps(edge, T)`: every node on some path from `S` to `T` over any edge kind |

### 6.4 Plan functions

| function | accepts | denotes |
|---|---|---|
| `scope(S)` | plan, step, rule, lease | located facts and hunks whose `path` matches the effective scope of some member of `S`. A step's effective scope is the step's own `@scope` when the step declares one; otherwise it is the plan's scope. A plan's effective scope is the union of the effective scopes of its steps. A rule's scope is its `scope` field. `∅` when `S` holds no scope-bearing fact |
| `promises(S)` | plan, step | promise facts whose step or plan is in `S` |
| `met(P)` | promise | the promises in `P` that are discharged, as defined in [vocabulary.md](vocabulary.md) section 10.5 |
| `done(S)` | plan, step | A step is in the result when both conditions hold. First: all of the step's promises are met; for a step with no promises, the first condition is instead that the step's scope intersects `changed(base)`. Second: every `verifies` edge in the step's scope is at rung `passing`, or at rung `unattributed` when `evidence.coverage-attribution` is `"optional"` ([manifest.md](manifest.md) section 12). A plan is in the result when all of its steps are in the result and the second condition holds for the plan's scope |

### 6.5 Status predicates

A predicate filters its argument: `pred(S) ⊆ S`.

| function | accepts | keeps `f ∈ S` iff |
|---|---|---|
| `inforce(S)` | any | For a declaration: `f` carries no status tag and no live `@supersedes` edge points at `f` ([vocabulary.md](vocabulary.md) section 8.1). The tool computes edge liveness as a fixpoint over the chains of `@supersedes` edges. On a cycle, the tool counts every member of the cycle as in force and reports the `cycle` finding. For a plan, for its steps, and for its promises: the plan is open — the ledger holds no `discharged` entry and no `abandoned` entry for it. The predicate keeps every fact of every other kind |
| `approved(S)` | any | A kind needs approval when `ledger.approval-required` lists it ([manifest.md](manifest.md) section 11.1). The predicate keeps `f` when any one of these conditions holds: `f` is a declaration of a kind that needs approval, and the ledger holds a stamp for `f`'s `(slug, rev, xh)`; `f` is a declaration of a kind that does not need approval; `f` is a plan, the kind `plan` needs approval, and `f`'s current commitment set is approved against the plan's latest stamped set ([ledger.md](ledger.md) section 11); `f` is a plan, and the kind `plan` does not need approval; `f` is a step of an approved plan; `f` is a fact of any other kind |
| `bumped(S)` | node | `f` is a declaration absent from the fact set of `B`, or present there with a smaller revision |
| `declined(S)` | node | `f` is a declaration or a plan with a live decline: one whose recorded hash equals `f`'s current extent hash (declarations) or commitment-set hash (plans) |
| `blocked(P)` | promise | The tag target of the promise is a slug that no declaration in `T` declares, and that some lease promises to declare. This case means that the current branch and the lease's branch are ordered, not that the promise is broken. The tool reports `blocked-on` for it, and not `dangling` |

### 6.6 Edge predicates

| function | keeps `e ∈ E` iff |
|---|---|
| `suspect(E)` | `rev(e) ≠ ⊥`, `dst(e) ≠ ⊥`, `dst(e)` is a declaration, and `rev(dst(e)) ≠ rev(e)` |
| `dangling(E)` | `dst(e) = ⊥`: no declaration has the slug, or the ref's namespace is undeclared, or its id fails the pattern |

### 6.7 Evidence predicates

The evidence predicates partition `kind(verifies)`. Every `verifies`
edge satisfies exactly one of them. The tool tests the predicates in
the order below. The **rung** of an edge is the name of the predicate
it satisfies.

Definitions used: `t = src(e)`. `sites(e)` is the set of code sites
in `src(in(satisfies, dst(e)))` — a test's own `@satisfies` never
connects the test to itself, and a markdown site has no coverage.
`runs(t)` is the set of run facts for `t` at the tree key of `T`.
`cov(t, s)` is the attributed coverage fact for `(t, s)`. `agg(s)` is
the aggregate coverage fact for `s`.

| function | keeps `e ∈ E` iff |
|---|---|
| `orphan(E)` | `kind(t) ≠ test`: the source of the `@verifies` edge is not a test, so the edge is an orphan ([vocabulary.md](vocabulary.md) section 7.2) |
| `neverran(E)` | `runs(t) = ∅` |
| `failed(E)` | some run in `runs(t)` has status `fail`, `error`, or `skip`. A skipped test does not discharge its promise, so `skip` counts as failed here |
| `disconnected(E)` | Every run passes, and `sites(e) ≠ ∅`, and one of these two holds: attributed coverage for `t` exists and `cov(t, s).hit = 0` for every site `s`; or only aggregate coverage exists and `agg(s).hit = 0` for every site `s`. In both cases the whole run executed no line in the sites, so the test `t` executed no line in the sites either |
| `unattributed(E)` | All three of these conditions hold: every run passes; `sites(e) ≠ ∅`; no attributed coverage for `t` exists. And one of these two conditions holds: some `agg(s).hit > 0`; or the evidence set holds no coverage data at all |
| `passing(E)` | every run passes, and either `sites(e) = ∅` or some `cov(t, s).hit > 0` |

### 6.8 Rule functions

| function | accepts | denotes |
|---|---|---|
| `owed(R)` | config | `⋃` over `r ∈ R` of `eval(trigger(r)) - eval(discharge(r))`: the obligation subjects of each rule. Rule expressions are evaluated in the same universe. A rule whose trigger or discharge mentions `owed` is an error in its rule file ([manifest.md](manifest.md) section 15); no rule depends on another rule through `owed` |
| `triggered(R)` | config | the rules in `R` whose trigger evaluates to a non-empty set |
| `judged(n)` | — | subjects with a `judgment` evidence fact for rule `n` whose verdict is `pass` and whose recorded hash matches the subject's current extent hash (or commitment-set hash) |

For a rule whose discharge is `acked(<rule>)`, an ack is live when
`subject ∈ eval(trigger)`. The discharge expression never evaluates
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

- `uncovered(e)` is `kind(req|design) ^ inforce(all) - dst(in($e, all))`:
  the requirements and design items in force that no edge of kind `e`
  points at.
- `unmet(p)` is `promises($p) - met(promises($p))`: the promises of
  `p` that are not met.

A finding class that a repository defines is also a saved definition.
It lives in a rule file ([manifest.md](manifest.md) section 15), and
the front matter of the rule file holds its expression.

A call looks like `uncovered(verifies)`, or a bare name for a
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
working tree. Untracked files count as wholly added. The table below
defines "touched" for each category:

| category | `f ∈ changed(b)` iff |
|---|---|
| `req` `design` `decision` | `f` is absent from the fact set of `b`, or its normalized extent hash differs between `b` and `T` |
| `plan` `step` `promise` | the plan's commitment set differs from the one in the fact set of `b`, or the fact is new |
| other located facts | the fact is new, or its line span intersects a hunk's new-side span |
| `hunk` | always |
| `tombstone` | always |
| `edge` | the edge is new, or its line intersects a hunk, or `dst(e)` is a tombstone — a citation of a declaration that vanished is changed even when its bytes are not |
| `evidence` `ref` | never |

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
`disconnected` at the base therefore appears as a new finding on the
first change that measures it. This cost happens once for each such
test, and Sinter accepts it.

A finding that exists at the base and still exists in the working tree
is pre-existing; diff mode does not report it. A finding absent at the
base is what the diff introduced. The diff-relative classes —
`rev-owed`, `unmapped-work`, `config-changed`, `code-drift`, `renamed` —
have `F(b) = ∅` by construction and appear in both modes.

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

1. Historical facts generate no findings of any class.
2. A live `@ack` discharges findings of ackable classes. The tool
   judges liveness before it removes the acked findings.
3. The tool evaluates the classes `never-ran`, `failed`,
   `disconnected`, and `unattributed` only when an evidence set exists
   for the tree. The tool reports an unmeasured tree as unmeasured; it
   must not report these classes as failures there. The `rung` field
   on edges reads `never-ran` either way; the tool withholds only the
   finding.
4. Facts that belong to a closed plan — the plan, its steps, its
   promises — generate no findings. A closed plan is a record, not an
   agreement.

Column `A` marks ackable classes; `A*` means ackable only under the
condition the row states. Column `F` marks classes with a mechanical
fix. The `tiers` column gives each class's built-in tier at the gates
`(turn, merge, target)` ([manifest.md](manifest.md) section 9.1). A
`—` means that the class takes no tier at that gate. The **rollout
cap** (`check.rollout-cap`) lowers each `block` of the column to
`warn`, at every gate. `sinter init` writes the cap, so a new
repository starts under it. A tier that `check.tiers` writes passes
the cap ([manifest.md](manifest.md) section 9.3).

| class | subject | definition | mode | A | F | tiers |
|---|---|---|---|---|---|---|
| `parse-error` | file | *engine*: a governed file its pack cannot parse; the file's facts are absent | tree | · | · | warn, block, block |
| `typo-tag` | line | *engine*: an unknown `@word` within Damerau–Levenshtein distance 2 of the vocabulary. The pack's foreign vocabulary is exempt | tree | · | F | warn, warn, warn |
| `bad-target` | tag | *engine*: a slug or ref that fails its pattern, or an undeclared namespace | tree | · | · | block, block, block |
| `duplicate` | node | *engine*: two slugs in one namespace that are equal, or that differ only in case ([vocabulary.md](vocabulary.md) section 4.1): two declarations; two plans (closed plans included); or two steps of one plan | tree | · | · | block, block, block |
| `bad-scope` | step | *engine*: a step whose `@scope` is not contained in its plan's | tree | · | · | block, block, — |
| `misplaced-plan` | node | *engine*: a `@plan` declaration outside `.plans/**` | tree | · | · | block, block, block |
| `unpinned` | edge | *engine*: a `satisfies`, `verifies`, `refines`, or `supersedes` edge without a revision | tree | · | F | block, block, block |
| `dangling` | edge | `dangling(kind(edge))`, minus edges whose tag target a lease promises to declare — those surface as `blocked-on` instead (*engine* performs this subtraction). When the tag target differs from a declared slug only in case, the `fix` of the finding names the declared spelling | tree | · | · | block, block, block |
| `renamed` | edge | *engine*: dangling edges whose slug has a tombstone in `B` and a new declaration in `T` with an equal extent hash | diff | · | F | block, block, block |
| `suspect` | edge | `suspect(kind(edge))` | tree | · | F | block, block, block |
| `rev-owed` | node | `kind(req\|design\|decision) ^ changed(base) - bumped(all)` | diff | · | F | block, block, block |
| `cycle` | node | *engine*: a cycle in `supersedes` or `refines` | tree | · | · | block, block, block |
| `code-drift` | site | *engine*: the `ch` of a code site changed since the base while the site's comment hash did not. This class is not ackable: it is diff-relative, so an ack for it would become void when the branch merges | diff | · | · | warn, warn, — |
| `declined` | node | `declined(kind(req\|design\|decision\|plan))`; the detail is the reason | tree | · | · | warn, block, — |
| `unratified-req` | edge | `in(satisfies\|verifies, kind(req) - approved(all))`. A kind that does not need approval counts as approved, so in a repository where `ledger.approval-required` does not list `req` this class reports nothing | tree | · | · | block, block, block |
| `unratified-design` | edge | `in(satisfies\|verifies, kind(design) - approved(all))` | tree | · | · | warn, warn, warn |
| `unstamped` | node | `kind(req\|design\|decision) ^ inforce(all) - approved(all)` | tree | · | · | off, warn, warn |
| `amendment` | plan | `kind(plan) ^ inforce(all) - approved(all)`. The engine writes the difference between the current commitment set and the stamped commitment set into the finding's `detail` field | tree | · | · | warn, block, — |
| `disendorsed` | edge | `kind(cites) - dangling(all) - in(cites, inforce(all))` — a rule's origin edge included | tree | A | · | warn, block, block |
| `stale-ack` | ack | *engine*: an `@ack` whose hash no longer matches its block, or whose tag target names nothing in that block | tree | · | F | block, block, block |
| `orphan` | edge | `orphan(kind(verifies)) + (kind(refines\|supersedes) - out(refines\|supersedes, kind(req\|design\|decision\|rule)))`: a citation whose kind needs a certain source and that does not have one ([vocabulary.md](vocabulary.md) section 7.2). A `@verifies` needs a test; a `@refines` or a `@supersedes` needs an enclosing declaration | tree | · | · | block, block, block |
| `never-ran` | edge | `neverran(kind(verifies)) ^ scope(inforce(kind(plan)))` at `turn`; `neverran(kind(verifies))` at `merge` and `target` | tree | · | · | warn, block, block |
| `failed` | edge | `failed(kind(verifies))` | tree | · | · | block, block, block |
| `disconnected` | edge | `disconnected(kind(verifies))` | tree | A | · | warn, block, block |
| `unattributed` | edge | `unattributed(kind(verifies))` | tree | · | · | off, warn, warn |
| `uncovered` | node | `uncovered(verifies) + uncovered(satisfies)` — incompleteness; never blocks a turn end | tree | · | · | off, warn, warn |
| `unmet` | promise | `unmet(active)` where `unmet(p) = promises($p) - met(promises($p))` — incompleteness; enforced only by `status --done` | tree | · | · | off, off, — |
| `promise-out-of-scope` | promise | *engine*: a promise met only by residue outside its step's scope | tree | · | · | warn, warn, — |
| `unverified-promise` | promise | *engine*: a promised `req` or `design` with no promised `verifies` of it in the same plan | tree | · | · | warn, warn, — |
| `promise-collision` | promise | *engine*: a promised declaration whose slug exists in the fact set of `B` or is promised by a lease | tree | · | · | block, block, — |
| `scope-overlap` | step | *engine*: two steps of one plan with intersecting scopes and intersecting promise sets | tree | · | · | warn, warn, — |
| `blocked-on` | promise | `blocked(promises(kind(plan)))` — reported in place of `dangling`, with the lease and step named | tree | · | · | off, warn, — |
| `lease-overlap` | step | *engine*: a step's scope intersects the scope of another branch's lease | tree | · | · | warn, warn, — |
| `unmapped-work` | hunk | `kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - scope(triggered(kind(rule))) - ambient - shared`. The engine also exempts hunks that are wholly mechanical repairs — tag-line re-pins and `@ack` insertions or deletions | diff | · | · | block, block, — |
| `rule-owed` | any | `owed(kind(rule))`, one finding per `(rule, subject)`; ackable only when the rule's discharge is `acked`; a rule's own `tiers` overrides the class's `tiers` | tree | A* | · | warn, block, block |
| `config-changed` | config or tombstone | *engine*: a change to the manifest between the base tree and the working tree, one finding for each change ([manifest.md](manifest.md) section 14.4). `check.tiers` cannot set its tier, and nothing turns it off; it always reports and never blocks | diff | · | · | warn, warn, warn |
| `undischarged-plan` | plan | *engine*: an open plan on the target branch that fails the discharge condition ([ledger.md](ledger.md) section 8): a person merged it before its work was complete | tree | · | · | —, —, block |
| `ledger-broken` | ledger | *engine*: ledger verification fails | tree | · | · | —, —, block |
| `pack-drift` | pack | *engine*: the hash of a fetched pack in the cache does not match the hash that the lock file `sinter.lock` fixes for it. The built-in pack `markdown` is not in the lock file. The class takes no tier at any gate: the tool stops with exit code 3 | tree | · | · | — |

`uncovered`, `unmet`, and `unstamped` are the incompleteness classes.
They exist so that `status` can report them, and so that the check
that closes a plan (`status --done` and the discharge condition in
[ledger.md](ledger.md)) can read them. The turn report never lists
them as violations. Every other class is a violation, or a signal
about the health of the repository's checking machinery.

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
.plans/auth-lockout.md:19:1: promise auth-lockout/verify-against-the-reqs verifies auth-lockout
.plans/auth-lockout.md:20:1: promise auth-lockout/verify-against-the-reqs verifies lockout-notify

$ sinter query 'uncovered(verifies)'
docs/auth.md:12:1: req auth-lockout v2
docs/auth.md:31:1: req lockout-notify v1
```

The first query lists the promises that are not met. The second query
lists the in-force requirements that no test verifies.
