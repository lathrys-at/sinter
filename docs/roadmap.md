<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Roadmap

This file lists the work ahead, in order. The items on this list are
intentions, not plans. A plan is a file under `.plans/` that holds
promises, and the tool checks those promises. An item moves off this
list when a plan takes up that item.

## Now

The work now is the bootstrap plan, `.plans/bootstrap.md`. The plan
covers five items:

- the decision records for what is already decided;
- the Claude Code skill pack;
- the Rust bridge that loads wasm grammars;
- `sinter parse`;
- `sinter serve` over stdin and stdout.

## Next

These items build the core of the tool. The list follows the order
that the design notes give:

1. The manifest reader for `sinter.toml` (design notes section 14).
2. The scanner behind the language-pack interface (section 5.2).
   Build the markdown pack first, because plans and decision records
   are markdown.
3. `sinter scan`, which emits the facts that `spec/jsonl.md` defines.
   This item includes conformance fixtures.
4. `sinter check` and the built-in finding classes
   (`spec/algebra.md` section 9). Start with the classes that need no
   ledger and no evidence.
5. The ledger commands and the evidence import.

## Noted, not designed

We agree on these items as directions. None of them has a design yet.
Each one needs a decision record before work starts.

- **`sinter search`** — find past decisions and other declarations by
  text. Keyword search over titles, descriptions, and extents is
  cheap once the scanner's index exists. Semantic search is still
  undecided. The candidates are a bundled local model, an external
  service behind an explicit opt-in, or a pluggable backend with
  keyword search as the default. One more question is undecided: does
  search cover all declaration kinds and plans, or decisions only?
- **`sinter serve --mcp`** — expose the serve loop as a server for
  the Model Context Protocol (MCP) over stdio. Name the tools after
  the CLI verbs, so that any MCP client can drive Sinter directly.
  This option overrides the "no MCP server" position in the design
  notes (section 9.1). The decision record must quote that argument
  and then answer it.
- **`sinter serve --detach`** — a mode that outlives its caller. The
  mode runs on a socket and serves several clients. We deferred this
  mode when we decided the serve mode. The serve loop stays
  transport-neutral, so that we can add this mode later.
- **`spec/protocol.md`** — the request and response protocol of
  `serve`, as a fifth specification. Write this specification when the
  shape of the protocol settles.
- **Issue #2** — a per-kind default location for promised
  declarations, so that plan steps need not repeat
  `docs/decisions/**` in their scope.
- **The `sinter-packs` repository** — the home of the language packs.
  We build and verify the packs there, as the licensing brief
  describes.
- **Test evidence for Sinter itself** — JUnit output from the test
  suite, so that Sinter can check its own plans once `evidence import`
  exists.
