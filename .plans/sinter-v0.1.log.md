# Journal: Sinter v0.1

## Check Sinter with Sinter

The manifest has no SPDX header. CONTRIBUTING.md says that a file at
the repository root carries none, and the annotation `**` of
REUSE.toml gives it its license.

`plan.shared` holds five root files more than the draft:
`.ocamlformat`, `DCO`, `LICENSE`, `LICENSE-SPEC`, and `NOTICE`. No
plan scope holds them, so a change to one of them would be
`unmapped-work` once diff mode reports that class.

The requirements tag spec/ledger.md, the shortest specification. Its
rules have no code yet, so each requirement is `uncovered` until the
ledger commands exist. spec/jsonl.md has code today, but most of it is
field tables of records that nothing writes yet.

The tag line stands alone as the first paragraph of a requirement's
section, so a requirement has no `desc`. The other form joined the tag
line to the rule's first paragraph: `desc` was then that whole
paragraph, and GitHub showed the tag inside the paragraph.

The headings 2.3 and 11.3 carry no tag. Their text states no rule:
2.3 says what the ledger is, and 11.3 lists the consequences of the
rules of 11.1. Each heading ends the extent of the requirement before
it. Section 12 (`pin`) has no tag, because it is deferred.

The CI step runs in the Linux leg of the `build` job, after "Test",
where the binary is already built. The checkout fetches the whole
history on both legs, because it packs to 2.4 MiB. The expression
`matrix.os == 'ubuntu-latest' && 0 || 1`, proposed to fetch it on
Linux only, gives 1 on every leg: 0 is false in GitHub expressions.

## Measure and improve the performance of scan and check

- The step's scope did not hold `bench/`, `CONTRIBUTING.md`, or
  `.github/workflows/`, which the design of the step names. PR #97
  widened it.
- The budgets file is TOML, read with Sinter's own TOML reader, so that
  it carries its license header and needs no entry in `REUSE.toml`.
- The generator is OCaml and makes its trees with `git fast-import`.
  Its file shapes follow the Python script of the research, but the
  trees differ, because the two random generators differ.
- The first order of the generator wrote the uncommitted files before
  it refreshed the index. Their entries then held the time of the
  checkout, in the same second as the index, and `git status` wrote
  the index again. The generator now refreshes the index first.
- The index of `Facts.residue` first held a key for every declaration
  and every edge: scan at 100,000 declarations rose from 688 to 716
  MiB. It now holds only the keys that a promise names (695 MiB), and
  `Facts.discharge` refuses a plan, a step, or a promise of other
  facts, and does not fall back to a list scan.
- At 100,000 declarations, the five indexes halve the instructions:
  scan 394 to 195 G, check 370 to 180 G (macOS). At 10,000 declarations
  the gain is 4 percent.
