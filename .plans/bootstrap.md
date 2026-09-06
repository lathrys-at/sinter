# Bootstrap: decisions, dogfooding, and the first parser
@plan bootstrap
@scope .claude-plugin/**, .claude/**, plugins/**, docs/decisions/**, .plans/**, bridge/**, lib/**, bin/**, test/**, .github/workflows/**, THIRD_PARTY.md, README.md, CONTRIBUTING.md, CLAUDE.md
Record the decisions made so far as decision records, ship the Claude
Code skill pack, and make `sinter parse` and `sinter serve` work with a
wasm grammar through a Rust bridge.

## Ship the skill pack
@scope .claude-plugin/**, .claude/**, plugins/**, docs/decisions/**, .plans/**, README.md
@decision skills-distribution
Add the plugin marketplace, the `sinter` plugin with the `plan` and
`decision` skills, and the settings that make this repository use its
own pack. Use both skills once: this plan file and the decision record
for the pack are their first outputs.

## Record the decisions made so far
@scope docs/decisions/**, CONTRIBUTING.md, CLAUDE.md
@decision implementation-language
@decision licensing
@decision ste-adoption
@decision versioning
@decision branch-workflow
Write one record for each decision that was made before this plan, so
that rules can cite their origin and nobody re-argues them.

## Build the parser bridge
@scope bridge/**, lib/**, bin/**, test/**, .github/workflows/**, THIRD_PARTY.md, docs/decisions/**
@decision parser-bridge
@decision json-handling
Add the Rust bridge that loads a wasm grammar through wasmtime, the
OCaml stubs over its six functions, and `sinter parse`, which prints
captures as JSONL. Record the measurements — binary size, load time,
parse time, the wasm import section, and the link on both platforms —
in the decision record.

## Add the serve mode
@scope bin/**, lib/**, docs/decisions/**
@decision serve-mode
Add `sinter serve`, which reads requests as JSON lines on stdin and
answers with the same JSONL the one-shot commands print. The process
is a child of its caller and exits when stdin closes.
