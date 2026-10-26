// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

// @cites toml-reader

//! Read a TOML document with toml_edit, and write every table, key,
//! and value with its byte span into one result buffer.

use toml_edit::{Datetime, Document, Item, Key, Offset, Table, TomlError, Value};

use crate::buffer::{TooLong, length_prefix, put_bytes, put_header, put_u32, set_count};

/// The `kind` field of a buffer that holds a TOML document.
pub(crate) const KIND_TOML_DOCUMENT: u32 = 3;

/// The `kind` field of a buffer that holds the error of a TOML text.
pub(crate) const KIND_TOML_ERROR: u32 = 4;

const TAG_STRING: u32 = 0;
const TAG_INTEGER: u32 = 1;
const TAG_FLOAT: u32 = 2;
const TAG_BOOLEAN: u32 = 3;
const TAG_DATETIME: u32 = 4;
const TAG_ARRAY: u32 = 5;
const TAG_TABLE: u32 = 6;
const TAG_ARRAY_OF_TABLES: u32 = 7;
const TAG_INLINE_TABLE: u32 = 8;

const FORM_CRATE: u32 = 0;

const FORM_HEADER_TABLE: u32 = 1;

const FORM_CRATE_AT_KEY: u32 = 2;

/// Why the writer stopped.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum WriteError {
    /// A length or an offset does not fit 32 bits.
    TooLong,
    /// toml_edit gave a key or a value no span.
    NoSpan,
}

impl From<TooLong> for WriteError {
    fn from(_: TooLong) -> Self {
        WriteError::TooLong
    }
}

fn put_offset(buffer: &mut Vec<u8>, offset: usize) -> Result<(), WriteError> {
    put_u32(buffer, length_prefix(offset)?);
    Ok(())
}

fn put_span(buffer: &mut Vec<u8>, span: Option<std::ops::Range<usize>>) -> Result<(), WriteError> {
    let span = span.ok_or(WriteError::NoSpan)?;
    put_offset(buffer, span.start)?;
    put_offset(buffer, span.end)
}

fn put_datetime(buffer: &mut Vec<u8>, datetime: &Datetime) {
    let parts = u32::from(datetime.date.is_some())
        | (u32::from(datetime.time.is_some()) << 1)
        | (u32::from(datetime.offset.is_some()) << 2);
    put_u32(buffer, parts);
    let (year, month, day) = datetime
        .date
        .map_or((0, 0, 0), |d| (d.year.into(), d.month.into(), d.day.into()));
    put_u32(buffer, year);
    put_u32(buffer, month);
    put_u32(buffer, day);
    let (hour, minute, second, nanosecond) = datetime.time.map_or((0, 0, 0, 0), |t| {
        (
            t.hour.into(),
            t.minute.into(),
            t.second.unwrap_or(0).into(),
            t.nanosecond.unwrap_or(0),
        )
    });
    put_u32(buffer, hour);
    put_u32(buffer, minute);
    put_u32(buffer, second);
    put_u32(buffer, nanosecond);
    let (offset, minutes) = match datetime.offset {
        Some(Offset::Custom { minutes }) => (1, i32::from(minutes)),
        Some(Offset::Z) | None => (0, 0),
    };
    put_u32(buffer, offset);
    put_u32(buffer, minutes as u32);
}

