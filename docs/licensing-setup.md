<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter: Licensing Setup

A brief for setting up licensing in the `sinter` repository (and, when it exists, the `sinter-packs` repository). Written to be handed to an agent in an empty repo. Everything here is a file to create, a field to set, or a check to install. Do not paraphrase license texts; fetch the canonical text and commit it verbatim.

## Decisions (already made — do not relitigate)

| artifact | license | why |
|---|---|---|
| Tool source, core library, CI/hook integration | **Apache-2.0** | permissive for infrastructure adoption; explicit patent grant and termination clause |
| Specifications: doctag vocabulary, query algebra, JSONL schema, ledger format | **CC-BY-4.0**, plus an explicit statement that implementing the formats needs no license from us | these are meant to be implemented by other tools |
| Design notes and other docs | **CC-BY-4.0** | same |
| Pack-authored files in each language pack (queries, descriptor, fixtures) | **Apache-2.0** | |
| Compiled tree-sitter grammars inside packs | **upstream license, preserved verbatim** | we redistribute; we do not relicense |
| Contributions | inbound = outbound, under a **DCO** (no CLA) | Apache §5 already covers the grant; a CLA costs contributors |

Copyright holder line: `Copyright <year> The Sinter Authors` — take the project's actual name/holder from the user if they want something else; if not told, use this.

## Repository: `sinter`

### 1. Root files

Create these at the repository root.

**`LICENSE`** — the full Apache License 2.0 text from <https://www.apache.org/licenses/LICENSE-2.0.txt>, unchanged. Do not add a copyright line inside this file (Apache's text has an appendix template; the copyright notice goes in `NOTICE` and source headers, not in `LICENSE`).

**`NOTICE`** — required by Apache-2.0 §4(d) when present; keep it short:

```
Sinter
Copyright <year> The Sinter Authors

This product includes software developed at The Apache Software Foundation
(http://www.apache.org/) only insofar as the Apache License 2.0 applies; see LICENSE.

Third-party components are listed in THIRD_PARTY.md with their licenses.
```

**`LICENSE-SPEC`** — the full Creative Commons Attribution 4.0 International legal code from <https://creativecommons.org/licenses/by/4.0/legalcode.txt>, preceded by this preamble:

```
The Sinter specifications — the doctag vocabulary, the query algebra, the
JSON Lines interchange schema, and the approval-ledger format — and the
design notes in docs/ are licensed under the Creative Commons Attribution
4.0 International License (CC-BY-4.0), reproduced below.

Implementing these specifications in any software, under any license,
requires no permission from and creates no obligation to The Sinter
Authors beyond the attribution CC-BY-4.0 asks for in the specification
text itself. The formats are intended to be implemented freely.
```

**`THIRD_PARTY.md`** — one line per bundled or linked dependency that ships in the release binary, with license and a link. Populate from the actual dependency set once it exists; expected entries include `wasmtime` (Apache-2.0 WITH LLVM-exception), `tree-sitter` runtime (MIT), `jq` if bundled (MIT; note its `oniguruma` dependency is BSD-2-Clause), and the OCaml runtime (LGPL-2.1 with the OCaml linking exception — static linking is permitted under that exception; state so). Regenerate this file in CI rather than by hand if a tool for the build system exists (`opam-licenses`, `cargo-about` for the Rust side, or a small script over `dune describe`).

**`DCO`** — the Developer Certificate of Origin 1.1 text, verbatim, from <https://developercertificate.org/>.

**`CONTRIBUTING.md`** — must contain, at minimum:

```
## Licensing of contributions

Sinter is licensed under Apache-2.0 (code) and CC-BY-4.0 (specifications
and docs); see LICENSE and LICENSE-SPEC. By contributing you agree that
your contribution is licensed under the same terms as the file it changes
(inbound = outbound). We do not use a CLA.

## Developer Certificate of Origin

Every commit must be signed off (`git commit -s`), which adds a
`Signed-off-by:` trailer certifying the DCO (see the DCO file). CI rejects
unsigned commits.

## Agent-authored changes

Much of this codebase is written with coding agents. That is expected and
welcome. The human who runs the agent signs off the commit and is the
contributor of record. Add a trailer naming the agent when one was used
substantially, e.g. `Assisted-by: Claude Code`, so authorship provenance is
in the history. Do not sign off code you have not reviewed.

## Third-party code

Do not copy code from other projects unless its license is Apache-2.0
compatible and you add it to THIRD_PARTY.md. Never vendor GPL/AGPL code.
```

**`README.md`** — a `## License` section:

```
Apache-2.0 for the tool (LICENSE). The specifications and design notes are
CC-BY-4.0 and may be implemented freely (LICENSE-SPEC). Language packs
carry their grammars' upstream licenses. Contributions are accepted under
a DCO; see CONTRIBUTING.md.
```

### 2. Directory layout and per-directory licensing

```
LICENSE            Apache-2.0
LICENSE-SPEC       CC-BY-4.0 + implementability statement
NOTICE
THIRD_PARTY.md
DCO
CONTRIBUTING.md
REUSE.toml         machine-readable map (below)
spec/              CC-BY-4.0: vocabulary.md, algebra.md, jsonl.md, ledger.md
docs/              CC-BY-4.0: design notes and everything else prose
src/ lib/ bin/ test/   Apache-2.0
```

Keep the specifications in `spec/` as separate files even if they start as sections copied from the design notes: they will be versioned and referenced independently, and their license differs from the code's. Put this header at the top of each file in `spec/` and `docs/`:

