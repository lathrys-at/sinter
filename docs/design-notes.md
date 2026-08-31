<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Design Notes: Plan-Centric Spec Tracing & Enforcement for Agentic Development

## 1. Thesis

Agentic coding systems reliably fail at two things: following project conventions and staying on an agreed plan. This is architectural, not a capability gap:

- Plan signal decays 4–12× within a single action-observation step; agents depend on the plan remaining literally in context ("Plans Don't Persist," arXiv:2606.22953).
- Constraint violations rise from 0% with a policy in full context to 30–59% after compaction ("Governance Decay," arXiv:2606.22528).
- Self-reported completion diverges from actual tool activity often enough that published enforcement patterns refuse to admit self-report as evidence (Proof-or-Stop, arXiv:2607.14890).

So agreements cannot be enforced by instructions in context. They must be enforced by an external system that (a) derives status from artifacts, never from self-report, and (b) blocks illegal transitions deterministically at the merge boundary while making them unmissable everywhere earlier. Context injection is an informational channel, not an enforcement channel — and so is tool-call interception: hooks that deny edits or seize turn-ends are enforcement aimed at the agent's hands, and what that trains under pressure is bypass. Locally the tool computes the same deterministic verdict CI will and hands it to whoever runs the session's workflow — a human, or an orchestrating lead agent — which is where in-loop judgment belongs.

**Threat model: the agent is collaborative.** The enemy is *decay* — plans falling out of context, conventions forgotten after compaction, completion pressure producing optimistic self-report — not a scheming adversary. The assumption is load-bearing: local evidence and hooks are trusted rather than tamper-proofed, approval prevents accidents and drift rather than forgery, and the manifest is agent-editable. Words like "laundering" name pressure gradients that arise without malice. Deployments that cannot make this assumption need hardening (§10.1 notes where it attaches) that the baseline deliberately does not carry.

**Prior art, and the gap.** Beads owns the agent-facing task graph but enforces nothing. Spec-driven tools (Spec Kit, OpenSpec, Kiro) treat specs as prompt-level context. The requirements-traceability tradition (Doorstop, StrictDoc, OpenFastTrace) owns typed graphs, suspect links, and coverage — proven under DO-178C — but predates agents. Claude Code hooks own deterministic blocking but have no data model. Luria (a truth-maintenance system over decision records) owns the *why*-layer and two operational lessons imported here: most propagation findings resolve by acknowledged judgment, not repair; and an enforcement field nobody ever moves is an enforcement mechanism that cannot fire. No system combines these.

## 2. Shape: One Dynamic Object, Static Residue

The system has exactly one dynamic object — the **plan** — and everything else is either the static residue plans deposit or machinery policing the conversion.

A **plan** is a branch-scoped agreement between user and agent: steps, each promising graph deltas. It is born on its branch and its entire purpose is to convert itself into **residue**: requirement and decision declarations in prose, `@satisfies` and `@verifies` citations at implementation and test sites, test evidence, ledger entries. **A plan dies by ledger entry, never by file event — `discharged` at merge, and only when everything it promised has become static fact, or `abandoned` by a human (§6.3)** — and its file never moves: a dead plan stays in the tree as inert record beside the residue it produced. Nothing is archived elsewhere because nothing is deleted; the ledger, not the filesystem, says when scaffolding stopped being an agreement.

- The **graph** (§3) is accumulated residue: tags in the repo's own text.
- **Evidence** (§4) binds `@verifies` citations to real test runs and coverage.
- **Specifications** (§6.4) are approved projections of the graph, outliving every plan that fed them.
- **The ledger** (§6.4) is the record of every judgment — stamps, declines, discharges, abandonments — on a git ref outside the tree; a plan's death is one of its facts (§6.3).
- **Obligations** (§7) are the computed difference between what agreements demand and what residue exists — never stored, recomputed at every gate.
- **Rules** (§7) are standing law: checked-in query expressions that generate obligations forever.
- **Gates** (§8) police the conversion.

Obligations attach to tags, plans, and diffs — never to the tree as a whole — so an existing repo starts with an empty graph and zero findings, and adoption is incremental by construction: any deliberate ratchet is a manifest rule, never a migration.

## 3. The Graph

### 3.1 Tags in the Repo's Own Text

Residue lives as **doctags** in comments and markdown — no sidecar files. Colocation is the anti-divergence mechanism: a tag in a doc comment moves with the function, is reviewed in the same diff, dies when the code dies. The graph is a compiled artifact: a scanner extracts tags into an ephemeral index. Plain text in git is the sole source of truth.

The scanner is **tree-sitter**, so it never scans raw text. Each file is parsed with its language pack (§5.2), and tags are recognized only inside nodes the pack designates as tag-bearing — comment nodes in code, the leading paragraph of a section in markdown. String literals, code fences, and `[[nodiscard]]`-style lookalikes are never scanned, because they are never those nodes. A comment attaches to the next named definition (function, struct, `it(...)` call — the pack says which), which is what makes test binding possible (§4).

### 3.2 Grammar

One shape: `@word target [vN]`, then description.

```markdown
## Lock account after 5 failed attempts
@req auth-lockout v2
@refines auth-security v1
Five consecutive failures within ten minutes freeze the account.

The section body below is the requirement's extent...
```

```rust
/// @satisfies auth-lockout v2
/// Counter is per-principal, reset on success.
fn enforce_lockout(...) { ... }

/// @verifies auth-lockout v2
#[test]
fn locks_after_five_failures() { ... }
```

