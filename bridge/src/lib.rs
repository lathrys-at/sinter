// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

// @cites rust-bridge

//! The C interface that Sinter uses to parse source text.
//!
//! The bridge loads a tree-sitter grammar that is compiled to
//! WebAssembly, parses a source text with that grammar, and runs a
//! tree-sitter query over the parse tree. It returns the captures, the
//! parse tree as an S-expression, or the error nodes of the tree, in
//! one flat buffer. It calls a function of a runner adapter, a
//! WebAssembly module, with bytes in and bytes out, under limits of
//! fuel and memory. It also computes the SHA-256 digest of a byte
//! string, and reads a TOML document.

#![warn(unsafe_op_in_unsafe_fn)]

#[cfg(panic = "abort")]
compile_error!("the bridge needs unwinding panics; do not build it with panic = \"abort\"");

use std::ffi::{c_char, CStr};

mod adapter;
mod buffer;
mod failure;
mod syntax;
mod toml_document;

use buffer::{length_prefix, put_bytes, put_header, set_count, KIND_DIGEST, KIND_RESPONSE};
use failure::{last_failure, set_failure, Failure};
use sha2::{Digest, Sha256};
use toml_edit::ImDocument;
use tree_sitter::{wasmtime, Language, Parser, Query, Tree, WasmStore};

fn set_error(message: impl Into<String>) {
    set_failure(Failure::Internal(message.into()));
}

fn null_argument() -> Failure {
    Failure::Internal("a required argument is null".to_owned())
}

/// An engine holds the WebAssembly runtime for grammars and a parser.
pub struct SinterBridgeEngine {
    parser: Parser,
    grammar_engine: wasmtime::Engine,
    config: wasmtime::Config,
    adapter_engine: Option<wasmtime::Engine>,
}

/// A grammar. It holds a counted reference to the tree-sitter
/// language, so it stays valid after its engine is freed.
pub struct SinterBridgeLanguage {
    language: Language,
    engine: wasmtime::Engine,
}

/// A parse tree, with a copy of the text it was parsed from. The tree
/// holds a counted reference to its language.
pub struct SinterBridgeTree {
    tree: Tree,
    source: Vec<u8>,
}

/// A compiled query, with a counted reference to its language.
pub struct SinterBridgeQuery {
    query: Query,
    language: Language,
}

/// The limits of one instance of an adapter. The fields match
/// `sinter_bridge_limits` in the C header.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct SinterBridgeLimits {
    fuel: u64,
    memory: u64,
}

/// A runner adapter: a compiled module that passed the checks of its
/// interface. The module holds a counted reference to its runtime, so
/// the adapter stays valid after its engine is freed.
pub struct SinterBridgeAdapter {
    adapter: adapter::Adapter,
}

impl SinterBridgeEngine {
    fn adapter_engine(&mut self) -> Result<wasmtime::Engine, Failure> {
        if let Some(engine) = &self.adapter_engine {
            return Ok(engine.clone());
        }
        let mut config = self.config.clone();
        config.consume_fuel(true);
        let engine = wasmtime::Engine::new(&config).map_err(|error| {
            Failure::Internal(format!(
                "cannot create the WebAssembly engine for adapters: {error}"
            ))
        })?;
        self.adapter_engine = Some(engine.clone());
        Ok(engine)
    }
}

/// The result of one run. The fields match `sinter_bridge_result` in
/// the C header.
#[repr(C)]
pub struct SinterBridgeResult {
    data: *mut u8,
    len: usize,
    capacity: usize,
}

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

fn result_of(written: Result<Vec<u8>, Failure>) -> *mut SinterBridgeResult {
    match written {
        Ok(buffer) => into_result(buffer),
        Err(failure) => {
            set_failure(failure);
            std::ptr::null_mut()
        }
    }
}

fn handle_of<T>(made: Result<T, Failure>) -> *mut T {
    match made {
        Ok(value) => Box::into_raw(Box::new(value)),
        Err(failure) => {
            set_failure(failure);
            std::ptr::null_mut()
        }
    }
}

/// # Safety
///
/// `handle` must be null, or a pointer that `handle_of` returned and
/// that was not dropped before.
unsafe fn drop_handle<T>(handle: *mut T) {
    if !handle.is_null() {
        drop(unsafe { Box::from_raw(handle) });
    }
}

fn keep_backtraces_off() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        std::env::set_var("RUST_LIB_BACKTRACE", "0");
        std::panic::set_hook(Box::new(|info| {
            eprintln!("sinter: the bridge stopped on an internal fault: {info}");
        }));
    });
}

