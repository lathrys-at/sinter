// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

//! Tests of the C interface, through the C functions.

use super::*;
use crate::adapter::tests::{Wasm, BIND, RECOGNISED};
use crate::buffer::{
    KIND_ERROR_REPORT, KIND_FAILURE, KIND_MATCHES, KIND_RESPONSE, KIND_TREE, MAGIC,
};
use crate::failure::{WASM_COMPILE, WASM_PARSE};
use std::ffi::CString;
use std::path::Path;

fn repository() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap()
}

fn fixture_wasm() -> Vec<u8> {
    std::fs::read(repository().join("test/fixtures/tree-sitter-json/tree-sitter-json.wasm"))
        .unwrap()
}

struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8], kind: u32) -> (Self, u32) {
        let mut reader = Reader { bytes, at: 0 };
        assert_eq!(reader.u32(), MAGIC);
        assert_eq!(reader.u32(), kind);
        let count = reader.u32();
        assert_eq!(reader.u32(), 0);
        (reader, count)
    }

    fn u32(&mut self) -> u32 {
        let value = u32::from_le_bytes(self.bytes[self.at..self.at + 4].try_into().unwrap());
        self.at += 4;
        value
    }

    fn string(&mut self) -> String {
        let len = self.u32() as usize;
        let value = String::from_utf8(self.bytes[self.at..self.at + len].to_vec()).unwrap();
        self.at += len;
        value
    }

    fn end(&self) {
        assert_eq!(self.at, self.bytes.len());
    }
}

fn take(result: *mut SinterBridgeResult) -> Result<Vec<u8>, Failure> {
    if result.is_null() {
        return Err(last_failure());
    }
    let bytes = unsafe { std::slice::from_raw_parts((*result).data, (*result).len) }.to_vec();
    unsafe { sinter_bridge_result_free(result) };
    Ok(bytes)
}

fn made<T>(handle: *mut T) -> Result<*mut T, Failure> {
    if handle.is_null() {
        Err(last_failure())
    } else {
        Ok(handle)
    }
}

fn new_engine() -> *mut SinterBridgeEngine {
    made(sinter_bridge_engine_new()).unwrap()
}

fn load(
    engine: *mut SinterBridgeEngine,
    wasm: &[u8],
) -> Result<*mut SinterBridgeLanguage, Failure> {
    let name = CString::new("json").unwrap();
    made(unsafe { sinter_bridge_language_load(engine, name.as_ptr(), wasm.as_ptr(), wasm.len()) })
}

fn parse(
    engine: *mut SinterBridgeEngine,
    language: *const SinterBridgeLanguage,
    source: &[u8],
) -> Result<*mut SinterBridgeTree, Failure> {
    made(unsafe { sinter_bridge_parse(engine, language, source.as_ptr(), source.len()) })
}

fn compile(
    language: *const SinterBridgeLanguage,
    text: &str,
) -> Result<*mut SinterBridgeQuery, Failure> {
    made(unsafe { sinter_bridge_query_new(language, text.as_ptr(), text.len()) })
}

struct Json {
    engine: *mut SinterBridgeEngine,
    language: *mut SinterBridgeLanguage,
}

impl Json {
    fn new() -> Self {
        let engine = new_engine();
        let language = load(engine, &fixture_wasm()).unwrap();
        Json { engine, language }
    }

    fn parse(&self, source: &str) -> *mut SinterBridgeTree {
        parse(self.engine, self.language, source.as_bytes()).unwrap()
    }

    fn compile(&self, text: &str) -> Result<*mut SinterBridgeQuery, Failure> {
        compile(self.language, text)
    }

    fn sexp(&self, source: &str) -> String {
        let tree = self.parse(source);
        let sexp = sexp_of(tree);
        unsafe { sinter_bridge_tree_free(tree) };
        sexp
    }

