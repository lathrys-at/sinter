<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Mark the part of a tag at fault and the places that relate to a finding
@decision related-places
@cites json-handling
A finding marks the part of its tag line that is at fault and carries the other places that explain it, each with a label, and the JSON form carries both as flat fields and one array of flat objects.

## Context

A finding points at the whole tag line. When the revision of a
citation is stale, the reader must find the revision on the line, and
then find the declaration that the citation names. The fault is in
one part of the line, and the explanation is often in another place:
the first occurrence of a `duplicate`, the declaration that a
`suspect` citation names, the successor of a `retired` item, the
other members of a `cycle`. Tools that report well, such as rustc,
show both. SARIF, the standard format for analysis results, and LSP,
the protocol of editors, carry both. `spec/jsonl.md` section 2
allowed no nested object, so the JSON form could not carry a place
with a label.

## Decision

- A finding can mark one part of its tag line: the tag word, the
  target, or the revision; for an `@ack`, the class, the subject, or
  the hash; for a `@scope` line, one glob. The mark has a label.
  Sinter derives the mark from the tag line when it makes the finding,
  and keeps no other span for it.
- A finding carries zero or more related places. Each has a label and
  a span in a file, or only a label when the place has no file, such
  as a claim on another branch.
- The place of a finding stays its whole tag line. The sort order, the
  finding id, and the text form do not change. The related places
  never enter the id. A related place under a historical path stays.
- The JSON form gives the mark as `mcol` and `mecol`, the columns of
  the part on the first line of the finding, and its label as `label`.
  It gives the related places as `related`, an array of objects. Each
  object holds `path`, `line`, `col`, `eline`, `ecol`, and `label`;
  the five fields of the place are absent together for a place with no
  file. The array is sorted by `(path, line, col, eline, ecol, label)`,
  with the places that have no file last, by `label`. No two are
  equal.
- The work comes in stages. A finding of a class that has no mark yet
  points at the whole tag line, as before.

## Alternatives considered

- **Parallel flat arrays**, `related_path`, `related_line`,
  `related_label`, and so on, of equal length. Not chosen: a reader
  must zip the arrays, a place with no file needs a placeholder value
  because no field can be null, and arrays of unequal length are an
  easy defect.
- **A separate record for each related place**, of kind `related`,
  with the id of its finding. Not chosen: a reader must join the
  records by id, and the related places sort apart from their finding.

## Consequences

`spec/jsonl.md` section 2 allows one more value: an array of flat
objects. The record `json-handling` takes the same change at its
revision 3. The JSON form maps onto the `relatedLocations` of SARIF
without loss. A reader of the JSON form that does not know the new
fields can ignore them, so `v` stays 1.
