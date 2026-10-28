<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter design notes

## 1. Thesis

A coding agent is a program that writes code for a person with a
language model. Coding agents often fail at two things: they do not
follow the conventions of a project, and they do not stay on the plan
that they agreed with the person. These failures come from how agents
work, not from a lack of skill. Three published results show this:

- An agent depends on its plan being in its **context**: the text that
  the model can see at one time. The signal of a plan falls by a
  factor of 4 to 12 within one step of action and observation ("Plans
  Don't Persist", arXiv:2606.22953).
- While a whole policy was in the agents' context, the rate of broken
  constraints was 0 percent. After **compaction**, which shortens the
  context to make room, the rate rose to 30 to 59 percent ("Governance
  Decay", arXiv:2606.22528).
- An agent's report that its work is complete often differs from what
  its tools did. Published patterns of enforcement therefore do not
  accept the agent's own report as evidence ("Proof-or-Stop",
  arXiv:2607.14890).

So instructions in the context cannot enforce an agreement. A system
outside the agent must enforce it, and that system needs two
properties:

1. It reads the state of the work from artifacts, which are the files
   of the repository and the results of test runs. It never reads the
   state from the agent's report about its own work.
2. It blocks a change that breaks an agreement at the merge, by rules
   that give the same answer every time. Before the merge, it makes
   each such change impossible to miss.

Sinter is such a system. The person who merges a change must be able to
check every state that Sinter reports from the repository and its test
results alone.

Text that a tool puts into the agent's context is a channel of
information, not of enforcement. A **hook** is a command that the
agent's program runs at a fixed event, for example after each edit. A
hook that stops an edit or holds the end of the agent's turn is also not
enforcement. Such a hook acts on the agent's actions, not on the result
of the work. Under pressure, it teaches the agent to go around it. So on
a local machine, Sinter computes the same result that CI (continuous
integration, the checks that the hosting service runs on each change)
will compute. Sinter gives that result to whoever runs the session: a
person, or a lead agent that directs other agents. That person or lead
agent is the place for judgment during the work.

**The threat model: the agent cooperates.** The problem is decay, not
an attacker. Plans fall out of the context, conventions are lost after
compaction, and the pressure to finish makes an agent's reports too
hopeful. Sinter does not defend against an agent that schemes. This
assumption carries weight in three places. Sinter trusts local
evidence and hooks, and does not protect them against tampering.
Approval prevents accidents and drift, not forgery. The agent can edit
the manifest. A deployment that cannot make this assumption needs more
protection, which Sinter by default does not carry, on purpose.
Section 6.4 says where that protection attaches.

**Prior art, and the gap.** Other tools hold parts of this design:

- Beads holds the task graph that agents use. It enforces that graph
  and its gates, but it binds no requirement to a test.
- Spec Kit, OpenSpec, and Kiro use specifications mostly as text for
  the prompt. OpenSpec checks only the structure of a specification.
  Kiro checks the requirements, but it takes the status of a task from
  the agent.
- Doorstop, StrictDoc, and OpenFastTrace come from the tradition of
  requirements traceability. They have graphs in which each item and
  each link has a kind, suspect links, and coverage. Projects
  certified under DO-178C, the standard for aircraft software, use the
  method. A suspect link is a link to an item that changed after the
  link was written. These tools are older than coding agents.
- agent-spec gives each requirement a result from `cargo test`, and
  gates on that result before a commit and in CI. It works for Rust
  only.
- coherence binds claims in separate specification files to symbols in
  the code and to test titles, in TypeScript, Python, and Ruby. It has
  no revisions, so nothing becomes suspect when a requirement changes.
- Claude Code hooks can block an action with a fixed rule, but they
  have no data model.
- Luria is a truth-maintenance system over decision records: it holds
  the reasons of a project. Sinter takes two lessons from it. Most of
  the findings that a change causes end with a judgment that a person
  records, not with a repair. And a field that sets off a check, such
  as the status of a record, does nothing when nobody ever changes
  it.

No tool checked in October 2026 has these five things:

- revision pins, so that a citation names the revision of the item
  that it cites; a check that forces a revision to rise; and a tool
  that never writes into the files;
- test evidence from any language, through JUnit XML, a common file
  format for test results;
- tags that a parser reads, not a regular expression;
- plans whose steps promise facts;
- output in SARIF, the standard format for the results of static
  analysis.

## 2. Shape: one changing object and static facts

The system has one object that changes over time: the **plan**.
Everything else is a static fact that plans leave behind, or a
mechanism that checks how plans turn into facts.

A **tag** is a short line in a comment or a document, such as
`@verifies auth-lockout v2`; section 3 defines the tags. A plan is an
agreement between a person and an agent. It holds steps, and each step
promises facts that its work will add to the repository. A plan exists
to turn itself into **static facts**: declarations of requirements and
decisions in prose, `@satisfies` and `@verifies` citations in the code
and the tests, test evidence, and entries in the ledger, Sinter's record
of judgments (section 6.4). A plan is **open** until the ledger records
that it closed. It closes in one of two ways (section 6.3). CI records
it as `completed` after the merge, and only when everything that it
promised is a static fact. Or a person records it as `abandoned`. The
plan file never moves. A closed plan stays in the tree as a record,
beside the facts that it produced. Nothing goes to an archive, because
nothing is deleted. The ledger, not the file system, says when a plan
stopped being an agreement.

The parts of the system:

- The **graph** (section 3) is the set of these facts, as tags in the
  repository's own text.
- **Evidence** (section 4) binds each `@verifies` citation to real
  test runs and coverage.
- **Compiled specifications** (section 6.4) are approved views of the
  graph. They outlast every plan that added to them.
- The **ledger** (section 6.4) is the record of every judgment:
  approvals, declines, completions, and abandonments. It lives on a
  git ref outside the tree. The closing of a plan is one of its
  entries.
- **Obligations** (section 7) are the difference between what the
  agreements demand and the facts that exist. Sinter never stores an
  obligation. It computes the obligations again at every gate.
- **Rules** (section 7) are standing law: query expressions, checked
  into the repository, that make obligations for as long as they
  stand.
- **Gates** (section 8) are the points where Sinter checks how plans
  turn into facts.

Obligations attach to tags, plans, and diffs, never to the tree as a
whole. So an existing repository starts with an empty graph and no
findings, and a project can adopt Sinter one step at a time. A project
that wants to raise its standard over time writes a rule or a setting
of the manifest, never a one-time change to the whole repository.

## 3. The graph

### 3.1 Tags in the repository's own text

The facts live as **doctags**: tags in comments and in markdown, in
the files that a project already keeps. A tag in the documentation
comment of a function moves with the function, shows in the same diff
for review, and goes away when the code goes away. So the facts and
the code do not drift apart, and no separate file can fall out of
date. The **graph** is the set of all these facts. Sinter reads it
again from the text each time it runs, and plain text in git is the
only source of truth.

Sinter parses each file with **tree-sitter**, a library that turns
source code into a syntax tree, and reads tags only in the nodes that
the language pack marks as **tag-bearing** (section 5.2). It never
searches raw text. So a tag in a string literal or in a code fence
never counts. A comment attaches to the next definition, such as a
function or a test, and that attachment is what binds a test to a
requirement (section 4). `spec/vocabulary.md` section 2 and
`spec/packs.md` sections 6 and 7 give the rules.

### 3.2 Grammar

Every tag has one shape: `@word target [vN]`, then an optional
description.

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

`spec/vocabulary.md` sections 3 to 5 give the rules. The reasons:

- **Unknown words.** Every line that starts with `@` is a tag line, but
  only the words of the vocabulary have a meaning. A near miss of a word
  gives the warning `typo-tag`, because a typo silently removes a
  citation from the graph. Other tools own some words, such as `@param`.
  Each pack lists those words as its **foreign vocabulary**, and they
  never count as typos.
- **Targets.** A citation never names the kind of its target, so the
  kinds `req`, `design`, and `decision` share one namespace of slugs.
  Plans have their own namespace, because a plan often has the slug of
  the requirement that it promises.
- **Revisions.** The detection of suspect citations depends on the
  revision (section 3.5). So a citation that needs one and lacks it is
  the finding `unpinned`, because it would silently escape that
  detection. A declaration without a revision is `v1`, so a project
  can start to tag with no ceremony.
- **No titles.** In markdown, the heading is the title.
- **The slug is the identity.** Sinter keeps no hidden machine ids. To
  rename an item is to delete it and to declare a new one. When the
  new declaration has the same extent hash, Sinter offers a mechanical
  fix for the old citations (finding `renamed`). A renamed item needs
  a new approval, because an approval belongs to a slug. The text that
  `sinter approve` shows calls the change "rename only, hash
  unchanged", so the new approval takes a glance.

### 3.3 Vocabulary

The vocabulary has fifteen words, and `@pin` is designed but
deferred. `spec/vocabulary.md` section 7 defines each word.

**Declarations** say: this text defines a thing. `@req` declares a
requirement, `@design` a design item, `@decision` a decision, `@plan` a
plan (section 6), and `@rule` a rule (section 7). `@design` differs from
`@req` only in its purpose, the architecture between the requirements
and the code, and in how strictly it needs approval. The chain from
requirement to design to code is a property of the graph: the design
item `@refines` the requirement, and the code `@satisfies` the design
item. The kind is on the tag and not on a path, so a project can keep
its design documents anywhere.

**Citations** say: this relates to that. `@satisfies` links code to a
requirement, `@verifies` links a test to it, `@refines` links two
requirements or design items, `@cites` links anything to anything,
and `@supersedes` replaces a declaration. Each citation is an
**edge** of the graph, from its source to its target. A source needs
a name only when another part of Sinter must address it. So a
`@satisfies` in code has a source with no name, a **site**: the file
and the extent of the comment. A test must be addressed, because
evidence binds to it, but the syntax tree already names the test, so
it needs no declaration either.

**Status tags** take an item out of force. `@deprecated` says that the
item no longer applies and nothing replaces it. `@rejected` marks a
decision that was considered and not chosen; its record stays, so that
nobody argues the choice again. `@deferred` marks a decision that is not
made yet. A status tag has effect only in the tag block of a
declaration, so the `@deprecated` of JSDoc in a code comment is safe.
Sinter has no tag for "done".

An item is **in force** when no status tag and no effective
`@supersedes` retires it; otherwise it is **retired**
(`spec/vocabulary.md` section 8). A `@supersedes` is **effective** when
its source carries no status tag and, where approval applies, is
approved. Supersession is an edge, not a status. So the retirement of
the old item takes effect with the approval of its successor, and the
old item needs no approval of its own. A successor that nobody approved
retires nothing yet, on purpose. In a chain, every item before the last
one is retired (record `supersession-chains`).

**Directives** record a judgment at one place. `@ack` records that a
person or an agent accepted a finding, or met the obligation of a
rule, for one block of text as it stood. The ack holds the hash of the
block (section 3.4), and it is **void** when the text changes or when
the finding that it names goes away. A void ack is itself a finding
(`stale-ack`), so a judgment never outlives what it judged.
`sinter check` prints the exact line to paste, and the report lists
every ack beside what it accepted. `spec/vocabulary.md` section 7.4
gives the rules.

An ack accepts one finding at one place, never findings in general.
The need for it came from Luria. In Luria's first wave of findings
after a change, 42 of 70 findings were correct citations of retired
records. Without a way to say so, the only way to a clean check was to
bring the retired records back in force: the record would lie to quiet
a linter. So a finding is **ackable** when its honest resolution can
be a judgment instead of an edit. An unexercised test is one example,
because an integration test can reach code along a path that coverage
cannot see. `spec/algebra.md` section 9 marks the ackable classes. A
citation of an item that has a successor moves to the successor
instead (record `cite-the-successor`).

### 3.4 Extent

The **extent** of an item is the text that its revision covers
(`spec/vocabulary.md` section 6). In code, it is the comment, without
the attached code: the meaning lives in the comment, and revision
discipline checks it; the behavior lives in the code, and evidence
checks it. In markdown, a declaration claims its whole section, and this
rule is what lets Sinter govern prose. A declaration in a nested section
takes that section out of the enclosing extent; otherwise each edit of a
small section would need a bump of every section above it. Prose outside
every extent is visibly not governed, which is at least honest.

**The extent hash** is the SHA-256 of the extent's normalized text
(`spec/vocabulary.md` section 6.1). Normalization leaves out what does
not change the meaning, and each part has a reason:

- A formatter can indent a doc comment again, and a person can record
  an ack inside a section, with no bump.
- A rename, or a bump with no other change, leaves the hash equal, so
  the fix for `renamed` can be mechanical.
- A new pin of a citation leaves the hash equal. Whether a pin is
  current is the business of `suspect`, not of approval, so a new pin
  never sets off new bumps and new approvals up the graph.

Normalization stays in the domain of text: it parses nothing and reads
no meaning. The same normalization of a block gives the hash that an
`@ack` records, so one rule serves both uses.

**A gap that is half closed.** No check with fixed rules can prove
that code drifted from a comment that did not change. But each site in
code also has a **code hash** of the attached definition. When the
code hash changes and the comment's hash does not, Sinter reports the
warning `code-drift`. It is not proof of drift. It tells a reviewer who
checks code by samples, such as the check with a fresh context
(section 8), which sites to sample.

### 3.5 Revision discipline and suspect citations

A stored fingerprint of each text would need a tool that writes it,
and Sinter writes into no governed file. OpenFastTrace's model, in
which a person writes each revision by hand, fits plain text. A
citation pins `v2`. A bump of the declaration to `v3` makes every
citation pinned to `v2` **suspect**, and the change shows in an
ordinary diff. That model has a known gap: nothing forces the bump
when the meaning changes.

**The check of the diff closes that gap.** When an extent changed and
its revision did not rise, Sinter reports `unbumped`
(`spec/vocabulary.md` section 9). No exception exists for an editorial
edit. A claim that "this edit did not change the meaning" would be a
second report of the agent, and someone would have to check it. A bump
after a typo costs only one new pin, which Sinter prints. A bump also
removes the item's approval until a person approves it again (section
6.4): one mechanism with two effects.

