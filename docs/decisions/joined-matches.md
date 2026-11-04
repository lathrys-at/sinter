<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Join two matches of one pattern that give one node the same role
@decision joined-matches
When two or more matches of one query pattern give one node the same role, Sinter joins them and takes each captured node once, in the order of the text.

## Context

tree-sitter can return the pieces of one test name in two matches of
one pattern. The example query of `spec/packs.md` section 4.4 did so:
for `it("a\nb", ...)`, one match held `a` and a second match held `\n`
and `b` (tree-sitter 0.26.13, the TypeScript grammar v0.23.2). The
pattern chose between two kinds of string, and each kind had a
repeated list of pieces. Section 4.1 chose between two matches only by
the order of their patterns. It said nothing about two matches of one
pattern, so taking the first match gave the name `a` with no warning.

## Decision

- Section 4.1 gains the rule: when two or more matches of one pattern
  give one node the same role, Sinter joins the matches and takes each
  node that they capture once, in the order of the text. The rule for
  two matches of two different patterns stays.
- The example of section 4.4 writes the test pattern as two patterns,
  one for each kind of string. Each test then gives one match.
- The step "Read JavaScript, OCaml, Rust, and TypeScript" builds the
  rule and its tests.

## Alternatives considered

- **Correct only the example, and take the first of two matches of one
  pattern.** Not chosen: a pack author who writes the shorter form gets
  wrong names with no warning, and the pack's tests find it only when a
  test name holds an escape or a substitution.
- **Correct the example, and report a finding when two matches of one
  pattern give one node the same role.** Not chosen: it needs a new
  kind of finding, and the users of a pack would see it in their own
  scans, not the authors of the pack in its CI.

## Consequences

Both forms of the query give the right name. The code that reads
matches needs one join step.
