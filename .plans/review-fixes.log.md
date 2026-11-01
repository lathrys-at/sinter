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
