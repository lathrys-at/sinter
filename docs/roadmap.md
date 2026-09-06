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
- **Scanner** — the language-pack interface, design notes section 5.2.
  - Markdown pack first: plans and decision records are markdown.
- **`sinter scan`**
  - Emit the facts that `spec/jsonl.md` defines.
  - Conformance fixtures.
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
- **`sinter serve --detach`** — a mode that outlives its caller, on a
  socket, for several clients.
- **`spec/protocol.md`** — the `serve` request and response protocol,
  as a fifth specification.
- **`sinter-packs` repository** — the language packs, built and
  verified as the licensing brief describes.
- **Test evidence for Sinter itself** — JUnit output from the test
  suite, for `evidence import`.
