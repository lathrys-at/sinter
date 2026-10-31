<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Give the classes of incomplete work no tier at the gate turn
@decision incompleteness-at-turn
The classes `untraced`, `unmet-promise`, and `awaiting-approval` take no tier at the gate `turn`, so the turn report never shows incomplete work.

## Context

The turn report, `sinter check --diff --gate turn`, runs when an agent
hands back its work. The design notes say that its tier `block` marks
violations, never incomplete work: an agent that cannot honestly hand
back "not done yet" learns to fake that it is done. The algebra said
that `untraced` never blocks a turn end. But the manifest let a
project write `check.tiers.turn.untraced = "block"`, so the
specifications contradicted each other.

Sinter never holds a turn. It prints findings and an exit code. A
hook of the harness, a lead agent, or a person reads the exit code and
decides whether the turn can end.

## Decision

`untraced`, `unmet-promise`, and `awaiting-approval` take no tier at
the gate `turn` (`—` in section 9 of the algebra). A tier for one of
them at `turn` is the existing manifest error for a class that takes
no tier at a gate. `sinter status` reports incomplete work. A harness
that holds a turn until the work is complete reads `sinter status` or
the JSON output, and its own configuration decides.

## Alternatives considered

- **The three classes act as every other class, `off` at `turn` by
  default.** Not chosen: a manifest could then make the turn report
  fail on incomplete work, and the principle of the design notes would
  become a default.
- **`block` is an error at `turn` for the three classes, and `warn`
  stays allowed.** Not chosen: it adds a rule of its own to the
  manifest for three classes, where the rule that a class takes no
  tier at a gate already exists.

## Consequences

A repository can no longer show incomplete work in the turn report,
not even as a warning. Whether to hold a turn until the work is
complete becomes a setting of the harness, not of Sinter. A manifest
that writes a tier at `turn` for one of the three classes stops with
exit code 3.
