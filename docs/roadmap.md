<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Roadmap

- **Manifest reader** — `sinter.toml`, design notes section 14.
  - The `[locations]` table: one default location per declaration
    kind (issue #2). `spec/vocabulary.md` section 10.5 defines the
    rule.
  - The `shared` list: paths that every plan step may touch (issue
    #9). `spec/vocabulary.md` section 10.4 defines the rule.
- **Scanner** — the language-pack interface, design notes section 5.2.
  - Markdown pack first: plans and decision records are markdown.
- **`sinter scan`**
  - Emit the facts that `spec/jsonl.md` defines.
  - Conformance fixtures.
- **`sinter check`**
  - The built-in finding classes, `spec/algebra.md` section 9.
  - Classes that need no ledger and no evidence first.
- **`sinter patch`** — print the mechanical fixes of the findings as a
  diff for `git apply`, design notes section 11.10. Sinter itself
  writes no file.
  - Among its fixes: move a citation of a superseded item to its
    successor, and bump the revision of the citing declaration (record
    `cite-the-successor`).
- **Ledger commands and evidence import**
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
- **`sinter-packs` repository** — the language packs, built and
  verified as `docs/licensing-setup.md` describes.
- **Test evidence for Sinter itself** — JUnit output from the test
  suite, for `evidence import`.
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
