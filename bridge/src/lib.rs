// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

//! The C interface that Sinter uses to parse source text.
//!
//! The bridge loads a tree-sitter grammar that is compiled to
//! WebAssembly, parses a source text with it, and runs a tree-sitter
//! query over the parse tree. It returns the captures of the query, or
//! the parse tree as an S-expression, in one flat buffer. The file
//! `README.md` beside this crate defines the layout of that buffer and
//! the rules that govern the lifetimes.

#![warn(unsafe_op_in_unsafe_fn)]

use std::cell::RefCell;
use std::ffi::{c_char, CStr, CString};

use tree_sitter::{wasmtime, Language, Parser, Query, QueryCursor, StreamingIterator, WasmStore};

/// The magic bytes at the start of every result buffer: `SBR1`.
const MAGIC: u32 = u32::from_le_bytes([b'S', b'B', b'R', b'1']);

/// The value of the `kind` field for a buffer of captures.
const KIND_CAPTURES: u32 = 0;

/// The value of the `kind` field for a buffer that holds a parse tree.
const KIND_TREE: u32 = 1;

thread_local! {
    /// The message of the last failure on this thread.
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::default());
}

/// Store a failure message for this thread.
fn set_error(message: impl Into<Vec<u8>>) {
    let text = message.into();
    // A NUL byte inside the message would truncate the C string.
    // Replace it, so that the caller always reads the whole message.
    let clean: Vec<u8> = text
        .into_iter()
        .map(|b| if b == 0 { b'?' } else { b })
        .collect();
    let value = CString::new(clean).unwrap_or_default();
    LAST_ERROR.with(|cell| *cell.borrow_mut() = value);
}

/// An engine holds the WebAssembly runtime and every language that was
/// loaded into it.
pub struct SinterBridgeEngine {
    /// The parser owns the wasm store between calls. A grammar that
    /// runs in WebAssembly needs the store for every call that reads
    /// the parse tree, so the store stays in the parser.
    parser: Parser,
    /// The engine owns the languages. A handle that
    /// `sinter_bridge_language_load` returns points into this list.
    /// Each language sits in its own box, so that the address of a
    /// language does not change when the list grows.
    #[allow(clippy::vec_box)]
    languages: Vec<Box<SinterBridgeLanguage>>,
}

/// A language handle. The engine owns it.
pub struct SinterBridgeLanguage {
    language: Language,
}

/// The result of one run. The bridge owns the bytes.
#[repr(C)]
pub struct SinterBridgeResult {
    data: *mut u8,
    len: usize,
    capacity: usize,
}

/// Make a slice from a C pointer and a length.
///
/// # Safety
///
/// When `len` is not 0, `data` must point to `len` readable bytes.
///
/// A null pointer with the length 0 is a slice of no bytes. Rust does
/// not allow a null pointer in `slice::from_raw_parts`, not even for
/// an empty slice, so that case is handled before the call.
unsafe fn slice_of(data: *const u8, len: usize) -> &'static [u8] {
    if data.is_null() {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(data, len) }
    }
}

fn put_u32(buffer: &mut Vec<u8>, value: u32) {
    buffer.extend_from_slice(&value.to_le_bytes());
}

fn put_bytes(buffer: &mut Vec<u8>, value: &[u8]) {
    put_u32(buffer, value.len() as u32);
    buffer.extend_from_slice(value);
}

/// Write the 16-byte header. The count is patched in later.
fn put_header(buffer: &mut Vec<u8>, kind: u32) {
    put_u32(buffer, MAGIC);
    put_u32(buffer, kind);
    put_u32(buffer, 0);
    put_u32(buffer, 0);
}

/// Write the final record count into the header.
fn set_count(buffer: &mut [u8], count: u32) {
    buffer[8..12].copy_from_slice(&count.to_le_bytes());
}

/// Move a buffer into a result that the caller frees.
fn into_result(buffer: Vec<u8>) -> *mut SinterBridgeResult {
    let mut buffer = buffer;
    let result = SinterBridgeResult {
        data: buffer.as_mut_ptr(),
        len: buffer.len(),
        capacity: buffer.capacity(),
    };
    std::mem::forget(buffer);
    Box::into_raw(Box::new(result))
}

