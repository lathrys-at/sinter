<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# The Sinter parser bridge

The bridge is a Rust crate. It links the tree-sitter library and the
wasmtime runtime. It loads a tree-sitter grammar that is compiled to
WebAssembly, parses a source text with that grammar, and runs a
tree-sitter query over the parse tree. It also computes the SHA-256
digest of a byte string, and reads a TOML document with the crate
`toml_edit`. It gives the results to OCaml through a C interface of
eight functions.

The bridge knows about grammars, source text, queries, captures,
digests, and TOML documents. It holds no Sinter vocabulary. The
reasons are in
[docs/decisions/parser-bridge.md](../docs/decisions/parser-bridge.md).

## Build

```
cargo build --release
```

The crate builds a static library, `libsinter_bridge.a`. The OCaml
library `sinter.bridge` in `lib/bridge/` links it.

The build needs `cmake` on the PATH, next to cargo. The crate depends
on `tree-sitter` with its `wasm` feature, which depends on
`wasmtime-c-api`. That package's build script runs cmake to install
the wasmtime C headers. Without cmake the build stops with
`failed to spawn cmake`.

The static library is about 40 MB. It holds wasmtime and the
Cranelift compiler.

`dune build` at the repository root builds the crate as well, through
a rule in `lib/bridge/dune`. That rule writes its output under the
user cache, by default `~/.cache/sinter-bridge-build`, in a directory
of its own for each checkout. `lib/bridge/build.sh` chooses the
directory, names it from the path of the crate, and writes the path
of the checkout into a file named `checkout` inside it. Two checkouts
must not share one: cargo would call the second checkout fresh and
leave the first checkout's library in place. `CONTRIBUTING.md`, in
"The bridge's build directory", says how to remove the directories of
checkouts that are gone.

The command above writes to `bridge/target` instead, so a contributor
who runs both has two copies of the build. `dune clean` removes
neither. To build the crate from nothing, remove one by hand.

## Checking the build directory rule

Each checkout builds the crate in its own directory. When
`lib/bridge/build.sh` changes, check the rule by hand; the check is
not part of CI, because it builds the crate twice from nothing.

1. Unpack the branch into two directories, A and B.
2. In B, add `#[no_mangle] pub static RB_MARKER: [u8; 16] =
   *b"RBE2EMARKERXYZZY";` to `bridge/src/lib.rs`, and run `touch` on
   that file so that B's sources are the newer ones.
3. Point `CARGO_TARGET_DIR` at one empty directory for both.
4. Run `dune build` in B, then in A. Use the same command in both;
   a plain `cargo build` in one of them hides the failure, because the
   dune rule adds `--print native-static-libs` to the command line,
   and cargo keeps a separate freshness record for it.
5. Count the marker in each `_build/default/lib/bridge/libsinter_bridge.a`
   with `strings -a ... | grep -c XYZZY`. The right answer is 1 in B
   and 0 in A. With one shared directory it is 1 in both.

## The C interface

[include/sinter_bridge.h](include/sinter_bridge.h) declares eight
functions:

| function | purpose |
|---|---|
| `sinter_bridge_engine_new` | create an engine |
| `sinter_bridge_engine_free` | free an engine and its languages |
| `sinter_bridge_language_load` | load a grammar from wasm bytes |
| `sinter_bridge_run` | parse a source text and run a query |
| `sinter_bridge_sha256` | compute the SHA-256 digest of a byte string |
| `sinter_bridge_toml_parse` | read a TOML document |
| `sinter_bridge_result_free` | free a result |
| `sinter_bridge_last_error` | read the message of the last failure |

Three rules govern the lifetimes:

1. The engine owns every language that was loaded into it. A language
   handle stays valid until the engine is freed.
2. A result owns its buffer. Read the buffer before you free the
   result.
3. Every function that can fail returns `NULL` on failure and stores
   the reason. `sinter_bridge_last_error` returns that reason. The
   message is stored per thread.

One thread at a time may use one engine.

## The result buffer

`sinter_bridge_run`, `sinter_bridge_sha256`, and
`sinter_bridge_toml_parse` return one flat buffer. The buffer holds a
header and then the records. Every integer is
unsigned, 32 bits wide, and little-endian. No field is padded and no
field is aligned: a reader must copy the four bytes of an integer
before it reads them. Every string is UTF-8 and carries no terminating
NUL byte.

