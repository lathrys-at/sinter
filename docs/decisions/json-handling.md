<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Write canonical JSONL with our own writer and read JSON with yojson
@decision json-handling
Sinter writes its JSON Lines output with a writer of its own that enforces the canonical form, and reads JSON with the `yojson` library.

## Context

`spec/jsonl.md` section 2 fixes the canonical form of every line
Sinter emits: keys sorted by UTF-16 code units, RFC 8785 escaping, no
insignificant whitespace, and only four value shapes — a string, an
integer in a fixed range, a boolean, and a flat array of those.
Conformance fixtures compare output byte for byte, so a single
deviation is a failed fixture. JSON libraries produce valid JSON, but
none of the OCaml libraries promises this canonical form. Sinter will
also read JSON: the serve mode takes requests as JSON lines.

## Decision

- `lib/jsonl.ml` in `sinter.core` writes every line. Its types admit
  only the four allowed value shapes, so a float, a null, or a nested
  object cannot be expressed. It sorts keys by UTF-16 code units,
  escapes as RFC 8785 requires, and refuses a repeated field name, an
  integer outside the allowed range, and a string that is not UTF-8.
  Every command that emits facts goes through it.
- `yojson` (BSD-3-Clause) reads JSON. It is declared as a dependency
  now, so that the choice is fixed and CI proves it resolves; the
  first module that links it is the serve mode.
- NFC normalization of strings that come from file text, which the
  specification requires, is not done yet. It needs the `uunf`
  library, and the roadmap lists it under `sinter scan`.

## Alternatives considered

- **`yojson` for writing as well** — rejected. It does not sort keys
  or escape as RFC 8785 requires, so the output would need a second
  pass to become canonical, and nothing in its types stops a float or
  a null from reaching the output.
- **A library that implements RFC 8785** — rejected. None exists for
  OCaml, and the specification restricts values enough that the
  canonical form fits in about a hundred lines of our own.
- **A JSON reader of our own** — rejected. Reading needs a full JSON
  parser, which is more code than the writer and gains nothing over a
  maintained library with a permissive license.

## Consequences

One module owns the canonical form, and its tests cover the cases
where UTF-16 order and UTF-8 byte order disagree. A record that
breaks the schema fails at construction, not in a fixture. Every JSON
reader in Sinter depends on `yojson`, which `THIRD_PARTY.md` lists.
