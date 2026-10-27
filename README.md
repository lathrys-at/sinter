# Sinter

A linter for keeping your specs, plans, and code in sync.

Sinter reads the tags in your repository's files: specs, plans,
decision records, and the code and tests that refer to them. It
reports where they have drifted apart, for example a test that checks
an old version of a spec, or a plan step whose promised work never
showed up.

It is built for projects where coding agents write much of the code.
Agents lose track of plans when their context changes, and sometimes
they say work is done when it isn't. Sinter checks the files and the
test results, never what an agent says about its own work.

Sinter is new and under construction. The full design is in
[docs/design-notes.md](docs/design-notes.md). The [spec/](spec/)
directory specifies the formats that other tools can implement.

## Build

We write Sinter in OCaml, and its parser bridge in Rust. To build
it, install [opam](https://opam.ocaml.org/), the Rust toolchain from
[rustup](https://rustup.rs), and `cmake`, which a build script of
wasmtime runs. Create an opam switch with the compiler that
`sinter.opam.locked` pins, 5.5.2; the install below fails on any other
compiler. Then, from the repository root:

```
opam switch create 5.5.2
eval $(opam env --switch=5.5.2)
opam install . --deps-only --with-test --with-dev-setup --locked
dune build
dune test
```

`CONTRIBUTING.md` has the full list of checks to run before a commit.

Sinter runs the `git` program, and it needs git 2.43.7 or later. A
distribution's build of an older version that carries the same
security fixes also works, such as git 2.43.0 in Ubuntu 24.04.

## jj

[jj (Jujutsu)](https://docs.jj-vcs.dev/latest/) is a version control
system that can keep its data in a git repository. Sinter works in a
colocated jj repository: a repository with a `.git` folder next to
the `.jj` folder. Since version 0.34.0, jj makes new repositories
colocated by default. Sinter reads such a repository through the
`git` program, as it reads any git repository.

Use jj 0.45.0 or later. Earlier versions can leave a stale cache in
the git index, and the tree that Sinter computes for the working tree
is then wrong ([jj-vcs/jj#9711](https://github.com/jj-vcs/jj/issues/9711)).

Sinter does not work yet in a jj repository that is not colocated. It
also does not work yet in a jj workspace that has no `.git`, such as a
workspace that `jj workspace add` made before jj 0.46.0.

## Skills for Claude Code

This repository is also a Claude Code plugin marketplace. The `sinter`
plugin holds two skills:

- `/sinter:plan` turns an approved plan into a plan file under
  `.plans/`.
- `/sinter:decision` writes a decision record under `docs/decisions/`.

To install the plugin, run these two commands inside Claude Code:

```
/plugin marketplace add lathrys-at/sinter
/plugin install sinter@sinter
```

The skills live in [plugins/sinter/skills/](plugins/sinter/skills/).

## Versioning

The specifications in `spec/` share one semantic version, separate
from the tool's own version. See
[docs/versioning.md](docs/versioning.md).

## License

The tool uses the Apache-2.0 license. See the LICENSE file. The
specifications and the design notes use the CC-BY-4.0 license. You can
implement the specifications freely, without permission. See the
LICENSE-SPEC file. Each language pack keeps the upstream license of its
grammar. We accept contributions under a Developer Certificate of
Origin (DCO). See CONTRIBUTING.md.
