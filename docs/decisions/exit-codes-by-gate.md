<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Exit 1 only on a finding that blocks at the chosen gate
@decision exit-codes-by-gate
@supersedes exit-codes v1
Every `sinter` command keeps the same five exit codes, and code 1 now means at least one finding at tier `block` for the gate the caller named, or any finding under `--strict`.

## Context

The record `exit-codes` gave code 1 to any finding. The design gives
each finding class a tier at each gate, and a new repository starts
under the rollout cap, which lowers every tier to `warn`. Under the
old record, the first warning in a new repository made a CI job fail,
so the rollout cap had no effect where it matters most. `sinter check`
is the first command that reports findings, so the choice had to be
made before its work starts.

## Decision

- Every command uses five exit codes: 0 when the command succeeded
  and nothing blocks; 1 when it succeeded and at least one finding
  blocks; 2 when the command line or the request is wrong; 3 when the
  command could not run in this environment; 4 when the command
  refused to act.
- A finding blocks when its tier is `block` at the gate that the
  caller names with `--gate`. With `--strict`, every finding counts.
- With no `--gate`, a command reports every finding and exits 0,
  unless `--strict` is given. Each caller that gates on the result
  names its gate.
- A control line of `sinter serve` carries the same codes.
- A fault of the tool itself stays outside the five: an exception
  that no command catches gives the argument parser's code 125.

## Alternatives considered

- **Exit 1 on any finding that the command prints**, as the record
  `exit-codes` said. Not chosen: the rollout cap would then change only
  the labels of findings, and CI would fail on the first warning.
- **No `--gate` means `--gate turn`.** Not chosen: a hidden default
  lets a CI job that forgets `--gate` use the turn tiers in silence,
  and a plain run would stop listing the classes that are `off` at the
  turn. With no default, a forgotten gate shows as a job that never
  fails.

## Consequences

A repository can run Sinter in CI from the first day and read its
warnings before anything blocks. Codes 0 and 1 still both mean a
valid run, and a caller that asks "did it run" still tests for a code
above 1. Every caller that gates on the result must name its gate;
the commands that `sinter init` writes carry one.
