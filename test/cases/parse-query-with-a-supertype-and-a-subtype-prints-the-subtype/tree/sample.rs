// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

fn first(items: Vec<u8>) -> Option<u8> {
    let head = items.first();
    head.copied()
}
