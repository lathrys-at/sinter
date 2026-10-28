<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Give each fix a help message and edits
@decision structured-fixes
@cites related-places
@cites json-handling
@cites cite-the-successor
A fix is a help message and one or more alternatives of edits, each edit a span in a file and its new text; the JSON form carries the edits in one flat array and no longer carries the `fix` string.

## Context

The fix of a finding was one line of text in the field `fix`. The
line was a tag word, the head of a tag line, a whole `@ack` line, or
several citations joined by " or ". A program could not tell these
forms apart, and could not apply the fix without parsing the line.
Other tools carry their fixes as edits: ruff gives a list of edits for
each fix, rustc puts a replacement on each span, and SARIF, the
standard format for analysis results, gives a list of fixes, each one
an alternative made of replacements. The planned command `sinter
patch`, the text form, and a SARIF output need edits. `spec/jsonl.md`
section 2 lets a field hold an array of flat objects one level deep,
and no deeper.

## Decision

- A fix has one help message for a person, and one alternative or
  more. Each alternative is a list of edits. An edit is a path, a span
  in the columns of `spec/jsonl.md` section 3, and the new text. An
  empty span inserts, and an empty text deletes. The edits of one
  alternative do not overlap. Two or more alternatives mean that a
  person chooses one.
- An edit covers only the part of the tag line that changes, such as
  the revision. The one edit that adds a line is an inserted `@ack`
  line: it follows the last tag line of its block, starts at the
  column of that line's `@`, and ends with that line's line ending.
- The fix that cites the successor of a retired item does not bump
  the citing declaration. `unbumped` reports that bump, and only the
  base decides its revision.
- The JSON form gives the help message as `help`, and the edits as
  `edits`: one array of objects with `alt`, `path`, `line`, `col`,
  `eline`, `ecol`, and `text`. `alt` numbers the alternatives from 1,
  and every object carries it. The field `fix` goes. It is optional,
  so `v` stays 1. The text form keeps its `fix:` line, made from the
  edits, until the form is redesigned.
- A fix carries no safety label. The specification gives the rules: a
  fix with more than one alternative needs a choice; a fix that
  inserts an `@ack` line is a judgment, because it accepts the finding
  and does not repair it; every other fix is mechanical.
- A finding stores its fix in a compact typed form, and Sinter derives
  the help message, the edits, and the text when it writes the output.

## Alternatives considered

- **A nested array**, `fixes` with a `help` and an `edits` array in
  each element. Not chosen: it undoes the one-level rule of
  `related-places`, and the record `json-handling` would change again.
- **A separate record for each fix**, joined to its finding by the
  finding id. Not chosen, for the reason `related-places` gives: a
  reader must join the records, and the fixes sort apart from their
  findings.
- **Edits only for a fix with one alternative.** Not chosen: an editor
  could not offer each successor of a retired item as a quick fix.
- **Keep `fix`, derived from the edits.** Not chosen: two fields would
  say the same thing, and the loose form of the line would become part
  of the contract.
- **Keep `fix` as it was, built apart from the edits.** Not chosen:
  three parts of the code would compute the same repair and could
  disagree, and each finding would hold more memory.
- **A safety label on each fix**, as ruff and rustc give. Not chosen:
  no command applies a fix yet, and the label only repeats what the
  rules decide. A later step can add it as an optional field without a
  new `v`.

## Consequences

The edits map onto the fixes of SARIF without loss: the objects with
one `alt` make one fix, and their paths make its changes to each file.
A test can apply the edits of a fix and check that the change is a
mechanical repair (`spec/algebra.md` section 9.1), so the code that
builds the fixes and the code that recognizes them must agree. Edits
of different findings can overlap: a `suspect` fix and a `retired` fix
can both replace the revision of one citation. `sinter patch` will
need a rule for that.