fn put_value(
    buffer: &mut Vec<u8>,
    value: &Value,
    fallback: Option<std::ops::Range<usize>>,
) -> Result<(), WriteError> {
    let tag = match value {
        Value::String(_) => TAG_STRING,
        Value::Integer(_) => TAG_INTEGER,
        Value::Float(_) => TAG_FLOAT,
        Value::Boolean(_) => TAG_BOOLEAN,
        Value::Datetime(_) => TAG_DATETIME,
        Value::Array(_) => TAG_ARRAY,
        Value::InlineTable(table) if table.is_dotted() => TAG_TABLE,
        Value::InlineTable(_) => TAG_INLINE_TABLE,
    };
    put_u32(buffer, tag);
    put_span(buffer, value.span().or(fallback))?;
    match value {
        Value::String(text) => put_bytes(buffer, text.value().as_bytes())?,
        Value::Integer(number) => buffer.extend_from_slice(&number.value().to_le_bytes()),
        Value::Float(number) => buffer.extend_from_slice(&number.value().to_bits().to_le_bytes()),
        Value::Boolean(flag) => put_u32(buffer, u32::from(*flag.value())),
        Value::Datetime(datetime) => put_datetime(buffer, datetime.value()),
        Value::Array(array) => {
            put_u32(buffer, length_prefix(array.len())?);
            for member in array.iter() {
                put_value(buffer, member, None)?;
            }
        }
        Value::InlineTable(table) => {
            put_u32(buffer, length_prefix(table.len())?);
            for (name, _) in table.iter() {
                let (key, item) = table.get_key_value(name).ok_or(WriteError::NoSpan)?;
                put_entry(buffer, key, item)?;
            }
        }
    }
    Ok(())
}

fn put_table(buffer: &mut Vec<u8>, table: &Table) -> Result<(), WriteError> {
    put_u32(buffer, length_prefix(table.len())?);
    for (name, _) in table.iter() {
        let (key, item) = table.get_key_value(name).ok_or(WriteError::NoSpan)?;
        put_entry(buffer, key, item)?;
    }
    Ok(())
}

fn put_entry(buffer: &mut Vec<u8>, key: &Key, item: &Item) -> Result<(), WriteError> {
    put_bytes(buffer, key.get().as_bytes())?;
    put_span(buffer, key.span())?;
    match item {
        Item::Value(value) => put_value(buffer, value, key.span()),
        Item::Table(table) => {
            put_u32(buffer, TAG_TABLE);
            put_span(buffer, key.span())?;
            put_table(buffer, table)
        }
        Item::ArrayOfTables(array) => {
            put_u32(buffer, TAG_ARRAY_OF_TABLES);
            put_span(buffer, key.span())?;
            put_u32(buffer, length_prefix(array.len())?);
            for table in array.iter() {
                put_table(buffer, table)?;
            }
            Ok(())
        }
        Item::None => Err(WriteError::NoSpan),
    }
}

/// A buffer of kind 3 that holds `document`.
pub(crate) fn document_buffer(document: &Document<&str>) -> Result<Vec<u8>, WriteError> {
    let mut buffer = Vec::new();
    put_header(&mut buffer, KIND_TOML_DOCUMENT);
    put_table(&mut buffer, document.as_table())?;
    set_count(&mut buffer, 1);
    Ok(buffer)
}

/// A dotted key that adds a key to a table that a table header made.
#[derive(Debug, PartialEq, Eq)]
pub(crate) struct HeaderTableError {
    /// The byte span of the whole dotted key, as the text writes it.
    pub(crate) start: usize,
    pub(crate) end: usize,
    /// The names of the table that a header made, from the top level.
    pub(crate) table: Vec<String>,
    /// Whether that table is the last table of an array of tables.
    pub(crate) array: bool,
    /// The names of the dotted key after that table.
    pub(crate) rest: Vec<String>,
}

/// One part of a dotted key: its decoded name and its byte span.
type KeyPart = (String, std::ops::Range<usize>);

fn is_bare_key_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-'
}

fn skip_blanks(bytes: &[u8], mut at: usize) -> usize {
    while matches!(bytes.get(at), Some(b' ' | b'\t')) {
        at += 1;
    }
    at
}

fn line_start(text: &str, at: usize) -> usize {
    let bytes = text.as_bytes();
    let first = bytes
        .get(..at)
        .and_then(|before| before.iter().rposition(|byte| *byte == b'\n'))
        .map_or(0, |newline| newline + 1);
    skip_blanks(bytes, first)
}

fn one_key(text: &str) -> Option<String> {
    let mut keys = Key::parse(text).ok()?;
    if keys.len() != 1 {
        return None;
    }
    Some(keys.pop()?.get().to_owned())
}

fn byte_before(bytes: &[u8], at: usize) -> Option<u8> {
    at.checked_sub(1)
        .and_then(|before| bytes.get(before))
        .copied()
}