A check that keeps no state cannot see one collision: two branches
each bump `v2` to `v3` with different meanings. So CI on a pull request
checks the branch as it would land, against the live tip of the
default branch, and the second branch to land shows an extent that
changed while its revision did not. For approved items, the ledger
also refuses a revision that another branch already took (section
6.4). For other items, the remaining exposure is the price of a check
that keeps no state.

### 3.6 Retirement and propagation

Two independent triggers spread a change through the graph:

- **A revision bump** means that the meaning changed. Each pinned
  citation is suspect until someone pins it again.
- **Retirement** means that the authors no longer stand behind the
  item. Each `@cites` of a retired item is a `retired` finding: this
  text argues from something that the record no longer endorses.

Propagation stops at the finding and never cascades. A bad argument
for an item does not defeat the item, and only a judgment can say
whether a thing that rests on a withdrawn premise stands on other
grounds. A classical truth-maintenance system marks each dependent
item as no longer believed; Sinter does not take that part.

When someone deletes a `@supersedes`, its target comes back in force,
and no dangling edge remains to report it. Revision discipline catches
this case: the tag line of the edge is in the extent of its source, so
the deletion needs a bump and, where approval applies, a new approval.

**Decisions are never deleted.** A decision can be superseded, rejected,
or deferred, and its old text stays, because the old reasons are the
record of why the new decision exists (`spec/vocabulary.md` section
8.3). The rule objects to silent revision, not to edits: a record that
still decides the same question is edited with a bump, and a different
choice takes a new record (record `revise-or-supersede`).

**Historical text is exempt as a class.** The manifest can declare
paths as **historical**, such as a log of development, and the
journals of plans are historical by a built-in rule. Citations there
resolve but make no findings. A demand for an ack at each place in
history would teach people the reflex to bypass the check.

Decision records follow the form of an architecture decision record:
the context, the choice, and the alternatives considered. The last
part has the most value and is skipped most often: it stops people from
arguing the same choice again. One record holds one decision, because
nobody can cite half of a record. A design that lives in an issue
tracker stays an external id, because the body of an issue has no diff
to check and no extent to hash.

### 3.7 Governed documentation

Nothing above is specific to documents of requirements. A user guide
that `@cites auth-lockout v2` becomes suspect when the requirement moves
to `v3`. A tutorial that cites a deprecated decision gets a `retired`
finding. So Sinter detects drift in documentation, one of the oldest
unsolved problems of software work, with the same two mechanisms and no
other machinery, when the markdown pack reads the documentation. This
use also orders the list of packs (section 5.2): the artifacts that most
need tracing and least often get it are interfaces and data shapes, not
code.

## 4. Test evidence

The rest of the design exists to make this section possible. A
`@verifies` citation is a claim that a test checks a requirement.
Sinter turns the claim into a fact or into a finding, and it uses
nothing that the agent said.

**The test comes from the syntax tree.** The query file `tests.scm` of a
language pack finds the tests of a file and their names. It also finds
the groups that hold the tests, such as the `describe` blocks of
JavaScript. A `@verifies` in a comment that attaches to such a test
makes the test the source of the edge, so no `@test` declaration exists.
A `@verifies` above a group covers every test in the group. Sinter does
not read the ids of requirements in test titles: a title carries no
revision, so a test bound by its title would never become suspect
(record `tags-not-titles`).

**Results bind to tests through adapters.** A test runner reports each
test by a name of its own, and runners differ in how they build that
name. So a language pack carries a **runner adapter** for each runner
that needs code to match the reported names to the tests in the
source. An adapter is a WebAssembly module that imports nothing, so it
reads no file, uses no network, and sees no clock. A runner without
an adapter of its own uses the default adapter, which joins the names
of a test with the runner's separators. The adapters live in the
packs and not in the tool, so a fix for a new version of a runner
needs no release of Sinter. Sinter keeps the meaning of every result,
so no adapter can make a failure pass. Record `runner-adapters` gives
the reasons, and `spec/packs.md` sections 8 to 11 give the rules.

**Evidence files.** Sinter reads the reports of test runners in standard
formats, JUnit XML first. It reads coverage in standard formats, such as
lcov, Cobertura, and the JSON of coverage.py. `sinter evidence import`
stores what it reads in a folder that git ignores,
`.sinter/evidence/<tree-key>/`, and the gates read it from there. The
**tree key** is the git tree hash of the working tree as it is on disk.
Sinter computes it without a change to the real index of git. Git stages
every file that it does not ignore into a temporary index, and writes a
tree from that index. The key makes sure that old evidence never binds
to a newer tree. In CI, Sinter computes the key again, and that result
is the one that counts.

The agent can write into the local evidence folder. Sinter trusts the
folder, and the folder is not proof. That is acceptable, because the
failure that Sinter catches is a claim that the tests pass when nobody
ran them. A forged report is a deliberate act, and the threat model of
section 1 leaves out deliberate attacks. CI on a pull request makes the
claim real for the merge. Sinter never runs tests. Whoever runs them,
the agent, a lead agent, or a step of CI, gives the files of that run to
`sinter evidence import`.

A tree with no evidence is a state, not a violation. The findings of the
evidence ladder below appear only when evidence exists, so such a tree
never fails a check for its evidence. `sinter status --done` still
refuses. A step is done only when each of its `@verifies` edges is at an
allowed rung, and with no evidence each edge is at `never-ran`
(`spec/algebra.md` section 6.4). The review gate enforces the rungs, so
a plan is checked against measured work before it merges.

**The coverage of each test is the expensive rung.** Rung 4 below asks
whether this test ran that site. Only the **coverage of each test**
answers that question: the coverage of one test, run on its own. The
**coverage of the whole run**, the usual output of lcov or Cobertura,
says only that something in the run ran the site. Some tools give the
coverage of each test:

- coverage.py with `dynamic_context = test_function`, for Python;
- the session data of JaCoCo, for the JVM, when a pack exists;
- the V8 coverage of Jest, run in batches with `--runTestsByPath`;
- the general fallback: each test that carries a `@verifies` runs in
  its own process, with its own coverage file. This is slow and always
  correct, and the conformance fixtures of each pack use it.

`cargo llvm-cov` and `go test -cover` give the coverage of the whole
run, unless a driver runs them one test at a time.

