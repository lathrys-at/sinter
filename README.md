# Sinter

Sinter is a development tool for projects where AI agents write code.
Agents often forget plans and conventions when their context changes.
Sinter records agreements as tags in the project's own text files. It
then checks that the code, the tests, and the documents keep those
agreements. It reads the state of the work from files and from test
results. It never trusts what an agent reports about its own work.

Sinter is new and under construction. The full design is in
[docs/design-notes.md](docs/design-notes.md). The [spec/](spec/)
directory specifies the formats that other tools can implement.

## Build

We write Sinter in OCaml. To build it, install
[opam](https://opam.ocaml.org/) and an OCaml switch (5.1 or newer).
Then run:

```
opam install . --deps-only --with-test
dune build
dune test
```

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
