# Sinter user manual
@plan sinter-user-manual@105d84
@scope docs/book/**, docs/decisions/**, test/**, .github/workflows/**, .gitignore, CONTRIBUTING.md
Write the user manual, the book "Using Sinter": a guide for new users
that adds detail step by step, and a full reference that a reader can
link to directly.

## Set up the book
@scope docs/book/**, docs/decisions/**, test/**, .github/workflows/**, .gitignore, CONTRIBUTING.md
Build the book with mdBook in CI, and write its introduction. Test the
examples, the internal links, and the notes on features that are not
built yet. Ask each step that changes a feature to update the book.

## Write the first guide chapters
@scope docs/book/**, test/**
Design the running project, and write the chapters that work on
markdown files alone: a first check, a traced requirement, Sinter in
an existing repository, and decision records.

## Write the reference
@scope docs/book/**, test/**
Write the pages for commands, settings, tags, findings, output forms,
exit codes, environment variables, packs, the ledger, and the words of
the book. Check that each of these has a page.

## Write the later guide chapters
@scope docs/book/**, test/**
Write the chapters on code, tests, plans, coding agents, approvals,
CI, rules, and language packs, with a note on each part that is not
built yet.
