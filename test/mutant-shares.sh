#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Sinter Authors

set -eu

usage() {
  echo "Usage: test/mutant-shares.sh <count> <share>" >&2
  echo "Prints the mutation files of share <share> of <count>, one on each line." >&2
  echo "Start it at the root of the project, after a build with --instrument-with mutaml." >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
count=$1
share=$2
case $count in '' | *[!0-9]*) usage ;; esac
case $share in '' | *[!0-9]*) usage ;; esac
if [ "$count" -lt 1 ]; then
  echo "mutant-shares.sh: the number of shares must be 1 or more." >&2
  exit 2
fi
if [ "$share" -lt 1 ] || [ "$share" -gt "$count" ]; then
  echo "mutant-shares.sh: the share must be a number from 1 to $count." >&2
  exit 2
fi

side=_build/.mutaml/default
list=$side/mutaml-mut-files.txt
if [ ! -f "$list" ]; then
  echo "mutant-shares.sh: there is no list of mutation files at $list." >&2
  echo "Build the tests with the code instrumented, at the root of the project:" >&2
  echo "  dune build @runtest --force --instrument-with mutaml" >&2
  exit 2
fi

files=$(LC_ALL=C sort -u "$list")
if [ -z "$files" ]; then
  echo "mutant-shares.sh: the list $list names no mutation file." >&2
  exit 1
fi

set --
while IFS= read -r file; do
  set -- "$@" "$file"
done <<EOF
$files
EOF

counts=$(cd "$side" && jq -r \
  '"\(.mutants | length)\t\((.skipped // []) | length)\t\(input_filename)"' \
  "$@")

printf '%s\n' "$counts" |
  LC_ALL=C awk -F '\t' '$1 + $2 > 0' |
  LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k3,3 |
  LC_ALL=C awk -F '\t' -v count="$count" -v share="$share" '
    BEGIN { for (s = 1; s <= count; s++) { total[s] = 0; files[s] = 0 } }
    {
      best = 1
      for (s = 2; s <= count; s++) if (total[s] < total[best]) best = s
      total[best] += $1
      files[best]++
      if (best == share) print $3
    }
    END {
      line = "The " count " shares hold"
      for (s = 1; s <= count; s++)
        line = line sprintf(" %d", total[s])
      line = line " mutants."
      print line > "/dev/stderr"
      printf "Share %d holds %d mutants in %d files.\n", share, total[share], files[share] > "/dev/stderr"
    }'