With only the coverage of the whole run, rung 4 reports **unmeasured**,
not passing: the run ran the site and the test passed, but the link
between the two is not proven. One case still holds without the coverage
of each test. When the whole run ran no line of any site that satisfies
the requirement, the test ran none either, so the test is
**unexercised**. `unmeasured` is off or a warning by default, so it does
not block unless a repository raises its tier. A repository that wants
rung 4 to bite pays for the coverage of each test in its test setup, and
sets `evidence.test-coverage = "required"` (`spec/manifest.md` section
12). `sinter evidence import` says so when it sees only the coverage of
the whole run.

**The evidence ladder**, in order of how much each rung catches:

1. **Wrong source.** The `@verifies` attaches to something that
   `tests.scm` does not find as a test. This is a check of structure.
2. **Never ran.** No result in the evidence of this tree binds to the
   test, or the test was skipped.
3. **Failed.** A result that binds to the test fails or ends in an
   error. The promise is not met.
4. **Unexercised.** The test passed, but the coverage of each test
   shows that it ran no line inside any site that `@satisfies` the
   same requirement. This is the closest check with fixed rules to a
   false verification. Both ends of the link already exist in the
   graph; the cost is the coverage of each test. With only the
   coverage of the whole run, the rung is **unmeasured**, unless that
   coverage shows no line run in any of the sites.
5. **Vacuous.** The test passed and is connected, but it does not test
   the property. Only a judged rule (section 7) can reach this rung.
   It is the limit of checks of structure, and the design says so
   plainly.

A `@verifies` edge is at exactly one rung at any time: `wrong-source`,
`never-ran`, `failed`, `unexercised`, `unmeasured`, or `passing`.
Rung 5 is a judgment on a sample, not a rung that Sinter assigns. The
rung is a field of the edge, and a family of predicates in the query
algebra (`spec/algebra.md` section 6.7). Rungs 1 to 4 are what
tree-sitter and standard test reports can give. Rung 4 also gives
`@satisfies` a job beyond the bookkeeping of coverage. The
conformance fixtures of each pack include a real run with the coverage
of each test, so the link is checked from end to end in each
language, not assumed.

## 5. Manifest, language packs, and external ids

### 5.1 Manifest

The **manifest** is a TOML file at the root of the repository,
`sinter.toml`. It holds the settings of one repository. Among them:

- the packs that read the files, and the files that each pack reads;
- the namespaces of external ids;
- the kinds that need approval;
- the historical paths, and the exempt paths, which a change can touch
  with no plan step;
- the tier of each finding class at each gate;
- the test evidence that meets a promise.

A lock file that the tool writes, `sinter.lock`, holds the exact release
and hash of each fetched pack, so a pack is the same bytes on every
machine and in CI. A repository's own rules and finding classes live in
rule files, not in the manifest (section 7). The manifest is TOML
because it holds pure configuration and no prose. `spec/manifest.md`
gives the format, and its section 3.1 lists every setting. Section 14 of
these notes gives the reasons for the shape of the manifest.

**The agent can edit the manifest, on purpose**, the tiers included.
Under the cooperative threat model the risk is drift, not sabotage, so
the defense is visibility. The built-in finding class `config-changed`
reports each change of a setting, in every report, the turn report
included: "this change also loosened the law". Nothing can turn the
class off, so a lowered tier never rides unseen inside an unrelated
diff.

### 5.2 Language packs

The support for a language is data, not code, and Sinter loads it
when it runs. A **language pack** holds these parts:

- one or more tree-sitter grammars, compiled to WebAssembly (wasm),
  each in one file that serves every platform;
- query files: which comments carry tags (`tags.scm`), which
  definitions a comment attaches to (`definitions.scm`), and which
  nodes are tests and what their names are (`tests.scm`);
- a descriptor, `pack.toml`, which lists the grammars, the comment
  sigils, the foreign vocabulary (section 3.2), and the test runners;
- the license notices;
- runner adapters, when a runner needs one (section 4);
- conformance fixtures: a small project, the JSONL that a scan of it
  must give, and real output of a test runner.

**A pack holds no code that can read or write anything outside itself.**
A grammar in wasm imports only memory and a few functions of the
tree-sitter host, such as tests of a character's class. A runner adapter
imports nothing, and it runs under limits of time and memory. Anyone can
check this in the import section of the wasm file. So a developer tool
such as Sinter can safely load packs when it runs. It can also fetch a
pack by hash into a user cache, and nobody has to trust a native
library. The cost: the binary links wasmtime, the runtime that the wasm
feature of tree-sitter supports, and the binary grows by about 15 MB
(record `parser-bridge` gives the measurements). A cache of compiled
modules makes a later load fast, so each machine compiles each grammar
once. The binary of the tool is the only part of the system that is
built for one platform.

The markdown pack is built into the tool, because plans, decision
records, and rule files are markdown; it changes with the tool. Every
other pack comes from a packs repository. Sinter checks a fetched pack
against its SHA-256 hash and records it in `sinter.lock` (record
`pack-delivery`). So support for a new language is a pull request to
the packs repository, never a release of the tool. A language that no
pack reads stays visibly not governed.

The first packs are markdown, TypeScript, Rust, and OCaml. After them,
the order goes by where requirements most need tracing, not by how
popular the language is:

1. YAML, for CI pipelines and Kubernetes manifests, where operational
   requirements live;
2. SQL, for migrations that `@satisfies` requirements about data;
3. OpenAPI and protobuf, for the contracts of interfaces. A
   `@satisfies` in the description field of a schema is the only place
   to trace a requirement about a wire format.

A pack that reads tags in the comments or the description fields of
structured data works like a pack that reads them in doc comments.
`spec/packs.md` gives the format of a pack and of the lock file.

### 5.3 External ids

An **external id**, such as `gh/42` or `jira/PROJ-1`, points at
something outside the repository. It is a pointer, not a node: it has
no revision, Sinter fetches nothing for it, and by default no change
spreads from it. The scanner checks its namespace and its pattern
against the manifest, with no network. No namespace is built in; a
project on GitHub declares `gh`.

`@pin` is the planned exception, and it is deferred. When an argument
really depends on content outside the repository, a person endorses
the current hash of that content through approval. CI then reports
each change of that content until a person endorses the new hash. `@pin`
works opposite to every other directive: it arms a check instead of
quieting one.

External ids give back the example that started the project, "close the
issues when the work is done", without Sinter touching GitHub. A rule
can check, with no network, that an external id is present: for example,
every item that the plan declares cites a `gh/*`. The state of the issue
on the host is a read over the network, in a networked layer such as CI
on the default branch. That layer could keep a plan from closing while
an item's external id points at an open issue. `sinter query` could list
the facts whose external ids are open. The agent could then fix them
with the `gh` command that it already has. That read is deferred with
`@pin`. The query algebra itself never reads the network.

## 6. Plans

### 6.1 The plan file

A plan is a markdown file under `.plans/`, for example
`.plans/auth-lockout.md`, committed on its branch. A file that git
ignores would not travel between worktrees, and CI could not see it, so
the check for unplanned work would have no authority. A plan is **open**
until the ledger records that it closed (section 6.3), and a closed plan
stays as a record beside its journal. `spec/vocabulary.md` section 10
gives the rules of plan files.

Two records change parts of sections 6.1, 6.3, and 6.7, and the
specifications do not carry them yet. Record `plans-span-branches`
says three things. A plan reaches the default branch in a pull request
of its own. That merge is its approval. Later branches each deliver
some of its steps. Record `plan-ids` gives each plan an id from its
creation, written as in `@plan upkeep@3f2a9c`, and a closed plan frees
its slug.

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

**A plan is a set of promised facts.** A plan uses the same tags as
the rest of the repository, but inside a plan, Sinter reads each tag
as a **promise**. `@req auth-lockout` means that the step will declare
`auth-lockout`. `@verifies auth-lockout` means that the step will
produce a passing, connected test that carries that citation. Each
`##` heading with a `@scope` or a promise is a **step**; a section
without one is prose, from which Sinter derives nothing. Steps have no
order; their order in the file is advice.

A promise is met only by a fact inside the step's scope, or inside the
default location of its kind that the manifest names. A fact outside
both is reported as `promise-out-of-scope`, because the scope is part of
the agreement. A promised `@verifies` needs a passing test, so a plan
cannot be done on a test that never ran or that failed (section 4).

**The active plan.** When exactly one plan is open on the branch, it
is active. With several, `sinter declare` names one; until then, the
brief (section 8.1) and the check of scope have no plan to anchor on,
and `sinter status` says why.

- **The state of a step is derived, never ticked.** A step is done
  when its promises are met and its evidence passes. Only when every
  step is done can the work merge.
- **The active step is the one statement of the agent that Sinter
  accepts.** It is safe, because it can only narrow what the brief
  covers and what the check of scope measures against. A wrong step
  makes the reports noisier, never quieter. It lives in
  `.sinter/session.json`, which git ignores, and it is the state of a
  session, never truth. Where the **harness**, the program that runs the
  agent, gives a session id, Sinter keeps the step per session (section
  11.18), so parallel sessions in one worktree do not collide.
- **A step with a scope and no promises is a refactor step.** It is
  done when a change touched its scope and the evidence still passes.
  That is a weaker condition, and visibly so.
- **Plans are exempt from revision discipline.** Sinter judges a plan by
  its commitments, never by its text (section 6.2). The count of its
  approved amendments serves as its revision.

A **hunk** is one part of a diff that changed: a run of removed and
added lines. The check of scope reports each hunk that no step covers
(`unplanned-change`). The plan file, the manifest, and the lock file
are outside that check, because other machinery governs them: a change
to a plan is an amendment (section 6.2), and each change of a setting
is reported (section 5.1). Exempt paths are outside it too. A hunk in
`Cargo.lock` maps to no step and never will, and without exempt paths
the first dependency that a step adds would flag its own lock file
(`spec/manifest.md` section 10.2).

### 6.2 Amendment: the monotone rule

A plan must be easy to change in its structure during the work, and
harder to loosen than code. Otherwise an agent can make invented work
look approved: it amends the plan first and then does the work. What a
person approved is the **commitment set**: the promises and the scope
of each step. The rule is monotone: a change that only narrows the
agreement is free, and a change that widens it or changes its promises
needs a new approval. To rename, reorder, or split steps is free. To
add a promise needs approval, because it would make invented work look
approved; to remove one needs approval too, because it would break the
agreement. `spec/ledger.md` section 11 gives the comparison.

