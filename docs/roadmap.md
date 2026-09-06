<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Roadmap

This file lists the work ahead, in order. It is a list of intentions,
not a plan: a plan is a file under `.plans/` with promises that Sinter
checks. An item moves off this list when a plan takes it up.

## Now

The bootstrap plan, `.plans/bootstrap.md`: the decision records for
what is already decided, the Claude Code skill pack, the Rust bridge
that loads wasm grammars, `sinter parse`, and `sinter serve` over
stdin and stdout.

## Next

The core of the tool, in the order the design notes lay out:

1. The manifest reader for `sinter.toml` (design notes section 14).
2. The scanner behind the language-pack interface (section 5.2), with
   the markdown pack first, because plans and decision records are
   markdown.
3. `sinter scan`, emitting the facts that `spec/jsonl.md` defines, with
   conformance fixtures.
4. `sinter check` and the built-in finding classes
   (`spec/algebra.md` section 9), starting with the classes that
   need no ledger and no evidence.
5. The ledger commands and the evidence import.

## Noted, not designed

These items are agreed as directions. None has a design yet, and each
needs a decision record before work starts.

- **`sinter search`** — find past decisions and other declarations by
  text. Keyword search over titles, descriptions, and extents is
  cheap once the scanner's index exists. Semantic search is the open
  half: a bundled local model, an external service behind an explicit
  opt-in, or a pluggable backend with keyword search as the default.
  Also open: whether search covers all declaration kinds and plans,
  or decisions only.
- **`sinter serve --mcp`** — expose the serve loop as an MCP server
  over stdio, with tools named after the CLI verbs, so that any MCP
  client can drive Sinter directly. This overrides the design notes'
  "no MCP server" position (section 9.1); the decision record must
  quote that argument and answer it.
- **`sinter serve --detach`** — a mode that outlives its caller, on a
  socket, for several clients. Deferred when the serve mode was
  decided; the loop stays transport-neutral so that it can be added.
- **`spec/protocol.md`** — the request and response protocol of
  `serve`, as a fifth specification, once its shape has settled.
- **Issue #2** — a per-kind default location for promised
  declarations, so that plan steps need not repeat
  `docs/decisions/**` in their scope.
- **The `sinter-packs` repository** — the language packs, built and
  verified as the licensing brief describes.
- **Test evidence for Sinter itself** — JUnit output from the test
  suite, so that Sinter can check its own plans once `evidence import`
  exists.
