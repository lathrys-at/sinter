<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Revise a record that decides the same question; supersede it when the choice changes
@decision revise-or-supersede
A decision record is revised in place when it still decides the same question, and a new record supersedes it when a different choice replaces it.

## Context

`spec/vocabulary.md` section 8.3 permits an edit of a decision record
with a revision bump, and the ledger attaches approval to one
revision of a record, not to its file. The design notes say that the
rule against deletion objects to silent revision, not to editing. The
project had treated every record as a file that never changes, so
every change of a decision took a new record with a new slug. A small amendment of the record
`branch-workflow` then needed a new name for the same subject.

## Decision

- When a record still decides the same question and only some of its
  rules change, edit the record and raise its revision. Each citation
  pinned to the old revision becomes suspect, and its author checks it
  and pins it again.
- When a different choice replaces the record's choice, write a new
  record with a new slug that supersedes the old one. The old record
  stays as it is, as the reason for the new one.
- What never changes is a revision: once approved, the text of a
  revision is fixed. A change makes a new revision.

## Alternatives considered

- **Always supersede.** Not chosen: a small amendment needs a new
  name for the same subject.
- **Always revise.** Not chosen: the reasoning behind a replaced
  choice leaves the files, and a record can drift far from its first
  meaning under the same name.

## Consequences

The author judges which case applies. The text of an earlier revision
stays only in the git history. Citations of an amended record become
suspect, so each citing item is checked against the new revision.