/// Create an engine. Returns null on failure.
#[no_mangle]
pub extern "C" fn sinter_bridge_engine_new() -> *mut SinterBridgeEngine {
    let wasm_engine = wasmtime::Engine::default();
    let store = match WasmStore::new(&wasm_engine) {
        Ok(store) => store,
        Err(error) => {
            set_error(format!("cannot create the WebAssembly store: {error}"));
            return std::ptr::null_mut();
        }
    };
    let mut parser = Parser::new();
    if let Err(error) = parser.set_wasm_store(store) {
        set_error(format!("cannot attach the WebAssembly store: {error}"));
        return std::ptr::null_mut();
    }
    Box::into_raw(Box::new(SinterBridgeEngine {
        parser,
        languages: Vec::new(),
    }))
}

/// Free an engine and every language that was loaded into it.
///
/// # Safety
///
/// `engine` must be null, or a pointer that
/// `sinter_bridge_engine_new` returned and that was not freed before.
/// Every language handle from this engine becomes invalid.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_engine_free(engine: *mut SinterBridgeEngine) {
    if engine.is_null() {
        return;
    }
    // Safety: the caller passes a pointer from sinter_bridge_engine_new
    // and does not use it again.
    drop(unsafe { Box::from_raw(engine) });
}

/// Load a grammar from WebAssembly bytes. Returns null on failure.
///
/// # Safety
///
/// `engine` must be a live pointer from `sinter_bridge_engine_new`.
/// `name` must point to a NUL-terminated string. `wasm` must point to
/// `wasm_len` readable bytes, or be null when `wasm_len` is 0.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_language_load(
    engine: *mut SinterBridgeEngine,
    name: *const c_char,
    wasm: *const u8,
    wasm_len: usize,
) -> *mut SinterBridgeLanguage {
    if engine.is_null() || name.is_null() || (wasm.is_null() && wasm_len != 0) {
        set_error("sinter_bridge_language_load received a null argument");
        return std::ptr::null_mut();
    }
    // Safety: the caller gives an engine from sinter_bridge_engine_new,
    // a NUL-terminated name, and wasm_len readable bytes at wasm.
    let engine = unsafe { &mut *engine };
    let name = match unsafe { CStr::from_ptr(name) }.to_str() {
        Ok(name) => name.to_owned(),
        Err(_) => {
            set_error("the grammar name is not valid UTF-8");
            return std::ptr::null_mut();
        }
    };
    let bytes = unsafe { slice_of(wasm, wasm_len) };

    let mut store = match engine.parser.take_wasm_store() {
        Some(store) => store,
        None => {
            set_error("the engine has no WebAssembly store");
            return std::ptr::null_mut();
        }
    };
    let loaded = store.load_language(&name, bytes);
    if let Err(error) = engine.parser.set_wasm_store(store) {
        set_error(format!("cannot attach the WebAssembly store: {error}"));
        return std::ptr::null_mut();
    }
    let language = match loaded {
        Ok(language) => language,
        Err(error) => {
            set_error(format!("cannot load the grammar {name}: {error}"));
            return std::ptr::null_mut();
        }
    };
    let mut handle = Box::new(SinterBridgeLanguage { language });
    let pointer: *mut SinterBridgeLanguage = &mut *handle;
    engine.languages.push(handle);
    pointer
}

