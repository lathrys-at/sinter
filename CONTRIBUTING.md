# Contributing to Sinter

## Licensing of contributions

Sinter uses two licenses:

- The code is licensed under Apache-2.0. See the LICENSE file.
- The specifications and the documentation are licensed under CC-BY-4.0.
  See the LICENSE-SPEC file.

When you contribute, you agree to one condition: your contribution uses
the same license as the file that it changes. This model is called
"inbound = outbound". We do not use a Contributor License Agreement (CLA).

## Developer Certificate of Origin

You must sign off every commit. Use `git commit -s`. This command adds a
`Signed-off-by:` line to the commit message. The line certifies that your
contribution satisfies the Developer Certificate of Origin. The DCO file
in this repository contains the full text. CI rejects commits that have
no sign-off.

## Changes written by agents

Coding agents write much of this codebase. That is expected and welcome.
The human who runs the agent signs off the commit. That human is the
contributor of record. When an agent wrote a large part of a change, add
a line to the commit message that names the agent. Example:
`Assisted-by: Claude Code`. This line keeps the record of authorship in
the git history. Do not sign off code that you did not review.

## Third-party code

Do not copy code from other projects, unless both conditions below are
true:

1. The license of the code is compatible with Apache-2.0.
2. You add the code to THIRD_PARTY.md.

Never copy GPL or AGPL code into this repository.
