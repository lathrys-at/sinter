# Third-party components

This file lists each dependency that ships in the Sinter release binary.
Each row of the table gives one component, the license of that
component, and a link.

The parser bridge pins its Rust dependencies in `bridge/Cargo.lock`.
That file names every crate and its version. The table below gives the
components whose license terms a reader must know. Some rows are
components that the design expects and the project does not pin yet.

| component | license | link |
|---|---|---|
| cmdliner | ISC | https://github.com/dbuenzli/cmdliner |
| yojson | BSD-3-Clause | https://github.com/ocaml-community/yojson |
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
