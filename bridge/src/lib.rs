// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

// @cites parser-bridge

//! The C interface that Sinter uses to parse source text.
//!
//! The bridge loads a tree-sitter grammar that is compiled to
//! WebAssembly, parses a source text with that grammar, and runs a
//! tree-sitter query over the parse tree. It returns the captures, or
//! the parse tree as an S-expression, in one flat buffer.

#![warn(unsafe_op_in_unsafe_fn)]

use std::cell::RefCell;
use std::ffi::{c_char, CStr, CString};

use tree_sitter::{
    wasmtime, Language, Node, Parser, Query, QueryCursor, StreamingIterator, WasmStore,
};

/// The first four bytes of every result buffer.
const MAGIC: u32 = u32::from_le_bytes(*b"SBR1");

/// The `kind` field of a buffer of captures.
const KIND_CAPTURES: u32 = 0;

/// The `kind` field of a buffer that holds a parse tree.
const KIND_TREE: u32 = 1;

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::default());
}

fn set_error(message: impl Into<Vec<u8>>) {
    let text = message.into();
    // The message reaches the caller as a C string, so it must hold no
    // NUL byte.
    let clean: Vec<u8> = text
        .into_iter()
        .map(|b| if b == 0 { b'?' } else { b })
        .collect();
    let value = CString::new(clean).unwrap_or_default();
    LAST_ERROR.with(|cell| *cell.borrow_mut() = value);
}

/// An engine holds the WebAssembly runtime. It owns every language
/// that is loaded into it.
pub struct SinterBridgeEngine {
    /// Holds the WebAssembly store between calls. A grammar that runs
    /// in WebAssembly needs the store for every read of a parse tree.
    parser: Parser,
    /// The handles that `sinter_bridge_language_load` returns point
    /// into this list. Each language sits in its own box, so that the
    /// address of a language survives a growth of the list.
    #[allow(clippy::vec_box)]
    languages: Vec<Box<SinterBridgeLanguage>>,
    /// The query that the engine compiled last.
    query: Option<CompiledQuery>,
}

/// A compiled query, with the grammar and the text it came from.
struct CompiledQuery {
    /// The address of the language handle the query was compiled for.
    language: usize,
    text: String,
    query: Query,
}

/// A grammar that is loaded into an engine. The engine owns it.
pub struct SinterBridgeLanguage {
    language: Language,
}

/// The output of one run. The fields match `sinter_bridge_result` in
/// the C header.
#[repr(C)]
pub struct SinterBridgeResult {
    data: *mut u8,
    len: usize,
    capacity: usize,
}

/// Make a slice from a C pointer and a length. A null pointer gives an
/// empty slice.
///
/// # Safety
///
/// When `len` is not 0, `data` must point to `len` readable bytes.
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

/// Write the 16-byte header. `set_count` fills the count in later.
fn put_header(buffer: &mut Vec<u8>, kind: u32) {
    put_u32(buffer, MAGIC);
    put_u32(buffer, kind);
    put_u32(buffer, 0);
    put_u32(buffer, 0);
}

/// Write the record count into the header.
fn set_count(buffer: &mut [u8], count: u32) {
    buffer[8..12].copy_from_slice(&count.to_le_bytes());
}

/// Whether tree-sitter gives this node a name of its own, such as
/// `MISSING "]"` or `UNEXPECTED '@'`, instead of the node's type.
///
/// Every such node is a leaf: the parser inserts a missing token, and
/// it reports an unusable character as an error with no child.
fn has_its_own_name(node: Node) -> bool {
    node.child_count() == 0 && (node.is_missing() || node.is_error())
}

