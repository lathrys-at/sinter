(lang dune 3.16)
; SPDX-License-Identifier: Apache-2.0
; Copyright 2026 The Sinter Authors
(name sinter)
(license Apache-2.0)
(generate_opam_files true)
(authors "The Sinter Authors")
(maintainers "The Sinter Authors")
(source (github lathrys-at/sinter))
(homepage "https://github.com/lathrys-at/sinter")
(bug_reports "https://github.com/lathrys-at/sinter/issues")

(package
 (name sinter)
 (synopsis "Plan, specification, and test tracing for agentic coding workflows")
 (description
  "Sinter reads tags in a repository's own text files. It uses them to check that code, tests, and documents keep the agreements a project made. It reads the state of the work from files and from test results, never from an agent's self-report. The design is in docs/design-notes.md; the formats are specified in spec/.")
 (depends
  (ocaml (>= 5.1))
  dune
  (cmdliner (>= 1.3))
  dune-build-info
  (alcotest :with-test)
  (ocamlformat
   (and
    :with-dev-setup
    (= 0.29.0)))))
