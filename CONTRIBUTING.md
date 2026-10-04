# Contributing to Sinter

## Writing

All text in this repository uses Simplified Technical English
(ASD-STE100) in the style of Simple English Wikipedia. This style
applies to documentation, specifications, code comments, commit
messages, pull requests, and the tool's own output. The rules:

- Write for the people who use Sinter or contribute to it. Assume
  they do not share your context.
- Use short sentences: one idea per sentence, about 20 words or
  fewer.
- Use the active voice and simple tenses.
- Use one word for one meaning, and use it the same way every time.
- Do not invent terms. When a technical term is necessary, define it
  at first use.
- Give every pronoun one clear referent. Repeat the noun when in
  doubt.
- Give the context before the detail, so that each sentence makes
  sense on its own.
- Use a numbered list for a sequence of steps.
- Use a table for facts that a reader can enumerate.
- Do not add notes that explain why a sentence or a file exists, or
  that restate what a reader can infer from the stated facts.
- Do not open a document with prose that explains what the document
  is, what it is not, or how a reader will use it. Start with the
  content.
- Do not narrate the process that produced a document or a change.
  Say what the thing is, not how it came to be.
- A list document — a roadmap, a checklist — is a flat list of items
  with brief names and their subtasks beneath them. Do not group the
  items under relative time headings.

We reproduce some text from elsewhere: license texts, the DCO, and
quoted standards. That text stays exactly as it is in the source.

### Code comments

A comment states something that the code cannot show: an ownership
rule, a lifetime, a precondition, a unit, an invariant, a contract.
Write nothing else in a comment.

- Do not restate what the code shows.
- Do not explain background that the reader does not need for the
  code in front of them.
- Do not explain why a line or a file exists.
- Do not reference the design notes or a specification, by name or
  by section. A choice that needs a reference rests on a decision
  record in `docs/decisions/`, and the comment block cites it with a
  tag line: `(* @cites <slug> *)` in OCaml, `// @cites <slug>` in
  Rust, `/* @cites <slug> */` in C.

A comment on an interface — a header file, an `.mli` file, a public
function — addresses the caller. It states what the function takes,
what it returns, who owns the result, and when the result stops being
valid. It does not narrate the implementation, and it does not list
what the interface does not offer.

### Messages that the tool prints

An error message or a help text addresses the person who runs the
tool. It says what is wrong and, when useful, what to do. It never
names a repository file or a document section, and it never explains
the tool's internal reasons.

## Code

Sinter's code holds to the standard of a library that other OCaml
projects depend on. The rules:

- Every module has an `.mli` file. The interface exports the smallest
  set of types and functions that its callers need. A type whose
  values a caller must not build by hand is abstract.
- A comment on every exported value addresses the caller, as the
  "Code comments" section describes: what the value takes, what it
  returns, who owns the result, and what can go wrong.
- A function's type says what can go wrong. A failure that a caller
  handles is a value of a `result` type with a variant error type. An
  exception is for a failure that ends the whole operation. The `.mli`
  declares every exception a function raises and the condition that
  raises it.
- A function is total over its declared input type. When the type
  admits inputs the function cannot handle, the function returns an
  error value, or the `.mli` states the precondition and the function
  checks it and raises `Invalid_argument`. Do not use `assert false`,
  `Obj.magic`, `Option.get`, `List.hd`, or `failwith` on data that
  came from outside the module.
- State is local. A module holds no global mutable state. A resource
  such as an engine, a channel, or a temporary file has a type, an
  owner, and a lifetime rule in the `.mli`. Code releases a resource on
  every path, the error paths included; use `Fun.protect`.
- Data from outside the process (a file, standard input, the bridge's
  buffer, a wasm module) is decoded and validated in one module. The
  rest of the code sees typed values.
- Each module does one thing and depends only on the modules below it.
  The core library does not read the command line, the terminal, or
  the process environment; the executable in `bin/` does.
