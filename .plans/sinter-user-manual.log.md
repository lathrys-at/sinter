# Journal: Sinter user manual

## Set up the book

- The test program is `test/book.ml`, and `test/book.mli` states its
  rules. The lead ruled on the details that the brief left open: a
  fence in a list or a block quote fails; a command's output is its
  standard output and standard error as one stream; each `$ ` line
  runs in its own shell, so a line that starts with `cd` or `export`,
  or that only sets variables, fails; the commands get `LC_ALL=C`.
- `sinter check` stops with exit 3 in a repository that has no commit
  on `main`. It prints `error: no branch 'main' exists here or on
  origin` and `= help: fetch it with git fetch origin
  main:refs/remotes/origin/main, or set 'default-branch' in sinter.toml
  to the name of the default branch`. So the Introduction commits
  before its first `sinter check`. The later design of `sinter init`
  needs this fact.
- `book.toml` sets `create-missing = false`. Without it, `mdbook build`
  writes a missing chapter as an empty file and passes.
- The rule for heading ids comes from the output of mdBook 0.5.4 on
  test pages. An id from `{#id}` does not count as a use of that id, so
  a later heading can get the same id.
- Left for the step that adds the first listing: `sinter.toml` reads
  `**/*.md`, so a Markdown file under `docs/book/listings/` holds real
  tags for Sinter's check of this repository. dune also leaves out a
  folder whose name starts with a dot, so a listing with `.plans/`
  needs `(dirs :standard .plans)`.
- Left for the step that writes the first chapters: a list of what the
  book holds, at the end of the Introduction. The lead ruled that this
  step leaves the list out, so that the page states only what is true
  now.
