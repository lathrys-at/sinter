# Bootstrap: decisions, dogfooding, and the first parser
@plan bootstrap
@scope .claude-plugin/**, .claude/**, plugins/**, docs/decisions/**, .plans/**, bridge/**, lib/**, bin/**, test/**, .github/workflows/**, THIRD_PARTY.md, README.md, CONTRIBUTING.md, CLAUDE.md, dune-project, sinter.opam, .gitignore, REUSE.toml, LICENSES/**
Write a decision record for each decision that the project made so
far. Ship the Claude Code skill pack. Make `sinter parse` and
`sinter serve` work with a wasm grammar through a Rust bridge.

## Ship the skill pack
@scope .claude-plugin/**, .claude/**, plugins/**, docs/decisions/**, .plans/**, README.md
@decision skills-distribution
The skill pack is the plugin marketplace, the `sinter` plugin, and
the settings that make this repository use the plugin. Add all three.
The plugin holds the `plan` skill and the `decision` skill. Use both
skills one time. This plan file is the first output of the `plan`
skill. The decision record for the pack is the first output of the
`decision` skill.

## Record the decisions made so far
@scope docs/decisions/**, CONTRIBUTING.md, CLAUDE.md
@decision implementation-language
@decision licensing
@decision ste-adoption
@decision versioning
@decision branch-workflow
Write one record for each decision that the project made before this
plan. A rule can then cite the record that holds its origin. Nobody
needs to re-argue the decision.

## Build the parser bridge
@scope bridge/**, lib/**, bin/**, test/**, .github/workflows/**, THIRD_PARTY.md, docs/decisions/**, dune-project, sinter.opam, .gitignore, REUSE.toml, LICENSES/**, CONTRIBUTING.md
@decision parser-bridge
@decision json-handling
Add three things: the Rust bridge that loads a wasm grammar through
wasmtime, the OCaml stubs over the six functions of the bridge, and
`sinter parse`. The `parse` command prints captures as JSONL. Record
these measurements in the decision record:

- the binary size
- the load time
- the parse time
- the wasm import section
- the link on both platforms

## Add the serve mode
@scope bin/**, lib/**, docs/decisions/**
@decision serve-mode
Add `sinter serve`. The command reads requests as JSON lines on
stdin. It answers with the same JSONL that the one-shot commands
print. The process is a child of its caller. The process exits when
stdin closes.
