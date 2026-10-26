<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Read TOML with toml_edit through the bridge
@decision toml-reader v3
@cites rust-bridge
@cites licensing
@cites current-dependencies
Sinter reads `sinter.toml` and the front matter of rule files, as TOML 1.1, with the Rust crate `toml_edit` 0.25.17, through one function of the parser bridge, behind a TOML interface of Sinter's own in `lib/`.

## Context

The manifest and the front matter of rule files are TOML. The
reader must give the line and column of every key and value, so that
an error names its place. No OCaml library on opam does all three of
these: gives positions, has a license that the record `licensing`
allows, and installs beside the locked dependencies. In October 2026
the crate moved from 0.22.27 to 0.25.17 under the record
`current-dependencies`. From 0.24 the crate reads the forms of TOML
1.1, and it has no setting that turns them off.

## Decision

- The bridge exports one function that parses a TOML document with
  `toml_edit` and returns its values with their positions. The crate
  is pinned to an exact version, `=0.25.17`.
- `lib/` holds a TOML interface of Sinter's own. No other module sees
  the crate or the bridge function.
- The reader accepts TOML 1.1.0. A test checks that the forms that
  TOML 1.1 adds are accepted.
- The official TOML test suite is checked in, with its license. A test
  maps the message of every invalid case to one of Sinter's own
  messages, and fails on a message form it does not know.
- The bridge may host other Rust libraries that Sinter uses.

## Alternatives considered

- **Keep TOML 1.0 only on `toml_edit` 0.25, with checks in Sinter's
  code that refuse the forms of TOML 1.1.** Not chosen: five checks
  and their tests to keep a version of the format that is no longer
  the newest, and the specification gave no other reason for it.
- **Stay on `toml_edit` 0.22.27 until wasmtime stops linking it.** Not
  chosen: it keeps a dependency behind for weeks, against the record
  `current-dependencies`.

- **An OCaml library from opam.** Not chosen: `otoml` gives no
  positions for values, links an LGPL library, and its last release
  does not install beside the lock file; `toml` 7.1.0 is LGPL-3.0 and
  fails 86 of the 205 valid cases of the official suite.
- **A TOML reader of Sinter's own, in OCaml.** Not chosen as the
  first road, because it is the most code to write and test. It stays
  the fallback if the crate stops fitting.
- **A reader built on the tree-sitter TOML grammar, through the
  bridge.** Explored by two agents. Not chosen: it fits only with a
  grammar built into the binary, the grammar alone accepts 79 of the
  474 invalid cases, so most of a decoder must still be written, and
  its benefit to the grammar layer is one the scanner brings anyway.

## Consequences

The manifest reader gets exact positions and a reference-quality
parser. The binary holds `toml_edit` 0.22 as well while wasmtime's
cache links it. A manifest that uses a form of TOML 1.1 cannot be read
by a tool that knows only TOML 1.0. Sinter now depends on the
bridge for configuration as well as for parsing, and a change of the
crate's version is a reviewed change of the pin and of the message
map.
