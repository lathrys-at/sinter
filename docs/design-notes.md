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

## 11. CLI Surface

The surface is specified as the help text itself. Conventions that apply to every verb:

- **Repo discovery.** Every verb runs from anywhere inside a git worktree; the repo root is `git rev-parse --show-toplevel` and the manifest is `sinter.toml` there. Nothing is looked up in the home directory except the pack cache.
- **Base.** `--base <rev>` is accepted by every verb that reads the diff. Default: `git merge-base HEAD <branch>` where `<branch>` is the manifest's `default-branch` (`main`). The working tree is always "now."
- **Output is deterministic.** Line output is sorted by `(kind, path, line, col, id)`. JSONL is canonical (§13.1). Two runs on the same tree, base, ledger, and evidence produce identical bytes.
- **Exit codes** are shared: `0` clean/success · `1` findings present (or plan not done under `status --done`) · `2` usage error · `3` environment error (manifest invalid, pack missing or hash mismatch, git unavailable, parse error in a governed file when `--strict-parse`) · `4` refused (`approve`, `decline`, or `ledger abandon` without a tty or under an agent marker; ledger not fast-forward; revision taken). A hook translates these into its harness's protocol (§11.18).
- **Line format** for findings, used by `check`, `status`, `query` when the result contains findings, and hook stderr:

  ```
  <path>:<line>:<col>: <class> <subject> [<detail>]
    fix: <one-line instruction or the exact line to paste>
  ```

  Identifiers containing whitespace (JS test titles) are double-quoted. Facts without a location (external ids, runs) print `-:-:-:` in the location slot so the column count is stable for `cut`/`awk`.

### 11.1 `sinter`

```
sinter — plans die into facts; facts are checked

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
    approve     Approve pending items into the ledger (human, on a terminal)
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
  --base <rev>        Diff base (default: merge-base of HEAD and the default branch)
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
  CLAUDECODE, …       Agent markers; approve refuses when any is set
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
    3. Open obligations: unplanned hunks, unmet-rule items, unapproved targets.
    3a. Live declines on anything in scope, with their reasons.
    3b. Claims: other branches' approved plans overlapping this scope, and
        promises here that are waiting on promises there (§6.7).
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
                  or 'unmeasured' where the manifest allows it). For merge
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
                    debt included. Diff-relative classes (unbumped, unplanned-
                    change, config-changed, code-drift, renamed, promise-
                    collision) are computed against --base and reported too.
  --diff            Diff mode: only findings the diff introduced — those whose
                    identity (sinter scan --help, "Finding identity") is absent
                    from the finding set of the base tree.

SELECTION
  <class>...        Restrict to these finding classes
  --gate <g>        Tier configuration to apply: turn | review | merged.
                    Without it, everything is reported and nothing is 'block'
                    for the exit code unless --strict. Classes at tier 'off'
                    for the gate are not evaluated.
  --path <glob>     Only findings located under <glob>; repeatable
  --plan <slug>     Only findings located within a plan's scope
  --strict          Treat 'warn' as 'block' for the exit code
  --acked           Also print findings accepted by a live @ack (marked)
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
  sinter check --summary --gate review
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
              test(id) external(ns/id) rule(n)  path(glob)  changed(base|<rev>)
              active  historical  exempt  acked(target)  findings(class|…)
  Traversal   out(k|…, S)  in(k|…, S)  src(E)  dst(E)  subject(F)
  Closure     deps(k|…, S)  rdeps(k|…, S)  paths(S, T)
  Plan        scope(S)  promises(S)  met(P)  done(S)  waiting(P)
  Status      inforce(S)  approved(S)  bumped(S)  declined(S)
  Edge        suspect(E)  dangling(E)
  Evidence    wrong-source(E)  never-ran(E)  failed(E)  unexercised(E)
              unmeasured(E)  passing(E)
  Law         obligations(R)  triggered(R)  judged(n)
  Operators   +  union    ^  intersection (binds tighter)    -  difference
  Names may contain '*' as a glob. Kinds may be alternated with '|'. Saved
  definitions are invoked like functions: untraced(verifies), unmet(active).

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
  sinter query 'untraced(verifies) ^ path(docs/auth/**)'
  sinter query --count 'suspect(kind(edge))'
  sinter query --json 'deps(refines, req(auth-lockout))'
  sinter query --dot 'rdeps(satisfies|verifies, req(auth-*))' | dot -Tsvg
  sinter query 'kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - exempt'
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
    6. Claims overlapping the scope, and promises here waiting on promises
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
  subject in the result; the fix line; and for unmet-rule findings the origin
  decision's full extent — context, choice, alternatives considered.
  For a class: its definition, tiers per gate, ackability, mechanical fix.
  For a rule: trigger, `expect` and its kind, scope, and its origin's
  extent.
  For a subject: every finding on it and every ledger entry about it.

  This is the why-layer reaching the moment it changes behavior (§7). The
  turn report includes the same origin text, so an agent normally does not
  need to run this; a human reviewing a finding does.

EXAMPLES
  sinter explain finding:unmet-rule:req:auth-lockout:ste-docs
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
  agent markers refuse, exit 4.

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

    approvals     pending approvals per branch, with batch size — large
                  batches flagged (review fatigue)
    deaths        plans whose death is blocked, and on what
    reworks       declines whose subject has since changed: the rework
                  landed; is it right now?
    spot-checks   rule acks recorded by agents since the last inbox visit
    claims        overlapping scopes, waiting cross-plan promises, and
                  claims released by branch deletion since the last visit

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
    unbumped       bump the revision by one and re-pin its citations
    unpinned       pin @satisfies/@verifies to the target's current revision
    typo-tag       replace a near-miss tag word with the vocabulary word
    stale-ack      delete the void @ack line
    ack            for findings of ackable classes, insert the @ack line
                   'check' printed (requires --ack; a judgment, not a fix)

  Anything not listed has no mechanical fix by design: dangling citations
  whose target was never renamed, unexercised tests, and rule obligations
  need an edit or a judgment.

OPTIONS
  --ack             Include @ack insertions (see above)
  --path <glob>     Restrict to hunks under <glob>; repeatable
  --plan <slug>     Restrict to the plan's scope
  --dry-run         Print the count of hunks per class instead of the diff

EXAMPLES
  sinter patch suspect | git apply
  sinter patch unbumped --path 'docs/**'
  sinter patch --ack unexercised --path 'tests/integration/**' | git apply
```

