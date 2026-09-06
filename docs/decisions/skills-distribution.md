<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Ship the Claude Code skills as a plugin marketplace in this repository
@decision skills-distribution
The Sinter repository is a Claude Code plugin marketplace with one plugin, `sinter`, whose skills are invoked as `/sinter:<skill>`.

## Context

Coding agents write most of Sinter, and Sinter's own method asks for
plans as `.plans/` files and decisions as `@decision` records. A set
of Claude Code skills can write those files from a plan that the user
approved in plan mode. The skills must reach two groups: contributors
to this repository, and users of Sinter in other repositories.

Claude Code offers three delivery paths. A project can commit skills
under `.claude/skills/`, which only people who clone the project get.
A repository can be a plugin marketplace, which any user adds with one
command and which carries a version. And `sinter init` (design notes
section 11.17) will one day install integration files into a target
repository. Claude Code has no hook that fires when a plan is
approved, and the path of the plan file is not documented, so a skill
must work from the approved plan as it stands in the conversation.

## Decision

The repository root holds `.claude-plugin/marketplace.json`, which
names one plugin with source `./plugins/sinter`. The plugin holds
`.claude-plugin/plugin.json` and `skills/<name>/SKILL.md` for each
skill. Users install it with `/plugin marketplace add lathrys-at/sinter`
and `/plugin install sinter@sinter`, and invoke a skill as
`/sinter:<name>`. The plugin's version tracks the tool's version.

This repository uses its own pack: `.claude/settings.json` declares
the marketplace and enables the plugin. When `sinter init` exists, it
installs the same pack into a target repository, so the skills have
one source and two delivery paths.

The skills are licensed under Apache-2.0, like the rest of the
integration files.

## Alternatives considered

- **Project-level `.claude/skills/` only** — rejected. Only people who
  clone this repository would get the skills, and the invocation names
  would change later when the skills moved into a plugin.
- **The marketplace plus `.claude/skills/` symlinks into the plugin**
  — rejected. Two delivery paths in one repository double the
  maintenance, and symlinks in git behave differently across
  platforms. Local iteration on a skill works without them: a
  contributor runs `/plugin marketplace add ./` once.
- **Skills embedded in the `sinter` binary and installed by
  `sinter init` only** — deferred, not rejected. It becomes the
  second delivery path when `init` exists, but a user who has not
  installed Sinter can still get the skills from the marketplace.

## Consequences

Users need one marketplace command before the skills appear. The
plugin version must be bumped with each tool release. Contributors
edit skills under `plugins/sinter/skills/`, and `.claude/settings.json`
points at the GitHub source, so a fresh session in this repository
uses the pushed version of the pack, not the working tree.