    fn captures(&self, query: &str, source: &str) -> Vec<Capture> {
        let query = self.compile(query).unwrap();
        let tree = self.parse(source);
        let found = run(query, tree).unwrap();
        unsafe { sinter_bridge_query_free(query) };
        unsafe { sinter_bridge_tree_free(tree) };
        found
    }

    fn report(&self, source: &str) -> Report {
        let tree = self.parse(source);
        let report = report_of(tree);
        unsafe { sinter_bridge_tree_free(tree) };
        report
    }
}

impl Drop for Json {
    fn drop(&mut self) {
        unsafe { sinter_bridge_language_free(self.language) };
        unsafe { sinter_bridge_engine_free(self.engine) };
    }
}

fn sexp_of(tree: *const SinterBridgeTree) -> String {
    let bytes = take(unsafe { sinter_bridge_tree_sexp(tree) }).unwrap();
    let (mut reader, count) = Reader::new(&bytes, KIND_TREE);
    assert_eq!(count, 1);
    let sexp = reader.string();
    reader.end();
    sexp
}

#[derive(Debug, PartialEq, Eq)]
struct Capture {
    number: u32,
    pattern: u32,
    range: [u32; 6],
    name: String,
    node_type: String,
    text: String,
}

fn run(
    query: *const SinterBridgeQuery,
    tree: *const SinterBridgeTree,
) -> Result<Vec<Capture>, Failure> {
    let bytes = take(unsafe { sinter_bridge_query_run(query, tree) })?;
    let (mut reader, count) = Reader::new(&bytes, KIND_MATCHES);
    let mut found = Vec::new();
    for _ in 0..count {
        let number = reader.u32();
        let pattern = reader.u32();
        let mut range = [0; 6];
        for value in &mut range {
            *value = reader.u32();
        }
        found.push(Capture {
            number,
            pattern,
            range,
            name: reader.string(),
            node_type: reader.string(),
            text: reader.string(),
        });
    }
    reader.end();
    Ok(found)
}

type Place = ([u32; 6], String);

type Report = (bool, Vec<(u32, Place)>, Option<Place>);

fn place(reader: &mut Reader) -> Place {
    let mut range = [0; 6];
    for value in &mut range {
        *value = reader.u32();
    }
    (range, reader.string())
}

fn report_of(tree: *const SinterBridgeTree) -> Report {
    let bytes = take(unsafe { sinter_bridge_tree_errors(tree) }).unwrap();
    let (mut reader, count) = Reader::new(&bytes, KIND_ERROR_REPORT);
    assert_eq!(count, 1);
    let flag = match reader.u32() {
        0 => false,
        1 => true,
        other => panic!("the root flag is {other}"),
    };
    let nodes = (0..reader.u32())
        .map(|_| {
            let form = reader.u32();
            (form, place(&mut reader))
        })
        .collect();
    let lowest = match reader.u32() {
        0 => None,
        1 => Some(place(&mut reader)),
        other => panic!("the lowest flag is {other}"),
    };
    reader.end();
    (flag, nodes, lowest)
}

fn on_row(row: u32, start: u32, end: u32, node_type: &str) -> Place {
    ([start, end, row, start, row, end], node_type.to_owned())
}

fn query_failure(query: &str) -> Failure {
    Json::new().compile(query).unwrap_err()
}

#[test]
fn a_query_gives_the_captures_of_the_fixture_with_match_numbers() {
    let source = std::fs::read_to_string(repository().join("test/fixtures/sample.json")).unwrap();
    let query = std::fs::read_to_string(repository().join("test/fixtures/sample.scm")).unwrap();
    let found: Vec<(u32, u32, String, String, String)> = Json::new()
        .captures(&query, &source)
        .into_iter()
        .map(|c| (c.number, c.pattern, c.name, c.node_type, c.text))
        .collect();
    let expected = [
        (0, 0, "key", "string_content", "name"),
        (0, 0, "value", "string_content", "sinter"),
        (1, 0, "key", "string_content", "version"),
        (1, 0, "value", "string_content", "0.1.0"),
        (2, 1, "number", "number", "8080"),
        (3, 1, "number", "number", "9090"),
    ]
    .map(|(m, p, n, t, x)| (m, p, n.to_owned(), t.to_owned(), x.to_owned()));
    assert_eq!(found, expected);
}