/// Parse a source text and run a query over the parse tree. When
/// `query_len` is 0 the bridge returns the parse tree as an
/// S-expression instead. Returns null on failure.
///
/// # Safety
///
/// `engine` must be a live pointer from `sinter_bridge_engine_new`,
/// and `language` a live handle that the same engine returned.
/// `source` must point to `source_len` readable bytes and `query` to
/// `query_len` readable bytes; either may be null when its length is
/// 0.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_run(
    engine: *mut SinterBridgeEngine,
    language: *mut SinterBridgeLanguage,
    source: *const u8,
    source_len: usize,
    query: *const u8,
    query_len: usize,
) -> *mut SinterBridgeResult {
    if engine.is_null() || language.is_null() || (source.is_null() && source_len != 0) {
        set_error("sinter_bridge_run received a null argument");
        return std::ptr::null_mut();
    }
    if query.is_null() && query_len != 0 {
        set_error("sinter_bridge_run received a null query");
        return std::ptr::null_mut();
    }
    // Safety: the caller gives an engine and a language from this
    // bridge, source_len readable bytes at source, and query_len
    // readable bytes at query.
    let engine = unsafe { &mut *engine };
    let language = unsafe { &*language };
    let source = unsafe { slice_of(source, source_len) };
    let query_bytes = unsafe { slice_of(query, query_len) };

    if let Err(error) = engine.parser.set_language(&language.language) {
        set_error(format!("cannot use the grammar: {error}"));
        return std::ptr::null_mut();
    }
    let tree = match engine.parser.parse(source, None) {
        Some(tree) => tree,
        None => {
            set_error("the parser returned no tree");
            return std::ptr::null_mut();
        }
    };

    if query_len == 0 {
        let mut buffer = Vec::new();
        put_header(&mut buffer, KIND_TREE);
        put_bytes(&mut buffer, tree.root_node().to_sexp().as_bytes());
        set_count(&mut buffer, 1);
        return into_result(buffer);
    }

    let query_text = match std::str::from_utf8(query_bytes) {
        Ok(text) => text,
        Err(_) => {
            set_error("the query is not valid UTF-8");
            return std::ptr::null_mut();
        }
    };
    let query = match Query::new(&language.language, query_text) {
        Ok(query) => query,
        Err(error) => {
            set_error(format!("cannot read the query: {error}"));
            return std::ptr::null_mut();
        }
    };
    let names = query.capture_names().to_vec();

    let mut buffer = Vec::new();
    put_header(&mut buffer, KIND_CAPTURES);
    let mut count: u32 = 0;
    let mut cursor = QueryCursor::new();
    let mut matches = cursor.matches(&query, tree.root_node(), source);
    while let Some(found) = matches.next() {
        for capture in found.captures {
            let node = capture.node;
            let start = node.start_position();
            let end = node.end_position();
            put_u32(&mut buffer, found.pattern_index as u32);
            put_u32(&mut buffer, node.start_byte() as u32);
            put_u32(&mut buffer, node.end_byte() as u32);
            put_u32(&mut buffer, start.row as u32);
            put_u32(&mut buffer, start.column as u32);
            put_u32(&mut buffer, end.row as u32);
            put_u32(&mut buffer, end.column as u32);
            let name = names.get(capture.index as usize).copied().unwrap_or("");
            put_bytes(&mut buffer, name.as_bytes());
            put_bytes(&mut buffer, node.kind().as_bytes());
            // A node always lies inside the source text. Read the
            // text without an index, so that a grammar that breaks
            // that rule gives an empty text and not a panic. A panic
            // here would abort the whole process, because the caller
            // is C.
            let text = source
                .get(node.start_byte()..node.end_byte())
                .unwrap_or(&[]);
            put_bytes(&mut buffer, text);
            count += 1;
        }
    }
    set_count(&mut buffer, count);
    into_result(buffer)
}

/// Free a result.
///
/// # Safety
///
/// `result` must be null, or a pointer that `sinter_bridge_run`
/// returned and that was not freed before. The buffer that `data`
/// points to becomes invalid.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_result_free(result: *mut SinterBridgeResult) {
    if result.is_null() {
        return;
    }
    // Safety: the caller passes a pointer from sinter_bridge_run and
    // does not use it again.
    let result = unsafe { Box::from_raw(result) };
    drop(unsafe { Vec::from_raw_parts(result.data, result.len, result.capacity) });
}