fn back_over_blanks(bytes: &[u8], mut at: usize) -> usize {
    while matches!(byte_before(bytes, at), Some(b' ' | b'\t')) {
        at -= 1;
    }
    at
}

fn part_start(bytes: &[u8], stop: usize) -> Option<usize> {
    match byte_before(bytes, stop)? {
        b'"' => {
            let mut at = stop - 1;
            loop {
                let quote = bytes.get(..at)?.iter().rposition(|byte| *byte == b'"')?;
                let backslashes = bytes[..quote]
                    .iter()
                    .rev()
                    .take_while(|byte| **byte == b'\\')
                    .count();
                if backslashes % 2 == 0 {
                    return Some(quote);
                }
                at = quote;
            }
        }
        b'\'' => bytes
            .get(..stop - 1)?
            .iter()
            .rposition(|byte| *byte == b'\''),
        byte if is_bare_key_byte(byte) => {
            let mut at = stop;
            while byte_before(bytes, at).is_some_and(is_bare_key_byte) {
                at -= 1;
            }
            Some(at)
        }
        _ => None,
    }
}

fn dotted_key_start(text: &str, mut at: usize) -> usize {
    let bytes = text.as_bytes();
    loop {
        let before = back_over_blanks(bytes, at);
        if byte_before(bytes, before) != Some(b'.') {
            return at;
        }
        match part_start(bytes, back_over_blanks(bytes, before - 1)) {
            Some(start) => at = start,
            None => return at,
        }
    }
}

fn key_path(text: &str, span: &std::ops::Range<usize>) -> Option<Vec<String>> {
    let name = one_key(text.get(span.clone())?)?;
    let parts = dotted_key_at(text, dotted_key_start(text, span.start));
    match parts.and_then(|parts| {
        let index = parts.iter().position(|(_, part)| part == span)?;
        Some(names_of(&parts[..=index]))
    }) {
        Some(path) => Some(path),
        None => Some(vec![name]),
    }
}

fn dotted_key_at(text: &str, start: usize) -> Option<Vec<KeyPart>> {
    let bytes = text.as_bytes();
    let mut at = start;
    let mut parts = Vec::new();
    loop {
        let part_start = at;
        match *bytes.get(at)? {
            b'"' => {
                at += 1;
                loop {
                    match *bytes.get(at)? {
                        b'\\' => at += 2,
                        b'"' => break,
                        b'\n' => return None,
                        _ => at += 1,
                    }
                }
                at += 1;
            }
            b'\'' => {
                at += 1;
                loop {
                    match *bytes.get(at)? {
                        b'\'' => break,
                        b'\n' => return None,
                        _ => at += 1,
                    }
                }
                at += 1;
            }
            byte if is_bare_key_byte(byte) => {
                while bytes.get(at).is_some_and(|byte| is_bare_key_byte(*byte)) {
                    at += 1;
                }
            }
            _ => return None,
        }
        parts.push((one_key(text.get(part_start..at)?)?, part_start..at));
        at = skip_blanks(bytes, at);
        if bytes.get(at) != Some(&b'.') {
            return Some(parts);
        }
        at = skip_blanks(bytes, at + 1);
    }
}

fn current_table(root: &Table) -> (&Table, Vec<String>) {
    let mut best: (isize, &Table, Vec<String>) = (0, root, Vec::new());
    let mut pending: Vec<(&Table, Vec<String>)> = vec![(root, Vec::new())];
    while let Some((table, names)) = pending.pop() {
        for (name, item) in table.iter() {
            let mut path = names.clone();
            path.push(name.to_owned());
            let children: Vec<&Table> = match item {
                Item::Table(child) => vec![child],
                Item::ArrayOfTables(array) => array.iter().collect(),
                _ => Vec::new(),
            };
            for child in children {
                if let Some(position) = child.position()
                    && position > best.0
                {
                    best = (position, child, path.clone());
                }
                pending.push((child, path.clone()));
            }
        }
    }
    (best.1, best.2)
}

