# Sinter v0.1
@plan sinter-v0.1
@scope spec/**, docs/**, CLAUDE.md, README.md, CONTRIBUTING.md, THIRD_PARTY.md, REUSE.toml, LICENSES/**, lib/**, bin/**, bridge/**, test/**, dune-project, sinter.opam, sinter.opam.locked, .github/workflows/**, .plans/**
Deliver the first useful version of Sinter: the tag graph of a
repository, checked with test evidence. It reads markdown with a
built-in pack and TypeScript, Rust, and OCaml with fetched packs.
`sinter scan` prints the facts; `sinter check` reports findings on a
tree or a diff, as text, JSON, or SARIF; `sinter evidence import` reads
JUnit XML.

## Write the manifest specification
@scope spec/**, docs/versioning.md, CLAUDE.md
Write `spec/manifest.md`, the fifth specification: the file
`sinter.toml`, its tables and keys, the rule files, and the errors of
a manifest that does not read.

## Correct the specifications
@scope spec/**, docs/design-notes.md
Bring the specifications in line with the rulings of 2026-10-03 and
2026-10-04: the slug pattern, a slug declared again after a deletion,
one meaning for each word, declarations in markdown list items,
markdown sections that cite without a declaration, and `orphan` for a
citation without the source it needs. State the principle that every
state Sinter reports can be read and checked in the repository's text.

## Record the decisions
@scope docs/decisions/**
@decision toml-reader
@decision pack-delivery
@decision rule-files
@decision sha256
@decision tags-not-titles
@decision plans-span-branches
@decision plan-ids
Write the records of the rulings that shape the project.

## Rename the request tag and raise the compiler bound
@scope bin/**, lib/request.ml, lib/request.mli, test/**, dune-project, sinter.opam
Call the caller's id of a serve request a request id. Declare
`ocaml >= 5.5`, the compiler that CI tests.

## Add the git module
@scope lib/**, test/**
Read the file set, the target branch, the merge base, the files of the
base tree, and the diff hunks from git, with typed errors. Compute the
tree key: the git tree hash of the working tree as it is on disk.

## Add the fixture harness
@scope test/**
Run test cases from folders and compare their output byte for byte
with expected files. Build a diff case as a temporary git repository
from a base folder and a tree folder.

## Compute SHA-256 through the bridge
@scope bridge/**, lib/**, test/**
Hash a string with the `sha2` crate that the bridge already links,
behind an interface in `lib/`.

## Read the manifest
@scope bridge/**, lib/**, test/**, THIRD_PARTY.md, REUSE.toml
Parse `sinter.toml` and the front matter of rule files with
`toml_edit` through the bridge, and check every key against the
manifest specification.

## Write the pack specification
@scope spec/**
Write `spec/packs.md`: the query files and their captures, the
descriptor, the comment sigils, the joining of line comments, the
attachment of a comment, a parse failure, and the test ID strategies.

## Build bridge version 2
@scope bridge/**, lib/**, bin/**, test/**, docs/decisions/**
Keep parsed trees and compiled queries as handles, run one query over
one tree, number the matches, count the errors of a tree from its
root, and return typed errors. Split `lib/parse.ml` by its jobs.

## Scan and check markdown
@scope lib/**, bin/**, test/**
Build the markdown pack into the tool. Add `sinter scan` and
`sinter check` for the static finding classes, in tree mode and diff
mode, and run them on Sinter itself.

## Fetch language packs
@scope lib/**, bin/**, test/**, docs/**
Fetch a pack from the packs repository with `sinter pack add`, record
it in `sinter.lock`, and keep it in a user cache keyed by its hash.

## Read TypeScript, Rust, and OCaml
@scope lib/**, test/**
Read the packs for TypeScript, Rust, and OCaml, and capture the tests
that each one declares.

## Import test evidence
@scope lib/**, bin/**, test/**, dune-project, sinter.opam, sinter.opam.locked, THIRD_PARTY.md, docs/decisions/**
Read JUnit XML with `sinter evidence import`, bind each result to its
test by the tree key, and report `never-ran` and `failed`. Write JUnit
XML from Sinter's own test suite.

## Write SARIF
@scope lib/**, bin/**, test/**, docs/decisions/**
Write the findings of `sinter check` as SARIF.

## Release the binaries
@scope .github/workflows/**, README.md, docs/**, THIRD_PARTY.md, REUSE.toml, LICENSES/**
Build release binaries for Linux x86-64 and macOS arm64 on a version
tag, with the notices of every bundled crate and grammar, and publish
them on GitHub Releases with an action that installs them.
