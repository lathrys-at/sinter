#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Sinter Authors

# Build the Rust bridge crate as a static library, and report the
# system libraries that a static link of that crate needs.
#
# The arguments, in order:
#   1. the directory that holds the crate's Cargo.toml
#   2. the directory for cargo's build output, when neither
#      CARGO_TARGET_DIR nor a home directory says where to put it
#   3. the path to write the static library to
#   4. the path to write the dune flags file to
#
# The flags file holds one s-expression: the linker flags that
# "cargo rustc --print native-static-libs" reports. The list differs
# between macOS and Linux.

set -eu

crate=$1
fallback=$2
archive=$3
flags=$4

# Cargo's build output must live outside _build, because dune empties
# a rule's directory before it runs the rule. One directory serves
# every checkout on the machine, and cargo keys its content by
# fingerprint, so two checkouts do not overwrite each other.
#
# "dune clean" does not remove this directory. Remove it by hand to
# build the crate from nothing. CARGO_TARGET_DIR moves it.
if [ -n "${CARGO_TARGET_DIR:-}" ]; then
  target=$CARGO_TARGET_DIR
elif [ -n "${XDG_CACHE_HOME:-}" ]; then
  target=$XDG_CACHE_HOME/sinter-bridge-build
elif [ -n "${HOME:-}" ]; then
  target=$HOME/.cache/sinter-bridge-build
else
  target=$fallback
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "The bridge needs the Rust toolchain, and cargo is not on the PATH." >&2
  echo "Install it with rustup: https://rustup.rs" >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "The bridge needs cmake, and cmake is not on the PATH." >&2
  echo "A build script of wasmtime runs it. Install cmake and build again." >&2
  exit 1
fi

log=$target/native-static-libs.log
mkdir -p "$target"

# CARGO_TERM_COLOR=always wraps the note in escape codes, so ask for
# plain output and strip any code that is left.
if ! cargo rustc --release --quiet --color never \
    --manifest-path "$crate/Cargo.toml" \
    --target-dir "$target" -- --print native-static-libs 2>"$log"; then
  cat "$log" >&2
  exit 1
fi

cp "$target/release/libsinter_bridge.a" "$archive"

# The C compiler driver links the C library itself, and naming it a
# second time makes the linker warn.
libraries=$(sed 's/\x1b\[[0-9;]*m//g' "$log" |
  sed -n 's/^note: native-static-libs: *//p' | tail -n 1 |
  tr ' ' '\n' | grep -v -e '^-lSystem$' -e '^-lc$' -e '^$' | tr '\n' ' ')
if [ -z "$libraries" ]; then
  echo "The Rust toolchain reported no native-static-libs line." >&2
  cat "$log" >&2
  exit 1
fi
printf '(%s)\n' "$libraries" >"$flags"
