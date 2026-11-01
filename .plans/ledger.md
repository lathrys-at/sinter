# The ledger
@plan ledger@b74038
@scope spec/**, docs/**, lib/**, bin/**, test/**, bench/**, plugins/**, .claude-plugin/**, .github/workflows/**, CLAUDE.md, README.md, CONTRIBUTING.md
Read and write the ledger: approvals, declines, and closings, the job
on the default branch that records deliveries, plans, and closings,
and plans that live in the ledger without a file.

## Read and verify the ledger
@scope spec/**, docs/**, lib/**, bin/**, test/**, bench/**, CONTRIBUTING.md
@decision ledger-layout
Read `refs/sinter/ledger` in closed chunks, check each entry by its
canonical bytes and its id, verify the history entry by entry, report
`ledger-broken`, and add `sinter ledger verify` and `sinter ledger log`.

## Check approvals
@scope spec/**, docs/**, lib/**, bin/**, test/**
Give the checks the approvals, the declines, the closings, and the
`delivered` entries: the classes `unapproved-req`,
`unapproved-design`, `awaiting-approval`, `unapproved-plan`, and
`declined`, open and closed plans, effective supersession, and the
steps that a delivery makes done.

## Check claims
@scope spec/**, docs/**, lib/**, bin/**, test/**
Give the checks the claims: the classes `waiting-on` and
`branch-overlap`, and the claims that `dangling` and
`promise-collision` read.

## Record approvals, declines, and closings
@scope spec/**, docs/**, lib/**, bin/**, test/**, plugins/**, .claude-plugin/**
@decision approval-commands
Add `sinter decline`, `sinter ledger abandon`, `sinter ledger repair`,
`sinter ledger show`, `sinter ledger fetch`, and `sinter ledger push`
with `--replay`, and the machinery that writes an entry without
touching the working tree. Each command that writes the ledger needs
a terminal and refuses under an agent, and `--dry-run` writes nothing.

## Approve
@scope spec/**, docs/**, lib/**, bin/**, test/**, plugins/**, .claude-plugin/**
Add `sinter approve`: show the delta since the last approval, ask for
each subject, refuse text that HEAD does not hold, and write the
approval with the commitment set of a plan.

## Run the job on the default branch
@scope spec/**, docs/**, lib/**, bin/**, test/**, .github/workflows/**
@decision ledger-plans
Add the job that runs at each push to the default branch, in CI or by
hand. It reads the commits from the head of its last entry to the
current head, imports the evidence of its run, and writes the
`delivered`, `plan`, and `completed` entries.

## Record a plan without a file
@scope spec/**, docs/**, lib/**, bin/**, test/**, plugins/**, .claude-plugin/**, CLAUDE.md, README.md, CONTRIBUTING.md
@decision ledger-only-plans
Let `sinter approve <draft>` record a plan that has no file, read each
plan from the tree first and then from the ledger, make the checks of
the recording command, publish the format of a draft, and revise the
record `agent-statements` and the thesis of the design notes to name
the ledger as the second channel for a statement.
