<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Licensing of the language packs

A language pack holds a compiled tree-sitter grammar, which Sinter
redistributes under the grammar's own upstream license, and files that
the pack's authors write, which use the Apache-2.0 license.
`docs/decisions/licensing.md` records the licenses of the tool, the
specifications, and the packs.

## The files of a pack

| file | content | license |
|---|---|---|
| `pack.toml` | the descriptor | Apache-2.0 |
| `grammar.wasm` | the compiled upstream grammar | the upstream license |
| `queries/*.scm` | the queries that the pack's authors write | Apache-2.0 |
| `fixtures/` | the conformance fixtures | Apache-2.0 |
| `LICENSE.upstream` | the upstream license of the grammar, as the upstream gives it | the upstream license |
| `NOTICE` | one line: `grammar.wasm is built from <repository> at <commit> under <SPDX identifier>` | Apache-2.0 |

## Rules

- `pack.toml` holds two required fields:
  `grammar_upstream = "<git URL>@<commit>"` and
  `grammar_license = "<SPDX identifier>"`.
- `sinter pack verify` fails a pack when `LICENSE.upstream` is
  missing, when `grammar_license` is not an SPDX identifier, or when
  `grammar_license` is not on this list: `MIT`, `Apache-2.0`,
  `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `Unlicense`, `0BSD`,
  `MPL-2.0`. Any other license needs a decision of the maintainer and
  a recorded exception.
- The repository of the packs holds the same root files as Sinter's
  own: `LICENSE` (Apache-2.0), `NOTICE`, `DCO`, and `CONTRIBUTING.md`.
  Its `CONTRIBUTING.md` adds a section on adding a pack: keep the
  upstream license, record the upstream commit, and run
  `sinter pack verify`.
- Its `REUSE.toml` gives `grammar.wasm` and `LICENSE.upstream` of each
  pack the upstream SPDX identifier.
- Its CI runs the same four license checks as Sinter's, and
  `sinter pack verify --all`.
