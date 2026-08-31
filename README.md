# Sinter

Sinter is a development tool for projects where AI agents write code.
Agents often forget plans and conventions when their context changes.
Sinter records agreements as tags in the project's own text files. It
then checks that the code, the tests, and the documents keep those
agreements. It reads the state of the work from files and from test
results. It never trusts what an agent reports about its own work.

Sinter is new and under construction. The full design is in
[docs/design-notes.md](docs/design-notes.md). The formats that other
tools can implement are specified in [spec/](spec/).

## Build

Sinter is written in OCaml. To build it, install
[opam](https://opam.ocaml.org/) and an OCaml switch (5.1 or newer).
Then run:

```
opam install . --deps-only --with-test
dune build
dune test
```

## Versioning

The specifications in `spec/` share one semantic version, separate
from the tool's own version. See
[docs/versioning.md](docs/versioning.md).

## License

The tool is licensed under Apache-2.0. See the LICENSE file. The
specifications and the design notes are licensed under CC-BY-4.0. You can
implement the specifications freely, without permission. See the
LICENSE-SPEC file. Language packs keep the upstream licenses of their
grammars. We accept contributions under a Developer Certificate of
Origin (DCO). See CONTRIBUTING.md.