fn guard<T>(failure: T, body: impl FnOnce() -> T) -> T {
    keep_backtraces_off();
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
        // @cites rust-bridge
        // The engine uses wasmtime's compiled-module cache. Wasmtime's
        // default cache configuration file sets it up. When that file is
        // missing, the cache is in wasmtime's default directory. When
        // wasmtime cannot read the file or make the directory, the engine
        // runs with no cache and compiles every grammar on each load.
        let mut config = wasmtime::Config::new();
        if let Ok(cache) = wasmtime::Cache::from_file(None) {
            config.cache(Some(cache));
        }
        config.wasm_memory64(false);
        let grammar_engine = match wasmtime::Engine::new(&config) {
            Ok(engine) => engine,
            Err(error) => {
                set_error(format!("cannot create the WebAssembly engine: {error}"));
                return std::ptr::null_mut();
            }
        };
        let store = match WasmStore::new(&grammar_engine) {
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
            grammar_engine,
            config,
            adapter_engine: None,
        }))
    })
}

/// Free an engine.
///
/// # Safety
///
/// `engine` must be null, or a pointer that
/// `sinter_bridge_engine_new` returned and that was not freed before.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_engine_free(engine: *mut SinterBridgeEngine) {
    guard((), move || unsafe { drop_handle(engine) })
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
                set_failure(syntax::grammar_load_failure(error));
                return std::ptr::null_mut();
            }
        };
        handle_of(
            syntax::check_version(language.abi_version()).map(|()| SinterBridgeLanguage {
                language,
                engine: engine.grammar_engine.clone(),
            }),
        )
    })
}

/// Free a language. Trees and queries of the language stay valid.
///
/// # Safety
///
/// `language` must be null, or a pointer that
/// `sinter_bridge_language_load` returned and that was not freed
/// before.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_language_free(language: *mut SinterBridgeLanguage) {
    guard((), move || unsafe { drop_handle(language) })
}

/// Parse a source text. Returns null on failure.
///
/// # Safety
///
/// `engine` must be a live pointer from `sinter_bridge_engine_new`,
/// and `language` a live pointer from `sinter_bridge_language_load`.
/// `source` must point to `source_len` readable bytes, or be null when
/// `source_len` is 0.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_parse(
    engine: *mut SinterBridgeEngine,
    language: *const SinterBridgeLanguage,
    source: *const u8,
    source_len: usize,
) -> *mut SinterBridgeTree {
    guard(std::ptr::null_mut(), move || {
        if engine.is_null() || language.is_null() || (source.is_null() && source_len != 0) {
            return handle_of(Err(null_argument()));
        }
        if length_prefix(source_len).is_err() {
            return handle_of(Err(Failure::SourceTooLong));
        }
        let engine = unsafe { &mut *engine };
        let language = unsafe { &*language };
        let source = unsafe { slice_of(source, source_len) };
        if !wasmtime::Engine::same(&engine.grammar_engine, &language.engine) {
            return handle_of(Err(Failure::Internal(
                "the grammar was loaded by another engine".to_owned(),
            )));
        }
        if engine.parser.set_language(&language.language).is_err() {
            return handle_of(Err(Failure::LanguageVersion(
                language.language.abi_version() as u32,
            )));
        }
        handle_of(
            engine
                .parser
                .parse(source, None)
                .map(|tree| SinterBridgeTree {
                    tree,
                    source: source.to_vec(),
                })
                .ok_or(Failure::ParseUnfinished),
        )
    })
}

/// Free a tree.
///
/// # Safety
///
/// `tree` must be null, or a pointer that `sinter_bridge_parse`
/// returned and that was not freed before.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_tree_free(tree: *mut SinterBridgeTree) {
    guard((), move || unsafe { drop_handle(tree) })
}

const BYTES_PER_NODE: usize = 64;

/// An estimate of the memory that a tree holds: its text, and an
/// amount for each node. Gives 0 for a null pointer.
///
/// # Safety
///
/// `tree` must be null or a live pointer from `sinter_bridge_parse`.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_tree_memory(tree: *const SinterBridgeTree) -> usize {
    guard(0, move || {
        if tree.is_null() {
            return 0;
        }
        let tree = unsafe { &*tree };
        let nodes = tree.tree.root_node().descendant_count();
        tree.source
            .len()
            .saturating_add(nodes.saturating_mul(BYTES_PER_NODE))
    })
}

/// The tree as an S-expression, in a buffer of kind 1. Returns null on
/// failure.
///
/// # Safety
///
/// `tree` must be a live pointer from `sinter_bridge_parse`.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_tree_sexp(
    tree: *const SinterBridgeTree,
) -> *mut SinterBridgeResult {
    guard(std::ptr::null_mut(), move || {
        if tree.is_null() {
            return result_of(Err(null_argument()));
        }
        result_of(syntax::sexp_buffer(&unsafe { &*tree }.tree))
    })
}

