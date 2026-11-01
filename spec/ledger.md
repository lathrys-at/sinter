<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Sinter specification: approval-ledger format

Status: draft. The seven specifications share one version; see [docs/versioning.md](../docs/versioning.md).

## 1. Introduction

The ledger is Sinter's event log for a repository: a sequence of
entries that writers only append. Each entry is an **event**. The
events come from two sources: the judgments of a person (approvals,
declines, and abandonments) and the records of the job on the default
branch (deliveries and completions). Every state that Sinter reads
from the ledger, such as approved, declined, delivered, or closed, is
a fold over the entries in the order of their `seq` (section 2.3).
This document defines where the ledger lives, how entries get their
ids and their order, each entry kind, and the rules that give entries
their meaning.

Anyone can implement this specification in any tool. See the
LICENSE-SPEC file at the repository root. Entries are JSONL records in
the canonical form of [jsonl.md](jsonl.md) section 2. The items the
ledger judges are defined in [vocabulary.md](vocabulary.md).

## 2. Storage

### 2.1 The ref and the chunks

@req ledger-storage v2

The ledger lives in the tree of the commits of a dedicated git ref:
`refs/sinter/ledger`. This ref is not a checkout path. No editor and
no file tool reaches the ledger without a git plumbing command.
Sinter imposes this restriction on purpose, so that only a deliberate
act writes the ledger.

The ref names a commit. A ref that names a tag, a tree, or a blob
makes the ledger broken (section 13.5). The commit at the ref is the
**tip** of the ledger.

The tree of each commit holds the entries in **chunks**. A chunk is a
file of JSON lines: one entry on each line, each line in the canonical
form of [jsonl.md](jsonl.md) section 2, and each line with its LF.
A chunk holds one entry or more. The tree holds these paths, and no
other:

| path | object |
|---|---|
| `entries` | a folder |
| `entries/<hh>` | a folder. `<hh>` is two lowercase hexadecimal digits |
| `entries/<hh>/<id>.jsonl` | a chunk: a regular file of mode `100644`. `<id>` is the id of the first entry of the chunk (section 3.1), and `<hh>` is the first two hexadecimal digits of that id after `e-` |

Each folder holds at least one entry. The names of each folder, and of
the tree of a commit, are in increasing byte order, and no name comes
twice. A symbolic link, a submodule, and an executable file are not
chunks. The tree of a commit that holds no entry is the empty tree.
For example, a ledger of 87 entries can hold two chunks:

```
entries/5b/e-5b1c0a9d2e11.jsonl    50 entries
entries/a0/e-a03f77c1d9e2.jsonl    37 entries
```

### 2.2 Append only

@req ledger-append-only v2

A write appends entries to the ledger, and it never changes or drops
an entry. Each write takes these actions in order:

1. It gives each new entry the next `seq` (section 3.4), and appends
   the entry to the **open** chunk: the chunk that holds the entry
   with the greatest `seq`, while that chunk holds fewer than K
   entries, with K = 50. When no chunk is open, the write starts a new
   chunk, and the new chunk takes the name of its first entry.
2. It commits the new tree, with the tip as the only parent.
3. It moves the ref to the new commit, by fast-forward only.

Every other chunk is **closed**, and a write keeps it as it is. A
commit can still move entries between chunks, as long as no entry
changes or disappears (section 13.4). Every commit of the ledger has
one parent, except the first commit, which has none. No commit of the
ledger is a merge commit. The first commit holds the entries of the
first write, or no chunk: the empty tree.

A reader does not count the entries of a chunk, and it does not look
for the open chunk.

### 2.3 Events, folds, and commands

@req ledger-folds

Unlike the derived JSONL of a scan, the ledger is history: its entries
carry their author and the time of their write, and no scan can derive
them again. The ledger is an event log:

- Each entry is an **event**. The approval command, the decline
  command, and the abandon command write the judgments of a person:
  `approval`, `commitment-set`, `decline`, and `abandoned`. The job on
  the default branch writes its records, `delivered` and `completed`
  (section 8). The job makes no judgment.
- A **fold** computes a state from the entries, one by one, in the
  order of their `seq`, or from the entries below a given `seq`. Each
  state that the specifications read from the ledger is a fold: an
  approval that counts (sections 5.2 and 6), a live decline (section
  7.2), an open plan (section 10.1), a claim (section 10.2), the
  approved commitment set of a plan (section 11.1), and the start of
  the job (section 8.4). A fold reads the entries and nothing else. It
  does not read git's commit graph, the clock, the environment, or the
  network.
- A **command** writes the ledger. It reads the working tree and the
  folds, checks the entries that it is about to write against the
  folds, and appends one commit. Each command states when it writes
  nothing because the folds already hold its judgment. Two equal ids
  never decide this.
