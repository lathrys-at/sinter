# Fixes from the review of 2026-11
@plan review-fixes@3ba194
@scope lib/**, bin/**, bridge/**, test/**, bench/**, spec/**, docs/**
Fix the 34 defects that the review of `main` at 39ab7b8 found
(issue gh/158). Each defect has a failing test on the branch
`xfail/cloud-review-2026-11`; each step takes the tests of its defects
into its own commits and makes them pass.

## Correct the messages of the manifest
@scope lib/**, bridge/**, test/**, spec/**
Keep a quoted name that holds "; " whole in a manifest error, name the
last header table on the path of a dotted key, and never suggest a key
of `[scan.packs.markdown]` that markdown refuses.

## Correct the findings
@scope lib/**, bin/**, test/**, spec/**, docs/**
Report `stale-ack`; report no `untraced` for a cited declaration whose
slug is declared twice; give one `renamed-step` for each lost slug;
make the `unbumped` fix at the largest revision repair its finding;
give no `typo-tag` fix that writes `@ack`; count the built-in members
of `paths.exempt` alike on both sides of `config-changed`; and keep a
carriage return with no line feed after it in its line.

## Make the tests independent of the machine
@scope test/**, bench/**
Let the suite pass when it runs as root or without `/usr/bin/time`,
and bound the timing tests by counted work, not by seconds.

## Bound the costs
@scope lib/**, bin/**, test/**, bench/**, spec/**
Keep the cost of an id pattern, of `delivery-without-change`, of many
declared items, steps, declarations, and promises, of a chain of
`@supersedes`, and of many related places in proportion to the input.

## Stop the crashes and give the right exit codes
@scope lib/**, bin/**, bridge/**, test/**, spec/**
Refuse a query that nests too deep, keep a grammar loadable after many
reloads, read a manifest whose path is not UTF-8 or that a pipe gives,
and exit with 3 for a full disk and for a current folder that is gone.

## Close the security gaps
@scope lib/**, bin/**, test/**, spec/**, docs/**
Refuse a manifest that is a symbolic link, without a race between the
check and the read; leave a file behind a linked folder out of the
file set; never run a `git` of a relative entry of `PATH`; and read a
delivery line in time and memory in proportion to its length.

## Make the diff independent of git's settings
@scope lib/**, test/**, spec/**, docs/**
Compare a tracked file as an untracked file whatever the age of the
index; let no attribute or setting make a text file binary; answer for
a repository under a folder with a colon and for an untracked path
that git refuses; give a deleted path the run of a deletion; let the
tree key hold the files as they are on disk; order the commits of the
change parents first; and read a delivery line after leading spaces.