Sinter compares sets, never text, so the ledger stores the approved
set itself: a hash cannot show that one set lies inside another. The
main reason for the rule is **approval fatigue, the real adversary**.
A person who approves by reflex gives approvals that are worth
nothing. Many free changes keep the approvals that remain meaningful.

**To cut work early is the amendment rule at work.** To merge part of
a plan is to approve a smaller set of promises. The half-done hunks of
a cut step then map to no step, so `unplanned-change` reports them
until someone reverts them or covers them honestly. Any part of the
work that reached a declared fact stays visible as debt, in
`untraced`. `sinter compile residual-plan` prints the unmet rest as a
plan for a later branch.

### 6.3 How a plan closes

A plan closes by a ledger entry, never by a change to a file, so no
deletion needs to be arranged and no merge commit needs an edit. It
closes as `completed` or as `abandoned` (section 6.7).

**The completion gate.** A plan can complete only when everything that
it promised is a static fact. The review gate enforces this, where
evidence exists, with `sinter status --done`. CI on the default branch
writes the entry: on each push, it checks each open plan that has
merged against the **completion condition**, and appends `completed`
for each plan that passes (`spec/ledger.md` section 8). The writer is
CI and not a person, so that the closing rests on the tree and the
approvals, not on anyone's report. A second run writes nothing new, so
a lost CI run costs a retry and loses no fact.

An open plan on the default branch that fails the condition is the
blocking finding `merged-incomplete`: someone merged half a plan.
(Under record `plans-span-branches`, an open plan on the default branch
is normal while its work goes on.) The honest ways out are an approved
smaller plan (section 6.2) or a revert of the merge.

A closed plan makes no findings, holds no claim, and adds no scope. Plan
slugs are permanent, like the slugs of decisions, so
`compile residual-plan` prints its plan under a new slug. (Record
`plan-ids` frees the slug of a closed plan; see section 6.1.) Without
the ledger ref, every plan reads as open, and `sinter status` says so.
This result on the default branch is intended. The plan and its journal
stay beside the facts that they produced, and the ledger says who
approved the plan, what it promised, and when it stopped being an
agreement.

### 6.4 Compiled specifications and the approval ledger

A **compiled specification** is a named view of the graph, such as
all the requirements under a path. Sinter compiles the **delta**, the
changes to the items since their last approval, into a document that a
person can read and approve. The approval attaches to the slug, the
revision, and the extent hash of each item, never to the document. The
document is only the way to read the items.

**The ledger** is the record of approvals and other judgments. It is a
file on a git ref of its own, `refs/sinter/ledger`, and entries are
only ever added (`spec/ledger.md`). CI can fetch the ref and every
worktree shares it, but it is outside every path that an editor or a
file tool touches. Only the low-level commands of git, its plumbing,
reach it, so to write it is a deliberate act. A kind needs approval
only when the manifest lists it in `ledger.approval-required`
(`spec/manifest.md` section 11.1).

Because the ledger is a shared record with timestamps, it gives five
more uses, each one a kind of entry or a query, and none a new
mechanism:

- **Declines.** A person who reads a delta and thinks "no, not like
  that" needs a durable place to say so; otherwise the thought goes into
  the chat and fades. A `decline` binds the reason to the exact text, by
  its hash, and `status` and the brief show it until the text changes.
  `sinter approve` asks before it approves over a live decline. It is an
  instruction that cannot fall out of the context, because it is
  attached to an artifact: the mechanism of section 1, used in the other
  direction.
- **Revision reservation.** The ledger refuses an approval of
  `auth-lockout v3` when it already holds `v3` for that slug with a
  different hash: "v3 is taken; bump to v4". So for approved items, the
  collision of section 3.5 is prevented, not only detected.
- **The archive of plans.** The ledger holds every promise of every
  approved plan, each amendment, and the closing. It answers which plan
  promised a requirement, who approved it, and when it landed, without
  a tree.
- **Signatures.** Ledger commits are git commits. A deployment that
  signs them makes each approval impossible to deny, and
  `sinter ledger verify --signers` checks them. This is the hardening
  path of section 1, with no change to the design. A deployment that
  wants the server to enforce that no approval comes from an agent's
  shell puts the ref under `refs/heads/sinter/ledger`, where the push
  rules of the host apply. The manifest has no setting for signatures
  yet.
- **History, release notes, and metrics.** Each entry has a commit and
  a time, so `sinter compile spec --as-of` rebuilds what was approved
  at any moment, and the delta between two points of the ledger is the
  release notes of the requirements. The health signals of section 8
  gain a time axis: the bumps of each item (a requirement at `v9` is
  unstable or badly scoped), the amendments of each plan, the time from
  approval to completion, and the seconds spent on each approval. The
  last one measures directly the fatigue that this design calls its
  real adversary.

The ledger works together with the revisions. An edit of an approved
item needs a bump, and the item is then not approved until a person
approves it, as its citations are suspect until someone pins them again.
A status tag is an edit, so it needs a bump, and a supersession waits
for the approval of its successor. So the retirement of an approved item
reaches a person on every path, with no extra rule.

**The approval gate.** A `@satisfies` or a `@verifies` of a requirement
that nobody approved is the finding `unapproved-req`: work against an
unapproved requirement. It blocks by default, and `unapproved-design`
only warns. To block on the approval of design is too much ceremony for
the work of one person, but an unapproved design is also how an agent
can quietly reinterpret what the person meant.

**Who can approve.** Under the cooperative model, an approval must be
unmistakable, not undeniable: every bypass must take a deliberate act,
and a deliberate act is outside the threat model. Two simple layers
give this:

1. The commands that write the ledger read the confirmation from the
   controlling terminal, `/dev/tty`, never from standard input. The
   shell of an agent has no controlling terminal, so the command
   refuses, and `yes | sinter approve` cannot work.
2. An **agent marker** is an environment variable, such as
   `CLAUDECODE`, that shows that an agent runs the command. When one is
   set, the command refuses. This closes the gap of a terminal pane
   that an agent drives (`spec/manifest.md` section 11.2).

Under these layers lies the structure: the ledger is outside every
checkout, and no path to an approval starts from an agent's shell.
Tokens issued for each session were considered and not chosen: they
defend against a deliberate attacker, whom the threat model leaves out,
and signatures already give that defense.

**A known limit.** Approval by delta assumes deltas of a size that a
person can review. A step that adds forty requirements leads a person to
approve without reading. The report counts the pending batch, but the
algebra has no arithmetic, so no rule can limit it; in the end it is the
person's discipline.

### 6.5 The plan journal

The agent's running list of tasks belongs to the agent's own tools,
and it ends with the agent's context. Between that list and the facts
in the tree lies a third thing: what the agent tried and why it
failed. A plan can carry a **journal**, `.plans/<slug>.log.md`. Its
path is historical by a built-in rule (section 3.6): the agent adds to
it, nothing in it makes findings, and its citations resolve. It stays
beside its plan as part of the record, and `compile residual-plan`
carries it forward.

The journal is the place where small decisions collect until one of
them earns a `@decision` record. The rule of section 7 for when to
write a rule needs a place where the first case is written down. Most
of the reasoning of a project is small, and without a journal it is
lost. Record `plan-journals` says how agents write and revise the
entries.

### 6.6 Plan checks and preview

A plan file is the one governed file that changes all the time, and
people need help to write it. Sinter scans plan files like every other
file, so the checks of a plan are ordinary findings (`spec/algebra.md`
section 9):

- `unverified-promise`: the plan promises a requirement and no test of
  it, so it agrees in advance to ship a requirement that nothing
  verifies.
- `promise-collision`: a step promises a slug that already exists at the
  base, or that another branch promises, so the step would produce a
  `duplicate`. The check reads the base and not the current tree,
  because in the tree a met promise is exactly such a slug.
- `scope-overlap`: two steps of one plan compete for one edge, which
  shows a plan that has not decided.

**Preview.** `sinter compile plan-preview` shows the graph as if every
promise were met: the new declarations and edges, what becomes suspect
or retired, and which gaps close or open. A person then approves a plan
with foresight instead of trust, and the approval of a plan is taken
against its preview.

### 6.7 Several plans at once

Each plan belongs to a branch. (Record `plans-span-branches` lets a
plan span several branches, and claims change with it.) A lead that
runs several agents on several branches needs three things that the
ledger can already give.

**Claims.** For each approved, open plan of another branch, Sinter reads
a **claim** from the ledger ref as it was last fetched, never from the
network. It reports an overlap of scopes as the warning
`branch-overlap`: "plan `session-store` on branch `feat/store`, approved
Tuesday, also claims `src/auth/**`." It is a warning and not a block,
because two plans can rightly touch one folder. But it is the earliest
moment to learn that two agents will conflict, days before the merge
shows it. A claim ends when its plan completes, when a person abandons
the plan with `sinter ledger abandon`, or when its branch is deleted
(`spec/ledger.md` section 9, `spec/jsonl.md` section 7).

**Promises across plans.** Plan B has `@satisfies auth-lockout`, and
`auth-lockout` exists nowhere on B's branch. Without claims, that
citation would dangle until A merges. With claims, Sinter sees that
plan A promises to declare `auth-lockout`, and reports `waiting-on`
instead: a fact about order, not an error. Only the real declaration
meets B's promise, after A merges. But B's status is honest in the
meantime, and its turn report does not fire by mistake.

**The order of merges.** Promises across plans make a graph of
dependencies between claims. `sinter compile merge-order` prints an
order that respects the graph, or names its cycle. This is the lead's
breakdown of the work, derived from what the plans promise instead of
kept in a separate list.

None of this needs a plan to know about other plans: claims are views
of the ledger, and a plan file never names a branch.

### 6.8 The inbox

Under the cooperative model, the attention of the person is the scarce
resource. Section 6.2 protects it, because free changes need no
approval, but nothing else schedules it. `sinter inbox` is one place,
across every branch that the ledger and the remote know, that lists
only what needs a person's judgment: pending approvals, plans that
cannot close, declines whose item changed since, rule acks that agents
wrote, and overlapping claims. Each item names the command that
resolves it. The inbox speaks only when a person asks: the tool should
be the one truthful place to ask "what needs me", and otherwise never
ask anything.

### 6.9 Out of scope for plans

Plans do not model time, effort, priority, or assignment. Those belong
to the tracker that the external ids point at.

## 7. Rules and obligations

