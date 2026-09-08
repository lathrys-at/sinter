# Contributing to Sinter

## Writing

All text in this repository uses Simplified Technical English
(ASD-STE100) in the style of Simple English Wikipedia. This style
applies to documentation, specifications, code comments, commit
messages, pull requests, and the tool's own output. The rules:

- Write for the people who use Sinter or contribute to it. Assume
  they do not share your context.
- Use short sentences: one idea per sentence, about 20 words or
  fewer.
- Use the active voice and simple tenses.
- Use one word for one meaning, and use it the same way every time.
- Do not invent terms. When a technical term is necessary, define it
  at first use.
- Give every pronoun one clear referent. Repeat the noun when in
  doubt.
- Give the context before the detail, so that each sentence makes
  sense on its own.
- Use a numbered list for a sequence of steps.
- Use a table for facts that a reader can enumerate.
- Do not add notes that explain why a sentence or a file exists, or
  that restate what a reader can infer from the stated facts.
- Do not open a document with prose that explains what the document
  is, what it is not, or how a reader will use it. Start with the
  content.
- Do not narrate the process that produced a document or a change.
  Say what the thing is, not how it came to be.
- A list document — a roadmap, a checklist — is a flat list of items
  with brief names and their subtasks beneath them. Do not group the
  items under relative time headings.

We reproduce some text from elsewhere: license texts, the DCO, and
quoted standards. That text stays exactly as it is in the source.

### Code comments

A comment states something that the code cannot show: an ownership
rule, a lifetime, a precondition, a unit, an invariant, a contract.
Write nothing else in a comment.

- Do not restate what the code shows.
- Do not explain background that the reader does not need for the
  code in front of them.
- Do not explain why a line or a file exists.
- Do not reference the design notes or a specification, by name or
  by section. A choice that needs a reference rests on a decision
  record in `docs/decisions/`, and the comment block cites it with a
  tag line: `(* @cites <slug> *)` in OCaml, `// @cites <slug>` in
  Rust, `/* @cites <slug> */` in C.

A comment on an interface — a header file, an `.mli` file, a public
function — addresses the caller. It states what the function takes,
what it returns, who owns the result, and when the result stops being
valid. It does not narrate the implementation, and it does not list
what the interface does not offer.

### Messages that the tool prints

An error message or a help text addresses the person who runs the
tool. It says what is wrong and, when useful, what to do. It never
names a repository file or a document section, and it never explains
the tool's internal reasons.

## Build and check

Install [opam](https://opam.ocaml.org/) and an OCaml switch (5.1 or
newer). The parser bridge in `bridge/` is a Rust crate, so also
install the Rust toolchain with [rustup](https://rustup.rs) and
install `cmake`, which a build script of wasmtime runs. Then, from the
repository root:

```
eval $(opam env)
opam install . --deps-only --with-test --with-dev-setup --locked
dune build
dune test
dune fmt
```

The `--with-dev-setup` flag installs `ocamlformat`, and `--locked`
installs the versions in `sinter.opam.locked`, the same versions CI
uses. When you change the dependencies in `dune-project`, run
`dune build` and then `opam lock ./sinter.opam`, and commit both
`sinter.opam` and `sinter.opam.locked`.

Before you commit, check that all of these pass:

- `dune build`, `dune test`, and `dune build @fmt`. `dune fmt`
  rewrites files in place; commit the files it changes.
- `reuse lint` (run it with `pipx run reuse lint`).
- In `bridge/`: `cargo fmt --check` and
  `cargo clippy --all-targets -- -D warnings`.

CI runs all of them.

## New files

Every new file needs an SPDX header with the license of its
directory, and the line `Copyright <year> The Sinter Authors`:

<!-- REUSE-IgnoreStart -->
- OCaml: `(* SPDX-License-Identifier: Apache-2.0 *)`
- Rust: `// SPDX-License-Identifier: Apache-2.0`
- C: `/* SPDX-License-Identifier: Apache-2.0 */`
- dune files: `; SPDX-License-Identifier: Apache-2.0`
- YAML, TOML, and shell: `# SPDX-License-Identifier: Apache-2.0`
- Markdown in `spec/` and `docs/`:
  `<!-- SPDX-License-Identifier: CC-BY-4.0 -->`
<!-- REUSE-IgnoreEnd -->

Files at the repository root need no header; `REUSE.toml` covers
them. Keep the two ignore markers around the list above. The markers
stop the `reuse` tool from reading the examples as license tags for
this file.

## Commits

- Sign off every commit with `git commit -s`. The line certifies
  that your contribution satisfies the Developer Certificate of
  Origin; the DCO file holds the full text. CI rejects a commit that
  has no sign-off.
- Use an imperative subject line and a short body that says what
  changed and why.
- Do not commit build output. `.gitignore` covers `_build/`.

### Changes written by agents

Coding agents write much of this codebase. We expect this practice and
we welcome it. The human who runs the agent signs off the commit. That
human is the contributor of record. When an agent wrote a large part of
a change, add a trailer to the commit message that names the agent. You
can use either of these two trailers:

- `Assisted-by: Claude Code` — the agent helped; the human is the
  author.
- `Co-Authored-By: Claude Code <noreply@anthropic.com>` — the agent is
  named as a co-author. GitHub shows co-authors next to the commit.

Both trailers keep the record of authorship in the git history. Do not
sign off code that you did not review.

## Decisions, plans, and rulings

- Decisions that shape the project live in `docs/decisions/`, one file
  per decision, with a `@decision` tag. Read the record before you
  re-argue a choice. To record a new decision, use the
  `/sinter:decision` skill or follow its format. "Alternatives
  considered" lists only the alternatives that someone put forward
  and that were deliberated: in an issue, a pull request, a plan, the
  design notes, or with the maintainer. When nobody put one forward,
  the section says so. A decision that rests on measurements carries
  them.
- Implementation work follows a plan in `.plans/`, written with the
  `/sinter:plan` skill. A change to a plan's promises or scopes is an
  amendment. Make it a separate, small pull request, so that the
  maintainer's merge is the approval.
- Ask a design question in a GitHub issue, with the options and their
  costs. The maintainer rules; the ruling is then carried out in a
  pull request.

## Pull requests

Every change reaches `main` through a pull request. The maintainer
reviews and merges; merges are squash merges.

A pull request description is documentation for the people who review
the change and for the people who read it later. It says what the
change adds, what it does not do, measurements when there are any,
and where to look first. It follows the writing rules above. It does
not describe the process that produced the change.

A review comment names an example of a defect, not its only instance.
When you address a comment, find and fix every instance of the same
defect across the whole change.

## Licensing of contributions

Sinter uses two licenses:

- The code uses the Apache-2.0 license. See the LICENSE file.
- The specifications and the documentation use the CC-BY-4.0 license.
  See the LICENSE-SPEC file.

When you contribute, you agree to one condition: your contribution uses
the same license as the file that it changes. People call this model
"inbound = outbound". We do not use a Contributor License Agreement (CLA).

## Third-party code

Do not copy code from other projects, unless both conditions below are
true:

1. The license of the code is compatible with Apache-2.0.
2. You add the code to THIRD_PARTY.md.

Never copy GPL or AGPL code into this repository.
