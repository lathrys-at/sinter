<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# The Sinter parser bridge

The bridge is a Rust crate. It links the tree-sitter library and the
wasmtime runtime. It loads a tree-sitter grammar that is compiled to
WebAssembly, parses a source text with that grammar, and runs a
tree-sitter query over the parse tree. It gives the results to OCaml
through a C interface of six functions.

The bridge holds no Sinter vocabulary. It knows about grammars,
source text, queries, and captures, and nothing else. See
[docs/decisions/implementation-language.md](../docs/decisions/implementation-language.md).

## Build

```
cargo build --release
```

The crate builds a static library, `libsinter_bridge.a`. The OCaml
library `sinter.bridge` in `lib/bridge/` links it. A dune rule runs
the cargo build, so `dune build` at the repository root builds the
crate too.

## The C interface

[include/sinter_bridge.h](include/sinter_bridge.h) declares six
functions:

| function | purpose |
|---|---|
| `sinter_bridge_engine_new` | create an engine |
| `sinter_bridge_engine_free` | free an engine and its languages |
| `sinter_bridge_language_load` | load a grammar from wasm bytes |
| `sinter_bridge_run` | parse a source text and run a query |
| `sinter_bridge_result_free` | free a result |
| `sinter_bridge_last_error` | read the message of the last failure |

Three rules govern the lifetimes:

1. The engine owns every language that was loaded into it. A language
   handle stays valid until the engine is freed. No function frees a
   single language.
2. A result owns its buffer. Read the buffer before you free the
   result.
3. Every function that can fail returns `NULL` on failure and stores
   the reason. `sinter_bridge_last_error` returns that reason. The
   message is stored per thread.

An engine is not safe to use from two threads at the same time. One
thread at a time may call `sinter_bridge_run` on one engine.

## The result buffer

`sinter_bridge_run` returns one flat buffer. The buffer holds a header
and then the records. Every integer is unsigned, 32 bits wide, and
little-endian. No field is padded and no field is aligned: a reader
must copy the four bytes of an integer before it reads them. Every
string is UTF-8 and carries no terminating NUL byte.

### Header

The header is 16 bytes.

| offset | size | field | meaning |
|---|---|---|---|
| 0 | 4 | magic | the ASCII bytes `S`, `B`, `R`, `1` |
| 4 | 4 | kind | `0` for captures, `1` for a parse tree |
| 8 | 4 | count | the number of records that follow |
| 12 | 4 | reserved | always `0` |

### A capture record, when kind is 0

The buffer holds one record per capture, in the order in which the
query cursor produced them. Each record holds seven integers, and then
three strings. Each string is a length in bytes and then that many
bytes.

| field | type | meaning |
|---|---|---|
| pattern | u32 | the index of the pattern in the query, from 0 |
| sbyte | u32 | the start of the node, a byte offset from 0 |
| ebyte | u32 | the end of the node, exclusive, a byte offset |
| srow | u32 | the start row of the node, from 0 |
| scol | u32 | the start column of the node, in bytes, from 0 |
| erow | u32 | the end row of the node, from 0 |
| ecol | u32 | the end column of the node, in bytes, exclusive |
| name | u32 + bytes | the capture name, without the `@` |
| type | u32 + bytes | the type of the node, for example `string` |
| text | u32 + bytes | the source text of the node |

### A tree record, when kind is 1

The buffer holds one record. The record is a length in bytes and then
that many bytes: the parse tree as an S-expression.

## The wasm surface of a grammar

A tree-sitter grammar that is compiled to WebAssembly imports nothing
but the functions that tree-sitter's own runtime supplies. It has no
WASI imports, so it cannot read a file, open a socket, or read the
clock. The design notes state this in section 5.2. The file
`measurements.md` of the parser-bridge work records the import section
of the fixture grammar.
