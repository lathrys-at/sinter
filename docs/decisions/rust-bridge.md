<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Hold trees, queries, and adapters as handles of the Rust bridge
@decision rust-bridge
@supersedes parser-bridge v2
@cites implementation-language
@cites runner-adapters
The Rust bridge gives OCaml a handle to each grammar, parse tree, compiled query, and runner adapter, runs adapters in a second wasmtime engine that counts fuel, and keeps the other choices of `parser-bridge`.

## Context

Version 1 of the bridge, in the record `parser-bridge`, parsed a text
and ran a query over it in one call, and its engine owned every
grammar. The scanner must compile a query once and run it over many
files, and must find the parse errors of a tree. Runner adapters must
run under limits of time and memory, as `spec/packs.md` section 10
says. In wasmtime, fuel (a counter that falls as WebAssembly code runs
and stops the code at zero) is a setting of a whole engine.
tree-sitter counts the references to a grammar, so a tree or a query
stays valid without the parser that made it.

## Decision

- A handle is an OCaml value that owns one Rust object. The bridge
  gives a handle for each grammar, parse tree, compiled query, and
  adapter. A tree handle holds a copy of its text.
- Each handle has `close`, which frees the object at once, and a
  finalizer, which frees it when the garbage collector finds that
  nothing uses the handle. A use after `close` raises
  `Invalid_argument`.
- The bridge numbers the matches of a query itself, and refuses a
  query over a tree of another grammar.
- A query may use only the ten predicates of `spec/packs.md` section
  4.1. Any other predicate or directive stops the compilation, in
  `sinter parse` too.
- The bridge parses the bytes that it gets. The code that reads files
  for packs adds the final line feed of `spec/packs.md` section 5.1.
- Each failure that a caller can act on has an error value of its own.
  One exception stays, for faults inside the bridge.
- Adapters run in a second engine, with fuel, made from a copy of the
  settings of the grammar engine. The bridge compiles an adapter once
  and makes a new instance for each call. It refuses each growth of
  memory past the limit of a call, and records the size it refused.
- Tests build adapters as WebAssembly bytes in OCaml.
- The other choices of `parser-bridge` stay: the crate in `bridge/`,
  linked statically; C stubs written by hand that copy each result
  into OCaml; one build directory for each checkout, outside
  `_build`; wasmtime's cache of compiled modules; the pinned Rust
  toolchain; and no Sinter vocabulary in the bridge. That record gives
  their alternatives and their measurements.

## Alternatives considered

- **A finalizer alone.** Not chosen: memory outside the OCaml heap
  would be freed at a time that no caller knows, inside the collector.
- **`close` alone.** Not chosen: a lost handle would leak.
- **One engine with fuel.** Not possible: the start code of
  tree-sitter ran out of fuel, and no grammar loaded.
- **One engine without fuel.** Not chosen: an adapter could run with
  no limit of time.
- **Epoch interruption, a signal that stops code after a time, in
  place of fuel.** Not chosen: it is also a setting of a whole engine,
  it also stopped tree-sitter, and the specification asks for fuel.
- **wasmtime's own memory limit, `StoreLimits`.** Not chosen: a
  refused growth reaches the adapter as -1, or fails the call with
  only a message.
- **tree-sitter's match id.** Not chosen: it has gaps where a
  predicate rejects a match.
- **The final line feed in the bridge.** Not chosen: the output of
  `sinter parse` and `sinter serve` would change.
- **A test adapter built from Rust source, and checked in or built
  in each build.** Not chosen: to build it, or to check a checked-in
  file against its source, needs the `wasm32` target of the pinned
  Rust version, which the toolchain does not install.
- **Test adapters in WebAssembly text, or built with the Rust crate
  `wasm-encoder`.** Not chosen: each adds a dependency, and the tests
  of the OCaml interface need their modules in OCaml.

## Consequences

Grammars still run without limits: tree-sitter makes the wasmtime
store of a grammar, the state of its running code, and sets no limit
on it. A caller must close each handle or leave it to the collector.
Tests write WebAssembly instructions by hand.

Measured on 2026-10-22 on an Apple M5, with tree-sitter 0.25.10 and
wasmtime 29.0.1: the second engine costs under 0.3 ms and no new
thread; an adapter of 15 to 116 KB compiles in 13 to 92 ms, or under
1 ms from the cache; a new instance costs 4 µs; fuel adds about 20
percent to the time of a call; a JUnit adapter used about 250 units of
fuel and 20 bytes of memory for each byte of a report.
