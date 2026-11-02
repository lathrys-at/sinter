<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Check a pack with `sinter pack verify`
@decision pack-verify
@cites pack-delivery
The command `sinter pack verify` checks a pack folder by the rules that Sinter applies when it loads a pack, so that the packs repository checks its packs with Sinter itself.

## Context

The packs repository must check every pack before a release: the
descriptor, the files, the grammars, the queries, and the adapters.
Sinter already applies these rules when it loads a pack
(`spec/packs.md` section 3.6). A second program that checks the same
rules can disagree with Sinter.

## Decision

- `spec/packs.md` specifies `sinter pack verify <folder>...`, which
  checks each folder by the rules of section 3.6 that need no
  repository, and `sinter pack verify --all`, which checks every pack
  of the lock file.
- The step "Fetch language packs" builds the command.
- Until then, the CI of the packs repository checks only what Sinter
  does not check, in shell. It does not copy the rules of section 3.6.

## Alternatives considered

- **A checker in Python in the packs repository, for the time before
  the command exists.** Not chosen: it is a second program for the
  same rules, and the Python library `tomllib` reads TOML 1.0, not the
  TOML 1.1.0 that the descriptor uses.

## Consequences

The rules of a pack live in one program. The packs repository cannot
check the rules of section 3.6 before "Fetch language packs" is done.
