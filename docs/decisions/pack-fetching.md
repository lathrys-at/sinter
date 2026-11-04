<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Download a pack with curl and read its archive inside Sinter
@decision pack-fetching
@cites pack-delivery
@cites rust-bridge
Sinter downloads the archive of a pack with a curl subprocess, reads the archive inside the tool, computes the pack hash from the entries in memory, and writes the files only when the hash matches.

## Context

`sinter pack add` and `sinter pack fetch` download an archive from the
packs repository and turn it into a folder in the cache. The archive is
input from the network. Tools that do the same job, among them Cargo,
rustup, opam, Go, Nix, uv, and Homebrew, all check a hash before the
files reach their place of use. Since 2024, many of them have moved to
a reader inside the tool that accepts only regular files and folders.
Their bugs cluster in links, path forms, and archives that two readers
read in different ways. Go computes a hash of the files from the
entries of the archive before it writes any file, as Sinter's pack hash
does.

## Decision

- A curl subprocess downloads the archive to a temporary file, with
  flags that allow only `https`, limit the redirects, the size, and the
  time, and turn off the user's curl configuration. Sinter also checks
  the size of the file itself.
- The bridge only inflates the gzip stream (crate `flate2`) and decodes
  the raw ustar entries. OCaml applies every rule and every limit of
  `spec/packs.md` section 12.1.
- Sinter computes the pack hash from the entries in memory. Only when
  it matches does Sinter write the files, into a new temporary folder,
  which it then renames into the cache.
- The archive accepts regular files and folders only. Sinter refuses
  PAX and GNU headers and every other entry type, and a folder with no
  file below it.
- The index holds no hash of the archive. The pack hash is the only
  hash that Sinter trusts.

## Alternatives considered

- **curl, and the `tar` crate unpacks the archive into a folder.** Not
  chosen: the crate's unpack step decides alone what reaches the disk,
  and the comparable tools found their bugs in that step.
- **An HTTP and TLS stack in OCaml, with `ocaml-tar` and
  `decompress`.** Not chosen: it adds three dependencies, and that
  `tar` reader turns an unknown entry type into a regular file and has
  no limit on what it reads.
- **curl, and the system `tar` unpacks into an empty folder, which
  Sinter then walks and hashes.** Not chosen: no comparable tool hands
  unchecked bytes to the system `tar`. GNU and BSD `tar` differ, they
  create links before Sinter can check them, and they have no limit on
  size.
- **A shell program, bundled with Sinter and run with `/bin/sh`, that
  calls curl and the system `tar`.** Not chosen: it can be tested on
  its own, but it keeps every problem of the system `tar` and adds
  shell quoting and one more language.
- **A hash of the archive in the index.** Not chosen for now: the pack
  hash already decides what Sinter trusts, and Sinter computes it
  before it writes a file.

## Consequences

The bridge gains the crate `flate2`, and the step "Fetch language
packs" gains `bridge/**` and `THIRD_PARTY.md` in its scope. Sinter
needs curl at run time. The rules of the archive live in OCaml, where
the mutation pass reaches them. The release job of the packs repository
must write archives in the ustar form only.