The 32 bits bound what the bridge can report. A source of 2^32 bytes
or more fails with a message before the bridge reads it, and so does
a parse tree whose S-expression is 2^32 bytes or more. The bridge
never truncates a length or an offset to fit.

### Header

The header is 16 bytes.

| offset | size | field | meaning |
|---|---|---|---|
| 0 | 4 | magic | the ASCII bytes `S`, `B`, `R`, `1` |
| 4 | 4 | kind | `0` for captures, `1` for a parse tree, `2` for a digest, `3` for a TOML document, `4` for a TOML error |
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

### A digest record, when kind is 2

The buffer holds one record: the 32 bytes of the SHA-256 digest. No
length comes before them.

### A TOML document, when kind is 3

The buffer holds one record: the top-level table of the document. A
byte offset counts from the start of the TOML text, and the end of a
span is exclusive.

A **table** is a count, and then that many entries. An **entry** is
one key and its value:

| field | type | meaning |
|---|---|---|
| name | u32 + bytes | the key, decoded: no quotes, and every escape resolved |
| kstart | u32 | the start of the key, a byte offset |
| kend | u32 | the end of the key |
| value | a value | the value of the key |

A **value** is a tag, a span, and the content that the tag names:

| tag | value | content after the span |
|---|---|---|
| 0 | a string | u32 + bytes: the string, decoded |
| 1 | an integer | 8 bytes: a signed 64-bit integer, little-endian |
| 2 | a float | 8 bytes: the bits of a 64-bit float, little-endian |
| 3 | a boolean | u32: `0` or `1` |
| 4 | a date or a time | ten u32 fields; see below |
| 5 | an array | a count, and then that many values |
| 6 | a table that a table header or a dotted key makes | a table |
| 7 | an array of tables | a count, and then that many tables |
| 8 | an inline table | a table |

The span of a value is two u32 fields: the start and the end. For an
inline table, the span holds the braces. A table that a table header
or a dotted key makes is not one piece of the text, and nor is an
array of tables: each takes the span of its key.

A date or a time holds these fields, in this order:

| field | meaning |
|---|---|
| parts | `1` for a date, `2` for a time, `3` for a date and a time, `7` for a date, a time, and an offset |
| year, month, day | the date, or `0` when there is none |
| hour, minute, second, nanosecond | the time, or `0` when there is none |
| offset | `0` for `Z` or for no offset, `1` for an offset in minutes |
| minutes | the offset in minutes, a signed 32-bit integer, or `0` |

### A TOML error, when kind is 4

The buffer holds one record: why the text is not a TOML document. The
record starts with a form, a u32, and a span, two u32 fields.

| form | meaning | fields after the span |
|---|---|---|
| 0 | `toml_edit` stopped at the span | the message of `toml_edit`, u32 + bytes; it can hold more than one line |
| 1 | a dotted key at the span adds a key to a table that a table header made | the dotted key as the text writes it, u32 + bytes; the names of that table from the top level, a count and then that many strings; `1` when that table is the last table of an array of tables, else `0`, a u32; the names of the dotted key after that table, a count and then that many strings |

`toml_edit` reports form 1 as a duplicate key and names a key that is
not one. The bridge finds the case: it reads the text before the
dotted key again, finds the table that the last table header opened,
and follows the dotted key from it.

## The wasm surface of a grammar

A tree-sitter grammar that is compiled to WebAssembly imports nothing
but what tree-sitter's own runtime supplies. It has no WASI import, so
it cannot read a file, open a socket, or read the clock. To check a
grammar, read the import section of its wasm file.

The fixture grammar, `test/fixtures/tree-sitter-json/`, imports four
things and no function at all:

| module | name | kind |
|---|---|---|
| `env` | `__memory_base` | global |
| `env` | `__table_base` | global |
| `env` | `memory` | memory, minimum 1 page |
| `env` | `__indirect_function_table` | table, minimum 1 entry |

A larger grammar imports a few functions as well. The grammar of
tree-sitter-typescript, release v0.23.2, imports the same four things
and two more: `env.iswspace` and `env.iswalpha`. Both classify
characters. Neither reads a file, opens a socket, or reads the clock.
