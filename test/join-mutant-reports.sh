#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Sinter Authors

set -eu

if [ "$#" -lt 2 ]; then
  echo "Usage: test/join-mutant-reports.sh <output> <report>..." >&2
  echo "Joins the reports that mutaml-runner wrote into one report at <output>." >&2
  exit 2
fi

output=$1
shift

for report in "$@"; do
  if [ ! -f "$report" ]; then
    echo "join-mutant-reports.sh: there is no report at $report." >&2
    exit 1
  fi
  if ! jq -e 'type == "object" and (.results | type) == "array"
      and ((.skipped // []) | type) == "array"' "$report" >/dev/null 2>&1; then
    echo "join-mutant-reports.sh: $report is not a report that mutaml-runner writes." >&2
    exit 1
  fi
done

twice=$(jq -n -r '
  [inputs] as $reports
  | ([$reports[] | .results[] | .mutant
      | {key: [.loc.loc_start.pos_fname, "mutant", .number],
         text: "the mutant \(.number) of \(.loc.loc_start.pos_fname)"}]
     + [$reports[] | (.skipped // [])[]
      | {key: [.loc.loc_start.pos_fname, "skip", .loc.loc_start.pos_cnum, .loc.loc_end.pos_cnum],
         text: "the marked place at line \(.loc.loc_start.pos_lnum) of \(.loc.loc_start.pos_fname)"}])
  | group_by(.key) | map(select(length > 1) | .[0].text) | .[]' "$@")
if [ -n "$twice" ]; then
  echo "join-mutant-reports.sh: the reports hold these more than once:" >&2
  printf '%s\n' "$twice" | sed 's/^/  /' >&2
  echo "Each source file must be in one report only." >&2
  exit 1
fi

partial=$output.partial
jq -n '
  [inputs] as $reports
  | {results: ([$reports[] | .results[]]
               | sort_by(.mutant.loc.loc_start.pos_fname, .mutant.number)),
     skipped: ([$reports[] | (.skipped // [])[]]
               | sort_by(.loc.loc_start.pos_fname, .loc.loc_start.pos_cnum))}' \
  "$@" >"$partial"
mv -- "$partial" "$output"