### 11.11 `sinter approve`

```
sinter approve — approve pending items into the ledger

USAGE
  sinter approve [options] [<subject>...]

  Renders the pending delta and asks for confirmation on the controlling
  terminal (/dev/tty, never stdin), then appends approvals to refs/sinter/ledger.
  With 'decline' and 'ledger abandon', this is one of the three verbs that
  change durable state.
  Each approval records HEAD and the branch, and is signed when [ledger].sign
  is set. At each subject the prompt offers: approve / skip / decline (with a
  reason, written as a decline entry — see sinter decline --help).

  Pending means: an approval-gated declaration whose (slug, rev, extent
  hash) has no ledger entry — new items and bumped items; and a plan whose
  current commitment set is not approved against its most recent approved
  set (§13.7). Text changed under an unchanged rev is not pending — it is
  unbumped here, and on another branch it is the reservation refusal below. Free amendments
  (narrowing scope; splitting, merging, renaming, reordering steps with the
  commitment multiset preserved) never make a plan pending.

  The delta is rendered as 'sinter compile spec --pending' renders it: for
  text kinds, the extent with word-level changes since the last approved
  extent; for a rename with an unchanged hash, one line saying so; for
  plans, added and removed promises and widened scope per step.

REFUSES (exit 4) when
  - /dev/tty cannot be opened (no controlling terminal)
  - an agent marker is set: CLAUDECODE or any name in [approve].refuse_env
  - refs/sinter/ledger is not a fast-forward of its fetched remote (--push
    fetches first; without --push the check uses the last fetched state;
    a lost race is recovered with 'sinter ledger push --replay')
  - any subject being approved has a blocking finding on it (dangling,
    duplicate, invalid-target, parse-error)
  - the ledger already holds an approval for the same slug and rev with a
    different extent hash: the revision is taken by another branch. The
    refusal names it and the fix is a bump ("rebase to v4").

OPTIONS
  <subject>...      Restrict to these subjects, as 'req:auth-lockout',
                    'design:session-store', 'plan:auth-lockout'
  --dry-run         Render the delta, approve nothing, exit 0 (works anywhere,
                    including under a harness)
  --note <text>     Attach a note to every approval written this run
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
                  and verifying tests (rung shown), plus untraced items.
                  Anonymous sites render as path:line links.
  report          The complete account for the diff: findings by class and
                  tier; every ack and what it accepted or cleared; law
                  touched by the diff; machinery health; evidence provenance.
                  This is what PR CI posts.
  residual-plan   The unmet remainder of a plan as a plan skeleton —
                  steps with unmet promises and their scopes, and the plan's
                  journal if it has one — under a successor slug (plan slugs
                  are permanent, §6.3), for a later branch. Emitted, not
                  written to .plans/.
  plan-preview    The graph after the plan, as if every promise were met:
                  declarations that will exist, edges they will carry, items
                  that become suspect or retired, coverage gaps that close or
                  open, and the plan-level findings (§6.6). This is what the
                  plan approval is taken against.
  history         A subject's life from the ledger joined with git: each
                  approved revision's extent (word-diffed against the previous),
                  who approved it and when, declines and their reasons, the
                  plan that promised it, the merge that completed that plan.
  release-notes   The requirements-layer delta between two ledger points:
                  declarations approved, bumped, retired, or completed in the
                  interval, rendered with extents. Derived, never written.
  merge-order     Claims in dependency order from cross-plan promises (§6.7),
                  or the cycle that prevents one.
  metrics         Health signals with a time axis: revision churn per item,
                  amendments per plan, approval-to-completion time, approvals per
                  approval session and seconds per approval, acks per week,
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

  log       Entries newest first: approvals, declines, completions — id,
            subject, rev, by, branch, when, note or reason
  show      Every approval for a subject, and for plans the approved
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
  abandon   Record that an approved plan will never merge: its claim dies,
            with the waiting-on promises resting on it. A human verb —
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
  sinter init [--hook <harness>]... [--ci <host>] [--default-branch <branch>]
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
                                 --base at the tip of the default branch
                                 (§3.5): check --diff --gate pr, evidence
                                 import, report as a comment, SARIF
                                 upload. The test-run
                                 line is the repo's own bash: init writes a
                                 marked RUN-TESTS step it cannot fill,
                                 seeded with each pack's suggested
                                 invocation, and --check flags it while
                                 unfilled. Both jobs fetch
                                 refs/sinter/ledger explicitly — clones do
                                 not.
                                 Main job: check --gate main, ledger verify,
                                 and the completion step — append 'completed'
                                 for merged plans meeting §6.3's condition;
                                 needs push rights to refs/sinter/ledger.
                                 No merge tooling exists: death is a ledger
                                 fact (--ci github writes .github/workflows/)

OPTIONS
  --hook <harness>   claude-code (others by PR to the harness table)
  --ci <host>        github | gitlab
  --default-branch <branch>
                     Default branch for base computation (default: main)
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
                  errors, typo-tags, invalid targets, any finding on facts in
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

`U` is a function of `(T, B, L, E, S)`; two invocations with the same five inputs see the same universe and print the same bytes. The algebra has no access to time, environment, or the network. `ref-state` (networked external ids, §5.3) is therefore not a function of the algebra but a separate importer that materializes `refstate` facts into `E`-like scratch for the main CI tier, and is deferred with `@pin`.

### 12.2 Kinds and categories

Every kind belongs to exactly one **category**. `kind(x)` accepts either.

| category | kinds | located? | notes |
|---|---|---|---|
| `node` | `req` `design` `decision` `plan` `step` `test` `site` | yes | `site` is an anonymous `@satisfies`/`@cites` source in code and carries the code hash `ch`; `test` is named by the pack's ID strategy |
| `edge` | `satisfies` `verifies` `refines` `cites` `supersedes` | yes | `src` is a node or a rule; `dst` is a node, an external id, or unresolved |
| `external` | `external` | no | one per distinct `ns/id` cited anywhere |
| `promise` | `promise` | yes | one per promissory tag in a plan step |
| `evidence` | `run` `cov` `judgment` | no | keyed to the tree key; `cov` is the site-level join, not raw lines; `judgment` is a judge's or checker's verdict |
| `law` | `rule` `gate` | yes (manifest) | a rule's origin is a `cites` edge with the rule as `src` |
| `ack` | `ack` | yes | live or void |
| `ledger` | `claim` `decline` | no | projections of the ledger: a claim of another branch's approved plan (§13.5); a live refusal bound to an extent hash |
| `hunk` | `hunk` | yes | one per hunk of `git diff B`, new-side coordinates |
| `tombstone` | `tombstone` | yes (base coordinates) | a fact present in `B`'s index and absent from `T`'s; carries the old `id`, `kind`, and extent hash |
| `finding` | `finding` | yes (its subject's) | derived; class and subject define identity |

"Located" facts carry `path`, `line`, `col`, `eline`, `ecol`. Only located facts are returned by `path(…)`, `scope(…)`, `historical`, `exempt`, and `acked(…)`.

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
- **Keywords** `all`, `active`, `historical`, `exempt`, `base` are reserved as bare words; a saved definition may not shadow a built-in.

### 12.4 Categories as types

Each expression is assigned a **category set** statically, before evaluation:

- `all` → every category. `kind(K)` → the categories of the kinds in `K`. Name selectors → their kind's category. `path`, `historical`, `exempt`, `acked` → every located category. `changed` → every category (tombstones and hunks included). `active` → `{node}`. `findings` → `{finding}`.
- `out`, `in` → `{edge}`. `src`, `dst`, `deps`, `rdeps`, `paths` → `{node, external, law}` (`src` of a rule's origin edge is a rule). `subject` → every category a finding can be about. `scope` → located categories plus `hunk` (and accepts `claim` in its argument). `promises` → `{promise}`. `met` → `{promise}`. `done` → `{node}`. Predicates, including `declined`, → the category set of their argument, intersected with what they accept. `obligations`, `judged` → every category (an obligation's subject is whatever the trigger selected). `triggered` → `{law}`.
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
| `external(ns/id)` | — | external facts matching |
| `path(g)` | — | located facts whose `path` matches `g` (a fact spanning lines is matched by its `path` alone) |
| `changed(b)` | — | see §12.7; `b` is `base` or a revision |
| `active` | — | the active plan and, if declared, the active step (§6.1); only in-force plans are candidates; `∅` if no plan is active |
| `historical` | — | located facts under a manifest `historical` path |
| `exempt` | — | located facts under a manifest `exempt` path, in a plan file, in the manifest, or in the lockfile |
| `acked(t)` | — | located facts `f` such that the tag-bearing block containing `f` carries a **live** `@ack` whose target `t` applies to `f`: the class or rule name matches, and the ack's subject, if given, equals `f`'s key (`dst` slug for an edge, slug for a node, `id` otherwise) |
| `findings(C)` | — | finding facts whose class ∈ `C` |

**Traversal** (one hop, typed)

| function | accepts | denotes |
|---|---|---|
| `out(K, S)` | `S`: node, law | `{e ∈ edges : kind(e) ∈ K ∧ src(e) ∈ S}` |
| `in(K, S)` | `S`: node, external | `{e ∈ edges : kind(e) ∈ K ∧ dst(e) ∈ S}` |
| `src(E)` | edge | `{src(e) : e ∈ E}` |
| `dst(E)` | edge | `{dst(e) : e ∈ E ∧ dst(e) ≠ ⊥}` — dangling edges contribute nothing |
| `subject(F)` | finding | `{subject(f) : f ∈ F}` |

**Closures** (least fixpoints; dangling edges are ignored; suspect edges are followed — a stale citation is still a citation)

| function | accepts | denotes |
|---|---|---|
| `deps(K, S)` | node, law | least `X ⊇ S` with `dst(out(K, X)) ⊆ X` |
| `rdeps(K, S)` | node, external | least `X ⊇ S` with `src(in(K, X)) ⊆ X` |
| `paths(S, T)` | node, external, law | `deps(edge, S) ^ rdeps(edge, T)`: every node on some path from `S` to `T` over any edge kind. This is Bazel's `allpaths`; `somepath` is omitted because its answer is not a deterministic function of the graph |

**Plan**

| function | accepts | denotes |
|---|---|---|
| `scope(S)` | plan, step, rule, claim | located facts and hunks whose `path` matches the effective scope of some `x ∈ S`. A step's effective scope is its own `@scope` if present, else its plan's; a plan's effective scope is the union of its steps' (its own `@scope` is the default for steps and the bound on them — a step exceeding it is a `scope-outside-plan` finding); a rule's is its `scope` field. `∅` if `S` has no scope-bearing fact |
| `promises(S)` | plan, step | promise facts whose step is in `S` or whose plan is in `S` |
| `met(P)` | promise | promises that are met (§6.1: a declaration with that slug within the step's scope; an edge of that kind within scope that is neither dangling nor suspect; a `verifies` edge within scope at rung `passing`, or `unmeasured` if the manifest allows) |
| `done(S)` | plan, step | steps all of whose promises are met — or, for a step with no promises, whose scope intersects `changed(base)` — and whose in-scope `verifies` edges are all at rung `passing`/allowed; plans all of whose steps are done and whose in-scope `verifies` edges are all at `passing`/allowed |

**Status predicates** (filters: `pred(S) ⊆ S`)

| function | accepts | keeps `f ∈ S` iff |
|---|---|---|
| `inforce(S)` | any | for a declaration: `f` carries no status tag and no effective `@supersedes` edge has `dst = f` (effective: the edge's source is in force and, if its kind is approval-gated, approved, §3.3 — a fixpoint over supersession chains; on a `supersedes` cycle every member is treated as in force and retired by nothing, and the `cycle` finding blocks, so the state is loud rather than guessed). For a plan, its steps, and its promises: the ledger holds no `completed` or `abandoned` entry for the plan (§6.3). Every other kind: kept |
| `approved(S)` | any | `f` is a declaration of a gated kind with a ledger approval for `(slug, rev, xh)`; or a declaration of a non-gated kind; or a plan whose current commitment set is approved against its latest approved set (§13.7 containment, not `csh` equality); or a step of an approved plan; or any other kind |
| `bumped(S)` | node | `f` is a declaration absent from `B`'s index, or present with `rev_B(f) < rev_T(f)` |
| `declined(S)` | node | `f` is a declaration or plan with a live `decline` fact: one whose recorded hash equals `f`'s current extent hash (declarations) or commitment-set hash (plans) |
| `waiting(P)` | promise | `p` targets a slug declared nowhere in `T` but promised for declaration by some `claim` — an ordering fact, reported instead of `dangling` |

**Edge predicates**

| function | keeps `e ∈ E` iff |
|---|---|
| `suspect(E)` | `rev(e) ≠ ⊥ ∧ dst(e) ≠ ⊥ ∧ dst(e)` is a declaration `∧ rev(dst(e)) ≠ rev(e)` |
| `dangling(E)` | `dst(e) = ⊥` — no declaration has the slug, or the external id's namespace is undeclared or its id fails the pattern |

**Evidence predicates** partition `kind(verifies)`: every verifies edge satisfies exactly one, tested in this order. `t = src(e)`, `sites(e) = src(in(satisfies, dst(e)))` minus test nodes (a test's own `@satisfies` never connects itself), `runs(t)` the run facts for `t` at `T`'s tree key, `cov(t, s)` the attributed cov fact for `(t, s)`, `agg(s)` the aggregate cov fact for `s`.

| function | keeps `e ∈ E` iff |
|---|---|
| `wrong-source(E)` | `kind(t) ≠ test` — the comment attached to something `tests.scm` does not capture |
| `never-ran(E)` | `runs(t) = ∅` |
| `failed(E)` | some `r ∈ runs(t)` has `status ∈ {fail, error, skip}` |
| `unexercised(E)` | all runs pass, `sites(e) ≠ ∅`, and either the coverage of each test exists for `t` and `∀s ∈ sites(e): cov(t, s).hit = 0`, or only the coverage of the whole run exists and `∀s ∈ sites(e): agg(s).hit = 0` — the run as a whole never touched the sites, so neither did `t` |
| `unmeasured(E)` | all runs pass, `sites(e) ≠ ∅`, no coverage of each test for `t`, and some `agg(s).hit > 0` or no coverage at all was imported |
| `passing(E)` | all runs pass and either `sites(e) = ∅` (nothing to connect to; `untraced(satisfies)` reports the target separately) or some `cov(t, s).hit > 0` |

**Law**

| function | accepts | denotes |
|---|---|---|
| `obligations(R)` | law | `⋃_{r ∈ R} ( eval(trigger(r)) - eval(expect(r)) )` — the obligation subjects of each rule. Rule expressions are evaluated in the same universe; a rule whose trigger or `expect` mentions `obligations` is rejected at manifest load (no recursion through the law) |
| `triggered(R)` | law | `{r ∈ R : eval(trigger(r)) ≠ ∅}` |
| `judged(n)` | — | subjects with a `judgment` evidence fact for rule `n` whose verdict is `pass` and whose recorded hash matches the subject's current extent (or commitment-set) hash — the `expect` selector for judged rules |

For an `acked` `expect`, ack liveness is `subject ∈ eval(trigger)` — the `expect` side never re-enters (§3.3); no circularity.

**Set operators.** `S + T` union, `S ^ T` intersection, `S - T` difference, all over fact identity.

That is 37 names. Grouped as above they fit on two pages, and every one is either a comprehension over fields the JSONL already carries or a least fixpoint over a finite graph. There are no user-defined functions, no recursion beyond the three built-in closures and the two fixpoint predicates, no arithmetic, and no strings other than names and globs.

### 12.6 Saved definitions

A saved definition is a name, an optional parameter list, and an expression. Built-ins ship in the tool; the manifest adds or overrides in `[findings]`:

```toml
[findings.untraced]
params = ["e"]
expr   = "kind(req|design) ^ inforce(all) - dst(in($e, all))"

