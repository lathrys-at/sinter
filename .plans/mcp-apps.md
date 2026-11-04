# Sinter in MCP apps
@plan mcp-apps@17ea99
@scope spec/**, docs/**, README.md, THIRD_PARTY.md, REUSE.toml, LICENSES/**, lib/**, bin/**, test/**, .github/workflows/**
Serve Sinter's results over the Model Context Protocol: text tools for
every MCP client, and pages that show plans, findings, and the ledger
in the clients that show MCP Apps. The tools and the pages only read;
none writes a file, the ledger, or a git object.

## Move the MCP server from the roadmap to this plan
@scope docs/roadmap.md
Replace the roadmap item `sinter serve --mcp` with a pointer to this
plan. Add as roadmap items: a static HTML report of the same records;
a cache of the ledger's folds, in memory for `sinter serve` and on
disk, that can always be discarded and built again; and the state of
each step (on deck, in progress, done) in the plans view.

## Run scan and check in the serve loop
@scope spec/**, docs/**, lib/**, bin/**, test/**
Give the serve loop the operations `scan` and `check`, with one
implementation for the command line and the loop (record
`serve-mode`).

## Accept -C on every command
@scope docs/**, lib/**, bin/**, test/**
Let every command take `-C <dir>` and run as if it started in that
folder, as design notes section 11.1 says.

## Serve the results as MCP tools
@scope spec/**, docs/**, README.md, lib/**, bin/**, test/**
@decision mcp-adapter
Add `sinter serve --mcp`: an MCP server over standard input and
output that speaks the protocol revision 2026-07-28 only. The tools
`sinter_check` and `sinter_scan` give the text of the commands with
those names, and `sinter_plans` gives one line for each step of each
plan. One server serves one repository. Test whole exchanges of
messages through the binary, byte for byte.

## Give the views their data in the JSON lines
@scope spec/**, docs/**, lib/**, bin/**, test/**
Add to `spec/jsonl.md` the fields that the views need: the HEAD
commit, whether the working tree has uncommitted changes, and the time
of the last fetch of the ledger in the index record, and on each
finding the steps whose scope covers it.

## Show the plans in a view
@scope spec/**, docs/**, THIRD_PARTY.md, REUSE.toml, LICENSES/**, lib/**, bin/**, test/**, .github/workflows/**
@decision app-views
Add the page `ui://sinter/view`, with the official MCP Apps library
inside it, and the plans view: plans, steps, and promises, with the
commit, the state of the working tree, the ledger it read, and a
Refresh button. The page puts repository text on screen only as plain
text. Test the page with `node --test` in CI, and by hand in Claude
Desktop and VS Code. Revise design notes section 9.1.

## Show the findings in a view
@scope docs/**, lib/**, bin/**, test/**
Add the findings view: each finding with its class, tier, detail,
place, related places, and fixes, grouped by step.

## Show the working trees live
@scope spec/**, docs/**, lib/**, bin/**, test/**
@decision live-working-trees
Let a view show every working tree of the repository side by side.
The server lists them with `git worktree list --porcelain`, and while
a view is open, a background thread checks each tree's HEAD, index,
and `git status` every few seconds and runs Sinter again for a tree
that changed.

## Show the ledger and the inbox in a view
@scope spec/**, docs/**, lib/**, bin/**, test/**
Add the ledger view: approvals that are due, live declines, plans
that cannot close, and claims, each with the command that resolves
it. It needs the steps "Check approvals" and "Check claims" of the
ledger plan, and a `sinter inbox` command that no plan holds yet.
