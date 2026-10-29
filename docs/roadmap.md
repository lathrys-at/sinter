<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Roadmap

- **Scanner** — the language-pack interface, design notes section 5.2.
- **`sinter scan`**
  - Conformance fixtures.
  - Print the `setting` records and the `gate` records of
    `spec/jsonl.md` section 7. `config-changed` already uses their ids.
  - `sinter scan --diff`: print the `hunk` records and the `tombstone`
    records. Not designed.
- **`sinter check`**
  - The built-in finding classes, `spec/algebra.md` section 9.
- **Rule files** — the rules and the finding classes that a
  repository writes, `spec/manifest.md` section 14.
  - Decide, when rule files are built, whether an edit of a rule file
    needs a revision bump (`unbumped`), and whether `config-changed`
    covers rule files.
- **`sinter patch`** — print the mechanical fixes of the findings as a
  diff for `git apply`, design notes section 11.10. Sinter itself
  writes no file.
  - Among its fixes: move a citation of a superseded item to its
    successor, and bump the revision of the citing declaration (record
    `cite-the-successor`).
- **Ledger commands and evidence import**
- **Show the approval delta so that a person reads it** — a person
  approves the changes to a set of items since their last approval
  (design notes section 6.4). How to show those changes so that the
  person actually reads what they approve is open. Not designed.
- **The coverage of each test for Rust and Go** — rung 4 of the
  evidence ladder needs the coverage of each test (design notes
  section 4). To run each test that carries a `@verifies` in its own
  process is correct and slow. A driver could merge the coverage files
  of `cargo llvm-cov` by test name, or run `go test -run` for each
  test. Whether either can be fast enough for the hook after each
  edit, and not only for CI, is unknown. Until then, these packs
  report rung 4 as `unmeasured` on a local machine, and as
  `unexercised` or `passing` in CI. Not designed.
- **Observations of the outside world** — an obligation that a
  decision record makes and that never ends, where the work depends on
  events outside the repository. An example is a decision to keep
  every dependency at its newest release.
  - A routine outside Sinter checks outside sources on a schedule,
    for example new releases and security advisories. It writes what
    it finds into a file in the repository, as evidence import does.
    `sinter check` never reads the network.
  - A rule (design notes section 7) whose origin is the record
    triggers on that file. A plan that cites the observation, or an
    `@ack`, clears the obligation.
  - It shares its design with `@pin` (`spec/vocabulary.md` section
    7.4) and with evidence import. Not designed.
- **Plans with their journals** — show each plan step with the
  journal entries for the step (record `plan-journals`): the step and
  its promises by default, the journal entries on request. Not
  designed.
- **Plans made of plans**: a step of one plan names another plan as
  its work, so that a large plan can split into smaller plans. The
  step is done when the plan it names is completed. For example, a
  step of `sinter-v0.1` would name the plan `readable-output`. Not
  designed.
- **Commit trailers** — read the `Step:`, `Record:`, `Issue:`, and
  `Meets:` trailers of the commits on a branch (record
  `commit-messages`) and check them against the plan and the diff.
  Not designed.
- **jj repositories without `.git`** — support a jj repository that
  is not colocated, and a jj workspace that has no `.git`. A small
  locator asks `jj` for the git folder and for the parent of the
  working-copy commit, and Sinter then runs git as it does today. Not
  designed.
- **`sinter search`**
  - Keyword search over titles, descriptions, and extents.
  - Semantic search: a bundled local model, an external service
    behind an opt-in, or a pluggable backend. Undecided.
  - Scope: all declaration kinds and plans, or decisions only.
    Undecided.
- **`sinter serve --mcp`**
  - An MCP server over stdio; tools named after the CLI verbs.
  - The decision record answers the "no MCP server" argument in the
    design notes, section 9.1.
  - A richer Claude Code plugin on top of the server: MCP Apps UI that
    shows plans, decisions, and other Sinter information to the user
    inside the client. A desired outcome, not yet designed.
- **`sinter serve --detach`** — a mode that outlives its caller, on a
  socket, for several clients.
- **`sinter serve --lsp`** — a Language Server Protocol adapter on the
  serve loop, after the MCP adapter. A child of the editor; it informs
  and never blocks a save.
  - Diagnostics on edit from the findings, and code actions from the
    mechanical fixes of `sinter patch`: re-pin, bump, rename fix-up,
    `@ack` insertion.
  - Hover, go to definition, and find references over the graph: a
    citation to its declaration, a declaration to its citing sites and
    tests, a `@verifies` to its rung, a `@decision` to its record.
  - Completion: the tag words, the slugs in the index, the test names
    a pack captures.
  - Rename as deletion plus declaration across the repository.
  - One server for a person's editor and for the Claude Code plugin
    (`.lsp.json`), so an agent gets diagnostics on every edit through
    the same protocol.
- **`spec/protocol.md`** — the `serve` request and response protocol,
  as a specification of its own.
- **Rank the items of the brief** — the brief ranks its items by
  their distance in the graph from the step's scope (design notes
  section 8.1). A wrong brief is worse than a short one, because it
  fills the budget with the wrong requirements. Other weights are
  possible: the number of citations, the recency of approval, or the
  declarations that the step's promises reach through `@refines`.
  Measurements of real sessions will decide; the metrics of the
  ledger (design notes section 6.4) will show the answer as fewer
  violations in each turn report. Not designed.
- **`sinter-packs` repository** — the language packs, built and
  verified as `docs/licensing-setup.md` describes.
- **Test evidence for Sinter itself** — JUnit output from the test
  suite, for `evidence import`.
- **Tests with no name** — the OCaml tests of `ppx_expect` and
  `ppx_inline_test` are anonymous extension nodes, and the runner
  reports no name for them. The OCaml pack needs a way to bind their
  results before it can read them as tests. This matters because
  Sinter checks its own code. Not designed.
- **Drop the pins on the measuring tools** when upstream `bisect_ppx`
  and `mutaml` release versions that install beside the lock file
  (`docs/decisions/instrumented-tooling.md`).
- **A fuzz target for the bridge boundary** — `crowbar` under AFL over
  the result-buffer decoder and the wasm export reader, built outside
  the test suite. `docs/decisions/test-rigor.md` notes the choice.
- **A generated third-party list** — `THIRD_PARTY.md` built in CI from
  `bridge/Cargo.lock` and `sinter.opam.locked` (`cargo about` or
  `cargo license` for the Rust tree), with a drift check. `cargo deny`
  checks the Rust licences against an allowlist until then.
