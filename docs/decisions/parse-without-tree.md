<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Treat a parse that gives no tree as a parse failure
@decision parse-without-tree
When the parser gives no syntax tree for a file, Sinter reports one parse-error finding at line 1, column 1, takes no fact from the file, and goes on with the scan.

## Context

The OCaml grammar v0.26.0 gives no tree for a file with 4,675 nested
comments; it parses one with 4,674. The upstream fix is in no release.
The specification did not say what a scan does when the parser gives
no tree. Today `sinter parse` stops with exit code 3.

## Decision

A parse that gives no tree is a parse failure of that file
(`spec/packs.md` section 5.2), in every pack, the markdown pack
included. The file yields no fact, and Sinter
reports one `parse-error` finding at line 1, column 1, as for a file
that is not valid UTF-8 (section 5.1). The scan goes on. A grammar that
does not load still stops the command (section 3.6). The step "Read
JavaScript, OCaml, Rust, and TypeScript" builds the rule.

## Alternatives considered

- **Stop the command with exit code 3.** Not chosen: one file that the
  grammar cannot parse would stop every scan of the repository, and
  the OCaml pack could not ship the upstream grammar.

## Consequences

The OCaml pack can use the upstream release v0.26.0. A file with no
tree gives a finding that a person sees, not a stopped command.
