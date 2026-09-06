# Working in this repository

This file orients a session to the Sinter repository: a person's
coding agent, a subagent, or a person. `AGENTS.md` is a symbolic link
to this file.

## Start here

Do these three things in order, before you change anything:

1. **Orient.** Read "What Sinter is" and "Layout" below. Then read the
   documents that the work touches: `docs/design-notes.md` for the
   design, `spec/` for the formats, `docs/roadmap.md` for the work
   ahead, and `docs/decisions/` for what is already decided.
2. **Learn the rules.** Read `CONTRIBUTING.md` in full. It holds the
   writing rules for prose, for code comments, and for the messages
   the tool prints; the build and check commands; the license headers;
   the commit rules; and how plans, decisions, and pull requests work.
3. **Begin.** Find the plan step in `.plans/`, the issue, or the
   request that asks for the work. Work on a branch. Run the checks
   before every commit.

If a file named `CLAUDE.local.md` exists at the repository root, read
it after this file. It holds instructions for one person's machine and
method. Git ignores it, and it binds only the sessions of the person
who wrote it.

## What Sinter is

Sinter traces plans, requirements, decisions, and tests through a
repository. It reads tags in the repository's own text files, and it
checks that code, tests, and documents keep the agreements a project
made. It reads the state of the work from files and from test
results, never from an agent's report about its own work. Coding
agents write most of Sinter, and Sinter's own method applies to Sinter.

## Layout

| path | content | license |
|---|---|---|
| `lib/` | the core library, `sinter.core`, and the bridge library | Apache-2.0 |
| `bin/` | the `sinter` executable | Apache-2.0 |
| `bridge/` | the Rust crate that loads grammars through wasmtime | Apache-2.0 |
| `test/` | the test suite and its fixtures | Apache-2.0 |
| `spec/` | the four normative specifications | CC-BY-4.0 |
| `docs/` | the design notes, the roadmap, the decision records | CC-BY-4.0 |
| `.plans/` | plan files and their journals | Apache-2.0 |
| `plugins/` | the Claude Code plugin with the project's skills | Apache-2.0 |
| `.github/workflows/` | CI | Apache-2.0 |

## Which document wins

When the code and a specification disagree, the specification wins.
When a specification and the design notes disagree, the specification
is the newer document; tell the person you work with.
`docs/roadmap.md` lists directions that are agreed but not designed;
do not design one until the maintainer asks.

## Writing

Follow the "Writing" section of `CONTRIBUTING.md` strictly. It applies
to every text you produce: documentation, specifications, comments,
commit messages, the tool's output, and your replies to the person you
work with. Write for the readers of the repository, not for that
person.
