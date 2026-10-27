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
