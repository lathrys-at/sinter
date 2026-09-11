<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# License the code under Apache-2.0 and the specifications under CC-BY-4.0
@decision licensing
The code uses Apache-2.0, the specifications and documentation use CC-BY-4.0 with a statement that implementing the formats needs no license, and contributions come in under a DCO.

## Context

Sinter is infrastructure: a tool that other projects adopt and that
CI runs. Its four specifications are formats that other tools should
implement. Its language packs redistribute compiled tree-sitter
grammars, each under that grammar's own license. Contributions come
from people and from coding agents, and the project must know who
stands behind each commit.

## Decision

- The tool source, the core library, and the CI and hook integration
  use Apache-2.0. The LICENSE file holds the full text. Apache-2.0
  has an explicit patent grant and a termination clause.
- The specifications and the design notes use CC-BY-4.0. The
  LICENSE-SPEC file holds the text, with a preamble: anyone can
  implement the formats in any software under any license, with no
  permission from and no obligation to The Sinter Authors beyond
  attribution of the specification text.
- Files that a language pack authors (queries, descriptor, fixtures)
  use Apache-2.0. A compiled grammar keeps its upstream license,
  verbatim, and the pack records the upstream repository and commit.
- Contributions come in under the same license as the file they
  change (inbound = outbound), certified by a Developer Certificate
  of Origin sign-off on every commit. There is no Contributor License
  Agreement.
- The repository follows the REUSE specification: an SPDX header in
  every source and specification file, and `REUSE.toml` for the
  rest. CI checks the sign-off, REUSE compliance, the third-party
  manifest, and the absence of GPL, AGPL, SSPL, and unknown
  licenses among the dependencies. LGPL is allowed only for the OCaml
  runtime, under its linking exception.

The copyright line everywhere is `Copyright <year> The Sinter
Authors`.

## Alternatives considered

- **A Contributor License Agreement** — rejected. Apache-2.0 section 5
  already covers the grant for contributions, and a CLA costs
  contributors time and trust.
- **A copyleft license, such as GPL or AGPL** — rejected. Copyleft
  blocks adoption as infrastructure and conflicts with redistributing
  grammars under their own permissive licenses.
- **Dual licensing or source-available terms** — not considered. The
  licensing brief puts them out of scope; a request for them is a
  decision for the maintainers.

## Consequences

Every new file needs the right SPDX header, and `reuse lint` fails
the build when one is missing. `THIRD_PARTY.md` lists every
dependency that ships in the binary, and CI rejects a forbidden
license there. A pack whose grammar license is not on the allowlist
needs a documented exception. Nobody copies GPL code into the
repository.
