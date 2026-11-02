#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Sinter Authors

set -eu

usage() {
  echo "Usage: test/run-mutant-share.sh [-j <workers>] [-s <number>] [-c <revision>] <output> <mutation file>..." >&2
  echo "Tests the mutants of each mutation file under two seeds, and joins the reports into one report at <output>." >&2
  echo "  -j <workers>   the number of mutants to test at one time; the default is 1" >&2
  echo "  -s <number>    the seeds are <number>1 and <number>2; the default is a random number" >&2
  echo "  -c <revision>  test only the mutants on the lines that changed since <revision>" >&2
  echo "Start it at the root of the project, after a build with --instrument-with mutaml." >&2
  exit 2
}

workers=1
number=
since=
while getopts j:s:c: option; do
  case $option in
    j) workers=$OPTARG ;;
    s) number=$OPTARG ;;
    c) since=$OPTARG ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ "$#" -ge 2 ] || usage
output=$1
shift

case $workers in '' | *[!0-9]* | 0) usage ;; esac
if [ -z "$number" ]; then
  number=$(od -An -N4 -tu4 /dev/urandom | tr -d ' \n')
fi
case $number in
  '' | *[!0-9]*)
    echo "run-mutant-share.sh: the value of -s must hold only digits." >&2
    exit 2
    ;;
esac
if [ "${#number}" -gt 17 ]; then
  echo "run-mutant-share.sh: the value of -s must hold 17 digits or fewer." >&2
  exit 2
fi

echo "The seeds of the property tests are ${number}1 and ${number}2."
echo "To test this share again under the same seeds, give the option -s $number."
echo "To test one mutant again, build the tests with the code instrumented, and run at the root:"
echo "  MUTAML_MUTANT=<name of the mutant> QCHECK_SEED=${number}1 test/run-mutants.sh"
echo "and then the same command with QCHECK_SEED=${number}2."

dir=_mutations/share
log=_mutations/runner.log
rm -rf "$dir"
mkdir -p "$dir"
: >"$log"

total=$#
index=0
for file in "$@"; do
  index=$((index + 1))
  echo "Testing the mutants of $file ($index of $total)." | tee -a "$log"
  rm -f mutaml-report.json "$dir/status"
  {
    status=0
    if [ -n "$since" ]; then
      mutaml-runner --build-context _build/default -j "$workers" \
        --repeat 2 --test-env "QCHECK_SEED=${number}{}" \
        --baseline-env "QCHECK_SEED=${number}2" \
        --changed-since "$since" --muts "$file" test/run-mutants.sh || status=$?
    else
      mutaml-runner --build-context _build/default -j "$workers" \
        --repeat 2 --test-env "QCHECK_SEED=${number}{}" \
        --baseline-env "QCHECK_SEED=${number}2" \
        --muts "$file" test/run-mutants.sh || status=$?
    fi
    echo "$status" >"$dir/status"
  } 2>&1 | tee -a "$log"
  if [ ! -f "$dir/status" ]; then
    echo "mutaml-runner did not finish on $file."
    exit 1
  fi
  status=$(cat "$dir/status")
  if grep -q '^Skipping ' "$log"; then
    echo "The runner skipped a mutation file, so the pass did not" \
      "measure the whole tree. The lines above that start with" \
      "Skipping name the files. Run dune clean and build again."
    exit 1
  fi
  if [ "$status" != 0 ]; then
    echo "mutaml-runner failed with status $status on $file."
    exit "$status"
  fi
  if [ ! -f mutaml-report.json ]; then
    echo "mutaml-runner wrote no report for $file."
    exit 1
  fi
  mv mutaml-report.json "$dir/$index.json"
done

set --
index=0
while [ "$index" -lt "$total" ]; do
  index=$((index + 1))
  set -- "$@" "$dir/$index.json"
done
sh test/join-mutant-reports.sh "$output" "$@"
rm -f "$dir/status"
echo "The report of the $total mutation files is in $output."