#[test]
fn a_capture_holds_its_byte_range_and_its_rows_and_columns() {
    let found = Json::new().captures("(number) @n", "[1,\n  22]");
    let ranges: Vec<[u32; 6]> = found.iter().map(|c| c.range).collect();
    assert_eq!(ranges, vec![[1, 2, 0, 1, 0, 2], [6, 8, 1, 2, 1, 4]]);
}

#[test]
fn the_match_numbers_have_no_gap_where_a_predicate_drops_a_match() {
    let source = "{\"a\": 1, \"version\": 2, \"b\": 3}";
    let query = "((pair key: (string (string_content) @k)) (#not-eq? @k \"version\"))";
    let found: Vec<(u32, String)> = Json::new()
        .captures(query, source)
        .into_iter()
        .map(|c| (c.number, c.text))
        .collect();
    assert_eq!(found, vec![(0, "a".to_owned()), (1, "b".to_owned())]);
}

#[test]
fn a_match_that_captures_nothing_takes_no_number() {
    let found: Vec<(u32, u32)> = Json::new()
        .captures("(pair)\n(number) @n", "{\"a\": 1, \"b\": 2}")
        .into_iter()
        .map(|c| (c.number, c.pattern))
        .collect();
    assert_eq!(found, vec![(0, 1), (1, 1)]);
}

#[test]
fn the_text_predicates_apply() {
    let json = Json::new();
    let source = "[\"ab\", \"cd\", \"x\"]";
    let texts = |query: &str| -> Vec<String> {
        json.captures(query, source)
            .into_iter()
            .map(|c| c.text)
            .collect()
    };
    assert_eq!(
        texts("((string_content) @s (#match? @s \"^[a-b]\"))"),
        vec!["ab"]
    );
    assert_eq!(
        texts("((string_content) @s (#any-of? @s \"x\" \"cd\"))"),
        vec!["cd", "x"]
    );
}

#[test]
fn a_tree_and_a_query_outlive_their_language_and_their_engine() {
    let engine = new_engine();
    let language = load(engine, &fixture_wasm()).unwrap();
    let tree = parse(engine, language, b"[1, 2]").unwrap();
    let query = compile(language, "(number) @n").unwrap();
    unsafe { sinter_bridge_language_free(language) };
    unsafe { sinter_bridge_engine_free(engine) };
    assert_eq!(sexp_of(tree), "(document (array (number) (number)))");
    assert_eq!(run(query, tree).unwrap().len(), 2);
    unsafe { sinter_bridge_query_free(query) };
    unsafe { sinter_bridge_tree_free(tree) };
}

#[test]
fn a_language_outlives_its_engine() {
    let engine = new_engine();
    let language = load(engine, &fixture_wasm()).unwrap();
    unsafe { sinter_bridge_engine_free(engine) };
    let query = compile(language, "(number) @n").unwrap();
    unsafe { sinter_bridge_query_free(query) };
    unsafe { sinter_bridge_language_free(language) };
}

#[test]
fn a_query_over_a_tree_of_another_language_fails() {
    let json = Json::new();
    let other = load(json.engine, &fixture_wasm()).unwrap();
    let query = compile(other, "(number) @n").unwrap();
    let tree = json.parse("[1]");
    assert_eq!(run(query, tree), Err(Failure::LanguageMismatch));
    unsafe { sinter_bridge_query_free(query) };
    unsafe { sinter_bridge_tree_free(tree) };
    unsafe { sinter_bridge_language_free(other) };
}

