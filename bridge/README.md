<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# The Sinter parser bridge

The bridge is a Rust crate. It links the tree-sitter library and the
wasmtime runtime. It loads a tree-sitter grammar that is compiled to
WebAssembly, parses a source text with that grammar, and runs a
tree-sitter query over the parse tree. It calls a function of a runner
adapter, a WebAssembly module, with bytes in and bytes out, under
limits of fuel and memory. It also computes the SHA-256 digest of a
byte string, and reads a TOML document with the crate `toml_edit`. It gives the results to OCaml through a C interface.

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

[include/sinter_bridge.h](include/sinter_bridge.h) declares these
functions:

| function | purpose |
|---|---|
| `sinter_bridge_engine_new` | create an engine |
| `sinter_bridge_engine_free` | free an engine |
| `sinter_bridge_language_load` | load a grammar from wasm bytes |
| `sinter_bridge_language_free` | free a language |
| `sinter_bridge_parse` | parse a source text into a tree |
| `sinter_bridge_tree_free` | free a tree |
| `sinter_bridge_tree_memory` | estimate the memory that a tree holds |
| `sinter_bridge_tree_sexp` | write a tree as an S-expression |
| `sinter_bridge_tree_errors` | report the error nodes of a tree |
| `sinter_bridge_query_new` | compile a query |
| `sinter_bridge_query_free` | free a query |
| `sinter_bridge_query_run` | run a query over a tree |
| `sinter_bridge_adapter_load` | load and check a runner adapter |
| `sinter_bridge_adapter_interface` | read the interface version of an adapter |
| `sinter_bridge_adapter_free` | free an adapter |
| `sinter_bridge_adapter_call` | call a function of an adapter |
| `sinter_bridge_run` | parse a source text and run a query |
| `sinter_bridge_sha256` | compute the SHA-256 digest of a byte string |
| `sinter_bridge_toml_parse` | read a TOML document |
| `sinter_bridge_result_free` | free a result |
| `sinter_bridge_last_error` | read the message of the last failure |
| `sinter_bridge_last_failure` | read the last failure |

A **handle** is an engine, a language, a tree, a query, or an adapter.
These rules govern the lifetimes:

1. The caller owns every handle and every result that a function
   returns, and frees each with its own function.
2. Each handle owns what it needs. A language, a tree, a query, and an
   adapter stay valid after the engine is freed. A tree and a query stay valid
   after their language is freed. A tree holds a copy of the source
   text it was parsed from.
3. A result owns its buffer. Read the buffer before you free the
   result.
4. Every function that can fail returns `NULL` on failure and stores
   the failure. `sinter_bridge_last_failure` returns that failure in a
   buffer of kind 5. The failure is stored per thread.

One thread at a time may use one handle.

A query holds only the predicates that tree-sitter's Rust library
applies to a match: `#eq?`, `#not-eq?`, `#any-eq?`, `#any-not-eq?`,
`#match?`, `#not-match?`, `#any-match?`, `#any-not-match?`,
`#any-of?`, and `#not-any-of?`. A query with any other predicate, or
with a directive such as `#set!`, does not compile.

## Runner adapters

An adapter runs in its own wasmtime engine, which counts **fuel**: a
number that wasmtime lowers as WebAssembly code runs. Most
instructions cost one unit. The engine of grammars counts no fuel,
because tree-sitter's own WebAssembly code then fails. The engine of
adapters is made on the first load of an adapter, from a copy of the
settings of the engine of grammars, so the two share wasmtime's cache
of compiled modules.

Each call of an adapter runs in a new instance of the module, under
two limits that the caller gives. The limit of fuel covers the start
of the instance, the two calls of `sinter_alloc`, and the call of the
function. The limit of memory bounds the size of all linear memories
of the instance together. A growth past the limit stops the call, and
the failure gives the size that the bridge refused.

The tables of an instance hold at most 1,048,576 elements together.
wasmtime allocates one pointer in the host for each element, so
without a bound one `table.grow` could take all the memory of the
process. A growth past the bound fails inside the module: `table.grow`
gives -1. A module whose tables start larger does not start.

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
| 4 | 4 | kind | `0` for captures, `1` for a parse tree, `2` for a digest, `3` for a TOML document, `4` for a TOML error, `5` for a failure, `6` for captures with match numbers, `7` for an error report, `8` for the response of an adapter |
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

The S-expression leaves out a `MISSING` node whose type is hidden,
which tree-sitter's own `to_sexp` prints.

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

### A failure, when kind is 5

The buffer holds one record: a code, a u32, and then the fields of
that code.