- The build is clean under dune's development profile, which turns
  warnings into errors. Do not silence a warning with a flag or an
  attribute; change the code.
- Prefer the standard library. Add a dependency only when the code it
  replaces would be larger than a module of our own, and record the
  choice in a decision record.

## Tests

- Every function that an `.mli` exports has a test. The test calls
  the function through the interface.
- Every property that a specification or an `.mli` states about an
  output is a property-based test: the test generates inputs with
  `qcheck` and checks the property for each input. A round trip, an
  ordering, an invariant, and a bound are properties.
- Every decoder of data from outside the process has a property test
  that feeds it generated and corrupted inputs. The decoder returns a
  value or an error for every input, and never crashes.
- Every exit code and every error message of a command has a test
  through the built binary.
- A bug fix comes with the test that failed before the fix.
- A test states one fact, and its name says which.
- CI measures coverage with `bisect_ppx`. A change does not lower the
  number.

## Build and check

Install [opam](https://opam.ocaml.org/), and create a switch with the
compiler that `sinter.opam.locked` pins, 5.5.0, for example with
`opam switch create 5.5.0`. The install below fails on any other
compiler. The parser bridge in `bridge/` is a Rust crate, so also
install the Rust toolchain with [rustup](https://rustup.rs) and
install `cmake`, which a build script of wasmtime runs. Then, from the
repository root:

```
eval $(opam env --switch=5.5.0)
opam install . --deps-only --with-test --with-dev-setup --locked
dune build
dune test
dune fmt
```

The `--with-dev-setup` flag installs `ocamlformat`, and `--locked`
installs the versions in `sinter.opam.locked`, the same versions CI
uses. When you change the dependencies in `dune-project`, run
`dune build` and then `opam lock ./sinter.opam`, and commit both
`sinter.opam` and `sinter.opam.locked`.

Before you commit, check that all of these pass:

- `dune build`, `dune test`, and `dune build @fmt`. `dune fmt`
  rewrites files in place; commit the files it changes.
- `reuse lint`. Install the tool once, for example with
  `pipx install reuse`.
- In `bridge/`: `cargo fmt --check` and
  `cargo clippy --all-targets -- -D warnings`.

CI runs all of them.

### The bridge's build directory

The dune rule that builds the bridge runs cargo outside `_build`, in a
directory of its own for each checkout, so that two checkouts never
link each other's library. The directory sits under the first of
these that is set: `CARGO_TARGET_DIR`; `$XDG_CACHE_HOME/sinter-bridge-build`;
`~/.cache/sinter-bridge-build`. Its name is a hash of the checkout's
path, and a file named `checkout` inside it holds that path. Each one
is about 500 MB. `dune clean` does not remove them, so a machine with
many worktrees collects them. This loop removes every directory whose
checkout is gone:

```
for d in "${XDG_CACHE_HOME:-$HOME/.cache}"/sinter-bridge-build/*/; do
  p=$(cat "$d/checkout" 2>/dev/null) || continue
  [ -d "$p" ] || rm -rf "$d"
done
```

A directory with no `checkout` file predates the file; remove it by
hand, and the next build writes a new one.

### Coverage

`bisect_ppx` measures how much of `lib/` and `bin/` the tests run. No
released version of it installs beside the versions in
`sinter.opam.locked`. The last release, 2.8.3, needs `ppxlib` below
0.36 and `cmdliner` below 2. The lock file pins the compiler 5.5.0,
which no `ppxlib` below 0.36 supports, and it pins `cmdliner` 2.1.1.
An open pull request of `bisect_ppx` builds against the newer
`ppxlib` and the newer `cmdliner`, so a coverage run pins one commit
of it. Pin it into the project's switch once:

```
opam pin add -y -n bisect_ppx \
  git+https://github.com/aantron/bisect_ppx.git#7061d643ff492b0045796357ee6917ded21fb1f0
opam install bisect_ppx
```

The pin names a commit and never a branch, so that every run installs
the same code. The install adds five packages: `bisect_ppx`, `ppxlib`,
and three packages that `ppxlib` needs. It changes no version that the
lock file pins. Remove the pin with `opam pin remove bisect_ppx` when
`bisect_ppx` makes a release that installs beside the lock file.
Install that release instead, and take the pin out of this section and
out of the `coverage` job. That job pins the same commit, for the same
reason.

Then, from the repository root:

```
dune build @runtest --force --instrument-with bisect_ppx
bisect-ppx-report summary --per-file
```

`--instrument-with` is the switch. Without it, the build carries no
instrumentation and costs nothing. `bisect-ppx-report` reads the
counts under `_build`, so it needs no path. For a page per file, run
`bisect-ppx-report html -o _build/coverage` and open
`_build/coverage/index.html`. Write the pages under `_build`, which
git already ignores.

The properties draw a new seed on each run, so the total moves by up
to about 0.6 of a per cent between runs of the same tree. Read the
lowest of several runs, not one run.

An instrumented build writes over `_build`. The next ordinary
`dune build` compiles the whole OCaml tree again. It does not build
the Rust crate again: cargo builds outside `_build`, so it finds its
work done.

CI runs the same commands on `ubuntu-latest` and fails below the
minimum that the `coverage` job sets. That job holds the number. A
change does not lower the coverage.

### Mutation testing

Coverage counts the lines that the tests run. It cannot see whether a
test checks what it runs. Mutation testing measures that. A tool makes
one small change to the source, such as `<=` where the code says `<`,
and runs the suite with that change switched on. The changed program
is a **mutant**. A mutant that makes a test fail is **killed**. A
mutant that the whole suite passes on **survives**, and it names a
behaviour that no test checks. A mutant that makes the suite run past
its time limit counts as killed. The **mutation score** is the share
of the mutants that were killed.

Sinter measures `lib/` and `bin/` with the project's fork of `mutaml`;
`docs/decisions/mutation-testing.md` gives the reasons for the fork.
The fork needs no other command, except `git` for the option
`--changed-since`. Pin it into the project's switch once:

```
opam pin add -y -n mutaml \
  git+https://github.com/lathrys-at/mutaml.git#b3c6b062522d1b8ac3b9615f84320e5d7e8d8ac8
opam install mutaml
```

The pin names a commit and never a branch, as the pin of `bisect_ppx`
does, and the `mutation` job pins the same commit. The pin is not in
`dune-project` or in the lock file, because the tool is not a
dependency of the package. The install changes no version that the
lock file pins. A move of the pin is a pull request of its own that
names the new commit.

**A full pass.** From the repository root:

```
MUTAML_MUT_RATE=100 MUTAML_SEED=42 \
  dune build @runtest --force --instrument-with mutaml
cores=$(getconf _NPROCESSORS_ONLN)
mutaml-runner --build-context _build/default \
  -j "$(( cores > 1 ? cores - 1 : 1 ))" \
  --repeat 3 --test-env 'QCHECK_SEED={}' \
  --baseline-env QCHECK_SEED=2 \
  test/run-mutants.sh
mutaml-report --fail-under 95 \
  --markdown _mutations/summary.md \
  --json-report _mutations/report.json
```

This is the pass that the `mutation` job makes on `main`.

**A pass on a branch.** Run `git fetch origin`, and put
`--changed-since origin/main` in front of the script name in the
`mutaml-runner` line. The runner then tests only the mutants on the
lines that the branch changed, and the score is a share of those. When
no mutant sits on a changed line, `mutaml-report` says that the run has
no score and exits 0. The `mutation` job makes this pass on a pull
request, and it skips a pull request that changed no file under `lib/`
or `bin/` (`docs/decisions/mutation-job-scope.md`).

**What each part does.**

- `--instrument-with mutaml` switches the instrumentation on. Without
  it, a build carries no instrumentation and costs nothing.
  `MUTAML_MUT_RATE=100` puts a mutant at every place that can hold
  one. `MUTAML_SEED` fixes the draw, which decides anything only at a
  rate below 100. The build writes one side file for each instrumented
  source file in `_build/.mutaml/default`.
- `test/run-mutants.sh` is the test command. The suite reads its
  fixtures from paths relative to its own folder under `_build`, so
  the script starts at the root, where the runner starts it, and runs
  the suite in that folder.
- `-j` is the number of mutants that the runner tests at one time: the
  number of cores less one, and never below 1.
  `getconf _NPROCESSORS_ONLN` gives the number of cores on macOS and on
  Linux; the `mutation` job uses `nproc`.
- `--repeat 3` with `--test-env 'QCHECK_SEED={}'` runs a mutant up to
  three times. The runner replaces `{}` with the number of the run, so
  the seeds are 1, 2, and 3. A mutant that any run kills is killed.
  The property tests draw a new seed on each ordinary run, and one
  fixed seed can miss a change that another seed catches.
- `--baseline-env QCHECK_SEED=2` checks the suite itself. The runner
  runs the suite twice with no mutant, under the seeds 1 and 2, and
  stops when the two runs disagree, because a suite that answers
  differently under two seeds gives the score no meaning. Give
  `--baseline-env` a fixed seed and never `{}`: both runs with no
  mutant are run number 1, so `{}` would compare a run with itself.
- The runner sets the time limit of one run: five times the run with
  no mutant, and never less than 10 seconds. Give `--timeout` only to
  set the limit yourself, and never near the time that the suite
  really takes: a run cut short counts as a kill, and the score then
  reads higher than it is.
- `mutaml-report` reads `mutaml-report.json`, which the runner writes
  at the root. It prints the score and, for each survivor, its name
  and a diff of the change. `--markdown` writes the same report with
  one row per source file. `--json-report` writes the
  mutation-testing-elements format that Stryker, Infection, and Mull
  share. Run the report after a pass of the runner: the runner makes
  the folder `_mutations/`, and the report does not.

**Rules for a pass.**

1. Start the runner at the repository root. Started anywhere else, it
   finds no side file and tests nothing, and `mutaml-report` then
   prints `Found no test results` and exits 1. A full pass makes
   several hundred mutants; a much smaller number means that the pass
   missed part of the tree.
2. Run no other `dune` command while a pass runs, and build again with
   `--instrument-with mutaml` after any ordinary `dune` command. An
   ordinary build links the executables again without the
   instrumentation. After an ordinary build of the whole tree, almost
   every mutant survives. A build beside a pass can leave one
   executable with the instrumentation and the other without it; every
   mutant of one source file then reads as a survivor, and that is the
   sign of this mistake.
3. A `dune` command during a pass also does a second harm. The suite
   writes its logs in one folder per run under
   `_build/default/test/_build/_tests`, and `dune` removes those
   folders. A run whose folder goes away dies, and the runner counts
   any run that fails as a kill, so the score then holds kills that no
   test made. `dune clean`, or the next ordinary build, removes the
   folders after a pass.
4. Run `dune clean` first when `MUTAML_MUT_RATE` or `MUTAML_SEED`
   differs from the last pass. `dune` does not always build again when
   only an environment variable changed.
5. Hold one core back. The runner takes the time limit from the run
   with no mutant, which it makes before any worker starts, on an idle
   machine. On a machine whose every core is busy, a later run can pass
   the limit through waiting alone, and the run then counts as a kill.
   Two mutants of the current tree hang the suite, so the column
   "timed out" of the report counts 2. A larger number on a pass that
   changed no source means that the machine was too busy.
6. Keep the suite safe to run in parallel, or set `-j` to 1. Three
   facts make it safe: the test command is a script and not `dune`,
   which locks the build folder; every file that the suite writes has
   a name from `Filename.temp_file`, under the worker's own `TMPDIR`,
   which the runner removes at the end of the pass; and neither `lib/`
   nor `bin/` keeps a cache on disk. A cache added later must write
   whole files, by writing a temporary file and renaming it, or live
   under `TMPDIR`.
7. Keep a value that only a release build can set out of the measured
   code. A branch of the code that only a release build takes is a
   branch that no test can reach. Read such a value in `bin/` and pass
   it to a function of the library, as `bin/main.ml` passes the package
   version and the output of `git describe` to
   `Sinter_core.Version.render`, and test that function with each
   value.

**Read every survivor.** Read the survivors that a report names on
every run, green or not: a run above the gate can still hold a
survivor, and nothing else draws a reader to it. Read a survivor as a
question: which test would have failed on this change? That test is
the answer. A few survivors have no answer, because no input can tell
the change from the original. Those are **equivalent mutants**, and
the next part says how to mark one.

**How to mark a mutant that no test can kill.** Write
`[@mutaml.skip "reason"]` on the smallest expression that holds the
mutant, and put that expression in parentheses:

```
let is_ready count = ((count >= 1) [@mutaml.skip "..."])
```

The attribute binds to the expression right in front of it, and it
binds tighter than an operator, so `count >= 1 [@mutaml.skip "..."]`
marks the `1` alone and leaves the comparison to be mutated. A mark
takes out every mutant inside the expression it names, the mutants
that the tests kill among them, so name no larger an expression than
the place needs. The reason is a string, and it is not optional: a
mark with no reason, with an empty reason, or with a payload that is
not a string stops the build with a message that names the file and
the line. A marked place is no mutant: it is outside the score, and
every report names it, its line, and its reason. The JSON report
gives it the status `Ignored` and the reason in `statusReason`.

A mark is a claim: that no input can tell the changed program from
the original. A mark that is wrong hides a gap in the tests for as
long as it stands, and no later pass will find that gap again. So
write the reason as a reader can check it against the code, name the
property that makes the two programs one, and read a mark in review
as closely as you read the code around it. Never mark a gap. When a
test could kill the mutant, that test is the answer, and the mark is
a way of not writing it.

**The gate.** `mutaml-report` exits 0 when the score is at or above
`--fail-under`, 2 when it is below, and 1 when the tool could not do
its work. Give it the number that the `mutation` job holds in
`MUTATION_MINIMUM`, so that a pass on your own machine answers as the
job does. The job is not a required check: it never holds a merge, and
a failure stays red on the pull request for the author and the
reviewer to read. The number is fixed at 95 by a ruling of the
maintainer (`docs/decisions/mutation-gate.md`). It does not rise when
the score rises, it does not fall, and it changes only on another
ruling of the maintainer.

95 is the gate and not the target. **The score to aim for is 100.**
The job prints the score of every run in its summary and names every
mutant that survived. The gap between 95 and 100 is there so that one
mutant that nobody has got to yet does not stop a pull request that is
sound in every other way; it is not room to leave survivors in.

## New files

A new file under `lib/`, `bin/`, `bridge/`, `test/`, `spec/`,
`docs/`, or `.github/` needs an SPDX header with the license of its
directory, and the line `Copyright <year> The Sinter Authors`:

<!-- REUSE-IgnoreStart -->
- OCaml: `(* SPDX-License-Identifier: Apache-2.0 *)`
- Rust: `// SPDX-License-Identifier: Apache-2.0`
- C: `/* SPDX-License-Identifier: Apache-2.0 */`
- dune files: `; SPDX-License-Identifier: Apache-2.0`
- YAML, TOML, and shell: `# SPDX-License-Identifier: Apache-2.0`
- Markdown in `spec/` and `docs/`:
  `<!-- SPDX-License-Identifier: CC-BY-4.0 -->`
<!-- REUSE-IgnoreEnd -->

Four kinds of file carry no header, and `REUSE.toml` gives each the
license of its directory: files at the repository root; files whose
format has no comment, such as JSON; files that a tool generates,
such as `bridge/Cargo.lock` and `sinter.opam`; and the plan files
under `.plans/` and the skill files under `plugins/`. Keep the two
ignore markers around the list above. The markers
stop the `reuse` tool from reading the examples as license tags for
this file.

## Commits

- Sign off every commit with `git commit -s`. The line certifies
  that your contribution satisfies the Developer Certificate of
  Origin; the DCO file holds the full text. CI rejects a commit that
  has no sign-off.
- Use an imperative subject line and a short body that says what
  changed and why.
- Do not commit build output. `.gitignore` covers `_build/`.

### Changes written by agents

Coding agents write much of this codebase. We expect this practice and
we welcome it. The human who runs the agent signs off the commit. That
human is the contributor of record. When an agent wrote a large part of
a change, add a trailer to the commit message that names the agent. You
can use either of these two trailers:

- `Assisted-by: Claude Code` — the agent helped; the human is the
  author.
- `Co-Authored-By: Claude Code <noreply@anthropic.com>` — the agent is
  named as a co-author. GitHub shows co-authors next to the commit.

Both trailers keep the record of authorship in the git history. Do not
sign off code that you did not review.

## Decisions, plans, and rulings

- Decisions that shape the project live in `docs/decisions/`, one file
  per decision, with a `@decision` tag. Read the record before you
  re-argue a choice. To record a new decision, use the
  `/sinter:decision` skill or follow its format. "Alternatives
  considered" lists only the alternatives that someone put forward
  and that were deliberated: in an issue, a pull request, a plan, the
  design notes, or with the maintainer. When nobody put one forward,
  the section says so. A decision that rests on measurements carries
  them.
- A record states a choice, the options that were put forward, and
  the reasons. It holds no format, no protocol, no interface, and no
  account of how something is built; those belong in `spec/`, in the
  interface files, and in the help text. A record fits on one screen.
- A record is written from a ruling of the maintainer: an issue, a
  comment on a pull request, or a plan the maintainer approved.
  Nobody writes a record for a choice the maintainer did not make.
- Implementation work follows a plan in `.plans/`, written with the
  `/sinter:plan` skill. A change to a plan's promises or scopes is an
  amendment. Make it a separate, small pull request, so that the
  maintainer's merge is the approval.
- Ask a design question in a GitHub issue, with the options and their
  costs. The maintainer rules; the ruling is then carried out in a
  pull request.

## Pull requests

Every change reaches `main` through a pull request. The maintainer
reviews and merges; merges are squash merges.

A pull request description is documentation for the people who review
the change and for the people who read it later. It says what the
change adds, what it does not do, measurements when there are any,
and where to look first. It follows the writing rules above. It does
not describe the process that produced the change.

Before you open a pull request that touches `lib/` or `bin/`, run the
mutation pass on your branch with `--changed-since origin/main`, as
"Mutation testing" above says, and read every survivor. The `mutation`
job makes the same pass on the pull request, and its result does not
hold the merge, so the pass on your machine is the one that catches a
gap before a reviewer sees it. Put the score and the survivors in the
pull request description when the pass found any.

A review comment names an example of a defect, not its only instance.
When you address a comment, find and fix every instance of the same
defect across the whole change.

## Licensing of contributions

Sinter uses two licenses:

- The code uses the Apache-2.0 license. See the LICENSE file.
- The specifications and the documentation use the CC-BY-4.0 license.
  See the LICENSE-SPEC file.

When you contribute, you agree to one condition: your contribution uses
the same license as the file that it changes. People call this model
"inbound = outbound". We do not use a Contributor License Agreement (CLA).

## Third-party code

Do not copy code from other projects, unless both conditions below are
true:

1. The license of the code is compatible with Apache-2.0.
2. You add the code to THIRD_PARTY.md.

Never copy GPL or AGPL code into this repository.