- A **repair** (section 14) is the one exception to the rule that
  writes only append. It rewrites the commits of the ledger. Only a
  person repairs the ledger.

An entry that names another entry, such as an approval of a plan that
names a commitment set by its hash, counts only when the named entry
has a smaller `seq`. A reference that names no such entry is a fault
of the fold, not of the format: the entry counts for nothing, and the
ledger is not broken. The field `dropped` of a `void` entry is no such
reference (section 14.1).

## 3. Entry identity

### 3.1 The id of an entry

@req ledger-entry-id v2

An entry's id is `e-` plus the first twelve lowercase hexadecimal
digits of a SHA-256 hash. The hash covers the canonical bytes of the
entry with the `id` key absent, without the LF. So the id covers
`seq`, and two entries of one ledger never have the same fields.

Two different entries can still get one id by chance: for a ledger of
100,000 entries, the chance is about 1 in 56,000. A writer whose new
entry has an id that the tip already holds sets the `ts` of the new
entry one second later, computes the id again, and tries again.

### 3.2 Recovery from a failed push

@req ledger-push-recovery v2

The ledger ref of the remote is the one central order of the ledger.
An entry that a clone wrote and has not pushed is **provisional**: its
`seq` and its id hold only in that clone. Two writers can push to the
ref of the remote at the same time, and the push of one of them then
fails. The writer that lost **replays** its entries on the new tip of
the remote, in these steps:

1. It fetches the ledger ref of the remote.
2. It finds the unpushed commits: the commits of the clone's ledger
   that the fetched ref does not reach.
3. It takes the judgments of those commits, oldest first. A judgment
   is one approval with its `commitment-set` entry, one decline, or
   one abandonment.
4. It checks each judgment again against the folds of the new tip,
   with the same subject, the same hash, and the same answers of the
   person. When the check needs to ask the person, it asks again on the
   terminal. With no terminal, it refuses the judgment.
5. It drops a judgment that the new folds refuse, or that the new
   folds already hold, and tells the person. It also drops each later
   judgment that names an entry that it dropped. It skips each entry
   that a `void` entry of the remote drops (section 14).
6. It appends each judgment that stays, with new `seq` values, and so
   with new ids. Every other field stays as it was. For an approval of
   a plan, it appends the `commitment-set` entry again only when the
   new tip needs it, by the rule of section 6.
7. It pushes again. When the push fails, it starts again at step 1.

The commits of the clone are only the units of its writes and of its
pushes. A replay does not keep them. A replay checks what an entry
says, not which program wrote it. The job on the default branch does
not replay: it drops its unpushed entries, fetches, and runs again
(section 8.3).

### 3.3 Unique ids

@req ledger-unique-ids v2

Ids never repeat within the tree of a commit of the ledger.

### 3.4 The order of entries

@req ledger-entry-order v3

Every entry holds `seq`, an integer of 1 or more. The entries of the
tree of every commit of the ledger hold each `seq` from 1 to n exactly
once, where n is the number of the entries of the tree, of every kind,
unknown kinds included. A write gives its new entries the numbers
above the greatest `seq` of the tip, in the order of the write. So the
order of `seq` is the order of appending, and it is the order of the
ledger.

Where order matters, for example when a decline follows an approval,
the entry with the greater `seq` comes later. The **latest** entry of
a set of entries is the entry with the greatest `seq`, and the
**first** is the entry with the least `seq`. The position of an entry
in a chunk, and the name of its chunk, decide nothing.

`ts` orders nothing. It is information for a person, written in UTC
(section 4.1). A writer's clock can be wrong, so `ts` can go backwards
from one entry to the next. No reader compares `ts` with a clock or
with the `ts` of another entry.

## 4. Common fields

### 4.1 The fields of every entry

@req ledger-common-fields v4

Every entry carries these fields:

| field | type | meaning |
|---|---|---|
| `id` | string | entry id (section 3) |
| `kind` | string | `approval`, `commitment-set`, `decline`, `delivered`, `completed`, `abandoned`, or `void` |
| `v` | int | schema version: `1` |
| `seq` | int | the position of the entry in the order of the ledger, 1 or more (section 3.4) |
| `by` | string | who wrote the entry |
| `ts` | string | the time of the write, in UTC, to the second (below) |
| `head` | string | the object id of the commit the writer stood on |
| `branch` | string | the branch the writer stood on; omitted when the writer stood on no branch |
| `tool` | string | tool version |

Every field but `branch` is required. `ts` has the form
`YYYY-MM-DDTHH:MM:SSZ` of RFC 3339, with no fraction of a second, for
example `2026-10-31T14:05:09Z`: 20 characters, an uppercase `T` and
`Z`, digits elsewhere. The date exists in the Gregorian calendar, the
hour is `00` to `23`, the minute `00` to `59`, and the second `00` to
`59`.

