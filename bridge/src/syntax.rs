// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

//! Parse trees and queries: the S-expression of a tree, the error
//! report of a tree, the compilation of a query, and the captures of
//! one query over one tree.

use tree_sitter::{
    Language, Node, Query, QueryCursor, QueryErrorKind, StreamingIterator, Tree, WasmError,
    WasmErrorKind,
};

use crate::buffer::{
    KIND_ERROR_REPORT, KIND_MATCHES, KIND_TREE, TooLong, length_prefix, put_bytes, put_header,
    put_u32, set_count,
};
use crate::failure::{Failure, WASM_COMPILE, WASM_INSTANTIATE, WASM_OTHER, WASM_PARSE};

/// The failure of a grammar that tree-sitter does not load.
pub(crate) fn grammar_load_failure(error: WasmError) -> Failure {
    let kind = match error.kind {
        WasmErrorKind::Parse => WASM_PARSE,
        WasmErrorKind::Compile => WASM_COMPILE,
        WasmErrorKind::Instantiate => WASM_INSTANTIATE,
        WasmErrorKind::Other => WASM_OTHER,
    };
    Failure::GrammarLoad {
        kind,
        message: error.message,
    }
}

/// Accept the ABI versions that tree-sitter reads, and refuse the
/// others.
pub(crate) fn check_version(version: usize) -> Result<(), Failure> {
    if (tree_sitter::MIN_COMPATIBLE_LANGUAGE_VERSION..=tree_sitter::LANGUAGE_VERSION)
        .contains(&version)
    {
        Ok(())
    } else {
        Err(Failure::LanguageVersion(
            u32::try_from(version).unwrap_or(u32::MAX),
        ))
    }
}

fn too_long(what: &str) -> Failure {
    Failure::Internal(format!(
        "{what} is 4 GiB or more, and the result buffer holds no string that large"
    ))
}

fn has_its_own_name(node: Node) -> bool {
    node.child_count() == 0 && (node.is_missing() || node.is_error())
}

