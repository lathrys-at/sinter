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

## Bound the costs

- Rulings of the maintainer and the lead on details that the brief
  left open:
  - The id pattern language gets a size limit (ruling F8): at most
    1,000 literals and classes when each quantifier is written out.
    A larger pattern gives the error `Too_large`. The matcher is a
    Thompson automaton. By a ruling of the lead, `{0}` counts as one
    copy, so that every pattern of the language passes the check of
    RE2. That check divides 1,000 by the largest count of each nested
    quantifier and refuses the pattern at 0 (`kMaxRepeat` in
    `re2/parse.cc`). This comes from the source of RE2; no run of RE2
    checked it.
  - The bench grows its existing generated tree: the first plan has
    `n / 5` steps, the first file of requirements holds a tenth of the
    requirements, and the message of the commit `work` holds the
    delivery line of each step. The existing growth limits apply.
  - A phase can have a limit of its own in `bench/budgets.toml`. The
    findings phase of `check` has the limit 16 (ruling F9); every
    other phase keeps 12.
- Each test bounds the growth between two sizes, never a time.
  `Counted_work` counts allocated words. The slow loops of five
  defects allocate nothing (`List.mem`, `List.assoc`, `List.exists`,
  `List.memq`), so their tests use `Timed_work`: the processor time,
  the shortest of three runs, a collection of the heap before each
  run, and a margin of 2 or 3. The timed tests are, in `facts`, "a
  file grows in proportion to its declarations", "a step grows in
  proportion to its promises", "a plan grows in proportion to its
  first block", "standing grows in proportion to the steps", and
  "standing grows in proportion to the promises"; and in `markdown`,
  "a section grows in proportion to its declared items". On the old
  code each fails at 2.4 to 2.8 times its limit. In the mutation pass
  a run that fails counts as a kill, so a timed test that fails by
  chance would raise the score.
- The bench found three more costs of the same shapes, each in its own
  commit: `scope-overlap` compared each step with every earlier step;
  `Facts.standing` checked its step and its promise with `List.memq`;
  and `delivery-without-change` and `unplanned-change` matched each
  changed path against the scope of each step. The last one needed an
  index of the scopes, `Path_index`.
- The search for strongly connected components moved from `Findings`
  into `Components`, so that `Facts.make` uses the same search.
- `Markdown.read` reads tags only in the first paragraph of a section
  or an item, so no nested container lies before the start of an
  extent. The walk of an extent starts at its first hole, with no
  search.
- The mutation pass counts 5 time-outs. Each is an endless loop that a
  mutant makes: 3 in `Components`, the search that `Findings` had
  before, and 2 in the walk of an extent.
- Left for later:
  - A glob with no leading names, such as `**/*.md`, is a candidate of
    `Path_index` for every path. Many steps with such scopes still
    cost the changed paths times those scopes.
  - `scope-overlap` compares in pairs the steps that share a promise,
    whether or not a finding comes out. Many steps that cite one
    record and have their own scopes cost the square of their number.
  - The findings phases of `check --diff` grow 11.95 and 11.97 times
    on the bench, near their limit of 12, for the same n log n reason
    as the findings phase of `check`.
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

## Kill the surviving mutants of the commands and the output

- `lib/` and `test/` did not change between b52bcb2 and the base of
  this branch, so the 82 survivors and the 8 timeouts of run
  41912076553 are those of the base.
- `test/test_check.ml` defined two tests that its list `tests` left
  out. One of them kills the mutant of `Check.reports`. Both are now
  in the list.
- The test of the refusals of `Fix.remove_acks` accepted any
  `Invalid_argument`. Two of its pairs index past the tags of their
  document, because a tag line after an empty line of a section is no
  tag, so those pairs never reached the checks. The test now checks
  the message of each refusal, with a pair that only that check
  refuses.
- mutaml makes the off-by-one mutants of an argument at the call that
  takes the argument. A mark on the argument alone takes out no
  mutant, and the `.muts` file lists that place with no operator. A
  mark must name the whole call. A mark on the result of a call, such
  as `String.length text`, takes out the two mutants of that result.
- A mark changes the names of other mutants: the ordinals of a name
  move when a mark takes out a mutant of the same name in the same
  binding, and the digest of a mutant holds the text of a mark inside
  it. A run of old names after a mark must map them by their text.
- Two marks in `lib/usage.ml` also take out mutants that the tests
  kill, because no smaller expression holds the equivalent one. The
  mark in `escape_end` also takes out the length plus 1, which the
  test "an escape code at the end is left out" kills. The mark on
  `String.sub line 0 colon` also takes out `colon - 1`, which the case
  "a name that ends with a space" kills; 1 in place of 0 and `0 + 1`,
  which the case "a name that starts with a space" kills; and
  `0 - 1`, which makes `String.sub` raise in the test "a usage and a
  message give the fault and the help".
- `trim` in `lib/render.ml` lost its branch, which had an equivalent
  mutant. The output phase of `@bench` allocates the same words before
  and after, on each tree.
