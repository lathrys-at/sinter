#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Sinter Authors

# Run the test suite for one mutant, where the suite's fixtures are.
#
# mutaml-runner starts at the root of the project: that is where it
# finds the preprocessor's side files, under _build/.mutaml/default,
# and where the source paths inside them resolve. The test suite
# cannot start there. It reads its fixtures from paths relative to its
# own directory in the build tree, so it must start in that directory.
#
# This script joins the two. The runner starts it at the root, once
# for the unmutated baseline and once for each mutant, and it starts
# the suite in the build copy of test/. Give the runner this script as
# its test command:
#
#     mutaml-runner --build-context _build/default test/run-mutants.sh
#
# The runner passes no arguments of its own. Any argument given here
# goes on to the suite.
#
# The script replaces itself with the suite, so that the suite's exit
# status is this script's status and a signal reaches the suite. The
# runner reads that status to tell a killed mutant from a mutant that
# ran too long or died of a signal.

set -eu

# The script stands in test/ in the source tree, so the directory
# above it is the root of the project. Start the copy in the source
# tree. Should dune ever copy this script into _build, that copy would
# read the root as _build/default, which holds no build tree of its
# own, and the check below would stop it.
#
# The line below carries two guards, and they stop two different
# things. CDPATH='' stops cd from going somewhere else: the runner
# starts this script as test/run-mutants.sh, so the operand of cd is
# "test/..", which does not begin with "." or "..", and cd therefore
# searches any CDPATH the reader's shell holds. A CDPATH that names a
# directory with a test/ in it would send cd there. The redirection
# stops cd from printing the directory it chose, which under a CDPATH
# it does, and which would land inside the command substitution and
# become part of the path. Keep both. The empty string is written out
# so that shellcheck does not read CDPATH= as a mistyped assignment.
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." >/dev/null && pwd)
suite=$root/_build/default/test/test_sinter.exe

if [ ! -x "$suite" ]; then
  echo "run-mutants.sh: no test suite at $suite" >&2
  echo "Build it first, with the code instrumented:" >&2
  echo "  dune build @runtest --force --instrument-with mutaml" >&2
  echo "and start the runner from the root of the project." >&2
  exit 2
fi

cd -- "$root/_build/default/test"
exec "$suite" "$@"
