<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Build in only the markdown pack; fetch every other pack
@decision pack-delivery
@cites parser-bridge
The markdown pack is built into the tool, and every other language pack is fetched from a packs repository, checked against its SHA-256 hash, and recorded in a lock file.

## Context

A language pack is a grammar and the queries that tell Sinter where
tags stand in one language. The first useful version needs markdown,
TypeScript, and Rust, and OCaml for Sinter's own code. Markdown is part
of Sinter's core: plans, decision records, and rule files are
markdown, and the vocabulary specification defines how Sinter reads
it. A change to a pack can change the extent hash of every block in
its language, so each repository must fix the exact pack it reads.

## Decision

- The markdown pack is built into the binary, and it has no version of
  its own: it changes with the tool.
- Every other language is a pack from the start, also in the first
  useful version:
  - A packs repository publishes each pack with its SHA-256 hash.
  - `sinter pack add` fetches a pack, checks the hash, records the
    pack in `sinter.lock`, and keeps it in a user cache keyed by the
    hash. It can also take a pack from a local path.
  - CI caches the packs.
- Trust comes from the hash in the lock file. Signed packs can come
  later.
- `spec/packs.md` holds the format of a pack and of the lock file.

## Alternatives considered

- **Build the packs of the first useful version into the binary**
  (markdown, TypeScript, and Rust; about 3 MB), and build the packs
  repository later. Not chosen: a new pack version would need a tool
  release, and every language but markdown would later move from
  built-in to fetched, which changes how every adopting repository
  works.
- **Keep packs as files in each user's repository.** Not chosen: it
  puts several megabytes of binary files into every adopting
  repository.

## Consequences

The packs repository, `sinter pack add`, and `sinter.lock` move before
the first useful version, so that version costs more work. In return,
a pack can change without a tool release, the binary stays small, and
each repository fixes its packs by hash from the first day. Only
markdown changes together with the tool.