/// The error report of a tree, in a buffer of kind 7. Returns null on
/// failure.
///
/// # Safety
///
/// `tree` must be a live pointer from `sinter_bridge_parse`.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_tree_errors(
    tree: *const SinterBridgeTree,
) -> *mut SinterBridgeResult {
    guard(std::ptr::null_mut(), move || {
        if tree.is_null() {
            return result_of(Err(null_argument()));
        }
        result_of(syntax::error_report_buffer(&unsafe { &*tree }.tree))
    })
}

/// Compile a query for a language. Returns null on failure.
///
/// # Safety
///
/// `language` must be a live pointer from `sinter_bridge_language_load`.
/// `text` must point to `len` readable bytes, or be null when `len` is
/// 0.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_query_new(
    language: *const SinterBridgeLanguage,
    text: *const u8,
    len: usize,
) -> *mut SinterBridgeQuery {
    guard(std::ptr::null_mut(), move || {
        if language.is_null() || (text.is_null() && len != 0) {
            return handle_of(Err(null_argument()));
        }
        let language = unsafe { &*language };
        let text = unsafe { slice_of(text, len) };
        handle_of(
            syntax::compile_query(&language.language, text).map(|query| SinterBridgeQuery {
                query,
                language: language.language.clone(),
            }),
        )
    })
}

/// Free a query.
///
/// # Safety
///
/// `query` must be null, or a pointer that `sinter_bridge_query_new`
/// returned and that was not freed before.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_query_free(query: *mut SinterBridgeQuery) {
    guard((), move || unsafe { drop_handle(query) })
}

/// Run a query over a tree, and give the captures in a buffer of kind
/// 6. Returns null on failure.
///
/// # Safety
///
/// `query` must be a live pointer from `sinter_bridge_query_new`, and
/// `tree` a live pointer from `sinter_bridge_parse`.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_query_run(
    query: *const SinterBridgeQuery,
    tree: *const SinterBridgeTree,
) -> *mut SinterBridgeResult {
    guard(std::ptr::null_mut(), move || {
        if query.is_null() || tree.is_null() {
            return result_of(Err(null_argument()));
        }
        let query = unsafe { &*query };
        let tree = unsafe { &*tree };
        if *tree.tree.language() != query.language {
            return result_of(Err(Failure::LanguageMismatch));
        }
        result_of(syntax::matches_buffer(
            &query.query,
            &tree.tree,
            &tree.source,
        ))
    })
}

/// Load a runner adapter from WebAssembly bytes, check its interface,
/// and read its `sinter_interface` in a new instance under the limits.
/// Returns null on failure.
///
/// # Safety
///
/// `engine` must be a live pointer from `sinter_bridge_engine_new`.
/// `wasm` must point to `wasm_len` readable bytes, or be null when
/// `wasm_len` is 0.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_adapter_load(
    engine: *mut SinterBridgeEngine,
    wasm: *const u8,
    wasm_len: usize,
    limits: SinterBridgeLimits,
) -> *mut SinterBridgeAdapter {
    guard(std::ptr::null_mut(), move || {
        if engine.is_null() || (wasm.is_null() && wasm_len != 0) {
            return handle_of(Err(null_argument()));
        }
        let engine = unsafe { &mut *engine };
        let bytes = unsafe { slice_of(wasm, wasm_len) };
        handle_of(
            engine
                .adapter_engine()
                .and_then(|runtime| adapter::load(&runtime, bytes, limits.fuel, limits.memory))
                .map(|adapter| SinterBridgeAdapter { adapter }),
        )
    })
}

/// The version of the interface that the `sinter_interface` of an
/// adapter gave when it loaded, read as unsigned. Gives 0 for a null
/// pointer.
///
/// # Safety
///
/// `adapter` must be null or a live pointer from
/// `sinter_bridge_adapter_load`.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_adapter_interface(
    adapter: *const SinterBridgeAdapter,
) -> u32 {
    guard(0, move || {
        if adapter.is_null() {
            return 0;
        }
        unsafe { &*adapter }.adapter.interface
    })
}

/// Free an adapter.
///
/// # Safety
///
/// `adapter` must be null, or a pointer that
/// `sinter_bridge_adapter_load` returned and that was not freed before.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_adapter_free(adapter: *mut SinterBridgeAdapter) {
    guard((), move || unsafe { drop_handle(adapter) })
}