fn names_of(parts: &[KeyPart]) -> Vec<String> {
    parts.iter().map(|(name, _)| name.clone()).collect()
}

/// The error of a dotted key that adds a key to a table that a table
/// header made, when `error` is that case.
pub(crate) fn header_table_error(text: &str, error: &TomlError) -> Option<HeaderTableError> {
    if error.message() != "duplicate key" {
        return None;
    }
    let span = error.span()?;
    let start = line_start(text, span.start);
    let parts = dotted_key_at(text, start)?;
    let named_at = parts.iter().position(|(_, part)| *part == span)?;
    let before = Document::parse(text.get(..start)?).ok()?;
    let leaf = parts.len().checked_sub(1)?;
    let (mut table, mut names) = current_table(before.as_table());
    for (index, (part, _)) in parts[..leaf].iter().enumerate() {
        names.push(part.clone());
        let (named, array) = match table.get(part)? {
            Item::Table(child) if !child.is_implicit() => (index, false),
            Item::Table(child) => {
                table = child;
                continue;
            }
            Item::ArrayOfTables(_) if index + 1 == leaf => (leaf, true),
            Item::ArrayOfTables(array) => {
                table = array.iter().last()?;
                continue;
            }
            _ => return None,
        };
        if named != named_at {
            return None;
        }
        return Some(HeaderTableError {
            start,
            end: parts[leaf].1.end,
            table: names,
            array,
            rest: names_of(&parts[index + 1..]),
        });
    }
    None
}

fn put_header_table(
    buffer: &mut Vec<u8>,
    text: &str,
    found: &HeaderTableError,
) -> Result<(), WriteError> {
    put_u32(buffer, FORM_HEADER_TABLE);
    put_offset(buffer, found.start)?;
    put_offset(buffer, found.end)?;
    put_bytes(
        buffer,
        text.get(found.start..found.end).unwrap_or("").as_bytes(),
    )?;
    put_u32(buffer, length_prefix(found.table.len())?);
    for name in &found.table {
        put_bytes(buffer, name.as_bytes())?;
    }
    put_u32(buffer, u32::from(found.array));
    put_u32(buffer, length_prefix(found.rest.len())?);
    for name in &found.rest {
        put_bytes(buffer, name.as_bytes())?;
    }
    Ok(())
}

