<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Write the text of a file as the file holds it
@decision text-as-written
@cites json-handling
Sinter writes each string that comes from the text of a file with the characters that the file holds: it selects and trims text by the rules of the specifications, and it never normalizes Unicode.

## Context

`spec/jsonl.md` section 2 required the scanner to normalize the
strings that come from the text of a governed file to Unicode NFC, so
that two strings that look equal also have equal bytes. The record
`json-handling` left this for `sinter scan`, with the `uunf` library.
When `sinter scan` was built, no normalization library was available
without a new dependency.

Normalization acts only on the strings that the specifications copy
from the text, such as the title of a section and a description. It
does not act on ids, slugs, paths, or hashes. A slug holds only ASCII
letters, digits, and hyphens; paths were never normalized; and the
extent hash covers the bytes as the file writes them.

## Decision

- A string that comes from the text of a file holds the characters
  that the file holds. Sinter takes the part of the text that a field
  names, and trims it as the specifications say, but it does not
  compose, decompose, or change any character.
- The canonical JSON form encodes the string. A reader that decodes it
  gets the same characters back.
- Every implementation of the specifications does the same, so two
  tools that read one repository write the same bytes.
- Tools compare strings by their bytes. Two strings that look equal
  but use different code points are different, as their hashes
  already are.

## Alternatives considered

- **NFC normalization with the `uunf` library**, as `json-handling`
  planned. Not chosen: it adds a dependency and Unicode tables to
  Sinter and to every other implementation, for two text fields that
  no rule of Sinter compares.

## Consequences

A program that reads the output of Sinter and wants titles or
descriptions that look equal to compare equal must normalize them
itself. `spec/jsonl.md` section 2 states the rule, and the roadmap no
longer lists normalization.
