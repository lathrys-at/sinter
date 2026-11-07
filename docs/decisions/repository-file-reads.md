<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Read a repository file with no link followed and no race
@decision repository-file-reads
@cites gh/158
Sinter opens a file of the repository one path part at a time with `openat` and `O_NOFOLLOW`, through a small C function, and a manifest inside the repository that a link reaches is an error.

## Context

The content of a repository is untrusted. A review found that a pull
request can commit `sinter.toml` as a symbolic link to a file outside
the repository, and that the error then prints a line of that file in
the CI log. `spec/manifest.md` section 7.3 says that Sinter follows no
symbolic link, but it said nothing about the manifest.

Sinter checks each file when it lists the file set, and it opens the
file by its path later. Another process can change what is at the path
between the two. The `Unix` library of OCaml has neither `openat` nor
`O_NOFOLLOW`, and only these two together close this race for the
folders on the way to a file.

## Decision

- `sinter.toml` at the repository root must be a regular file. A
  symbolic link or another kind of file there is an error.
- A path given with `--manifest` that is inside the repository follows
  the same rule, for every path part below the root. A path outside
  the repository is followed, so `/dev/stdin` keeps working.
- One read function serves the manifest inside the repository, the
  files of the file set, and the source lines of a finding. It walks
  the path in OCaml, opens each part through one small C function that
  calls `openat` with `O_NOFOLLOW`, and reads through the last open
  file descriptor.

## Alternatives considered

- **Follow only a link to a regular file inside the repository** — not
  chosen. It adds an exception to section 7.3, and the base tree would
  have to resolve links too, so that both trees read one file.
- **Follow any manifest link, as before** — not chosen. This is the
  defect.
- **Check by `lstat` in OCaml, open by path, and compare the identity
  of the open file** — not chosen. It needs no C, but a process can
  swap a folder to a link and back while Sinter checks the path.
- **Change only the file set, and check only `sinter.toml`** — not
  chosen. The race stays for every other file.
- **Apply the rule only to `sinter.toml`, and always follow a path
  given with `--manifest`** — not chosen. The person chooses that path,
  but a pull request controls what is at a path inside the repository,
  so the same attack stays open for each project whose CI names such a
  path.

## Consequences

A project cannot keep its manifest behind a link in the repository. A
read costs about 30 microseconds more for each file at depth 3. The C
function is outside the reach of the mutation tests, so the walk stays
in OCaml, where they reach it. A file that becomes a link between the
listing and the read makes the command fail. Version 1 does not support
Windows, so `openat` is on every platform.