The target of this specification also has the kind `plan-version`:
the whole text of a plan, linked to the version of the plan before it
and to its commitment set. The step of the ledger plan that adds
`sinter approve` defines it. Until then, a reader reads it as an
unknown kind (section 13.2).

### 4.2 The fields of each kind

@req ledger-field-types

Sections 5 to 9 and 14 give the meaning of the fields of each kind.
This table gives their types. A **hash** is 64 lowercase hexadecimal
digits. A **commit** is the object id of a commit: 40 lowercase
hexadecimal digits, or 64 in a repository that uses git's SHA-256
object format. An **entry id** is the id of section 3.1.

| field | kinds | type | required |
|---|---|---|---|
| `subject` | `approval` `decline` `delivered` `completed` `abandoned` | string | yes |
| `rev` | `approval` | int, 1 or more | with `xh` |
| `xh` | `approval` | hash | with `rev` |
| `csh` | `approval` | hash | no |
| `csh` | `commitment-set` `delivered` | hash | yes |
| `note` | `approval` | string | no |
| `scopes` | `commitment-set` | array of objects: `glob`, a string, required; `step`, a string, optional | yes |
| `promises` | `commitment-set` | array of objects: `step`, `word`, and `target`, each a string, required | yes |
| `approval` | `completed` | entry id | no |
| `hash` | `decline` | hash | yes |
| `reason` | `decline` `abandoned` `void` | string | yes |
| `merge` | `delivered` `completed` | commit | yes |
| `report` | `completed` | hash | yes |
| `dropped` | `void` | entry id | yes |

An `approval` entry holds `rev` and `xh` together, or `csh`, and never
both. `head` is a commit. An array of `scopes` or `promises` can be
empty. A key of an object of `scopes` or `promises` that the table
does not name is an unknown field (section 13.2).

### 4.3 The writers

@req ledger-writers v7

Four writers exist. The approval command writes `approval` entries:
of a declaration, of a plan, and of a step. Before the approval of a
plan, it writes the `commitment-set` entry of the plan's set, unless
the tip already holds that set (section 6). The decline command
writes `decline`. The abandon command writes `abandoned`. A person
runs these three commands. The fourth writer is the job on the
default branch, which writes `delivered` and `completed` (section 8).
A repair writes `void` (section 14). Each command refuses the
judgments that sections 5 to 10 name as refusals, and writes nothing.

## 5. `approval`

### 5.1 The fields of an approval entry

@req ledger-approval-entry v4

An `approval` entry records that a person approved a subject. The
subject is a declaration, a plan, or a step.

| field | meaning |
|---|---|
| `subject` | for example `req:auth-lockout`, `plan:auth-lockout@3f2a9c`, or `step:auth-lockout@3f2a9c/tidy` |
| `rev` `xh` | declarations only: the revision and extent hash approved |
| `csh` | plans and steps only: the commitment-set hash of a plan, or the step hash of a step ([jsonl.md](jsonl.md) section 4) |
| `note` | omitted when none |

The subject of a plan is the fact id of the plan, which holds the full
form of the plan ([vocabulary.md](vocabulary.md) section 4.3). The
approval command refuses to approve a plan that has no plan id. So the
full form of every approved plan holds a plan id, and the id of a
claim can be read ([jsonl.md](jsonl.md) section 9). The `csh` of the
approval of a plan names the `commitment-set` entry that holds the
approved set (section 6).

The subject of a step is the fact id of the step,
`step:<plan>/<step>`, which holds the full form of its plan. The
approval command refuses to approve a step that has promises, and a
step of a plan that has no plan id. An approval of a step matches the
step while its `csh` equals the current step hash of the step. While
`proof.step` is `"approval"` ([manifest.md](manifest.md) section
10.4), an approval of a step without promises that counts (section
5.2) approves the step, and so meets the first condition of `done()`
([algebra.md](algebra.md) section 6.4).

The approval command also refuses to approve a closed plan (section
10.1), and a step of a closed plan.

### 5.2 Approval

@req ledger-approval v4

Approval attaches to the `(slug, rev, xh)` triple, never to a
document. The last judgment on the current text wins. For a
declaration of a kind that needs approval
([manifest.md](manifest.md) section 10.1), take these entries:

- each approval of its current `(slug, rev, xh)`;
- each decline of the declaration whose `hash` is its current `xh`
  (section 7).

An approval **counts** for the declaration when it is the latest of
these entries. The declaration is **approved** if and only if an
approval counts for it. A revision bump therefore removes approval
until the item is approved again. A decline at the current text after
the approval also removes it. A judgment at another hash counts for
nothing in this comparison. A declaration of a kind that does not need
approval counts as approved.