/// Write the parse tree under `root` as an S-expression. The walk
/// holds its state in a cursor and in one vector, and it does not
/// recurse, so the depth of the tree costs heap and not stack.
pub(crate) fn write_sexp(root: Node, out: &mut String) {
    let mut cursor = root.walk();
    let mut open: Vec<bool> = Vec::new();
    let mut descending = true;
    let mut written = false;
    loop {
        if descending {
            let node = cursor.node();
            let visible = node.is_named() || node.is_missing();
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

/// The tree as a buffer of kind 1.
pub(crate) fn sexp_buffer(tree: &Tree) -> Result<Vec<u8>, Failure> {
    let mut buffer = Vec::new();
    put_header(&mut buffer, KIND_TREE);
    let mut sexp = String::new();
    write_sexp(tree.root_node(), &mut sexp);
    put_bytes(&mut buffer, sexp.as_bytes()).map_err(|_| too_long("the parse tree"))?;
    set_count(&mut buffer, 1);
    Ok(buffer)
}

fn put_range(buffer: &mut Vec<u8>, node: Node) {
    let start = node.start_position();
    let end = node.end_position();
    for value in [
        node.start_byte(),
        node.end_byte(),
        start.row,
        start.column,
        end.row,
        end.column,
    ] {
        put_u32(buffer, value as u32);
    }
}

fn put_node(buffer: &mut Vec<u8>, node: Node) -> Result<(), TooLong> {
    put_range(buffer, node);
    put_bytes(buffer, node.kind().as_bytes())
}

const FORM_ERROR: u32 = 0;

const FORM_MISSING: u32 = 1;

struct ErrorReport<'tree> {
    nodes: Vec<(bool, Node<'tree>)>,
    lowest: Option<Node<'tree>>,
}

fn error_report(root: Node) -> ErrorReport {
    let mut report = ErrorReport {
        nodes: Vec::new(),
        lowest: None,
    };
    if !root.has_error() {
        return report;
    }
    let mut cursor = root.walk();
    let mut above: Vec<bool> = Vec::new();
    let mut held = 0usize;
    'visit: loop {
        let node = cursor.node();
        if held == 0 && (node.is_error() || node.is_missing()) {
            report.nodes.push((node.is_missing(), node));
        }
        if cursor.goto_first_child() {
            loop {
                if cursor.node().has_error() {
                    above.push(node.is_error());
                    held += usize::from(node.is_error());
                    continue 'visit;
                }
                if !cursor.goto_next_sibling() {
                    break;
                }
            }
            cursor.goto_parent();
        }
        if report.lowest.is_none() {
            report.lowest = Some(node);
        }
        loop {
            while cursor.goto_next_sibling() {
                if cursor.node().has_error() {
                    continue 'visit;
                }
            }
            match above.pop() {
                None => break 'visit,
                Some(error) => {
                    held -= usize::from(error);
                    cursor.goto_parent();
                }
            }
        }
    }
    report
}

/// The error report of a tree as a buffer of kind 7.
pub(crate) fn error_report_buffer(tree: &Tree) -> Result<Vec<u8>, Failure> {
    let root = tree.root_node();
    let report = error_report(root);
    let mut buffer = Vec::new();
    put_header(&mut buffer, KIND_ERROR_REPORT);
    put_u32(&mut buffer, u32::from(root.has_error()));
    put_u32(&mut buffer, report.nodes.len() as u32);
    let written = (|| -> Result<(), TooLong> {
        for (missing, node) in &report.nodes {
            put_u32(
                &mut buffer,
                if *missing { FORM_MISSING } else { FORM_ERROR },
            );
            put_node(&mut buffer, *node)?;
        }
        match report.lowest {
            Some(node) => {
                put_u32(&mut buffer, 1);
                put_node(&mut buffer, node)
            }
            None => {
                put_u32(&mut buffer, 0);
                Ok(())
            }
        }
    })();
    written.map_err(|_| too_long("the type of a node"))?;
    set_count(&mut buffer, 1);
    Ok(buffer)
}

fn row_and_column(text: &str, offset: usize) -> (u32, u32) {
    let before = &text.as_bytes()[..offset.min(text.len())];
    let row = before.iter().filter(|&&byte| byte == b'\n').count();
    let line_start = before
        .iter()
        .rposition(|&byte| byte == b'\n')
        .map_or(0, |index| index + 1);
    (row as u32, (before.len() - line_start) as u32)
}

fn query_error_kind(kind: QueryErrorKind) -> u32 {
    match kind {
        QueryErrorKind::Syntax => 0,
        QueryErrorKind::NodeType => 1,
        QueryErrorKind::Field => 2,
        QueryErrorKind::Capture => 3,
        QueryErrorKind::Predicate => 4,
        QueryErrorKind::Structure => 5,
        QueryErrorKind::Language => 6,
    }
}

fn operator_not_applied(query: &Query, index: usize) -> Option<String> {
    if let Some(predicate) = query.general_predicates(index).first() {
        return Some(predicate.operator.to_string());
    }
    if !query.property_settings(index).is_empty() {
        return Some("set!".to_owned());
    }
    query
        .property_predicates(index)
        .first()
        .map(|(_, positive)| if *positive { "is?" } else { "is-not?" }.to_owned())
}

/// Compile a query for `language`. The query is valid only when every
/// predicate of every pattern is one that the query cursor applies.
pub(crate) fn compile_query(language: &Language, text: &[u8]) -> Result<Query, Failure> {
    if length_prefix(text.len()).is_err() {
        return Err(too_long("the query"));
    }
    let text = std::str::from_utf8(text)
        .map_err(|_| Failure::Internal("the query is not UTF-8".to_owned()))?;
    let query = Query::new(language, text).map_err(|error| Failure::Query {
        kind: query_error_kind(error.kind),
        row: error.row as u32,
        column: error.column as u32,
        offset: error.offset as u32,
        message: error.message,
    })?;
    for index in 0..query.pattern_count() {
        if let Some(operator) = operator_not_applied(&query, index) {
            let offset = query.start_byte_for_pattern(index);
            let (row, column) = row_and_column(text, offset);
            return Err(Failure::PredicateNotAllowed {
                operator,
                pattern: index as u32,
                offset: offset as u32,
                row,
                column,
            });
        }
    }
    Ok(query)
}

/// The captures of `query` over `tree`, whose text is `source`, as a
/// buffer of kind 6.
///
/// The matches are numbered from 0, with no gap, in the order in
/// which the cursor gives them. A match that holds no capture takes no
/// number.
pub(crate) fn matches_buffer(
    query: &Query,
    tree: &Tree,
    source: &[u8],
) -> Result<Vec<u8>, Failure> {
    let names = query.capture_names();
    let mut buffer = Vec::new();
    put_header(&mut buffer, KIND_MATCHES);
    let mut count: u32 = 0;
    let mut number: u32 = 0;
    let mut cursor = QueryCursor::new();
    let mut matches = cursor.matches(query, tree.root_node(), source);
    while let Some(found) = matches.next() {
        if found.captures.is_empty() {
            continue;
        }
        for capture in found.captures {
            let node = capture.node;
            put_u32(&mut buffer, number);
            put_u32(&mut buffer, found.pattern_index as u32);
            let name = names.get(capture.index as usize).copied().unwrap_or("");
            let text = source
                .get(node.start_byte()..node.end_byte())
                .unwrap_or(&[]);
            put_range(&mut buffer, node);
            put_bytes(&mut buffer, name.as_bytes())
                .and_then(|()| put_bytes(&mut buffer, node.kind().as_bytes()))
                .and_then(|()| put_bytes(&mut buffer, text))
                .map_err(|_| too_long("a string of a capture"))?;
            count = count
                .checked_add(1)
                .ok_or_else(|| too_long("the list of captures"))?;
        }
        number += 1;
    }
    set_count(&mut buffer, count);
    Ok(buffer)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_versions_13_to_15_are_accepted_and_the_others_refused() {
        assert_eq!(check_version(12), Err(Failure::LanguageVersion(12)));
        assert_eq!(check_version(13), Ok(()));
        assert_eq!(check_version(15), Ok(()));
        assert_eq!(check_version(16), Err(Failure::LanguageVersion(16)));
    }

    #[test]
    fn a_row_and_a_column_count_bytes_from_the_last_line_feed() {
        let text = "ab\ncd\n\u{e9}f";
        assert_eq!(row_and_column(text, 0), (0, 0));
        assert_eq!(row_and_column(text, 2), (0, 2));
        assert_eq!(row_and_column(text, 3), (1, 0));
        assert_eq!(row_and_column(text, 5), (1, 2));
        assert_eq!(row_and_column(text, 6), (2, 0));
        assert_eq!(row_and_column(text, 8), (2, 2));
    }

    #[test]
    fn every_kind_of_wasm_error_has_its_code() {
        let pairs = [
            (WasmErrorKind::Parse, WASM_PARSE),
            (WasmErrorKind::Compile, WASM_COMPILE),
            (WasmErrorKind::Instantiate, WASM_INSTANTIATE),
            (WasmErrorKind::Other, WASM_OTHER),
        ];
        for (kind, code) in pairs {
            let failure = grammar_load_failure(WasmError {
                kind,
                message: "m".to_owned(),
            });
            assert_eq!(
                failure,
                Failure::GrammarLoad {
                    kind: code,
                    message: "m".to_owned()
                }
            );
        }
    }

    #[test]
    fn every_kind_of_query_error_has_its_code() {
        let kinds = [
            QueryErrorKind::Syntax,
            QueryErrorKind::NodeType,
            QueryErrorKind::Field,
            QueryErrorKind::Capture,
            QueryErrorKind::Predicate,
            QueryErrorKind::Structure,
            QueryErrorKind::Language,
        ];
        for (code, kind) in kinds.into_iter().enumerate() {
            assert_eq!(query_error_kind(kind), code as u32);
        }
    }
}
