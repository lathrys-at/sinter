# The ledger
@plan ledger@b74038
@scope spec/**, docs/**, lib/**, bin/**, test/**, plugins/**, .claude-plugin/**, .github/workflows/**, CLAUDE.md, README.md, CONTRIBUTING.md
Read and write the ledger: a person's approvals and closings, the job
on the default branch that records deliveries, plans, and closings,
and plans that live in the ledger without a file.

## Read the ledger
@scope spec/**, docs/**, lib/**, bin/**, test/**
Read `refs/sinter/ledger`, verify its entries, and give the checks the
approvals, the `delivered` entries, and the `plan` entries that they
read.

## Write a person's entries
@scope spec/**, docs/**, lib/**, bin/**, test/**, plugins/**, .claude-plugin/**
Add `sinter approve`, `sinter decline`, `sinter ledger abandon`, and
`sinter ledger show`. Each command that writes the ledger refuses when
an agent marker is set, and `--dry-run` writes nothing.

## Run the job on the default branch
@scope spec/**, docs/**, lib/**, bin/**, test/**, .github/workflows/**
@decision ledger-plans
Add the job that runs at each push to the default branch, in CI or by
a person's hand. It reads the commits from the head of its last entry
to the current head, imports the evidence of its run, and writes the
`delivered`, `plan`, and `completed` entries.

## Record a plan without a file
@scope spec/**, docs/**, lib/**, bin/**, test/**, plugins/**, .claude-plugin/**, CLAUDE.md, README.md, CONTRIBUTING.md
@decision ledger-only-plans
Let `sinter approve <draft>` record a plan that has no file, read each
plan from the tree first and then from the ledger, make the checks of
the recording command, publish the format of a draft, and revise the
record `agent-statements` and the thesis of the design notes to name
the ledger as the second channel for a statement.
