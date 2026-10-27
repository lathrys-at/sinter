# Sinter v0.1
@plan sinter-v0.1
@scope spec/**, docs/**, CLAUDE.md, README.md, CONTRIBUTING.md, THIRD_PARTY.md, REUSE.toml, LICENSES/**, lib/**, bin/**, bridge/**, test/**, bench/**, dune-project, sinter.opam, sinter.opam.locked, sinter.toml, .github/workflows/**, .plans/**, plugins/**, .claude-plugin/**
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
@scope spec/**, docs/decisions/**
@decision runner-adapters
Write `spec/packs.md`: the query files and their captures, the
descriptor, the comment sigils, the joining of line comments, the
attachment of a comment, a parse failure, the interface of a runner
adapter, and the default matcher. Add the runners of a pack to the
manifest specification.

## Build bridge version 2
@scope bridge/**, lib/**, bin/**, test/**, docs/decisions/**
Keep parsed trees and compiled queries as handles, run one query over
one tree, number the matches, count the errors of a tree from its
root, and return typed errors. Call a function of a wasm module with
bytes in and out, under limits of time and memory, for runner
adapters. Split `lib/parse.ml` by its jobs.

## Close the gaps of the markdown scan
@scope spec/**
State in the specifications what the scan of markdown and the check
of a tree need and the specifications do not yet say: the structure
that markdown gives, blocks and extents, strings and paths, and the
ids and rules of the findings in tree mode.

## Scan markdown
@scope lib/**, bin/**, test/**, THIRD_PARTY.md, REUSE.toml
Build the markdown pack into the tool, with the markdown grammar
embedded in the binary. Take the facts of markdown files, and print
them with `sinter scan`.

## Check a tree
@scope lib/**, bin/**, test/**
Add `sinter check` for the finding classes that the facts of markdown,
the manifest, and git give, in tree mode, with tiers, gates, and exit
codes, as text and as JSON.

## Cite the successor of a superseded item
@scope spec/**, lib/**, test/**, docs/**, CONTRIBUTING.md, plugins/**, .claude-plugin/**
@decision supersession-chains
@decision cite-the-successor
Keep a `@supersedes` edge live when its source is itself superseded,
so that a chain of records retires each record before its end. Give a
citation of a superseded item a fix that names the item that
supersedes it, and let no `@ack` discharge that finding. Tell authors,
in the decision skill and in `CONTRIBUTING.md`, to move such a
citation in the change that supersedes the item.

## Move to tree-sitter 0.26 and wasmtime 36
@scope bridge/**, lib/**, test/**, docs/**, CONTRIBUTING.md, THIRD_PARTY.md
@decision current-dependencies
Move the bridge from tree-sitter 0.25.10 and wasmtime 29.0.1 to
tree-sitter 0.26.13 and wasmtime 36.0.19. The store of the grammars
then stops growing with each parse, and the bridge leaves two critical
security advisories of wasmtime 29. Keep the refusal of an adapter
with a 64-bit memory. Test that a query that names a supertype with a
subtype runs.

## Limit comments and pull request descriptions
@scope lib/**, bin/**, bridge/**, test/**, .github/workflows/**, dune-project, sinter.toml, REUSE.toml, docs/decisions/**, CONTRIBUTING.md
@decision code-comments
@decision pull-request-descriptions
Permit a comment only when Sinter reads it, as a tag block and its
prose, or when it is an API comment, a license header, or other text
that the community of the language expects. Such a comment states
what the code does, not why. Remove every other comment, in every
language of the repository. Limit a pull request description to the
plan step or the issue that the change carries out, and the records
or the rules that it adds. Change the rules in `CONTRIBUTING.md` to
match.

## Measure and improve the performance of scan and check
@scope lib/**, bin/**, bridge/**, test/**, bench/**, docs/**, .github/workflows/**, CONTRIBUTING.md
Add a benchmark that measures the time and the peak memory of
`sinter scan` and `sinter check` on Sinter itself and on generated
trees of 1,000, 10,000, and 100,000 declarations. Profile them, fix the
largest costs, and record a baseline and budgets that later steps
keep.

## Move to tree-sitter 0.27 and wasmtime 48
@scope bridge/**, lib/**, test/**, spec/**, docs/**, CONTRIBUTING.md, THIRD_PARTY.md, .github/workflows/**
Move the bridge to the first release of tree-sitter 0.27 or later that
reads the supertypes of a WebAssembly grammar correctly, with
wasmtime 48, and move the pinned Rust version to the version that
wasmtime 48 needs. Keep a limit of fuel that a call exceeds on every
machine or on none (`spec/packs.md` section 10.2). Measure the
baseline of the performance step again.

## Close the gaps of diff mode
@scope spec/**, docs/design-notes.md, docs/roadmap.md
State in the specifications what diff mode needs and the
specifications do not yet say: the options and the hunks of the diff,
the ids that the subtraction compares, the rules of `renamed` and of
mechanical repairs, the classes that compare with the base, and the
section number that a heading can carry.

## Check a diff
@scope lib/**, bin/**, test/**, bench/**
Read the facts of the base from git, and add diff mode to
`sinter check`: the findings that the diff adds, `rev-owed`, and
`renamed`.

## Report unmapped work
@scope lib/**, bin/**, test/**, bench/**
Report `unmapped-work`: each hunk of the diff that no open plan step,
rule, ambient path, or shared path covers.

## Report changes to the configuration
@scope lib/**, bin/**, test/**, bench/**
Report `config-changed`: each setting of the manifest that differs
from the base.

## Check Sinter with Sinter
@scope sinter.toml, .github/workflows/**, spec/**, docs/**, .plans/**
Add the manifest of Sinter, fix the findings that Sinter reports on
itself, and run `sinter check` on every pull request in CI.

## Fetch language packs
@scope lib/**, bin/**, test/**, docs/**
Fetch a pack, with its grammars, queries, and runner adapters, from
the packs repository with `sinter pack add`, record it in
`sinter.lock`, and keep it in a user cache keyed by its hash.

## Read TypeScript, Rust, and OCaml
@scope lib/**, test/**
Read the packs for TypeScript, Rust, and OCaml, and capture the tests
that each one declares.

## Import test evidence
@scope lib/**, bin/**, test/**, dune-project, sinter.opam, sinter.opam.locked, THIRD_PARTY.md, docs/decisions/**
Read test reports with `sinter evidence import` through the runner
adapters of the packs, bind each result to its test by the tree key,
and report `never-ran` and `failed`. Write JUnit XML from Sinter's own
test suite.

## Write SARIF
@scope lib/**, bin/**, test/**, docs/decisions/**
Write the findings of `sinter check` as SARIF.

## Release the binaries
@scope .github/workflows/**, README.md, docs/**, THIRD_PARTY.md, REUSE.toml, LICENSES/**
Build release binaries for Linux x86-64 and macOS arm64 on a version
tag, with the notices of every bundled crate and grammar, and publish
them on GitHub Releases with an action that installs them.