A step takes the same rule: of the approvals of the step that match
its current step hash and the declines of the step whose `hash` is its
current step hash, an approval counts when it is the latest. A plan
takes the rule of section 7.2 and section 11.

### 5.3 Revision reservation

@req ledger-revision-reservation v3

A writer must refuse to write an approval for `(slug, rev)` when the
ledger already holds an approval for that pair with a different `xh`.
The refusal message names the earlier entry and the branch that entry
was written from. To resolve the refusal, the author must increase the
declaration's revision again.

When an approval of the same `(slug, rev, xh)` counts (section 5.2),
the writer writes no new entry. When a decline of the current text is
latest, the writer asks the person before it approves over the
decline, and then writes a new approval of the same `(slug, rev, xh)`.

## 6. `commitment-set`

@req ledger-approved-commitment-set v2

A `commitment-set` entry holds the commitment set of a plan
([vocabulary.md](vocabulary.md) section 10.6) in full, not only as a
hash. A hash shows only that two sets differ. It does not show which
promises or scopes differ, and the comparison in section 11 needs that
detail.

| field | meaning |
|---|---|
| `csh` | the commitment-set hash of the set ([jsonl.md](jsonl.md) section 4) |
| `scopes` | one object for each glob of a scope line of the plan: `glob`, the glob, and `step`, the slug of the step whose own `@scope` line holds the glob. A glob of the plan scope has no `step` |
| `promises` | one object for each promise of the plan: `step`, the slug of the step that holds the promise, and `word` and `target`, as the promise record gives them ([jsonl.md](jsonl.md) section 5) |

The **hash of the set** of an entry is the commitment-set hash of
[jsonl.md](jsonl.md) section 4, computed from `scopes` and `promises`
alone:

- The plan scope is the globs of the objects of `scopes` that have no
  `step`.
- The effective scope of a step is the globs of the objects of
  `scopes` whose `step` is the slug of the step. When no object of
  `scopes` names the step, it is the plan scope.
- Each object of `promises` is one promise, with the effective scope
  of its `step`.

A reader computes the hash of the set again, and compares it with
`csh`. The hash **holds** when the two are equal and the canonical
bytes that the hash covers are 1 MiB (1,048,576 bytes) or shorter.
Those bytes repeat the effective scope of a step in each of its
promises, so their length grows with the number of promises times the
number of globs, and a short line could cost a reader much time and
memory. A reader adds up the length of those bytes first, from the
printed form of each string, and builds no bytes and computes no hash
when the length is above the limit.

An approval of a plan names its set by its `csh`. Its **set entry** is
the latest `commitment-set` entry below the approval whose `csh` is the
`csh` of the approval and whose hash holds. Two such entries can hold
different sets, because the hash leaves out the slugs of the steps and
the scopes of the steps without promises. So the approval takes the
set of that one entry, and an entry with a greater `seq` than the
approval changes nothing. An approval of a plan **has its set** when
it has a set entry. An approval of a plan without its set counts for
nothing: no `commitment-set` entry below it has its `csh`, or the hash
of none of those entries holds.

An approval without its set is a fault of the fold, not a fault of the
format. The ledger is not broken, and each line still passes the
checks of section 13. The reason: an object of `scopes` or `promises`
can hold a key that a tool does not know (section 4.2). A newer writer
can compute the hash with that key, and an older tool then computes
another hash from the same line. A fault of the format would stop the
older tool at that line. A fault of the fold leaves the approval
without effect, and the plan waits for an approval that the tool can
read.

The approval command writes the `commitment-set` entry of the set
before the approval, in the same write. It writes no such entry when
the latest `commitment-set` entry of the tip with that `csh` and a
hash that holds has the same `scopes` and `promises` as the set.

## 7. `decline`

### 7.1 The fields of a decline

@req ledger-decline v2

A decline records a refusal by a person, bound to the exact text
refused.

| field | meaning |
|---|---|
| `subject` | fact id |
| `hash` | the subject's extent hash (`xh`), commitment-set hash (`csh`), or step hash at the moment of refusal |
| `reason` | required |

The subject of a decline is a declaration, a plan, or a step. The
decline command refuses a subject of another kind. A person can
decline one text twice, each time with a reason. Both declines stay.

### 7.2 A live decline

@req ledger-live-decline v3

A decline is never deleted. A decline is **live** while both of these
conditions hold:

1. The current hash of the subject equals `hash`.
2. No later approval counts against it:
   - for a declaration, no approval of the current `(slug, rev, xh)`
     has a greater `seq`;
   - for a step, no approval that matches the current step hash has a
     greater `seq`;
   - for a plan, the latest approval of the plan that has its set
     (section 6) has a smaller `seq`, or the plan has no such
     approval.

