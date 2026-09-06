# Instructions for coding agents

Coding agents write much of Sinter. This file tells an agent how to
work in this repository. [CONTRIBUTING.md](CONTRIBUTING.md) holds the
rules for every contributor. Read CONTRIBUTING.md first. The rules
below add to the rules in CONTRIBUTING.md.

## Writing

Follow the "Writing" section of CONTRIBUTING.md strictly. That section
applies to every text you produce: documentation, specifications,
comments, commit messages, the tool's output, and your replies to the
person you work with. Write for the readers of the repository, not for
that person. Avoid these three faults:

- Do not use invented jargon.
- Do not compress several ideas into one phrase.
- Do not leave out the context that a sentence needs.

## Layout

| path | content | license |
|---|---|---|
| `lib/` | the core library, `sinter.core` | Apache-2.0 |
| `bin/` | the `sinter` executable | Apache-2.0 |
| `test/` | the test suite | Apache-2.0 |
| `spec/` | the four normative specifications | CC-BY-4.0 |
| `docs/` | the design notes and other prose | CC-BY-4.0 |
| `.github/workflows/` | CI: `build.yml` and `licensing.yml` | Apache-2.0 |

[docs/design-notes.md](docs/design-notes.md) holds the design.
[spec/](spec/) holds the formats other tools can implement.
[docs/roadmap.md](docs/roadmap.md) lists the work ahead and the
directions that are agreed but not designed yet.
[docs/decisions/](docs/decisions/) holds the decision records; read
the record before you re-argue a choice. When the
code and a specification disagree, the specification wins. When a
specification and the design notes disagree, tell the person you work
with. The specifications are the newer documents.

## Build and check

```
eval $(opam env)
dune build
dune test
dune fmt
```

Run `dune build`, `dune test`, and `dune fmt` before every commit.
`dune fmt` rewrites files in place. Commit the files that `dune fmt`
changes. Also run `reuse lint` (see CONTRIBUTING.md).

## New files

Every new file needs an SPDX header with the license of its
directory, and the line `Copyright <year> The Sinter Authors`:

<!-- REUSE-IgnoreStart -->
- OCaml: `(* SPDX-License-Identifier: Apache-2.0 *)`
- dune files: `; SPDX-License-Identifier: Apache-2.0`
- YAML and shell: `# SPDX-License-Identifier: Apache-2.0`
- Markdown in `spec/` and `docs/`:
  `<!-- SPDX-License-Identifier: CC-BY-4.0 -->`
<!-- REUSE-IgnoreEnd -->

Files at the repository root need no header. `REUSE.toml` covers those
files. Keep the two ignore markers around the list above. The markers
stop the `reuse` tool from reading the examples as license tags for
this file.

## Commits

- Sign off every commit with `git commit -s`. The person who runs
  you is the contributor of record. That person reviews what you sign
  off.
- Add a trailer that names you, for example `Assisted-by: Claude Code`
  or `Co-Authored-By: <agent> <email>`.
- Use an imperative subject line and a short body that says what
  changed and why.
- Do not commit build output. `.gitignore` covers `_build/`.
