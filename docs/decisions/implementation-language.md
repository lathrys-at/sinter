<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Implement the core of Sinter in OCaml
@decision implementation-language
The core library and the `sinter` binary are OCaml; Rust appears only in the bridge that links tree-sitter and wasmtime.

## Context

Sinter has a closed vocabulary of fourteen tags. Every gate, query,
and compiler must handle every tag. The design notes (section 9)
want an unhandled tag to be a build error, not a discipline. The tool
also runs inside editor hooks, where startup time above a few
milliseconds gets the hook disabled. Language packs run in wasmtime,
which offers a Rust and a C interface. Coding agents write most of
the code, and they write OCaml less well than Rust or TypeScript.

## Decision

The core library `sinter.core` and the `sinter` binary are OCaml,
version 5.1 or newer, built with dune and installed with opam. The
vocabulary is a variant type, and every gate is an exhaustive match
over it: a new tag that a gate does not handle fails the build. The
tool shells out to git; it never links git. The only platform-specific
artifact is the native binary. Version 1 does not support Windows.

Rust appears in one place: the bridge that links the tree-sitter
library and wasmtime. The bridge holds no vocabulary logic.

## Alternatives considered

- **Rust** — rejected. Agents write Rust better, and Rust also has
  exhaustive matching. The design notes chose OCaml for the closed
  vocabulary as a variant type with pattern matching, for native
  startup in milliseconds, and for one module signature behind which
  the language packs, markdown, and TOML sit.
- **TypeScript** — rejected for the same reasons as Rust, and because
  a Node runtime adds startup time that hooks would feel.

## Consequences

Contributors need opam and an OCaml switch, and a Rust toolchain for
the bridge. Agents need more care with OCaml than with Rust; the
build catches what they miss in a match. The binary links wasmtime
and grows by its size. Windows support waits for a later version.
