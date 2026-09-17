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

Install [opam](https://opam.ocaml.org/) and an OCaml switch (5.1 or
newer). The parser bridge in `bridge/` is a Rust crate, so also
install the Rust toolchain with [rustup](https://rustup.rs) and
install `cmake`, which a build script of wasmtime runs. Then, from the
repository root:

```
eval $(opam env)
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
- `reuse lint` (run it with `pipx run reuse lint`).
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
test checks what it runs, so a coverage number rises with tests that
check nothing. Mutation testing measures that. A tool makes one small
change to the source, such as `<=` where the code says `<`, and runs
the suite with that change switched on. The changed program is a
mutant. A mutant that makes a test fail is killed. A mutant that the
whole suite passes on has survived, and it names a behaviour that no
test checks. The mutation score is the share of the mutants that were
killed. A mutant that makes the suite run past its time limit counts
as killed, because a run that never ends is a fault the suite found.

Sinter measures `lib/` and `bin/` with the project's fork of `mutaml`.
The released tool does not build on the compiler in
`sinter.opam.locked`, loses its working files under the current
`dune`, and makes no mutant of a comparison operator;
`docs/decisions/mutation-testing.md` gives the reasons for the fork.

`mutaml` needs no command of the system for the run this project
makes. It needs no `diff` command: `mutaml-report` writes the diff of
a mutant itself. It needs no `timeout` command: the runner starts each
test run itself and stops a run that goes on too long. The one option
that needs a command of the system is `--changed-since`, which asks
`git` which lines a branch touched; the `mutation` job gives it on a
pull request, and the pass on a branch below gives it too.

Pin the fork into the project's switch once:

```
opam pin add -y -n mutaml \
  git+https://github.com/lathrys-at/mutaml.git#b3c6b062522d1b8ac3b9615f84320e5d7e8d8ac8
opam install mutaml
```

The pin names a commit and never a branch, so that every run installs
the same code, as the pin of `bisect_ppx` above does. It does not
enter `dune-project` or the lock file, because the tool is not a
dependency of the package. The `mutation` job pins the same commit.
Moving a pin is a pull request of its own that names the new commit.
The install adds `mutaml` and the packages it needs, among them
`ppxlib` 0.36 or newer, which the `bisect_ppx` pin above also asks
for. It changes no version that the lock file pins.

Then, from the repository root:

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

That is the full pass, the one the `mutation` job makes on `main`.
On a branch, put `--changed-since origin/main` in front of the script
name in the `mutaml-runner` line, after `git fetch origin`. The runner
then tests only the mutants that sit on a line the branch changed,
and records every other mutant as not run and outside the score. The
score is then a share of what the branch touched, and a survivor in
it is one the branch made or uncovered. When no mutant sits on a
changed line, `mutaml-report` says the run has no score and exits 0.
The `mutation` job makes this pass on a pull request, and it skips
the job when the pull request changed no file under `lib/` or `bin/`;
`docs/decisions/mutation-job-scope.md` holds the rule.

`--instrument-with` is the switch, as it is for coverage. Without it
the build carries no instrumentation and costs nothing.
`MUTAML_MUT_RATE=100` puts a mutant at every place that can hold one,
so that a pass covers the whole set, and `MUTAML_SEED` fixes the draw,
which decides anything only at a rate below 100. The build writes one
side file for each instrumented source file, beside the build
directory in `_build/.mutaml/default`, and the runner reads them.

**Start the runner at the repository root and nowhere else.**
`--build-context _build/default` names the build directory, and the
runner looks beside it for the side files and reads the source paths
in them from the root. Started anywhere else it finds no side file and
tests nothing; `mutaml-report` then prints `Found no test results` and
exits 1. Read the number of mutants in the report of every pass. A
pass over the whole tree makes several hundred, 380 when this was
written, so a much smaller number means that the pass missed part of
the tree.

`test/run-mutants.sh` is the test command. The suite reads its
fixtures from paths relative to its own directory under `_build`, so
the suite cannot start at the root. The script starts at the root,
where the runner starts it, and starts the suite where the fixtures
are.

The runner sets the time that one run of the suite may take, and it
takes that time from the run with no mutant: five times that run, and
never less than ten seconds. It prints the rule, and not the number
of seconds the rule gives, after the runs with no mutant, because the
number follows a measurement and a measurement differs from one
machine to the next. Give `--timeout` only to set the limit yourself,
and do not set it near the time the suite really takes: a run cut
short counts as a kill, and the score then reads higher than it is
with nothing to show it. Two mutants hang the suite instead of
failing it, and each of the two costs a pass the whole of the limit.
The "timed out" column of the report is the check: it counts 2, and a
larger number on a pass that changed no source means that the machine
was too busy for a run to finish inside the limit.

`-j` is the number of mutants the runner tests at one time. Set it to
the number of cores of the machine less one, and never below 1.
`getconf _NPROCESSORS_ONLN` gives the core count on macOS and on Linux
both; the `mutation` job works the same number out from `nproc`, which
Ubuntu has. Hold the one core back. The runner takes the time limit
from the run with no mutant, and it makes that run before any worker
starts and therefore on an unloaded machine. On a machine whose every
core is busy, a later run can pass that limit through waiting alone,
and a run stopped at the limit counts as a kill, so the score would
rise for a reason that has nothing to do with the tests. Each worker
runs a test process of its own, writes only the output file of its own
mutant, and works under a `TMPDIR` of its own, which the runner
removes at the end of the pass. The results keep the order of the
mutants, so the lines the runner prints and the report it writes do
not depend on which run ends first, and a parallel pass names the same
survivors as a serial one. Sinter's suite is safe to run this way for
three reasons: the test command is a script and not `dune`, which
locks the build directory and which the runner therefore refuses to
run more than once at a time; every file the suite writes has a name
from `Filename.temp_file`, which no other worker draws and which lies
under the worker's own `TMPDIR`; and neither `lib/` nor `bin/` keeps a
cache on disk, so no two workers can read a half-written one. Keep all
three true, or lower `-j` to 1. A cache added later must write whole
files, by writing a temporary file and renaming it, or live under
`TMPDIR`.

`--repeat 3` gives one mutant three runs, and `--test-env
QCHECK_SEED={}` gives each of the three a seed of its own: the runner
replaces the two characters `{}` by the number of the run, counted
from 1, so the seeds are 1, 2, and 3. A mutant that any one of the
three runs kills is killed, and only a mutant that all three pass is a
survivor. Sinter's property tests draw a new seed on each ordinary
run, which is why a pass fixes one, and one fixed seed can miss a
change that another seed catches. Without the three runs, such a
mutant reads as a survivor, and it sends a reader looking for a test
that the suite already holds. A survivor costs three runs of the
suite; a killed mutant usually still costs one, because most mutants
die under the first seed.

`--baseline-env QCHECK_SEED=2` is a check on the suite, not on the
mutants. The runner runs the suite twice with no mutant and stops
when the two runs disagree, because a suite that answers differently
under two seeds gives the score no meaning. The first of the two
takes its seed from `--test-env`, and the runner counts a run with no
mutant as run number 1, so `{}` there gives 1; the second takes
`QCHECK_SEED=2`. The two runs therefore use the seeds 1 and 2, as
they did before `--repeat`. Give `--baseline-env` a seed of its own
and never `{}`: both runs with no mutant are run number 1, so `{}`
would give 1 in each of them and the check would compare a run with
itself.

`mutaml-report` reads `mutaml-report.json`, which the runner wrote at
the root, so it needs no path. It prints the score and, for each
survivor, the name of the mutant and a diff of the change that
survived. Read a survivor as a question: which test would have failed
on this change? The answer is the test to write. A few survivors have
no answer, because no input can tell the change from the original;
those are equivalent mutants, and the part below says how to mark
one. `--markdown` writes the same report as a file with a table of
one row per source file, and `--json-report` writes the
mutation-testing-elements format that Stryker, Infection, and Mull
share, which the HTML viewer of that format reads. Both paths above
are inside `_mutations/`, which git ignores. The runner makes that
directory in the step above, and `mutaml-report` does not make it, so
run the report after a pass of the runner and not on its own in a
clean tree.

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

`mutaml-report` exits 0 when the score is at or above `--fail-under`,
2 when it is below, and 1 when the tool could not do its work. Give it
the number that the `mutation` job holds in `MUTATION_MINIMUM`, so
that a pass on your own machine answers as the job does. The job is
not a required check: it never holds a merge, and a failure stays red
on the pull request for the author and the reviewer to read. The
maintainer fixed that number at 95 on 2026-09-16. It does not follow
the measurement: it does not rise when the score rises and it does not
fall, and it changes only on another ruling of the maintainer.

95 is the gate and not the target. **The score to aim for is 100.**
The job prints the score of every run in its summary and names every
mutant that survived, so the number a pull request reached is on the
page whether the gate passed or not. The gap between 95 and 100 is
there so that one mutant nobody has got to yet does not stop a pull
request that is sound in every other way; it is not room to leave
survivors in. Read every survivor the summary names. The answer is
the test that kills it, or, when no input can tell the change from
the original, a mark with a reason, as the part above says.

An instrumented build writes over `_build`, as a coverage build does,
and the next ordinary `dune build` compiles the whole OCaml tree
again. `dune` does not always build again when only an environment
variable changed, so run `dune clean` first when the variables of this
pass differ from those of the last one.

**Build again with `--instrument-with mutaml` after any ordinary
`dune` command, and never run one while a pass is running.** An
ordinary build carries no instrumentation and relinks what it builds
without it. Measured here from a clean tree: after the instrumented
build, `bin/main.exe` and `test/test_sinter.exe` both carried the
instrumentation; after a plain `dune build`, neither did.

A pass on a tree in that state measures nothing, and it shows itself
in two ways. After an ordinary build of the whole tree, nearly every
mutant survives and the score collapses, which is hard to miss. A
build that runs beside a pass is the one that hides: the two
executables can end up in different states, and the pass then reports
as survivors every mutant of the source that went plain, while the
rest of the tree reads as usual. That happened here. `bin/main.exe`
went plain, the test executable kept its instrumentation, and the
whole of `bin/main.ml` read as surviving with nothing else disturbed.
So read a whole source file surviving at once as this, and not as a
gap in the tests.

A pass leaves one directory for each run of the suite under
`_build/default/test/_build/_tests`, several hundred of them, because
`alcotest` writes its logs there and nothing removes them while the
pass runs. `dune` did not put them there, so the next ordinary
`dune build` removes them. `dune clean` removes them at once.

**This is the second reason not to run `dune` beside a pass, and it
costs you kills you did not earn.** A `dune` that runs while a pass
runs removes those directories from under the suite runs that are
still using them. Such a run dies, the runner sees a non-zero exit,
and it counts any non-zero exit as a kill. The pass then reports
mutants as caught that no test caught. This was measured on this
branch: an ordinary `dune build` started beside a pass left ten runs
of `lib/bridge/sinter_bridge.ml` at exit status 125, in one unbroken
block, which read an ordinary test failure in every later pass.

The score does not answer to the state of this checkout, and that is
worth keeping. `Sinter_core.Version.render` works out the version to
print from two values that its caller reads for it: the version of
the package, which only a build of a release carries, and the output
of `git describe`. It reads neither itself, so its tests hand it a
bare hash, the name of a tag, and the word `unknown`, and every road
of it is tested whatever this repository carries. The first release
tag will therefore change what the tool prints and not what a pass
reports.

While that logic stood in `bin/main.ml` it was the other way about.
Seven of its mutants sat on a road that only an installed build
reaches, so no test could state a fact about them; three more
answered to whether the repository carried a tag, and a pass on the
day of the first tag would have lost those three kills for a reason
that is not in the tests at all. That is the shape to watch for: a
road that only the build can choose is a road that no test can
reach, and the score then measures the build and not the suite.

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
