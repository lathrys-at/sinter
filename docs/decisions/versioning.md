<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Version the specifications and the tool separately
@decision versioning
The four specifications share one semantic version with tags `spec/vX.Y.Z`; the tool has its own semantic version with tags `vX.Y.Z`; a development build prints the next release and the commit hash.

## Context

Formats and code change at different speeds. Other tools implement
the specifications, so they need to name the version they implement.
A development build needs an identifier that names the exact commit,
without a person editing a version string.

## Decision

The policy is in `docs/versioning.md`. In short:

- The four documents in `spec/` are one coherent set with one
  semantic version. Major changes break an existing implementation,
  minor changes are additions, patch changes are editorial.
- The `sinter` binary and its libraries have their own semantic
  version. A released tool states which specification version it
  implements.
- `sinter --version` prints the package version on an opam release
  build, the tag on a tagged commit, and otherwise the next planned
  release with a `-dev` marker and the commit hash, for example
  `v0.1.0-dev+751a66d`. A dune rule embeds `git describe` at build
  time.

The JSONL field `v` is not a specification version. It is an integer
wire-format version that increases only for an incompatible change.

## Alternatives considered

- **One version for the specifications and the tool** — rejected. A
  tool patch would bump the specifications' version with no change
  in any format.
- **One version per specification file** — rejected. The four
  documents are one coherent set, and other implementations track the
  set, not single files.
## Consequences

Two tag namespaces exist. The Claude Code plugin has its own semantic
version, and a change to a skill bumps it. The first tool release needs a `v0.1.0` tag; from then on,
git's own description names untagged builds.