For a declaration and a step, an approval at another hash ends no
decline. A person who approves a text over their own refusal of the
same text ends that refusal. For a plan, the latest approval of the
plan that has its set ends every earlier decline, because the plan is
approved against the set of that approval (section 11). So a decline
at the commitment-set hash X, then an approval of a set Y that
contains X, and then the text X again give an approved plan with no
live decline. A plan with a live decline is not approved.

## 8. The job on the default branch

### 8.1 The job and the `completed` entry

@req ledger-completed v7

The **job on the default branch** writes the `delivered` and the
`completed` entries. The job runs on the default branch, in CI or by a
person's hand. It runs the same command either way, and it makes no
judgment of its own. In CI, it runs on each push to the default
branch. The job takes these actions in order:

1. Find the range of its run, and check that its head is new (section
   8.4). When the clone does not hold the commits of the range, fetch
   them. A clone in CI is often shallow.
2. Import the test evidence of its run.
3. Append one `delivered` entry for each delivery line of the range
   that section 8.4 names.
4. Find the open plans on the default branch.
5. Check each of those plans against the completion condition below.
6. Append one `completed` entry for each plan that passes the
   condition.

A `completed` entry closes a plan whose steps are all done
([algebra.md](algebra.md) section 6.4).

| field | meaning |
|---|---|
| `subject` | `plan:<slug>@<id>`: the fact id of the plan, with its full form |
| `approval` | the id of the latest approval of the plan that has its set (section 6), among the entries below the `seq` of the `completed` entry; omitted when the plan has no such approval |
| `merge` | the merge commit that delivered the last step of the plan ([vocabulary.md](vocabulary.md) section 10.8) |
| `report` | SHA-256 of the report compiled when the plan closed |

### 8.2 The completion condition

@req ledger-completion-condition v5

A plan passes the condition when every step of the plan is done
(`done()`, [algebra.md](algebra.md) section 6.4). The job imports the
test evidence of its run before it checks the condition. Without
evidence, a `verifies` edge is at rung `never-ran`
([algebra.md](algebra.md) section 6.7), and the step that holds the
edge in its scope is not done. So a plan with a `verifies` edge in the
scope of a step does not close without evidence.

Under `proof.step = "delivered"`, a step without promises is done when
the ledger holds a `delivered` entry that matches its current step
hash (section 8.4). So the job appends the `delivered` entries of its
run before it checks the condition.

An open plan that fails this condition is normal while its work goes
on. A step merged in part, with some of its promises met and some not,
is the finding `merged-incomplete` ([algebra.md](algebra.md) section
9).

### 8.3 A repeated run

@req ledger-completion-idempotent v4

The writes of the job are idempotent. A second run adds no second
`completed` entry for a plan, and no `completed` entry for a closed
plan. It adds no `delivered` entry whose subject and `csh` are those
of a `delivered` entry that the ledger holds. These checks read the
folds of the tip, not the ids of the entries: two runs of the job
write two `ts`, and so two ids, for one delivery. The approvals of a
plan, the repository tree, the messages of its commits, and the test
evidence of the run hold the facts that prove delivery and completion.
A run reads every commit from the start of section 8.4, so a run of
the job that does not finish costs one repeat run and loses no facts.
When the push of a run fails, the job drops the entries of that run,
fetches the ledger ref, and runs again.

### 8.4 The `delivered` entry

@req ledger-delivered v2

A `delivered` entry records that a commit of the default branch
delivered a step ([vocabulary.md](vocabulary.md) section 10.8). An
entry **matches** a step when its subject is the step and its `csh` is
the current step hash of the step.

| field | meaning |
|---|---|
| `subject` | `step:<plan>/<step>`: the fact id of the step, with the full form of its plan |
| `csh` | the step hash of the step in the tree of the head of the run, all 64 hex digits ([jsonl.md](jsonl.md) section 4) |
| `merge` | the commit of the range whose message holds the delivery line. After a squash merge, it is the merge commit. After another kind of merge, it can be a commit of the merged branch |

The **range** of a run is the set of commits that the head of the
default branch reaches and that the **start** of the run does not
reach. The start is the first of these that exists:

1. The `head` of the latest `delivered` or `completed` entry of the
   ledger. The job alone writes these two kinds, so this is the head of
   the latest run that appended an entry.
2. The `head` of the first entry of the ledger whose `branch` is the
   default branch.

When the ledger holds no such entry, the run has no start, and the
range holds every commit that the head reaches. A run that appends no
entry leaves the start where it was, so the next run reads the same
commits again.

Before it writes, the job compares its head `H` with `J`, the start
of rule 1. When the clone does not hold `J`, the job fetches it by its
object id. When rule 1 gives no start, the job makes no comparison.
Otherwise:

