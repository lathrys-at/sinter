# Third-party components

This file names the third-party components that a reader of the
license notices must know: the components that ship in the Sinter
release binary, the components that are checked into the repository,
and the components that the test suite links. Each row of a table
gives one component, the license of that component, and a link.

The parser bridge pins its Rust dependencies in `bridge/Cargo.lock`.
That file names every crate and its version, and the tables below do
not repeat it. The licensing workflow reads the license of every crate
in that lock file and fails on a forbidden one. Some rows below are
components that the design expects and the project does not pin yet.

| component | license | link |
|---|---|---|
| cmdliner | ISC | https://github.com/dbuenzli/cmdliner |
| wasmtime | Apache-2.0 WITH LLVM-exception | https://github.com/bytecodealliance/wasmtime |
| tree-sitter runtime | MIT | https://github.com/tree-sitter/tree-sitter |
| cranelift (a dependency of wasmtime) | Apache-2.0 WITH LLVM-exception | https://github.com/bytecodealliance/wasmtime |
| jq (only if bundled) | MIT | https://github.com/jqlang/jq |
| oniguruma (a dependency of jq) | BSD-2-Clause | https://github.com/kkos/oniguruma |
| OCaml runtime | LGPL-2.1-only WITH OCaml-LGPL-linking-exception | https://ocaml.org/ |

## Files in the repository

These components are checked into the repository. They are not part of
the release binary. Each one keeps its own license file beside it.

| component | license | link |
|---|---|---|
| tree-sitter-json grammar, release v0.24.8, a test fixture | MIT | https://github.com/tree-sitter/tree-sitter-json |

## Test dependencies

The test suite links these components. They are not part of the
release binary, and the release notices do not name them.

| component | license | link |
|---|---|---|
| alcotest | ISC | https://github.com/mirage/alcotest |
| qcheck | BSD-2-Clause | https://github.com/c-cube/qcheck |
| qcheck-alcotest | BSD-2-Clause | https://github.com/c-cube/qcheck |
| yojson | BSD-3-Clause | https://github.com/ocaml-community/yojson |