[findings.design-awaiting-approval]
expr   = "kind(design) ^ inforce(all) - approved(all)"
```

Invocation is `untraced(verifies)` or bare `design-awaiting-approval`. Parameters are substituted as text for `$name` tokens before parsing; a parameter may therefore be an expression, a kind list, a name, or a glob, and the result is parsed and category-checked as a whole. Definitions may reference other definitions; cycles are a manifest load error. A definition with `tiers` (per gate), and optionally `ackable`, `detail`, and `fix` (the mechanical fix class), is a finding class and is evaluated by `check`; one without `tiers` is query-only. There is one table, because a finding is just a definition someone decided to enforce. Overriding a built-in finding's `expr` is allowed and is itself a `law-touched` finding on the diff that does it.

### 12.7 `changed(base)` and diff mode

`changed(b)` is the fact set touched by `git diff b` against the working tree. The diff compares each file of the working tree that git does not ignore with its blob in the base, whether git tracks the file or not, and a file that the base does not hold is wholly added ([spec/algebra.md](../spec/algebra.md) section 8.1). "Touched" is defined per category, because the naive definition — extent intersects a hunk — is wrong for declarations in both directions (an `@ack` line added inside a section is not a change of meaning; a section deleted wholesale leaves nothing to intersect):

| category | `f ∈ changed(b)` iff |
|---|---|
| `req` `design` `decision` | `f ∉ index(b)`, or `xh_b(f) ≠ xh_T(f)` (the normalized extent hash, §3.4) |
| `plan` `step` `promise` | the plan's commitment set differs from `index(b)`'s for that plan, or the fact is new |
| other located facts | new, or the fact's line span intersects a hunk's new-side span |
| `hunk` | always (hunks exist only relative to `b`) |
| `tombstone` | always |
| `edge` | new, or its line intersects a hunk, or `dst(e)` is a tombstone — a citation whose target vanished is changed even if its bytes are not |
| `evidence` `external` | never |

`b` may be `base` (the `--base` value) or a git revision. Evaluating `changed(x)` for an `x` other than the base requires a second index for `x`, built and cached on demand.

**Diff mode** (`check --diff`) is **baseline subtraction**: `check --diff` reports `F(T) - F(b)` where `F(x)` is the finding set of tree `x` and subtraction is by finding identity (§13.6). `F(b)` is evaluated on the base tree read straight from git objects — no checkout — with the same ledger and an **empty evidence set**: evidence-ladder findings at the base are all `never-ran`, so a pre-existing `unexercised` test surfaces as introduced on the first PR that measures it, a one-time cost of first light, accepted. A finding that existed at the base and still exists is debt, not a violation; a finding absent at the base is what this diff introduced. This subsumes the intersection rule for every class where it was right and repairs it for `dangling` and `retired`, where the introduced finding sits on a line the diff never touched. Diff-relative classes — `unbumped`, `unplanned-change`, `config-changed`, `code-drift`, `renamed`, `promise-collision` — have `F(b) = ∅` by construction and appear in both modes.

### 12.8 Built-in finding definitions

`check` is the union of these. `expr` is the definition where the class is expressible; *engine* marks classes the scanner or adjudicator emits directly because they concern malformed input or two-tree comparisons the algebra does not model (their subjects and details are still ordinary finding facts). Two subtractions are engine steps applied after evaluation to every class, never written into definitions: `historical` facts generate no findings of any class (§3.6), and live `@ack`s accept findings of ackable classes (liveness judged pre-subtraction, §3.3). A third rule governs the evidence ladder: `never-ran`, `failed`, `unexercised`, and `unmeasured` are evaluated only when an evidence set exists for the tree — the tool judges measurements that exist and never demands one nobody took; wanting the measurement is expressed by importing it (PR CI does; a main job may), and `status --done` refuses without one, because death requires measurement. The `rung` field reads `never-ran` either way; only the finding is withheld. A fourth: facts belonging to a plan not in force — the plan, its steps, its promises — generate no findings; a dead plan is record, not agreement (§6.3). Tiers are the shipped defaults for `(turn, pr, main)`; every class ships at `warn` under warn-only and is promoted per §8. `A` = ackable, `F` = mechanical fix exists.

| class | subject | definition | mode | A | F | tiers |
|---|---|---|---|---|---|---|
| `parse-error` | file | *engine*: a governed file its pack cannot parse; the whole file's facts are absent | tree | · | · | warn, block, block |
| `typo-tag` | line | *engine*: an unknown `@word` within Damerau–Levenshtein distance 2 of the vocabulary, the pack's foreign vocabulary exempt (§3.2) | tree | · | F | warn, warn, warn |
| `invalid-target` | tag | *engine*: a slug or external id failing its pattern, or an undeclared namespace | tree | · | · | block, block, block |
| `duplicate` | node | *engine*: two declarations of one slug, two plans of one slug (dead ones included — plan slugs are permanent), or two steps of one plan slugifying identically | tree | · | · | block, block, block |
| `scope-outside-plan` | step | *engine*: a step whose `@scope` is not contained in its plan's (§13.7 containment) | tree | · | · | block, block, — |
| `misplaced-plan` | node | *engine*: a `@plan` declaration outside `.plans/**` (§6.1) | tree | · | · | block, block, block |
| `unpinned` | edge | *engine*: a `satisfies`, `verifies`, `refines`, or `supersedes` edge with `rev = ⊥` | tree | · | F | block, block, block |
| `dangling` | edge | `dangling(kind(edge))`, minus edges whose target a claim promises to declare — those surface as `waiting-on` on the promise instead (*engine* performs the subtraction) | tree | · | · | block, block, block |
| `renamed` | edge | *engine*: dangling edges whose slug has a tombstone in `B` and a new declaration in `T` with equal `xh` | diff | · | F | block, block, block |
| `suspect` | edge | `suspect(kind(edge))` | tree | · | F | block, block, block |
| `unbumped` | node | `kind(req\|design\|decision) ^ changed(base) - bumped(all)` | diff | · | F | block, block, block |
| `cycle` | node | *engine*: a cycle in `supersedes` or `refines` | tree | · | · | block, block, block |
| `code-drift` | site | *engine*: `ch` changed since base while the site's comment `xh` did not (§3.4); the judge's sampling frame. Not ackable: the class is diff-relative, so an ack would void on merge | diff | · | · | warn, warn, — |
| `declined` | node | `declined(kind(req\|design\|decision\|plan))` — a live refusal; the detail is the reason | tree | · | · | warn, block, — |
| `unapproved-req` | edge | `in(satisfies\|verifies, kind(req) - approved(all))` — a kind outside `approve` counts approved, so the class self-silences | tree | · | · | block, block, block |
| `unapproved-design` | edge | `in(satisfies\|verifies, kind(design) - approved(all))` | tree | · | · | warn, warn, warn |
| `awaiting-approval` | node | `kind(req\|design\|decision) ^ inforce(all) - approved(all)` — informational; the subject is what `approve` will show | tree | · | · | off, warn, warn |
| `unapproved-plan` | plan | `kind(plan) ^ inforce(all) - approved(all)`; *engine* supplies the set delta as detail | tree | · | · | warn, block, — |
| `retired` | edge | `kind(cites) - dangling(all) - in(cites, inforce(all))` — includes a rule's origin edge, hence "law resting on withdrawn reasoning" | tree | A | · | warn, block, block |
| `stale-ack` | ack | *engine*: an `@ack` whose hash no longer matches its block, or whose target names nothing at that site | tree | · | F | block, block, block |
| `wrong-source` | edge | `wrong-source(kind(verifies))` | tree | · | · | block, block, block |
| `never-ran` | edge | `never-ran(kind(verifies)) ^ scope(inforce(kind(plan)))` at turn; `never-ran(kind(verifies))` at pr and main | tree | · | · | warn, block, block |
| `failed` | edge | `failed(kind(verifies))` | tree | · | · | block, block, block |
| `unexercised` | edge | `unexercised(kind(verifies))` | tree | A | · | warn, block, block |
| `unmeasured` | edge | `unmeasured(kind(verifies))` | tree | · | · | off, warn, warn |
| `untraced` | node | `untraced(verifies) + untraced(satisfies)` — incompleteness; never blocks turn-end | tree | · | · | off, warn, warn |
| `unmet-promise` | promise | `unmet(active)` where `unmet(p) = promises($p) - met(promises($p))` — incompleteness; enforced only by `status --done` | tree | · | · | off, off, — |
| `promise-out-of-scope` | promise | *engine*: a promise met only by facts outside its step's scope | tree | · | · | warn, warn, — |
| `unverified-promise` | promise | *engine*: a promised `req`/`design` with no promised `verifies` of it in the same plan (§6.6) | tree | · | · | warn, warn, — |
| `promise-collision` | promise | *engine*: a promised declaration whose slug exists in `index(B)` or is promised by a claim | tree | · | · | block, block, — |
| `scope-overlap` | step | *engine*: two steps of one plan with intersecting scopes and intersecting promise sets | tree | · | · | warn, warn, — |
| `waiting-on` | promise | `waiting(promises(kind(plan)))` — reported in place of `dangling` for the citation, with the claim and step named (§6.7) | tree | · | · | off, warn, — |
| `branch-overlap` | step | *engine*: a step's scope intersects a claim's scope on another branch | tree | · | · | warn, warn, — |
| `unplanned-change` | hunk | `kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - scope(triggered(kind(rule))) - exempt`; *engine* also exempts hunks that are wholly the tool's own medicine — tag-line re-pins and `@ack` insertions or deletions | diff | · | · | block, block, — |
| `unmet-rule` | any | `obligations(kind(rule))`, one finding per `(rule, subject)`; ackable iff the rule's `expect` is `acked`; a rule's `tiers` overrides the class's | tree | A* | · | warn, block, block |
| `law-touched` | law | `kind(rule\|gate) ^ changed(base)` — non-disableable; always reported, never blocks | diff | · | · | warn, warn, warn |
| `merged-incomplete` | plan | *engine*: an in-force plan on the default branch failing the §6.3 completion condition — merged incomplete; a plan meeting it is completed by main CI, not a finding | tree | · | · | —, —, block |
| `ledger-broken` | ledger | *engine*: `ledger verify` fails | tree | · | · | —, —, block |
| `pack-mismatch` | pack | *engine*: a pinned pack's hash does not match the cache | tree | · | · | exit 3 everywhere |

`untraced`, `unmet-promise`, and `awaiting-approval` are the incompleteness classes: they exist so `status` and the death gate can see them, and the turn report never lists them as violations (§8). Everything else is a violation or a health signal.

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

$ sinter query 'untraced(verifies)'
docs/auth.md:12:1: req auth-lockout v2
docs/auth.md:31:1: req lockout-notify v1

$ sinter query 'kind(hunk) ^ changed(base) - scope(inforce(kind(plan))) - scope(triggered(kind(rule))) - exempt'
src/session/store.rs:88:1: hunk +14/-3
```

The last line is a hunk outside every step's scope — the agent simplified a store the plan never mentioned. It is exactly what the turn report names as a violation — the state an orchestrator refuses to accept a hand-back in. The honest resolutions are the two the monotone rule allows: revert it (`git checkout src/session/store.rs`), or widen the plan's scope in `.plans/auth-lockout.md`, which routes to an approval. What the report will not bless is the hunk staying while the plan stays silent.

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
| `approval` | string | *derived*: ledger approval id when approved |
| `gated` | bool | whether the manifest gates this kind on approval |
| `declined` | bool | *derived*: a live decline exists for `(slug, xh)` |

```json
{"approval":"e-3f9a1c0b7d42","approved":true,"col":1,"desc":"Five consecutive failures within ten minutes freeze the account.","ecol":21,"eline":13,"gated":true,"id":"req:auth-lockout","inforce":true,"kind":"req","line":13,"pack":"markdown","path":"docs/auth.md","rev":2,"slug":"auth-lockout","title":"Lock account after 5 failed attempts","v":1,"xeline":29,"xh":"9f3a…","xline":12}
```

**`plan`**

| field | type | meaning |
|---|---|---|
| `slug` `title` | string | |
| `scope` | array of string | plan-level globs |
| `approved` | bool | *derived*: current commitment set approved against the last approval (§13.7) |
| `approval` | string | *derived* |
| `active` | bool | *derived* from session |
| `open` | bool | *derived*: no `completed` or `abandoned` ledger entry for the plan (§6.3); its in-force state |
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

### 13.4 Edges, external ids, promises

**edge** (`kind` is `satisfies` `verifies` `refines` `cites` `supersedes`)

| field | type | meaning |
|---|---|---|
| `src` | string | id of the source fact (a node or a rule) |
| `target` | string | the target as written: slug or `ns/id` |
| `dst` | string | *derived*: id of the resolved target; omitted when dangling |
| `rev` | int | pinned revision; omitted when unpinned |
| `desc` | string | inline description; omitted if empty |
| `suspect` `dangling` | bool | *derived* |
| `rung` | string | `verifies` only, *derived*: `wrong-source` `never-ran` `failed` `unexercised` `unmeasured` `passing` |
| `effective` | bool | `supersedes` only, *derived* |

Tags inside plan files never produce edges; they are `promise` facts (§6.1).

```json
{"col":5,"dst":"req:auth-lockout","ecol":31,"eline":40,"id":"verifies:test:auth::lockout::tests::locks_after_five_failures->auth-lockout","kind":"verifies","line":40,"pack":"rust","path":"src/auth/lockout.rs","rev":2,"rung":"passing","src":"test:auth::lockout::tests::locks_after_five_failures","target":"auth-lockout","v":1}
```

**`external`**

| field | type | meaning |
|---|---|---|
| `ns` | string | namespace |
| `name` | string | id within the namespace |

Unlocated; one per distinct target. (`refstate`, the networked read, is deferred with `@pin`.)

**`promise`**

| field | type | meaning |
|---|---|---|
| `plan` `step` | string | slugs |
| `word` | string | `req` `design` `decision` `satisfies` `verifies` `refines` `cites` `supersedes` |
| `target` | string | as written |
| `met` | bool | *derived* |
| `by` | string | *derived*: id of the fact that meets it, when met |
| `out_of_scope` | bool | *derived*: facts that would meet it exist only outside the step's scope; `met` stays false (§6.1) |

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
| `test` | string | test fact id, or `*` for the coverage of the whole run |
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

**`claim`** (unlocated; projected from the ledger for each approved plan on another branch that is neither completed nor abandoned and whose branch existed on the remote at the last fetch)

| field | type | meaning |
|---|---|---|
| `plan` | string | plan slug |
| `branch` | string | branch the approval was written from |
| `approval` | string | latest approval id |
| `scope` | array of string | union of approved step scopes |
| `declares` | array of string | slugs the claim promises to declare |
| `ts` | string | RFC 3339 timestamp of the approval |

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
| `name` `origin` `trigger` `expect` | string | as declared |
| `via` | string | `checked` `judged` `acked` — inferred from `expect` |
| `scope` | array of string | |
| `triggered` | bool | *derived* |
| `obligations` | int | *derived* obligation count |

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
| `target` | string | as written, e.g. `retired cache-ttl` or `ste-docs` |
| `hash` | string | as written |
| `live` | bool | *derived* |
| `void` | string | *derived*: `hash` or `target`; omitted when live |
| `for` | string | *derived*: id of the finding accepted, or the rule, when live |

**`hunk`** (new-side coordinates; a pure deletion has `line = eline = ` the line after the deletion and `added = 0`)

| field | type | meaning |
|---|---|---|
| `added` `removed` | int | |
| `exempt` | bool | *derived* |
| `planned` | array of string | *derived*: ids of steps or rules whose scope covers the hunk; empty when no step and no rule covers the hunk |

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
| `rule` | string | `unmet-rule` only |
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
| `external` | `external:<ns>/<id>` | |
| `promise` | `promise:<step-id>:<word>:<target>` | parse from the right |
| `run` | `run:<test-id>@<tree>` | |
| `cov` | `cov:<test-id or *>@<site-id>` | |
| `judgment` | `judgment:<rule>:<subject-id>@<hash>` | |
| `claim` | `claim:<plan>@<branch>` | |
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

Four writers exist: `approve` writes `approval` (with its `approved-*` lines), `decline` writes `decline`, `ledger abandon` writes `abandoned`, and main CI writes `completed` (§6.3). Entry ids are content-derived: `e-` plus the first twelve hex digits of SHA-256 over the entry's canonical bytes with the `id` key absent. Two writers can never mint one id for different entries, so replay after a lost push race is a set union (`ledger push --replay`); accretion is checked per file — every commit's ledger is a byte-prefix extension of its parent's, and ids never repeat. Where order matters (a decline superseded by a later approval), `ts` decides, never file position. When `[ledger].sign` is set, every ledger commit is signed and `ledger verify --signers` enforces the allowlist.

**Every entry** carries `id`, `kind`, `v`, `by`, `ts` (RFC 3339, UTC), `head` (the commit the writer stood on), `branch`, and `tool`.

**`approval`**

| field | type | meaning |
|---|---|---|
| `subject` | string | `req:auth-lockout`, `plan:auth-lockout`, … |
| `rev` `xh` | | declarations only |
| `csh` | string | plans only: commitment-set hash (§13.3) |
| `note` | string | omitted if none |

**Revision reservation.** `approve` refuses to write an `approval` for `(slug, rev)` when the ledger already holds an approval for that pair with a different `xh`; the refusal names the earlier entry and branch. An approval with equal `xh` is idempotent and skipped.

**`decline`**

| field | type | meaning |
|---|---|---|
| `subject` | string | |
| `hash` | string | `xh` or `csh` at the moment of refusal |
| `reason` | string | required |

A decline is live while the subject's current hash equals `hash` and no later approval of the subject exists. It is never deleted; a later approval — at a different hash, or at the same one, the human overriding their own refusal after an `approve` prompt — supersedes it in effect, and `compile history` shows both.

**`completed`**

| field | type | meaning |
|---|---|---|
| `subject` | string | `plan:<slug>` |
| `approval` | string | the approval the plan died under |
| `merge` | string | merge commit |
| `report` | string | SHA-256 of the report compiled at completion |

**`abandoned`**

| field | type | meaning |
|---|---|---|
| `subject` | string | `plan:<slug>` |
| `reason` | string | required |

Abandonment kills the claim and every `waiting-on` resting on it; `compile residual-plan` remains the path back for whatever work the plan still had to do.

**`approved-scope`** — one per glob, plan-level when `step` is omitted

| field | type |
|---|---|
| `approval` | string |
| `step` | string (slug), omitted for plan scope |
| `glob` | string |

**`approved-promise`** — one per promise

| field | type |
|---|---|
| `approval` | string |
| `step` | string |
| `word` `target` | string |

**Commitment-set comparison.** The current set `C` and the approved set `C₀` are compared as follows; `approved(plan)` iff every clause holds.

1. The multiset of `(word, target)` over all promises is equal.
2. The plan scope is contained: `scope(C) ⊆ scope(C₀)`.
3. For each promise `p`, matched by `(word, target)` (matching among duplicates is by step slug first, then arbitrary — duplicates are rare and identical in effect), the effective scope of `p`'s step in `C` is contained in the effective scope of its step in `C₀`.

**Glob containment** `G' ⊆ G` is decided structurally and conservatively: every glob in `G'` either appears verbatim in `G`, or is a literal path or path prefix that some glob in `G` matches (checked by matching the literal against the glob), or is `<g>/<segments>` for some `<g>/**` in `G`. Anything the checker cannot prove is treated as widening. This is decidable, deterministic, and errs toward asking the human, which is the correct direction for an approval gate.

The consequences: renaming steps is free (clause 3 matches by promise, not by step); reordering is free; splitting is free when each fragment keeps or narrows its scope; merging is free when the merged scope equals the originals' and approved otherwise; any promise added or removed fails clause 1. This is the precise form of §6.2.

**`pin`** (deferred): `{"approval":…,"external":"gh/42","hash":…,"kind":"pin"}`.

### 13.8 Header and summary

**`index`** — first line of every scan; excluded from conformance comparison

| field | type | meaning |
|---|---|---|
| `tree` | string | tree key |
| `base` | string | resolved base revision |
| `default_branch` | string | default branch |
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
| `unplanned` | int (hunks) |
| `obligations` | int (rule obligations) |
| `evidence_fresh` | bool |
| `bumps` | int (declarations bumped since base) |
| `acks_live` `acks_void` | int |
| `declines` | int (live, in scope) |
| `claims` `waiting` | int |
| `code_drift` | int |
| `law_touched` | bool |

### 13.9 Conformance

A pack's fixture directory contains a tiny project, `expected.jsonl`, a fixture ledger (`ledger.jsonl`), and real runner and coverage artifacts with the coverage of each test. `sinter pack verify` scans the fixture with the fixture ledger and evidence, drops the header line, and requires byte equality with `expected.jsonl`. Because derived fields are included, the fixture exercises binding and the evidence ladder end to end, not just parsing. A tool release that changes any derived field's semantics must regenerate every pack's fixture, which is the intended friction.

## 14. Manifest Reference

`sinter.toml` is pure configuration, and short. Everything with a sensible default is absent; `sinter init` writes only what it had to choose. The whole file is inside the boundary (§5.1): edits to `[gates]`, `[findings]`, `[rules]`, and `approve` are `law-touched` on any diff, always.

```toml
enforce    = "warn"                        # warn-only: nothing blocks or exits 1 until this line goes or a class is promoted below (§8)
approve    = ["req"]                       # kinds the ledger gates; kinds not listed count approved (§12.8)
historical = ["docs/devlog/**"]            # citations resolve and render; no findings (.plans/*.log.md is built-in)
exempt     = ["Cargo.lock", "**/generated/**"]   # exempt from scope confinement; counted in the report

[languages]                                # constraints here; exact versions and hashes in sinter.lock
rust   = "1.4"
python = "1.2"

[languages.markdown]                       # long form: override the pack's default file set
version = "1.0"
files   = ["docs/**/*.md", ".plans/*.md"]  # the pack's default is **/*.md