| case | the job |
|---|---|
| `H` is `J`, or an ancestor of `J` | writes nothing, tells the person that a later run recorded this head, and exits with code 0 |
| `J` is an ancestor of `H` | runs from `J` |
| neither, or the job cannot fetch `J` | warns, and runs from the start of rule 2, or with no start when rule 2 gives none |

Section 8.3 keeps a run from the third case from writing an entry a
second time. This comparison reads git's commit graph, so it is a
check of the job, a command, and no fold. A run of the job on an older
head, such as a run that a person starts late, writes nothing.

A person can run the job over the whole default branch. Such a run
has no start: it reads every commit that the head reaches, from the
first commit, makes no comparison of `H` and `J`, and appends only the
entries that the ledger lacks (section 8.3).

The job reads the message of each commit of the range, in the order
that `git rev-list ^<start> <head>` gives them, and reads the delivery
lines of each message as [vocabulary.md](vocabulary.md) section 10.8
says. It appends one `delivered` entry for each step for which a
delivery line of the range meets both of these conditions, in the
tree of the head and with the test evidence of the run:

1. The line counts for the step.
2. Each promise of the step is met ([vocabulary.md](vocabulary.md)
   section 10.5). A step without promises meets this condition.

The `merge` of the entry is the commit of the first such line in that
order. The job appends no entry for another line.

A line whose step has a promise that is not met at a run gives no
entry. When a later run appends an entry, the start moves past the
commit of that line, and no run reads the line again. The step is
then done when its promises are met, as for every step with promises,
and it is started by its met promises.

## 9. `abandoned`

### 9.1 The fields of an abandoned entry

@req ledger-abandoned v5

An `abandoned` entry closes a plan whose remaining steps no branch
will deliver ([vocabulary.md](vocabulary.md) section 10.8). A person
runs the abandon command; the tool never writes this entry on its own.
The abandon command refuses a closed plan, and a plan that neither the
current tree nor a claim (section 10.2) holds.

| field | meaning |
|---|---|
| `subject` | `plan:<slug>@<id>`: the fact id of the plan, with its full form |
| `reason` | required |

### 9.2 The end of the claim

@req ledger-abandoned-claim

An `abandoned` entry ends the plan's claim. It also releases every
`waiting-on` promise that depended on that claim.

## 10. Open and closed plans

### 10.1 Open and closed

@req ledger-open-plans v4

A plan is **open** until the ledger holds a `completed` or an
`abandoned` entry for its full form ([vocabulary.md](vocabulary.md)
section 4.3). A plan with such an entry is **closed**. The first such
entry closes the plan, and a later one counts for nothing. Only a
ledger entry closes a plan. No change to the plan file — an edit, a
move, or a deletion — closes a plan.

A closed plan generates no findings, holds no claim, contributes no
scope, and is not a candidate for the active plan. Its slug is free: a
later plan can take the slug, with a new plan id. The file and the
journal of a closed plan can leave `.plans/`.

### 10.2 Claims

A **claim** is an open plan that the ledger holds an approval of with
its set (section 6), and whose full form the current tree does not
hold ([vocabulary.md](vocabulary.md) section 4.3). The approval of a
claim is the latest approval of the plan that has its set, and the
claim reads its scopes and its promises from that set. A claim
does not depend on a branch. It ends when the plan closes. Sinter
projects each claim from the ledger as a `claim` record
([jsonl.md](jsonl.md) section 7). An open plan that the current tree
holds is no claim, so a branch that delivers a step of a plan on the
default branch sees that plan as a plan, not as a claim.

### 10.3 An absent ledger ref

@req ledger-absent-ref v4

When the ledger ref is absent, a tool sees no `completed` and no
`abandoned` entries, so it treats every plan as open. A tool in this
state, on a tree that holds at least one plan, must warn the user that
it found no ledger, so every plan counts as open. The help of the tool
must say how to fetch the ledger from the remote `origin`, with this
command:

```
git fetch --no-filter origin refs/sinter/ledger:refs/sinter/ledger
```

The option `--no-filter` makes a partial clone fetch every chunk of
the ledger.

## 11. Plan approval: commitment-set comparison

### 11.1 The comparison of commitment sets

@req ledger-plan-approval v5

A plan reaches the default branch in a pull request of its own
([vocabulary.md](vocabulary.md) section 10.1). When the kind `plan`
needs approval, a person approves the plan in the ledger before that
pull request merges. The merge alone does not approve the plan.

A plan's **commitment set** is the set of canonical facts about the
plan: the promises of each step, the scope of each step, and the plan
scope. When the kind `plan` does not need approval
([manifest.md](manifest.md) section 10.1), every plan counts as
approved, and this section does not apply. Otherwise the tool compares
the current set `C` against the approved set `C₀`: the set of the
latest approval of the plan that has its set (section 6). The plan
is approved if and only if it has such an approval, it has no live
decline (section 7.2), and all three clauses hold:

