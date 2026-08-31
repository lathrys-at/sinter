# Third-party components

This file lists each dependency that ships in the Sinter release binary.
Each line gives the license and a link.

The project has no pinned dependencies yet. The table below lists the
components that the design expects. When the build system exists, CI will
generate this file from the real dependency set. CI will then fail if
this file does not match the generated one.

| component | license | link |
|---|---|---|
| wasmtime | Apache-2.0 WITH LLVM-exception | https://github.com/bytecodealliance/wasmtime |
| tree-sitter runtime | MIT | https://github.com/tree-sitter/tree-sitter |
| jq (only if bundled) | MIT | https://github.com/jqlang/jq |
| oniguruma (a dependency of jq) | BSD-2-Clause | https://github.com/kkos/oniguruma |
| OCaml runtime | LGPL-2.1-only WITH OCaml-LGPL-linking-exception | https://ocaml.org/ |

Note on the OCaml runtime: its license is LGPL-2.1 with the OCaml linking
exception. The exception permits static linking. So we can link the
runtime statically into the Sinter binary.
