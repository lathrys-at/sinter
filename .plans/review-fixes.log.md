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