/// Write the parse tree under `root` as an S-expression.
///
/// tree-sitter's own `to_sexp` walks the tree by recursion, so a file
/// that nests deeply overflows the stack of the calling thread. The
/// walk below holds its state in a cursor and in one vector, so the
/// depth of the tree costs heap and not stack.
fn write_sexp(root: Node, out: &mut String) {
    let mut cursor = root.walk();
    // One entry for each node from the root to the node the cursor is
    // on. The entry says whether that node opened a parenthesis.
    let mut open: Vec<bool> = Vec::new();
    let mut descending = true;
    // A space separates one node from the node before it. The first
    // node written takes none.
    let mut written = false;
    loop {
        if descending {
            let node = cursor.node();
            let visible = node.is_named() || node.is_missing();
            // A node with a name of its own is written whole, with its
            // parentheses, so nothing closes it later.
            let opened = visible && !has_its_own_name(node);
            if visible {
                if written {
                    out.push(' ');
                }
                written = true;
                if let Some(field) = cursor.field_name() {
                    out.push_str(field);
                    out.push_str(": ");
                }
                if opened {
                    out.push('(');
                    out.push_str(node.kind());
                } else {
                    // A leaf costs no recursion, so tree-sitter names
                    // it.
                    out.push_str(&node.to_sexp());
                }
            }
            open.push(opened);
            if cursor.goto_first_child() {
                continue;
            }
        }
        if open.pop() == Some(true) {
            out.push(')');
        }
        if cursor.goto_next_sibling() {
            descending = true;
            continue;
        }
        if !cursor.goto_parent() {
            return;
        }
        descending = false;
    }
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

/// Run `body`. Turn a panic into `failure`, so that no panic reaches
/// the C caller.
///
/// Rust aborts the process when a panic tries to leave an
/// `extern "C"` function, and an aborted process gives the caller no
/// message and no exit code of its own.
///
/// The guard works only while the crate unwinds a panic. A release
/// profile that sets `panic = "abort"` makes every guard in the crate
/// dead, and the process aborts again.
fn guard<T>(failure: T, body: impl FnOnce() -> T) -> T {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(body)) {
        Ok(value) => value,
        Err(_) => {
            set_error("the parser bridge stopped on an internal fault");
            failure
        }
    }
}

/// Create an engine. Returns null on failure.
#[no_mangle]
pub extern "C" fn sinter_bridge_engine_new() -> *mut SinterBridgeEngine {
    guard(std::ptr::null_mut(), move || {
        // @cites parser-bridge
        // The engine uses wasmtime's compiled-module cache, in wasmtime's
        // default directory. Without that directory the engine runs with
        // no cache and compiles every grammar on each load.
        let mut config = wasmtime::Config::new();
        if config.cache_config_load_default().is_err() {
            config = wasmtime::Config::new();
        }
        let wasm_engine = match wasmtime::Engine::new(&config) {
            Ok(engine) => engine,
            Err(error) => {
                set_error(format!("cannot create the WebAssembly engine: {error}"));
                return std::ptr::null_mut();
            }
        };
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
            query: None,
        }))
    })
}

/// Free an engine and every language that is loaded into it.
///
/// # Safety
///
/// `engine` must be null, or a pointer that
/// `sinter_bridge_engine_new` returned and that was not freed before.
/// Every language handle from this engine becomes invalid.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_engine_free(engine: *mut SinterBridgeEngine) {
    guard((), move || {
        if engine.is_null() {
            return;
        }
        // Safety: the caller passes a pointer from sinter_bridge_engine_new
        // and does not use it again.
        drop(unsafe { Box::from_raw(engine) });
    })
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
    guard(std::ptr::null_mut(), move || {
        if engine.is_null() || name.is_null() || (wasm.is_null() && wasm_len != 0) {
            set_error("a required argument is null");
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
                set_error("the parser bridge did not recover from an earlier failure");
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
                set_error(error.to_string());
                return std::ptr::null_mut();
            }
        };
        let mut handle = Box::new(SinterBridgeLanguage { language });
        let pointer: *mut SinterBridgeLanguage = &mut *handle;
        engine.languages.push(handle);
        pointer
    })
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
    guard(std::ptr::null_mut(), move || {
        if engine.is_null() || language.is_null() || (source.is_null() && source_len != 0) {
            set_error("a required argument is null");
            return std::ptr::null_mut();
        }
        if query.is_null() && query_len != 0 {
            set_error("the query is null, and its length is not 0");
            return std::ptr::null_mut();
        }
        // Safety: the caller gives an engine and a language from this
        // bridge, source_len readable bytes at source, and query_len
        // readable bytes at query.
        let language_key = language as usize;
        let engine = unsafe { &mut *engine };
        let grammar = unsafe { &*language }.language.clone();
        let source = unsafe { slice_of(source, source_len) };
        let query_bytes = unsafe { slice_of(query, query_len) };

        if let Err(error) = engine.parser.set_language(&grammar) {
            set_error(format!("cannot use the grammar: {error}"));
            return std::ptr::null_mut();
        }
        let tree = match engine.parser.parse(source, None) {
            Some(tree) => tree,
            None => {
                set_error("the grammar produced no parse tree");
                return std::ptr::null_mut();
            }
        };

        if query_len == 0 {
            let mut buffer = Vec::new();
            put_header(&mut buffer, KIND_TREE);
            let mut sexp = String::new();
            write_sexp(tree.root_node(), &mut sexp);
            put_bytes(&mut buffer, sexp.as_bytes());
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
        // The engine keeps the query it compiled last. One run of
        // "sinter parse" puts the same query over many files, so the
        // query is compiled once and not once per file.
        let hit = engine
            .query
            .as_ref()
            .is_some_and(|c| c.language == language_key && c.text == query_text);
        if !hit {
            match Query::new(&grammar, query_text) {
                Ok(compiled) => {
                    engine.query = Some(CompiledQuery {
                        language: language_key,
                        text: query_text.to_owned(),
                        query: compiled,
                    })
                }
                Err(error) => {
                    set_error(format!("cannot read the query: {error}"));
                    return std::ptr::null_mut();
                }
            }
        }
        let query = match &engine.query {
            Some(compiled) => &compiled.query,
            None => {
                set_error("the engine holds no compiled query");
                return std::ptr::null_mut();
            }
        };
        let names = query.capture_names().to_vec();

        let mut buffer = Vec::new();
        put_header(&mut buffer, KIND_CAPTURES);
        let mut count: u32 = 0;
        let mut cursor = QueryCursor::new();
        let mut matches = cursor.matches(query, tree.root_node(), source);
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
                let text = source
                    .get(node.start_byte()..node.end_byte())
                    .unwrap_or(&[]);
                put_bytes(&mut buffer, text);
                count += 1;
            }
        }
        set_count(&mut buffer, count);
        into_result(buffer)
    })
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
    guard((), move || {
        if result.is_null() {
            return;
        }
        // Safety: the caller passes a pointer from sinter_bridge_run and
        // does not use it again.
        let result = unsafe { Box::from_raw(result) };
        drop(unsafe { Vec::from_raw_parts(result.data, result.len, result.capacity) });
    })
}

