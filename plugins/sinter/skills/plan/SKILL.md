---
name: plan
description: Turn an approved plan into a Sinter plan file under .plans/, with steps, scopes, and promised tags. Use when the user approved a plan-mode plan and wants it recorded as a Sinter plan, or asks to "make this a sinter plan", "write the plan file", or runs /sinter:plan. Do not use for writing decision records (use /sinter:decision), for changing the promises of an existing plan without the user's agreement, or for planning itself.
user-invocable: true
argument-hint: "[path to a plan file; omit to use the plan just approved]"
---

# Turn an approved plan into a Sinter plan

A Sinter plan is a markdown file under `.plans/`. It records an
agreement between the user and the agent about a piece of work. The
plan holds a set of steps. Each step promises that certain tagged
items exist when the step is done. The plan reaches the default
branch in a pull request of its own. Later branches each deliver one
or more of its steps, and the tool checks the promises against the
repository. This skill writes the plan file from a plan that the user
approved, and says how a later branch marks a step that it delivers.

The full specification is at
<https://github.com/lathrys-at/sinter/blob/main/spec/vocabulary.md>,
section 10. The rules below are the parts this skill needs.

## Input

Use the first of these two inputs that exists:

1. The path the user gives as an argument.
2. The plan the user approved in this conversation (the text shown
   when plan mode ended).

If neither exists, stop and ask the user for the plan.

## Procedure

Do the steps in order. Ask the user at the points marked "confirm".

### 1. Derive the plan slug and make the plan id

The slug names the plan. Derive it from the plan's title:

1. Change the title to lowercase.
2. Replace each sequence of non-alphanumeric characters with one
   hyphen.
3. Remove a hyphen at the start and at the end.

The result must match the slug pattern
`[A-Za-z0-9]+([-_.][A-Za-z0-9]+)*`. Shorten the slug to the two to four
words that name the work.

A slug is free when no open plan has it. The tool does not yet read
which plans are closed, so it counts every plan file in `.plans/` as
open. Two slugs that differ only in case are the same slug. Look for
the slug in the `@plan` line of every file in `.plans/`, with no regard
to case:

```
grep -rliE '^@plan[[:space:]]+<slug>(@|[[:space:]]|$)' .plans/
```

Name each file that the command finds to the user, with its journal:
the file of the same name that ends in `.log.md`. The user can choose
another slug, or delete those files first. Git keeps them in the
history. Confirm the slug with the user.

The plan id is six lowercase hex digits. The slug, `@`, and the plan
id together, `<slug>@<id>`, name this plan exactly, also after a later
plan takes the same slug. Make the plan id with this shell command,
and use its output as it is:

```
openssl rand -hex 3
```

If `openssl` is missing, use this command:

```
od -An -N3 -tx1 /dev/urandom | tr -d ' \n'
```

Never write the digits yourself, and never copy a plan id from another
plan or from a document. Check that the output is exactly six
characters, each from `0` to `9` or from `a` to `f`.

### 2. Map the plan to steps

Each unit of work in the plan becomes one step. A unit of work is
usually what one later branch delivers in one pull request, or one
numbered phase. A step is a `##` heading and the tag block after it.
Derive the step slug from the heading text with the same rule as the
plan slug. Two steps in one plan must not produce the same slug.

Some sections of the plan hold only context, out-of-scope notes, or
verification notes. These sections do not become steps. Keep them out
of the plan file, or keep them as `##` sections with no tags. A
section with no tags is prose, not a step.

Step order in the file is advice, not a rule. Put steps in the order
the plan gives.

### 3. Turn the plan's outputs into promises

Inside a plan file, every tag is a promise. The tag says that the
step will produce that item. Map the plan's outputs like this:

| the plan says the step will | write in the step |
|---|---|
| decide something, or write a decision record | `@decision <slug>` |
| write or change a requirement | `@req <slug>` |
| write or change a design item | `@design <slug>` |
| implement a requirement or a design item in code | `@satisfies <slug>` |
| write a test for a requirement or a design item | `@verifies <slug>` |
| refine a requirement or a design item | `@refines <slug>` |
| cite an item or an external id, such as an issue | `@cites <slug or ns/id>` |

A promise carries no revision. Never write `v1` or `vN` after a slug
in a plan file. Every slug must match the slug pattern from step 1.
A promised `@satisfies` or `@verifies` needs a target. The target
exists in the repository, or another step of the same plan promises
to declare it. If neither is true, ask the user what the target is.

A step with a scope and no promises is a refactor step. The manifest
key `proof.step` in `sinter.toml` says when a refactor step is done.
Read it before you write one:

- `"delivered"`, or no key: the step is done when the plan file marks
  it as delivered (section "Deliver a step" below). A mark on a step
  whose scope the branch did not change is a finding. So give a
  refactor step a narrow scope, the files that its work changes, or
  give it a promise. A broad scope, such as `lib/**`, lets the mark
  pass after a change that did not do the step's work.
- `"approval"`: the step is done when a person approves it in the
  ledger. Tell the user that the step needs that approval.