#[test]
fn a_parse_with_a_language_of_another_engine_fails() {
    let json = Json::new();
    let engine = new_engine();
    assert_eq!(
        parse(engine, json.language, b"[1]"),
        Err(Failure::Internal(
            "the grammar was loaded by another engine".to_owned()
        ))
    );
    unsafe { sinter_bridge_engine_free(engine) };
}

#[test]
fn the_tree_holds_the_source_as_given() {
    let json = Json::new();
    let with = json.captures("(document) @d", "[1]\n");
    let without = json.captures("(document) @d", "[1]");
    assert_eq!(with[0].text, "[1]\n");
    assert_eq!(without[0].text, "[1]");
}

#[test]
#[cfg(target_pointer_width = "64")]
fn a_source_of_four_gib_or_more_fails_before_it_is_read() {
    let json = Json::new();
    let one_byte = [b'1'];
    let tree = unsafe {
        sinter_bridge_parse(
            json.engine,
            json.language,
            one_byte.as_ptr(),
            u32::MAX as usize + 1,
        )
    };
    assert!(tree.is_null());
    assert_eq!(last_failure(), Failure::SourceTooLong);
}

#[test]
fn a_null_handle_fails_with_a_message() {
    let null = Failure::Internal("a required argument is null".to_owned());
    let json = Json::new();
    assert_eq!(
        parse(std::ptr::null_mut(), json.language, b""),
        Err(null.clone())
    );
    assert_eq!(parse(json.engine, std::ptr::null(), b""), Err(null.clone()));
    assert_eq!(compile(std::ptr::null(), ""), Err(null.clone()));
    assert_eq!(
        take(unsafe { sinter_bridge_tree_sexp(std::ptr::null()) }),
        Err(null.clone())
    );
    assert_eq!(
        take(unsafe { sinter_bridge_tree_errors(std::ptr::null()) }),
        Err(null.clone())
    );
    assert_eq!(run(std::ptr::null(), std::ptr::null()), Err(null));
    assert_eq!(unsafe { sinter_bridge_tree_memory(std::ptr::null()) }, 0);
}

#[test]
fn freeing_a_null_handle_does_nothing() {
    unsafe {
        sinter_bridge_engine_free(std::ptr::null_mut());
        sinter_bridge_language_free(std::ptr::null_mut());
        sinter_bridge_tree_free(std::ptr::null_mut());
        sinter_bridge_query_free(std::ptr::null_mut());
        sinter_bridge_result_free(std::ptr::null_mut());
    }
}

#[test]
fn the_memory_of_a_tree_counts_its_text_and_its_nodes() {
    let json = Json::new();
    let small = json.parse("[1]");
    let large = json.parse("[1, 2, 3, 4]");
    let memory = |tree| unsafe { sinter_bridge_tree_memory(tree) };
    assert_eq!(memory(small), 3 + 5 * BYTES_PER_NODE);
    assert!(memory(large) > memory(small));
    unsafe { sinter_bridge_tree_free(small) };
    unsafe { sinter_bridge_tree_free(large) };
}

#[test]
fn bytes_that_are_not_wasm_do_not_load() {
    let engine = new_engine();
    let failure = load(engine, b"not wasm").unwrap_err();
    assert!(
        matches!(&failure, Failure::GrammarLoad { kind, .. } if *kind == WASM_PARSE),
        "{failure:?}"
    );
    unsafe { sinter_bridge_engine_free(engine) };
}

#[test]
fn a_grammar_cut_short_does_not_load() {
    let engine = new_engine();
    let wasm = fixture_wasm();
    let failure = load(engine, &wasm[..wasm.len() / 2]).unwrap_err();
    assert!(
        matches!(failure, Failure::GrammarLoad { .. }),
        "{failure:?}"
    );
    unsafe { sinter_bridge_engine_free(engine) };
}

