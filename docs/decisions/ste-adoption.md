<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Write all project text in Simplified Technical English
@decision ste-adoption
Every text in the repository, and the tool's own output, follows Simplified Technical English (ASD-STE100) in the style of Simple English Wikipedia.

## Context

Coding agents write most of Sinter's text. Agent prose has three
common faults: invented jargon, several ideas compressed into one
phrase, and missing context. The readers are the people who use
Sinter or contribute to it, not the person who runs the agent. Those
readers do not share the agent's context.

## Decision

All text follows the rules in the "Writing" section of
CONTRIBUTING.md. In short: short sentences with one idea each; active
voice and simple tenses; one word for one meaning; no invented terms,
and a definition at first use for a necessary technical term; one
clear referent for every pronoun; context before detail; lists for
sequences and tables for enumerable facts; no notes that explain why
a sentence or a file exists; no prose that opens a document by
explaining what the document is.

The rules apply to documentation, specifications, code comments,
commit messages, the tool's output, and an agent's replies to the
person it works with. Text reproduced from elsewhere — license
texts, the DCO, quoted standards — stays verbatim.

Reviewers check text against these rules with the `asd-ste100` skill.
This record is the origin for a future `ste-docs` rule (design notes
section 7).

## Alternatives considered

None were put forward.

## Consequences

Every document costs more words than a dense draft, because a clear
explanation is longer than a compressed one. Reviews name the rule a
sentence breaks. A rule in the manifest can later make the check
automatic for governed documents.
