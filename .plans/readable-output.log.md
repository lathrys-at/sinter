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

## Rename the settings of the manifest and the gates

- Four JSON fields that the record does not name: the field `ref` of
  the record `external` becomes `name`, the id inside the namespace.
  The field `ref` of the deferred ledger entry `pin` becomes
  `external`. The field `attributed` of a `cov` record and the field
  `capped` of a `gate` record keep their names; only their
  descriptions change.
- Each runner table yields one setting fact as a member of
  `scan.packs.<name>.runners`, with the id of the old array member, so
  that `config-changed` still sees a runner that a change turns on or
  off. Each runner setting yields its own setting fact.
- The step's scope lacked `.claude-plugin/**`, which the bump of the
  plugin version touches. An amendment (#122) added it.
- The record `commit-messages` still calls the target of `Issue:` a
  ref; records keep the words of their time.
- A bad runner name is now an error of a key name, found in the step
  of the names, as a bad pack name is. Runners come in the order of
  the file. A runner in two packs is reported at the key of the later
  pack in byte order.
- Unlike the step before, a test checks that each old key and each
  old gate name is now unknown, because the brief fixes that no alias
  stays. Those tests are the only old names left in `test/`.
- Sections 10.2 and 10.3 of `spec/manifest.md` became one, so the
  default locations moved from 10.4 to 10.3; the references follow.
- Left for later: the design notes still use names of an older design
  that the record does not list: the gates `pr` and `main`, `enforce`,
  `refuse_env`, `evidence.require_attribution`, and `ref-state`. The
  pack descriptor of `spec/packs.md` keeps its own key `spec`.

## Show the parts of a tag and the related places

- A fact finds its tag through a field `tag : Markdown.tag` on the
  records of a declaration, an edge, a promise, and a plan. The brief
  allowed int columns or an index from a fact to its tag, whichever is
  smaller. The field is a reference, the one-word form of that index:
  it needs no lookup from a path, and no column is computed until a
  finding asks. Two int columns would cost two words for each fact and
  a count of characters for every fact. The lead accepted the field.
- A step is no tag line, so a `duplicate` of a step has no mark.
- `unbumped` marks the revision of the declaration, or its word when
  the tag gives no revision.
- A `retired` finding names the cited item, with its status or with
  "superseded", and each successor. The status tag line is not at
  hand, so the label of the cited item names the status.
- Left for later, because each needs data threaded through `Facts`:
  the paragraph that Sinter reads, for `ignored-tag`; the declaration
  with another spelling, for `dangling`; the status tag and the
  retiring edge, for `retired`; the `@scope` lines and their globs,
  for `scope-outside-plan` and `promise-out-of-scope`; the edges of a
  `cycle`; and the parts of an `@ack`.
- `Finding.escape` returns its argument when the text holds no
  control character, instead of a copy. The brief did not ask for it.
  The marks and the related places made the findings phase allocate
  30 to 41 percent more words on the benchmark, and the copy of each
  detail, fix, and label was the largest part of that. With the
  change, the findings phase allocates fewer words than before the
  step.

## Structure the fixes

- A fix is held as `Fix.t`, an abstract type. Each form keeps the
  `Markdown.tag` that it changes, and only the new parts: a
  word, a revision, a slug, the successors, or the block of an `@ack`
  line. The columns, the help message, the edits, and the
  text come from the tag when the output is written. Functions that
  make a fix refuse a tag with no target, so the output functions
  are total. On the tree of 10,000 declarations, the findings phase
  of `check` allocates 0.3 million fewer words, and the output phase
  0.45 million more.
- `Markdown.block` gains `new_line`, the text that opens the inserted
  `@ack` line, because the reader keeps no text of the file. An
  indent of up to 16 characters with no tab shares a constant string,
  so most blocks allocate nothing for it.
- A revision edit whose new revision equals the old one is left out,
  for `renamed` and for each successor of `retired` (ruling of the
  lead). The target and the revision are two edits, so the gap between
  them stays as it is.
- Nothing inside a block quote holds tags, so the prefix rule for `>`
  is tested on `Tag_line.indent` alone.
- Section 9.1 of the algebra called the repairs that it accepts
  "edits". They are now "changes", so that "edit" keeps the meaning of
  `spec/jsonl.md` section 8. Section 9.1 accepts the same hunks.
- A `retired` finding whose cited item has neither a status nor a
  successor gets no fix; at 170c04b its fix was `""`, which
  `Finding.make` refuses. `Facts.successors` and the rule of in force
  rule the case out. Its detail stays as it was (ruling of the lead).

## Render the full and brief forms

- `opam lock` read `compiler-cloning` as `enabled` from the switch.
  The lock keeps `disabled`, as it had, because the package is not a
  dependency of Sinter. The lock also takes the synopsis and the
  description of `dune-project` again; they were stale.
- Without a gate, the primary mark and its label take the bold style of
  the headline; the style table gives a color only to the marks of a
  tier. The style renderer is `None` in this step, so no output shows
  it.
- `Format` breaks a line at a break hint when the queue is flushed,
  whatever the margin. The renderer writes no break hint, and the large
  margin guards only text inside a box.
- The full and brief output name the base only with `-v`, so
  `spec/manifest.md` section 6 now says so (ruling of the lead).
- The ledger warning shows only when a plan exists, and the help, not
  the warning, says how to fetch the ledger. `ledger-absent-ref` moves
  to v3 with the same rule (ruling of the lead).
- Every detail names the item it is about, as `kind:slug`, a step id,
  or the tag as written, because the text forms no longer show the
  subject id (ruling of the lead). A cycle of one declaration now has
  a detail too. The details of `parse-error` and `ignored-tag` stay:
  their location is their item. The labels of the marks do not
  change.

## Print errors in one layout and in color

- The fixture runner no longer passes the caller's `TERM`, `NO_COLOR`,
  `CLICOLOR_FORCE`, `FORCE_COLOR`, and `CLICOLOR` to a run, and no
  longer sets `NO_COLOR=1`. A case sets a variable in a new entry,
  `env`, one `NAME=value` on each line (ruling of the lead).
- The warnings of `Scan` and `Check` hold their text without the word
  `warning:`, so that the printer can give the word its style (ruling
  of the lead).
- A new module, `Error_text`, holds the fault, the help, and the place
  of an error. `Manifest.explain` and `Scan.explain` give it; `Grammar`,
  `Query_file`, and `Parse_record` keep `message` as the fault and gain
  `help`. `Parse.Error` and `Serve.Error` carry an `Error_text.t`; the
  control line of `serve` keeps the fault as its message, so its JSON
  does not change (ruling of the lead).
- A message that the manifest reader embeds from `Toml`, `Branch_name`,
  `Glob`, or `Id_pattern` splits at its first "; ": the part after it
  is the help. A message with no such part gets a help of its own. The
  messages of those modules whose part after "; " stated a fact now
  state an action there, for example "write ']' here" in the place of
  "expected ']'".
- The mark of a manifest error stops at the column after the last
  character of its line when the span goes on past it. A syntax error
  at the end of a line thus shows one caret after the last character.
  A span that starts further right shows no source line (ruling of the
  lead).
- A usage error that `parse` makes itself now asks cmdliner for the
  usage line, so it gets the help `usage: ...` as cmdliner's own usage
  errors do (ruling of the lead).
- cmdliner writes the option of "required option X is missing" in
  bold under `TERM=xterm` and plain with no quotes without `TERM`. The
  bold part becomes a quoted part, so this one message reads
  `'--grammar'` under `TERM=xterm` and `--grammar` without `TERM`.

## Write the porcelain form

- A manifest string can hold `\u0000`, and a `config-changed` subject
  holds that string, so a field can hold a NUL. With `-z`, a field that
  holds a NUL or starts with `"` is quoted by the rule of the tab form,
  and every other field is written as it is (rulings of the
  maintainer). A reader undoes the quotes exactly when a field starts
  with `"`. The record takes the ruling.
- `--headers` reads its value as one string and splits it at commas.
  cmdliner's list type drops an empty name, so `--headers=` and
  `--headers=base,,mode` would have passed; they are now an unknown
  header `''`.
- An unknown header name is the one usage error whose help lists the
  header names. The other usage errors take the usage line as their
  help, as cmdliner's own errors do.
- The help names "the porcelain specification" and no path, because a
  help text never names a repository file (ruling of the lead).
- `Scan.ledger_commit` is the one lookup of the ledger ref, and
  `ledger_warning` uses it. A run that names the header `ledger` and
  holds a plan runs `git rev-parse` for the ref twice.
- `Check.run` makes the header lines, so that a tool version that a
  header cannot hold raises `Invalid_argument` before any output. Such
  a version comes only from a build whose package version is empty.
