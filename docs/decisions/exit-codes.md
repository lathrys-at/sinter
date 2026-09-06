<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# One set of exit codes for every command
@decision exit-codes
Every `sinter` command uses the same five exit codes: 0 success, 1 findings present, 2 usage error, 3 environment error, 4 refused.

## Context

Sinter runs in places that read the exit code and nothing else: a
continuous-integration job, a git hook, and an editor hook. Each of
those places must tell three cases apart. The tool ran and found
nothing. The tool ran and found something the caller must look at.
The tool did not run.

A caller cannot tell those cases apart from the output alone. The
output of a command changes as the command grows, and a hook must
decide in one comparison. Sinter also has many commands, and a caller
that learns one set of codes should not have to learn a second set
for the next command.

## Decision

Every command uses these codes.

| code | meaning |
|---|---|
| 0 | the command succeeded and reported no finding |
| 1 | the command succeeded and reported at least one finding |
| 2 | the command line is wrong |
| 3 | the command could not run in this environment |
| 4 | the command refused to act |

Code 1 means a fact about the repository, not a fault of the run. The
command did its work. A caller that wants "did it run" tests for a
code above 1.

Code 2 covers an unknown option, a missing argument, an argument of
the wrong shape, and two options that exclude each other. The
argument parser also produces this code, so a command must map the
parser's own code onto 2.

Code 3 covers everything outside the command line that stops the
work: a file that does not exist, a file the process cannot read, a
grammar that does not load, a query that does not parse, a manifest
that is not valid, a pack whose hash does not match, and git that is
not available.

Code 4 marks a refusal. A command refuses when it needs a human
judgment that the current context cannot give: an approval asked for
without a terminal, or asked for by an agent.

A command that fails writes one line to standard error. The line
starts with `sinter: `. It says what is wrong, and, when the caller
can act, what to do.

## Alternatives considered

- **Two codes, 0 for success and 1 for any failure** — rejected. A
  hook cannot then tell a repository with findings from a broken
  install, so a missing grammar would look like a real finding and
  block a commit for the wrong reason.
- **The codes of `sysexits.h`, such as 64 for a usage error and 78
  for a configuration error** — rejected. That set has no code for
  "the tool ran and found something", which is the case Sinter needs
  most. It is also not used by the tools Sinter sits beside, so it
  would surprise the reader of a hook script.
- **One code for each class of finding** — rejected. The set of
  finding classes grows with every rule, and a caller would have to
  change its script each time. The classes belong in the output,
  where a caller can filter them.
- **Follow the exit code of the underlying tool, such as git** —
  rejected. Sinter calls several tools, and their codes disagree with
  each other.

## Consequences

A caller can gate on the exit code alone: `0` and `1` mean the run
was valid, and anything above `1` means it was not. The help text of
`sinter` lists the five codes, so the set is part of the surface that
users depend on, and a change to it is a change to the surface.

Every command must map an error onto one of the five codes, even when
the distinction is fine. The line between code 2 and code 3 is fixed
by one test: an argument the parser can reject without touching the
file system is a usage error, and everything else is an environment
error. So a `--query` option given together with `--tree` is code 2,
and a `--query` file that does not exist is code 3.

Code 1 is unused until the first command reports findings. The `parse`
command reports captures, not findings, so it exits 0 or above 1.

The five cover the outcomes a command designs for. A fault of the tool
itself is outside them: an exception that a command does not catch
reaches the argument parser, which reports its own internal-error
code, 125. That code stays as it is. It marks a bug in the tool, not
a state of the repository, and a bug must be loud and distinct from
the five codes above. A user who sees it reports it.
