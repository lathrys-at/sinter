#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Sinter Authors

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

# @cites rust-bridge
# Cargo's build output lives outside _build, in a directory of its own
# for each checkout. "dune clean" does not remove that directory.
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

checkout=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$root")
printf '%s\n' "$checkout" >"$target/checkout"

if ! cargo rustc --release --quiet --color never \
    --manifest-path "$crate/Cargo.toml" \
    --target-dir "$target" -- --print native-static-libs 2>"$log"; then
  cat "$log" >&2
  exit 1
fi

cp "$target/release/libsinter_bridge.a" "$archive"

note=$(sed 's/\x1b\[[0-9;]*m//g' "$log" |
  sed -n 's/^note: native-static-libs: *//p' | tail -n 1)
if [ -z "$note" ]; then
  echo "The Rust toolchain reported no native-static-libs line." >&2
  cat "$log" >&2
  exit 1
fi
echo "note: native-static-libs: $note" >&2

libraries=$(printf '%s' "$note" |
  tr ' ' '\n' | grep -v -e '^-lSystem$' -e '^-lc$' -e '^$' | tr '\n' ' ')
printf '(%s)\n' "$libraries" >"$flags"
