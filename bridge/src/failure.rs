// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

//! The failures of the bridge, and the buffer that carries one to the
//! caller.

use std::cell::RefCell;

use crate::buffer::{put_bytes, put_header, put_u32, put_u64, set_count, KIND_FAILURE};

/// Why a call of the bridge failed. Each variant has the code that the
/// buffer of a failure gives it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Failure {
    /// Code 0: a fault of the bridge or of its caller, which the caller
    /// cannot act on.
    Internal(String),
    /// Code 1: tree-sitter does not load the grammar.
    GrammarLoad { kind: u32, message: String },
    /// Code 2: the ABI version of the grammar is one tree-sitter does
    /// not read.
    LanguageVersion(u32),
    /// Code 3: the parser gave no tree.
    ParseUnfinished,
    /// Code 4: the source text is 2^32 bytes or more.
    SourceTooLong,
    /// Code 5: tree-sitter does not compile the query.
    Query {
        kind: u32,
        row: u32,
        column: u32,
        offset: u32,
        message: String,
    },
    /// Code 6: a pattern of the query uses a predicate or a directive
    /// that the bridge does not apply.
    PredicateNotAllowed {
        operator: String,
        pattern: u32,
        offset: u32,
        row: u32,
        column: u32,
    },
    /// Code 7: the query and the tree come from different languages.
    LanguageMismatch,
    /// Code 8: the module is not a valid adapter.
    AdapterInvalid { cause: u32, details: Vec<String> },
    /// Code 9: the adapter used all of its fuel.
    AdapterOutOfFuel,
    /// Code 10: the adapter trapped, or its instance did not start.
    AdapterTrap(String),
    /// Code 11: the adapter asked for more memory than its limit. The
    /// value is the size in bytes that the bridge refused.
    AdapterMemoryLimit(u64),
    /// Code 12: `sinter_alloc` gave 0, or a range outside `memory`.
    AdapterAlloc {
        call: u32,
        address: u32,
        length: u32,
        memory_size: u64,
    },
    /// Code 13: the response lies outside `memory`.
    AdapterResponse {
        address: u32,
        length: u32,
        memory_size: u64,
    },
}

/// The `kind` of a grammar that the WebAssembly parser rejects.
pub(crate) const WASM_PARSE: u32 = 0;
/// The `kind` of a grammar that the WebAssembly compiler rejects.
pub(crate) const WASM_COMPILE: u32 = 1;
/// The `kind` of a grammar whose instance does not start.
pub(crate) const WASM_INSTANTIATE: u32 = 2;
/// The `kind` of any other failure to load a grammar.
pub(crate) const WASM_OTHER: u32 = 3;

/// The `cause` of a module that wasmtime does not compile.
pub(crate) const CAUSE_NOT_A_MODULE: u32 = 0;
/// The `cause` of a module that imports something.
pub(crate) const CAUSE_IMPORTS: u32 = 1;
/// The `cause` of a module that lacks one of the five exports.
pub(crate) const CAUSE_MISSING_EXPORT: u32 = 2;
/// The `cause` of a module whose export has the wrong type.
pub(crate) const CAUSE_EXPORT_TYPE: u32 = 3;

/// The `call` of a failed `sinter_alloc` for the request.
pub(crate) const CALL_REQUEST: u32 = 0;
/// The `call` of a failed `sinter_alloc` for the report.
pub(crate) const CALL_REPORT: u32 = 1;

/// Write a string of a failure. A string of 2^32 bytes or more does not
/// fit the format, so a fixed text takes its place.
fn put_text(buffer: &mut Vec<u8>, text: &str) {
    if put_bytes(buffer, text.as_bytes()).is_err() {
        let _ = put_bytes(buffer, b"the message is 4 GiB or more");
    }
}