```
<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright <year> The Sinter Authors -->
```

### 3. SPDX headers and build metadata

Every source file (`.ml`, `.mli`, `.rs` if any, `.sh`, `dune` files, CI YAML) gets a two-line header, using the comment syntax of the language:

```
(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright <year> The Sinter Authors *)
```

Build metadata:

- `dune-project`: `(license Apache-2.0)` and, once a package is defined, `(package (name sinter) (license Apache-2.0) ...)`.
- Any generated `sinter.opam`: `license: "Apache-2.0"`.
- If a Rust crate exists for the wasmtime bridge: `license = "Apache-2.0"` in its `Cargo.toml`.

### 4. `REUSE.toml`

Adopt the REUSE specification (<https://reuse.software/>) so the multi-license layout is machine-checkable. Create `REUSE.toml`:

```toml
version = 1
SPDX-PackageName = "sinter"
SPDX-PackageSupplier = "The Sinter Authors"

[[annotations]]
path = ["spec/**", "docs/**"]
precedence = "aggregate"
SPDX-FileCopyrightText = "The Sinter Authors"
SPDX-License-Identifier = "CC-BY-4.0"

[[annotations]]
path = ["**"]
precedence = "closest"
SPDX-FileCopyrightText = "The Sinter Authors"
SPDX-License-Identifier = "Apache-2.0"
```

Place the license texts where REUSE expects them: `LICENSES/Apache-2.0.txt` and `LICENSES/CC-BY-4.0.txt`. Keep the root `LICENSE` and `LICENSE-SPEC` files as the human-facing entry points (they may be copies or symlinks; copies are safer across platforms).

### 5. CI checks

Add a workflow (`.github/workflows/licensing.yml` or the equivalent for the chosen host) that runs on every pull request:

1. **DCO** — every commit in the PR has a `Signed-off-by:` trailer matching the author. On GitHub, install the DCO app or use a `dco-check`-style action; elsewhere, a script over `git log --format='%an <%ae>%n%(trailers:key=Signed-off-by,valueonly)'`.
2. **REUSE** — `pipx run reuse lint` exits 0.
3. **Third-party manifest** — `THIRD_PARTY.md` is regenerated and compared; drift fails the job.
4. **No forbidden licenses** — the generated dependency list contains no GPL, AGPL, SSPL, or "unknown" entries. LGPL is allowed only for the OCaml runtime under its linking exception.

### 6. Commit plan

Commit in this order, each signed off:

1. `LICENSE`, `LICENSES/`, `NOTICE`, `LICENSE-SPEC`, `DCO` — "Add licenses"
2. `REUSE.toml`, SPDX headers on any existing files — "Add REUSE metadata and SPDX headers"
3. `CONTRIBUTING.md`, README license section — "Document contribution terms"
4. `THIRD_PARTY.md` and the licensing CI workflow — "Add licensing checks"

## Repository: `sinter-packs` (when created)

The packs repository redistributes compiled tree-sitter grammars, each under its own upstream license. Layout per pack:

```
packs/<name>/
  pack.toml            descriptor; Apache-2.0
  grammar.wasm         compiled upstream grammar; upstream license
  queries/*.scm        pack-authored; Apache-2.0
  fixtures/            pack-authored; Apache-2.0
  LICENSE.upstream     verbatim upstream grammar license
  NOTICE               "grammar.wasm is built from <repo> at <commit> under <SPDX id>"
```

Requirements:

- `pack.toml` gains two required fields: `grammar_upstream = "<git url>@<commit>"` and `grammar_license = "<SPDX identifier>"`.
- `sinter pack verify` (in the tool) must fail a pack whose `LICENSE.upstream` is missing, whose `grammar_license` is not an SPDX identifier, or whose `grammar_license` is not on the allowlist (`MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `Unlicense`, `0BSD`, `MPL-2.0`). Anything else needs a human decision and a documented exception.
- Root `LICENSE` (Apache-2.0), `NOTICE`, `DCO`, `CONTRIBUTING.md` (same text as the tool's, plus a section on adding a pack: preserve the upstream license, record the commit, run `sinter pack verify`), and a `REUSE.toml` whose per-pack annotations map `grammar.wasm` and `LICENSE.upstream` to the upstream identifier.
- CI: the same four checks as the tool, plus `sinter pack verify --all`.

## Verification checklist

Before reporting done, confirm each of these and show the evidence:

- [ ] `LICENSE` is byte-identical to the canonical Apache-2.0 text (`sha256sum` against a fresh download).
- [ ] `LICENSE-SPEC` contains the implementability preamble followed by the canonical CC-BY-4.0 legal code.
- [ ] `reuse lint` passes.
- [ ] Every source and spec file has an SPDX header; `grep -rL "SPDX-License-Identifier" src spec docs` prints nothing.
- [ ] `dune-project` declares `Apache-2.0`.
- [ ] `CONTRIBUTING.md` covers inbound=outbound, DCO sign-off, agent-authored changes, third-party code.
- [ ] `THIRD_PARTY.md` exists (may be a stub with the expected entries until dependencies are pinned).
- [ ] The licensing CI workflow exists and runs the four checks.
- [ ] All commits carry `Signed-off-by:`.

## Not in scope

No CLA. No trademark policy. No dual licensing. No source-available or copyleft option. If someone asks for any of these, that is a decision for the maintainers, not this setup.
