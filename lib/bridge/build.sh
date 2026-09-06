#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Sinter Authors

# Build the Rust bridge crate as a static library, and report the
# system libraries that a static link of that crate needs.
#
# With --target-dir as the first argument, the script prints the build
# directory that it chooses for the crate in the second argument, and
# does nothing else.
#
# The arguments of a build, in order:
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

if [ "${1:-}" = "--target-dir" ]; then
  crate=$2
  fallback=
else
  crate=$1
  fallback=$2
  archive=$3
  flags=$4
fi

# @cites parser-bridge
# Cargo's build output must live outside _build, and each checkout
# must build in a directory of its own. "dune clean" does not remove
# that directory; remove it by hand to build the crate from nothing.
if [ -n "${CARGO_TARGET_DIR:-}" ]; then
  base=$CARGO_TARGET_DIR
elif [ -n "${XDG_CACHE_HOME:-}" ]; then
  base=$XDG_CACHE_HOME/sinter-bridge-build
elif [ -n "${HOME:-}" ]; then
  base=$HOME/.cache/sinter-bridge-build
else
  base=$fallback
fi

root=$(cd "$crate" && pwd -P)
if command -v shasum >/dev/null 2>&1; then
  key=$(printf '%s' "$root" | shasum -a 256 | cut -c1-16)
elif command -v sha256sum >/dev/null 2>&1; then
  key=$(printf '%s' "$root" | sha256sum | cut -c1-16)
else
  key=$(printf '%s' "$root" | cksum | tr -d ' ')
fi
target=$base/$key

if [ "${1:-}" = "--target-dir" ]; then
  printf '%s\n' "$target"
  exit 0
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

# The note names the system libraries that a static link of the crate
# needs. Print it, so that every build log holds it.
note=$(sed 's/\x1b\[[0-9;]*m//g' "$log" |
  sed -n 's/^note: native-static-libs: *//p' | tail -n 1)
if [ -z "$note" ]; then
  echo "The Rust toolchain reported no native-static-libs line." >&2
  cat "$log" >&2
  exit 1
fi
echo "note: native-static-libs: $note" >&2

# The C compiler driver links the C library itself, and naming it a
# second time makes the linker warn.
libraries=$(printf '%s' "$note" |
  tr ' ' '\n' | grep -v -e '^-lSystem$' -e '^-lc$' -e '^$' | tr '\n' ' ')
printf '(%s)\n' "$libraries" >"$flags"