#[test]
fn a_grammar_with_a_64_bit_memory_does_not_compile() {
    let mut wasm = fixture_wasm();
    let import = b"\x03env\x06memory\x02";
    let flags = wasm
        .windows(import.len())
        .position(|bytes| bytes == import)
        .expect("the fixture imports its memory")
        + import.len();
    wasm[flags] |= 0x04;
    let engine = new_engine();
    let failure = load(engine, &wasm).unwrap_err();
    assert!(
        matches!(
            &failure,
            Failure::GrammarLoad { kind, message }
                if *kind == WASM_COMPILE && message.contains("memory64")
        ),
        "{failure:?}"
    );
    unsafe { sinter_bridge_engine_free(engine) };
}

#[test]
fn an_empty_query_compiles_and_captures_nothing() {
    assert_eq!(Json::new().captures("", "[1]"), vec![]);
    assert_eq!(Json::new().captures("; a comment\n", "[1]"), vec![]);
}

#[test]
fn a_query_error_gives_its_kind_and_its_place() {
    let failure = |query: &str| match query_failure(query) {
        Failure::Query {
            kind,
            row,
            column,
            offset,
            ..
        } => (kind, row, column, offset),
        other => panic!("{other:?}"),
    };
    assert_eq!(failure("(pair key: (string) @k"), (0, 0, 22, 22));
    assert_eq!(failure("(number)\n(no_such_node)"), (1, 1, 1, 10));
    assert_eq!(failure("(pair nofield: (string))"), (2, 0, 6, 6));
    assert_eq!(failure("((number) @a (#eq? @b \"1\"))"), (3, 0, 20, 20));
    assert_eq!(failure("(string (number))"), (5, 0, 8, 8));
}