- On the ubuntu-26.04 runners, `perf` counts no instructions ("The
  instructions:u event is not supported"), and the macOS runners give
  no count from `time -l`.
- The growth budget first divided instruction counts of whole runs. No
  CI runner counts instructions, and a whole-run ratio hid the slow
  step at 10,000 declarations. The budget divides the words that each
  phase allocates: records grew ×28.5 before the fixes, ×10.4 after.
- The first trees held no retired decision and no `@ack`, so the code
  of `block_hash` and `acked` never ran in the benchmark. The generator
  now retires 3 decisions in 50 and acks their citations in four ways.
  The phase findings then grows ×13.06 without fixes 4 and 5, and
  ×10.95 with them. The lookup of `block_hash` alone allocates nothing,
  so a regression of it alone would not show in the words.
- Left for later: `git diff` with Sinter's options rewrites a stale
  `.git/index` (found in the research). The benchmark of Sinter itself
  reads `bench/sinter-self.toml`, not the root `sinter.toml`.

## Close the gaps of diff mode

- The rulings left some details open. The lead ruled these:
  - A hunk with no added line has `ecol = 1`.
  - A binary hunk has `added = 0` and `removed = 0`.
  - The mechanical repairs also hold the fixes of `retired` and
    `typo-tag`, because each fix that Sinter prints is on the list.
  - The fix of `renamed` writes a revision only when the edge carries
    one.
- Plain `check` reports `unplanned-change` and `config-changed`, so
  hunk and tombstone facts exist in every run that reads the base, not
  in diff mode only. `scan` does not print them yet.
- Other details: an added empty file gives `hunk:<path>:1-1`.
  `renamed` counts its one tombstone and its one new declaration
  across all kinds, and then requires one kind. The spaces and tabs
  after a section number go with it, and each heading inside an
  extent loses its number.
- The diff compares the file sets of manifest section 7.3, so a file
  that git ignores is never an added file.
- Left for later:
  - Git reads `GIT_NO_LAZY_FETCH` only from version 2.44 on, by
    memory and not checked, while the code needs 2.30.
  - A clean filter or `core.autocrlf` can make a file on disk differ
    from its blob when git shows no change.
  - Outside sections 11.3 and 12.7, the design notes still use old
    names of classes and gates, for example `law-touched` and `pr`.
- The diff compares a file as git stores it, after its clean filter
  and its end-of-line conversion. A comparison of raw bytes would show
  every line changed in a checkout with CRLF line ends, and every Git
  LFS file changed on every run. The cost is wrong positions in a file
  whose filter changes its number of lines.
- Details of `unplanned-change` and `config-changed`, fixed before
  their steps: a hunk with no line is not a mechanical repair; plan
  files of either tree are exempt; the detail of `unplanned-change`;
  `config-changed` ignores historical paths; what counts on the base
  side; the line of an entry; the form of a tier change. Runner
  settings wait for packs with descriptors.
- A mechanical repair must write exactly the tag that Sinter's fix
  writes, checked against the facts; only a bump of a declaration can
  write any higher revision. A check of the shape alone would let any
  retarget of a citation pass without a plan step.

## Check a diff

- The diff is way C4 of the research: a copy of the index with the
  assume-unchanged and skip-worktree flags cleared, `git add -N` of
  the untracked files, and `git diff` with a temporary object folder
  that holds the empty blob. Git still sets the time of
  `.git/sharedindex.<id>` in a repository with a split index, because
  every read of a split index does so, the old reads included. The
  reads of the index pass `-c core.fsmonitor=false`, because with
  `core.fsmonitor=true` they started the monitor daemon in `.git`.
- A file that the diff finds binary has one hunk with no lines, so
  each position of the base in it, or in a deleted file, has no place
  in the working tree. Diff mode reports the findings of such a file
  again.
- `unbumped` compares a declaration with every declaration of the
  base that has its slug. It is unchanged when one of them has its
  kind and its extent hash. With two declarations of the slug at the
  base, this departs from the wording of `changed` in algebra section
  8.1. It is bumped when one has a lower revision, as `bumped` reads.
  The fix takes the highest revision plus 1.
- `renamed` needs exactly one tombstone of a declaration with the slug
  of the edge. Two tombstones of one slug leave the edge `dangling`.
- Tree mode first read the whole base into a second set of facts. On
  the tree of 10,000 declarations, the peak memory of check rose from
  66.7 to 85.3 MiB on macOS. A file whose document the base reuses has
  the same facts in both trees, so tree mode now builds facts only for
  the files that differ, and the git part of the base read runs before
  the parse. The peak fell to 71.3 MiB. In tree mode, those facts
  count in the phase `findings`: their size follows the number of
  changed files, not the size of the tree, and as a phase of their
  own they failed the growth limit (19.1). `base-facts` and
  `base-findings` are phases of `check --diff`, where they hold the
  whole base.
- `bench/budgets.toml` gives `check-diff` a growth limit only. Its
  memory number waits for the first measure of the CI job on Linux.
