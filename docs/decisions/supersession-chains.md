<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Keep a supersession in force when its record is superseded
@decision supersession-chains
A `@supersedes` edge stays live when the declaration that holds it is itself superseded; only a status tag on that declaration, or a missing approval, stops the edge.

## Context

`spec/vocabulary.md` section 8.1 made a `@supersedes` edge live only
when its source was in force. In a chain where `b` supersedes `a` and
`c` supersedes `b`, the record `b` is retired, so its edge to `a`
stops, and `a` comes back in force. On such a chain, `sinter check`
reported a citation of `b` and nothing for a citation of `a`. In
Sinter's own records, a record that superseded `rust-bridge` would
bring `parser-bridge` back in force. The rule is right for a source
that a status tag retires: a `@rejected` or `@deferred` record never
took effect, so the record that it names still holds.

## Decision

- A `@supersedes` edge is live when its source is a declaration that
  carries no status tag and, when its kind needs approval, is approved
  at its current revision. Whether a later edge supersedes the source
  does not matter.
- In a chain, every declaration before the end is retired. The end of
  the chain, which is in force, is the successor of each of them.
- A status tag on a source stops its edges, as before.
- A cycle of `@supersedes` edges is handled as before: each member
  counts as in force, and the `cycle` finding reports the cycle.

## Alternatives considered

- **Keep the rule of section 8.1, and have the author of `c` also
  write `@supersedes a`.** Not chosen: an author who forgets the second
  line brings `a` back in force, and no finding says so.

## Consequences

Whether an edge is live no longer depends on whether its source is in
force, so the tool needs no fixpoint to compute it. The field `live`
of a `supersedes` edge in the output of `sinter scan` follows the new
rule. A `@deprecated` source still brings back the item that it
superseded, although `@deprecated` says that nothing replaces it; that
case stays as it is until a project needs it changed.
