#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Sinter Authors

# Build the Rust bridge crate as a static library, and report the
# system libraries that a static link of that crate needs.
#
# The arguments, in order:
#   1. the directory that holds the crate's Cargo.toml
#   2. the directory that cargo uses for its build output
#   3. the path to write the static library to
#   4. the path to write the dune flags file to
#
# The flags file holds one s-expression: the list of linker flags,
# as "cargo rustc --print native-static-libs" reports them. The list
# differs between macOS and Linux, so we ask the toolchain instead of
# writing the list down.

set -eu

crate=$1
target=$2
archive=$3
flags=$4

log=$target/native-static-libs.log
mkdir -p "$target"

if ! cargo rustc --release --quiet --manifest-path "$crate/Cargo.toml" \
    --target-dir "$target" -- --print native-static-libs 2>"$log"; then
  cat "$log" >&2
  exit 1
fi

cp "$target/release/libsinter_bridge.a" "$archive"

# The C compiler driver already links the C library itself. Naming it
# again makes the linker warn about a duplicate, so drop it here.
libraries=$(sed -n 's/^note: native-static-libs: *//p' "$log" | tail -n 1 |
  tr ' ' '\n' | grep -v -e '^-lSystem$' -e '^-lc$' -e '^$' | tr '\n' ' ')
if [ -z "$libraries" ]; then
  echo "The Rust toolchain reported no native-static-libs line." >&2
  cat "$log" >&2
  exit 1
fi
printf '(%s)\n' "$libraries" >"$flags"