- **Description.** A tag's *inline* description is the remainder of its own line. A block's *trailing prose* — non-`@` lines after the last tag line, up to a blank line or the end of the tag-bearing node — belongs to the block's declaration if it has one, otherwise to the block's first tag. (In the example above, "Five consecutive failures…" describes `auth-lockout`, not `@refines`.) Descriptions are used when compiling human-facing output and are part of the extent; otherwise the tool ignores them. Any `@`-prefixed line is a tag line, ours or not; unknown tags are simply not ours (a warn-tier `typo-tag` finding fires for unknown tags within edit distance 2 of the vocabulary — minus each pack's declared **foreign vocabulary**: tag words other toolchains own (`@see`, `@param`, `@returns` in JSDoc, Doxygen, odoc) are never typo candidates — since a typo's failure mode is a silently absent edge).
- **Targets** are slugs (`auth-lockout`), unique across the citable declaration kinds — a citation names no type, so `req`, `design`, and `decision` share one namespace; plan slugs are their own namespace (a plan routinely shares its slug with the requirement it promises) and permanent — a dead plan keeps its slug, and reuse is a `duplicate` — and step slugs are scoped to their plan — or refs (`gh/42`) whose namespace the manifest declares. A slug matches `[a-z0-9]+(-[a-z0-9]+)*`; a ref matches `<ns>/<id>` where `ns` is a declared namespace and `id` matches that namespace's pattern. A citation never names a type; the declaration owns it. Duplicate slugs are a finding (`duplicate`), as is a slug or ref that fails the pattern (`bad-target`).
- **`vN`** is the revision, `v` followed by a positive integer, starting at `v1`. It is load-bearing for suspect detection (§3.5). Mandatory on `@satisfies`, `@verifies`, `@refines`, and `@supersedes` (unpinned would silently opt out of suspect detection — finding `unpinned`), optional on `@cites`, absent on promises (the target doesn't exist yet), and defaulting to `v1` when omitted on a declaration — friendly to first tagging; the first `rev-owed` patch writes it out. A bump must strictly increase the revision relative to the base; the emitted patch always uses `+1`.
- **No titles.** In markdown the heading is the title; in code, declarations don't appear.
- **Identity is the slug.** Rename is death-plus-birth; the adjudicator detects the resulting dangling citations in the same diff and emits a fix-up patch. No hidden machine IDs. Renaming an approved item yields an unapproved slug even with untouched content — correct, so the delta presentation renders it as "rename only, hash unchanged" to make the re-stamp a glance.

### 3.3 Vocabulary

Fourteen words. One more (`@pin`) is designed but deferred.

**Declarations** — this text defines a thing.

| tag | where | what the tool checks |
|---|---|---|
| `@req <slug> vN` | requirements docs | satisfied? verified? approved at this rev? text changed without a bump? |
| `@design <slug> vN` | design docs | same checks as `@req`; approval strictness is a per-type manifest setting |
| `@decision <slug> vN` | decision records | text changed without a bump? still cited after retirement? never deleted (§3.6) |
| `@plan <slug>` | plan files | see §6 |

`@design` differs from `@req` only in what it is for — architecture between requirements and code — and in how strictly it is approved. The chain req → design → code is a graph property (design `@refines` req; code `@satisfies` design), and the type lives on the tag rather than on a path, so design documents live wherever a project keeps them.

**Citations** — this relates to that.

| tag | source → target | source | what the tool checks |
|---|---|---|---|
| `@satisfies <slug> vN` | code site → req or design | anonymous (file + extent) | target exists, rev current, target approved; feeds coverage |
| `@verifies <slug> vN` | test → req or design | the attached test, identified from the AST | all of the above, plus the evidence ladder (§4) |
| `@refines <slug> vN` | req or design → req or design | enclosing declaration | target exists, rev current; builds the hierarchy |
| `@cites <slug or ref> [vN]` | anything → any declaration or ref | anonymous | target exists; if a decision, still in force |
| `@supersedes <slug> vN` | T → T, same type | enclosing declaration | endpoint types match; live edge retires its target |

The source rule follows one principle: *a name is owed exactly when other machinery must address the node; location suffices for everything that merely reads.* Coverage reports render anonymous sources as links. Tests are the case where machinery must address the node — and the AST already names them, so no declaration is owed.

**Status** — we stopped standing behind this. Goes inside the declaration's extent; outside one it is inert, which is what makes code comments safe ground for JSDoc's and odoc's own `@deprecated`. There is no "done" status anywhere.

| tag | applies to | effect |
|---|---|---|
| `@deprecated` | req, design, decision | no longer applies, nothing replaces it |
| `@rejected` | decision | considered and declined; the record stays so nobody re-argues it |
| `@deferred` | decision | undecided; the description says what would settle it |

An item is **in force** iff it carries no status tag and no live `@supersedes` targets it. A `@supersedes` edge is **live** iff its source is itself in force and — for approval-gated types — approved at its current revision. Supersession is an edge, not a status, so the retirement rides the successor's approval turn instead of owing a second stamp on the old item; an unapproved successor retires nothing yet, which is the point.

**Directives** — recorded judgment at a site.

| tag | effect |
|---|---|
| `@ack <finding> <hash>` | a judgment recorded at this site: the named finding is accepted, or the named rule is satisfied, for the text as hashed |
| `@pin <ref>` *(deferred)* | arms an upstream-drift check on external content, endorsed through the approval flow |

`@ack` is one mechanism for two jobs. Its grammar is `@ack <target> <hash>` where `<hash>` is the last token and `<target>` is everything between: a finding class with an optional subject (`disendorsed cache-ttl`, `disconnected`) or a rule name (`ste-docs`) — exactly what `check` reported. The hash is the first eight or more hex digits of the block hash (§3.4). An ack is *live* iff the hash matches the block's current hash **and** the target still names something: an obligation of that rule at this site, or a finding of that class (with that subject, if given) at this site. It is void the moment either goes stale: the text changes, or the finding it names no longer exists. Liveness is judged against the *pre-ack* result — a rule's obligations are its trigger alone, a finding class its raw definition before ack subtraction, which is an engine step (§12.8) — so an ack cannot void itself by succeeding. Either way the void ack is itself a finding, so a judgment can never outlive what it judged. `check` prints the exact line to paste, so the ceremony is a copy, and the report lists every ack next to what it accepted or discharged. It is a *targeted* judgment, never a generic ignore: in Luria's first propagation wave, 42 of 70 findings were correct citations of retired records; without a way to say so, the only path to green is un-retiring things — the record lying to quiet a linter. A finding is ackable iff its honest resolution can be a judgment rather than an edit: retired citations, rule obligations whose discharge is an `@ack`, and disconnected tests (an integration test may exercise a site through a path coverage cannot see) are; suspect and dangling citations are not, because their resolution is a mechanical edit the tool already emits.

**Plan-only:** `@scope <globs>`. Headings are steps (§6.1).

### 3.4 Extent

An item's extent is what its revision covers. In code: the comment block, **excluding the attached code** — meaning lives in the comment and rev discipline polices it; behavior lives in the code and evidence polices it. In markdown: a tag block in the leading paragraph of a section claims the **whole section** as extent, up to the next same-or-higher heading — which is what makes prose governable. Two boundary rules: adjacency never merges (an extent ends where the next declaration begins), and a nested section declaration carves its section *out* of the enclosing extent — otherwise every leaf edit owes bumps up the whole ancestor chain. Prose outside any extent is visibly ungoverned, which is at least honest. Residual gap, half-closed: code drifting from an unchanged comment is not something a deterministic check can *prove*. But each site also carries a **code hash** `ch` over the attached definition's body (pack-normalized the same way). `ch` changed while `xh` is unchanged is a warn-tier `code-drift` finding — not evidence of drift, but the exact sampling frame the fresh-context judge (§8) draws from, and a count the report can show. "We sample" becomes "we sample *these*."

**The extent hash** is SHA-256 over the extent's *pack-normalized text*: the pack's query yields the comment's content lines with sigils (`///`, `#`, `*`) and leading indentation removed, trailing whitespace removed, line endings as LF, `@ack` lines dropped, the declaration's own `@word slug vN` prefix dropped from its tag line (so a rename, or a bare bump with no text change, leaves the hash equal — which is what lets the approval delta render "rename only, hash unchanged" and lets `renamed` fix-ups be mechanical), the `vN` token dropped from every citation line (so a re-pin after an upstream bump is hash-neutral: pin currency is `suspect`'s business, not approval's, and `sinter patch suspect` never cascades `rev-owed` and re-stamps up the graph), and a final LF. Markdown sections normalize the same way minus sigils. This is still the text domain — no parsing, no reflow, no semantic anything — but it means `rustfmt` re-indenting a doc comment or a human recording a judgment inside a section does not owe a bump. Every other byte change does. The same normalized text, hashed, is the block hash `@ack` pins (§3.3); one hash function, one exclusion rule, two consumers.

### 3.5 Revision Discipline & Suspect Links

Stored fingerprints want a write path, which is banned. OpenFastTrace's manual-revision model fits plain text: citations pin `v2`; bumping the declaration to `v3` makes every pinned citation suspect, visible in ordinary diffs. OFT's known gap: nothing forces the bump when meaning changes.

**The diff adjudicator closes exactly that gap:** the turn report or CI sees "extent changed, rev didn't" — flagged at hand-back, blocked at CI. Every extent edit owes a bump — there is no editorial escape hatch, because a self-reported "this didn't change meaning" is a second self-report channel to spot-check, and a typo-driven bump costs one emitted re-pin patch. Stateless, deterministic. A bump also un-approves the item until re-stamped (§6.4): one mechanism, two consequences.

One collision statelessness cannot see locally: two branches each bump `v2`→`v3` with different meanings. Mitigation: PR CI checks out the host's merge ref — the branch as it would land — with `--base` at the *live target tip*, never a stale merge base, so the second branch lands as "extent changed, rev didn't"; approved items are further covered by the ledger's extent hash (same rev, different bytes → unapproved). The residual exposure on unapproved items is the price of statelessness, filed.

### 3.6 Retirement & Propagation

Two orthogonal propagation triggers share machinery and differ in what discharges them:

- **Rev bump** — *the meaning changed*: pinned citations go suspect until re-pinned.
- **Retirement** — *we no longer stand behind this*: via a status tag or a live `@supersedes`. Every `@cites` of a retired item becomes a finding: "this argues from something the record no longer endorses."

Propagation halts at the finding, never cascades: a bad argument for P is not a defeater of P — only a judgment can say whether the thing resting on a withdrawn premise stands on other grounds. (Classical TMS marks nodes OUT automatically; that is precisely the part not imported.) Retired items drop out of coverage queries. One polarity, filed: status tags fail closed; edge-derived retirement fails open — a deleted `@supersedes` restores its target and leaves no dangling edge behind to report it. What catches it is rev discipline: the edge's tag line is part of its source's extent, so the deletion owes a bump and, for gated kinds, a re-stamp.

**Decisions are never deleted** — the one type whose death the adjudicator refuses. The moves are supersede (body intact; the old reasoning *is* the record of why the new decision exists), reject, or defer. The slug is permanent. The rule objects to *silent* revision, not to editing.

**Historical text is exempt by class, not ceremony.** The manifest may declare paths *historical* (devlogs, journals): citations there resolve and render but generate no findings. Demanding per-site acks in history trains the bypass reflex.

Decision records are ADR-shaped — context, choice, *alternatives considered* (the highest-value and most-skipped section: it stops re-litigation). One decision, one thing: a record with two halves is one nobody can cite half of. Do not blur: specifications are compiled views (§6.4); design and decision documents are authored prose hosting `@design` and `@decision` declarations. Design hosted in an issue tracker stays a ref — an issue body has no diff to adjudicate and no extent to hash.

### 3.7 Governed Documentation

Nothing above is specific to requirements documents. A user-facing guide that `@cites auth-lockout v2` goes suspect the moment the requirement bumps to `v3`; a tutorial that cites a deprecated decision becomes `disendorsed`. That is documentation-drift detection — one of the oldest unsolved pains in the trade — delivered by the same two mechanisms with no additional machinery, provided the docs are governed by the markdown pack. It is worth stating as a first-class use, because it also orders the pack roadmap (§5.2): the artifacts that most need tracing and least often get it are interfaces and data shapes, not code.

## 4. Test Evidence

This is the section the rest exists to make possible. A `@verifies` citation is a claim; the tool's job is to turn it into a fact or a finding, using nothing the agent said.

**Identity from the AST.** The language pack's `tests.scm` query captures test definitions and their names (and `describe`-style parents where the language has them). A `@verifies` in a comment attached to a captured definition *is* the test node; no `@test` declaration exists. The pack also selects an **ID strategy** from a fixed, compiled-in menu — Rust module path from file path plus `mod` nesting, Python dotted path from the package root, Go package plus function, JS title path — and parameterizes it. That strategy produces the same string the runner reports, so evidence binding is an exact join; a strategy may also declare a runner-ID normalization (pytest's parametrize suffixes, Jest's `it.each` expansions) so a family of runner rows binds to the one test fact that spawned it. The menu is code, extended by PR when a language genuinely needs a new strategy; packs are data.

**Evidence artifacts.** Runner output in standard formats (JUnit XML first; `go test -json`, `cargo nextest` JUnit, pytest `--junitxml`, Jest reporters all produce it) plus coverage in standard formats (lcov, cobertura, coverage.py JSON). Locally, a gitignored evidence directory (`.sinter/evidence/<tree-key>/`) that `sinter evidence import` populates and the gate reads, keyed by **tree key** so stale evidence never binds to a newer tree. The tree key is the git tree hash of the working tree *as it is*, computed non-destructively: stage everything into a temporary index (`GIT_INDEX_FILE=… git add -A && git write-tree`), honoring `.gitignore`. In CI, recomputed from scratch as the authority. Stated plainly: the local evidence dir is agent-writable — trusted, not proof — acceptable because the failure being caught is "claimed the tests pass without running them," which forging well-formed XML does not resemble; PR CI is what makes the merged claim real. The tool never runs tests: whoever runs them — the agent, an orchestrator, a workflow step — points `evidence import` at the artifacts the run produced. And an absent evidence set is a state, not a violation: the ladder's finding classes evaluate only when one exists (§12.8), so an unmeasured tree reads as unmeasured, never red — while `status --done` refuses regardless, because death requires measurement.

**Attribution is the expensive rung.** Rung 4 below asks whether *this test* executed *that site*, which requires coverage attributed per test. Aggregate lcov/cobertura cannot say; they only say the site was executed by *something in the run*. Attributed sources the packs understand: coverage.py with `dynamic_context = test_function` (Python), JaCoCo session data (JVM, when a pack exists), Jest's per-file `coverageProvider: v8` output combined with `--runTestsByPath` batches, and the universal fallback of running each `@verifies`-bearing test in its own process with its own coverage file — slow, always correct, and what the pack's conformance fixture does. `cargo llvm-cov` and `go test -cover` produce aggregate data unless driven per test. Each `cov` fact carries `attributed: true|false`. With unattributed coverage, rung 4 reports **unattributed** rather than *passing*: the site was executed by the run and the test passed, but the join is not proven. One case survives aggregation: zero aggregate hits on every satisfying site proves **disconnected** outright — if the whole run never touched the site, neither did the test (§12.5). Unattributed is warn-tier by default and never blocks; a repo that wants rung 4 to bite pays for attribution in its test configuration, and `sinter evidence import` says so when it sees only aggregate data.

**The findings ladder**, in order of how much each catches:

1. **Orphan** — `@verifies` attached to something `tests.scm` doesn't capture. Structural, deterministic.
2. **Never ran** — the test's ID appears in no evidence artifact for this tree.
3. **Failed or skipped** — present, not passing. The promise is not discharged.
4. **Disconnected** — passed, but attributed coverage shows it executes zero lines inside any site that `@satisfies` the same requirement. The closest deterministic proxy for a fraudulent verification. Both endpoints of the join already exist; what costs is attribution (above). When only aggregate coverage is present the rung reports **unattributed** instead — unless the aggregate shows zero hits on every site, which proves disconnection without attribution.
5. **Vacuous** — passed, connected, doesn't actually test the property. Reachable only by a judged discharge (§7). This is the ceiling for structural checks, and it is worth saying plainly.

A `@verifies` edge is at exactly one rung at any time: `orphan`, `never-ran`, `failed`, `disconnected`, `unattributed`, or `passing` (rung 5 is a sampled judgment, not a rung the tool assigns). The rung is a field on the edge fact and a family of predicates in the algebra (§12.5). Rungs 1–4 are what tree-sitter and standard artifacts buy. Rung 4 also gives `@satisfies` citations a job beyond coverage bookkeeping. The pack's conformance fixtures include a real runner run with attributed coverage, so the join is verified end-to-end per language, not assumed.

## 5. Manifest, Language Packs, Refs

### 5.1 Manifest

A **TOML manifest at repo root**, `sinter.toml`, declares: the languages in use, as version constraints (exact versions and hashes live in `sinter.lock`, tool-owned, so a pack is the same bytes on every machine and in CI); ref namespaces; which kinds the ledger gates; historical and ambient paths (lockfiles and generated code — exempt from scope confinement, counted in the report); rules (§7); repo-defined finding classes; and gate tiers. Which files a pack governs is the pack's business, declared in its descriptor and overridable per language. TOML because it is pure config with zero prose; the reference is §14 and it fits on a screen.

**The manifest is inside the boundary, on purpose.** The agent can edit it, gate settings included. Under the collaborative model the risk is drift, not sabotage, so the mitigation is visibility: a built-in, non-disableable rule surfaces any diff touching gate configuration or rules in the report and the turn report — "this change also loosened the law" — so a demotion can never ride silently inside an unrelated diff.

### 5.2 Language Packs

Language support is **data, not code**, loaded at runtime. A pack contains:

- the grammar as **`.wasm`** — one file, every platform, built with `tree-sitter build --wasm`;
- `.scm` queries: which nodes carry tags and what extent they govern, how a comment attaches to a definition, what is a test and what its name is;
- a TOML descriptor: ID strategy and parameters, evidence formats understood, the foreign tag vocabulary exempt from `typo-tag` (§3.2), tree-sitter CLI and wasi-sdk versions it was built with (so "rebuild and compare hashes" is a procedure, not a hope);
- conformance fixtures: a tiny project, expected JSONL, real runner output.

**A pack contains no executable code except a lexer that cannot perform I/O.** A tree-sitter grammar wasm has no WASI imports; the host supplies linear memory and a handful of tree-sitter builtins, and that is the entire surface. Anyone can verify this by reading the wasm import section. This is why runtime loading is acceptable for a dev tool and why packs may be fetched from a registry by hash into a user cache without asking anyone to trust a `.so`. The cost accepted: the tool links wasmtime (the only runtime tree-sitter's wasm feature supports), the binary is 10–20 MB heavier, and a compiled-module cache makes warm load fast — cold load per grammar per machine is paid once. The tool binary is the only platform-specific artifact in the system.

Markdown and TOML are packs too — markdown's queries designate sections and leading paragraphs as tag-bearing and mask code spans by omission. Adding a language is a PR to the packs repository, never a release of the tool. Unsupported languages are visibly ungoverned. V1 packs: Rust, Python, TypeScript/JavaScript, Go, OCaml, Markdown, TOML. Next, ordered by leverage rather than popularity: YAML (CI pipelines, Kubernetes manifests — where operational requirements actually live), SQL (migrations `@satisfies` data requirements), OpenAPI and protobuf (interface contracts, where a `@satisfies` in the schema description is the only place a requirement about a wire format can be traced). A pack that recognizes tags inside structured-data comments or description fields is no different from one that recognizes them in doc comments.

### 5.3 Refs

Refs (`gh/42`, `jira/PROJ-1`) are pointers, not nodes: no fingerprints, no fetching, no propagation by default; the scanner validates namespace and pattern locally. **`@pin` is the opt-in exception** (deferred): when reasoning genuinely depends on external content, the human endorses its current hash through the approval flow and CI thereafter reports upstream drift until re-endorsed. It runs opposite to every other directive — arming a check rather than quieting one.

Refs recover the original motivating example ("close issues when done") without the tool touching GitHub: *presence* is a local rule ("every plan-declared item `@cites` a `gh/*`"); *remote state* is a networked-tier read — a plan can be blocked from dying while a declared item's ref resolves to an open issue, and `query` surfaces "residue with open refs" for the agent to fix with the `gh` CLI it already has.

## 6. Plans

### 6.1 The Plan File

A markdown file under `.plans/`, e.g. `.plans/auth-lockout.md`, **committed on the branch and never deleted: a plan is *live* until the ledger says otherwise.** Death is a `discharged` or `abandoned` entry (§6.3), and a dead plan is inert record — no findings, no lease, no scope, readable beside its journal forever. A file is a plan iff it lives under `.plans/` and its first tag block carries `@plan` — which is also what flips every tag in the file into promissory mood; a `@plan` anywhere else is a block-tier `misplaced-plan` finding, so plan discovery and death bookkeeping need only look there. Branch-committed because a gitignored plan doesn't travel across worktrees and is invisible to CI, leaving the anti-invention gate with no authoritative tier.

```markdown
# Account lockout after failed logins
@plan auth-lockout
@scope src/auth/**, tests/auth/**, docs/auth.md

## Write the requirements
@scope docs/auth.md
@req auth-lockout
@req lockout-notify

## Implement lockout counter and freeze
@scope src/auth/**
@satisfies auth-lockout

## Verify against the reqs
@scope src/auth/**, tests/auth/**
@verifies auth-lockout
@verifies lockout-notify

## Simplify the session-store interface
@scope src/auth/session.rs
```

**A plan is a set of promised residue.** Same tags, one semantic rule: inside a plan, tags are read in *promissory mood* — `@req auth-lockout` means this step will declare it; `@verifies auth-lockout` means this step will produce a passing, connected test carrying that citation. Every `##` heading carrying at least one plan tag — `@scope` or a promise — is a step (a bare section is prose: context, notes, nothing derived); a step's slug is the heading text lowercased, non-alphanumerics collapsed to single hyphens, trimmed (`## Verify against the reqs` → `verify-against-the-reqs`); two steps slugifying identically is a `duplicate` finding. Steps are unordered facts; document order is advice.

**What discharges a promise.** A promised declaration (`@req`, `@design`, `@decision`) is met iff a declaration with that slug exists, located within the step's scope. A promised `@satisfies`/`@refines`/`@cites`/`@supersedes` is met iff at least one such edge exists within the step's scope that is neither dangling nor suspect. A promised `@verifies` is met iff such an edge exists within scope at rung `passing` — or at rung `unattributed`, when the manifest sets `evidence.require_attribution = false` (the default until a repo opts in). Residue that discharges a promise from *outside* the step's scope is a warn-tier finding (`promise-out-of-scope`), not a discharge: the scope is part of the agreement.

**Scope globs** are gitignore-style patterns relative to the repo root, comma-separated on the `@scope` line: `*` within a segment, `**` across segments, `!` negation, a trailing `/` meaning "directory and everything under it." A step with no `@scope` inherits the plan's. A step's effective scope is what out-of-scope surfacing measures against and what promise discharge is located against.

**Active plan.** If exactly one *in-force* plan exists on the branch it is active by default — dead plans, however many, are not candidates; with several live ones, `sinter declare <plan>` is required before the brief and out-of-scope surfacing have a plan to anchor on (until then `status` says why).

- **Step status is derived, never ticked.** A step is done iff its promises hold as residue with evidence. The plan is done iff all steps are and all existing evidence is still green. Only then may the branch merge.
- **Forward references resolve within the plan.** Promises float and are checked against the revision current at discharge.
- **The active step is a declared claim — the rare claim safe to accept, because it is purely self-limiting:** it only narrows what the brief compiles for and what out-of-scope surfacing measures against; misdeclaring makes the reports noisier, never quieter. The claim lives in `.sinter/session.json`, beside the index cache and the evidence directory, all gitignored — session state, never truth — keyed by the harness's session id where one exists (§11.18), so parallel sessions in one worktree fight over nothing. Absent a step declaration, scope attribution falls back to plan-level scope.
- **A step with scope and no promises is a refactor:** done when its scope was touched and existing evidence stays green. Weaker, and visibly so.
- **Plan files are exempt from rev discipline** — they are judged by commitment-set diff, never text (§6.2). The plan's revision is the count of stamped amendments.

**Three carve-outs from scope attribution**, each governed by other machinery: the plan file itself (routes to amendment adjudication); the manifest and lockfile (every touch is already loud); and ambient paths (a `Cargo.lock` hunk maps to no step and never will — without this, the first dependency added under a legitimate step flags its own lockfile).

### 6.2 Amendment: The Monotone Rule

Plans must be refactorable on the fly *and* harder to loosen than code — otherwise the agent legitimizes invented work by amending the plan first. "What was approved" is the **commitment set** — the canonical facts for promises and scope per step — and the adjudicator diffs sets, never text:

- **Free:** narrowing scope; renaming and reordering steps; splitting a step; merging steps whose effective scopes are equal — all so long as the commitment multiset is preserved. Merging steps with *different* scopes widens where each merged promise may be discharged and is stamped; §13.7 states the comparison exactly.
- **Stamped:** widening scope; promise-set changes in *both* directions — additions launder invented work, removals welch on the agreement.

"Still approved" is a set comparison, not a path reconstruction, which is why the ledger stores the stamped set itself (a hash cannot be diffed against). The rationale is defensive both ways: **approval fatigue is the real adversary.** Reflexively-granted approvals are worth nothing; maximizing the free region is what keeps the gated region meaningful.

**Cutting work early is the amendment machinery working.** Merging partway is a stamped promise-set shrink. The shrunk plan must then be residue-complete against the tree it ships — half-done hunks from a cut step map to no remaining step, so anti-invention fires until they are reverted or honestly covered. Anything that reached declared residue survives as visible debt in `uncovered()`. `compile residual-plan` emits the undischarged remainder as a plan skeleton for a later branch.

### 6.3 Death Mechanics

Death is a **ledger fact, never a file event.** A plan dies `discharged` or `abandoned` (§6.7); the file stays where it is. There is no deletion to orchestrate, no merge commit to edit, no host-specific machinery — this used to be the hardest section in the document and is now bookkeeping.

The **death gate** is unchanged in substance: a plan may only be discharged when everything it promised has become static fact. Enforcement sits at the merge gate — `status --done`, run where evidence exists (PR CI, the merge queue, or whoever merges). What *writes* the entry is main CI: on every push to the target branch it finds in-force plans now on main — merged, in other words — checks each against the **discharge condition** — every promise has its residue: declarations present, edges present and neither dangling nor suspect, `@verifies` edges at `passing` (or allowed `unattributed`) when main's job measures, at any rung when it does not (§12.8; rung enforcement already happened at the merge gate) — and appends its `discharged` entry, recording the merge commit and the hash of the report compiled at discharge. An in-force plan on main that *fails* the condition is the `undischarged-plan` finding, blocking: someone merged half a plan, and the honest exits are a stamped shrink (§6.2) or reverting the merge. The writer is idempotent bookkeeping — the plan's stamps and the tree are the evidence — so a lost CI run costs a retry, not truth. (The job needs push rights to `refs/sinter/ledger`.)

A plan **not in force** — dead — is exempt from everything: its facts generate no findings (§12.8), it holds no lease, contributes no scope, and is skipped by the active-plan rule. Plan slugs are permanent, like decision slugs — reuse is a `duplicate` — so `compile residual-plan` emits its skeleton under a successor slug. Liveness is a ledger read: without the ledger ref every plan reads live, which `status` flags loudly (fetch the ledger). What this leaves on main is deliberate: the plan and its journal beside the residue they produced, with the ledger saying who approved it, what it promised, and when it stopped being an agreement.

### 6.4 Cash-Out: Specifications & the Approval Ledger

A **specification** is a named projection of the graph — all reqs under a path, a plan, a tag. The tool compiles the *delta since last approval* into a readable document; the human reviews and stamps the batch. Approval attaches to `(slug, rev, extent-hash)` triples, never to the document — the document is the interface. This is the dynamic→static conversion in its purest form.

**The ledger** covers plans, reqs, and (per manifest) design items and decisions, plus pin endorsements. Append-only, living on a **dedicated git ref** (`refs/sinter/ledger`): fetchable by CI, shared across worktrees, outside every path an editor or file tool touches — reaching it takes git plumbing, a deliberate act. Main CI verifies the ref only fast-forwards and entries only accrete. Plan entries embed their stamped commitment set; text-extent kinds keep hash-only entries. Every entry records the `HEAD` and branch it was written from.

Because it is an append-only, timestamped, shared record, the ledger does more than hold stamps. Five things fall out of it, each one more entry kind or one more query, none a new mechanism:

- **Declines.** A human who reads a delta and thinks "no, not like that" has, in v13, nowhere durable to say so; the thought goes into chat and decays. A `decline` entry — `(subject, xh, reason)` — is the human's voice bound to the exact text it was about. `status` and the brief (§8.1) surface it until the extent's hash changes — void, like an ack — or until a later stamp of the subject supersedes it, the human overriding their own refusal (`approve` prompts before stamping over a live decline). It is an instruction that cannot fall out of context, because it is attached to an artifact, not a context — the thesis's own mechanism, pointed the other way.
- **Revision reservation.** Stamping `auth-lockout v3` when the ledger already holds a `v3` for that slug with a different hash is a refusal: "v3 is taken; rebase to v4." The §3.5 collision on approved items moves from *detected at PR CI* to *prevented at approve*. The residual exposure on unapproved items remains the price of statelessness.
- **The plan archive.** The plan's file is now its own record, and the ledger holds the judgment layer over it: every promise every approved plan ever made, each amendment, and the death. Main CI (§6.3) appends the `discharged` entry — the one machine writer — recording the merge commit and the report hash at discharge. A plan's whole life is closed in the ledger: stamped, amended, discharged or abandoned. "Which plan promised this requirement, who approved it, when did it land" is answerable from the ledger alone, without reading a tree.
- **Signing for free.** Ledger commits are git commits. `commit.gpgsign` on the ref makes every approval non-repudiable; `ledger verify --signers` makes that checkable. The §10.1 hardening path attaches with zero design change. Deployments that want the "no approval path from an agent's shell" property enforced *server-side* place the ref under `refs/heads/sinter/ledger`, where hosting platforms' push restrictions apply.
- **As-of, release notes, and metrics.** With `HEAD` and a timestamp on every entry, `compile spec --as-of <ledger-commit>` reconstructs exactly what was approved at any moment; the delta between two ledger points, rendered with extents, is release notes for the requirements layer, derived rather than written. And the §8 health signals gain a time axis: revision churn per item (a req on `v9` is unstable or mis-scoped), amendments per plan (six means it was underspecified), stamp-to-discharge time, and stamps per approval session with seconds per stamp — a direct measurement of the fatigue this design names as its real adversary.

The ledger unifies with revision machinery: editing an approved item bumps its rev, and `auth-lockout v3` is simply unapproved until stamped — exactly as its citations are suspect until re-pinned. Retirement composes for free: a status tag is an extent edit (owes a bump, bump un-approves, routes through the stamp); supersession routes through the successor's stamp. Retirement of contract items reaches the human on every path, with no additional rule.

**The unratified gate:** `@satisfies`/`@verifies` targeting an unapproved `req vN` is an obligation — "implementing against unratified spec." Strictness is per type and per gate, expressed the ordinary way: the class splits into `unratified-req` and `unratified-design` (§12.8), each with its own tiers, and a kind outside `approve` is never unratified at all — non-gated kinds count as approved. Requirements block; design defaults to warn, because blocking on design approval is too much ceremony for solo work, but unratified architecture is also exactly how an agent launders a reinterpretation of intent.

**Known limit:** delta-based approval assumes deltas sized for review. A step dumping forty reqs puts the user back in rubber-stamp territory; the report's health signals count the pending batch (the algebra has no arithmetic, so this cannot be a rule), but it is fundamentally the user's discipline.

### 6.5 The Plan Journal

Session scratch — the agent's running todo — belongs to the agent's own machinery and dies with the context window. Between scratch and residue there is a third thing the design should give a home to: what was tried and why it failed. A plan may carry a journal, `.plans/<slug>.log.md`, historical by a built-in glob — no manifest line owed (§3.6): the agent appends, nothing in it generates findings, citations in it resolve and render. It stays beside its plan as part of the record; `compile residual-plan` carries it forward, and `compile report` includes it. Its purpose is to be the place where small decisions accumulate until one earns promotion to a `@decision` record — the promotion heuristic of §7 needs somewhere for the first instance to be written down. Under the collaborative model, most of a project's actual reasoning is small, and without this it is lost.

### 6.6 Plan Linting and Preview

Plans are the one dynamic object and, in v13, the one governed file nothing helps you write. Plan files are scanned like everything else, so plan-level findings are ordinary findings:

- `unverified-promise` — a promised `@req` or `@design` with no promised `@verifies` of it anywhere in the plan. The plan is agreeing, up front, to ship an unverified requirement. Warn by default; a repo can make it block.
- `promise-collision` — a promised declaration of a slug that already existed at the base or is promised by another branch's stamped lease (§6.7). The step would produce a `duplicate`. (The current tree is never consulted: a discharged promise is precisely a slug that now exists in the tree.)
- `scope-overlap` — two steps in one plan with intersecting scopes *and* intersecting promise sets; document order is advice, but two steps racing for one edge is a plan that has not decided.

**Preview** (`compile plan-preview`) renders the graph *after* the plan as if every promise were met: the declarations that will exist, the edges they will carry, what becomes suspect or retired if a step promises a `@supersedes`, which `uncovered` gaps close and which open. The human approves a plan with foresight instead of trust, and the preview is the document the plan stamp is taken against.

### 6.7 Multi-Plan Coordination

Plans are branch-scoped, and v13 is silently single-plan. A team lead running several worker agents on several branches needs three things the ledger can already supply.

**Scope leases.** Every stamped plan's step scopes are in the ledger. `status` reads the last-fetched ledger ref — never the network; `sinter ledger fetch` or `inbox --fetch` refreshes it — and materializes each other branch's stamped, still-leased plan as a `lease` fact, and reports overlap: "plan `session-store` on branch `feat/store`, stamped Tuesday, also claims `src/auth/**`." Overlap is a warn-tier `lease-overlap` finding, not a block — two plans may legitimately touch one directory — but it is the earliest possible moment to learn that two agents are about to conflict, days before the merge does. A lease dies three ways: its plan is discharged; its plan is **abandoned** — `sinter ledger abandon plan:<slug> --reason …`, a human verb sharing `approve`'s refusal set, for the branch that will never merge; or its branch no longer existed on the remote at the last fetch — deleting a branch releases its claims, and the inbox names leases released that way since the last visit.

**Cross-plan promises.** Plan B's `@satisfies auth-lockout` where `auth-lockout` exists nowhere on B's branch is, in v13, a dangling citation until A merges. With leases, the resolver sees that plan A promises to declare `auth-lockout` and reports `blocked-on A/write-the-requirements` instead — an ordering fact, not an error. Discharge of B's promise still requires the real declaration (after A merges and B rebases), but B's status is honest in the meantime and its turn report does not misfire.

**Merge order.** Cross-plan promises form a dependency graph over leases. `compile merge-order` prints a topological order — or names the cycle — and `status` on any branch says which leases it waits on and which wait on it. This is the team lead's decomposition, derived from what the plans actually promise rather than tracked in a separate list.

None of this requires a plan to know about other plans. Leases are read-only projections of the ledger; a plan file never names a branch.

### 6.8 The Inbox

Under the collaborative model the human is the scarce resource. §6.2 *protects* their attention by maximizing the free region; nothing *schedules* it. `sinter inbox` is one place, across every branch and worktree the ledger and the remote know about, listing only things that need a human judgment: pending stamps per branch, with batch sizes; plans whose death is blocked, and on what; declines whose subject has since changed (rework landed — is it right now?); rule acks agents recorded since the last inbox visit, as the spot-check queue; leases that overlap. Each item names the command that resolves it. It is batched, not pushed: the design's position is that the tool should be the one truthful place to ask "what needs me," and should otherwise never ask.

### 6.9 Out of Scope for Plans

Plans do not model time, effort, priority, or assignment. Those belong to the tracker the refs point at.

## 7. Standing Law: Rules & Derived Obligations

Process conventions ("all drafted prose gets rewritten into Simplified Technical English") are neither derivable from the graph nor tasks. They are **rules**: *(origin, trigger, discharge)* triples in the manifest, where trigger and discharge are expressions in the query algebra (§9.2) and an obligation is literally `trigger − discharge`:

```toml
[rules.ste-docs]
origin    = "ste-adoption"                                   # a @decision slug
trigger   = "kind(req|design) ^ path(docs/**) ^ changed(base)"
discharge = "acked(ste-docs)"
scope     = ["docs/**"]                                      # where discharge edits are expected
```

The rules engine *is* the query engine — no second predicate language, and the exhaustive-match property OCaml buys covers rules for free. Because obligations attach to **artifacts, not contexts**, rules are immune to §1's decay: the turn report re-derives the obligation from the diff no matter what fell out of whose window. Rules are themselves facts in the universe (kind `rule`, §13.5), which is what lets the report and the algebra reason about the law the same way they reason about everything else.

**Every rule cites its origin** — the `decision` that earned it — because a law whose evidence is missing reads as taste, and taste gets re-litigated by the next agent. The origin is modeled as a `cites` edge whose source is the rule fact, so retiring the origin makes the rule surface as *law resting on withdrawn reasoning* through the ordinary `disendorsed` finding — this system's own decay mode, caught by its own machinery with no special case. A rule's `scope` declares where its discharge edits land, so that work done to satisfy a triggered rule outside the plan's scope is not reported as invented (§12.8, `unmapped-work`). Promotion heuristic: one instance is a decision; write the rule on the second re-derivation.

**The why reaches the block.** Rules cite origins, and origins have extents with an *alternatives considered* section. In v13 that reasoning existed but never reached the moment it would change behavior. Now every `rule-owed` finding carries its origin decision's extent (byte-budgeted by `[brief].why_budget`) in the turn report and in `sinter explain`. An agent told "owed: rule `ste-docs`; its origin decision says *three users misread the lockout docs; alternatives considered: glossary (rejected, nobody reads it), reviewer checklist (rejected, decays)*" reframes; an agent told only "owed: rule `ste-docs`" routes around.

**Three kinds of discharge**, in descending trust. A rule does not declare which; the tool reads it off the discharge expression and labels the rule with it in every report, so it is always explicit which laws are enforced and which merely witnessed:

- **Checked** — the discharge is a structural expression: the obligation is gone when the graph says so (`issue-linked` above is discharged by a `@cites gh/*` edge existing). Also the home for external linters: a checker writes `judgment` facts like the judge does, and the discharge is `judged(<rule>)` with a program, not a model, as the judge. Use whenever one exists.
- **Judged** — the discharge is `judged(<rule>)`: an independent LLM call, never the working agent, against a rubric; a fresh context cannot be motivated by wanting to finish. Deferred with `sinter judge`.
- **Acknowledged** — the discharge is `acked(<rule>)`: `@ack <rule> <hash>` (§3.3). Self-report with a liveness mechanism: the text changes, the ack is void, the obligation is back. Known soft spot: an agent under completion pressure will eventually ack text it merely glanced at. Mitigations: every discharge surfaced in the report and the inbox; later, a sampled fraction routed to the judge. No new grammar — acknowledgment arrives with rules, not after them.

How hard a rule's obligations bite is a separate question from how they are discharged, and it is answered the way it is for every other finding: the `rule-owed` class has a tier per gate, and a rule may override it with its own `tiers`.

The system does not model pipelines and does not care whether an obligation is discharged inline or by a subagent: it publishes what is owed; orchestration stays the agent's problem.

## 8. Gates, and the Brief

**Adjudication is layered**, fast/local → authoritative, all installed by `init` (§11). Hooks, the CLI, and CI share one adjudication library, and **the local tiers inform; only CI blocks.** A position, not a concession: in-loop interception — denying tool calls, seizing turn-ends — is enforcement aimed at the agent's hands, and what it trains under pressure is bypass. Enforcement belongs at the merge boundary, which cannot be talked past, and in the workflow of whoever orchestrates the session — a human, or a lead agent running workers — consuming the same deterministic report CI will recompute. What the tool contributes is that the report is seconds-fast, identical at every tier, and derived from artifacts alone; a hand-edit meets the same adjudication as an agent edit.

**One diff, adjudicated at several moments.** Every gate evaluates the working tree against the same **base**: the merge-base of `HEAD` and the manifest's target branch (`main` by default), overridable with `--base`. The working tree is always "now," uncommitted and untracked files included. Hooks, pre-commit, `sinter check`, and PR CI therefore see the same findings, differing only in when they look and which tiers they consult — pre-commit runs the turn tiers, and PR CI is the one variation in *what* it sees: it evaluates the host's merge ref with `--base` at the target tip (§3.5), so the diff is exactly the branch's contribution as it would land. Diff mode (`--diff`) reports the findings the diff *introduced*: those whose identity (§13.6) does not appear in the base tree's finding set. Intersecting with touched facts, as v13 said, would miss a citation nobody touched whose target was deleted.

- **PostToolUse** (surfaces): parse and validation failures on the just-edited file, seconds after writing, plus a note when the edit landed outside the active step's scope. Parse errors degrade toward *stricter* findings, never silent holes — an unparsed `@verifies` is an absent edge — which makes fast parse feedback load-bearing. Only file-path-bearing tools (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`) yield a just-edited file; shell writes surface at the next turn report, which re-derives everything from the actual diff.
- **The turn report** (`check --diff --gate turn`) is the hand-back contract: what an orchestrator runs before accepting a worker's turn, a human before walking away, an agent before calling itself done — its exit code is what a workflow gates on. Its block tier marks **violations, never incompleteness.** Violations are states the tree must never be *left* in: rev-bump owed, dangling citations, out-of-plan work (every hunk maps onto a step or a triggered rule's scope), rule obligations triggered by artifacts touched this turn, claims-vs-evidence divergence. Incompleteness — unmet promises, uncovered items — is never a violation; it is enforced solely by the death gate. An agent that cannot honestly hand back "not done yet" is an agent being trained to fabricate doneness — which is why nothing mechanical seizes the turn: the report is addressed to whoever accepts it.
- **Fresh-context verification** (merge-request time and on demand): an independent agent re-derives expected work from the approved spec and plan, reporting drift both ways — missing *and invented*. It exists because the turn report is path-granular; only a semantic reading catches unrequested work inside a legitimate scope. Also the tier that samples rung 5 of the evidence ladder.
- **CI, two tiers — the only mechanical blocks**: PR CI recomputes the full adjudication and evidence binding against the branch-committed plan — the authoritative backstop. Main CI recomputes residue checks on the merged result, appends `discharged` entries for merged complete plans (§6.3), runs networked checks, and enforces the evidence ladder iff its job imports evidence (§12.8).

**Rollout discipline:** every class ships as *warn*, promoted to *block* individually after its false-positive rate proves out. A gate that cries wolf trains bypass behavior, which is worse than no gate. Mechanically: `init` writes `enforce = "warn"`, a cap over the shipped tiers (§12.8); a class is promoted by naming it under `[gates.<gate>]`, and the cap is lifted for everything by deleting the line. Both are `law-touched`, so promotion is always a visible act. The `turn` tiers ride the same cap — under it `check --gate turn` exits 0, so an orchestrator's gate opens too.

**Reporting discipline:** the compiled report is a complete account — every ack and pin counted next to what it accepted, discharged, or armed — and carries **machinery-health signals**: a repo where no rev has ever bumped and no ack exists is not clean; it is one whose propagation has never fired, and its green says only that nobody has looked.

### 8.1 The Informational Channel: The Brief

§1 names two channels and v13 built only one. The cited results — plan signal decaying within a step, governance decaying after compaction — are answered on the enforcement side by gates and, on the informational side, by nothing: the agent is left to remember. But the tool is the one component that knows exactly what the agent needs right now, because it is all in the index.

**`sinter brief`** compiles that: the active plan and step with its promises and their states; the *approved text* of every declaration the step's promises target (not a summary — the extent, since that is what the agent is implementing against); decisions in force reachable from the step's scope, by `paths` and by `@cites` from anything in scope; rules whose trigger intersects the scope, each with its origin's one-line summary; live declines on anything in scope; leases that overlap; and the current blocking findings with fix lines. Ranked by graph distance from the step's scope, cut to `[brief].budget` bytes, deterministic for a given index.

**Delivery** is by hook. Claude Code's `SessionStart` fires with `source: compact` after a compaction, and `UserPromptSubmit` fires every turn; the stdout of either becomes context. `init --hook claude-code` registers `sinter hook session-start` and, optionally, `sinter hook user-prompt-submit` with a smaller budget. Re-injecting the agreement from artifacts after every compaction is the direct countermeasure to both cited failure modes, and it costs a projection of facts the tool already holds. The brief is informational: it enforces nothing, and nothing in it is trusted by any gate. It exists so the turn report stays short.

## 9. Infrastructure

**Implementation: OCaml.** The vocabulary is a variant type and every gate is an exhaustive match over it, so "no mouth carries logic of its own" is a compile error rather than a discipline: add a tag and every adjudicator, query, and compiler that hasn't handled it fails to build. Language packs, markdown, and TOML sit behind one module signature. Native startup in milliseconds keeps hook latency below where gates get disabled. Costs accepted: agents are weaker at OCaml than at Rust or TypeScript; the wasmtime link (§5.2); Windows unsupported in v1. Git is shelled out to, never linked.

**Canonical interchange: JSON Lines, one fact per line** — node, edge, ref, plan fact, evidence fact, rule, or derived finding, each with a kind, a stable identity, and a schema version, canonicalized per RFC 8785 with values restricted to strings, integers, booleans, and flat arrays of those (which makes JCS trivial: sort keys, no floats). Only ever machine-written. Conformance is byte equality against checked-in fixtures. **The JSONL is always derived, never source.** **Hash domains never blur:** text extents hash as pack-normalized text (§3.4); semantic objects hash over canonical bytes. The index is in-memory with a rebuildable on-disk cache; no database. The schema is specified in §13.

### 9.1 Tool Surface

The binary is `sinter` (sintering fuses loose particles into a solid mass under pressure, without melting them). One core library and thin mouths — CLI, hooks, CI — all speaking the same JSONL. Agents use the CLI through their shell like everyone else; there is no MCP server, because a stateless tool has no process to host one and a stdio shim over the CLI would add a tool surface without adding a capability. The surface is specified as help text in §11. Its principles:

- **Suggest, never touch.** `init` is the one exception, and it touches only tool-owned integration files — workflows, hook settings, the manifest skeleton — never governed text. Otherwise the tool may *emit* a patch (`sinter patch`) on stdout; it never applies one. Whoever applies it authors the diff, and the adjudicator judges it like any other.
- **Three verbs change durable state.** `approve`, `decline`, and `ledger abandon` write the ledger; all refuse to run under a harness (§10.1) and share one refusal set. Main CI appends `discharged` entries (§6.3). `declare` and `evidence import` write session and evidence state under `.sinter/`, which is gitignored scratch, never truth.
- **Absences by design:** no daemon, no web UI, no MCP server, no second predicate language — every addition in this document is a compiled projection, a ledger entry kind, or a finding definition. No `new`, no `close`, no `ack` (the tool prints the line; a human or agent pastes it, and that edit is adjudicated), no configuration outside the manifest.
- **Every mouth is a saved query.** `check` is the union of finding definitions; the turn report is `check --diff --gate turn`; CI is `check --gate pr` or `--gate main`; a hook is a filtered `check` or a `brief`. There is nothing a gate can see that `sinter query` cannot show you.

### 9.2 Queries: A Closed Algebra

Not a menu, not Datalog: a Bazel-sized algebra over the fact stream, specified in §12. The universe is *facts* — nodes, edges, refs, plan facts, evidence, rules, hunks, and derived findings, each with a kind — so a query returns fact lines, and `query --json` is simply a filtered `scan --json`. Bazel's universe is node sets only, which is its one structural mismatch with this domain: half of what matters here (suspect, dangling, evidence) is about edges or (edge, evidence) pairs.

`changed(base)` is the one selector without a Bazel analog and the one that makes the unification real: the fact set touched by a diff against a base. With it, hooks, CI, and `check` are all `query` with a different base, and every mouth on the tool is a saved expression.

**Output modes**, in order of who uses them: ripgrep-shaped lines by default — `docs/auth.md:12:1: req auth-lockout v2  uncovered(verifies)` — in deterministic order always, sort key `(kind, path, line, col, id)`, never hash-iteration order (Bazel added `--order_output` after nondeterminism broke everyone's scripts); `--json` for JSONL facts; `--sarif` for findings, so PR CI gets file-and-line annotations from GitHub code scanning with zero integration work (CodeQL and Semgrep's lesson); `--dot` for anything graph-shaped; and `--jq`, bundled the way `gh` bundles it, as the escape hatch for whatever the algebra can't express. Templates (`--format`) wait until someone asks. Embedding a real engine — SQLite views, Datalog — remains the documented upgrade path, not a commitment; the revisit trigger is a *rule* that cannot be written in the algebra.

## 10. Open Questions

**10.1 Approval UX** (mechanism decided). Under the collaborative model the requirement is *unmistakable*, not *undeniable*: every bypass must require a deliberate act, because a deliberate act is circumvention and circumvention is out of threat model. Two cheap layers: confirmation read from `/dev/tty`, never stdin (a harness's non-interactive shell has no controlling terminal, so the command refuses; `yes | approve` is dead for free); and a harness-envvar tripwire (`CLAUDECODE=1`, manifest-extensible) closing the tmux-pane gap. Plus the structural layer: ledger on a ref outside every checkout, no approval path reachable from an agent's shell. Rejected: per-session token minting — the cryptographic path in a trench coat. For deployments outside the collaborative model the hardening path is now concrete and design-free: signed ledger commits with a signer allowlist, and the ref placed where the host's push restrictions reach it (§6.4). **Still open:** rendering the spec delta so that what is stamped is actually read.

**10.2 Attributed coverage on Rust and Go.** Rung 4 needs per-test coverage (§4). The universal fallback — one process per `@verifies`-bearing test — is correct and slow. Whether `cargo llvm-cov` profraw merging by test name, or a `go test -run` driver, can be made cheap enough to run in the PostToolUse tier rather than only in CI is unknown; until then those packs ship rung 4 as `unattributed` locally and `disconnected`/`passing` in CI.

**10.3 Brief ranking.** "Graph distance from the step's scope" is a heuristic, and a wrong brief is worse than a short one: it fills the budget with the wrong requirements. Whether to weight by citation count, by recency of stamp, or by which declarations the step's promises transitively `@refines` is a question for measurement against real sessions — the metrics tables (§6.4) are where the answer will show up as fewer violations per turn report.

**10.4 ID strategies for unusual test conventions.** OCaml's `ppx_expect` and `ppx_inline_test` are anonymous inline extension nodes with no runner-reported names; JS `describe`/`it` nesting is a title path, not a symbol. The fixed strategy menu must cover these before those packs ship; the OCaml one matters because the tool dogfoods on itself.

---

# Part II — Surfaces

## 11. CLI Surface

The surface is specified as the help text itself. Conventions that apply to every verb:

- **Repo discovery.** Every verb runs from anywhere inside a git worktree; the repo root is `git rev-parse --show-toplevel` and the manifest is `sinter.toml` there. Nothing is looked up in the home directory except the pack cache.
- **Base.** `--base <rev>` is accepted by every verb that reads the diff. Default: `git merge-base HEAD <target>` where `<target>` is `manifest.target` (`main`). The working tree is always "now."
- **Output is deterministic.** Line output is sorted by `(kind, path, line, col, id)`. JSONL is canonical (§13.1). Two runs on the same tree, base, ledger, and evidence produce identical bytes.
- **Exit codes** are shared: `0` clean/success · `1` findings present (or plan not done under `status --done`) · `2` usage error · `3` environment error (manifest invalid, pack missing or hash mismatch, git unavailable, parse error in a governed file when `--strict-parse`) · `4` refused (`approve`, `decline`, or `ledger abandon` without a tty or under a harness marker; ledger not fast-forward; revision taken). A hook translates these into its harness's protocol (§11.18).
- **Line format** for findings, used by `check`, `status`, `query` when the result contains findings, and hook stderr:

  ```
  <path>:<line>:<col>: <class> <subject> [<detail>]
    fix: <one-line instruction or the exact line to paste>
  ```

  Identifiers containing whitespace (JS test titles) are double-quoted. Facts without a location (refs, runs) print `-:-:-:` in the location slot so the column count is stable for `cut`/`awk`.

### 11.1 `sinter`

```
sinter — plans die into residue; residue is checked

USAGE
  sinter <command> [options]
  sinter --help | --version

COMMANDS
  Everyday
    status      What should happen next: active plan and step, derived step
                states, open obligations, finding counts (recomputed every run)
    brief       Compile the context the active step needs (for hooks)
    check       Evaluate every finding definition; exit 1 if any fire
    explain     Why a finding fired, and the reasoning behind the rule
    query       Evaluate an expression in the fact algebra
    declare     Record the active plan/step (session state, never truth)
    patch       Print mechanical fix-ups as a unified diff (never applies them)

  Cash-out
    inbox       Everything that needs a human judgment, across branches
    approve     Stamp pending items into the ledger (human, on a terminal)
    decline     Record a refusal with a reason, bound to the text refused
    compile     Render specs, coverage, reports, previews, history, metrics
    ledger      Inspect and verify the approval ledger ref

  Plumbing
    scan        Rebuild the fact index and print it as JSONL
    evidence    Import runner and coverage artifacts for the current tree
    pack        Fetch, verify, and list language packs
    hook        Harness hook entrypoint (registered by init)
    init        Install manifest skeleton, hooks, CI workflows, ledger ref

GLOBAL OPTIONS
  -C <dir>            Run as if started in <dir>
  --manifest <path>   Manifest path (default: <repo>/sinter.toml)
  --base <rev>        Diff base (default: merge-base of HEAD and manifest target)
  --json              JSON Lines on stdout; one fact per line (see: sinter scan --help)
  --color <when>      auto | always | never  (also honors NO_COLOR)
  -q, --quiet         Findings only; no progress, hints, or health lines
  -v, --verbose       More detail; repeatable
  --no-cache          Ignore the on-disk index cache
  -h, --help          Help for sinter or a command
  -V, --version       Tool version, schema version, wasmtime version

EXIT CODES
  0  clean / success
  1  findings present, or plan not done (status --done)
  2  usage error
  3  environment error (manifest, packs, git)
  4  refused (approve, decline, or ledger abandon without a controlling
     terminal or under a harness)

ENVIRONMENT
  SINTER_BASE          Default for --base
  SINTER_PACK_CACHE    Pack cache directory (default: $XDG_CACHE_HOME/sinter/packs)
  CLAUDECODE, …       Harness markers; approve refuses when any is set
                      (list extended by refuse_env in the manifest)

Run 'sinter <command> --help' for details. The algebra is documented in
'sinter query --help'; the JSONL schema in 'sinter scan --help'.
```

### 11.2 `sinter status`

```
sinter status — what should happen next

USAGE
  sinter status [--plan <slug>] [--done] [--json] [--base <rev>]

  Prints, in order:
    1. Active plan and step (or why there is none), with the effective scope.
    2. Every step of the active plan with its derived state and unmet promises:
         done          every promise met, evidence green within scope
         partial n/m   n of m promises met (0/m once a hunk lands in scope)
         untouched     no promise met and no hunk in scope
         refactor      no promises; done iff scope touched and evidence green
    3. Open obligations: unmapped hunks, rule-owed items, unratified targets.
    3a. Live declines on anything in scope, with their reasons.
    3b. Leases: other branches' stamped plans overlapping this scope, and
        promises here that are blocked on promises there (§6.7).
    4. Finding counts by class, split by tier under the turn tier set.
    5. Machinery health: revisions bumped since base, live acks, void acks,
       evidence age (tree key match), rules whose origin is not in force.
    6. Next-action hints ("sinter patch suspect", "sinter evidence import …").
  Nothing here is stored; every line is recomputed from the tree, the ledger
  ref, and the evidence directory.

OPTIONS
  --plan <slug>   Report on this plan instead of the active one
  --done          Print nothing; exit 0 iff the plan is done (every step done
                  and no verifies edge within plan scope below rung 'passing',
                  or 'unattributed' where the manifest allows it). For merge
                  queues and scripts.
  --json          A leading {"kind":"summary"} fact followed by the plan, step,
                  promise, and finding facts the report was built from

EXAMPLES
  sinter status
  sinter status --done && git push
  sinter status --json | jq -c 'select(.kind=="promise" and .met==false)'
```

### 11.3 `sinter check`

```
sinter check — evaluate every finding definition

USAGE
  sinter check [options] [<class>...]

  Evaluates each finding definition — built-in (sinter query --list) and
  manifest-defined — over the working tree against --base, and prints one
  line per finding. With no <class> argument every class runs. Exits 1 iff
  any finding whose tier for the selected gate is 'block' fires; 'warn'
  findings print but do not affect the exit code unless --strict.

  This command is the turn report, the CI job, and the pre-commit check.
  Each is 'sinter check --diff --gate <g>' with a different base and gate
  (pre-commit uses the turn tiers).

MODES
  (default)         Tree mode: every finding on the working tree, pre-existing
                    debt included. Diff-relative classes (rev-owed, unmapped-
                    work, law-touched, code-drift, renamed) are computed
                    against --base and reported too.
  --diff            Diff mode: only findings the diff introduced — those whose
                    identity (sinter scan --help, "Finding identity") is absent
                    from the finding set of the base tree.

SELECTION
  <class>...        Restrict to these finding classes
  --gate <g>        Tier configuration to apply: turn | pr | main. Without it,
                    everything is reported and nothing is 'block' for the exit
                    code unless --strict. Classes at tier 'off' for the gate
                    are not evaluated.
  --path <glob>     Only findings located under <glob>; repeatable
  --plan <slug>     Only findings located within a plan's scope
  --strict          Treat 'warn' as 'block' for the exit code
  --acked           Also print findings discharged by a live @ack (marked)
  --strict-parse    Exit 3 on any parse error in a governed file instead of
                    reporting it as a 'parse-error' finding

OUTPUT
  (default)         path:line:col: class subject [detail]
                      fix: …        (present when a mechanical fix exists)
  --json            JSONL finding facts (kind "finding")
  --sarif           SARIF 2.1.0 to stdout; class → ruleId, tier → level,
                    finding id → partialFingerprints.sinterId, patches → fixes
  --summary         One line per class: count, tier, ackable
  --explain         After each finding, the expanded definition it fired from

EXAMPLES
  sinter check
  sinter check --diff --gate turn
  sinter check dangling suspect --path 'src/auth/**'
  sinter check --diff --sarif > sinter.sarif
  sinter check --summary --gate pr
```

### 11.4 `sinter query`

```
sinter query — evaluate an expression in the fact algebra

USAGE
  sinter query [options] <expr>
  sinter query --list
  sinter query --explain <name>

  The universe is the fact set of the working tree (sinter scan). An
  expression denotes a subset of it. Selectors pick facts; traversals and
  closures walk edges; predicates filter by derived state; + ^ - combine.
  Binary operators must be whitespace-separated: 'a - b' is difference,
  'auth-lockout' is a slug. Full semantics: see the manual page or §12 of
  the design notes; a one-screen reference follows.

REFERENCE
  Selectors   all  kind(k|…)  req(s) design(s) decision(s) plan(s) step(p/s)
              test(id) ref(ns/id) rule(n)  path(glob)  changed(base|<rev>)
              active  historical  ambient  acked(target)  findings(class|…)
  Traversal   out(k|…, S)  in(k|…, S)  src(E)  dst(E)  subject(F)
  Closure     deps(k|…, S)  rdeps(k|…, S)  paths(S, T)
  Plan        scope(S)  promises(S)  met(P)  done(S)  blocked(P)
  Status      inforce(S)  approved(S)  bumped(S)  declined(S)
  Edge        suspect(E)  dangling(E)
  Evidence    orphan(E)  neverran(E)  failed(E)  disconnected(E)
              unattributed(E)  passing(E)
  Law         owed(R)  triggered(R)  judged(n)
  Operators   +  union    ^  intersection (binds tighter)    -  difference
  Names may contain '*' as a glob. Kinds may be alternated with '|'. Saved
  definitions are invoked like functions: uncovered(verifies), unmet(active).

OPTIONS
  --list            List saved definitions: built-in and [findings] in the manifest
  --explain <name>  Print a saved definition with every nested definition
                    expanded, and its inferred category
  --count           Print the cardinality only
  --order <keys>    Sort keys, comma-separated, from: kind path line col id
                    (default: kind,path,line,col,id)
  --json            JSONL facts
  --dot             Graphviz: node facts become nodes, edge facts become edges;
                    other kinds are omitted with a note on stderr
  --sarif           Only when the result is all findings
  --jq <filter>     Pipe the JSONL through the bundled jq

EXAMPLES
  sinter query 'kind(req) ^ inforce(all) - dst(in(verifies, all))'
  sinter query 'uncovered(verifies) ^ path(docs/auth/**)'
  sinter query --count 'suspect(kind(edge))'
  sinter query --json 'deps(refines, req(auth-lockout))'
  sinter query --dot 'rdeps(satisfies|verifies, req(auth-*))' | dot -Tsvg
  sinter query 'kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - ambient'
  sinter query --jq '.slug' 'kind(decision) - inforce(all)'
```

### 11.5 `sinter declare`

```
sinter declare — record the active plan and step

USAGE
  sinter declare <plan>[/<step>]
  sinter declare --clear
  sinter declare --show

  Writes the active-step claim to .sinter/session.json, keyed by harness
  session id when one exists so parallel sessions in a worktree do not
  fight. The claim is session state, never truth: it only anchors the brief and
  out-of-scope surfacing (§8). Misdeclaring makes reports noisier, never
  quieter, which is why this is the one self-report the tool accepts.

  <plan> is the plan slug (the @plan tag), <step> the step slug derived from
  its heading (sinter status lists them). With <plan> alone, scope falls back
  to the plan's @scope.

OPTIONS
  --clear    Remove the claim; surfacing falls back to the sole plan's scope
             if there is exactly one plan, otherwise says so on every edit
  --show     Print the current claim and its effective scope

EXAMPLES
  sinter declare auth-lockout/implement-lockout-counter-and-freeze
  sinter declare auth-lockout
  sinter declare --show
```


### 11.6 `sinter brief`

```
sinter brief — compile the context the active step needs

USAGE
  sinter brief [--plan <slug>[/<step>]] [--budget <bytes>] [--json]

  The informational channel (§8.1). Prints, ranked by graph distance from
  the active step's scope and cut to the budget:

    1. The active plan and step; each promise with its state.
    2. The approved text — the extent, not a summary — of every declaration
       the step's promises target. Unapproved targets are marked as such.
    3. Decisions in force reachable from the scope: cited by anything in
       scope, or on a paths() route from in-scope items.
    4. Rules whose trigger intersects the scope, each with its origin's
       first line.
    5. Live declines on anything in scope, with reasons.
    6. Leases overlapping the scope, and promises here blocked on promises
       there.
    7. Current block-tier findings with fix lines.

  Deterministic for a given index. Enforces nothing; no gate trusts it.
  Delivered by 'sinter hook session-start' after compaction, which is the
  reason it exists.

OPTIONS
  --plan <p[/s]>    Brief for this plan/step instead of the active one
  --budget <bytes>  Cut here (default [brief].budget)
  --json            The facts the brief was built from, in rank order

EXAMPLES
  sinter brief
  sinter brief --budget 4000
```

### 11.7 `sinter explain`

```
sinter explain — why a finding fired, and the reasoning behind the rule

USAGE
  sinter explain <finding-id> | <class> | rule:<name> | <subject-id>

  For a finding id: the finding line; the definition it fired from, fully
  expanded; the facts on each side of the final set difference that put the
  subject in the result; the fix line; and for rule-owed findings the origin
  decision's full extent — context, choice, alternatives considered.
  For a class: its definition, tiers per gate, ackability, mechanical fix.
  For a rule: trigger, discharge and its kind, scope, and its origin's
  extent.
  For a subject: every finding on it and every ledger entry about it.

  This is the why-layer reaching the moment it changes behavior (§7). The
  turn report includes the same origin text, so an agent normally does not
  need to run this; a human reviewing a finding does.

EXAMPLES
  sinter explain finding:rule-owed:req:auth-lockout:ste-docs
  sinter explain rule:ste-docs
  sinter explain req:auth-lockout
```

### 11.8 `sinter decline`

```
sinter decline — record a refusal, bound to the text refused

USAGE
  sinter decline <subject> --reason <text>

  Appends a decline entry (subject, current extent hash, reason) to the
  ledger. The decline is live while the subject's extent hash is unchanged
  and is surfaced by status, brief, and inbox until then; when the text
  changes it is void and the subject returns to pending, with the old
  reason shown beside the new delta so the reviewer can judge whether it
  was addressed.

  This is the human's durable voice: an instruction attached to an
  artifact instead of a context, which is the only kind that survives
  compaction. Shares approve's refusal set — controlling terminal required,
  harness markers refuse, exit 4.

OPTIONS
  --reason <text>   Required. One paragraph is the right length.
  --push            Push the ledger ref after writing

EXAMPLES
  sinter decline req:auth-lockout --reason "Lockout must be per principal, not per IP; see decision shared-nat"
```

### 11.9 `sinter inbox`

```
sinter inbox — everything that needs a human judgment, across branches

USAGE
  sinter inbox [--fetch] [--since <date>] [--json]

  One list, batched, from the ledger and every branch the remote knows:

    approvals     pending stamps per branch, with batch size — large
                  batches flagged (review fatigue)
    deaths        plans whose death is blocked, and on what
    reworks       declines whose subject has since changed: the rework
                  landed; is it right now?
    spot-checks   rule acks recorded by agents since the last inbox visit
    leases        overlapping scopes, blocked cross-plan promises, and
                  leases released by branch deletion since the last visit

  Each item names the command that resolves it. The tool never notifies;
  this is the one place to ask "what needs me," so that nothing else ever
  has to.

OPTIONS
  --fetch         Fetch the ledger and branch heads first
  --since <date>  Spot-check window (default: last inbox run, from session)
  --json          One fact per item

EXAMPLES
  sinter inbox --fetch
```

### 11.10 `sinter patch`

```
sinter patch — print mechanical fix-ups as a unified diff

USAGE
  sinter patch [options] [<class>...]

  For every finding of a class with a mechanical resolution, prints a hunk
  that resolves it, as a unified diff on stdout with repo-root-relative
  paths (apply from the root, or 'git -C <root> apply'). Nothing is written to the
  tree: apply with 'git apply' (or 'sinter patch | git apply') and the
  resulting edit is adjudicated like any other. Classes with a mechanical
  fix:

    suspect        re-pin each citation to the target's current revision
    renamed        retarget citations of a slug that was renamed in the
                   diff (tombstone at base, new slug with equal extent hash)
    rev-owed       bump the revision by one and re-pin its citations
    unpinned       pin @satisfies/@verifies to the target's current revision
    typo-tag       replace a near-miss tag word with the vocabulary word
    stale-ack      delete the void @ack line
    ack            for findings of ackable classes, insert the @ack line
                   'check' printed (requires --ack; a judgment, not a fix)

  Anything not listed has no mechanical fix by design: dangling citations
  whose target was never renamed, disconnected tests, and rule obligations
  need an edit or a judgment.

OPTIONS
  --ack             Include @ack insertions (see above)
  --path <glob>     Restrict to hunks under <glob>; repeatable
  --plan <slug>     Restrict to the plan's scope
  --dry-run         Print the count of hunks per class instead of the diff

EXAMPLES
  sinter patch suspect | git apply
  sinter patch rev-owed --path 'docs/**'
  sinter patch --ack disconnected --path 'tests/integration/**' | git apply
```

### 11.11 `sinter approve`

```
sinter approve — stamp pending items into the ledger

USAGE
  sinter approve [options] [<subject>...]

  Renders the pending delta and asks for confirmation on the controlling
  terminal (/dev/tty, never stdin), then appends stamps to refs/sinter/ledger.
  With 'decline' and 'ledger abandon', this is one of the three verbs that
  change durable state.
  Each stamp records HEAD and the branch, and is signed when [ledger].sign
  is set. At each subject the prompt offers: stamp / skip / decline (with a
  reason, written as a decline entry — see sinter decline --help).

  Pending means: an approval-gated declaration whose (slug, rev, extent
  hash) has no ledger entry — new items and bumped items; and a plan whose
  current commitment set is not approved against its most recent stamped
  set (§13.7). Text changed under an unchanged rev is not pending — it is
  rev-owed here, and on another branch it is the reservation refusal below. Free amendments
  (narrowing scope; splitting, merging, renaming, reordering steps with the
  commitment multiset preserved) never make a plan pending.

  The delta is rendered as 'sinter compile spec --pending' renders it: for
  text kinds, the extent with word-level changes since the last stamped
  extent; for a rename with an unchanged hash, one line saying so; for
  plans, added and removed promises and widened scope per step.

REFUSES (exit 4) when
  - /dev/tty cannot be opened (no controlling terminal)
  - a harness marker is set: CLAUDECODE or any name in [approve].refuse_env
  - refs/sinter/ledger is not a fast-forward of its fetched remote (--push
    fetches first; without --push the check uses the last fetched state;
    a lost race is recovered with 'sinter ledger push --replay')
  - any subject being stamped has a blocking finding on it (dangling,
    duplicate, bad-target, parse-error)
  - the ledger already holds a stamp for the same slug and rev with a
    different extent hash: the revision is taken by another branch. The
    refusal names it and the fix is a bump ("rebase to v4").

OPTIONS
  <subject>...      Restrict to these subjects, as 'req:auth-lockout',
                    'design:session-store', 'plan:auth-lockout'
  --dry-run         Render the delta, stamp nothing, exit 0 (works anywhere,
                    including under a harness)
  --note <text>     Attach a note to every stamp written this run
  --push            Fetch, verify fast-forward, write, push the ledger ref
  --no-pager        Do not page the delta
  --yes             Skip the per-subject prompt after the delta is shown.
                    Still requires a tty; 'yes | sinter approve' cannot work.

EXAMPLES
  sinter approve --dry-run
  sinter approve
  sinter approve plan:auth-lockout --note "cut step 4, ships without notify"
  sinter approve --push
```

### 11.12 `sinter compile`

```
sinter compile — render generated documents (never into the tree)

USAGE
  sinter compile spec          [--pending | --plan <slug> | --path <glob>]
                               [--as-of <ledger-commit>]
  sinter compile coverage      [--plan <slug> | --path <glob>] [--edge verifies|satisfies]
  sinter compile report        [--base <rev>]
  sinter compile residual-plan --plan <slug>
  sinter compile plan-preview  --plan <slug>
  sinter compile history       <subject>
  sinter compile release-notes --from <ledger-commit> [--to <ledger-commit>]
  sinter compile merge-order
  sinter compile metrics       [--since <date>]
  … [--out <file>] [--format md|html]

  Every compiled document is a projection of the fact set. None is written
  into the repository by the tool; --out writes wherever you say, default
  stdout. Documents are deterministic for a given tree, ledger, and
  evidence, so diffing two compilations is meaningful.

  spec            A specification: declarations under the selection,
                  rendered as prose in document order with status, rev,
                  approval, and coverage per item. --pending renders only the
                  approval delta — exactly what 'approve' would show.
  coverage        Requirements and design items with their satisfying sites
                  and verifying tests (rung shown), plus uncovered items.
                  Anonymous sites render as path:line links.
  report          The complete account for the diff: findings by class and
                  tier; every ack and what it accepted or discharged; law
                  touched by the diff; machinery health; evidence provenance.
                  This is what PR CI posts.
  residual-plan   The undischarged remainder of a plan as a plan skeleton —
                  steps with unmet promises and their scopes, and the plan's
                  journal if it has one — under a successor slug (plan slugs
                  are permanent, §6.3), for a later branch. Emitted, not
                  written to .plans/.
  plan-preview    The graph after the plan, as if every promise were met:
                  declarations that will exist, edges they will carry, items
                  that become suspect or retired, coverage gaps that close or
                  open, and the plan-level findings (§6.6). This is what the
                  plan stamp is taken against.
  history         A subject's life from the ledger joined with git: each
                  approved revision's extent (word-diffed against the previous),
                  who stamped it and when, declines and their reasons, the
                  plan that promised it, the merge that discharged that plan.
  release-notes   The requirements-layer delta between two ledger points:
                  declarations stamped, bumped, retired, or discharged in the
                  interval, rendered with extents. Derived, never written.
  merge-order     Leases in dependency order from cross-plan promises (§6.7),
                  or the cycle that prevents one.
  metrics         Health signals with a time axis: revision churn per item,
                  amendments per plan, stamp-to-discharge time, stamps per
                  approval session and seconds per stamp, acks per week,
                  code-drift counts. Tables, not judgments.

OPTIONS
  --pending         (spec) Only items pending approval
  --as-of <c>       (spec) Reconstruct what was approved as of ledger commit <c>
  --plan <slug>     Selection: items promised by, or within the scope of, plan
  --path <glob>     Selection: items located under glob
  --edge <k>        (coverage) Which citation kind defines coverage
  --out <file>      Write here instead of stdout
  --format <f>      md (default) or html

EXAMPLES
  sinter compile spec --pending
  sinter compile coverage --plan auth-lockout
  sinter compile report --base origin/main > report.md
  sinter compile residual-plan --plan auth-lockout > /tmp/auth-lockout-2.md
```

### 11.13 `sinter ledger`

```
sinter ledger — inspect and verify the approval ledger ref

USAGE
  sinter ledger log    [-n <count>] [--subject <s>] [--json]
  sinter ledger show   <subject> [--json]
  sinter ledger verify [--against <remote>] [--signers <file>]
  sinter ledger fetch  [<remote>]
  sinter ledger push   [<remote>] [--replay]
  sinter ledger abandon <plan> --reason <text>

  The ledger is JSONL on refs/sinter/ledger (sinter scan --help, "Ledger
  entries"). Each approve appends lines in a new commit whose parent is the
  previous tip. The ledger is not a checkout path: no editor or file tool
  reaches it without git plumbing, which is the point.

  log       Entries newest first: stamps, declines, discharges — id,
            subject, rev, by, branch, when, note or reason
  show      Every stamp for a subject, and for plans the stamped
            commitment set alongside the current one with the delta marked
  verify    Exit 0 iff every commit on the ref is a fast-forward of its
            parent and every ledger file is a byte-prefix extension of its
            parent's; --against also requires the local ref to be an
            ancestor-or-equal of the remote's; --signers requires every
            commit to carry a valid signature from a listed key. Main CI
            runs this.
  fetch     git fetch <remote> refs/sinter/ledger:refs/sinter/ledger, fast-
            forward only
  push      git push <remote> refs/sinter/ledger, refusing non-fast-forward;
            --replay recovers a lost race: fetch, re-append the local
            entries absent upstream (by id) in ts order, push again
  abandon   Record that a stamped plan will never merge: its lease dies,
            with the blocked-on promises resting on it. A human verb —
            shares approve's refusal set (tty required, harness refuses)

EXAMPLES
  sinter ledger log -n 10
  sinter ledger show plan:auth-lockout
  sinter ledger verify --against origin
```

### 11.14 `sinter evidence`

```
sinter evidence — import runner and coverage artifacts for the current tree

USAGE
  sinter evidence import <file>... [--format <f>] [--tree <key>]
  sinter evidence list   [--all]
  sinter evidence clear  [--all]
  sinter evidence key

  Evidence binds to a tree key: the git tree hash of the working tree as it
  is, computed through a temporary index so nothing is staged for real.
  Artifacts imported for one key never bind to another; 'evidence key'
  prints the current one so a test script can name its output directory.

  import    Parse each artifact, bind test IDs to test facts through the
            pack's ID strategy, and store the normalized facts under
            .sinter/evidence/<key>/, warning when an artifact path sits
            inside the worktree unignored (the artifact itself would perturb
            the tree key). Prints a binding summary: tests seen,
            tests bound, tests unbound (with the nearest test fact by
            edit distance), coverage attributed or aggregate. Exit 1 if a
            @verifies-bearing test was seen in no artifact.
  list      Evidence sets present, newest first, with age relative to the
            current key; --all includes keys for other trees
  clear     Remove evidence for the current key; --all for every key
  key       Print the current tree key

FORMATS  (auto-detected from content; --format to force)
  junit           JUnit XML (pytest --junitxml, cargo nextest, Jest reporters)
  go-test-json    go test -json
  lcov            lcov .info (aggregate unless the file carries TN: records
                  per test, which some drivers emit)
  cobertura       Cobertura XML (aggregate)
  coverage-json   coverage.py JSON with contexts (attributed when
                  dynamic_context = test_function was set)
  jacoco          JaCoCo XML with session data (attributed)

OPTIONS
  --format <f>    Force a format for every file given
  --tree <key>    Bind to a specific key instead of the current one

EXAMPLES
  pytest --junitxml .sinter/junit.xml --cov --cov-context test \
      && coverage json -o .sinter/cov.json \
      && sinter evidence import .sinter/junit.xml .sinter/cov.json
  sinter evidence list
```

### 11.15 `sinter scan`

```
sinter scan — rebuild the fact index and print it

USAGE
  sinter scan [--json] [--path <glob>] [--kind <k|…>] [--stats] [--no-cache]

  Parses every governed file with its language pack and prints the fact set
  as JSON Lines: one fact per line, canonical (RFC 8785, keys sorted, no
  floats, no nested objects), sorted by (kind, path, line, col, id). This is
  the interchange the whole tool speaks; 'query --json' and 'check --json'
  are filtered scans. The first line is the index header; conformance
  fixtures compare every line after it.

  Line output (no --json) is one summary line per governed file: path,
  pack, facts, parse errors.

OPTIONS
  --path <glob>   Only facts under glob; repeatable
  --kind <k|…>    Only facts of these kinds or categories
  --stats         Counts per kind and per pack, and cache status
  --no-cache      Parse everything; ignore and rewrite the on-disk cache

SCHEMA
  Documented in the manual page and in §13 of the design notes; the schema
  version is the "v" field on every line and is printed by 'sinter -V'.

EXAMPLES
  sinter scan --json > facts.jsonl
  sinter scan --json --kind edge | jq -c 'select(.suspect)'
  sinter scan --stats
```

### 11.16 `sinter pack`

```
sinter pack — fetch, verify, and list language packs

USAGE
  sinter pack add    <name>[@<version>] [--hash <sha256>] [--registry <url>]
  sinter pack verify <name> | --all
  sinter pack list
  sinter pack info   <name>

  A pack is a directory: grammar.wasm, queries (*.scm), pack.toml, and
  conformance fixtures. It contains no executable code except a lexer with
  no WASI imports; 'verify' checks that too. Packs live in the user cache
  keyed by hash. The manifest [languages] table names them with a version
  constraint; sinter.lock pins the exact version and hash. A pack whose
  hash does not match the lock is a refusal (exit 3) everywhere, not a
  warning.

  add      Resolve the constraint (or the given version) against the
           registry, fetch into the cache, and write sinter.lock. Prints the
           [languages] line to add if the manifest lacks one. With --hash,
           refuse anything else.
  verify   Run the pack's conformance fixtures: parse the fixture project,
           compare the JSONL byte-for-byte, bind the fixture's runner
           output, and check the wasm import section is empty
  list     Pinned packs with cache status and the tree-sitter and wasi-sdk
           versions each was built with
  info     Descriptor, ID strategy and parameters, evidence formats and
           the suggested runner invocation that produces them, designated
           tag-bearing nodes

EXAMPLES
  sinter pack add rust@1.4.0
  sinter pack verify --all
  sinter pack info markdown
```

### 11.17 `sinter init`

```
sinter init — install the integration the design assumes

USAGE
  sinter init [--hook <harness>]... [--ci <host>] [--target <branch>]
             [--check] [--yes] [--print]

  Idempotent. Writes only what is missing; reports drift in what exists and
  never overwrites a user's edits. Interactive when run bare on a terminal;
  fully scriptable with flags. Touches only tool-owned integration files:

    sinter.toml, sinter.lock     manifest skeleton naming the languages
                                 found in the tree; lock with exact versions
                                 and hashes; enforce = "warn" (§8)
    .gitignore                   the '.sinter/' entry
    .plans/.gitkeep              the plan directory
    refs/sinter/ledger            an empty ledger commit, if absent
    <harness settings>           PostToolUse/SessionStart entries calling
                                 'sinter hook <event>' (--hook claude-code
                                 writes .claude/settings.json;
                                 UserPromptSubmit is offered, off by
                                 default)
    <ci workflows>               PR job, on the host's merge ref with
                                 --base at the target tip (§3.5): check
                                 --diff --gate pr, evidence import, report
                                 as a comment, SARIF upload. The test-run
                                 line is the repo's own bash: init writes a
                                 marked RUN-TESTS step it cannot fill,
                                 seeded with each pack's suggested
                                 invocation, and --check flags it while
                                 unfilled. Both jobs fetch
                                 refs/sinter/ledger explicitly — clones do
                                 not.
                                 Main job: check --gate main, ledger verify,
                                 and the discharge step — append 'discharged'
                                 for merged plans meeting §6.3's condition;
                                 needs push rights to refs/sinter/ledger.
                                 No merge tooling exists: death is a ledger
                                 fact (--ci github writes .github/workflows/)

OPTIONS
  --hook <harness>   claude-code (others by PR to the harness table)
  --ci <host>        github | gitlab
  --target <branch>  Target branch for base computation (default: main)
  --check            Write nothing; exit 1 if anything is missing or drifted
  --yes              Accept defaults without prompting
  --print            Print what would be written, to stdout, and stop

EXAMPLES
  sinter init
  sinter init --hook claude-code --ci github --yes
  sinter init --check
```

### 11.18 `sinter hook`

```
sinter hook — harness hook entrypoint

USAGE
  sinter hook <event> [--harness <h>]

  Registered by 'sinter init --hook'. Reads the harness's hook payload on
  stdin, evaluates the corresponding surface, and answers in the harness's
  protocol. Every event is a filtered 'sinter check' or a 'sinter brief';
  nothing here can see what they cannot. Hooks inform, never block: local
  enforcement is the workflow of whoever runs the turn report (§8).

EVENTS
  post-tool-use   If the payload names a file path (Edit, Write, MultiEdit,
                  NotebookEdit): re-parse the edited file; surface parse
                  errors, typo-tags, bad targets, any finding on facts in
                  that file, and a note when the edit landed outside the
                  active step's scope — each with its fix line. Tools
                  without a path pass silently.
  session-start   'sinter brief' on stdout, which the harness injects as
                  context. Fires on new sessions and after compaction
                  (source: compact), which is the case it exists for.
  user-prompt-    'sinter brief' at a quarter of brief.budget, every turn.
  submit          Smaller and cheaper; registered only if asked at init.

HARNESS PROTOCOLS
  claude-code     stdin JSON (hook_event_name, tool_name, tool_input,
                  session_id, source). PostToolUse feedback is exit 2 with
                  the findings on stderr — the tool already ran, so this
                  surfaces to the agent without undoing anything; a clean
                  file is exit 0. SessionStart and UserPromptSubmit stdout
                  is added to the agent's context. Session state (the
                  declared step) is keyed by session_id.

OPTIONS
  --harness <h>   Protocol to speak (default: claude-code)

EXAMPLES
  echo '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"src/x.rs"}}' \
      | sinter hook post-tool-use; echo $?
```

## 12. The Query Algebra

### 12.1 Universe

A query is evaluated against a **universe** `U`, the fact set produced by scanning one working tree `T` against one base `B`, with one ledger `L`, one evidence set `E` (for `T`'s tree key), and one session `S`. Every fact is an immutable record with a `kind` and a stable `id` (§13.6). A query denotes a subset of `U` and nothing else: no scalars, no tuples, no new facts. Because `U` is finite and every closure is a least fixpoint of a monotone step, every closure terminates; evaluation is a bottom-up fold with fixpoints only where the reference below says so.

`U` is a function of `(T, B, L, E, S)`; two invocations with the same five inputs see the same universe and print the same bytes. The algebra has no access to time, environment, or the network. `ref-state` (networked refs, §5.3) is therefore not a function of the algebra but a separate importer that materializes `refstate` facts into `E`-like scratch for the main CI tier, and is deferred with `@pin`.

### 12.2 Kinds and categories

Every kind belongs to exactly one **category**. `kind(x)` accepts either.

| category | kinds | located? | notes |
|---|---|---|---|
| `node` | `req` `design` `decision` `plan` `step` `test` `site` | yes | `site` is an anonymous `@satisfies`/`@cites` source in code and carries the code hash `ch`; `test` is named by the pack's ID strategy |
| `edge` | `satisfies` `verifies` `refines` `cites` `supersedes` | yes | `src` is a node or a rule; `dst` is a node, a ref, or unresolved |
| `ref` | `ref` | no | one per distinct `ns/id` cited anywhere |
| `promise` | `promise` | yes | one per promissory tag in a plan step |
| `evidence` | `run` `cov` `judgment` | no | keyed to the tree key; `cov` is the site-level join, not raw lines; `judgment` is a judge's or checker's verdict |
| `law` | `rule` `gate` | yes (manifest) | a rule's origin is a `cites` edge with the rule as `src` |
| `ack` | `ack` | yes | live or void |
| `ledger` | `lease` `decline` | no | projections of the ledger: a live lease of another branch's stamped plan (§13.5); a live refusal bound to an extent hash |
| `hunk` | `hunk` | yes | diff mode only; one per hunk of `git diff B`, new-side coordinates |
| `tombstone` | `tombstone` | yes (base coordinates) | a fact present in `B`'s index and absent from `T`'s; carries the old `id`, `kind`, and extent hash |
| `finding` | `finding` | yes (its subject's) | derived; class and subject define identity |

"Located" facts carry `path`, `line`, `col`, `eline`, `ecol`. Only located facts are returned by `path(…)`, `scope(…)`, `historical`, `ambient`, and `acked(…)`.

### 12.3 Syntax

```
query    := expr
expr     := term ( ws ('+' | '-') ws term )*
term     := atom ( ws '^' ws atom )*
atom     := '(' expr ')'
          | 'all'
          | word                              -- saved definition without parameters, or a keyword selector
          | word '(' args ')'                 -- built-in or saved definition
args     := arg ( ',' ws? arg )*
arg      := expr | kinds | name | glob | revspec
kinds    := word ( '|' word )*
name     := slugpat | slugpat '/' slugpat | testpat
slugpat  := [a-z0-9*]+ ( '-' [a-z0-9*]+ )*
testpat  := any run of characters other than ',' and ')' ; quote with "…" otherwise; '*' globs
glob     := gitignore-style pattern; quote with "…" if it contains whitespace or ','
revspec  := 'base' | any git revision
word     := [a-z][a-z0-9-]*
ws       := one or more spaces
```

Lexical rules that matter:

- **Binary operators are whitespace-delimited.** `a - b` is difference; `auth-lockout` is a slug. Without this rule slugs and difference are ambiguous, and slugs are the more common token. `^` and `+` follow the same rule for uniformity. Parentheses do not need whitespace.
- **Precedence:** `^` binds tighter than `+` and `-`, which share a level and associate left. `a + b ^ c - d` is `(a + (b ^ c)) - d`. When in doubt, parenthesize; `--explain` prints the fully parenthesized form.
- **Argument kinds are positional and declared per function** (§12.5). A `name` argument may contain `*` as a glob over the slug (or test ID) alphabet. A `kinds` argument may be a category name.
- **Names are resolved after substitution**: a saved definition's parameters are substituted syntactically (§12.6) before the expression is parsed, so a parameter may stand for an expression, a kind list, a name, or a glob.
- **Keywords** `all`, `active`, `historical`, `ambient`, `base` are reserved as bare words; a saved definition may not shadow a built-in.

### 12.4 Categories as types

Each expression is assigned a **category set** statically, before evaluation:

- `all` → every category. `kind(K)` → the categories of the kinds in `K`. Name selectors → their kind's category. `path`, `historical`, `ambient`, `acked` → every located category. `changed` → every category (tombstones and hunks included). `active` → `{node}`. `findings` → `{finding}`.
- `out`, `in` → `{edge}`. `src`, `dst`, `deps`, `rdeps`, `paths` → `{node, ref, law}` (`src` of a rule's origin edge is a rule). `subject` → every category a finding can be about. `scope` → located categories plus `hunk` (and accepts `lease` in its argument). `promises` → `{promise}`. `met` → `{promise}`. `done` → `{node}`. Predicates, including `declined`, → the category set of their argument, intersected with what they accept. `owed`, `judged` → every category (an obligation's subject is whatever the trigger selected). `triggered` → `{law}`.
- `S + T` → union of category sets; `S ^ T` → intersection; `S - T` → the left's.

Every function declares which categories it **accepts** per argument. Facts of other categories in an argument are dropped silently — `src(all)` is fine and means "sources of every edge." A static **error** is raised only when an argument's category set does not intersect the accepted set: `src(kind(req))` cannot mean anything and is rejected before evaluation with the message `src() accepts edge; argument has category {node}`. This catches definite mistakes without an annotation burden, and it is exactly the exhaustiveness the OCaml implementation gets from a variant of categories.

### 12.5 Function reference

Notation: `S`, `T` range over fact sets; `E` over sets of edges; `P` promises; `R` rules; `K` a kind list; `n` a name pattern; `g` a glob. `src(e)`, `dst(e)`, `rev(e)`, `rev(d)`, `xh(d)` are the fields of an edge or declaration. `⊥` is "unresolved." "Declaration" means a `req`, `design`, or `decision`.

**Selectors**

| function | accepts | denotes |
|---|---|---|
| `all` | — | `U` |
| `kind(K)` | — | `{f : kind(f) ∈ K ∨ category(f) ∈ K}` |
| `req(n)` `design(n)` `decision(n)` `plan(n)` `rule(n)` | — | facts of that kind whose slug or name matches `n` |
| `step(p/s)` | — | steps whose plan slug matches `p` and step slug matches `s` |
| `test(n)` | — | test nodes whose pack-assigned ID matches `n` |
| `ref(ns/id)` | — | ref facts matching |
| `path(g)` | — | located facts whose `path` matches `g` (a fact spanning lines is matched by its `path` alone) |
| `changed(b)` | — | see §12.7; `b` is `base` or a revision |
| `active` | — | the active plan and, if declared, the active step (§6.1); only in-force plans are candidates; `∅` if no plan is active |
| `historical` | — | located facts under a manifest `historical` path |
| `ambient` | — | located facts under a manifest `ambient` path, in a plan file, in the manifest, or in the lockfile |
| `acked(t)` | — | located facts `f` such that the tag-bearing block containing `f` carries a **live** `@ack` whose target `t` applies to `f`: the class or rule name matches, and the ack's subject, if given, equals `f`'s key (`dst` slug for an edge, slug for a node, `id` otherwise) |
| `findings(C)` | — | finding facts whose class ∈ `C` |

**Traversal** (one hop, typed)

| function | accepts | denotes |
|---|---|---|
| `out(K, S)` | `S`: node, law | `{e ∈ edges : kind(e) ∈ K ∧ src(e) ∈ S}` |
| `in(K, S)` | `S`: node, ref | `{e ∈ edges : kind(e) ∈ K ∧ dst(e) ∈ S}` |
| `src(E)` | edge | `{src(e) : e ∈ E}` |
| `dst(E)` | edge | `{dst(e) : e ∈ E ∧ dst(e) ≠ ⊥}` — dangling edges contribute nothing |
| `subject(F)` | finding | `{subject(f) : f ∈ F}` |

**Closures** (least fixpoints; dangling edges are ignored; suspect edges are followed — a stale citation is still a citation)

| function | accepts | denotes |
|---|---|---|
| `deps(K, S)` | node, law | least `X ⊇ S` with `dst(out(K, X)) ⊆ X` |
| `rdeps(K, S)` | node, ref | least `X ⊇ S` with `src(in(K, X)) ⊆ X` |
| `paths(S, T)` | node, ref, law | `deps(edge, S) ^ rdeps(edge, T)`: every node on some path from `S` to `T` over any edge kind. This is Bazel's `allpaths`; `somepath` is omitted because its answer is not a deterministic function of the graph |

**Plan**

| function | accepts | denotes |
|---|---|---|
| `scope(S)` | plan, step, rule, lease | located facts and hunks whose `path` matches the effective scope of some `x ∈ S`. A step's effective scope is its own `@scope` if present, else its plan's; a plan's effective scope is the union of its steps' (its own `@scope` is the default for steps and the bound on them — a step exceeding it is a `bad-scope` finding); a rule's is its `scope` field. `∅` if `S` has no scope-bearing fact |
| `promises(S)` | plan, step | promise facts whose step is in `S` or whose plan is in `S` |
| `met(P)` | promise | promises that are discharged (§6.1: a declaration with that slug within the step's scope; an edge of that kind within scope that is neither dangling nor suspect; a `verifies` edge within scope at rung `passing`, or `unattributed` if the manifest allows) |
| `done(S)` | plan, step | steps all of whose promises are met — or, for a step with no promises, whose scope intersects `changed(base)` — and whose in-scope `verifies` edges are all at rung `passing`/allowed; plans all of whose steps are done and whose in-scope `verifies` edges are all at `passing`/allowed |

**Status predicates** (filters: `pred(S) ⊆ S`)

| function | accepts | keeps `f ∈ S` iff |
|---|---|---|
| `inforce(S)` | any | for a declaration: `f` carries no status tag and no live `@supersedes` edge has `dst = f` (live: the edge's source is in force and, if its kind is approval-gated, approved, §3.3 — a fixpoint over supersession chains; on a `supersedes` cycle every member is treated as in force and retired by nothing, and the `cycle` finding blocks, so the state is loud rather than guessed). For a plan, its steps, and its promises: the ledger holds no `discharged` or `abandoned` entry for the plan (§6.3). Every other kind: kept |
| `approved(S)` | any | `f` is a declaration of a gated kind with a ledger stamp for `(slug, rev, xh)`; or a declaration of a non-gated kind; or a plan whose current commitment set is approved against its latest stamped set (§13.7 containment, not `csh` equality); or a step of an approved plan; or any other kind |
| `bumped(S)` | node | `f` is a declaration absent from `B`'s index, or present with `rev_B(f) < rev_T(f)` |
| `declined(S)` | node | `f` is a declaration or plan with a live `decline` fact: one whose recorded hash equals `f`'s current extent hash (declarations) or commitment-set hash (plans) |
| `blocked(P)` | promise | `p` targets a slug declared nowhere in `T` but promised for declaration by some live `lease` — an ordering fact, reported instead of `dangling` |

**Edge predicates**

| function | keeps `e ∈ E` iff |
|---|---|
| `suspect(E)` | `rev(e) ≠ ⊥ ∧ dst(e) ≠ ⊥ ∧ dst(e)` is a declaration `∧ rev(dst(e)) ≠ rev(e)` |
| `dangling(E)` | `dst(e) = ⊥` — no declaration has the slug, or the ref's namespace is undeclared or its id fails the pattern |

**Evidence predicates** partition `kind(verifies)`: every verifies edge satisfies exactly one, tested in this order. `t = src(e)`, `sites(e) = src(in(satisfies, dst(e)))` minus test nodes (a test's own `@satisfies` never connects itself), `runs(t)` the run facts for `t` at `T`'s tree key, `cov(t, s)` the attributed cov fact for `(t, s)`, `agg(s)` the aggregate cov fact for `s`.

| function | keeps `e ∈ E` iff |
|---|---|
| `orphan(E)` | `kind(t) ≠ test` — the comment attached to something `tests.scm` does not capture |
| `neverran(E)` | `runs(t) = ∅` |
| `failed(E)` | some `r ∈ runs(t)` has `status ∈ {fail, error, skip}` |
| `disconnected(E)` | all runs pass, `sites(e) ≠ ∅`, and either attributed coverage for `t` exists and `∀s ∈ sites(e): cov(t, s).hit = 0`, or only aggregate coverage exists and `∀s ∈ sites(e): agg(s).hit = 0` — the run as a whole never touched the sites, so neither did `t` |
| `unattributed(E)` | all runs pass, `sites(e) ≠ ∅`, no attributed coverage for `t`, and some `agg(s).hit > 0` or no coverage at all was imported |
| `passing(E)` | all runs pass and either `sites(e) = ∅` (nothing to connect to; `uncovered(satisfies)` reports the target separately) or some `cov(t, s).hit > 0` |

**Law**

| function | accepts | denotes |
|---|---|---|
| `owed(R)` | law | `⋃_{r ∈ R} ( eval(trigger(r)) - eval(discharge(r)) )` — the obligation subjects of each rule. Rule expressions are evaluated in the same universe; a rule whose trigger or discharge mentions `owed` is rejected at manifest load (no recursion through the law) |
| `triggered(R)` | law | `{r ∈ R : eval(trigger(r)) ≠ ∅}` |
| `judged(n)` | — | subjects with a `judgment` evidence fact for rule `n` whose verdict is `pass` and whose recorded hash matches the subject's current extent (or commitment-set) hash — the discharge selector for judged rules |

For an `acked` discharge, ack liveness is `subject ∈ eval(trigger)` — the discharge side never re-enters (§3.3); no circularity.

**Set operators.** `S + T` union, `S ^ T` intersection, `S - T` difference, all over fact identity.

That is 37 names. Grouped as above they fit on two pages, and every one is either a comprehension over fields the JSONL already carries or a least fixpoint over a finite graph. There are no user-defined functions, no recursion beyond the three built-in closures and the two fixpoint predicates, no arithmetic, and no strings other than names and globs.

### 12.6 Saved definitions

A saved definition is a name, an optional parameter list, and an expression. Built-ins ship in the tool; the manifest adds or overrides in `[findings]`:

```toml
[findings.uncovered]
params = ["e"]
expr   = "kind(req|design) ^ inforce(all) - dst(in($e, all))"

[findings.unstamped-design]
expr   = "kind(design) ^ inforce(all) - approved(all)"
```

Invocation is `uncovered(verifies)` or bare `unstamped-design`. Parameters are substituted as text for `$name` tokens before parsing; a parameter may therefore be an expression, a kind list, a name, or a glob, and the result is parsed and category-checked as a whole. Definitions may reference other definitions; cycles are a manifest load error. A definition with `tiers` (per gate), and optionally `ackable`, `detail`, and `fix` (the mechanical fix class), is a finding class and is evaluated by `check`; one without `tiers` is query-only. There is one table, because a finding is just a definition someone decided to enforce. Overriding a built-in finding's `expr` is allowed and is itself a `law-touched` finding on the diff that does it.

### 12.7 `changed(base)` and diff mode

`changed(b)` is the fact set touched by `git diff b` against the working tree (untracked files count as wholly added). "Touched" is defined per category, because the naive definition — extent intersects a hunk — is wrong for declarations in both directions (an `@ack` line added inside a section is not a change of meaning; a section deleted wholesale leaves nothing to intersect):

| category | `f ∈ changed(b)` iff |
|---|---|
| `req` `design` `decision` | `f ∉ index(b)`, or `xh_b(f) ≠ xh_T(f)` (the normalized extent hash, §3.4) |
| `plan` `step` `promise` | the plan's commitment set differs from `index(b)`'s for that plan, or the fact is new |
| other located facts | new, or the fact's line span intersects a hunk's new-side span |
| `hunk` | always (hunks exist only relative to `b`) |
| `tombstone` | always |
| `edge` | new, or its line intersects a hunk, or `dst(e)` is a tombstone — a citation whose target vanished is changed even if its bytes are not |
| `evidence` `ref` | never |

`b` may be `base` (the `--base` value) or a git revision. Evaluating `changed(x)` for an `x` other than the base requires a second index for `x`, built and cached on demand.

**Diff mode** (`check --diff`) is **baseline subtraction**: `check --diff` reports `F(T) - F(b)` where `F(x)` is the finding set of tree `x` and subtraction is by finding identity (§13.6). `F(b)` is evaluated on the base tree read straight from git objects — no checkout — with the same ledger and an **empty evidence set**: evidence-ladder findings at the base are all `never-ran`, so a pre-existing `disconnected` test surfaces as introduced on the first PR that measures it, a one-time cost of first light, accepted. A finding that existed at the base and still exists is debt, not a violation; a finding absent at the base is what this diff introduced. This subsumes the intersection rule for every class where it was right and repairs it for `dangling` and `disendorsed`, where the introduced finding sits on a line the diff never touched. Diff-relative classes — `rev-owed`, `unmapped-work`, `law-touched`, `code-drift`, `renamed` — have `F(b) = ∅` by construction and appear in both modes.

### 12.8 Built-in finding definitions

`check` is the union of these. `expr` is the definition where the class is expressible; *engine* marks classes the scanner or adjudicator emits directly because they concern malformed input or two-tree comparisons the algebra does not model (their subjects and details are still ordinary finding facts). Two subtractions are engine steps applied after evaluation to every class, never written into definitions: `historical` facts generate no findings of any class (§3.6), and live `@ack`s discharge findings of ackable classes (liveness judged pre-subtraction, §3.3). A third rule governs the evidence ladder: `never-ran`, `failed`, `disconnected`, and `unattributed` are evaluated only when an evidence set exists for the tree — the tool judges measurements that exist and never demands one nobody took; wanting the measurement is expressed by importing it (PR CI does; a main job may), and `status --done` refuses without one, because death requires measurement. The `rung` field reads `never-ran` either way; only the finding is withheld. A fourth: facts belonging to a plan not in force — the plan, its steps, its promises — generate no findings; a dead plan is record, not agreement (§6.3). Tiers are the shipped defaults for `(turn, pr, main)`; every class ships at `warn` under the rollout cap and is promoted per §8. `A` = ackable, `F` = mechanical fix exists.

| class | subject | definition | mode | A | F | tiers |
|---|---|---|---|---|---|---|
| `parse-error` | file | *engine*: a governed file its pack cannot parse; the whole file's facts are absent | tree | · | · | warn, block, block |
| `typo-tag` | line | *engine*: an unknown `@word` within Damerau–Levenshtein distance 2 of the vocabulary, the pack's foreign vocabulary exempt (§3.2) | tree | · | F | warn, warn, warn |
| `bad-target` | tag | *engine*: a slug or ref failing its pattern, or an undeclared namespace | tree | · | · | block, block, block |
| `duplicate` | node | *engine*: two declarations of one slug, two plans of one slug (dead ones included — plan slugs are permanent), or two steps of one plan slugifying identically | tree | · | · | block, block, block |
| `bad-scope` | step | *engine*: a step whose `@scope` is not contained in its plan's (§13.7 containment) | tree | · | · | block, block, — |
| `misplaced-plan` | node | *engine*: a `@plan` declaration outside `.plans/**` (§6.1) | tree | · | · | block, block, block |
| `unpinned` | edge | *engine*: a `satisfies`, `verifies`, `refines`, or `supersedes` edge with `rev = ⊥` | tree | · | F | block, block, block |
| `dangling` | edge | `dangling(kind(edge))`, minus edges whose target a lease promises to declare — those surface as `blocked-on` on the promise instead (*engine* performs the subtraction) | tree | · | · | block, block, block |
| `renamed` | edge | *engine*: dangling edges whose slug has a tombstone in `B` and a new declaration in `T` with equal `xh` | diff | · | F | block, block, block |
| `suspect` | edge | `suspect(kind(edge))` | tree | · | F | block, block, block |
| `rev-owed` | node | `kind(req\|design\|decision) ^ changed(base) - bumped(all)` | diff | · | F | block, block, block |
| `cycle` | node | *engine*: a cycle in `supersedes` or `refines` | tree | · | · | block, block, block |
| `code-drift` | site | *engine*: `ch` changed since base while the site's comment `xh` did not (§3.4); the judge's sampling frame. Not ackable: the class is diff-relative, so an ack would void on merge | diff | · | · | warn, warn, — |
| `declined` | node | `declined(kind(req\|design\|decision\|plan))` — a live refusal; the detail is the reason | tree | · | · | warn, block, — |
| `unratified-req` | edge | `in(satisfies\|verifies, kind(req) - approved(all))` — a kind outside `approve` counts approved, so the class self-silences | tree | · | · | block, block, block |
| `unratified-design` | edge | `in(satisfies\|verifies, kind(design) - approved(all))` | tree | · | · | warn, warn, warn |
| `unstamped` | node | `kind(req\|design\|decision) ^ inforce(all) - approved(all)` — informational; the subject is what `approve` will show | tree | · | · | off, warn, warn |
| `amendment` | plan | `kind(plan) ^ inforce(all) - approved(all)`; *engine* supplies the set delta as detail | tree | · | · | warn, block, — |
| `disendorsed` | edge | `kind(cites) - dangling(all) - in(cites, inforce(all))` — includes a rule's origin edge, hence "law resting on withdrawn reasoning" | tree | A | · | warn, block, block |
| `stale-ack` | ack | *engine*: an `@ack` whose hash no longer matches its block, or whose target names nothing at that site | tree | · | F | block, block, block |
| `orphan` | edge | `orphan(kind(verifies))` | tree | · | · | block, block, block |
| `never-ran` | edge | `neverran(kind(verifies)) ^ scope(inforce(kind(plan)))` at turn; `neverran(kind(verifies))` at pr and main | tree | · | · | warn, block, block |
| `failed` | edge | `failed(kind(verifies))` | tree | · | · | block, block, block |
| `disconnected` | edge | `disconnected(kind(verifies))` | tree | A | · | warn, block, block |
| `unattributed` | edge | `unattributed(kind(verifies))` | tree | · | · | off, warn, warn |
| `uncovered` | node | `uncovered(verifies) + uncovered(satisfies)` — incompleteness; never blocks turn-end | tree | · | · | off, warn, warn |
| `unmet` | promise | `unmet(active)` where `unmet(p) = promises($p) - met(promises($p))` — incompleteness; enforced only by `status --done` | tree | · | · | off, off, — |
| `promise-out-of-scope` | promise | *engine*: a promise met only by residue outside its step's scope | tree | · | · | warn, warn, — |
| `unverified-promise` | promise | *engine*: a promised `req`/`design` with no promised `verifies` of it in the same plan (§6.6) | tree | · | · | warn, warn, — |
| `promise-collision` | promise | *engine*: a promised declaration whose slug exists in `index(B)` or is promised by a lease | tree | · | · | block, block, — |
| `scope-overlap` | step | *engine*: two steps of one plan with intersecting scopes and intersecting promise sets | tree | · | · | warn, warn, — |
| `blocked-on` | promise | `blocked(promises(kind(plan)))` — reported in place of `dangling` for the citation, with the lease and step named (§6.7) | tree | · | · | off, warn, — |
| `lease-overlap` | step | *engine*: a step's scope intersects a live lease's scope on another branch | tree | · | · | warn, warn, — |
| `unmapped-work` | hunk | `kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - scope(triggered(kind(rule))) - ambient`; *engine* also exempts hunks that are wholly the tool's own medicine — tag-line re-pins and `@ack` insertions or deletions | diff | · | · | block, block, — |
| `rule-owed` | any | `owed(kind(rule))`, one finding per `(rule, subject)`; ackable iff the rule's discharge is `acked`; a rule's `tiers` overrides the class's | tree | A* | · | warn, block, block |
| `law-touched` | law | `kind(rule\|gate) ^ changed(base)` — non-disableable; always reported, never blocks | diff | · | · | warn, warn, warn |
| `undischarged-plan` | plan | *engine*: an in-force plan on the target branch failing the §6.3 discharge condition — merged incomplete; a plan meeting it is discharged by main CI, not a finding | tree | · | · | —, —, block |
| `ledger-broken` | ledger | *engine*: `ledger verify` fails | tree | · | · | —, —, block |
| `pack-drift` | pack | *engine*: a pinned pack's hash does not match the cache | tree | · | · | exit 3 everywhere |

`uncovered`, `unmet`, and `unstamped` are the incompleteness classes: they exist so `status` and the death gate can see them, and the turn report never lists them as violations (§8). Everything else is a violation or a health signal.

### 12.9 Evaluation, ordering, errors

- Evaluation is bottom-up over the parse tree. Selectors are answered from per-kind indexes; traversals from adjacency maps built once per scan; fixpoints by worklist. A saved definition is expanded once per invocation site, not memoized across differing parameters.
- Results print in order `(kind, path, line, col, id)` with unlocated facts after located ones, ordered by `id`. `--order` reorders; it never changes the set.
- Static errors (category mismatch, unknown function, arity, unknown saved definition, parameter count) exit 2 before evaluation and name the offending subexpression. A name selector that matches nothing is not an error — it denotes `∅` — because that is what `req(auth-lockout)` should mean on a branch that has not written it yet. `changed(x)` for an `x` git cannot resolve exits 3.

### 12.10 Worked evaluation

On the plan from §6.1 after the second step has landed but before tests exist:

```
$ sinter query 'promises(active) - met(promises(active))'
.plans/auth-lockout.md:19:1: promise auth-lockout/verify-against-the-reqs verifies auth-lockout
.plans/auth-lockout.md:20:1: promise auth-lockout/verify-against-the-reqs verifies lockout-notify

$ sinter query 'uncovered(verifies)'
docs/auth.md:12:1: req auth-lockout v2
docs/auth.md:31:1: req lockout-notify v1

$ sinter query 'kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - scope(triggered(kind(rule))) - ambient'
src/session/store.rs:88:1: hunk +14/-3
```

The last line is a hunk outside every step's scope — the agent simplified a store the plan never mentioned. It is exactly what the turn report names as a violation — the state an orchestrator refuses to accept a hand-back in. The honest resolutions are the two the monotone rule allows: revert it (`git checkout src/session/store.rs`), or widen the plan's scope in `.plans/auth-lockout.md`, which routes to a stamp. What the report will not bless is the hunk staying while the plan stays silent.

## 13. JSONL Interchange

### 13.1 Canonical form

One fact per line. Each line is a JSON object canonicalized per RFC 8785 (JCS): keys sorted by UTF-16 code units, no insignificant whitespace, strings escaped per JCS, UTF-8, LF terminated. The schema restricts values so that JCS is trivial to implement and impossible to get subtly wrong:

- **Value types:** string, integer in `[-(2^53-1), 2^53-1]`, boolean, or an array of those. **No floats, no nulls, no nested objects.** An absent value is an omitted key, never `null`.
- **Strings** are NFC-normalized where they come from file text; ids and paths are used as-is.
- **Paths** are repository-relative with forward slashes, no leading `./`.
- **Hashes** are lowercase hex. `xh` is 64 hex characters (SHA-256). The tree key and git revisions are 40 hex characters.

A file of facts is sorted by `(kind, path, line, col, id)`; unlocated facts sort after located ones by `id`. The first line is the `index` header (§13.8). Two scans of the same `(T, B, L, E, S)` produce byte-identical output; conformance fixtures compare every line after the header.

The schema version is the integer `v` on every line. It is bumped only for incompatible changes to a kind's required fields or identity; adding an optional field is not a bump.

### 13.2 Envelope

Every fact carries:

| field | type | meaning |
|---|---|---|
| `v` | int | schema version (`1`) |
| `kind` | string | one of the kinds in §12.2, or `index`, `summary`, or a ledger kind (§13.7) |
| `id` | string | stable identity (§13.6) |
| `pack` | string | for facts extracted from a governed file: the pack name that produced it |

Located facts add:

| field | type | meaning |
|---|---|---|
| `path` | string | file |
| `line` `col` | int | 1-based start |
| `eline` `ecol` | int | inclusive end line; exclusive end column |

For a declaration in markdown, the span is the tag line; the extent (whole section) is separate (`xline`, `xeline`) so that tools can highlight the tag without highlighting pages of prose.

Fields marked *derived* below are computed from the ledger, evidence, session, or base — not from the file — and are present so that `jq` users need not re-derive them. They are included in conformance comparison, which is why fixtures ship their own ledger and evidence.

### 13.3 Nodes

**`req` / `design` / `decision`**

| field | type | meaning |
|---|---|---|
| `slug` | string | |
| `rev` | int | `N` from `vN` |
| `xh` | string | extent hash (§3.4) |
| `xline` `xeline` | int | extent span |
| `title` | string | markdown: heading text; code: omitted |
| `desc` | string | description per §3.2; omitted if empty |
| `status` | string | `deprecated` `rejected` `deferred`; omitted if none |
| `inforce` | bool | *derived* |
| `approved` | bool | *derived* |
| `stamp` | string | *derived*: ledger stamp id when approved |
| `gated` | bool | whether the manifest gates this kind on approval |
| `declined` | bool | *derived*: a live decline exists for `(slug, xh)` |

```json
{"approved":true,"col":1,"desc":"Five consecutive failures within ten minutes freeze the account.","ecol":21,"eline":13,"gated":true,"id":"req:auth-lockout","inforce":true,"kind":"req","line":13,"pack":"markdown","path":"docs/auth.md","rev":2,"slug":"auth-lockout","stamp":"s-41","title":"Lock account after 5 failed attempts","v":1,"xeline":29,"xh":"9f3a…","xline":12}
```

**`plan`**

| field | type | meaning |
|---|---|---|
| `slug` `title` | string | |
| `scope` | array of string | plan-level globs |
| `approved` | bool | *derived*: current commitment set approved against the last stamp (§13.7) |
| `stamp` | string | *derived* |
| `active` | bool | *derived* from session |
| `live` | bool | *derived*: no `discharged` or `abandoned` ledger entry for the plan (§6.3); its in-force state |
| `csh` | string | commitment-set hash: SHA-256 over a canonical, step-name-free form — sorted `(word, target, effective step scope)` triples plus the plan scope — so free renames leave it unchanged and a `decline` bound to it survives them |
| `declined` | bool | *derived* |

**`step`**

| field | type | meaning |
|---|---|---|
| `plan` | string | plan slug |
| `slug` `title` | string | slug derived per §6.1 |
| `scope` | array of string | *effective* scope |
| `own_scope` | bool | whether the step declared its own `@scope` |
| `refactor` | bool | no promises |
| `met` `total` | int | *derived* promise counts |
| `done` | bool | *derived* |
| `active` | bool | *derived* |

**`test`**

| field | type | meaning |
|---|---|---|
| `name` | string | the ID the pack's strategy produced — the same string the runner reports |
| `parents` | array of string | `describe`-style ancestry where the language has it, outermost first |
| `dline` `deline` | int | span of the test's body |

**`site`**

| field | type | meaning |
|---|---|---|
| `name` | string | name of the attached definition, if the pack captured one — qualified (impl, class, module path) where the language nests, so two `new`s in one file stay distinct |
| `node` | string | tree-sitter node type of the attached definition (`function_item`, `class_definition`) |
| `dline` `deline` | int | span of the attached definition's body — the frame the `cov` join measures against |
| `ch` | string | code hash: SHA-256 over the attached definition's pack-normalized body |

### 13.4 Edges, refs, promises

**edge** (`kind` is `satisfies` `verifies` `refines` `cites` `supersedes`)

| field | type | meaning |
|---|---|---|
| `src` | string | id of the source fact (a node or a rule) |
| `target` | string | the target as written: slug or `ns/id` |
| `dst` | string | *derived*: id of the resolved target; omitted when dangling |
| `rev` | int | pinned revision; omitted when unpinned |
| `desc` | string | inline description; omitted if empty |
| `suspect` `dangling` | bool | *derived* |
| `rung` | string | `verifies` only, *derived*: `orphan` `never-ran` `failed` `disconnected` `unattributed` `passing` |
| `live` | bool | `supersedes` only, *derived* |

Tags inside plan files never produce edges; they are `promise` facts (§6.1).

```json
{"col":5,"dst":"req:auth-lockout","ecol":31,"eline":40,"id":"verifies:test:auth::lockout::tests::locks_after_five_failures->auth-lockout","kind":"verifies","line":40,"pack":"rust","path":"src/auth/lockout.rs","rev":2,"rung":"passing","src":"test:auth::lockout::tests::locks_after_five_failures","target":"auth-lockout","v":1}
```

**`ref`**

| field | type | meaning |
|---|---|---|
| `ns` | string | namespace |
| `ref` | string | id within the namespace |

Unlocated; one per distinct target. (`refstate`, the networked read, is deferred with `@pin`.)

**`promise`**

| field | type | meaning |
|---|---|---|
| `plan` `step` | string | slugs |
| `word` | string | `req` `design` `decision` `satisfies` `verifies` `refines` `cites` `supersedes` |
| `target` | string | as written |
| `met` | bool | *derived* |
| `by` | string | *derived*: id of the discharging fact when met |
| `out_of_scope` | bool | *derived*: residue that would discharge it exists only outside the step's scope; `met` stays false (§6.1) |

Duplicate promissory tags within one step collapse to a single promise fact.

### 13.5 Evidence, law, acks, hunks, tombstones

**`run`** (unlocated)

| field | type | meaning |
|---|---|---|
| `test` | string | test fact id; a run that binds to no test fact is not emitted as a fact but is reported by `evidence import` |
| `status` | string | `pass` `fail` `error` `skip` — several artifacts for one test merge to the worst |
| `tree` | string | tree key |
| `sources` | array of string | artifact paths, as imported |
| `ms` | int | duration, when the artifact reports one |

**`cov`** (unlocated; the site-level join, not raw line data)

| field | type | meaning |
|---|---|---|
| `test` | string | test fact id, or `*` for aggregate |
| `site` | string | site fact id |
| `hit` `of` | int | executable lines inside the site's attached definition that were hit / that exist |
| `attributed` | bool | `false` iff `test` is `*` |
| `tree` | string | tree key |

**`judgment`** (unlocated; written by the judge or an external checker into the evidence directory, never the tree)

| field | type | meaning |
|---|---|---|
| `rule` | string | rule name |
| `subject` | string | fact id judged |
| `verdict` | string | `pass` `fail` |
| `judge` | string | model or program identifier |
| `hash` | string | the subject's extent (or commitment-set) hash at judgment; live while it matches — bound to the text, not the tree, so unrelated edits do not void it |
| `reason` | string | one line |

**`lease`** (unlocated; projected from the ledger for each stamped plan on another branch that is neither discharged nor abandoned and whose branch existed on the remote at the last fetch)

| field | type | meaning |
|---|---|---|
| `plan` | string | plan slug |
| `branch` | string | branch the stamp was written from |
| `stamp` | string | latest stamp id |
| `scope` | array of string | union of stamped step scopes |
| `declares` | array of string | slugs the lease promises to declare |
| `stamped` | string | RFC 3339 |

**`decline`** (unlocated; projected from the ledger, live entries only)

| field | type | meaning |
|---|---|---|
| `subject` | string | fact id |
| `hash` | string | extent or commitment-set hash the refusal was bound to |
| `reason` | string | |
| `by` `ts` | string | |
| `entry` | string | ledger entry id |

**`rule`** (located in the manifest)

| field | type | meaning |
|---|---|---|
| `name` `origin` `trigger` `discharge` | string | as declared |
| `via` | string | `checked` `judged` `acked` — inferred from `discharge` |
| `scope` | array of string | |
| `triggered` | bool | *derived* |
| `owed` | int | *derived* obligation count |

**`gate`** (located in the manifest, one per `(gate, class)` pair, defaults materialized)

| field | type | meaning |
|---|---|---|
| `gate` | string | `turn` `pr` `main` |
| `class` | string | finding class |
| `tier` | string | `off` `warn` `block` |
| `default` | bool | `true` when not set in the manifest |

**`ack`**

| field | type | meaning |
|---|---|---|
| `block` | string | id of the block's primary fact: the declaration, site, or test the block belongs to |
| `target` | string | as written, e.g. `disendorsed cache-ttl` or `ste-docs` |
| `hash` | string | as written |
| `live` | bool | *derived* |
| `void` | string | *derived*: `hash` or `target`; omitted when live |
| `for` | string | *derived*: id of the finding discharged, or the rule, when live |

**`hunk`** (diff mode; new-side coordinates; a pure deletion has `line = eline = ` the line after the deletion and `added = 0`)

| field | type | meaning |
|---|---|---|
| `added` `removed` | int | |
| `ambient` | bool | *derived* |
| `mapped` | array of string | *derived*: ids of steps or rules whose scope covers the hunk; empty when unmapped |

**`tombstone`** (base coordinates)

| field | type | meaning |
|---|---|---|
| `of` | string | the kind of the vanished fact |
| `was` | string | its id at the base |
| `slug` `rev` `xh` | | for declarations, so `renamed` can be computed |

### 13.6 Findings and identity

**`finding`** (located at its subject)

| field | type | meaning |
|---|---|---|
| `class` | string | §12.8 |
| `subject` | string | id of the fact the finding is about |
| `rule` | string | `rule-owed` only |
| `detail` | string | one line, human-facing; deterministic |
| `fix` | string | the exact `@ack` line or a one-line instruction; omitted when none |
| `ackable` | bool | |
| `acked` | bool | present only under `--acked` |
| `tier` `gate` | string | tier under the gate `check` ran with |
| `mode` | string | `tree` or `diff` |

**Identity.** Ids are what makes baseline subtraction, `@ack` targeting, and SARIF fingerprints work across line shifts, so they are content-derived wherever content exists and positional only as a last resort:

| kind | id | notes |
|---|---|---|
| `req` `design` `decision` `plan` | `<kind>:<slug>` | |
| `step` | `step:<plan>/<step>` | |
| `test` | `test:<name>` | `name` may contain spaces; quoted in line output |
| `site` | `site:<path>#<name>` | `name` from the pack's `defs.scm`; fallback `site:<path>@L<line>` is positional and marked with `"positional":true` |
| edges | `<kind>:<src-id>-><target>` | parse from the right: `target` cannot contain `->` |
| `ref` | `ref:<ns>/<id>` | |
| `promise` | `promise:<step-id>:<word>:<target>` | parse from the right |
| `run` | `run:<test-id>@<tree>` | |
| `cov` | `cov:<test-id or *>@<site-id>` | |
| `judgment` | `judgment:<rule>:<subject-id>@<hash>` | |
| `lease` | `lease:<plan>@<branch>` | |
| `decline` | `decline:<entry-id>` | |
| `rule` | `rule:<name>` | |
| `gate` | `gate:<gate>/<class>` | |
| `ack` | `ack:<block-id>:<target>` | block-anchored, not line-anchored |
| `hunk` | `hunk:<path>:<line>-<eline>` | positional by nature |
| `tombstone` | `tombstone:<was>` | |
| `finding` | `finding:<class>:<subject-id>[:<rule>]` | |

An id is stable under: re-indentation, reformatting, line shifts, and re-pinning. It changes under: slug rename (by design — rename is death plus birth), moving a site to a different named definition, and retargeting an edge.

**SARIF mapping** (`--sarif`): `class` → `ruleId`; `tier` → `level` (`warn` → `warning`, `block` → `error`, `off` → not emitted); location → `physicalLocation` with `artifactLocation.uri` and `region`; `id` → `partialFingerprints.sinterId/v1`; mechanical fixes → `fixes[]` with the patch hunk; `detail` → `message.text`; `fix` for ackable findings → a second `message` line.

### 13.7 Ledger entries

The ledger is a JSONL file `ledger.jsonl` in the tree of `refs/sinter/ledger`. Every `approve` run appends lines and commits with the previous tip as parent. Verification (§11.13) checks fast-forward and byte-prefix accretion. Timestamps and authorship are legitimate here — the ledger is history, not a derivation.

Four writers exist: `approve` writes `stamp` (with its `stamped-*` lines), `decline` writes `decline`, `ledger abandon` writes `abandoned`, and main CI writes `discharged` (§6.3). Entry ids are content-derived: `e-` plus the first twelve hex digits of SHA-256 over the entry's canonical bytes with the `id` key absent. Two writers can never mint one id for different entries, so replay after a lost push race is a set union (`ledger push --replay`); accretion is checked per file — every commit's ledger is a byte-prefix extension of its parent's, and ids never repeat. Where order matters (a decline superseded by a later stamp), `ts` decides, never file position. When `[ledger].sign` is set, every ledger commit is signed and `ledger verify --signers` enforces the allowlist.

**Every entry** carries `id`, `kind`, `v`, `by`, `ts` (RFC 3339, UTC), `head` (the commit the writer stood on), `branch`, and `tool`.

**`stamp`**

| field | type | meaning |
|---|---|---|
| `subject` | string | `req:auth-lockout`, `plan:auth-lockout`, … |
| `rev` `xh` | | declarations only |
| `csh` | string | plans only: commitment-set hash (§13.3) |
| `note` | string | omitted if none |

**Revision reservation.** `approve` refuses to write a `stamp` for `(slug, rev)` when the ledger already holds a stamp for that pair with a different `xh`; the refusal names the earlier entry and branch. A stamp with equal `xh` is idempotent and skipped.

**`decline`**

| field | type | meaning |
|---|---|---|
| `subject` | string | |
| `hash` | string | `xh` or `csh` at the moment of refusal |
| `reason` | string | required |

A decline is live while the subject's current hash equals `hash` and no later stamp of the subject exists. It is never deleted; a later stamp — at a different hash, or at the same one, the human overriding their own refusal after an `approve` prompt — supersedes it in effect, and `compile history` shows both.

**`discharged`**

| field | type | meaning |
|---|---|---|
| `subject` | string | `plan:<slug>` |
| `stamp` | string | the stamp the plan died under |
| `merge` | string | merge commit |
| `report` | string | SHA-256 of the report compiled at discharge |

**`abandoned`**

| field | type | meaning |
|---|---|---|
| `subject` | string | `plan:<slug>` |
| `reason` | string | required |

Abandonment kills the lease and every `blocked-on` resting on it; `compile residual-plan` remains the path back for whatever the plan still owed.

**`stamped-scope`** — one per glob, plan-level when `step` is omitted

| field | type |
|---|---|
| `stamp` | string |
| `step` | string (slug), omitted for plan scope |
| `glob` | string |

**`stamped-promise`** — one per promise

| field | type |
|---|---|
| `stamp` | string |
| `step` | string |
| `word` `target` | string |

**Commitment-set comparison.** The current set `C` and the stamped set `C₀` are compared as follows; `approved(plan)` iff every clause holds.

1. The multiset of `(word, target)` over all promises is equal.
2. The plan scope is contained: `scope(C) ⊆ scope(C₀)`.
3. For each promise `p`, matched by `(word, target)` (matching among duplicates is by step slug first, then arbitrary — duplicates are rare and identical in effect), the effective scope of `p`'s step in `C` is contained in the effective scope of its step in `C₀`.

**Glob containment** `G' ⊆ G` is decided structurally and conservatively: every glob in `G'` either appears verbatim in `G`, or is a literal path or path prefix that some glob in `G` matches (checked by matching the literal against the glob), or is `<g>/<segments>` for some `<g>/**` in `G`. Anything the checker cannot prove is treated as widening. This is decidable, deterministic, and errs toward asking the human, which is the correct direction for an approval gate.

The consequences: renaming steps is free (clause 3 matches by promise, not by step); reordering is free; splitting is free when each fragment keeps or narrows its scope; merging is free when the merged scope equals the originals' and stamped otherwise; any promise added or removed fails clause 1. This is the precise form of §6.2.

**`pin`** (deferred): `{"kind":"pin","stamp":…,"ref":"gh/42","hash":…}`.

### 13.8 Header and summary

**`index`** — first line of every scan; excluded from conformance comparison

| field | type | meaning |
|---|---|---|
| `tree` | string | tree key |
| `base` | string | resolved base revision |
| `target` | string | target branch |
| `ledger` | string | ledger tip commit; omitted if the ref is absent |
| `evidence` | bool | whether evidence exists for `tree` |
| `packs` | array of string | `name@version#hash`, from `sinter.lock` |
| `tool` | string | version |
| `mode` | string | `tree` or `diff` |

**`summary`** — first line of `status --json`

| field | type |
|---|---|
| `plan` `step` | string, omitted if none |
| `done` | bool |
| `steps_done` `steps_total` | int |
| `block` `warn` | int (finding counts under the turn tier set) |
| `unmapped` | int (hunks) |
| `owed` | int (rule obligations) |
| `evidence_fresh` | bool |
| `bumps` | int (declarations bumped since base) |
| `acks_live` `acks_void` | int |
| `declines` | int (live, in scope) |
| `leases` `blocked` | int |
| `code_drift` | int |
| `law_touched` | bool |

### 13.9 Conformance

A pack's fixture directory contains a tiny project, `expected.jsonl`, a fixture ledger (`ledger.jsonl`), and real runner and coverage artifacts with attribution. `sinter pack verify` scans the fixture with the fixture ledger and evidence, drops the header line, and requires byte equality with `expected.jsonl`. Because derived fields are included, the fixture exercises binding and the evidence ladder end to end, not just parsing. A tool release that changes any derived field's semantics must regenerate every pack's fixture, which is the intended friction.

## 14. Manifest Reference

`sinter.toml` is pure configuration, and short. Everything with a sensible default is absent; `sinter init` writes only what it had to choose. The whole file is inside the boundary (§5.1): edits to `[gates]`, `[findings]`, `[rules]`, and `approve` are `law-touched` on any diff, always.

```toml
enforce    = "warn"                        # rollout cap: nothing blocks or exits 1 until this line goes or a class is promoted below (§8)
approve    = ["req"]                       # kinds the ledger gates; kinds not listed count approved (§12.8)
historical = ["docs/devlog/**"]            # citations resolve and render; no findings (.plans/*.log.md is built-in)
ambient    = ["Cargo.lock", "**/generated/**"]   # exempt from scope confinement; counted in the report

[languages]                                # constraints here; exact versions and hashes in sinter.lock
rust   = "1.4"
python = "1.2"

[languages.markdown]                       # long form: override the pack's default file set
version = "1.0"
files   = ["docs/**/*.md", ".plans/*.md"]  # the pack's default is **/*.md

[refs]                                     # namespace → anchored id pattern; gh is built in
jira = "[A-Z]+-[0-9]+"

[gates.turn]                               # per-class promotion past the cap; omitted → shipped default (§12.8)
unmapped-work = "block"
rev-owed      = "block"
[gates.pr]
disconnected  = "block"

[rules.ste-docs]                           # standing law (§7)
origin    = "ste-adoption"
trigger   = "kind(req|design) ^ path(docs/**) ^ changed(base)"
discharge = "acked(ste-docs)"                # acknowledged discharge: an @ack at the site

[rules.issue-linked]
origin    = "issues-are-truth"
trigger   = "kind(req) ^ changed(base)"
discharge = "src(out(cites, kind(req)) ^ in(cites, ref(gh/*)))"   # checked discharge: the graph says so

[findings.decision-uncited]                # a repo-defined finding; without tiers it is query-only
expr    = "kind(decision) ^ inforce(all) - dst(in(cites, all))"
detail  = "decision in force that nothing cites"
ackable = true
tiers   = { pr = "warn" }
```

**What the packs own.** A pack's descriptor declares the files it governs (`files = ["**/*.rs"]`), so the manifest never maps paths to packs. `[languages.<name>]` may narrow or replace a pack's `files` — the markdown case above, where governing every README in the tree is not wanted — and may add `exclude`. A file matched by two packs is a manifest load error, not a precedence rule.

**The lockfile.** `sinter.lock` is tool-owned, written by `sinter pack add` and `sinter init`, and holds the exact version and hash for every language in `[languages]`. Versions in the manifest are constraints (`"1.4"` means `1.4.x`); the lock is the truth CI verifies. This is Cargo's split, adopted for the same reason: the manifest stays readable and the lock stays exact. `pack-drift` compares the cache against the lock.

**Saved definitions** are `[findings.<class>]` entries; a finding with no `tiers` is evaluated by `query` and never by `check`, which is what a reusable definition is. There is no separate `[defs]` table.

**Tier sets** are three — `turn`, `pr`, `main`. Only `pr` and `main` block mechanically, in CI; `turn` is the severity vocabulary the report, its exit code, and orchestrators consult (§8). `check` and the PostToolUse hook always report everything.

**Tuning keys** exist but are not in the example; each has a default that should be right for most repositories:

| key | default | meaning |
|---|---|---|
| `target` | `"main"` | branch whose merge-base is the default `--base` |
| `brief.budget` | `12000` | bytes; the turn-level brief uses a quarter of it |
| `brief.why_budget` | `2000` | bytes; the origin-decision extent attached to a `rule-owed` block (§7) |
| `evidence.require_attribution` | `false` | `true`: rung `unattributed` never discharges a `@verifies` promise |
| `ledger.sign`, `ledger.signers` | `false`, `[]` | signed ledger commits and the allowlist (§6.4) |
| `refuse_env` | `["CLAUDECODE"]` | harness markers that make `approve`/`decline` refuse |
| `rules.<name>.scope` | `[]` | where a rule's discharge edits land (§7); only needed when outside the plan's scope |
| `rules.<name>.tiers` | from `[gates]` `rule-owed` | per-gate override for one rule's obligations |

Deliberately absent: a hooks table (hook registration lives in the harness's own settings file, which `init` writes; there is nothing to configure twice), a journal switch (a journal exists iff the file does), an evidence directory (fixed at `.sinter/evidence`), the ledger ref (fixed), a schema version (assumed `1` until a `2` exists), sampling of acknowledged discharges by the judge (waits for `sinter judge`), a classification-tag table (an earlier draft's `compile spec --tag` — a selection nobody has asked for yet), and per-kind declaration paths (`[declare]` in an earlier draft — a warn-tier nicety that cost a table and two finding classes; if a repo wants it, it is one `[findings]` entry away: `kind(req) - path(docs/requirements/**)`).