/// The message of the last failure on the calling thread.
#[no_mangle]
pub extern "C" fn sinter_bridge_last_error() -> *const c_char {
    LAST_ERROR.with(|cell| cell.borrow().as_ptr())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    /// One decoded capture record.
    struct Capture {
        pattern: u32,
        name: String,
        node_type: String,
        text: String,
    }

    /// Read a little-endian u32 at `at` and move `at` past it.
    fn take_u32(bytes: &[u8], at: &mut usize) -> u32 {
        let value = u32::from_le_bytes(bytes[*at..*at + 4].try_into().unwrap());
        *at += 4;
        value
    }

    /// Read a length-prefixed string at `at` and move `at` past it.
    fn take_string(bytes: &[u8], at: &mut usize) -> String {
        let len = take_u32(bytes, at) as usize;
        let value = String::from_utf8(bytes[*at..*at + len].to_vec()).unwrap();
        *at += len;
        value
    }

    /// Run the bridge over the fixture and return the raw buffer.
    fn run(source: &[u8], query: &[u8]) -> (u32, Vec<u8>) {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
        let wasm = std::fs::read(root.join("test/fixtures/tree-sitter-json/tree-sitter-json.wasm"))
            .unwrap();
        let engine = sinter_bridge_engine_new();
        assert!(!engine.is_null());
        let name = CString::new("json").unwrap();
        let language = unsafe {
            sinter_bridge_language_load(engine, name.as_ptr(), wasm.as_ptr(), wasm.len())
        };
        assert!(!language.is_null());
        let result = unsafe {
            sinter_bridge_run(
                engine,
                language,
                source.as_ptr(),
                source.len(),
                query.as_ptr(),
                query.len(),
            )
        };
        assert!(!result.is_null());
        let bytes = unsafe { std::slice::from_raw_parts((*result).data, (*result).len) }.to_vec();
        unsafe { sinter_bridge_result_free(result) };
        unsafe { sinter_bridge_engine_free(engine) };
        let mut at = 0;
        assert_eq!(take_u32(&bytes, &mut at), MAGIC);
        let kind = take_u32(&bytes, &mut at);
        (kind, bytes)
    }

    #[test]
    fn the_query_returns_the_captures_of_the_fixture() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
        let source = std::fs::read(root.join("test/fixtures/sample.json")).unwrap();
        let query = std::fs::read(root.join("test/fixtures/sample.scm")).unwrap();
        let (kind, bytes) = run(&source, &query);
        assert_eq!(kind, KIND_CAPTURES);
        let mut at = 8;
        let count = take_u32(&bytes, &mut at);
        at += 4;
        let mut captures = Vec::new();
        for _ in 0..count {
            let pattern = take_u32(&bytes, &mut at);
            for _ in 0..6 {
                take_u32(&bytes, &mut at);
            }
            let name = take_string(&bytes, &mut at);
            let node_type = take_string(&bytes, &mut at);
            let text = take_string(&bytes, &mut at);
            captures.push(Capture {
                pattern,
                name,
                node_type,
                text,
            });
        }
        assert_eq!(at, bytes.len());
        let found: Vec<(u32, &str, &str, &str)> = captures
            .iter()
            .map(|c| {
                (
                    c.pattern,
                    c.name.as_str(),
                    c.node_type.as_str(),
                    c.text.as_str(),
                )
            })
            .collect();
        assert_eq!(
            found,
            vec![
                (0, "key", "string_content", "name"),
                (0, "value", "string_content", "sinter"),
                (0, "key", "string_content", "version"),
                (0, "value", "string_content", "0.1.0"),
                (1, "number", "number", "8080"),
                (1, "number", "number", "9090"),
            ]
        );
    }

    #[test]
    fn an_empty_query_returns_the_parse_tree() {
        let (kind, bytes) = run(b"[1]", b"");
        assert_eq!(kind, KIND_TREE);
        let mut at = 8;
        assert_eq!(take_u32(&bytes, &mut at), 1);
        at += 4;
        let tree = take_string(&bytes, &mut at);
        assert_eq!(tree, "(document (array (number)))");
        assert_eq!(at, bytes.len());
    }

    #[test]
    fn a_bad_query_reports_an_error() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
        let wasm = std::fs::read(root.join("test/fixtures/tree-sitter-json/tree-sitter-json.wasm"))
            .unwrap();
        let engine = sinter_bridge_engine_new();
        let name = CString::new("json").unwrap();
        let language = unsafe {
            sinter_bridge_language_load(engine, name.as_ptr(), wasm.as_ptr(), wasm.len())
        };
        let source = b"[]";
        let query = b"(no_such_node) @x";
        let result = unsafe {
            sinter_bridge_run(
                engine,
                language,
                source.as_ptr(),
                source.len(),
                query.as_ptr(),
                query.len(),
            )
        };
        assert!(result.is_null());
        let message = unsafe { CStr::from_ptr(sinter_bridge_last_error()) }
            .to_str()
            .unwrap()
            .to_owned();
        assert!(message.contains("query"), "message was {message}");
        unsafe { sinter_bridge_engine_free(engine) };
    }
}
