<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Give the settings of the manifest and the gates plain names
@decision manifest-names
@cites plain-names
@cites ste-adoption
The settings of the manifest and the gates take names with one meaning each, two settings with one effect become one, and a ref becomes an external id.

## Context

Every user writes a manifest before Sinter reports anything, so its
settings are the first words of Sinter that a person types. A review
of all 16 settings found three problems. Some names had a second
meaning in Sinter: "target" named the target branch, the tag target,
and the gate `target`; "ref" named a tag target outside the repository
and also a git ref, in a file that names git refs; `spec` read as the
version of the user's own specification. Some names were coined or
were jargon: `ambient`, `rollout-cap`, `harness-markers`, and
`coverage-attribution`, whose class became `unmeasured`
([plain-names](plain-names.md)). And two settings, `plan.ambient` and
`plan.shared`, had one effect: the rule of `unplanned-change` subtracts
both, and nothing else reads either.

## Decision

| before | after |
|---|---|
| `spec` | `sinter-spec` |
| `target` | `default-branch` |
| `scan.refs.<ns>` | `scan.namespaces.<ns>` |
| `scan.packs.<name>.runners` and `scan.packs.<name>.<runner>.<key>` | `scan.packs.<name>.runners.<runner>.<key>` |
| `check.rollout-cap` | `check.warn-only` |
| `plan.ambient` and `plan.shared` | `plan.exempt` |
| `ledger.harness-markers` | `ledger.agent-markers` |
| `evidence.coverage-attribution` | `evidence.test-coverage` |
| the gates `turn`, `merge`, `target` | `turn`, `review`, `merged` |

- The target branch is the **default branch**, the term of GitHub,
  GitLab, and git's `init.defaultBranch`.
- A tag target outside the repository, `<ns>/<id>`, is an **external
  id**. The JSON record kind `ref` becomes `external`. "Ref" means only
  a git ref.
- A test runner is on when its table under `runners` exists, for
  example `runners.vitest = {}`. No runner name is reserved.
- `plan.exempt` holds the built-in members of `plan.ambient`: each
  plan file, the manifest, and `sinter.lock`.
- The specifications say "the coverage of each test" and "the coverage
  of the whole run", and "a tree with no evidence" where they said "an
  unmeasured tree".
- `sinter init` still writes `warn-only = true`, and the default stays
  `false`.
- `check.tiers` and `plan.locations` keep their names.

## Alternatives considered

- **`main-branch` for `target`.** Not chosen: it reads oddly when the
  branch is `trunk` or `develop`.
- **`scan.namespaces` with the term "ref" kept.** Not chosen: the
  messages and the JSON would still say "ref" beside git refs.
- **`requires-sinter` or `format-version` for `spec`.** Not chosen:
  the first reads as a version of the program, and the second as a
  version of the file format only.
- **Two settings with `ambient` renamed, or a difference designed
  between them.** Not chosen: users would choose between two settings
  that have one effect; a real difference can split the setting later.
- **`built-in-blocks = false` for `rollout-cap = true`.** Not chosen:
  more exact, but inverted and harder to read.
- **"level" or "severity" for "tier".** Not chosen: "level" is the
  level of a markdown heading, which ends a requirement's text, and a
  tier changes per gate, which "severity" does not suggest.
- **`merged` alone for `target`, or `edit` for `turn`.** Not chosen:
  `merge` and `merged` differ by one letter and mean before and after;
  `turn` names a real moment in the work of an agent.
- **A list of runners with the settings under `runner-settings`.** Not
  chosen: two places for one runner remain.
- **`per-test-coverage`, or naming the setting after the class.** The
  first was shortened; the second reads backwards.
- **`agent-variables` for `harness-markers`.** Not chosen: it reads as
  variables passed to an agent.
- **`homes` for `locations`, or a table of per-kind settings.** Not
  chosen: a metaphor, and a table that no part of Sinter owns.

## Consequences

The names are part of every manifest, the CLI option `--gate`, and the
JSON form, so the change breaks every reader of the old names. No
repository outside Sinter used them. Sinter's own manifest and CI step
change with the specifications. The records written before this one
keep the old names, because they record what was decided then.
