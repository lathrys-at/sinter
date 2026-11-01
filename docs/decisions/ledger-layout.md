<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Keep the ledger in closed chunks, number its entries, and verify it entry by entry
@decision ledger-layout
@cites json-handling
@cites ledger-event-log
The ledger holds its entries in closed chunks of 50 entries and numbers them 1 to n in the order of appending, Sinter verifies its history by entries and not by the bytes of one file, reads only the parts of an entry that it knows, and stops when the ledger is broken.

## Context

The specification kept the ledger as one file, `ledger.jsonl`, that
each write extends, and it verified the history by checking that each
commit's file starts with its parent's bytes. That check reads the
file of every commit, so its cost grows with the square of the number
of commits: 2.8 s for 1,000 commits of a 2.8 MB file, and about 1.4 TB
to read for 100,000 one-entry commits. It also made any change of the
layout look like a rewrite. The specification did not say what a
reader does with an entry kind or a field that it does not know, or
what a check reads when the ledger is broken. It ordered the entries
by `ts`, a time that the writer chooses: an approval with a time in
the year 2099 overrode a later decline, and `sinter ledger verify`
passed a commit that swapped two entries between chunks, because a
commit's tree keeps no order of its chunks. No ledger existed yet, so
the layout could still change at no cost.

## Decision

- The ledger holds its entries in **chunks**: files of JSON lines
  under `entries/`, in folders named by the first two hexadecimal
  digits of the id of their first entry, and named by that id. One
  chunk is open; a write appends to it, or starts a new chunk when the
  open one is full. A full chunk is closed and never changes. A chunk
  is full at 50 entries. Measurement fixed that size: at 100,000
  entries, chunks of 25, 50, and 100 entries read the tip in the same
  time; chunks of 25 and 50 entries verify the history at the same
  cost, and chunks of 100 entries need about a fifth more
  instructions. Chunks of 50 entries make half as many files as
  chunks of 25.
- Sinter verifies the history entry by entry: each commit holds every
  entry of its parent, byte for byte, and may add new entries,
  wherever they live. An unchanged closed chunk has the same object
  id in both commits, so the check skips it. So a commit that merges
  chunks or changes the layout passes, as long as no entry changes or
  disappears. The ref moves forward only. Dropping old history is not
  such a commit; it stays a rare, explicit act outside these rules.
- Every entry carries `seq`, a whole number, and its id covers it.
  The entries of every commit of the ledger hold each `seq` from 1 to
  n exactly once, where n counts the entries of every kind. The order
  of the ledger is the order of `seq`, which is the order of
  appending; `ts` orders nothing. The new entries of a commit hold the
  numbers above those of its parent. The host's ref is the one
  central order: an entry that is not yet pushed is provisional, and a
  replay after a lost push can give it a new `seq` and so a new id.
- A repair writes an entry of the kind `void`, with the fields
  `dropped` and `reason`, at the `seq` of each entry that it drops. No
  later entry changes its `seq` or its id.
- Sinter checks every line, whatever its kind: the line is in the
  canonical form, and its id is the hash of its bytes. It checks the
  types of the fields only for the kinds that it knows. It ignores an
  entry of an unknown kind and an unknown field of a known kind, and
  it warns once with their count. An entry whose version `v` is
  higher than the version that the tool reads stops the command with
  exit code 3, and the help says to upgrade.
- When the ledger is broken, every check stops with exit code 3. The
  error names the first bad entry and its commit, and the help names
  `sinter ledger repair`. The checks at the gates `turn` and `review`
  check the tip; the check at the gate `merged` and
  `sinter ledger verify` check the whole history.

## Alternatives considered

- **One file, verified by the bytes of each commit's file, as the
  specification said.** Not chosen: the cost of verification grows
  with the square of the number of commits, and each write stores a
  new copy of the whole file.
- **One file for each write.** Not chosen: verification becomes
  linear, but every check must read one small file for each entry,
  1.7 s for 100,000 entries against 0.08 s for one file.
- **Many entries in each commit.** Not chosen: it lowers the cost only
  by a constant.
- **Order by `ts`, as the specification said.** Not chosen: the writer
  chooses `ts`, so a wrong clock or a chosen time moves an entry
  before entries that came earlier.
- **A `ts` that must rise.** Not chosen: a wrong clock makes every
  later writer refuse; an entry with a time in 2099 would stop every
  write until 2099.
- **A `prev` link from each entry to the entry before it.** Not
  chosen: a repair breaks the chain, so the id of every later entry
  changes, and the link gives no position number.
- **A tree of entries with no central order, where two clones can
  append at the same time and a merge joins them.** Not chosen: the
  order of two judgments would then be partial, and the projections
  need one order. The host's ref already gives one.
- **Order by the names of the chunks and the positions of the lines.**
  Not chosen: it forbids moving entries between chunks, and two equal
  judgments at two positions get one id.
- **Read the history at every gate to find the order.** Not chosen: it
  costs about 6.5 s against 0.9 s at 100,000 entries, and a clone that
  fetched only the tip cannot order its entries.
- **A repair numbers the later entries again.** Not chosen: the id of
  every later entry changes, and every reference to one of them must
  be written again.
- **An entry of an unknown kind makes the ledger broken.** Not chosen:
  a tool that predates a new kind of entry would stop at the first
  entry of that kind, so every clone would have to upgrade at once.
- **A check uses no entry of a broken ledger.** Not chosen: every
  approval would vanish, and the approval findings would block every
  branch while the checks still ran.
- **A check uses the entries up to the first bad one, and warns.** Not
  chosen: a broken ledger puts every approval in doubt, and work should
  not go on from it.

## Consequences

For a ledger of 100,000 entries in 100,000 commits, on a machine
with a load average of about 2, reading the tip and checking every
line takes about 0.9 s, and verifying the whole history takes about
6.5 s. A `seq` adds about 12 bytes to a line of about 294 bytes. The
layout can change later in an ordinary forward commit. Two clones that
push at the same time cannot both win: the second one replays its
entries on top of the first, with new numbers and new ids. A broken
ledger stops all work through Sinter until someone repairs it, so the
repair command comes with the commands that write the ledger. A tool
can read a ledger that a newer tool wrote, unless a version rises.
