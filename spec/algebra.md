<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: query algebra

Status: draft.

## 1. Introduction

The query algebra is the small language that Sinter uses for queries,
for rules, and for finding definitions. A query selects a subset of the
facts that a scan produced. This document defines the universe of
facts, the syntax of expressions, the type discipline, every function,
and the built-in finding definitions.

Anyone can implement this specification in any tool. See the
LICENSE-SPEC file at the repository root. The facts themselves are
defined in the JSONL specification, [jsonl.md](jsonl.md); the tags they
come from are defined in [vocabulary.md](vocabulary.md).

Notation used in this document: `∈` means "is a member of", `⊆` means
"is a subset of", `∅` is the empty set, `⋃` is a union over a family of
sets, and `⊥` means "unresolved". `S` and `T` range over fact sets, `E`
over edge sets, `P` over promises, `R` over rules, `K` over kind
lists, `n` over name patterns, and `g` over globs.

## 2. Universe

A query is evaluated against a **universe** `U`. The universe is the
fact set produced by scanning one working tree `T` against one base
`B`, with one ledger `L`, one evidence set `E` (for the tree key of
`T`), and one session `S`. Every fact is an immutable record with a
`kind` and a stable `id` (see [jsonl.md](jsonl.md), section
"Identity").

A query denotes a subset of `U` and nothing else. There are no
scalars, no tuples, and no new facts. `U` is finite. Every closure is
a least fixpoint of a monotone step, so every closure terminates.

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
| `law` | `rule` `gate` | yes (in the manifest) |
| `ack` | `ack` | yes |
| `ledger` | `lease` `decline` | no |
| `hunk` | `hunk` | yes; diff mode only |
| `tombstone` | `tombstone` | yes (base coordinates) |
| `finding` | `finding` | yes (its subject's location) |

Notes on individual kinds:

- A `site` is an anonymous `@satisfies` or `@cites` source in code. It
  carries the code hash `ch`.
- A `test` is named by the language pack's ID strategy.
- An edge's `src` is a node or a rule. An edge's `dst` is a node, a
  ref, or unresolved. A rule's origin is a `cites` edge whose `src` is
  the rule.
- A `hunk` is one hunk of `git diff B`, in new-side coordinates.
- A `tombstone` is a fact that is present in the index of `B` and
  absent from the index of `T`. It carries the old id, kind, and
  extent hash.

"Located" facts carry `path`, `line`, `col`, `eline`, and `ecol`. Only
located facts are returned by `path(…)`, `scope(…)`, `historical`,
`ambient`, and `acked(…)`.

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
slugpat  := [a-z0-9*]+ ( '-' [a-z0-9*]+ )*
testpat  := any run of characters other than ',' and ')' ;
            quote with "…" otherwise; '*' globs
glob     := gitignore-style pattern; quote with "…" if it contains
            whitespace or ','
revspec  := 'base' | any git revision
word     := [a-z][a-z0-9-]*
ws       := one or more spaces
```

Lexical rules:

- **Binary operators are whitespace-delimited.** `a - b` is a
  difference. `auth-lockout` is one slug. Without this rule, slugs and
  difference would be ambiguous. `^` and `+` follow the same rule.
  Parentheses do not need whitespace.
- **Precedence.** `^` binds tighter than `+` and `-`. `+` and `-`
  share one level and associate left. So `a + b ^ c - d` means
  `(a + (b ^ c)) - d`.
- **Arguments are positional.** Each function declares the kind of
  each argument (section 6). A `name` argument can contain `*` as a
  glob. A `kinds` argument can be a category name.
- **Names are resolved after substitution.** A saved definition's
  parameters are substituted as text before the expression is parsed
  (section 7). A parameter can therefore stand for an expression, a
  kind list, a name, or a glob.
- **Keywords.** `all`, `active`, `historical`, `ambient`, and `base`
  are reserved as bare words. A saved definition must not shadow a
  built-in name.

## 5. Categories as types

Each expression is assigned a **category set** statically, before
evaluation:

- `all` → every category. `kind(K)` → the categories of the kinds in
  `K`. A name selector → its kind's category. `path`, `historical`,
  `ambient`, `acked` → every located category. `changed` → every
  category, tombstones and hunks included. `active` → `{node}`.
  `findings` → `{finding}`.
- `out`, `in` → `{edge}`. `src`, `dst`, `deps`, `rdeps`, `paths` →
  `{node, ref, law}` (the `src` of a rule's origin edge is a rule).
  `subject` → every category a finding can be about. `scope` → the
  located categories plus `hunk`; its argument also accepts `lease`.
  `promises`, `met` → `{promise}`. `done` → `{node}`. A predicate →
  the category set of its argument, intersected with what it accepts.
  `owed`, `judged` → every category. `triggered` → `{law}`.
- `S + T` → the union of the two category sets. `S ^ T` → the
  intersection. `S - T` → the left side's set.

Each function declares which categories it accepts per argument. Facts
of other categories in an argument are dropped silently: `src(all)` is
valid and means "the sources of every edge". A static error is raised
only when an argument's category set does not intersect the accepted
set. Example: `src(kind(req))` is rejected before evaluation with the
message `src() accepts edge; argument has category {node}`.

## 6. Function reference

There are 37 names. In the tables, `src(e)`, `dst(e)`, and `rev(e)`
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
| `active` | the active plan and, if declared, the active step; only in-force plans are candidates; `∅` when no plan is active |
| `historical` | located facts under a manifest `historical` path |
| `ambient` | located facts under a manifest `ambient` path, in a plan file, in the manifest, or in the lockfile |
| `acked(t)` | located facts `f` such that the tag-bearing block containing `f` carries a live `@ack` whose target `t` applies to `f`: the class or rule name matches, and the ack's subject, when given, equals `f`'s key (the `dst` slug for an edge, the slug for a node, the `id` otherwise) |
| `findings(C)` | finding facts whose class is in `C` |

### 6.2 Traversal (one hop, typed)

| function | accepts | denotes |
|---|---|---|
| `out(K, S)` | `S`: node, law | edges `e` with `kind(e) ∈ K` and `src(e) ∈ S` |
| `in(K, S)` | `S`: node, ref | edges `e` with `kind(e) ∈ K` and `dst(e) ∈ S` |
| `src(E)` | edge | the sources of the edges in `E` |
| `dst(E)` | edge | the resolved targets of the edges in `E`; a dangling edge contributes nothing |
| `subject(F)` | finding | the subjects of the findings in `F` |

### 6.3 Closures

Closures are least fixpoints. Dangling edges are ignored. Suspect
edges are followed, because a stale citation is still a citation.

| function | accepts | denotes |
|---|---|---|
| `deps(K, S)` | node, law | the least `X ⊇ S` with `dst(out(K, X)) ⊆ X` |
| `rdeps(K, S)` | node, ref | the least `X ⊇ S` with `src(in(K, X)) ⊆ X` |
| `paths(S, T)` | node, ref, law | `deps(edge, S) ^ rdeps(edge, T)`: every node on some path from `S` to `T` over any edge kind |

### 6.4 Plan functions

| function | accepts | denotes |
|---|---|---|
| `scope(S)` | plan, step, rule, lease | located facts and hunks whose `path` matches the effective scope of some member of `S`. A step's effective scope is its own `@scope` when present, else its plan's. A plan's effective scope is the union of its steps'. A rule's scope is its `scope` field. `∅` when `S` holds no scope-bearing fact |
| `promises(S)` | plan, step | promise facts whose step or plan is in `S` |
| `met(P)` | promise | the promises in `P` that are discharged, as defined in [vocabulary.md](vocabulary.md) section 10.5 |
| `done(S)` | plan, step | steps whose promises are all met — or, for a step with no promises, whose scope intersects `changed(base)` — and whose in-scope `verifies` edges are all at rung `passing` or an allowed rung; plans whose steps are all done, under the same evidence condition |

### 6.5 Status predicates

A predicate filters its argument: `pred(S) ⊆ S`.

| function | accepts | keeps `f ∈ S` iff |
|---|---|---|
| `inforce(S)` | any | for a declaration: `f` carries no status tag and no live `@supersedes` edge targets `f`. Liveness is a fixpoint over supersession chains; on a cycle every member counts as in force, and the `cycle` finding fires. For a plan, its steps, and its promises: the ledger holds no `discharged` or `abandoned` entry for the plan. Every other kind is kept |
| `approved(S)` | any | `f` is a declaration of a gated kind with a ledger stamp for `(slug, rev, xh)`; or a declaration of a kind the ledger does not gate; or a plan whose current commitment set is approved against its latest stamped set (see [ledger.md](ledger.md)); or a step of an approved plan; or any other kind |
| `bumped(S)` | node | `f` is a declaration absent from the index of `B`, or present there with a smaller revision |
| `declined(S)` | node | `f` is a declaration or a plan with a live decline: one whose recorded hash equals `f`'s current extent hash (declarations) or commitment-set hash (plans) |
| `blocked(P)` | promise | the promise targets a slug that is declared nowhere in `T` but that some live lease promises to declare — an ordering fact, reported instead of `dangling` |

### 6.6 Edge predicates

| function | keeps `e ∈ E` iff |
|---|---|
| `suspect(E)` | `rev(e) ≠ ⊥`, `dst(e) ≠ ⊥`, `dst(e)` is a declaration, and `rev(dst(e)) ≠ rev(e)` |
| `dangling(E)` | `dst(e) = ⊥`: no declaration has the slug, or the ref's namespace is undeclared, or its id fails the pattern |

### 6.7 Evidence predicates

The evidence predicates partition `kind(verifies)`. Every `verifies`
edge satisfies exactly one of them, tested in the order below. The
rung of an edge is the name of the predicate it satisfies.

Definitions used: `t = src(e)`. `sites(e) = src(in(satisfies,
dst(e)))` minus test nodes — a test's own `@satisfies` never connects
the test to itself. `runs(t)` is the set of run facts for `t` at the
tree key of `T`. `cov(t, s)` is the attributed coverage fact for
`(t, s)`. `agg(s)` is the aggregate coverage fact for `s`.

| function | keeps `e ∈ E` iff |
|---|---|
| `orphan(E)` | `kind(t) ≠ test`: the comment attached to something the pack's test query does not capture |
| `neverran(E)` | `runs(t) = ∅` |
| `failed(E)` | some run in `runs(t)` has status `fail`, `error`, or `skip` |
| `disconnected(E)` | all runs pass, `sites(e) ≠ ∅`, and either attributed coverage for `t` exists with `cov(t, s).hit = 0` for every site `s`, or only aggregate coverage exists with `agg(s).hit = 0` for every site `s` — the whole run never touched the sites, so neither did `t` |
| `unattributed(E)` | all runs pass, `sites(e) ≠ ∅`, no attributed coverage for `t` exists, and some `agg(s).hit > 0` or no coverage was imported at all |
| `passing(E)` | all runs pass, and either `sites(e) = ∅` or some `cov(t, s).hit > 0` |

### 6.8 Law functions

| function | accepts | denotes |
|---|---|---|
| `owed(R)` | law | `⋃` over `r ∈ R` of `eval(trigger(r)) - eval(discharge(r))`: the obligation subjects of each rule. Rule expressions are evaluated in the same universe. A rule whose trigger or discharge mentions `owed` is rejected when the manifest loads; there is no recursion through the law |
| `triggered(R)` | law | the rules in `R` whose trigger evaluates to a non-empty set |
| `judged(n)` | — | subjects with a `judgment` evidence fact for rule `n` whose verdict is `pass` and whose recorded hash matches the subject's current extent hash (or commitment-set hash) |

For a rule whose discharge is `acked(<rule>)`, ack liveness is
`subject ∈ eval(trigger)`. The discharge side never re-enters, so
there is no circularity.

### 6.9 Set operators

`S + T` is union. `S ^ T` is intersection. `S - T` is difference. All
three operate over fact identity.

There are no user-defined functions, no recursion beyond the three
closures and the two fixpoint predicates, no arithmetic, and no
strings other than names and globs.

## 7. Saved definitions

A saved definition is a name, an optional parameter list, and an
expression. Built-in definitions ship with the tool. The manifest adds
or overrides definitions in its `[findings]` table:

```toml
[findings.uncovered]
params = ["e"]
expr   = "kind(req|design) ^ inforce(all) - dst(in($e, all))"

[findings.unstamped-design]
expr   = "kind(design) ^ inforce(all) - approved(all)"
```

Invocation is `uncovered(verifies)`, or bare `unstamped-design` for a
definition without parameters. Parameters are substituted as text for
`$name` tokens before parsing. The substituted expression is parsed
and category-checked as a whole.

Definitions can reference other definitions. A cycle among definitions
is an error when the manifest loads. A definition with a `tiers` field
is a **finding class**: `check` evaluates it. It can also carry
`ackable`, `detail`, and `fix` (the mechanical-fix class). A
definition without `tiers` is query-only. There is one table for both,
because a finding is a definition that someone decided to enforce.
Overriding a built-in finding's expression is allowed, and the diff
that does it fires the `law-touched` finding.

## 8. `changed(b)` and diff mode

### 8.1 `changed(b)`

`changed(b)` is the fact set touched by `git diff b` against the
working tree. Untracked files count as wholly added. "Touched" is
defined per category:

| category | `f ∈ changed(b)` iff |
|---|---|
| `req` `design` `decision` | `f` is absent from the index of `b`, or its normalized extent hash differs between `b` and `T` |
| `plan` `step` `promise` | the plan's commitment set differs from the one in the index of `b`, or the fact is new |
| other located facts | the fact is new, or its line span intersects a hunk's new-side span |
| `hunk` | always |
| `tombstone` | always |
| `edge` | the edge is new, or its line intersects a hunk, or `dst(e)` is a tombstone — a citation whose target vanished is changed even when its bytes are not |
| `evidence` `ref` | never |

`b` can be `base` (the `--base` value) or a git revision. Evaluating
`changed(x)` for another revision requires a second index for `x`,
built on demand.

### 8.2 Diff mode

Diff mode is baseline subtraction. `check --diff` reports
`F(T) - F(b)`, where `F(x)` is the finding set of tree `x` and the
subtraction compares finding identities ([jsonl.md](jsonl.md), section
"Identity").

`F(b)` is evaluated on the base tree, read from git objects without a
checkout, with the same ledger and an **empty evidence set**. So every
evidence-ladder finding at the base is `never-ran`. A pre-existing
`disconnected` test therefore surfaces as introduced on the first
change that measures it. This is a one-time cost, accepted.

A finding that existed at the base and still exists is debt, not a
violation. A finding absent at the base is what the diff introduced.
The diff-relative classes — `rev-owed`, `unmapped-work`,
`law-touched`, `code-drift`, `renamed` — have `F(b) = ∅` by
construction and appear in both modes.

## 9. Built-in finding classes

`check` is the union of the finding classes below. In the table,
`expr` gives the definition where the class is expressible in the
algebra. The mark *engine* means the scanner or the adjudicator emits
the class directly, because it concerns malformed input or a two-tree
comparison the algebra does not model. Engine findings are still
ordinary finding facts.

Four global rules apply after evaluation. They are never written into
definitions:

1. Historical facts generate no findings of any class.
2. A live `@ack` discharges findings of ackable classes. Liveness is
   judged before this subtraction.
3. The classes `never-ran`, `failed`, `disconnected`, and
   `unattributed` are evaluated only when an evidence set exists for
   the tree. An unmeasured tree reads as unmeasured, never as red. The
   `rung` field on edges reads `never-ran` either way; only the
   finding is withheld.
4. Facts that belong to a plan not in force — the plan, its steps, its
   promises — generate no findings. A dead plan is record, not
   agreement.

Column `A` marks ackable classes. Column `F` marks classes with a
mechanical fix. `tiers` gives the shipped defaults for the gates
`(turn, pr, main)`; every class ships at `warn` under the rollout cap
until the repository promotes it.

| class | subject | definition | mode | A | F | tiers |
|---|---|---|---|---|---|---|
| `parse-error` | file | *engine*: a governed file its pack cannot parse; the file's facts are absent | tree | · | · | warn, block, block |
| `typo-tag` | line | *engine*: an unknown `@word` within Damerau–Levenshtein distance 2 of the vocabulary, the pack's foreign vocabulary exempt | tree | · | F | warn, warn, warn |
| `bad-target` | tag | *engine*: a slug or ref that fails its pattern, or an undeclared namespace | tree | · | · | block, block, block |
| `duplicate` | node | *engine*: two declarations of one slug; two plans of one slug (dead plans included); or two steps of one plan with equal slugs | tree | · | · | block, block, block |
| `bad-scope` | step | *engine*: a step whose `@scope` is not contained in its plan's | tree | · | · | block, block, — |
| `misplaced-plan` | node | *engine*: a `@plan` declaration outside `.plans/**` | tree | · | · | block, block, block |
| `unpinned` | edge | *engine*: a `satisfies`, `verifies`, `refines`, or `supersedes` edge without a revision | tree | · | F | block, block, block |
| `dangling` | edge | `dangling(kind(edge))`, minus edges whose target a lease promises to declare — those surface as `blocked-on` instead (*engine* performs this subtraction) | tree | · | · | block, block, block |
| `renamed` | edge | *engine*: dangling edges whose slug has a tombstone in `B` and a new declaration in `T` with an equal extent hash | diff | · | F | block, block, block |
| `suspect` | edge | `suspect(kind(edge))` | tree | · | F | block, block, block |
| `rev-owed` | node | `kind(req\|design\|decision) ^ changed(base) - bumped(all)` | diff | · | F | block, block, block |
| `cycle` | node | *engine*: a cycle in `supersedes` or `refines` | tree | · | · | block, block, block |
| `code-drift` | site | *engine*: `ch` changed since the base while the site's comment hash did not. Not ackable: the class is diff-relative, so an ack would void on merge | diff | · | · | warn, warn, — |
| `declined` | node | `declined(kind(req\|design\|decision\|plan))`; the detail is the reason | tree | · | · | warn, block, — |
| `unratified-req` | edge | `in(satisfies\|verifies, kind(req) - approved(all))` — a kind the ledger does not gate counts as approved, so the class self-silences | tree | · | · | block, block, block |
| `unratified-design` | edge | `in(satisfies\|verifies, kind(design) - approved(all))` | tree | · | · | warn, warn, warn |
| `unstamped` | node | `kind(req\|design\|decision) ^ inforce(all) - approved(all)` | tree | · | · | off, warn, warn |
| `amendment` | plan | `kind(plan) ^ inforce(all) - approved(all)`; *engine* supplies the set delta as detail | tree | · | · | warn, block, — |
| `disendorsed` | edge | `kind(cites) - dangling(all) - in(cites, inforce(all))` — a rule's origin edge included | tree | A | · | warn, block, block |
| `stale-ack` | ack | *engine*: an `@ack` whose hash no longer matches its block, or whose target names nothing at that site | tree | · | F | block, block, block |
| `orphan` | edge | `orphan(kind(verifies))` | tree | · | · | block, block, block |
| `never-ran` | edge | `neverran(kind(verifies)) ^ scope(inforce(kind(plan)))` at `turn`; `neverran(kind(verifies))` at `pr` and `main` | tree | · | · | warn, block, block |
| `failed` | edge | `failed(kind(verifies))` | tree | · | · | block, block, block |
| `disconnected` | edge | `disconnected(kind(verifies))` | tree | A | · | warn, block, block |
| `unattributed` | edge | `unattributed(kind(verifies))` | tree | · | · | off, warn, warn |
| `uncovered` | node | `uncovered(verifies) + uncovered(satisfies)` — incompleteness; never blocks a turn end | tree | · | · | off, warn, warn |
| `unmet` | promise | `unmet(active)` where `unmet(p) = promises($p) - met(promises($p))` — incompleteness; enforced only by `status --done` | tree | · | · | off, off, — |
| `promise-out-of-scope` | promise | *engine*: a promise met only by residue outside its step's scope | tree | · | · | warn, warn, — |
| `unverified-promise` | promise | *engine*: a promised `req` or `design` with no promised `verifies` of it in the same plan | tree | · | · | warn, warn, — |
| `promise-collision` | promise | *engine*: a promised declaration whose slug exists in the index of `B` or is promised by a lease | tree | · | · | block, block, — |
| `scope-overlap` | step | *engine*: two steps of one plan with intersecting scopes and intersecting promise sets | tree | · | · | warn, warn, — |
| `blocked-on` | promise | `blocked(promises(kind(plan)))` — reported in place of `dangling`, with the lease and step named | tree | · | · | off, warn, — |
| `lease-overlap` | step | *engine*: a step's scope intersects a live lease's scope on another branch | tree | · | · | warn, warn, — |
| `unmapped-work` | hunk | `kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - scope(triggered(kind(rule))) - ambient`; *engine* also exempts hunks that are wholly mechanical repairs — tag-line re-pins and `@ack` insertions or deletions | diff | · | · | block, block, — |
| `rule-owed` | any | `owed(kind(rule))`, one finding per `(rule, subject)`; ackable iff the rule's discharge is `acked`; a rule's own `tiers` overrides the class's | tree | A* | · | warn, block, block |
| `law-touched` | law | `kind(rule\|gate) ^ changed(base)` — cannot be disabled; always reported, never blocks | diff | · | · | warn, warn, warn |
| `undischarged-plan` | plan | *engine*: an in-force plan on the target branch that fails the discharge condition ([ledger.md](ledger.md)) — merged incomplete | tree | · | · | —, —, block |
| `ledger-broken` | ledger | *engine*: ledger verification fails | tree | · | · | —, —, block |
| `pack-drift` | pack | *engine*: a pinned pack's hash does not match the cache | tree | · | · | exit 3 everywhere |

`uncovered`, `unmet`, and `unstamped` are the incompleteness classes.
They exist so that `status` and the death gate can see them. The turn
report never lists them as violations. Every other class is a
violation or a health signal.

## 10. Evaluation, ordering, and errors

- Evaluation is bottom-up over the parse tree. Selectors are answered
  from per-kind indexes; traversals from adjacency maps built once per
  scan; fixpoints by worklist. A saved definition is expanded once per
  invocation site.
- Results print in the order `(kind, path, line, col, id)`. Unlocated
  facts come after located ones, ordered by `id`. Reordering never
  changes the set.
- Static errors — a category mismatch, an unknown function, a wrong
  arity, an unknown saved definition, a wrong parameter count — are
  reported before evaluation and name the offending subexpression.
- A name selector that matches nothing is not an error. It denotes
  `∅`, because that is what `req(auth-lockout)` should mean on a
  branch that has not written it yet.
- `changed(x)` for a revision git cannot resolve is an environment
  error.

## 11. Example

This example is informative. On a plan whose implementation step has
landed but whose tests do not exist yet:

```
$ sinter query 'promises(active) - met(promises(active))'
.plans/auth-lockout.md:19:1: promise auth-lockout/verify-against-the-reqs verifies auth-lockout
.plans/auth-lockout.md:20:1: promise auth-lockout/verify-against-the-reqs verifies lockout-notify

$ sinter query 'uncovered(verifies)'
docs/auth.md:12:1: req auth-lockout v2
docs/auth.md:31:1: req lockout-notify v1
```

The first query lists the promises that are not met. The second lists
the in-force requirements that no test verifies.
