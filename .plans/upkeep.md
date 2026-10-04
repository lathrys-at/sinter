# Upkeep: small fixes from the assessment
@plan upkeep
@scope .github/workflows/**, test/**, bin/**, lib/dune, lib/version.mli, spec/**, docs/versioning.md, docs/roadmap.md, docs/licensing-setup.md, docs/design-notes.md, CONTRIBUTING.md, README.md, THIRD_PARTY.md, plugins/**, .claude-plugin/**, .plans/**
Make the small fixes that the assessment of 2026-10-03 found in CI,
in the measuring tools, in the command line, in the specifications,
and in the documents.

## Pin the CI runner images
@scope .github/workflows/**
Name the runner images in every job and put the image in the key of
every cache, so that a new image is a reviewed change. Skip the opam
setup when the cache holds the switch. This step is due before
2026-10-19, when `ubuntu-latest` moves to Ubuntu 26.

## Guard the standard descriptors
@scope bin/**, test/**
Open `/dev/null` on each closed standard descriptor before any engine
starts, so that no file that the tool opens takes descriptor 1. Report
a closed standard output as an environment error, and a failed read
of standard input with a message of its own. Add the tests that fail
before the fix.

## Shorten the mutation pass and raise the coverage minimum
@scope test/run-mutants.sh, .github/workflows/**, CONTRIBUTING.md
Stop each run of the suite at its first failing test, and measure a
full pass before and after. Fix the seed of the property tests in the
coverage step, and raise the coverage minimum from 92 to 94.

## Describe only tool tags in the version
@scope lib/dune, lib/version.mli, docs/versioning.md, test/**
Make `git describe` match only the tags of the tool, so that a tag of
the specifications never appears as the tool's version.

## Close small gaps in the specifications
@scope spec/**, test/**
State that a decision record can be edited with a revision bump.
Correct the `pin` example of the ledger. Settle the markdown cases that
the assessment found: text before the first heading, the headings that
bound a section, the place of a status tag, the text of a heading,
the built-in saved definitions, and the length of a hash. Add a test
that every JSON example in `spec/` is canonical.

## Correct the contributor documents
@scope CONTRIBUTING.md, README.md, docs/roadmap.md, docs/licensing-setup.md, .github/workflows/**
State each fact of "Mutation testing" as a rule, without the history
of one branch and without stale numbers. Remove the delivered entry
from the roadmap. Keep only the pack part of the licensing brief, as
reference text. Correct the build instructions and the comment on the
mutation minimum.

## Quote tags safely and correct the prior art
@scope plugins/**, .claude-plugin/**, docs/design-notes.md
Tell the two skills to quote a tag line on GitHub only inside a fenced
code block, and raise the version of the skill pack. Correct the
paragraph on prior art in design notes section 1.