Some conventions of a process, such as "rewrite all drafted prose in
Simplified Technical English", are not facts that Sinter can derive
from the graph, and they are not tasks. They are **rules**. A rule has
two expressions of the query algebra (section 9.2): a **trigger** and
an **expect**. Its **obligations** are the facts that the trigger
selects and the expect does not: the trigger minus the expect.

An example: a rule `ste-docs` has the trigger
`kind(req|design) ^ path(docs/**) ^ changed(base)`, which selects each
requirement and design item under `docs/` that the diff changed. Its
expect is `acked(ste-docs)`, which selects each item whose block holds a
live `@ack ste-docs`. So each changed item without such an ack is an
obligation. A rule also has a scope: the paths where the edits that
clear its obligations land. So work done for a triggered rule outside
the plan's scope is not reported as `unplanned-change`.

A rule lives in a **rule file**: a markdown file that starts with front
matter, a block of TOML. The front matter holds the expressions, and the
text below it holds the reason for the rule. `@rule <slug> vN` declares
the rule, and the extent of the rule is the whole file. So a change to
the expressions or to the reason needs a bump. A rule file keeps a rule
beside its argument, so the reviewer of a change sees both (record
`rule-files`, `spec/manifest.md` section 15). Where rule files live, how
a rule is approved, and what its scope means are settled with the work
on rules.

The engine of rules is the query engine. There is no second language of
predicates, and the exhaustive matching that OCaml gives (section 9)
covers the rules at no extra cost. Obligations attach to artifacts, not
to a context, so the decay of section 1 cannot touch them. The turn
report derives each obligation again from the diff, whatever fell out of
any agent's context. Rules are facts like all others, of the kind
`rule`, so the report and the algebra reason about rules as they reason
about everything else.

**A rule should cite its origin**, the decision that earned it, with
`@cites`. A rule whose evidence is missing reads as taste, and the next
agent argues against taste. The citation is an ordinary `cites` edge
whose source is the rule. When the origin retires, the ordinary
`retired` finding shows a rule that rests on withdrawn reasons. So the
way this system decays is caught by its own machinery, with no special
case. When to write a rule: one case is a decision. Write the rule when
the same reasons come up a second time.

**The reasons reach the finding.** The origin of a rule has an extent
with the alternatives considered. That reasoning helps only when it
reaches the moment where it would change what the agent does. So each
`unmet-rule` finding carries the extent of its origin, cut to a budget
of bytes, in the turn report and in `sinter explain`. Compare two
agents. The first is told: "obligation: rule `ste-docs`; its origin
says that three users misread the lockout documents; alternatives
considered: a glossary (not chosen, nobody reads it), a checklist for
reviewers (not chosen, it decays)". That agent understands the purpose
and changes its approach. The second is told only "obligation: rule
`ste-docs`", and works around it.

**Three kinds of expect**, from the most trusted to the least. A rule
does not declare its kind. Sinter reads the kind from the expect, and it
shows the kind in every report. So it is always clear which rules Sinter
enforces and which it only records.

1. **Checked.** The expect is an expression of structure, and the
   obligation ends when the graph says so. An example is a rule
   `issue-linked` with the expect
   `src(out(cites, kind(req)) ^ in(cites, external(gh/*)))`: a
   `@cites gh/*` on the requirement clears it. External linters fit here
   too. A checker writes `judgment` facts as the judge does, and the
   expect is `judged(<rule>)`, with a program as the judge instead of a
   model. Use this kind wherever it can work.
2. **Judged.** The expect is `judged(<rule>)`: a separate call to a
   language model, never the agent that does the work, against a
   rubric. A fresh context has no wish to finish. This kind is
   deferred, with `sinter judge`.
3. **Acknowledged.** The expect is `acked(<rule>)`: an
   `@ack <rule> <hash>` (section 3.3). This is a report of the agent
   with a check that it is still live: when the text changes, the ack is
   void, and the obligation returns. A known weak point: an agent under
   pressure to finish will at some point ack text that it only glanced
   at. The defenses: the report and the inbox show every cleared
   obligation, and later the judge will check a sample.

How hard the obligations of a rule bite is a separate question from
how they are cleared, and it has the usual answer. The class
`unmet-rule` has a tier at each gate, and a rule can set tiers of its
own.

Sinter does not model pipelines: it publishes the obligations, and
whether the agent clears one itself or through another agent is the
agent's choice.

## 8. Gates and the brief

**Checks come in layers**, from fast and local to authoritative.
`sinter init` installs all of them (section 11.17). Hooks, the command
line, and CI share one library for the checks. **The local layers
inform, and only CI blocks.** A block inside the agent's loop, such as a
denied tool call or a held end of a turn, acts on the agent's actions.
Under pressure, it teaches the agent to go around the block. Enforcement
belongs at the merge, which nobody can talk past, and in the workflow of
whoever directs the session, a person or a lead agent. That person or
lead agent reads the same report that CI will compute. What Sinter adds:
the report takes seconds, it is the same at every layer, and it comes
from artifacts alone. An edit by hand meets the same checks as an edit
by an agent.

**One diff, checked at several moments.** Every check compares the
working tree with the same **base**. By default, the base is the merge
base of `HEAD` and the default branch that the manifest names (`main`
unless the manifest says otherwise), and `--base` overrides it. The
working tree is always "now", with its uncommitted and untracked files.
So hooks, the git hook before a commit, `sinter check`, and CI see the
same findings. They differ only in when they look and in which gate's
tiers they apply. The hook before a commit uses the tiers of the gate
`turn`. CI on a pull request is the one place that sees something
different. It checks the merge ref that the host makes, with the base at
the tip of the default branch (section 3.5). So its diff is exactly what
the branch adds, as it would land.

**Diff mode** (`--diff`) reports only the findings that the diff
introduced: the findings that the base tree does not have. A simpler
rule, to keep only the findings on lines that the diff touched, would
miss a citation that nobody touched whose target the diff deleted.
`spec/algebra.md` section 8 gives the rules.

A **gate** is a point where Sinter checks the work. Each finding class
has a **tier** at each gate: `off`, `warn`, or `block`. A finding at
`block` makes the check exit with code 1 (`spec/manifest.md` section
9.1). The layers:

- **After each edit.** A hook of the harness reports parse errors and
  other findings in the file that the agent just edited, seconds after
  the edit. It also notes when the edit landed outside the active
  step's scope. A parse error makes the findings stricter, never a
  silent gap: a `@verifies` that does not parse is a missing edge. That
  is why fast feedback on parsing matters. Only a tool that names a
  file gives the hook an edited file. A write by a shell command shows
  at the next turn report, which derives everything again from the
  actual diff.
- **The turn report**, `sinter check --diff --gate turn`, is the
  contract when an agent hands back its work. A lead agent runs it
  before it accepts a worker's turn, a person before walking away, and
  an agent before it calls itself done. Its exit code is what a workflow
  gates on. Its tier `block` marks **violations, never incompleteness**.
  A violation is a state that the tree must never be left in:

  - a missing bump;
  - a dangling citation;
  - work outside the plan: each hunk must map to a step or to the
    scope of a triggered rule;
  - an obligation of a rule that the turn's changes triggered;
  - a statement of the agent that the evidence contradicts.

  Incompleteness, such as an unmet promise or an untraced item, is
  never a violation; only the completion gate enforces it. An agent
  that cannot honestly hand back "not done yet" learns to fake that it
  is done. So nothing mechanical holds the turn: the report goes to
  whoever accepts the work.
- **A check with a fresh context**, at the time of the merge request
  and on demand. A separate agent derives the expected work again from
  the approved requirements and the plan, and reports drift in both
  directions: missing work and invented work. This check exists
  because the turn report works at the level of paths. Only a reading
  of the meaning catches work that nobody asked for inside a
  legitimate scope. This layer also takes the samples for rung 5 of
  the evidence ladder (section 4).
- **CI, at two gates, the only mechanical blocks.** At the gate
  `review`, CI on a pull request computes every check, and binds the
  evidence again, against the plan committed on the branch. It is the
  authoritative backstop. At the gate `merged`, CI on the default branch
  checks the promises again on the merged result. It appends the
  `completed` entries of complete plans (section 6.3), and it runs the
  checks that need the network. It enforces the evidence ladder when its
  job imports evidence.

**Each check starts as a warning.** Every finding class starts as a
warning, and becomes a block only after it proves that it rarely reports
a problem that is not real. A gate that often reports problems that are
not real teaches people to bypass it, which is worse than no gate. In
practice, `sinter init` writes `check.warn-only = true`, which lowers
each built-in `block` to `warn`. A project makes one class block by
writing its tier under `check.tiers`, and lifts `warn-only` for all
classes by deleting its line. Both changes are `config-changed`
findings, so a change of a tier is always visible. The gate `turn`
follows `warn-only` too: under it, `sinter check --gate turn` exits 0,
so a lead agent's gate opens too. `spec/manifest.md` section 9.3 gives
the rule, and record `exit-codes-by-gate` gives the exit codes.

**The report counts everything.** The compiled report is a complete
account: it counts every ack and every pin beside what it accepted,
cleared, or armed. It also carries signals about the health of the
machinery. A repository where no revision ever rose and no ack exists
is not clean. Its propagation has never fired, and its clean result
says only that nobody has looked.

### 8.1 The brief

Section 1 names two channels, enforcement and information. Section 1
cites two results: the decay of a plan within a step, and the decay of
rules after compaction. On the side of enforcement, the gates answer
them. On the side of information, without the brief, the agent would
have to remember. But Sinter is the one part of the system that knows
exactly what the agent needs now, because all of it is in the index.

**`sinter brief`** compiles it:

1. the active plan and step, with the state of each promise;
2. the approved text of every declaration that the step's promises
   target: the extent, not a summary, because the agent works against
   that text;
3. the decisions in force that the step's scope reaches, by `paths`
   and by `@cites` from anything in the scope;
4. the rules whose trigger meets the scope, each with the first line
   of its origin;
5. the live declines on anything in the scope;
6. the claims that overlap the scope;
7. the current blocking findings, with their fix lines.

The brief ranks these items by their distance in the graph from the
step's scope, and cuts them to a budget of bytes. For one index, it
always gives the same output.

