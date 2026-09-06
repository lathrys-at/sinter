---
name: plan
description: Turn an approved plan into a Sinter plan file under .plans/, with steps, scopes, and promised tags. Use when the user approved a plan-mode plan and wants it recorded as a Sinter plan, or asks to "make this a sinter plan", "write the plan file", or runs /sinter:plan. Do not use for writing decision records (use /sinter:decision), for changing the promises of an existing plan without the user's agreement, or for planning itself.
user-invocable: true
argument-hint: "[path to a plan file; omit to use the plan just approved]"
---

# Turn an approved plan into a Sinter plan

A Sinter plan is a markdown file under `.plans/`. It records an
agreement between the user and the agent for one branch. The plan
holds a set of steps. Each step promises that certain tagged items
exist when the step is done. The tool later checks the promises
against the repository. This skill writes the plan file from a plan
that the user approved.

The full format is in `spec/vocabulary.md`, section 10, of the Sinter
repository. The rules below are the parts this skill needs.

## Input

Use the first of these two inputs that exists:

1. The path the user gives as an argument.
2. The plan the user approved in this conversation (the text shown
   when plan mode ended).

If neither exists, stop and ask the user for the plan.

## Procedure

Do the steps in order. Ask the user at the points marked "confirm".

### 1. Derive the plan slug

The slug is the identity of the plan. The slug is permanent. Derive
it from the plan's title:

1. Change the title to lowercase.
2. Replace each sequence of non-alphanumeric characters with one
   hyphen.
3. Remove a hyphen at the start and at the end.

The result must match `[a-z0-9]+(-[a-z0-9]+)*`. Shorten the slug to
the two to four words that name the work. Check that
`.plans/<slug>.md` does not exist. A slug can never be reused.
Confirm the slug with the user.

### 2. Map the plan to steps

Each unit of work in the plan becomes one step. A unit of work is
usually one pull request, one branch, or one numbered phase. A step
is a `##` heading and the tag block after it. Derive the step slug
from the heading text with the same rule as the plan slug. Two steps
in one plan must not produce the same slug.

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
| cite an item or an external ref, such as an issue | `@cites <slug or ns/id>` |

A promise carries no revision. Never write `v1` or `vN` after a slug
in a plan file. Every slug must match the slug pattern from step 1.
A promised `@satisfies` or `@verifies` needs a target. The target
exists in the repository, or another step of the same plan promises
to declare it. If neither is true, ask the user what the target is.

A step with a scope and no promises is a refactor step. A refactor
step is allowed. Tell the user when you write one, because the tool
only checks whether the step touched its scope.

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
explicit, confirm the globs with the user. Only an item inside a
step's scope discharges a promise of that step. So a step that
promises a decision record must include `docs/decisions/**` in its
scope. Do the same for every other kind of promised item.

### 5. Write the files

Write `.plans/<slug>.md` with this shape:

```markdown
# <Plan title>
@plan <slug>
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

The first tag block of the file must carry `@plan`. Put prose that
explains a step after its tag lines, not before them.

Also write `.plans/<slug>.log.md`. This file holds only a title line:
`# Journal: <plan title>`. While the plan is open, the agent records
in this journal what it tried and why the attempt failed. The tool
never reports findings on a journal.

### 6. Show the result

Print the plan file. Then print a list with one line for each
promise: `<step slug>: <word> <target>`. Tell the user that the
branch agrees to deliver these promises. Tell the user that a later
change to a promise needs the user's approval.

## Writing rules

All text in the plan file follows the project's writing rules in
`CONTRIBUTING.md`: short sentences, active voice, one meaning per
word, no invented terms, no notes that explain why the file exists.

## Checks before you finish

- The first tag block carries `@plan <slug>`.
- Every `##` heading with a tag is a step, and every step slug is
  unique in the plan.
- Every promised slug matches `[a-z0-9]+(-[a-z0-9]+)*`.
- No promise carries a revision.
- Every step scope sits inside the plan scope.
- Every promised item's kind can exist inside its step's scope.
- The journal file exists.
