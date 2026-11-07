<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Write the user manual as a tested book
@decision user-manual
The user manual is a book, "Using Sinter", built with mdBook from `docs/book/`, that teaches new users with one running project and ends with a reference part, and a test runs its examples.

## Context

Sinter had a short README, design notes, and specifications, and no text
for a person who wants to use the tool. A new user reads to solve a
problem. A pro user looks up one exact fact. Many features are not built
yet, and each step changes the output of the tool.

## Decision

- The book teaches a developer with an existing repository, step by step,
  in the style of the Rust book. Its chapters share one running project.
- A reference part ends the book. Its pages have fixed names, so that a
  reader can link to them directly.
- mdBook builds the book from `docs/book/`. CI builds it on each pull
  request. Publishing waits for the maintainer.
- The book describes the finished tool, and a note marks each part that is
  not built. Text with no note is true of the current build.
- A small test program in `test/` writes the files and runs the commands of
  each page, and compares the output byte for byte. It skips a block that a
  note marks. It also checks the internal links.
- A reference page holds its tags in an HTML comment (record
  `markdown-comment-tags`). A guide chapter holds no tag.

## Alternatives considered

- **Reference pages first, and guides later.** Not chosen: a new reader gets
  no way in.
- **One manual for people and one for coding agents.** Not chosen: two texts
  can disagree, and clear text serves both readers.
- **Plain Markdown on GitHub, with no site.** Not chosen: it has no search and
  no sidebar, and a reference part needs both.
- **MkDocs or Docusaurus.** Not chosen: they need Python or Node, and mdBook
  meets each need.
- **Describe only what works today.** Not chosen: the story stops early, and
  the project gets no early view of how the finished tool reads.
- **Describe the finished tool with no notes, and publish at the release.** Not
  chosen: the repository then holds text that is partly untrue, with no way to
  tell which part.
- **`ocaml-mdx` to run the examples.** Not chosen: it adds a development
  dependency with several packages of its own.
- **Copy examples by hand from the case folders, or check them by hand.** Not
  chosen: nothing then keeps the text correct.
- **Independent chapters, with a new example in each.** Not chosen: a reader
  gets no view of how the parts of Sinter work together.

## Consequences

Each change to a feature also updates the book. A person must still catch a note
that a change leaves behind. The writing of the book shows where the design is
hard to explain, while the design can still change.