1. The multiset of `(word, target)` over all promises is equal in `C`
   and `C₀`.
2. The plan scope is contained: `scope(C) ⊆ scope(C₀)`.
3. Match each promise in `C` to a promise in `C₀` by `(word,
   target)`. When several promises share one `(word, target)` pair,
   first match the pairs whose step slugs are equal; then match the
   remaining promises in the order of their step slugs, sorted on both
   sides. For each matched pair, the effective scope of the step in
   `C` must be contained in the effective scope of the step in `C₀`.

### 11.2 Glob containment

@req ledger-glob-containment v2

**Glob containment** `G' ⊆ G` is decided structurally and
conservatively. Every glob in `G'` must satisfy one of these three
cases:

- it appears verbatim in `G`;
- it is a literal path, or a literal path prefix, that some glob in
  `G` matches;
- it is `<g>/<segments>` for some `<g>/**` in `G`.

When the checker cannot prove that a glob satisfies one of these three
cases, the checker treats the new scope as wider than the approved
scope. The rule is decidable and deterministic. When the checker
cannot prove containment, the checker asks a person for a new approval,
which is the safe result for approval.

### 11.3 Free amendments

An amendment is **free** when the plan stays approved after it and no
new approval is needed. The consequences of the three clauses:

- Renaming a step is free, because clause 3 matches by promise and not
  by step name. A delivered step keeps its slug all the same
  ([vocabulary.md](vocabulary.md) section 10.3).
- Reordering steps is free.
- Splitting a step is free when each new step keeps or narrows the
  scope of the original step.
- Merging steps is free only when the scope of the merged step is
  contained in the scope of each original step, for example when the
  original steps have one scope. A merged step that takes the union of
  different scopes widens the scope of some promise, fails clause 3,
  and needs an approval.
- Any promise added or removed fails clause 1 and needs an approval.

## 12. `pin` (deferred)

A `pin` entry will endorse the current hash of external content. It
adds three fields to the common fields of section 4: `approval`,
`external`, and `hash`. The example shows only the fields of the
entry's own:

```json
{"approval":"…","external":"gh/42","hash":"…","kind":"pin"}
```

It is designed but deferred, together with the `@pin` directive.

## 13. Reading and verification

### 13.1 The checks of a line

@req ledger-line-checks

A reader checks each line of each chunk that it reads, whatever the
kind of its entry:

1. The line is a JSON object in the canonical form of
   [jsonl.md](jsonl.md) section 2, with the value shapes of that
   section. A reader parses the line, prints the value again in the
   canonical form, and compares the bytes with the line.
2. The line holds `id` and `kind`, each a string, and `v` and `seq`,
   each an integer of 1 or more.
3. `id` is the id of section 3.1 of the line.

For an entry of a kind of section 4.1, the reader also checks the
fields of sections 4.1 and 4.2: each required field is present, and
each field has its type. For a `commitment-set` entry, the reader
also computes the hash of its set again (section 6). A hash that does
not hold is no fault of the line.

### 13.2 Unknown kinds, fields, and versions

@req ledger-unknown-parts

A tool reads one version of the entries: `v` = 1. A reader reads `v`
before it makes the other checks of section 13.1. When a line is a
JSON object whose `v` is an integer above the version that the tool
reads, the command stops with exit code 3, and the help says to
upgrade Sinter.

An entry of a kind that section 4.1 does not name counts for nothing,
and so does a field that sections 4 to 9 and 14 do not name for the
kind of its entry, and a key of an object of `scopes` or `promises`
that section 4.2 does not name. The reader still makes the checks of
section 13.1 for such an entry, and its id still counts in section
3.3. The tool ignores it otherwise. A command that reads such entries
or fields warns once, and the warning gives the number of each.

### 13.3 The tip

@req ledger-tip

A check of the tip reads the commit at the ref, and checks:

1. The ref names a commit (section 2.1).
2. The tree of the commit holds the paths of section 2.1, and no
   other.
3. The name of each chunk is the id of its first entry (section 2.1).
4. Every line of every chunk meets sections 13.1 and 13.2.
5. No id repeats in the tree (section 3.3).
6. The `seq` values of the entries of the tree are 1 to n, each once,
   where n is the number of the entries of the tree (section 3.4).

The check reads the objects of the tree in this order: the tree of
the commit, the folder `entries`, each folder of `entries` in the byte
order of the names, and each chunk of a folder in the byte order of
the names. It checks each object when it reads it. For a tree, it
checks the path and the mode of each entry, and then the order of the
names. It checks the lines of a chunk in their order. For each line,
it makes the checks of sections 13.1 and 13.2, then checks that the id
of the line is new, and then that the `seq` of the line is new. It
checks the name of a chunk after its first line. After the last
chunk, it checks that no `seq` from 1 to n is missing. That fault
names the least `seq` that is missing.

