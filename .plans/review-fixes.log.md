# Journal: Fixes from the review of 2026-11

## Make the tests independent of the machine

- Rulings of the lead on details that the brief left open:
  - A permission test always makes its failure in a way that works for
    every user. It also runs the chmod way when the system refuses the
    read. A test skips only when no other way exists.
  - `run.exe` takes the program `time` from the option `--time`, with
    the default `/usr/bin/time`.
- The ways that work for every user: `files` meets a symbolic link
  loop at `src` (ELOOP); `tree_key` runs a `git` that refuses `add`;
  the index of `tree_key` is a folder.
- `scan` "a file that does not read is an error" skips as root. The
  file set holds only regular files, and root reads every regular
  file, so no other way exists.
- As root, the test of the unreadable index checks only the cause. The
  error of `copy_index` for a failed read does not name the index.
  This goes to the step "Make the diff independent of git's settings".
- `test/test_manifest.ml`, "load of a file it cannot open is
  unreadable", passes as root and checks nothing there. This goes to
  the step "Correct the messages of the manifest".
- A part of a cost that is the same at each size lowers the growth
  that `Counted_work.growth` sees. With a ratio of the sizes just above
  the margin, a cost one exponent above the bound passed, because of
  the header word of an array. The helper needs a ratio above the
  margin; a test should use a ratio of about twice the margin.
- Left for later: `Scan.escape_path` allocates more than in proportion
  to its path, as `Delivery_line.shown` does: 6,550 words for 100
  bytes of 0xff, and 254,612 words for 1,600.

## Correct the messages of the manifest

- `Toml`, `Glob`, `Branch_name`, and `Id_pattern` give each message in
  two parts, the fault and the help. The manifest no longer splits a
  message at its first "; ". The one-line `message` of each module
  stays, as the two parts joined with "; ", so its text and its tests
  do not change.
- The bridge names the last table on the path of a dotted key that a
  header made. An implicit table on the path does not count. An array
  of tables counts, and the walk goes on into its last table.
- Left for later: two forms still give a help that does not read when
  the person follows it. Both are the same on `main`:
  - The last key is itself a header table. For `[a.b.c]`, `[a.b]`,
    then `[a]` and `b.c = 1`, the help says to write 'c' under
    `[a.b]`, and that defines `c` twice.
  - An inline table is on the path. For `[a.b]` with `c = {d = 1}`,
    then `[a]` and `b.c.x = 1`, the help says to write 'c.x' under
    `[a.b]`, and that gives the error of an inline table.
- The test of a manifest that does not open uses a Unix socket. The
  system refuses to open a socket for every user. A socket path holds
  at most 104 bytes on macOS, and the folder of a worker of the
  mutation pass is under the checkout. So the test makes the socket by
  its name inside its folder.

## Correct the findings

- Rulings of the lead on details that the brief left open:
  - `stale-ack` judges condition 2 of `spec/vocabulary.md` section 7.4
    wherever Sinter can judge it in tree mode. An `@ack` of
    `unexercised` is not void by its tag target, because Sinter reads
    no evidence. An `@ack` of `unmet-rule` or of a declared `@rule` is
    not void by its tag target either, because Sinter evaluates no
    rules.
  - The fix of `stale-ack` removes the `@ack` line, one edit from the
    end of the tag line before it. The void acks of one id give one
    finding, and its fix removes each of their lines. An `@ack` on the
    first tag line of its block gets no fix.
  - The help of that fix is "remove the @ack line, check the block,
    and write a new @ack if the finding still applies".
- A removal from the end of the line before the `@ack` fails on the
  last line of a file with no final LF: git then shows the line before
  as changed, and the test of mechanical repairs refuses the hunk. On
  that line the edit starts at column 1. `Markdown.t.unterminated`
  gives the line.
- `typo-tag` takes the nearest word by the rule of the row, ties in
  byte order included, and then gives no fix when that word is `ack`.
  So `@reck`, two edits from both `ack` and `req`, gets no fix.
- After the fix of the lone CR, an `@ack` on the last line of a file
  with no final LF, whose hash ends in that CR, reads the CR as part of
  its hash. The ack is then void.
- `Facts.ack_id` replaces two copies of the id of an ack in
  `lib/facts.ml`.
