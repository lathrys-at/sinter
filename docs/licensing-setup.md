<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Licensing of the language packs

A language pack holds compiled tree-sitter grammars, which Sinter
redistributes under the license of each upstream project, and files
that the authors of the pack write, which use the Apache-2.0 license.
`docs/decisions/licensing.md` records the licenses of the tool, the
specifications, and the packs. `spec/packs.md` section 2.3 gives the
files of a pack. The paths below are relative to the pack root.

## The files of a pack

| file | content | license |
|---|---|---|
| `pack.toml` | the descriptor | Apache-2.0 |
| `grammars/<grammar>.wasm` | a compiled upstream grammar | the license of the upstream project |
| `queries/<grammar>/*.scm` | the query files that the authors of the pack write | Apache-2.0 |
| `adapters/<runner>.wasm` | a runner adapter | the `adapter.license` of the runner in the descriptor |
| `licenses/Apache-2.0.txt` | the text of the Apache-2.0 license | Apache-2.0 |
| `licenses/<upstream repository>.LICENSE` | one for each upstream repository: its license file, exactly as the upstream project gives it | the license of the upstream project |
| `licenses/NOTICE` | the source of each grammar: the upstream repository, the tag, the commit, the release asset, and the SHA-256 of the file | Apache-2.0 |

`licenses/NOTICE` has the form that the `CONTRIBUTING.md` of the packs
repository gives.

The conformance fixtures of a pack are not files of the pack. They
live in the packs repository, in `fixtures/<pack>/<case>/`, and they
use the Apache-2.0 license.

## Rules

- The top-level `license` of the descriptor is `Apache-2.0`, the
  license of the descriptor and of the query files.
- The `license` of each `[[grammar]]` table of the descriptor is the
  license of the grammar, as an SPDX license expression.
- The packs repository accepts only the licenses on its list: `0BSD`,
  `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `MIT`,
  `MPL-2.0`, and `Unlicense`. Each license that an expression of a
  descriptor names must be on the list. Any other license needs a
  decision of the maintainer. The list is a rule of the packs
  repository, not of Sinter: `sinter pack verify` does not check it.
- The packs repository, `sinterworks/sinter-packs`, holds the same
  root files as Sinter's own: `LICENSE` (Apache-2.0), `NOTICE`, `DCO`,
  and `CONTRIBUTING.md`.
- Its `REUSE.toml` gives `grammars/*.wasm` and `licenses/*.LICENSE` of
  each pack the license of the upstream project, with the copyright
  line of the upstream license file.
- Its `CONTRIBUTING.md` gives the procedure to add a pack and its
  grammars.
- Its CI runs the same license checks as Sinter's, and checks the
  list of licenses with `tools/check-licenses.sh`. When Sinter has the
  command, CI also runs `sinter pack verify packs/*/`.