/// The message of the last failure on the calling thread.
#[no_mangle]
pub extern "C" fn sinter_bridge_last_error() -> *const c_char {
    guard(c"".as_ptr(), move || {
        LAST_ERROR.with(|cell| cell.borrow().as_ptr())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    struct Capture {
        pattern: u32,
        name: String,
        node_type: String,
        text: String,
    }

    /// Read a little-endian u32 at `at`, and move `at` past it.
    fn take_u32(bytes: &[u8], at: &mut usize) -> u32 {
        let value = u32::from_le_bytes(bytes[*at..*at + 4].try_into().unwrap());
        *at += 4;
        value
    }

    /// Read a length-prefixed string at `at`, and move `at` past it.
    fn take_string(bytes: &[u8], at: &mut usize) -> String {
        let len = take_u32(bytes, at) as usize;
        let value = String::from_utf8(bytes[*at..*at + len].to_vec()).unwrap();
        *at += len;
        value
    }

    /// Run the fixture grammar over `source` with `query`. Returns the
    /// kind of the buffer and the whole buffer.
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
        let captures = decode_captures(&bytes);
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

    /// A parser that holds the fixture grammar.
    fn fixture_parser() -> Parser {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
        let wasm = std::fs::read(root.join("test/fixtures/tree-sitter-json/tree-sitter-json.wasm"))
            .unwrap();
        let wasm_engine = wasmtime::Engine::new(&wasmtime::Config::new()).unwrap();
        let mut store = WasmStore::new(&wasm_engine).unwrap();
        let language = store.load_language("json", &wasm).unwrap();
        let mut parser = Parser::new();
        parser.set_wasm_store(store).unwrap();
        parser.set_language(&language).unwrap();
        parser
    }

    /// The bytes of the fixture grammar.
    fn fixture_wasm() -> Vec<u8> {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
        std::fs::read(root.join("test/fixtures/tree-sitter-json/tree-sitter-json.wasm")).unwrap()
    }

    /// Read the capture records of a buffer whose kind is 0.
    fn decode_captures(bytes: &[u8]) -> Vec<Capture> {
        let mut at = 8;
        let count = take_u32(bytes, &mut at);
        at += 4;
        let mut captures = Vec::new();
        for _ in 0..count {
            let pattern = take_u32(bytes, &mut at);
            for _ in 0..6 {
                take_u32(bytes, &mut at);
            }
            let name = take_string(bytes, &mut at);
            let node_type = take_string(bytes, &mut at);
            let text = take_string(bytes, &mut at);
            captures.push(Capture {
                pattern,
                name,
                node_type,
                text,
            });
        }
        assert_eq!(at, bytes.len());
        captures
    }

    /// One run on an engine that stays alive between calls. Gives the
    /// texts of the captures, or None when the run failed.
    fn texts_of(
        engine: *mut SinterBridgeEngine,
        language: *mut SinterBridgeLanguage,
        source: &[u8],
        query: &[u8],
    ) -> Option<Vec<String>> {
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
        if result.is_null() {
            return None;
        }
        let bytes = unsafe { std::slice::from_raw_parts((*result).data, (*result).len) }.to_vec();
        unsafe { sinter_bridge_result_free(result) };
        Some(
            decode_captures(&bytes)
                .into_iter()
                .map(|c| c.text)
                .collect(),
        )
    }

    #[test]
    fn a_panic_becomes_a_failure_and_not_an_abort() {
        set_error("");
        let value = guard(-1_i32, || panic!("a panic inside the bridge"));
        assert_eq!(value, -1);
        let message = unsafe { CStr::from_ptr(sinter_bridge_last_error()) }
            .to_str()
            .unwrap()
            .to_owned();
        assert!(!message.is_empty(), "the guard stored no message");
    }

    #[test]
    fn the_engine_compiles_a_query_once_and_notices_a_new_one() {
        let wasm = fixture_wasm();
        let engine = sinter_bridge_engine_new();
        let name = CString::new("json").unwrap();
        let language = unsafe {
            sinter_bridge_language_load(engine, name.as_ptr(), wasm.as_ptr(), wasm.len())
        };
        let numbers = b"(number) @n";
        let strings = b"(string_content) @s";
        let source = b"{\"a\": 1, \"b\": 2}";

        // An empty source compiles the query and captures nothing.
        // "sinter parse" uses this to report a bad query against the
        // query file and not against the first source file.
        assert_eq!(texts_of(engine, language, b"", numbers), Some(vec![]));

        let first = texts_of(engine, language, source, numbers);
        assert_eq!(first, Some(vec!["1".to_owned(), "2".to_owned()]));
        // The same query again reads the compiled form.
        assert_eq!(texts_of(engine, language, source, numbers), first);
        // Another query replaces it.
        assert_eq!(
            texts_of(engine, language, source, strings),
            Some(vec!["a".to_owned(), "b".to_owned()])
        );
        // And the first query is compiled again.
        assert_eq!(texts_of(engine, language, source, numbers), first);
        // A query that does not compile fails, and leaves the engine
        // able to run the query before it.
        assert_eq!(texts_of(engine, language, source, b"(no_such) @x"), None);
        assert_eq!(texts_of(engine, language, source, numbers), first);

        unsafe { sinter_bridge_engine_free(engine) };
    }

    #[test]
    fn the_writer_agrees_with_tree_sitter_on_every_shape() {
        let mut parser = fixture_parser();
        let sources = [
            "",
            "[]",
            "{}",
            "[1]",
            "[1, 2, 3]",
            "{\"a\": true, \"b\": false, \"c\": null}",
            "{\"a\": [1, {\"b\": \"c\"}]}",
            "{\"k\": \"caf\u{e9} \u{1f600}\"}",
            "// a comment\n[1]",
            "[1,]",
            "{\"a\" 1}",
            "[1",
            "\"unterminated",
            "@",
            "{,}",
            "[[[[[1]]]]]",
        ];
        for source in sources {
            let tree = parser.parse(source, None).unwrap();
            let mut written = String::new();
            write_sexp(tree.root_node(), &mut written);
            assert_eq!(written, tree.root_node().to_sexp(), "source was {source:?}");
        }
    }

    #[test]
    fn a_tree_that_nests_deeply_is_written_and_does_not_crash() {
        let depth = 40_000;
        let source = format!("{}1{}", "[".repeat(depth), "]".repeat(depth));
        let (kind, bytes) = run(source.as_bytes(), b"");
        assert_eq!(kind, KIND_TREE);
        let mut at = 8;
        assert_eq!(take_u32(&bytes, &mut at), 1);
        at += 4;
        let sexp = take_string(&bytes, &mut at);
        assert_eq!(at, bytes.len());
        assert!(
            sexp.starts_with("(document (array (array "),
            "started {:.40}",
            sexp
        );
        assert_eq!(sexp.matches("(array").count(), depth);
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