- The review test of `unbumped` at 2^53 - 1 passes because the finding
  has no fix, so it checks nothing there. A test of the adjudicator
  states that the finding has no fix.
- Left for later: the fix of `retired` inserts its `@ack` after the
  last line of a file with no final LF. git's diff then shows that
  line changed, and the test of mechanical repairs refuses the hunk.
- Left for later: an `@ack` with no hash, or in a block with no
  declaration and no site, gives no ack fact, so it gives no
  `stale-ack`.

## Stop the crashes and give the right exit codes

- The limit of a query is 100 levels. Each `(`, each `[`, and each
  field name before a `:` adds a level, because each of the three
  recurses in the query parser of tree-sitter 0.26. A field chain such
  as `a: b: c: (x)` recurses with no bracket. The deepest query of the
  repository has 2 levels. A query at the limit compiles on a stack of
  256 KiB.
- The count of levels can be higher than the real recursion, never
  lower: a byte at or above 0x80 counts as a byte of a name. A count
  that is too high gives a false refusal and no crash.
- The bridge frees the instances of freed grammars when it replaces
  the store at the next load. A grammar freed after the last load keeps
  its instance until then. A test counts the instances through the
  private field of the engine, so the bridge exports no new function.
- A write error on standard output: before each error, the tool
  flushes standard output, and closes it when the flush fails. The
  close drops the bytes that failed, so the flush at exit has nothing
  to write. The help and the version of cmdliner raise their write
  error from `Cmd.eval'` or from the flush at the end; main catches
  both.
- macOS has no `/dev/full`. The tests of standard output also run with
  SIGXFSZ ignored and a file size limit of 0, which makes each write
  fail with EFBIG. The limit stops git and the temporary files of
  scan, so scan and check are tested on `/dev/full` only, on Linux.
- The words of the phases are tested on macOS with `/dev/fd/3`, a pipe
  that no process reads. Linux blocks the open of such a pipe, so that
  test skips there.
- APFS refuses a name that is not UTF-8, so the tests of a manifest
  path that is not UTF-8 skip on macOS. The tests of `/dev/stdin` fail
  before the fix only on Linux, where realpath of `/dev/stdin` fails.
- Left for later: the other errors of the manifest print a path that
  is not UTF-8 as raw bytes: "no manifest at", "cannot read the
  manifest", and the `-->` line of an error in the file. None of them
  crashes.

## Measure the whole mutation score within the time limit

- In changed mode each part runs every file of its share with
  `--changed-since`, not only the files that the pull request changed.
  The brief limited the files because a run on an unchanged file would
  cost the two runs without a mutant. That reason did not hold: the
  runner runs no test when it finds no mutant to run (runner.ml,
  `if to_run = []`). An unchanged file costs one start of the runner
  and one `git diff`, and the joined report then holds the mutants
  that did not run, as the report of one runner does (ruling of the
  lead).
- The loop over the files of a share is a third script,
  `test/run-mutant-share.sh`, so that a share runs on a machine with
  the same code as in CI.
- `mutaml-report` writes a mutated copy of each survivor under
  `_mutations/` and does not make the folder; without it, the report
  exits 1. The last job makes the folder of each source file first.
- The property tests read `QCHECK_SEED` with `int_of_string`, and take
  a seed of their own when the value does not fit. The number is 32
  bits from `/dev/urandom`, and the script refuses more than 17 digits.
- The artifact `mutation-report` holds the elements report and the
  joined runner report (ruling of the lead).
- The new scripts join the files whose change runs the full set.
  `MUTAML_COMMIT` moves to the env of the workflow, because two jobs
  read it.
- The CI run of the pull request in full mode (run 41536056030) gave
  each part 1,185 mutants, and took 1 h 39 min, 1 h 53 min, 2 h 51 min,
  and 1 h 15 min. The longest part is 2.3 times the shortest: a timeout
  costs the whole limit of a run, and the slow part held 30 of the 70
  timeouts and the slowest files (`lib/findings.ml`, 57 min;
  `lib/toml.ml`, 35 min). The longest part has more than two hours to
  spare, so the shares stay by count. The option `--shard` of the fork
  (lathrys-at/mutaml issue 10) would balance by mutant across files.
  The joined score was 97.4 percent: 4,740 mutants, 4,546 killed, 70
  timed out, 124 survived.
