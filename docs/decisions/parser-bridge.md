<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Load grammars through a Rust bridge linked into the binary
@decision parser-bridge
@cites implementation-language
Sinter loads tree-sitter grammars compiled to WebAssembly through a small Rust crate, linked statically into the `sinter` binary, that exposes six C functions to the OCaml core.

## Context

The design notes fix three things: language packs are tree-sitter
grammars compiled to WebAssembly (section 5.2), wasmtime runs them,
and the core of Sinter is OCaml (section 9). So the question is how
an OCaml program calls tree-sitter's parser with a wasm grammar.

Tree-sitter's C library has a wasm feature: it takes a wasmtime engine
and the bytes of a grammar, and returns a language object that parses
and answers queries like a native grammar. The wasmtime C interface is
a Rust build product. The tree-sitter Rust crate wraps the same C
library, and its `wasm` feature builds and links wasmtime by itself.
The Zed editor loads extension grammars through this exact stack.

Sinter runs inside editor hooks, where startup time matters, and it
must build on macOS and Linux from a clean checkout.

## Decision

- The bridge is a Rust crate in `bridge/`, license Apache-2.0. It
  depends on the `tree-sitter` crate with its `wasm` feature, so cargo
  builds tree-sitter and wasmtime together. It builds as a static
  library.
- The crate exposes six C functions: create an engine, free an
  engine, load a grammar from wasm bytes, parse a text and run a query
  over it, free a result, and read the last error message. An engine
  owns every grammar loaded into it. An empty query makes the run
  function return the parse tree as an S-expression.
- The result of a run is one flat buffer: a header, then one record
  per capture with the pattern index, the byte range, the row and
  column range, the capture name, the node type, and the captured
  text. `bridge/README.md` defines the layout.
- The OCaml library `sinter.bridge` in `lib/bridge/` binds the six
  functions with hand-written C stubs. It does not use the `ctypes`
  library. A stub copies the whole result buffer into an OCaml string
  and frees the bridge's copy in the same call, so no OCaml value
  points into memory the bridge owns. The buffer is decoded in OCaml.
- A dune rule runs `cargo build --release` and links the static
  library. The rule reads the system libraries the link needs from
  `cargo rustc --print native-static-libs`, so no per-platform list is
  written down.
- Cargo writes its build output to `$XDG_CACHE_HOME/sinter-bridge-build`
  (or `~/.cache/sinter-bridge-build`), one directory for every checkout
  on the machine. `CARGO_TARGET_DIR` overrides it.
- wasmtime's compiled-module cache is on, in wasmtime's default cache
  directory. A grammar is compiled once per machine; later loads read
  the compiled form.
- The bridge holds no vocabulary logic. It knows nothing about tags.

## Alternatives considered

- **Bind the tree-sitter C library and the wasmtime C interface
  directly from OCaml** — rejected. The wasmtime C interface is a
  Rust build product, so the build would either download prebuilt
  archives per platform or run cargo anyway. Tree-sitter's C interface
  is also wide, and one of its core types is a struct passed by value,
  which OCaml stubs handle badly. The Rust crate does the same work
  with less code of ours.
- **A helper process, `sinter-parse`, speaking JSONL over a pipe** —
  rejected for the bridge. It needs no foreign-function code and
  isolates a parser crash, but it makes two binaries to distribute,
  and the design wants one. A serve mode over stdin and stdout gives
  callers the same composition without a second binary.
- **Native grammars loaded as shared libraries** — rejected. The
  design requires packs that carry no native code, so that a pack can
  be fetched by hash and run without trust in a `.so` file.
- **The `ctypes` library instead of hand-written stubs** — rejected.
  Six functions do not justify a dependency, and `ctypes` adds startup
  cost that hooks would feel.
- **Cargo's build output inside `_build`, or one directory per
  checkout** — rejected after measurement. Dune empties a rule's
  directory before the rule runs, so a target inside `_build` rebuilt
  all 128 crates on every edit inside `bridge/`. A directory per
  checkout costs 19 seconds and 900 MB for each of the many worktrees
  Sinter is written in; one shared directory builds a fresh clone in
  under a second.
- **No compiled-module cache** — rejected. The design notes assume the
  cache, and the measurement below shows why: without it, seven
  version-1 packs cost about 105 ms of grammar load in every process.

## Consequences

Contributors need the Rust toolchain and `cmake`, which a build script
of wasmtime runs. The binary grows from 2.0 MB to 15.4 MB, inside the
10 to 20 MB the design notes expect. The build is no longer hermetic:
`dune clean` does not remove cargo's output. The query is compiled on
every call, which costs 0.015 ms for a two-pattern query and 0.7 ms
for a hundred patterns; the scanner will want to compile a query once
and run it over many files, which is a change inside the crate and
not to the six functions.

Measured on the pair's Apple silicon machine, with the commands in
the pull request that added the bridge:

| measurement | result |
|---|---|
| binary size | 2,089,576 bytes without the bridge; 16,149,496 with it |
| first load, tree-sitter-json (5.6 KB) | 1.5 ms |
| first load, tree-sitter-typescript (1.4 MB), no cache | 17.5 ms; engine creation 8.2 ms |
| first load, tree-sitter-typescript, module cache warm | 3.3 ms; engine creation 0.5 ms |
| parse and query, a 214 KB JSON file | 26 ms, 6,300 captures |
| static link, macOS arm64 | clean; `-liconv -lSystem -lc -lm`, no framework |
| static link, Linux x86_64 (CI) | clean; `-lgcc_s -lutil -lrt -lpthread -lm -ldl -lc` |

The design's safety claim holds. The import section of
tree-sitter-json names linear memory, a function table, and two
relocation bases, and no function at all. tree-sitter-typescript adds
two character-classification functions, `iswspace` and `iswalpha`,
which tree-sitter's own host supplies. Neither grammar imports
anything from a WASI module. So a grammar imports memory, a table,
two relocation bases, and a small set of character-classification
functions from tree-sitter's host, and nothing else.