### 13.4 Verification of the history

@req ledger-verification v2

A verifier checks the tip as section 13.3 says. Then it checks each
commit with its parent, from the tip back to the first commit. For a
commit `C` and its parent `P`:

1. `C` has one parent or none. A commit with two parents or more is a
   merge commit, and it fails. A parent that is a tree, a blob, or a
   tag fails.
2. The tree of `P` meets the checks 2 to 6 of section 13.3.
3. Each entry of `P` is an entry of `C`, with the same bytes. `C` can
   hold the entry in another chunk, and it can hold new entries.

A chunk at one path with one object id in `P` and in `C` holds the
same entries in both, so a verifier reads it once. A verifier reads
the objects of `P` in the order of section 13.3, and checks each line
of a chunk that it reads against the items 2 and 3 of this section.

A verifier makes check 6 for `P` without the `seq` of every entry of
`P`. `C` passed check 6, so its entries hold 1 to n. Let k be the
number of the entries of `C` that no line of `P` matches. By item 3,
`P` holds the other n - k entries of `C`. So `P` holds 1 to n - k if
and only if each of the k entries has a `seq` above n - k. When one of
them does not, `P` fails check 6, and the fault names the least `seq`
of the k entries: the least `seq` that `P` lacks. The verifier makes
this check after the other checks of `P`.
A verifier reads the parents of each commit from the raw commit
object, and not from `git rev-list`, `git log`, or another command
that reads the grafts of the clone (`.git/info/grafts`) or the
replacement objects of git.

### 13.5 A broken ledger

@req ledger-broken

The ledger is **broken** when a check of section 13.3 or 13.4 fails.
Each command that reads the ledger makes one of the two checks:

| command | check |
|---|---|
| `sinter check` at the gate `turn`, at the gate `review`, and with no gate | the tip (section 13.3) |
| `sinter check` at the gate `merged` | the history (section 13.4) |
| `sinter scan` and `sinter ledger log` | the tip |
| `sinter ledger verify` | the history |

When its check fails, each command stops with exit code 3. The error
names the first fault in the order of sections 13.3 and 13.4: the
first line or object that fails a check, or whose `v` is above the
version that the tool reads. It also names the commit that holds the
fault, and the id of the entry at fault when there is one. The help
names the command `sinter ledger repair`. With `-o json`,
`sinter ledger verify` also writes the fault as a finding of the class
`ledger-broken` ([algebra.md](algebra.md) section 9). It exits with
code 0 when the history passes.

A clone can lack an object of the ledger. A shallow clone lacks the
commits behind its boundary, and a partial clone can lack chunks and
folders. When a check needs an object that the clone does not hold,
the command stops with exit code 3, and the help says how to fetch the
ledger (section 10.3). The ledger is not broken.

### 13.6 The ledger of a remote

@req ledger-remote

A clone can hold entries that it has not pushed, and the remote can
hold entries that the clone has not fetched. The local ref and the
ref of the remote must be on one line of history: one of the two
commits is an ancestor of the other, or they are equal. When neither
is an ancestor of the other, the writer whose push failed recovers as
section 3.2 says. The commands that move the ledger ref between a
clone and its remote check this rule.

A repair (section 14) breaks this rule once. After a repair, the ref of
the remote holds a new history. Each clone replays its unpushed
entries on that history (section 3.2), and then moves its own ref to
the ref of the remote, with force.

## 14. Repair

### 14.1 The `void` entry

@req ledger-void

A `void` entry takes the place of an entry that a repair dropped.

| field | meaning |
|---|---|
| `dropped` | the id of the entry that the repair dropped |
| `reason` | why the repair dropped the entry |

The `void` entry holds the `seq` of the entry that it replaces. So the
entries of each commit still hold each `seq` from 1 to n, and no later
entry changes its `seq` or its id. The entry that the repair dropped
is no longer in the tree, so no fold reads it. A `void` entry counts
for nothing in every fold, and it cancels no entry: a `void` entry
whose `dropped` names an entry of the tree changes nothing. The field
`dropped` serves one use: a replay (section 3.2) skips each of its own
entries whose id a `void` entry of the remote names.

### 14.2 What a repair writes

@req ledger-repair

A repair makes a new history of the ledger in which every commit passes
the checks of section 13. Only a person runs it, with
`sinter ledger repair`, and the command refuses under an agent
([manifest.md](manifest.md) section 10.2). In each commit of the new
history:

1. Each entry that the repair keeps has the bytes that it had.
2. Each entry that the repair drops gives its place to one `void`
   entry, with the same `seq`.

A repair is the one change of the ledger that is not an append. It
moves the ref of the remote with force, and each clone then follows as
section 13.6 says.
