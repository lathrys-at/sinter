<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Roadmap

- **Bootstrap plan** — `.plans/bootstrap.md`.
  - Decision records for the decisions made so far.
  - The Claude Code skill pack.
  - The Rust bridge that loads wasm grammars.
  - `sinter parse`.
  - `sinter serve` over stdin and stdout.
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
  - NFC normalization of strings that come from file text
    (`spec/jsonl.md` section 2), with the `uunf` library. `sinter parse`
    does not normalize yet.
- **`sinter check`**
  - The built-in finding classes, `spec/algebra.md` section 9.
  - Classes that need no ledger and no evidence first.
- **Ledger commands and evidence import**
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
  as a fifth specification.
- **`sinter-packs` repository** — the language packs, built and
  verified as the licensing brief describes.
- **Test evidence for Sinter itself** — JUnit output from the test
  suite, for `evidence import`.
- **A generated third-party list** — `THIRD_PARTY.md` built in CI from
  `bridge/Cargo.lock` and `sinter.opam.locked` (`cargo about` or
  `cargo license` for the Rust tree), with a drift check. `cargo deny`
  checks the Rust licences against an allowlist until then.