**Delivery** is by hook. In Claude Code, the hook `SessionStart` fires
with `source: compact` after a compaction, and `UserPromptSubmit` fires
on every turn. The standard output of either hook becomes context.
`sinter init --hook claude-code` registers `sinter hook session-start`,
and on request `sinter hook user-prompt-submit` with a smaller budget.
To put the agreement back into the context from artifacts after each
compaction is the direct answer to both failures that section 1 cites.
It costs one view of facts that Sinter already holds. The brief only
informs: it enforces nothing, and no gate trusts anything in it. It
exists so that the turn report can stay short.

## 9. Infrastructure

**Implementation: OCaml.** The vocabulary is a variant type, and every
gate is an exhaustive match over it. So when someone adds a tag, every
check, query, and compiler that does not handle it fails to build: the
compiler enforces the rule, not a discipline. The language packs and
markdown sit behind one module signature. A native program starts in
milliseconds, which keeps the delay of a hook below the point where
people turn the hook off. The costs: agents write OCaml less well than
Rust or TypeScript; the binary links wasmtime (section 5.2) through a
small bridge in Rust; and version 1 does not support Windows. Sinter
runs git as a separate program and never links it. Records
`implementation-language` and `rust-bridge` give the reasons.

**The interchange format is JSON Lines (JSONL)**: one fact per line.
Each line is a node, an edge, an external id, a plan fact, an evidence
fact, a rule, or a finding, with a kind, a stable identity, and a schema
version. Each line is in the canonical form of RFC 8785. The values are
only strings, integers, booleans, flat arrays of those, and arrays of
flat objects, whose values are again strings, integers, or booleans
(record `json-handling`). This makes the canonical form simple to write:
sort the keys, and no floats exist. Only a machine writes the JSONL.
Conformance is byte equality with fixtures that the repository holds.

- **The JSONL is always derived, never a source.**
- **The two domains of hashes never mix.** An extent hashes as
  normalized text (section 3.4). An object of meaning, such as a
  commitment set, hashes over its canonical bytes.
- **No database.** The index lives in memory, with a cache on disk
  that Sinter can rebuild.

Section 13 gives the reasons for the format, and points to
`spec/jsonl.md`.

### 9.1 Tool surface

The binary is `sinter`. Sintering fuses loose particles into a solid
mass under pressure, without melting them. One core library sits
under thin surfaces: the command line, the hooks, and CI. All of them
speak the same JSONL. Agents use the command line through their shell,
as everyone else does. Section 11 gives the design of the commands.
Its principles:

- **Suggest, never touch.** `sinter init` is the one exception, and it
  touches only integration files that the tool owns, such as
  workflows, hook settings, and the skeleton of the manifest. It never
  touches governed text. Otherwise, Sinter can print a patch
  (`sinter patch`) on standard output, but it never applies one.
  Whoever applies the patch is the author of the diff, and the checks
  judge it like any other diff.
- **Three commands change durable state.** `approve`, `decline`, and
  `ledger abandon` write the ledger. All three refuse to run under an
  agent (section 6.4), and they share one set of refusals. CI on the
  default branch appends the `completed` entries (section 6.3).
  `declare` and `evidence import` write the state of the session and
  the evidence under `.sinter/`, which git ignores and which is never
  truth.
- **Absences by design.** There is no web interface, and no second
  language of predicates. Every feature in this document is a compiled
  view, a kind of ledger entry, or a definition of a finding. There is
  no `new`, no `close`, and no `ack` command. For an ack, Sinter prints
  the line, a person or an agent pastes it, and the checks judge that
  edit. There is no configuration outside the manifest and the rule
  files.
- **One serve loop.** A tool without state has no process to host a
  server, and a thin layer over the command line adds a surface without
  a capability. But a loop that keeps the WebAssembly runtime and the
  grammars loaded is a capability, because each fresh call pays to start
  the runtime and to compile the grammar. So Sinter has one serve loop.
  Its first form is `sinter serve`, a child process of its caller, which
  reads requests on standard input and answers on standard output. Later
  forms are adapters over the same loop: a detached process on a socket,
  a server of the Model Context Protocol (MCP), and a server of the
  Language Server Protocol (record `serve-mode`, and `docs/roadmap.md`).
- **Every surface is a saved query.** `sinter check` is the union of the
  definitions of findings. The turn report is
  `check --diff --gate turn`. CI runs `check --gate review` or
  `check --gate merged`. A hook is a filtered `check` or a `brief`. A
  gate can see nothing that `sinter query` cannot show.

### 9.2 Queries: a closed algebra

Sinter has neither a fixed menu of queries nor Datalog. It has a small
algebra over the stream of facts, about the size of the query language
of Bazel, a build tool. Section 12 gives its reasons, and
`spec/algebra.md` gives its rules. The universe of the algebra is the
facts: nodes, edges, external ids, plan facts, evidence, rules, hunks,
and findings, each with a kind. So a query returns fact lines, and
`sinter query --json` is a filtered `sinter scan`. Bazel's universe
holds only nodes, and that is its one mismatch with this domain. Half of
what matters here concerns edges, or an edge with its evidence: suspect
citations, dangling citations, and the evidence ladder.

`changed(base)` is the one selector with no counterpart in Bazel. It
selects the facts that a diff against a base touches. With it, the
hooks, CI, and `sinter check` are all `sinter query` with a different
base, and every surface of the tool is a saved expression.

**Output modes**, in the order of who uses them:

- lines in the style of ripgrep by default, such as
  `docs/auth.md:12:1: req auth-lockout v2  untraced(verifies)`. The
  order is always fixed, by kind, path, line, column, and id, and never
  the order of a hash table. Bazel added `--order_output` after an
  unstable order broke the scripts of its users;
- `--json`, for JSONL facts;
- `--sarif`, for findings, so that CI on a pull request gets annotations
  at each file and line from GitHub code scanning with no work of
  integration, as CodeQL and Semgrep showed;
- `--dot`, for anything that has the shape of a graph;
- `--jq`, bundled as the `gh` command bundles it, for whatever the
  algebra cannot express. Templates (`--format`) wait until someone asks
  for them.

To embed a real engine, such as views in SQLite or Datalog, stays the
documented way to grow, not a commitment. The condition to reconsider it
is a rule that the algebra cannot express.

## 10. Open questions

The questions of the design that are still open are in
`docs/roadmap.md`, with the other directions that are agreed but not
designed. Two earlier questions have answers:

- How a person approves: the confirmation on the controlling terminal
  and the agent markers (section 6.4).
- How a test runner's names match the tests in the source: runner
  adapters in the packs replace a fixed menu of strategies in the tool
  (record `runner-adapters`, `spec/packs.md` sections 10 and 11). The
  default adapter joins the names of the groups and the test, so the
  nested `describe` and `it` blocks of JavaScript need no strategy of
  their own.

## 11. Command-line surface

No specification covers the commands as a whole yet. Where a
specification holds a part of a command, the text gives the reason and
names the specification. A command that exists states its options in its
own help text, `sinter <command> --help`.

These conventions apply to every command:

- **The repository and the base.** Every command runs from anywhere
  inside a git worktree, and reads the manifest at the repository root
  (`spec/manifest.md` section 2). The base of a diff is by default the
  merge base of `HEAD` and the default branch, and `--base` overrides
  it. The working tree is always "now".
- **Fixed output.** Lines sort by kind, path, line, column, and id, and
  JSONL is in its canonical form (`spec/jsonl.md` section 2). Two runs
  on the same inputs give the same bytes, so a script or a diff of two
  runs can rely on the output.
- **One set of exit codes.** Every command uses five codes (record
  `exit-codes-by-gate`). Code 1 means at least one finding that blocks
  at the gate that `--gate` names, so a hook or a CI job decides with
  one comparison. Without `--gate`, and without `--strict`, a command
  reports every finding and exits 0. Code 2 means that the command line
  is wrong, code 3 that the command could not run here, and code 4 that
  it refused, as `approve` does for an agent.
- **One line for each finding**, which `check`, `status`, `query`, and
  the hooks print:

  ```
  <path>:<line>:<col>: <class> <subject> [<detail>]
    fix: <one-line instruction or the exact line to paste>
  ```

  A finding with no place in a file prints `-:-:-:` in the place of
  the location, so that the number of columns stays the same for
  `cut` and `awk`.

### 11.1 `sinter`

| group | commands |
|---|---|
| everyday | `status`, `brief`, `check`, `explain`, `query`, `declare`, `patch` |
| judgment | `inbox`, `approve`, `decline`, `compile`, `ledger` |
| plumbing | `scan`, `evidence`, `pack`, `hook`, `init`, `parse`, `serve` |

The everyday commands serve the agent and the person during the work.
The commands of judgment serve the person who approves, and only
`approve`, `decline`, and `ledger abandon` change the ledger (section
9.1). Every command accepts `-C <dir>`, `--manifest`, `--base`,
`--json`, `--color`, `-q`, `-v`, and `--no-cache`, and the variables
`SINTER_BASE` and `SINTER_PACK_CACHE` give defaults for the base and the
cache of packs. `parse` and `serve` exist: `parse` prints the tree of a
file or the matches of a query, and `serve` is the serve loop of section
9.1.

### 11.2 `sinter status`

`sinter status` answers "what should happen next". It prints the
active plan and step; each step with its derived state and its unmet
promises; the open obligations; the live declines and the claims that
touch the scope; the counts of findings; the health of the machinery,
such as the bumps since the base and the void acks; and a hint of the
next command, such as `sinter patch suspect`. Sinter stores none of
it, and computes every line again from the tree, the ledger, and the
evidence. `--done` prints nothing and exits 0 only when the plan is
done, for a merge queue or a script: `sinter status --done && git push`.

### 11.3 `sinter check`

`sinter check` evaluates every finding class over the working tree
against the base. This one command is the turn report, the CI jobs,
and the check before a commit: each is `sinter check --gate <gate>`,
with `--diff` where only the change counts, and with its own base. So
every gate sees what the others see (section 8). The classes and
their tiers are in `spec/algebra.md` section 9, diff mode in section
8.2, and the gates in `spec/manifest.md` section 9.

The other options narrow or change the output: `--path` and `--plan`
narrow it; `--strict` makes every finding block; `--acked` also shows
the findings that an ack accepted; `--strict-parse` turns a parse error
into exit code 3; `--summary` prints one line for each class; and
`--explain` prints the definition behind each finding. `--json` prints
the records of `spec/jsonl.md` section 8, and `--sarif` prints SARIF as
section 13 maps it.

### 11.4 `sinter query`