impl Failure {
    /// The code of the failure in its buffer.
    pub(crate) fn code(&self) -> u32 {
        match self {
            Failure::Internal(_) => 0,
            Failure::GrammarLoad { .. } => 1,
            Failure::LanguageVersion(_) => 2,
            Failure::ParseUnfinished => 3,
            Failure::SourceTooLong => 4,
            Failure::Query { .. } => 5,
            Failure::PredicateNotAllowed { .. } => 6,
            Failure::LanguageMismatch => 7,
            Failure::AdapterInvalid { .. } => 8,
            Failure::AdapterOutOfFuel => 9,
            Failure::AdapterTrap(_) => 10,
            Failure::AdapterMemoryLimit(_) => 11,
            Failure::AdapterAlloc { .. } => 12,
            Failure::AdapterResponse { .. } => 13,
        }
    }

    /// The failure as a buffer of kind 5.
    pub(crate) fn buffer(&self) -> Vec<u8> {
        let mut buffer = Vec::new();
        put_header(&mut buffer, KIND_FAILURE);
        put_u32(&mut buffer, self.code());
        match self {
            Failure::Internal(message) | Failure::AdapterTrap(message) => {
                put_text(&mut buffer, message)
            }
            Failure::GrammarLoad { kind, message } => {
                put_u32(&mut buffer, *kind);
                put_text(&mut buffer, message);
            }
            Failure::LanguageVersion(version) => put_u32(&mut buffer, *version),
            Failure::ParseUnfinished
            | Failure::SourceTooLong
            | Failure::LanguageMismatch
            | Failure::AdapterOutOfFuel => {}
            Failure::Query {
                kind,
                row,
                column,
                offset,
                message,
            } => {
                for value in [*kind, *row, *column, *offset] {
                    put_u32(&mut buffer, value);
                }
                put_text(&mut buffer, message);
            }
            Failure::PredicateNotAllowed {
                operator,
                pattern,
                offset,
                row,
                column,
            } => {
                put_text(&mut buffer, operator);
                for value in [*pattern, *offset, *row, *column] {
                    put_u32(&mut buffer, value);
                }
            }
            Failure::AdapterInvalid { cause, details } => {
                put_u32(&mut buffer, *cause);
                put_u32(&mut buffer, details.len() as u32);
                for detail in details {
                    put_text(&mut buffer, detail);
                }
            }
            Failure::AdapterMemoryLimit(size) => put_u64(&mut buffer, *size),
            Failure::AdapterAlloc {
                call,
                address,
                length,
                memory_size,
            } => {
                for value in [*call, *address, *length] {
                    put_u32(&mut buffer, value);
                }
                put_u64(&mut buffer, *memory_size);
            }
            Failure::AdapterResponse {
                address,
                length,
                memory_size,
            } => {
                put_u32(&mut buffer, *address);
                put_u32(&mut buffer, *length);
                put_u64(&mut buffer, *memory_size);
            }
        }
        set_count(&mut buffer, 1);
        buffer
    }
}

thread_local! {
    static LAST_FAILURE: RefCell<Failure> = const { RefCell::new(Failure::Internal(String::new())) };
}

/// Record the failure of the current call on this thread.
pub(crate) fn set_failure(failure: Failure) {
    LAST_FAILURE.with(|cell| *cell.borrow_mut() = failure);
}

