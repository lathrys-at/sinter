# Journal: The ledger

## Read and verify the ledger

- The lead ruled on six details of the brief. The help fetches the
  absent ledger with one line,
  `git fetch --no-filter origin refs/sinter/ledger:refs/sinter/ledger`,
  because no local entry exists when the ref is absent. The rule that
  the local ref and the remote ref are on one line of history belongs
  to the commands that move the ref, in a later step; `ledger verify`
  checks the local ref only. `ledger-broken` takes no tier at any gate,
  as `pack-mismatch` does. `scan` and `ledger log` stop with exit code
  3 on a broken tip. One interactive `git cat-file --batch` reads the
  tip and the history, in place of `ls-tree`, because `ls-tree -r`
  does not show an empty folder and the walk of the history must
  decode raw trees anyway. The index record gains the field `ledger`,
  which no code wrote before.
- The lead first ruled that `ledger verify` exits with code 1 on a
  broken ledger, and then changed the ruling to code 3, as every other
  command does, so that the record `exit-codes-by-gate` holds as
  written. With `-o json`, the command still writes the finding.
- The lead ruled that `branch` is optional, because a writer on a
  detached HEAD has no branch. Every other common field is required.
- The walk keys its index by the bytes of a line, not by the id. A
  parent's entry counts as held only when the child holds the same
  bytes, so a changed entry is a dropped entry, and the reader needs no
  fault for two entries with one id and other bytes. A line of the
  parent that the child holds needs no new line check.
- The first walk read one object at a time and took about 270 µs for
  each commit. Three changes brought it to about 65 µs: the objects of
  a window of commits are read ahead in batches of 64; a folder
  listing is compared with the child's listing by its raw bytes, so
  only the folders that changed are decoded; and an open chunk whose
  content is a prefix of the child's chunk at the same path takes the
  child's lines with no check. The JSON printer now copies runs of
  plain bytes, which made it about five times faster; the reader
  prints each line again to check its canonical form.
