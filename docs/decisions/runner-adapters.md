<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Let language packs carry runner adapters
@decision runner-adapters
@cites pack-delivery
@cites tags-not-titles
A language pack can carry runner adapters: sandboxed WebAssembly modules that bind a test runner's results to the tests in the source, built, versioned, and released with the pack, while the tool keeps the meaning of every result.

## Context

Sinter binds a test result to the test that a `@verifies` tag marks.
Each test runner names its tests in its own way, several runners let a
project change the naming, and a JUnit XML report does not say which
program wrote it. A study of fifteen runners found that most can be
matched with a small amount of data per runner, but some need code (Go
import paths, Rust module paths and test binaries, the way RSpec joins
descriptions), and runners change their naming between versions.
Runner knowledge in the tool would tie every such fix to a release of
the tool.

## Decision

- A language pack can carry runner adapters, one per test runner. An
  adapter is a WebAssembly module, built, versioned, and released in
  the packs repository with its pack, and fixed by hash in the lock
  file with the rest of the pack.
- An adapter runs in a sandbox: it imports nothing, so it reads no
  file, uses no network, and sees no clock, and it runs under limits
  of time and memory. Sinter calls its functions with JSON and reads
  JSON back, through a versioned interface.
- An adapter decides which result binds to which test, and gives a
  reason for each binding. It can read a runner's own report formats,
  not only JUnit XML, and it can recognise which runner wrote a report.
- The tool keeps the meaning of the results: the worst status in a
  group, a skipped test that counts as not run, `never-ran` when
  nothing binds to a test, a finding when one result binds to two
  tests, and a warning when most of a report binds to nothing. No
  adapter can make a failure pass.
- A runner without an adapter of its own uses the default adapter,
  which joins the names of a test from the source with the runner's
  separators and compares the result with the reported name.
- The manifest names the runners of each pack. A report that two
  adapters both recognise needs `--runner` on the command line.
- `spec/packs.md` holds the interface and the default adapter.

## Alternatives considered

- **ID strategies as code in the tool**, a fixed menu as the design
  notes first planned. Not chosen: every new runner, and every change
  of a runner's naming, would need a release of the tool.
- **Packs of data only, with one matcher in the tool.** Not chosen:
  some runners need code, and the knowledge still could not change
  without a release of the tool.
- **Adapters as packs of their own**, apart from the language packs.
  Not chosen for now: more units to name, fetch, and lock. It can come
  later, when one runner needs a release cycle of its own.
- **For naming the runners:** a table in the manifest that names each
  report file, and the command line alone. Not chosen: report paths
  differ between local runs and CI, and a choice on the command line
  escapes `config-changed`.

## Consequences

Packs become software: the packs repository needs a build, tests with
real reports of each runner version, and releases. Sinter needs a
stable, versioned interface for adapters, and bridge version 2 gains a
way to call a WebAssembly function under limits. Some reports lack the
information that a binding needs, such as Gradle's default names of
parameterized tests; an adapter says so instead of guessing.
