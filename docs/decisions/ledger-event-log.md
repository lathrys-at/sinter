<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Treat the ledger as an event log, and Sinter as a pure function of it
@decision ledger-event-log
@cites delivery-lines
Sinter is a pure function of a snapshot and one event log: the ledger is the log, each entry is an event, and every state that comes from a judgment is a fold over the entries in their order.

## Context

Sinter reads six inputs: the working tree, the base, the commit
messages of the change, the ledger, the test evidence, and the
session. The ledger already behaved like an event log: its ref moves
forward only, and a reader skips the kinds that it does not know. But
the specification called it a set of entries, ordered the entries by a
time that the writer chooses, joined the entries of two writers after
a lost push as a union with no check, and let some states read git's
commit graph. The next steps of the ledger plan are almost all states
computed from the ledger and commands that write it, so each would
otherwise decide order and replay on its own.

## Decision

- Sinter is a pure function of a snapshot and one event log. The
  snapshot is the working tree, the base, the commit messages, the
  test evidence, and the session. The log is the ledger: the sequence
  of the entries at the tip of the clone's ref, in the order of their
  `seq`.
- Each entry is an event. Every state that comes from a judgment, such
  as approved, declined, closed, delivered, or claimed, is a fold over
  the entries in that order, or over a prefix of them. No fold reads
  git's commit graph, the clock, the environment, or the network. The
  same inputs give the same output for one version of the tool.
- A command that writes the ledger reads the snapshot and the folds,
  checks, and appends one commit. After a lost push, it replays its
  entries on top of the new tip and checks each judgment again; a
  judgment whose situation changed is asked again or refused.
- The rest of Sinter is not an event log. The working tree is a
  snapshot. Git's history of the working tree is not read as events,
  as the records `delivery-marks` and `delivery-lines` decided. The
  job on the default branch reads git's history as a command, not as
  a fold.
- A repair of a broken ledger rewrites the log. It is the one
  exception, and only a person does it.

## Alternatives considered

- **Call all of Sinter event sourced.** Not chosen: the main input,
  the working tree, is a snapshot, not a log, and the model would push
  toward reading git's history as events, which two records turned
  down.
- **Keep the specification as it was.** Not chosen: the order by a
  time that the writer chooses stays, and each later step of the
  ledger plan decides order and replay on its own.

## Consequences

The order of the ledger is the order of appending, and the time `ts`
is information only (record `ledger-layout`). The specifications state
each state as a fold, and the replay after a lost push checks again.
Two clones with the same entries at their tips give the same states,
whatever history each clone holds. A state that must depend on git's
history moves into the command that writes the entry. A cache of the
folds is safe while the ledger's tip has not changed.
