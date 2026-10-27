# Journal: Readable output

## Rename the finding classes and their words

- The requirement `ledger-stamp` became `ledger-approval-entry`, not
  `ledger-approval`, because `ledger-approval` already names section
  5.2 of the ledger specification. The lead ruled.
- The fields that named a stamp entry became `approval`: in the
  entries `approved-scope`, `approved-promise`, `completed`, and
  `pin`, and in the records of a declaration, a plan, and a claim. The
  time field `stamped` of a claim became `ts`, because `approved` is a
  bool on a declaration and on a plan. The lead ruled on `ts`.
- The maintainer ruled on words that the record does not name. The
  rungs `orphan`, `disconnected`, and `unattributed` and their
  predicates take the names of their classes, and `neverran(E)`
  becomes `never-ran(E)`. `blocked(P)` and the summary field
  `blocked` become `waiting`. "Owes a bump" becomes "needs a bump".
  The hunk field `mapped` and the summary field `unmapped` become
  `planned` and `unplanned`. "Endorse" and "amendment" stay.
- The maintainer ruled that "effective" keeps two uses: an effective
  `@supersedes` edge, and the effective scope of a step.
- `bench/` joined the scope of the step, because the generated trees
  write `@ack` lines that name a class.
- An ack accepts a finding, and a finding that an ack can accept is
  ackable; a finding no longer accepts an ack. A plan passes the
  completion condition, so that "meet" stays with a promise. A rung
  meets a promise, so that "complete" stays with a plan.
- `uncovered(e)` became `untraced(e)`. `unmet(p)` keeps its name,
  because the class is now `unmet-promise` and "unmet" is a plain
  word.
- In the code, `Facts.discharge` became `Facts.standing`, and
  `Facts.residue` became `Facts.meeting_fact`, because the module
  already has a type `fact`.
- No test checks that an old class name is unknown, because such a
  test would put an old name in `test/`. The tests of the 41 names
  and of the table of the specification fix the set.