/// The failure that the last failed call on this thread recorded.
pub(crate) fn last_failure() -> Failure {
    LAST_FAILURE.with(|cell| cell.borrow().clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The u32 at byte `at` of `bytes`.
    fn u32_at(bytes: &[u8], at: usize) -> u32 {
        u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap())
    }

    #[test]
    fn every_failure_has_its_own_code() {
        let all = [
            Failure::Internal(String::new()),
            Failure::GrammarLoad {
                kind: WASM_PARSE,
                message: String::new(),
            },
            Failure::LanguageVersion(0),
            Failure::ParseUnfinished,
            Failure::SourceTooLong,
            Failure::Query {
                kind: 0,
                row: 0,
                column: 0,
                offset: 0,
                message: String::new(),
            },
            Failure::PredicateNotAllowed {
                operator: String::new(),
                pattern: 0,
                offset: 0,
                row: 0,
                column: 0,
            },
            Failure::LanguageMismatch,
            Failure::AdapterInvalid {
                cause: 1,
                details: vec![],
            },
            Failure::AdapterOutOfFuel,
            Failure::AdapterTrap(String::new()),
            Failure::AdapterMemoryLimit(0),
            Failure::AdapterAlloc {
                call: 0,
                address: 0,
                length: 0,
                memory_size: 0,
            },
            Failure::AdapterResponse {
                address: 0,
                length: 0,
                memory_size: 0,
            },
        ];
        for (index, failure) in all.iter().enumerate() {
            assert_eq!(failure.code(), index as u32);
            let buffer = failure.buffer();
            assert_eq!(&buffer[0..4], b"SBR1");
            assert_eq!(u32_at(&buffer, 4), KIND_FAILURE);
            assert_eq!(u32_at(&buffer, 8), 1);
            assert_eq!(u32_at(&buffer, 16), index as u32);
        }
    }

    #[test]
    fn a_query_failure_holds_its_fields_in_order() {
        let buffer = Failure::Query {
            kind: 4,
            row: 2,
            column: 0,
            offset: 7,
            message: "bad".to_owned(),
        }
        .buffer();
        let fields: Vec<u32> = (0..5).map(|i| u32_at(&buffer, 20 + 4 * i)).collect();
        assert_eq!(fields, vec![4, 2, 0, 7, 3]);
        assert_eq!(&buffer[40..], b"bad");
    }

    #[test]
    fn a_predicate_failure_holds_the_operator_then_the_place() {
        let buffer = Failure::PredicateNotAllowed {
            operator: "set!".to_owned(),
            pattern: 1,
            offset: 9,
            row: 1,
            column: 2,
        }
        .buffer();
        assert_eq!(u32_at(&buffer, 20), 4);
        assert_eq!(&buffer[24..28], b"set!");
        let fields: Vec<u32> = (0..4).map(|i| u32_at(&buffer, 28 + 4 * i)).collect();
        assert_eq!(fields, vec![1, 9, 1, 2]);
        assert_eq!(buffer.len(), 44);
    }

    #[test]
    fn an_invalid_adapter_holds_its_cause_and_a_list_of_strings() {
        let buffer = Failure::AdapterInvalid {
            cause: 1,
            details: vec!["env.f".to_owned(), "env.g".to_owned()],
        }
        .buffer();
        assert_eq!(u32_at(&buffer, 20), 1);
        assert_eq!(u32_at(&buffer, 24), 2);
        assert_eq!(u32_at(&buffer, 28), 5);
        assert_eq!(&buffer[32..37], b"env.f");
        assert_eq!(u32_at(&buffer, 37), 5);
        assert_eq!(&buffer[41..], b"env.g");
    }

    #[test]
    fn the_sizes_of_memory_are_written_in_64_bits() {
        let buffer = Failure::AdapterMemoryLimit(1 << 32).buffer();
        assert_eq!(&buffer[20..], &(1u64 << 32).to_le_bytes());
        let buffer = Failure::AdapterAlloc {
            call: 1,
            address: 8,
            length: 16,
            memory_size: 65536,
        }
        .buffer();
        let fields: Vec<u32> = (0..3).map(|i| u32_at(&buffer, 20 + 4 * i)).collect();
        assert_eq!(fields, vec![1, 8, 16]);
        assert_eq!(&buffer[32..], &65536u64.to_le_bytes());
        let buffer = Failure::AdapterResponse {
            address: 4,
            length: 2,
            memory_size: 3,
        }
        .buffer();
        assert_eq!(u32_at(&buffer, 20), 4);
        assert_eq!(u32_at(&buffer, 24), 2);
        assert_eq!(&buffer[28..], &3u64.to_le_bytes());
    }

    #[test]
    fn the_last_failure_is_kept_per_thread() {
        set_failure(Failure::SourceTooLong);
        let other = std::thread::spawn(last_failure).join().unwrap();
        assert_eq!(other, Failure::Internal(String::new()));
        assert_eq!(last_failure(), Failure::SourceTooLong);
    }
}