- The eight branches of `bin/main.ml` that report an error and give
  the exit code 3 call one function, so the branch that no test
  reaches holds no sequence of its own. No test reaches the branch
  where the parser bridge does not start: no option reaches it, and
  `ulimit -v` does not limit memory on macOS. A test under `ulimit -v`
  on Linux is left for later.
- The test of `Exit_code.refused` is in `test/test_cli.ml`: no code of
  `lib/` or `bin/` uses the value.

## Kill the surviving mutants of the readers and the findings

- A mark on an argument does not take out the mutants "argument off
  by one" of that argument: the call makes them, outside the marked
  expression. A mark for such a mutant sits on the call.
- `Findings.hash_mark` counts the characters before the hash in place,
  with `Line_index.characters`, and no longer counts a copy. A mark on
  the call `String.sub` would also have taken out six mutants that the
  tests kill. The results do not change; the findings phase of
  `@bench` allocates 98 words less on the tree of 1,000 declarations
  and 979 words less on the tree of 10,000.
- The test "an entry with both flags is compared by its content" set
  its flags with one command, `git update-index --assume-unchanged
  --skip-worktree`, which sets only the first flag. Two commands now
  set the two flags.
- The tests of the view put a script named `git` first on `PATH`. The
  script runs the real git and records the input of the commands of
  the view, so that a test reads which paths each command gets. The
  test of the store sets the umask to 0, so that the mode does not
  depend on the machine.
- A mark changes the name of each other mutant whose text holds the
  marked expression, because the name holds a digest of that text.
  The connective 261dd9fa of `Toml.between` is now b59bbcb2.
- The reason of a mark names each other mutant that the mark takes
  out and what that mutant changes, and names no test. Four marks take
  out a mutant that the tests kill:
  - `String.length text` in `Delivery_line.trimmed` takes out
    `String.length text - 1`, which "reads a line of the pattern"
    kills.
  - The two lengths in `Toml.find_marker` take out
    `String.length text + 1` and `String.length marker - 1`, which make
    `String.sub` raise; the suite stops at its start on them, and
    "read_message reads each description of the reader" kills them.
  - `text.[offset]` in `Markdown.new_line` takes out `offset - 1`,
    which "the new line follows the last tag line" kills.
- A mark on the condition of an `if` does not take out the mutant
  that negates the condition: that mutant sits on the `if`. The
  mutants `not (cut > 0)` of `Markdown.walk_section` and
  `not (at > last)` of `Toml.find_marker` stay, and the tests kill
  them. Their names change with the text of the reason.
- Each of the 60 mutants that ran to the time limit hangs the suite
  of its module past 60 seconds, except the if-condition 51431a0a of
  `Facts.trim`: the suite of the facts kills it with a failure, and in
  the full suite the suite of the adjudicator hangs on it first.

## Close the security gaps

- `Source` reads only the manifest location and the paths of the file
  set, and it opens no absolute path. A review found that a name in the
  tree of the base reached any file: `/etc/hosts` by its absolute name,
  `.git/config` and an ignored `.env` by a relative name. A branch that
  deletes a tracked `.env` and then ignores it reached the same read with
  no crafted tree. An outside manifest has no finding with a place in it,
  so no absolute path needs a read, and a manifest pipe is read once.
- A path of `--manifest` outside the repository is read by its resolved
  text. Read by the path that the person gave, `ci/link/../../../m.toml`
  lets a committed link choose the file.
- A folder counts as inside when its real path is the root or a folder
  below it. The first form of the check took only the root, and a link
  of the person's own to `repo/ci` then followed a committed link in
  `ci`.
- A path that ends in `/`, `/.`, or `/..` keeps a final `/` through
  `Repo_file.place`, so `sinter.toml/` stays the error of a missing
  manifest. Without the `/`, the text form read the file.
- `Utf_8.escaped` replaces both `Delivery_line.shown` and
  `Scan.escape_path`, which held the same code. A name of 40 KB in the
  tree of a base commit used 933 MB through `Scan.escape_path`.
- Through the binary, no other cost on the road of a delivery line grows
  faster than the line. The shapes measured to 1.6 MB: plain text,
  spaces, tabs, control characters, bidirectional characters, combining
  marks, wide characters, long plan and step names, and many lines.
- A test of a file set with a link to itself on the way expected the
  error `ELOOP`. A link on the way now leaves the file out, so the test
  changed.
- The first mutation pass left four survivors. The close after a failed
  `fstat` went away, because `read_handle` now has one close for each
  refusal. The mode of `openfile` has a mark. `Ok false` in
  `is_real_folder` showed that the link in the tests had no file behind
  it; the tests now put one there. The removal of `Hashtbl.add` in
  `is_real_folder` falls to "the cost of the file set does not grow with
  the depth of each file".
- Left open: a link that the person makes outside the repository is
  followed when no folder of the path leads below the root: a link at the
  last part, or a link to a committed link to a folder. A committed path
  that changes between the `realpath` of a folder and the read can also
  change the place that the check gives.
- Left for later: the tree of a base can hold a name that git never
  checks out, such as `/etc/hosts`, and a finding still names it as a
  place. No file opens for it.
- Left for later: `--manifest CI/m.toml` on a disk that ignores case
  keeps the case of the text in its location, so the lookup in the base
  misses, and the check gives `config-changed`.
