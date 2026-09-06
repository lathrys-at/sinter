<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Ship the Claude Code skills as a plugin marketplace in this repository
@decision skills-distribution
The Sinter repository is a Claude Code plugin marketplace with one plugin, `sinter`, whose skills a user invokes as `/sinter:<skill>`.

## Context

Coding agents write most of Sinter. Sinter's own method asks for
plans as `.plans/` files and for decisions as `@decision` records. A
set of Claude Code skills can write those files from a plan that the
user approved in plan mode. The skills must reach two groups:
contributors to this repository, and users of Sinter in other
repositories.

Claude Code offers three delivery paths:

1. A project commits the skills under `.claude/skills/`. Only people
   who clone the project get them.
2. A repository is a plugin marketplace. Any user adds the
   marketplace with one command, and the marketplace carries a
   version.
3. `sinter init` (design notes section 11.17) installs integration
   files into a target repository. This command does not exist yet.

Claude Code has no hook that fires on the approval of a plan. Claude
Code also does not document the path of the plan file. So a skill
must work from the approved plan as the conversation shows it.

## Decision

The repository root holds `.claude-plugin/marketplace.json`. This
file names one plugin with the source `./plugins/sinter`. The plugin
holds `.claude-plugin/plugin.json` and one `skills/<name>/SKILL.md`
file for each skill. A user installs the plugin with two commands:
`/plugin marketplace add lathrys-at/sinter` and
`/plugin install sinter@sinter`. The user then invokes a skill as
`/sinter:<name>`. The plugin's version tracks the tool's version.

This repository uses its own skill pack. The skill pack is the
marketplace file, the plugin, and the `.claude/settings.json` file
that declares the marketplace and enables the plugin. When
`sinter init` exists, it installs the same pack into a target
repository. The skills then have one source and two delivery paths.

The skills use the Apache-2.0 license, like the rest of the
integration files.

## Alternatives considered

- **Project-level `.claude/skills/` only** — rejected. Only people
  who clone this repository get the skills. The invocation names also
  change later, when the skills move into a plugin.
- **The marketplace plus `.claude/skills/` symlinks into the plugin**
  — rejected. Two delivery paths in one repository double the
  maintenance. Symlinks in git also behave differently across
  platforms. A contributor can work on a skill without symlinks: the
  contributor runs `/plugin marketplace add ./` one time.
- **Skills embedded in the `sinter` binary and installed by
  `sinter init` only** — deferred, not rejected. This path becomes
  the second delivery path when `init` exists. A user who does not
  install Sinter can still get the skills from the marketplace.

## Consequences

A user runs one marketplace command before the skills appear. Each
tool release needs a new plugin version. Contributors edit the skills
under `plugins/sinter/skills/`. The file `.claude/settings.json`
points at the GitHub source. So a fresh session in this repository
uses the pushed version of the pack, not the working tree.

Claude Code caches an installed plugin by its version. A change to a
skill reaches users only after the plugin version in
`plugins/sinter/.claude-plugin/plugin.json` and in
`.claude-plugin/marketplace.json` increases. So every change to a
skill bumps the plugin version.