`sinter query <expr>` evaluates an expression of the algebra of
section 9.2 over the facts (`spec/algebra.md`). `--list` lists the
saved definitions, and `--explain <name>` expands one. Besides lines,
it prints `--json`, `--dot` for Graphviz, and `--jq <filter>`.
Examples:

```
sinter query 'untraced(verifies) ^ path(docs/auth/**)'
sinter query --dot 'rdeps(satisfies|verifies, req(auth-*))' | dot -Tsvg
sinter query 'kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - exempt'
```

### 11.5 `sinter declare`

`sinter declare <plan>[/<step>]` records the active plan and step for
the session (section 6.1). The record only anchors the brief and the
note about edits outside the scope, so it is the one statement of the
agent that Sinter accepts. `--clear` removes it, and `--show` prints
it with its effective scope.

### 11.6 `sinter brief`

`sinter brief` prints the brief of section 8.1, and marks each target
that nobody approved. `--plan` gives the brief of another step,
`--budget` sets the budget, and `--json` prints the facts of the brief
in the order of their rank.

### 11.7 `sinter explain`

`sinter explain` takes a finding, a class, a rule, or a subject. For a
finding, it prints the definition that the finding fired from, the
facts that put the subject in the result, the fix, and for an
`unmet-rule` finding the whole extent of the rule's origin. For a
subject, it prints every finding on it and every ledger entry about
it. This is where the reasons reach the moment when they change
behavior (section 7). The turn report carries the same text of the
origin, so an agent rarely needs this command; a person who reviews a
finding does.

### 11.8 `sinter decline`

`sinter decline <subject> --reason <text>` appends a decline to the
ledger (section 6.4, `spec/ledger.md` section 7). When the text
changes, the decline is void, and the old reason shows beside the new
delta, so the reviewer can judge whether the rework answered it. The
command has the refusals of `approve`.

### 11.9 `sinter inbox`

`sinter inbox` prints the list of section 6.8, from the ledger and
every branch that the remote knows. It marks a large batch of
approvals, because a large batch causes fatigue. `--fetch` fetches the
ledger and the branches first.

### 11.10 `sinter patch`

`sinter patch` prints, for each finding with a mechanical fix, a hunk
that resolves it, as a unified diff. Sinter writes nothing into the
tree: a person or an agent applies the diff with `git apply`, for
example `sinter patch suspect | git apply`, and the checks judge the
edit like any other. So the tool suggests and never touches (section
9.1). The classes with a mechanical fix are marked in `spec/algebra.md`
section 9, and section 9.1 there lists their edits, which
`unplanned-change` does not report as unplanned work. They include the
new pin of a suspect citation, the bump of an unbumped declaration, and
the move of a citation to the successor of a retired item, when the item
has exactly one successor (record `cite-the-successor`).

With `--ack`, the command also inserts the `@ack` lines that `check`
printed for ackable findings; that is a judgment, not a fix. Every other
finding has no mechanical fix by design: a dangling citation that no
rename and no difference of case explains, an unexercised test, and an
obligation of a rule need an edit or a judgment from someone who knows
the meaning.

### 11.11 `sinter approve`

`sinter approve` shows the pending delta, asks for a confirmation on
the controlling terminal, and appends the approvals to the ledger
(section 6.4). For each subject, the prompt offers three answers:
approve, skip, or decline with a reason. An item is pending when it
needs approval and the ledger holds no approval for its current text
(`spec/ledger.md` sections 5 and 11). The delta shows the changes of
words since the last approved text, one line for a rename with an
unchanged hash, and for a plan the promises added or removed and the
scopes widened.

The command refuses, with exit code 4, when it has no controlling
terminal or an agent marker is set (section 6.4), when the ledger ref
would not move forward, when a subject has a blocking finding such as
`dangling`, and when another branch took the revision (`spec/ledger.md`
section 5.3). `--dry-run` shows the delta and works anywhere, also under
an agent. `--yes` skips the prompt for each subject, but still needs a
terminal, so `yes | sinter approve` cannot work.

### 11.12 `sinter compile`

`sinter compile` writes documents that are views of the facts. It never
writes them into the repository, and for the same inputs each document
is always the same, so a diff of two compilations has meaning.

| document | content |
|---|---|
| `spec` | a compiled specification: the declarations of a selection, with the status, revision, approval, and coverage of each. `--pending` shows only the delta that `approve` would show. `--as-of` rebuilds what was approved at a point of the ledger |
| `coverage` | the requirements, with their sites, their tests and rungs, and the untraced items |
| `report` | the complete account of a diff (section 8), with the changes of configuration and where the evidence came from; CI on a pull request posts it |
| `residual-plan` | the unmet rest of a plan, with its journal, as a plan for a later branch (section 6.2) |
| `plan-preview` | the graph after the plan, and the checks of the plan (section 6.6) |
| `history` | the life of a subject: each approved revision and its changes, who approved it, the declines, and the plan that promised it |
| `release-notes` | the delta of the requirements between two points of the ledger (section 6.4) |
| `merge-order` | the claims in the order that promises across plans require (section 6.7) |
| `metrics` | the health signals with a time axis (section 6.4), as tables, not judgments |

### 11.13 `sinter ledger`

`sinter ledger` reads and moves the ledger ref (`spec/ledger.md`). `log`
and `show` print entries; `show` of a plan sets the approved commitment
set beside the current one. `verify` checks that the ref only moved
forward and that no entry changed (section 13 there), with `--signers`
for the signatures of section 6.4; CI on the default branch runs it.
`fetch` and `push` move the ref by fast-forward only, and
`push --replay` recovers a lost race (section 3.2 there).
`abandon <plan> --reason <text>` closes a plan that will never merge and
ends its claim; it is a command for a person, with the refusals of
`approve`.

### 11.14 `sinter evidence`

`sinter evidence import <file>...` reads the reports of test runners and
of coverage, binds each result to its test through the runner adapters,
and stores the results by tree key (section 4, `spec/packs.md` section
9). It warns when a report lies inside the worktree where git does not
ignore it, because the report itself would change the tree key. It
prints how many tests it bound, and names the tests that it could not
bind, with the nearest test by name. `sinter evidence key` prints the
current tree key, so that a test script can name its output folder.
Example:

```
pytest --junitxml .sinter/junit.xml --cov --cov-context test \
    && coverage json -o .sinter/cov.json \
    && sinter evidence import .sinter/junit.xml .sinter/cov.json
```

### 11.15 `sinter scan`

`sinter scan` prints the facts of every governed file as JSONL, in the
form of `spec/jsonl.md`. `sinter query --json` and `sinter check --json`
print filtered scans, so every tool that reads Sinter reads one
format.

### 11.16 `sinter pack`

`sinter pack add <name>` fetches a pack from the packs repository,
checks its hash, and records it in `sinter.lock`. `sinter pack fetch`
fills the cache from the lock file on another machine (`spec/packs.md`
section 12). `verify` runs the conformance fixtures of a pack and checks
the import sections of its wasm files (section 5.2). `list` and `info`
describe the packs. A pack whose hash does not match the lock stops
every command with exit code 3, because a pack that changed could change
every extent hash of its language.

### 11.17 `sinter init`

`sinter init` installs the integration that the design assumes. It
writes only what is missing, reports drift in what exists, and never
overwrites a user's edit. It touches only files that the tool owns:

| file | content |
|---|---|
| `sinter.toml`, `sinter.lock` | a manifest that names the packs for the languages in the tree, with `check.warn-only = true` (section 8); the lock |
| `.gitignore` | the line `.sinter/` |
| `.plans/` | the folder of plans |
| `refs/sinter/ledger` | an empty ledger commit, when the ref is absent |
| the settings of the harness | the hooks that call `sinter hook <event>`; for Claude Code, in `.claude/settings.json` |
| the CI workflows | a job for pull requests: `check --diff --gate review` on the host's merge ref, against the tip of the default branch (section 3.5), the import of evidence, the report, and SARIF. A job for the default branch: `check --gate merged`, `ledger verify`, and the step that appends `completed` (section 6.3), with the right to push the ledger ref. Both jobs fetch the ledger ref, because a clone does not |

The command that runs the tests is the repository's own. `init` writes a
marked step that it cannot fill, with the runner command that each pack
suggests, and `--check` reports the step while it is empty. No tooling
for merges exists, because the closing of a plan is a ledger entry.
`--hook claude-code` chooses the harness, and `--ci github` or
`--ci gitlab` the host. `--check` writes nothing and exits 1 when
anything is missing, and `--print` prints what it would write. The
skills of the Claude Code plugin reach a repository by the same route
(record `skills-distribution`).

### 11.18 `sinter hook`

`sinter hook <event>` is the entry point that `sinter init --hook`
registers. Each event is a filtered `sinter check` or a `sinter brief`,
so a hook sees nothing that those cannot see. Hooks inform and never
block (section 8).

| event | effect |
|---|---|
| `post-tool-use` | when the payload names a file (the tools `Edit`, `Write`, `MultiEdit`, and `NotebookEdit`), parse that file again and report its findings with their fix lines, and note an edit outside the active step's scope |
| `session-start` | print the brief, which the harness adds to the context; it fires after a compaction, the case that it exists for |
| `user-prompt-submit` | print the brief at a quarter of its budget, on every turn; registered only on request |

**The protocol of Claude Code.** The payload is JSON on standard input,
with `hook_event_name`, `tool_name`, `tool_input`, `session_id`, and
`source`. Feedback after a tool is exit code 2 with the findings on
standard error: the tool already ran, so the agent sees the findings and
nothing is undone. A clean file is exit code 0. The standard output of
`SessionStart` and `UserPromptSubmit` goes into the agent's context. The
state of the session, the declared step, is kept per `session_id`.
`--harness <h>` names the protocol, and the default is `claude-code`.

## 12. The query algebra

`spec/algebra.md` defines the algebra: its universe, syntax, types,
functions, and built-in finding classes.

**The universe is one fixed set of facts.** Sinter builds the facts
from five inputs: one working tree, one base, one ledger, one
evidence set, and one session. A query selects a subset of those
facts, and nothing else: it makes no numbers, no tuples, and no new
facts. Two queries with the same five inputs give the same bytes,
because the algebra has no access to the time, the environment, or the
network. Every gate depends on this: a check on a laptop and a check
in CI must agree.