- `"promises"`: every step needs a promise, and the tool reports each
  refactor step. Do not write a refactor step. Ask the user which item
  the step will produce, and promise it.

### 4. Set the scopes

The plan's `@scope` line lists the paths the whole plan may touch.
Each step's `@scope` line lists the paths that step may touch. A
step's scope must sit inside the plan's scope. A step with no
`@scope` line inherits the plan's scope.

Scope globs are relative to the repository root. Separate them with
commas. They use gitignore style:

- `*` matches inside one path segment.
- `**` matches across path segments.
- `!` negates the glob.
- A trailing `/` means the directory and everything under it.

Derive scopes from the files the plan names. Where the plan is not
explicit, confirm the globs with the user. An item meets a
promise of a step only when the item sits inside the step's scope, or
inside the default location that the manifest key `paths.<kind>`
gives for the item's kind. When the manifest has no default location
for a kind, a step that promises an item of that kind must include
the item's path in its scope: for example `docs/decisions/**` for a
decision record.

### 5. Write the files

A header is the comment at the top of a file that names the license
and the copyright holder. Give each file you write the header that
the repository you work in puts on the files beside it. Look for that
header in this order: a file that is already in `.plans/`, then
`REUSE.toml`, then the repository's contributing guide. When the
repository puts no header on those files, write none. Never write a
license or a copyright holder that the repository does not use.

Write `.plans/<slug>.md` with this shape:

```markdown
# <Plan title>
@plan <slug>@<id>
@scope <plan-level globs>
<One or two sentences: what the plan delivers.>

## <Step heading>
@scope <step globs>
@decision <slug>
@req <slug>
<Optional prose: what the step does, in a few sentences.>

## <Next step heading>
...
```

The first tag block of the file must carry `@plan`, with the slug and
the plan id of step 1. Put prose that
explains a step after its tag lines, not before them.

Also write `.plans/<slug>.log.md`. This file holds only a title line:
`# Journal: <plan title>`. While the plan is open, the agent records
in this journal what it tried and why the attempt failed. The tool
never reports findings on a journal.

### 6. Show the result

Print the plan file. Then print a list with one line for each
promise: `<step slug>: <word> <target>`. Tell the user that the plan
reaches the default branch in a pull request of its own, and that
later branches deliver its steps. Tell the user that a later change to
a promise needs the user's approval.

When you quote the plan, or any of its tag lines, on GitHub (in an
issue, a pull request, or a comment), put the text in a fenced code
block. GitHub reads `@word` outside code as a mention of the account
`word`, and most tag words, such as `req`, `plan`, and `cites`, are
GitHub accounts, so a bare tag line notifies strangers.

## Deliver a step

A branch that delivers a step marks the step in the plan file with
one tag line, `@delivered <hash>`, in the tag block of the step: the
tag lines right after its heading. `<hash>` is the first six hex
digits of the step hash, which covers the step's scope, its promises,
and its text. Do these steps on the branch that delivers the step:

1. Do the work of the step, and meet its promises.
2. Run `sinter check --diff`. For a step with promises that the branch
   makes met, Sinter reports `unmarked-step` and prints the line to
   add. Add that line after the last tag line of the step, as printed.
3. For a step without promises, Sinter prints no such line. Run
   `sinter scan`, find the record of the step (`"kind":"step"`), and
   take the first six digits of its field `csh`.
4. Run `sinter check --diff` again, and fix what it reports.

Keep the heading and the text of a delivered step. A rename, a split,
a merge, or a removal of a delivered step is the finding
`renamed-step`. An edit of the scope, a promise, or the text of a
delivered step changes its hash, and the old mark is the finding
`stale-mark`. Write the new hash that Sinter prints. The person who
merges the branch sees the edit and the new mark together.

Mark only the steps that the branch delivers. Never mark a step whose
work the branch did not do.

## Writing rules

All text in the plan file follows these rules:

- Use short sentences: one idea per sentence, about 20 words or
  fewer.
- Use the active voice and simple tenses.
- Use one word for one meaning, and use it the same way every time.
- Do not invent terms. Define a technical term at first use.
- Do not add notes that explain why a sentence or a file exists.

The plan file states the work, not the document. Do not narrate the
process that produced the plan file.

When the repository you work in states writing rules of its own,
follow them too.

## Checks before you finish

- Each file carries the header that the repository you work in puts
  on the files beside it, or carries none because the repository puts
  none on them.
- The first tag block carries `@plan <slug>@<id>`, with a plan id from
  the command of step 1.
- Every `##` heading with a tag is a step, and every step slug is
  unique in the plan.
- Every promised slug matches `[A-Za-z0-9]+([-_.][A-Za-z0-9]+)*`.
- No promise carries a revision.
- Every step scope sits inside the plan scope.
- Every promised item's kind can exist inside its step's scope.
- Every step has a promise when `proof.step` is `"promises"`.
- Every refactor step has a narrow scope or a promise.
- The journal file exists.
