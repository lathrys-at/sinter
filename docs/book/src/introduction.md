<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Introduction

Your project has a requirement: a user session ends after 30 minutes
without activity. A guide for users repeats this fact. Then the
requirement changes to 15 minutes, and nobody edits the guide.

The guide is now wrong. No compiler reports the mistake, because a
compiler does not read a guide. No test fails, because no test reads
the guide. You learn about the mistake when a user follows the guide
and gets a surprise.

Sinter is a command-line tool that reports this kind of mistake. You
add short lines to the text files of your repository. These lines give
names to parts of your text, and they say which text depends on which
other text. Sinter reads the lines, and it tells you which text can be
out of date.

Each of these lines is a *tag*. A tag is a line of text in your own
file. It is not a git tag, which is a name that git gives to a commit.

## How Sinter fits your work

In many projects, coding agents now write much of the code. A *coding
agent* is a program that writes and changes code from your
instructions. When agents write the code, your own work changes. You
decide what the software must do, and you write it down. You give the
work to agents. Then you check that the result still matches what you
decided.

Sinter is built for this way of work. Your requirements, your
decisions, and your plans are text in your repository. Sinter reports
where the work no longer agrees with them. An agent can say that its
work is done, but Sinter counts only what your repository shows.

## An example

For this example, you need git and Sinter. The section "Build" of the
[README](https://github.com/sinterworks/sinter#build) says how to build
Sinter. Make an empty folder, and run `git init -b main` in it. Run all
the commands below in that folder.

Sinter reads its settings from the file `sinter.toml` in the top folder
of the repository. These settings tell Sinter to read each Markdown
file:

```toml,file=sinter.toml
[scan]
packs.markdown.files = ["**/*.md"]
```

Write the requirement in the file `docs/requirements.md`:

```markdown,file=docs/requirements.md
# Requirements

## Session length
@req session-length v1
A session ends after 30 minutes without activity.
```

The line `@req session-length v1` is a tag. It says three things about
the text below it:

- The text is a requirement.
- The name of the requirement is `session-length`.
- The text is revision 1.

A *revision* is a number that you raise each time you change the
meaning of the text.

Write the guide in the file `docs/guide.md`:

```markdown,file=docs/guide.md
# User guide

## When a session ends
@cites session-length v1
Your session ends after 30 minutes without activity.
```

The tag `@cites session-length v1` says that the text below it depends
on revision 1 of the requirement.

Commit the three files:

```console,run
$ git add .
$ git commit --quiet --message "Add the requirement and the guide"
```

Now the requirement changes. Change the time to 15 minutes, change the
revision to 2, and commit the change:

```markdown,file=docs/requirements.md
# Requirements

## Session length
@req session-length v2
A session ends after 15 minutes without activity.
```

```console,run
$ git commit --quiet --all --message "Make sessions shorter"
```

Nobody edited the guide, so the guide still says 30 minutes. Run Sinter:

```console,run
$ sinter check
suspect: the @cites names v1, and req:session-length is at v2
 --> docs/guide.md:4:1
  |
4 | @cites session-length v1
  |                       ^^ names v1
  |
 ::: docs/requirements.md:4:1
  |
4 | @req session-length v2
  | ---------------------- now at v2
  |
help: check that the citation still holds, then pin it to the current revision
  |
4 - @cites session-length v1
4 + @cites session-length v2
  |

untraced: nothing satisfies req:session-length, and nothing verifies it
 --> docs/requirements.md:4:1
  |
4 | @req session-length v2
  |      ^^^^^^^^^^^^^^ nothing satisfies it, and nothing verifies it
  |
2 findings in 2 files; 1 has a fix
```

Each problem that Sinter reports is a *finding*. A finding names the
requirement as `req:session-length`, where `req` means a requirement.

The finding `suspect` says that the guide names revision 1 of the
requirement. The requirement is now at revision 2. Sinter cannot read
the meaning of the guide, so it does not say that the guide is wrong.
It tells you where to look. After you correct the guide, make the
change that the lines after `help` show.

The finding `untraced` says that no code and no test names the
requirement yet.

Correct the time in the guide, change the tag to revision 2, and commit
the change:

```markdown,file=docs/guide.md
# User guide

## When a session ends
@cites session-length v2
Your session ends after 15 minutes without activity.
```

```console,run
$ git commit --quiet --all --message "Correct the guide"
```

Run Sinter again:

```console,run
$ sinter check
untraced: nothing satisfies req:session-length, and nothing verifies it
 --> docs/requirements.md:4:1
  |
4 | @req session-length v2
  |      ^^^^^^^^^^^^^^ nothing satisfies it, and nothing verifies it
  |
1 finding in 1 file
```

The finding `suspect` is gone.