[namespaces]                               # namespace → anchored id pattern; gh is built in
jira = "[A-Z]+-[0-9]+"

[gates.turn]                               # per-class promotion past the cap; omitted → shipped default (§12.8)
unplanned-change = "block"
unbumped      = "block"
[gates.pr]
unexercised   = "block"

[rules.ste-docs]                           # standing law (§7)
origin    = "ste-adoption"
trigger   = "kind(req|design) ^ path(docs/**) ^ changed(base)"
expect    = "acked(ste-docs)"                # acknowledged: an @ack at the site

[rules.issue-linked]
origin    = "issues-are-truth"
trigger   = "kind(req) ^ changed(base)"
expect    = "src(out(cites, kind(req)) ^ in(cites, external(gh/*)))"   # checked: the graph says so

[findings.decision-uncited]                # a repo-defined finding; without tiers it is query-only
expr    = "kind(decision) ^ inforce(all) - dst(in(cites, all))"
detail  = "decision in force that nothing cites"
ackable = true
tiers   = { pr = "warn" }
```

**What the packs own.** A pack's descriptor declares the files it governs (`files = ["**/*.rs"]`), so the manifest never maps paths to packs. `[languages.<name>]` may narrow or replace a pack's `files` — the markdown case above, where governing every README in the tree is not wanted — and may add `exclude`. A file matched by two packs is a manifest load error, not a precedence rule.

**The lockfile.** `sinter.lock` is tool-owned, written by `sinter pack add` and `sinter init`, and holds the exact version and hash for every language in `[languages]`. Versions in the manifest are constraints (`"1.4"` means `1.4.x`); the lock is the truth CI verifies. This is Cargo's split, adopted for the same reason: the manifest stays readable and the lock stays exact. `pack-mismatch` compares the cache against the lock.

**Saved definitions** are `[findings.<class>]` entries; a finding with no `tiers` is evaluated by `query` and never by `check`, which is what a reusable definition is. There is no separate `[defs]` table.

**Tier sets** are three — `turn`, `pr`, `main`. Only `pr` and `main` block mechanically, in CI; `turn` is the severity vocabulary the report, its exit code, and orchestrators consult (§8). `check` and the PostToolUse hook always report everything.

**Tuning keys** exist but are not in the example; each has a default that should be right for most repositories:

| key | default | meaning |
|---|---|---|
| `default-branch` | `"main"` | branch whose merge-base is the default `--base` |
| `brief.budget` | `12000` | bytes; the turn-level brief uses a quarter of it |
| `brief.why_budget` | `2000` | bytes; the origin-decision extent attached to an `unmet-rule` block (§7) |
| `evidence.require_attribution` | `false` | `true`: rung `unmeasured` never meets a `@verifies` promise |
| `ledger.sign`, `ledger.signers` | `false`, `[]` | signed ledger commits and the allowlist (§6.4) |
| `refuse_env` | `["CLAUDECODE"]` | agent markers that make `approve`/`decline` refuse |
| `rules.<name>.scope` | `[]` | where the edits that clear a rule's obligations land (§7); only needed when outside the plan's scope |
| `rules.<name>.tiers` | from `[gates]` `unmet-rule` | per-gate override for one rule's obligations |

Deliberately absent: a hooks table (hook registration lives in the harness's own settings file, which `init` writes; there is nothing to configure twice), a journal switch (a journal exists iff the file does), an evidence directory (fixed at `.sinter/evidence`), the ledger ref (fixed), a schema version (assumed `1` until a `2` exists), sampling of acknowledged obligations by the judge (waits for `sinter judge`), a classification-tag table (an earlier draft's `compile spec --tag` — a selection nobody has asked for yet), and per-kind declaration paths (`[declare]` in an earlier draft — a warn-tier nicety that cost a table and two finding classes; if a repo wants it, it is one `[findings]` entry away: `kind(req) - path(docs/requirements/**)`).
