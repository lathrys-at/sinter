<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Versioning

Sinter uses semantic versioning (<https://semver.org/>) for two
separate things: the specifications and the tool. They have separate
version numbers, because formats and code change at different speeds.

## The specifications

The `spec/` directory holds four documents:

- the doctag vocabulary;
- the query algebra;
- the JSONL interchange schema;
- the approval-ledger format.

These four documents are one coherent set, and they share one version.
A release of the set is a git tag of the form `spec/vX.Y.Z`. The three
parts of the version number change for different reasons:

- **Major** increases for a change that breaks an existing
  implementation of the formats.
- **Minor** increases for an addition that existing implementations
  can ignore.
- **Patch** increases for an editorial change with no change in
  meaning.

The specifications are drafts now and have no released version. The
first release will be `spec/v1.0.0`.

The `v` field on every JSONL line ([spec/jsonl.md](../spec/jsonl.md)
section 2) is not the specification version. It is an integer
wire-format version. It increases only for an incompatible change to a
record kind's required fields or identity.

## The tool

The `sinter` binary and its libraries have their own version,
independent of the specification version. A release of the tool is a
git tag of the form `vX.Y.Z`. A released tool states which
specification version it implements.

## Development builds

`sinter --version` prints:

- for an opam release build: the package version, for example
  `v0.1.0`;
- for a build of a tagged commit: the tag;
- for any other build: the next planned release, a `-dev` marker, and
  the commit hash, for example `v0.1.0-dev+751a66d`. The suffix
  `-dirty` appears when the checkout has uncommitted changes.

The next planned release is the `base` value in
[lib/version.ml](../lib/version.ml). The commit hash comes from
`git describe`. A dune rule runs that command at build time.
