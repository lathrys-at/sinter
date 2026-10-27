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
