<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Keep a repository's own law in rule files
@decision rule-files
A rule that a repository writes, and a finding class that a repository defines, lives in a rule file that holds both its implementation and its reason, not in the manifest.

## Context

Besides the built-in finding classes, a repository can state law of
its own: a rule with a trigger and a check, or a finding class with an
expression. Such law needs a strict machine format, which favours the
manifest. It also needs its reason beside it, so that a reader sees
why the law exists and a change to the reason shows in review. The
manifest is the wrong place for a reason, and a tag line holds only
one target and prose.

## Decision

- A rule file is a markdown file with TOML front matter between two
  `+++` lines. The front matter holds the implementation. The text
  below holds the reason.
- `@rule <slug> vN` declares the rule. Its extent is the whole file,
  front matter included, so a change to the implementation or to the
  reason owes a new revision.
- A rule is retired as a decision is. A rule may cite the decision
  that it rests on.
- A finding class that a repository defines is the same kind of file,
  with its expression in the front matter.
- The manifest keeps only the tiers of the built-in finding classes and
  the rollout cap. It has no table of rules and no table of findings.
- The front matter is read by the same rules as the manifest
  (`spec/manifest.md`). Where rule files live, how many rules one file
  holds, how a rule is approved, and what a rule's scope means are
  settled with the work on rules.

## Alternatives considered

- **Rules and finding classes as tables in the manifest**, as the
  design notes first sketched. Not chosen: the law would sit apart
  from its reason, and a reviewer of a manifest change would see the
  expression without the argument for it.
- **Rule tags in decision records**, so that a decision carries the
  rule it earned. Not chosen: a tag line holds one target and prose,
  and cannot hold a machine format of two expressions.

## Consequences

Each piece of a repository's law is one file that a reader can open
and understand by itself, and its reason is governed by the same
revision discipline as its implementation. The manifest stays small.
The rules work must still decide the location, the approval, and the
scope of rule files before any rule runs.