#[test]
fn a_predicate_error_gives_the_row_of_its_pattern() {
    match query_failure("(number) @n\n\n((string) @s\n  (#eq? @s))") {
        Failure::Query {
            kind, row, message, ..
        } => {
            assert_eq!((kind, row), (4, 2));
            assert!(message.contains("#eq?"), "{message}");
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn the_ten_predicates_compile() {
    let json = Json::new();
    for predicate in [
        "#eq? @s \"a\"",
        "#not-eq? @s \"a\"",
        "#any-eq? @s \"a\"",
        "#any-not-eq? @s \"a\"",
        "#match? @s \"a\"",
        "#not-match? @s \"a\"",
        "#any-match? @s \"a\"",
        "#any-not-match? @s \"a\"",
        "#any-of? @s \"a\" \"b\"",
        "#not-any-of? @s \"a\" \"b\"",
    ] {
        let query = json
            .compile(&format!("((string_content) @s ({predicate}))"))
            .unwrap_or_else(|failure| panic!("{predicate}: {failure:?}"));
        unsafe { sinter_bridge_query_free(query) };
    }
}

#[test]
fn every_other_predicate_and_every_directive_is_refused() {
    for (predicate, operator) in [
        ("#set! kind \"x\"", "set!"),
        ("#is? local", "is?"),
        ("#is-not? local", "is-not?"),
        ("#select-adjacent! @s @s", "select-adjacent!"),
        ("#strip! @s \"a\"", "strip!"),
        ("#lua-match? @s \"a\"", "lua-match?"),
        ("#foo? @s", "foo?"),
    ] {
        let query = format!("(number) @n\n  ((string_content) @s ({predicate}))");
        assert_eq!(
            query_failure(&query),
            Failure::PredicateNotAllowed {
                operator: operator.to_owned(),
                pattern: 1,
                offset: 14,
                row: 1,
                column: 2,
            },
            "{predicate}"
        );
    }
}

#[test]
fn a_predicate_whose_name_ends_in_neither_mark_is_a_syntax_error() {
    let query = "(number) @n\n  ((string_content) @s (#eq @s \"a\"))";
    assert_eq!(
        query_failure(query),
        Failure::Query {
            kind: 0,
            row: 1,
            column: 27,
            offset: 39,
            message: "  ((string_content) @s (#eq @s \"a\"))\n                           ^"
                .to_owned(),
        }
    );
}

#[test]
fn a_query_that_is_not_utf_8_fails() {
    let json = Json::new();
    let text = b"(number) @\xff";
    let query = unsafe { sinter_bridge_query_new(json.language, text.as_ptr(), text.len()) };
    assert!(query.is_null());
    assert_eq!(
        last_failure(),
        Failure::Internal("the query is not UTF-8".to_owned())
    );
}

#[test]
fn a_tree_with_no_error_has_an_empty_report() {
    assert_eq!(
        Json::new().report("[1, {\"a\": null}]"),
        (false, vec![], None)
    );
}

#[test]
fn a_missing_node_is_its_own_lowest_error_node() {
    let missing = ([3, 3, 1, 1, 1, 1], "]".to_owned());
    assert_eq!(
        Json::new().report("[\n1"),
        (true, vec![(1, missing.clone())], Some(missing))
    );
}

#[test]
fn an_error_node_inside_an_error_node_is_not_reported() {
    assert_eq!(
        Json::new().report("@"),
        (
            true,
            vec![(0, on_row(0, 0, 1, "ERROR"))],
            Some(on_row(0, 0, 1, "ERROR"))
        )
    );
}

#[test]
fn an_error_node_whose_children_hold_no_error_is_the_lowest() {
    assert_eq!(
        Json::new().report("[1 2]"),
        (
            true,
            vec![(0, on_row(0, 1, 2, "ERROR"))],
            Some(on_row(0, 1, 2, "ERROR"))
        )
    );
}

#[test]
fn the_error_nodes_come_in_the_order_of_the_text() {
    assert_eq!(
        Json::new().report("[@ [1]"),
        (
            true,
            vec![(0, on_row(0, 1, 2, "ERROR")), (1, on_row(0, 6, 6, "]"))],
            Some(on_row(0, 1, 2, "ERROR"))
        )
    );
}

#[test]
fn a_tree_that_nests_deeply_is_written_and_does_not_crash() {
    let depth = 40_000;
    let source = format!("{}1{}", "[".repeat(depth), "]".repeat(depth));
    let sexp = Json::new().sexp(&source);
    assert!(
        sexp.starts_with("(document (array (array "),
        "started {:.40}",
        sexp
    );
    assert_eq!(sexp.matches("(array").count(), depth);
}

#[test]
fn the_report_of_a_tree_that_nests_deeply_does_not_crash() {
    let depth = 40_000;
    let source = format!("{}1 2{}", "[".repeat(depth), "]".repeat(depth));
    let error = (
        [
            depth as u32,
            depth as u32 + 1,
            0,
            depth as u32,
            0,
            depth as u32 + 1,
        ],
        "ERROR".to_owned(),
    );
    assert_eq!(
        Json::new().report(&source),
        (true, vec![(0, error.clone())], Some(error))
    );
}

fn fixture_parser() -> Parser {
    let wasm_engine = wasmtime::Engine::new(&wasmtime::Config::new()).unwrap();
    let mut store = WasmStore::new(&wasm_engine).unwrap();
    let language = store.load_language("json", &fixture_wasm()).unwrap();
    let mut parser = Parser::new();
    parser.set_wasm_store(store).unwrap();
    parser.set_language(&language).unwrap();
    parser
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
        syntax::write_sexp(tree.root_node(), &mut written);
        assert_eq!(written, tree.root_node().to_sexp(), "source was {source:?}");
    }
}

#[test]
fn the_last_failure_comes_back_in_a_buffer() {
    set_failure(Failure::LanguageVersion(16));
    let bytes = take(sinter_bridge_last_failure()).unwrap();
    assert_eq!(bytes, Failure::LanguageVersion(16).buffer());
    let (mut reader, count) = Reader::new(&bytes, KIND_FAILURE);
    assert_eq!((count, reader.u32(), reader.u32()), (1, 2, 16));
    reader.end();
}

#[test]
fn a_panic_becomes_a_failure_and_not_an_abort() {
    set_failure(Failure::SourceTooLong);
    let value = guard(-1_i32, || panic!("a panic inside the bridge"));
    assert_eq!(value, -1);
    assert_eq!(
        last_failure(),
        Failure::Internal("the parser bridge stopped on an internal fault".to_owned())
    );
}

const LIMITS: SinterBridgeLimits = SinterBridgeLimits {
    fuel: 1_000_000,
    memory: 1 << 20,
};

fn load_adapter(
    engine: *mut SinterBridgeEngine,
    wasm: &[u8],
) -> Result<*mut SinterBridgeAdapter, Failure> {
    made(unsafe { sinter_bridge_adapter_load(engine, wasm.as_ptr(), wasm.len(), LIMITS) })
}

fn call_adapter(
    adapter: *const SinterBridgeAdapter,
    function: u32,
    report: &[u8],
) -> Result<Vec<u8>, Failure> {
    let request = b"{}";
    let bytes = take(unsafe {
        sinter_bridge_adapter_call(
            adapter,
            function,
            request.as_ptr(),
            request.len(),
            report.as_ptr(),
            report.len(),
            LIMITS,
        )
    })?;
    let (mut reader, count) = Reader::new(&bytes, KIND_RESPONSE);
    assert_eq!(count, 1);
    let len = reader.u32() as usize;
    let response = bytes[reader.at..reader.at + len].to_vec();
    reader.at += len;
    reader.end();
    Ok(response)
}

#[test]
fn an_adapter_loads_and_answers_both_calls_through_the_c_interface() {
    let engine = new_engine();
    let adapter = load_adapter(engine, &Wasm::good().bytes()).unwrap();
    assert_eq!(unsafe { sinter_bridge_adapter_interface(adapter) }, 1);
    assert_eq!(call_adapter(adapter, 0, b"r").unwrap(), RECOGNISED);
    assert_eq!(call_adapter(adapter, 1, b"\xffr").unwrap(), b"\xffr");
    unsafe { sinter_bridge_adapter_free(adapter) };
    unsafe { sinter_bridge_engine_free(engine) };
}

#[test]
fn an_adapter_outlives_its_engine() {
    let engine = new_engine();
    let first = load_adapter(engine, &Wasm::good().bytes()).unwrap();
    let second = load_adapter(engine, &Wasm::good().body(BIND, vec![0x00]).bytes()).unwrap();
    unsafe { sinter_bridge_engine_free(engine) };
    assert_eq!(call_adapter(first, 1, b"r").unwrap(), b"r");
    assert!(matches!(
        call_adapter(second, 1, b"r"),
        Err(Failure::AdapterTrap(_))
    ));
    unsafe { sinter_bridge_adapter_free(first) };
    unsafe { sinter_bridge_adapter_free(second) };
}

#[test]
fn an_adapter_that_does_not_load_gives_its_failure() {
    let engine = new_engine();
    assert!(matches!(
        load_adapter(engine, b"not wasm"),
        Err(Failure::AdapterInvalid { cause: 0, .. })
    ));
    unsafe { sinter_bridge_engine_free(engine) };
}

#[test]
fn an_adapter_call_with_a_bad_argument_fails() {
    let null = Failure::Internal("a required argument is null".to_owned());
    let engine = new_engine();
    assert_eq!(load_adapter(std::ptr::null_mut(), b""), Err(null.clone()));
    assert_eq!(
        made(unsafe { sinter_bridge_adapter_load(engine, std::ptr::null(), 1, LIMITS) }),
        Err(null.clone())
    );
    assert_eq!(call_adapter(std::ptr::null(), 0, b""), Err(null.clone()));
    let adapter = load_adapter(engine, &Wasm::good().bytes()).unwrap();
    let report = unsafe {
        sinter_bridge_adapter_call(adapter, 0, std::ptr::null(), 1, std::ptr::null(), 0, LIMITS)
    };
    assert_eq!(take(report), Err(null));
    assert_eq!(
        call_adapter(adapter, 2, b""),
        Err(Failure::Internal(
            "the adapter has no function 2".to_owned()
        ))
    );
    assert_eq!(
        unsafe { sinter_bridge_adapter_interface(std::ptr::null()) },
        0
    );
    unsafe { sinter_bridge_adapter_free(adapter) };
    unsafe { sinter_bridge_adapter_free(std::ptr::null_mut()) };
    unsafe { sinter_bridge_engine_free(engine) };
}

fn sha256_hex(data: &[u8]) -> String {
    let bytes = take(unsafe { sinter_bridge_sha256(data.as_ptr(), data.len()) }).unwrap();
    let (reader, count) = Reader::new(&bytes, KIND_DIGEST);
    assert_eq!(count, 1);
    assert_eq!(bytes.len(), reader.at + 32);
    bytes[reader.at..]
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

#[test]
fn the_digest_matches_the_published_test_values() {
    assert_eq!(
        sha256_hex(b""),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
    assert_eq!(
        sha256_hex(b"abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
    assert_eq!(
        sha256_hex(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    );
    assert_eq!(
        sha256_hex(b"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"),
        "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"
    );
    assert_eq!(
        sha256_hex(&[b'a'; 1_000_000]),
        "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
    );
}

#[test]
fn a_null_pointer_hashes_as_the_empty_string_when_the_length_is_0() {
    assert!(take(unsafe { sinter_bridge_sha256(std::ptr::null(), 0) }).is_ok());
}

#[test]
fn a_null_pointer_with_a_length_fails_with_a_message() {
    assert_eq!(
        take(unsafe { sinter_bridge_sha256(std::ptr::null(), 1) }),
        Err(Failure::Internal("a required argument is null".to_owned()))
    );
}

fn toml_result(text: &[u8]) -> Result<(u32, Vec<u8>), Failure> {
    let bytes = take(unsafe { sinter_bridge_toml_parse(text.as_ptr(), text.len()) })?;
    let kind = u32::from_le_bytes(bytes[4..8].try_into().unwrap());
    Ok((kind, bytes))
}

#[test]
fn a_toml_document_and_a_toml_error_have_their_kinds() {
    let (kind, bytes) = toml_result(b"a = 'x'\n").unwrap();
    assert_eq!(kind, toml_document::KIND_TOML_DOCUMENT);
    let (mut reader, count) = Reader::new(&bytes, kind);
    assert_eq!(count, 1);
    assert_eq!(reader.u32(), 1);
    assert_eq!(reader.string(), "a");
    let (kind, _) = toml_result(b"a = \n").unwrap();
    assert_eq!(kind, toml_document::KIND_TOML_ERROR);
}

#[test]
fn a_toml_text_that_is_not_utf_8_fails_with_a_message() {
    assert_eq!(
        toml_result(b"a = '\xff'"),
        Err(Failure::Internal("the TOML text is not UTF-8".to_owned()))
    );
}

#[test]
fn a_null_toml_text_with_a_length_fails_with_a_message() {
    assert_eq!(
        take(unsafe { sinter_bridge_toml_parse(std::ptr::null(), 1) }),
        Err(Failure::Internal("a required argument is null".to_owned()))
    );
}

#[test]
#[cfg(target_pointer_width = "64")]
fn a_toml_text_of_four_gib_or_more_fails_with_a_message() {
    let one_byte = [b'a'];
    let result = unsafe { sinter_bridge_toml_parse(one_byte.as_ptr(), u32::MAX as usize + 1) };
    assert!(result.is_null());
    assert!(
        matches!(last_failure(), Failure::Internal(message) if message.contains("4 GiB or more"))
    );
}