| code | failure | fields after the code |
|---|---|---|
| 0 | an internal fault of the bridge, or a fault of its caller | the message, u32 + bytes |
| 1 | tree-sitter does not load the grammar | the kind, a u32: `0` the wasm does not parse, `1` it does not compile, `2` its instance does not start, `3` any other cause; the message, u32 + bytes |
| 2 | the ABI version of the grammar is outside 13 to 15 | the version, a u32 |
| 3 | the parser gave no tree | none |
| 4 | the source text is 2^32 bytes or more | none |
| 5 | tree-sitter does not compile the query | the kind, a u32: `0` syntax, `1` node type, `2` field, `3` capture, `4` predicate, `5` structure, `6` language; the row, the column, and the byte offset, three u32 fields; the message, u32 + bytes |
| 6 | a pattern holds a predicate outside the ten above, or a directive | the operator without its `#`, u32 + bytes; the index of the pattern, its first byte, its row, and its column in bytes, four u32 fields |
| 7 | the query and the tree come from different languages | none |
| 8 | the module is not a valid adapter | the cause, a u32, and then a count and that many strings, each u32 + bytes; see below |
| 9 | the adapter ran out of fuel | none |
| 10 | the adapter trapped, or its instance did not start | the message, u32 + bytes |
| 11 | the adapter asked for more memory than its limit | the size in bytes of all its memories that the bridge refused, an unsigned 64-bit integer, little-endian |
| 12 | `sinter_alloc` gave 0, or a range outside `memory` | the call, a u32: `0` for the request, `1` for the report; the address and the length, two u32 fields; the size of `memory` in bytes, an unsigned 64-bit integer |
| 13 | the response lies outside `memory` | the address and the length, two u32 fields; the size of `memory` in bytes, an unsigned 64-bit integer |

The cause of code 8, and its strings:

| cause | meaning | strings |
|---|---|---|
| 0 | wasmtime does not compile the module | one: the message of wasmtime |
| 1 | the module imports something | one for each import: the module and the name of the import, joined by `.` |
| 2 | the module lacks `memory` or one of the four functions | one: the name of the export |
| 3 | an export has the wrong kind or the wrong type | one: the name of the export |

The row and the column of code 5 count from 0. For the kind
predicate, tree-sitter gives the row where the pattern starts, and the
column and the offset 0. When a pattern holds more than one operator
of code 6, the failure names one of them.

### A capture record, when kind is 6

The buffer holds one record per capture of one query over one tree,
in the order of the matches, and in each match in the order of its
captures. Each record holds eight integers, and then three strings.

| field | type | meaning |
|---|---|---|
| match | u32 | the number of the match, from 0 |
| pattern | u32 | the index of the pattern in the query, from 0 |
| sbyte | u32 | the start of the node, a byte offset from 0 |
| ebyte | u32 | the end of the node, exclusive, a byte offset |
| srow | u32 | the start row of the node, from 0 |
| scol | u32 | the start column of the node, in bytes, from 0 |
| erow | u32 | the end row of the node, from 0 |
| ecol | u32 | the end column of the node, in bytes, exclusive |
| name | u32 + bytes | the capture name, without the `@` |
| type | u32 + bytes | the type of the node, for example `string` |
| text | u32 + bytes | the bytes of the source that the node covers |

The bridge numbers the matches that hold at least one capture, from 0
and with no gap, in the order in which tree-sitter's query cursor
gives them. That cursor gives a match when the match ends, so the
numbers do not follow the start of the matches. The text of a capture
is any bytes: the source text can be any bytes.

### An error report, when kind is 7

The buffer holds one record. A **node** in the record is six u32
fields and a string: sbyte, ebyte, srow, scol, erow, and ecol, as in a
capture record, and then the type of the node, u32 + bytes.

The **error flag** of a node is set when the node, or a node below it,
is an `ERROR` node or a `MISSING` node. A **lowest error node** is a
node whose error flag is set, when no child of the node has its error
flag set. A `MISSING` node whose type is hidden is no child here, so
a lowest error node can stand near such a node.

| field | type | meaning |
|---|---|---|
| flag | u32 | `1` when the error flag of the root node is set, else `0` |
| count | u32 | the number of error nodes that follow |
| error nodes | count × (u32 + node) | each `ERROR` node and each `MISSING` node that no `ERROR` node holds, in the order of the text. The u32 before each node is `0` for an `ERROR` node and `1` for a `MISSING` node. The type of a `MISSING` node is the type of the node that is missing |
| lowest | u32 | `1` when a node follows, else `0` |
| node | a node | the first lowest error node in the order of the text; present when the flag is `1` |

### An adapter response, when kind is 8

The buffer holds one record: the bytes of the response, u32 + bytes.
The bridge does not read them, and they need not be UTF-8.

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
