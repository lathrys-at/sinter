<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Allow only printable ASCII in the paths of a pack
@decision pack-paths
@cites pack-fetching
Every path of a pack is printable ASCII without a backslash, with no empty, `.`, or `..` name, at most 255 bytes long, and distinct from every other path after ASCII case folding.

## Context

The pack listing of `spec/packs.md` section 2.4 has one line for each
file, in the form that `sha256sum` prints. The specification set no
rule on the bytes of a path. A path with a line feed can then forge
lines of the listing, so two different packs can give one pack hash. A
path that differs from another only in case is one file on a file
system that ignores case, such as the default on macOS.

## Decision

Section 2.3 gives each path of a pack these rules:

- each byte is printable ASCII, 0x20 to 0x7E, and is not `\`;
- no name is empty, `.`, or `..`, and the path does not start with
  `/`;
- the path has at most 255 bytes;
- no two paths are equal after ASCII case folding;
- no path of a file is also the path of a folder.

The listing keeps the form that `sha256sum` prints.

## Alternatives considered

- **The same rule, with any UTF-8 text in place of ASCII.** Not
  chosen: two forms of one accented name can be one file on one file
  system and two files on another, and case folding beyond ASCII
  differs between file systems.
- **A new form of the listing that cannot be forged, for example with
  a separator byte that no path can hold.** Not chosen: the listing
  would no longer be what `sha256sum` prints, so no common command
  could check a pack hash.

## Consequences

A pack hash names one set of files. The informative command of section
2.4 stays correct. A pack cannot hold a file whose name is not ASCII.
