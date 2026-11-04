<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Check the pack hash of a cached pack each time it loads
@decision pack-load-check
@cites pack-fetching
Every command that loads a fetched pack computes its pack hash again from the files in the cache and stops when the hash differs from the lock file.

## Context

The cache of packs is a folder of the user, outside every repository.
Any program of the user can change it. Comparable tools have had
advisories when they trusted a cache that was checked only once, among
them opam (OSEC-2023-01) and Homebrew.

## Decision

Each command that loads a fetched pack computes the pack hash of the
files in the cache and compares it with the hash of the lock file.
When the two differ, the command stops with exit code 3
(`pack-mismatch`), and the message says to run `sinter pack fetch`.
The step "Fetch language packs" measures the cost with the benchmark.

## Alternatives considered

- **Check a pack only when it is fetched, and keep the cache
  read-only.** Not chosen: a read-only mode stops mistakes, not a
  program that changes the mode first, and the stricter rule costs one
  hash of a few megabytes for each command.

## Consequences

A changed file in the cache never reaches a scan. Each command pays
for one hash of each pack it loads.