**Categories work as types.** Each kind of fact belongs to one category,
such as `node`, `edge`, or `finding`. Sinter gives each expression a set
of categories before it evaluates the expression, and each function
states the categories that it accepts. When an argument's categories
cannot meet the accepted ones, Sinter rejects the query before it runs,
with a message such as
`src() accepts edge; argument has category {node}`. When the sets
overlap, Sinter drops the facts of the other categories silently, so
`src(all)` means "the sources of every edge". So the check catches
definite mistakes, and the writer of a query needs no annotations. This
is the same exhaustive check that OCaml gives the implementation from a
variant type of categories.

**Binary operators need spaces around them.** `a - b` is a
difference, and `auth-lockout` is one slug. Without this rule, a
parser could not tell a slug with a hyphen from a difference, and
slugs are the more common of the two. `^` and `+` follow the same
rule, so that all three look alike. `^` binds tighter than `+` and
`-`.

**The algebra stays small.** Every function is a filter over fields that
the JSONL already carries, or a closure over a finite graph, which adds
facts until nothing new comes, so every query ends. The closures `deps`,
`rdeps`, and `paths` follow suspect edges, because a citation of an old
revision is still a citation, and they ignore dangling edges. `paths` is
Bazel's `allpaths`. Bazel's `somepath` is left out, because its answer
is not a fixed function of the graph. Users cannot add functions, and
the algebra has no recursion beyond the closures and the fixpoint of
supersession, no arithmetic, and no strings other than names and globs.

**A finding class is a saved definition with tiers.** A saved
definition is a name, optional parameters, and an expression. A
definition with tiers is a finding class, which `sinter check`
evaluates; one without tiers is only for queries. So one form serves
both, because a finding is a definition that someone decided to
enforce. A repository's own definitions live in rule files (section
7), and they cannot take the name of a built-in definition.

**`changed(base)` defines "touched" for each category.** The simple
rule, "the extent meets a hunk", is wrong for declarations in both
directions. An `@ack` line added inside a section is not a change of
meaning, and a section deleted as a whole leaves nothing to meet. So a
declaration counts as changed when it is new, its kind changed, or its
extent hash differs from the base, and a plan when its commitment set
differs. A citation whose target vanished counts as changed, even when
its own bytes did not change. `spec/algebra.md` section 8.1 gives the
table.

**Diff mode subtracts the findings of the base.** `check --diff`
reports the findings of the working tree minus the findings of the
base tree, compared by their ids. It reads the base tree from the
objects of git, with no checkout, and with an empty evidence set. A
finding that existed at the base and still exists is debt, not a
violation. This rule also catches a new `dangling` or `retired`
finding on a line that the diff never touched. The cost: a test that
was already unexercised at the base shows as new on the first change
that measures it. This cost comes once for each such test, and it is
accepted.

**Some classes come from the engine.** A class that concerns input
that does not parse, or that compares two trees in a way that the
algebra does not model, comes straight from the scanner or from the
comparison of the trees. Such a class is marked *engine*, and its
findings are ordinary finding facts. Four global rules apply after
evaluation and are never written into a definition: historical facts
make no findings; a live `@ack` accepts what it names; the classes of
the evidence ladder appear only when evidence exists; and a closed
plan makes no findings.

**Three classes measure incompleteness, not violations.** `untraced`,
`unmet-promise`, and `awaiting-approval` exist so that `sinter status`
and the closing of a plan can read them. The turn report never lists
them as violations (section 8).

**A name that matches nothing is not an error.** `req(auth-lockout)`
gives the empty set on a branch where nobody declared `auth-lockout`
yet, which is what the query should mean there.

**An example.** Take the plan of section 6.1, after its second step
landed and before any test exists:

```
$ sinter query 'promises(active) - met(promises(active))'
.plans/auth-lockout.md:19:1: promise auth-lockout/verify-against-the-reqs verifies auth-lockout
.plans/auth-lockout.md:20:1: promise auth-lockout/verify-against-the-reqs verifies lockout-notify

$ sinter query 'untraced(verifies)'
docs/auth.md:12:1: req auth-lockout v2
docs/auth.md:31:1: req lockout-notify v1

$ sinter query 'kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - scope(triggered(kind(rule))) - exempt'
src/session/store.rs:88:1: hunk +14/-3
```

The last line is a hunk outside the scope of every step: the agent
simplified a store that the plan never mentions. The turn report names
exactly this hunk as a violation (`unplanned-change`), and a lead
refuses the hand-back while it stands. The honest ways out are the two
that the amendment rule allows. Revert the hunk
(`git checkout src/session/store.rs`), or widen the plan's scope in
`.plans/auth-lockout.md`, which needs a new approval. Sinter does not
accept the hunk while the plan says nothing about it.

## 13. JSONL interchange

`spec/jsonl.md` defines the JSONL: its canonical form, the record of
each kind, and the identity of facts. `spec/ledger.md` defines the
entries of the ledger, which are JSONL records too.

**A strict canonical form.** Each line is a JSON object in the canonical
form of RFC 8785. The values are only strings, integers in a safe range,
booleans, and flat arrays of those. One more shape exists: an array of
flat objects, whose values are only strings, integers, and booleans. An
object appears only as a member of such an array. A finding needs this
shape to carry its related places, each with a label (record
`related-places`). There are no floats and no nulls, and an absent value
is a missing key. With these limits, the canonical form is simple to
write and hard to get subtly wrong: sort the keys, and no number needs a
rule for its format. So conformance can be byte equality. A string from
a file keeps the characters that the file holds, with no Unicode
normalization (record `text-as-written`). The schema version `v` rises
only for an incompatible change, never for a new optional field.

**Derived fields are in the records.** A record carries fields that
Sinter derives from the ledger, the evidence, the session, or the
base, such as `inforce`, `approved`, and the rung of a `@verifies`
edge. A user of `jq` then needs to derive nothing again. The
conformance comparison includes these fields, so the fixture of each
pack holds its own ledger and evidence, and checks the whole path
from a report of a test runner to the rung of an edge, not only
parsing. A release of the tool that changes the meaning of a derived
field must make every pack's fixture again. That cost is intended.

**A declaration records two spans.** The span of a declaration in
markdown is its tag line, and its extent, the whole section, is a
separate span. So a tool can mark the tag without marking pages of
prose.

**Ids come from content.** Three operations need a fact to keep its
id when lines move: the subtraction of diff mode, the target of an
`@ack`, and the fingerprint of a finding in SARIF. So an id comes from
content wherever content exists, such as `req:auth-lockout`, and from
a position only as a last resort. An id stays the same when the text
is indented again, formatted again, moved down the file, or pinned
again. It changes when the slug changes, because a rename is a
deletion and a declaration. The hash of a commitment set leaves out
the names of the steps, so a free rename of a step does not change
it, and a decline bound to it stays live.

**The ledger is history.** The records of a scan are derived, so they
carry no time and no author. Entries of the ledger record judgments,
so they carry both. The id of an entry comes from its content, so two
writers never make one id for two entries, and the recovery from a
lost push race is a union of sets. Where order matters, the time of
an entry decides it, never its place in the file. An approval of a
plan stores the approved commitment set itself, because only the set
can show that a later set lies inside it. Containment of globs is
decided by structure and with caution: what the check cannot prove
counts as a wider scope. So the check errs toward asking the person,
which is the right direction for an approval.

**SARIF output.** No specification covers SARIF yet. The design maps a
finding to SARIF as follows:

| finding | SARIF |
|---|---|
| class | `ruleId` |
| tier | `level`: `warn` is `warning`, `block` is `error`, and `off` is not written |
| location | `physicalLocation`, with `artifactLocation.uri` and `region` |
| id | `partialFingerprints.sinterId/v1` |
| mechanical fix | `fixes[]`, with the hunk of the patch |
| detail | `message.text` |
| related places | `relatedLocations` (record `related-places`) |
| fix of an ackable finding | a second line of the message |

## 14. Manifest reference

`spec/manifest.md` defines the manifest `sinter.toml`: its tables,
its keys, its errors, and the facts that it yields.

**Short, with defaults.** Every key with a sensible default is
absent from a manifest until a project needs another value.
`sinter init` writes only what it had to choose. The smallest useful
manifest names the files of the markdown pack, and nothing more.

**One meaning for each name.** Each setting has a name with one
meaning, and two settings with one effect became one (record
`manifest-names`). The keys sit in tables by the part of Sinter that
they act on: `[scan]`, `[check]`, `[plan]`, `[ledger]`, and
`[evidence]`.

**The agent can edit it, and every change shows.** The manifest is
inside what the agent can change (section 5.1). The finding
`config-changed` reports each change of a setting on every diff, and
nothing can turn it off. So a lowered tier is always visible.

**A manifest and a lock file.** The manifest names the release of a
pack as `MAJOR.MINOR`, which any patch release meets. The lock file
`sinter.lock`, which the tool writes, holds the exact release and hash
that CI checks. This is the split of Cargo, for the same reason: the
manifest stays readable, and the lock stays exact. `pack-mismatch`
compares the cache with the lock.

**Each file in one pack.** The manifest names the files of each pack.
A file in the files of two packs is an error, not a case for a rule of
precedence.

**Rules live outside the manifest.** A repository's rules and finding
classes live in rule files, beside their reasons (section 7, record
`rule-files`). The manifest holds settings only, and no rule or finding
class.

**Three gates.** `turn`, `review`, and `merged` each have a set of
tiers. Only `review` and `merged` block by machine, in CI. `turn` is
the scale of severity that the turn report, its exit code, and a lead
agent read (section 8).

**Deliberately absent.** The manifest has no table for hooks: the
settings file of the harness holds the hooks, and `init` writes it, so
nothing needs to be set twice. It has no switch for journals, because a
journal exists when its file exists. The folder of evidence
(`.sinter/evidence`) and the ledger ref are fixed. Some settings wait
for the work that needs them: the budgets of the brief (12,000 bytes, a
quarter of that for the brief on each turn, and 2,000 bytes for the
origin of an unmet rule), the signatures of the ledger, and the share of
acknowledged obligations that the judge samples. There is no table of
tags for the classification of items, which nobody has asked for. A
check that declarations of a kind live under one path needs no table
either: it is one finding class, such as
`kind(req) - path(docs/requirements/**)`. `plan.locations` is a
different setting: it says where a promised declaration can be met
(section 6.1).