/// Call a function of an adapter, in a new instance under the limits,
/// and give the response in a buffer of kind 8. `function` is 0 for
/// `sinter_recognise` and 1 for `sinter_bind`. Returns null on failure.
///
/// # Safety
///
/// `adapter` must be a live pointer from `sinter_bridge_adapter_load`.
/// `request` must point to `request_len` readable bytes and `report` to
/// `report_len` readable bytes; either may be null when its length is
/// 0.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_adapter_call(
    adapter: *const SinterBridgeAdapter,
    function: u32,
    request: *const u8,
    request_len: usize,
    report: *const u8,
    report_len: usize,
    limits: SinterBridgeLimits,
) -> *mut SinterBridgeResult {
    guard(std::ptr::null_mut(), move || {
        if adapter.is_null()
            || (request.is_null() && request_len != 0)
            || (report.is_null() && report_len != 0)
        {
            return result_of(Err(null_argument()));
        }
        let Some(function) = adapter::Function::of_number(function) else {
            return result_of(Err(Failure::Internal(format!(
                "the adapter has no function {function}"
            ))));
        };
        let adapter = unsafe { &*adapter };
        let request = unsafe { slice_of(request, request_len) };
        let report = unsafe { slice_of(report, report_len) };
        result_of(
            adapter::call(
                &adapter.adapter,
                function,
                request,
                report,
                limits.fuel,
                limits.memory,
            )
            .and_then(|response| {
                let mut buffer = Vec::new();
                put_header(&mut buffer, KIND_RESPONSE);
                put_bytes(&mut buffer, &response)
                    .map_err(|_| Failure::Internal("the response is 4 GiB or more".to_owned()))?;
                set_count(&mut buffer, 1);
                Ok(buffer)
            }),
        )
    })
}

/// Hash a byte string with SHA-256. Returns null on failure.
///
/// # Safety
///
/// `data` must point to `len` readable bytes, or be null when `len` is
/// 0.
// @cites sha256
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_sha256(
    data: *const u8,
    len: usize,
) -> *mut SinterBridgeResult {
    guard(std::ptr::null_mut(), move || {
        if data.is_null() && len != 0 {
            set_error("a required argument is null");
            return std::ptr::null_mut();
        }
        let bytes = unsafe { slice_of(data, len) };
        let mut buffer = Vec::with_capacity(16 + 32);
        put_header(&mut buffer, KIND_DIGEST);
        buffer.extend_from_slice(&Sha256::digest(bytes));
        set_count(&mut buffer, 1);
        into_result(buffer)
    })
}

/// Read a TOML document. Returns null on failure.
///
/// A text that is not a TOML document is no failure: the result then
/// holds the error.
///
/// # Safety
///
/// `text` must point to `len` readable bytes, or be null when `len` is
/// 0.
// @cites toml-reader
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_toml_parse(
    text: *const u8,
    len: usize,
) -> *mut SinterBridgeResult {
    guard(std::ptr::null_mut(), move || {
        if text.is_null() && len != 0 {
            set_error("a required argument is null");
            return std::ptr::null_mut();
        }
        if length_prefix(len).is_err() {
            set_error(
                "the TOML text is 4 GiB or more, and the result buffer holds no offset that large",
            );
            return std::ptr::null_mut();
        }
        let bytes = unsafe { slice_of(text, len) };
        let Ok(text) = std::str::from_utf8(bytes) else {
            set_error("the TOML text is not UTF-8");
            return std::ptr::null_mut();
        };
        let written = match ImDocument::parse(text) {
            Ok(document) => toml_document::document_buffer(&document),
            Err(error) => toml_document::error_buffer(text, &error),
        };
        match written {
            Ok(buffer) => into_result(buffer),
            Err(toml_document::WriteError::TooLong) => {
                set_error("a string of the TOML document is 4 GiB or more, and the result buffer holds no string that large");
                std::ptr::null_mut()
            }
            Err(toml_document::WriteError::NoSpan) => {
                set_error("the TOML reader gave a key or a value no place in the text");
                std::ptr::null_mut()
            }
        }
    })
}

/// Free a result.
///
/// # Safety
///
/// `result` must be null, or a pointer that a function of this bridge
/// returned as a `SinterBridgeResult` and that was not freed before.
/// The buffer that `data` points to becomes invalid.
#[no_mangle]
pub unsafe extern "C" fn sinter_bridge_result_free(result: *mut SinterBridgeResult) {
    guard((), move || {
        if result.is_null() {
            return;
        }
        let result = unsafe { Box::from_raw(result) };
        drop(unsafe { Vec::from_raw_parts(result.data, result.len, result.capacity) });
    })
}

/// The last failure on the calling thread, in a buffer of kind 5.
/// Returns null only on an internal fault.
#[no_mangle]
pub extern "C" fn sinter_bridge_last_failure() -> *mut SinterBridgeResult {
    guard(std::ptr::null_mut(), move || {
        into_result(last_failure().buffer())
    })
}

#[cfg(test)]
mod tests;
