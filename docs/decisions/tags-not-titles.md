<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Bind tests to requirements by tags, not by test titles
@decision tags-not-titles
A test states what it verifies only with a `@verifies` tag in a comment, which pins a revision; Sinter does not read requirement ids in test titles.

## Context

Some projects put a requirement id in a test's title, for example
`it('SC-1: ...')`, and some forbid such ids in comments. Another tool
binds claims to tests by finding the claim's text in the runner's full
test title, and that works on vitest. But a `@verifies` tag pins a
revision of its requirement, and a pinned test becomes suspect when the
requirement changes. The specification reads no tags in string
literals, and a test title is a string literal.

## Decision

- A test declares what it verifies with `@verifies <slug> vN` in a
  comment above the test, or above a group of tests (one tag covers
  every test in the group).
- Sinter does not read requirement ids in test titles.
- A project that keeps ids in titles moves them into tag lines, for
  example with a script; a title may keep its id as text.

## Alternatives considered

- **Let a pack read an id in a test's title, as a setting that a
  repository turns on.** Not chosen: a title carries no revision, so a
  test bound by its title never becomes suspect when its requirement
  changes. It would also need an exception to the rule on string
  literals, an exact rule for where the id sits in the title (a plain
  substring finds `SC-1` inside `SC-10`), and a second way to bind
  tests in every pack. It can be added later if adoption shows the
  need, because it adds a way to bind and removes nothing.

## Consequences

Every bound test keeps Sinter's main signal: a changed requirement
flags the tests that check it. Adoption in a project that keeps ids in
titles costs a one-time script and a change to that project's rule on
comments.