- The mutation pass first counted every mutant as killed, because a
  test of `bench/run.exe` used a temporary folder as a folder outside
  every checkout, and the runner puts that folder inside the checkout
  (fixed in #165). The real pass then gave 76.2 %. Most survivors were
  in the fast paths, whose mutants change only the work. The id is no
  longer cut out of the line, and the second check of repeated keys is
  gone, because neither saved a clear amount. `Ledger.work` counts the
  waits for git, the folder listings decoded in full, the lines
  checked, and the lines matched by their bytes, so that a test can
  pin the work of a history. The fourth pass gave 97.8 %.
- The read-ahead takes a window of 193 commits, 3 × 64 + 1, where 64
  is the size of a batch of ids. At a multiple of 64, a window one
  commit longer or shorter needs the same number of batches, so no
  test could tell such a change. At 193 it needs one batch more or
  less, and a test pins the waits of a history of 194 parents. At
  100,000 entries, 193 and 256 measured the same: 7.3 to 8.0 s and
  113 G instructions for the verification, 0.88 s for the tip.
- After the fixes of the mutation pass, the verification of 100,000
  entries took 6.5 s and 80.8 G instructions. The growth of its words
  from 1,000 to 100,000 entries is 143.5, above 100, because the
  folder listing that each commit compares grows from about 20 folders
  to 256; it stops growing there. Its limit is 160.
- The tables of the reader take a random seed, because their keys are
  bytes of the ledger, which anyone with push access writes.
- A corrupt loose object at the ref reads as an object that the clone
  does not hold, because `git cat-file --batch` answers "missing". The
  command still stops with exit code 3.
- The help for a missing parent fetches with `--depth=2147483647` and
  no destination ref. `--unshallow` fails in a clone that is not
  shallow, and a destination ref is refused when the clone holds
  entries that it has not pushed.
- K is 50 by measurement, and the lead accepted it. The method: a
  ledger of 100,000 entries with one commit for each entry, made by
  `bench/generate.exe --ledger`, for each K; then `time -l` of
  `sinter ledger log` (the tip) and `sinter ledger verify` (the
  history), three runs each, interleaved, on an Apple M5 with git
  2.54.0. The load average was 12 to 26, so the wall times spread; the
  instruction counts of sinter are stable.

  | K | tip (s) | tip instructions | verify (s) | verify instructions | verify peak | objects |
  |---|---|---|---|---|---|---|
  | 25 | 2.2-2.6 | 14.6 G | 13.2-16.6 | 59.0 G | 350 MB | 67.7 MB |
  | 50 | 2.3-2.7 | 14.5 G | 15.3-16.5 | 60.0 G | 410 MB | 67.7 MB |
  | 100 | 1.7-3.7 | 14.4 G | 16.9-22.3 | 73.3 G | 414 MB | 68.7 MB |

  The tip hardly depends on K, because the checks of the 100,000 lines
  cost the most. The work of a verification grows with K, because each
  commit reads its open chunk again: the instruction counts of 25, 50,
  and 100 show it, and so do the object stores of a first run under
  another load, 72.7 MB at K = 200 and 96.0 MB at K = 400. Below 50 it
  gains almost nothing. A run for K = 1,000 needed about 14 GB of chunk
  content and was stopped.
- Each fast path of the walk was measured against a build without it,
  at K = 50 and 100,000 commits: the read-ahead of a window of commits
  gives 6.9 s against 9.5 s (best of four interleaved runs); the raw
  diff of the folder listing 62 G instructions against 185 G; the
  prefix path 62 G against 82 G. A read-ahead of the tip gave 1.15 s
  against 1.25 s for `ledger log`, so it was dropped.
- Left for later: the reader holds each object whole in memory, and
  the specification sets no limit on the size of a chunk. The fixture
  harness still reserves the name `ledger.jsonl`, and the form of a
  fixture ledger is not defined.
- The ledger bench needed `bench/**` and `CONTRIBUTING.md`, which the
  step did not hold. The lead amended the plan in #162.
- After the maintainer's rulings on the ledger as an event log (records
  `ledger-event-log` and `last-judgment-wins`), the step adds `seq` to
  every entry, orders by it, and checks that the entries of each
  commit hold each `seq` from 1 to n. The ruling came before #168
  merged, so no ledger and no writer existed and the format changed at
  no cost.
- The walk checks `seq` without a read of every line of the parent.
  The child passed the tip check, and the parent's entries are a
  subset of the child's by their bytes. So the parent holds 1 to n - k
  if and only if each of the k lines of the child that no line of the
  parent matches has a `seq` above n - k. The walk already knows these
  lines: the lines of the child's changed chunks whose ids the
  parent's changed chunks do not hold.
- The lead ruled that a `commitment-set` entry whose `csh` does not
  hold is read as usual, and the ledger is not broken: an older tool
  can compute another hash for a set that holds a key it does not know.
  The reader says whether the hash holds, in `csh_holds`. The critic's
  review fixed which set an approval takes when two entries share one
  `csh`: the latest below the approval whose hash holds.
- The lead ruled that the two record commits go first, and that the
  record `ledger-event-log` drops its citation of `ledger-layout`, so
  that every commit of the chain passes the check at the gate
  `merged`.
- The new module `Commitment_set` computes the commitment-set hash for
  the facts of a plan and for an entry of the ledger, so that the two
  cannot differ.
- Three tests that pin the work of a read moved by one folder listing,
  because `seq` changed every id and so the spread of the chunks over
  the folders. A test of a copied entry now expects the fault at the
  copy: the walk reads only the changed chunk, and the old expectation
  held only for one byte order of the two chunk names.
- The commitment-set hash repeats the effective scope of a step in
  each of its promises, so its bytes grow with promises times globs.
  The critic measured 21.5 s and 8.1 GB for `ledger log` on one line of
  552 KB. The lead ruled that the hash of a set holds only when those
  bytes are 1 MiB or shorter, and the reader adds up their length
  before it builds them. A hash that names each scope once goes to the
  maintainer later. The critic also found that the reader looked up
  the scope of each promise in every scope object; it now groups both
  by step once.