/// A buffer of kind 4 that holds the error of `text`.
pub(crate) fn error_buffer(text: &str, error: &TomlError) -> Result<Vec<u8>, WriteError> {
    let mut buffer = Vec::new();
    put_header(&mut buffer, KIND_TOML_ERROR);
    if let Some(found) = header_table_error(text, error) {
        put_header_table(&mut buffer, text, &found)?;
        set_count(&mut buffer, 1);
        return Ok(buffer);
    }
    let span = error.span().unwrap_or(text.len()..text.len());
    let path = key_path(text, &span);
    put_u32(
        &mut buffer,
        if path.is_some() {
            FORM_CRATE_AT_KEY
        } else {
            FORM_CRATE
        },
    );
    put_offset(&mut buffer, span.start)?;
    put_offset(&mut buffer, span.end)?;
    put_bytes(&mut buffer, error.message().as_bytes())?;
    if let Some(path) = path {
        put_u32(&mut buffer, length_prefix(path.len())?);
        for name in &path {
            put_bytes(&mut buffer, name.as_bytes())?;
        }
    }
    set_count(&mut buffer, 1);
    Ok(buffer)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn header_table_error_of(text: &str) -> Option<HeaderTableError> {
        let error = Document::parse(text).expect_err("the text is not TOML");
        header_table_error(text, &error)
    }

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(|name| (*name).to_owned()).collect()
    }

    #[test]
    fn a_dotted_key_into_a_table_that_a_header_made_above_it_is_accepted() {
        let text = "[a.b.c]\nz = 9\n[a]\nb.ct = 1\n";
        let document = Document::parse(text).expect("the text is TOML");
        let Some(Item::Table(table)) = document.as_table().get("a").and_then(|a| a.get("b")) else {
            panic!("a.b is not a table");
        };
        let (key, item) = table.get_key_value("ct").expect("a.b holds ct");
        assert_eq!(key.span(), Some(20..22));
        assert_eq!(item.as_integer(), Some(1));
        assert_eq!(item.span(), Some(25..26));
    }

    #[test]
    fn a_dotted_key_into_a_table_that_a_header_named_is_found() {
        let text = "[a.b]\nx = 1\n[a]\n  b . y = 2\n";
        assert_eq!(
            header_table_error_of(text),
            Some(HeaderTableError {
                start: 18,
                end: 23,
                table: names(&["a", "b"]),
                array: false,
                rest: names(&["y"]),
            })
        );
    }

    #[test]
    fn a_dotted_key_through_a_named_table_names_that_table() {
        let text = "[a.b.c.d]\nz = 9\n[a]\nb.c.d.k.t = 1\n";
        let found = header_table_error_of(text).expect("the case is found");
        assert_eq!(found.table, names(&["a", "b", "c", "d"]));
        assert_eq!(found.rest, names(&["k", "t"]));
        assert_eq!(&text[found.start..found.end], "b.c.d.k.t");
    }

    #[test]
    fn a_dotted_key_into_an_array_of_tables_is_found() {
        let text = "[[tab.arr]]\n[tab]\narr.val1=1\n";
        let found = header_table_error_of(text).expect("the case is found");
        assert_eq!(found.table, names(&["tab", "arr"]));
        assert!(found.array);
        assert_eq!(found.rest, names(&["val1"]));
    }

    #[test]
    fn quoted_parts_of_the_dotted_key_are_decoded() {
        let text = "[\"a b\".c]\nz = 9\n[\"a b\"]\n\"c\" . 'k\\x' = 1\n";
        let found = header_table_error_of(text).expect("the case is found");
        assert_eq!(found.table, names(&["a b", "c"]));
        assert_eq!(found.rest, names(&["k\\x"]));
        assert_eq!(&text[found.start..found.end], "\"c\" . 'k\\x'");
    }

    #[test]
    fn a_key_defined_twice_is_not_the_case() {
        assert_eq!(header_table_error_of("x.y = 1\nx.y = 2\n"), None);
        assert_eq!(header_table_error_of("[t]\nx = 1\nx = 2\n"), None);
        assert_eq!(header_table_error_of("a = {b.c = 1, b.c = 2}\n"), None);
        assert_eq!(header_table_error_of("[t]\nx = 1\n[t]\n"), None);
        assert_eq!(header_table_error_of("a = 1\na.b = 2\n"), None);
    }

    #[test]
    fn a_dotted_key_is_read_with_the_name_and_the_span_of_each_part() {
        assert_eq!(
            dotted_key_at("a . \"b.c\".'d' = 1", 0),
            Some(vec![
                ("a".to_owned(), 0..1),
                ("b.c".to_owned(), 4..9),
                ("d".to_owned(), 10..13),
            ])
        );
        assert_eq!(
            dotted_key_at("x = \"a\\\"b\" = 1", 4),
            Some(vec![("a\"b".to_owned(), 4..10)])
        );
        assert_eq!(dotted_key_at("= 1", 0), None);
        assert_eq!(dotted_key_at("\"a\nb\" = 1", 0), None);
        assert_eq!(dotted_key_at("'a", 0), None);
    }

    fn u32_at(buffer: &[u8], at: usize) -> u32 {
        u32::from_le_bytes(buffer[at..at + 4].try_into().unwrap())
    }

    fn error_buffer_of(text: &str) -> Vec<u8> {
        let error = Document::parse(text).expect_err("the text is not TOML");
        error_buffer(text, &error).unwrap()
    }

    #[test]
    fn an_error_at_one_key_gives_the_key_decoded() {
        let buffer = error_buffer_of("a = 1\n'a' = 2\n");
        assert_eq!(u32_at(&buffer, 16), FORM_CRATE_AT_KEY);
        assert_eq!((u32_at(&buffer, 20), u32_at(&buffer, 24)), (6, 9));
        let message_length = u32_at(&buffer, 28) as usize;
        assert_eq!(&buffer[32..32 + message_length], b"duplicate key");
        let path_at = 32 + message_length;
        assert_eq!(u32_at(&buffer, path_at), 1);
        assert_eq!(u32_at(&buffer, path_at + 4), 1);
        assert_eq!(&buffer[path_at + 8..], b"a");
    }

    fn key_path_of(text: &str) -> Option<Vec<String>> {
        let error = Document::parse(text).expect_err("the text is not TOML");
        key_path(text, &error.span().expect("the error has a span"))
    }

    #[test]
    fn the_path_of_a_key_runs_from_its_first_part_to_the_part_at_the_error() {
        assert_eq!(
            key_path_of("x.a = 1\nx . a.b = 2\n"),
            Some(names(&["x", "a"]))
        );
        assert_eq!(
            key_path_of("[x]\ny = 1\n[x.y.z]\n"),
            Some(names(&["x", "y"]))
        );
        assert_eq!(
            key_path_of("t = { a.b = 1, a.b.c = 2 }\n"),
            Some(names(&["a", "b"]))
        );
        assert_eq!(
            key_path_of("\"q\\\"r\" = 1\n'p'.\"q\\\"r\".s = 1\n\"q\\\"r\".s = 2\n"),
            Some(names(&["q\"r"]))
        );
        assert_eq!(
            key_path_of("'a.b' = 1\n'a.b'.c = 2\n"),
            Some(names(&["a.b"]))
        );
    }

    #[test]
    fn the_path_of_a_key_reads_back_over_quoted_parts() {
        assert_eq!(
            key_path_of("x.\"q\\\"r\" = 1\nx . \"q\\\"r\".s = 2\n"),
            Some(names(&["x", "q\"r"]))
        );
        assert_eq!(
            key_path_of("\"a\\\\\".b = 1\n\"a\\\\\".b.c = 2\n"),
            Some(names(&["a\\", "b"]))
        );
        assert_eq!(
            key_path_of("'a.b'.c = 1\n'a.b'.c.d = 2\n"),
            Some(names(&["a.b", "c"]))
        );
    }

    #[test]
    fn a_key_whose_dotted_key_does_not_read_gives_its_own_name() {
        assert_eq!(key_path("a.b.'c", &(2..3)), Some(names(&["b"])));
        assert_eq!(key_path("a = 1\n\"x\" = 2\n", &(6..9)), Some(names(&["x"])));
        assert_eq!(key_path("= b", &(2..3)), Some(names(&["b"])));
        assert_eq!(key_path("a = 1", &(1..2)), None);
    }

    #[test]
    fn an_error_at_text_that_is_not_one_key_gives_no_key() {
        let buffer = error_buffer_of("a = \n");
        assert_eq!(u32_at(&buffer, 16), FORM_CRATE);
        let message_length = u32_at(&buffer, 28) as usize;
        assert_eq!(buffer.len(), 32 + message_length);
    }

    #[test]
    fn one_key_decodes_a_single_key_only() {
        assert_eq!(one_key("'a b'"), Some("a b".to_owned()));
        assert_eq!(one_key("\"\\u0041\""), Some("A".to_owned()));
        assert_eq!(one_key("a.b"), None);
        assert_eq!(one_key(""), None);
    }

    #[test]
    fn the_start_of_a_line_is_its_first_byte_after_the_blanks() {
        assert_eq!(line_start("x = 1\n \tab = 2\n", 9), 8);
        assert_eq!(line_start("ab = 1\n", 1), 0);
        assert_eq!(line_start("ab = 1\n", 99), 0);
    }

    #[test]
    fn the_last_header_is_the_current_table() {
        let document = Document::parse("[a]\n[b.c]\n[[d]]\n[a.e]\n").unwrap();
        let (_, names_of_current) = current_table(document.as_table());
        assert_eq!(names_of_current, names(&["a", "e"]));
        let document = Document::parse("x = 1\n").unwrap();
        let (_, names_of_current) = current_table(document.as_table());
        assert!(names_of_current.is_empty());
    }
}
