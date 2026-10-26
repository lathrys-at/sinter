<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Keep comments to tags and to the text that a language expects
@decision code-comments
A comment in Sinter's code is a tag block that Sinter reads, or text that the community of the language expects, and it states what the code does, not why.

## Context

Coding agents write most of Sinter's code, and they wrote many
comments that explain a choice, tell what happened before, or
describe what the code already shows. People read Sinter's code
rarely. An agent reads the code itself and does not need such
comments. A comment that explains a reason also goes out of date when
the code changes, and nothing checks it.

## Decision

A comment is permitted only in these cases:

- Sinter reads it: a tag block, with the prose that follows the tags
  as their description.
- The community of the language expects it: the API comment on an
  exported value (`(** *)` in an `.mli` file, `///` and `//!` in Rust,
  with the `# Safety` section of an `unsafe` function, a comment on a
  declaration in a C header), and the license header of a file.

A permitted comment is descriptive and mechanistic. It states what
the code takes, what it gives, what it guarantees, and what can go
wrong. It never states why the code is as it is, what it replaced, or
what else was possible. Reasons go in decision records, in the
specifications, and in commit messages.

The reason of a `[@mutaml.skip "reason"]` attribute stays, in the
same mechanistic form: it states why the mutant is equivalent in terms
of what the code does.

The rule applies to every file of code: OCaml, Rust, C, shell, the CI
workflows, the build files, the TOML files, and the tests. Every other
comment is removed.

## Alternatives considered

None were put forward.

## Consequences

The code holds fewer lines, and no comment can contradict the code
that it stands beside. A reason that a reader needs is in a record or
a specification, where a tag can cite it and Sinter can check it. A
person who reads the code without an agent has less help.
