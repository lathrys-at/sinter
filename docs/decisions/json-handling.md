<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Write all JSON with one printer of our own and read JSON with yojson
@decision json-handling v4
@cites related-places
Sinter writes all its JSON with one printer of its own that enforces the canonical form, the JSON Lines records through a typed layer over it, and reads JSON with the `yojson` library.

## Context

`spec/jsonl.md` section 2 fixes the canonical form of every line
Sinter emits: keys sorted by UTF-16 code units, RFC 8785 escaping, no
insignificant whitespace, and only five value shapes: a string, an
integer in a fixed range, a boolean, a flat array of those, and an
array of flat objects whose values are strings, integers, or
booleans.
Conformance fixtures compare output byte for byte, so a single
deviation is a failed fixture. JSON libraries produce valid JSON, but
none of the OCaml libraries promises this canonical form. Sinter also
reads JSON: the serve mode takes requests as JSON lines. SARIF output
nests objects and arrays six levels deep and more, and the request to
a runner adapter must be nested JSON in the canonical form of RFC
8785 (`spec/packs.md`).

## Decision

- One printer in `sinter.core` writes all of Sinter's JSON. It prints
  nested objects and arrays, strings, integers, booleans, and null,
  in the canonical form of RFC 8785: it sorts the keys of each object
  by UTF-16 code units, escapes as RFC 8785 requires, and refuses a
  repeated key, an integer outside the allowed range, and a string
  that is not UTF-8. It prints no float; a float waits for a use that
  needs one.
- `lib/jsonl.ml` is a typed layer over the printer. Its types admit
  only the five value shapes of `spec/jsonl.md`, so a float and a null
  cannot be expressed in a record, and an object can appear only as
  an element of an array, with no array or object inside it. Every
  command that emits facts goes through it.
- SARIF output and other nested JSON use the printer directly.
- `yojson` (BSD-3-Clause) reads JSON. It never writes Sinter's output.
- Sinter does not normalize Unicode in the strings it writes. The
  record `text-as-written` gives the reasons.

## Alternatives considered

- **`yojson` for writing as well** — rejected. It does not sort keys
  or escape as RFC 8785 requires, so the output would need a second
  pass to become canonical, nothing in its types stops a float or a
  null from reaching the output, and it writes a string that is not
  UTF-8 as it is.
- **`Jsonl` grows nested objects and arrays** — rejected. The records
  of `spec/jsonl.md` would lose the guarantee that their types give.
- **A second writer for nested JSON, which shares the escaping and the
  key sort with `Jsonl`** — rejected. One printer with a typed layer
  for the records gives the same guarantee with one copy of the
  canonical form.
- **A printer for SARIF only, written by hand** — rejected. Nothing
  else could use it, and each new SARIF object needs more code.

## Consequences

One printer owns the canonical form, and its tests cover the cases
where UTF-16 order and UTF-8 byte order disagree. A record that breaks
the schema fails at construction, not in a fixture. The output of
`Jsonl` does not change by a byte when it moves onto the printer. A
float needs a change of the printer and of this record. Every JSON
reader in Sinter depends on `yojson`, which `dune-project`, the lock
file, and `THIRD_PARTY.md` declare.
