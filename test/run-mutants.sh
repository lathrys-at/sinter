#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Sinter Authors

set -eu

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
exec "$suite" --bail "$@"
