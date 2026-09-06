#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Sinter Authors

# Build the Rust bridge crate as a static library, and report the
# system libraries that a static link of that crate needs.
#
# The arguments, in order:
#   1. the directory that holds the crate's Cargo.toml
#   2. the directory to use for cargo's build output, when neither
#      CARGO_TARGET_DIR nor DUNE_SOURCEROOT says where to put it
#   3. the path to write the static library to
#   4. the path to write the dune flags file to
#
# The flags file holds one s-expression: the list of linker flags,
# as "cargo rustc --print native-static-libs" reports them. The list
# differs between macOS and Linux, so we ask the toolchain instead of
# writing the list down.

set -eu

crate=$1
fallback=$2
archive=$3
flags=$4

# Cargo's build output must live outside _build. Dune empties a rule's
# directory before it runs the rule, so a target directory inside
# _build would start empty every time. Cargo would then build all 128
# crates again on every change inside bridge/, which takes about half
# a minute.
#
# The output goes to bridge/target, which is where cargo puts it when
# a contributor runs "cargo build --release" in bridge/ by hand. One
# directory therefore serves both ways of building. Dune exports the
# source root as DUNE_SOURCEROOT. bridge/dune hides that directory
# from dune and .gitignore hides it from git.
#
# "dune clean" does not remove bridge/target. Remove it by hand to
# build the crate from nothing.
if [ -n "${CARGO_TARGET_DIR:-}" ]; then
  target=$CARGO_TARGET_DIR
elif [ -n "${DUNE_SOURCEROOT:-}" ]; then
  target=$DUNE_SOURCEROOT/bridge/target
else
  target=$fallback
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "The bridge needs the Rust toolchain, and cargo is not on the PATH." >&2
  echo "Install it with rustup: https://rustup.rs" >&2
  exit 1
fi

# A build script of wasmtime runs cmake. Without cmake the cargo build
# fails inside that build script, and the message there does not say
# what is missing.
if ! command -v cmake >/dev/null 2>&1; then
  echo "The bridge needs cmake, and cmake is not on the PATH." >&2
  echo "A build script of wasmtime runs it. Install cmake and build again." >&2
  exit 1
fi

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
