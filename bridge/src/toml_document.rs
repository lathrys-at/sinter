// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

// @cites toml-reader

//! Read a TOML document with toml_edit, and write every table, key,
//! and value with its byte span into one result buffer.

use toml_edit::{Datetime, ImDocument, Item, Key, Offset, Table, TomlError, Value};

use crate::{length_prefix, put_bytes, put_header, put_u32, set_count, TooLong};

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

/// The `form` field of an error record: the error as toml_edit
/// reports it.
const FORM_CRATE: u32 = 0;

/// The `form` field of an error record: a dotted key that adds a key
/// to a table that a table header made.
const FORM_HEADER_TABLE: u32 = 1;

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
            t.second.into(),
            t.nanosecond,
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

/// Write one value with its span. A value that toml_edit gives no span
/// of its own, an inline table that a dotted key made, takes `fallback`,
/// the span of its key.
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
        // An inline table that a dotted key inside an inline table
        // made is no piece of the text of its own.
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

/// Write the entries of a table that a header or a dotted key made.
fn put_table(buffer: &mut Vec<u8>, table: &Table) -> Result<(), WriteError> {
    put_u32(buffer, length_prefix(table.len())?);
    for (name, _) in table.iter() {
        let (key, item) = table.get_key_value(name).ok_or(WriteError::NoSpan)?;
        put_entry(buffer, key, item)?;
    }
    Ok(())
}

/// Write one key and its item. A table that is not one piece of text,
/// and an array of tables, take the span of their key.
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
pub(crate) fn document_buffer(document: &ImDocument<&str>) -> Result<Vec<u8>, WriteError> {
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

fn is_bare_key_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-'
}

fn skip_blanks(bytes: &[u8], mut at: usize) -> usize {
    while matches!(bytes.get(at), Some(b' ' | b'\t')) {
        at += 1;
    }
    at
}

/// The decoded parts of the dotted key that starts at `start`, and the
/// offset one past its last part. None when no key starts there.
fn dotted_key_at(text: &str, start: usize) -> Option<(Vec<String>, usize)> {
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
        let mut keys = Key::parse(text.get(part_start..at)?).ok()?;
        if keys.len() != 1 {
            return None;
        }
        parts.push(keys.pop()?.get().to_owned());
        let end = at;
        at = skip_blanks(bytes, at);
        if bytes.get(at) != Some(&b'.') {
            return Some((parts, end));
        }
        at = skip_blanks(bytes, at + 1);
    }
}

/// The table that the last table header of `root` opened, and its
/// names; the top-level table when no header opened one.
fn current_table(root: &Table) -> (&Table, Vec<String>) {
    let mut best: (usize, &Table, Vec<String>) = (0, root, Vec::new());
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
                if let Some(position) = child.position() {
                    if position > best.0 {
                        best = (position, child, path.clone());
                    }
                }
                pending.push((child, path.clone()));
            }
        }
    }
    (best.1, best.2)
}

/// The error of a dotted key that adds a key to a table that a table
/// header made, when `error` is that case. toml_edit reports the case
/// as a duplicate key and names a key that is not one, so the text
/// before the key is read again to find the table.
pub(crate) fn header_table_error(text: &str, error: &TomlError) -> Option<HeaderTableError> {
    let start = error.span()?.start;
    let before = ImDocument::parse(text.get(..start)?).ok()?;
    let (parts, end) = dotted_key_at(text, start)?;
    let leaf = parts.len().checked_sub(1)?;
    let (mut table, mut names) = current_table(before.as_table());
    for (index, part) in parts[..leaf].iter().enumerate() {
        names.push(part.clone());
        let (named, array, rest) = match table.get(part)? {
            Item::Table(child) if !child.is_implicit() => (part, false, index + 1),
            Item::Table(child) if !child.is_dotted() && index + 1 == leaf => {
                (&parts[leaf], false, leaf)
            }
            Item::Table(child) => {
                table = child;
                continue;
            }
            Item::ArrayOfTables(_) if index + 1 == leaf => (&parts[leaf], true, leaf),
            Item::ArrayOfTables(array) => {
                table = array.iter().last()?;
                continue;
            }
            _ => return None,
        };
        if error.message() != format!("duplicate key `{named}`") {
            return None;
        }
        return Some(HeaderTableError {
            start,
            end,
            table: names,
            array,
            rest: parts[rest..].to_vec(),
        });
    }
    None
}

/// A buffer of kind 4 that holds the error of `text`.
pub(crate) fn error_buffer(text: &str, error: &TomlError) -> Result<Vec<u8>, WriteError> {
    let mut buffer = Vec::new();
    put_header(&mut buffer, KIND_TOML_ERROR);
    match header_table_error(text, error) {
        Some(found) => {
            put_u32(&mut buffer, FORM_HEADER_TABLE);
            put_offset(&mut buffer, found.start)?;
            put_offset(&mut buffer, found.end)?;
            put_bytes(
                &mut buffer,
                text.get(found.start..found.end).unwrap_or("").as_bytes(),
            )?;
            put_u32(&mut buffer, length_prefix(found.table.len())?);
            for name in &found.table {
                put_bytes(&mut buffer, name.as_bytes())?;
            }
            put_u32(&mut buffer, u32::from(found.array));
            put_u32(&mut buffer, length_prefix(found.rest.len())?);
            for name in &found.rest {
                put_bytes(&mut buffer, name.as_bytes())?;
            }
        }
        None => {
            put_u32(&mut buffer, FORM_CRATE);
            let span = error.span().unwrap_or(text.len()..text.len());
            put_offset(&mut buffer, span.start)?;
            put_offset(&mut buffer, span.end)?;
            put_bytes(&mut buffer, error.message().as_bytes())?;
        }
    }
    set_count(&mut buffer, 1);
    Ok(buffer)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn header_table_error_of(text: &str) -> Option<HeaderTableError> {
        let error = ImDocument::parse(text).expect_err("the text is not TOML");
        header_table_error(text, &error)
    }

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(|name| (*name).to_owned()).collect()
    }

    #[test]
    fn a_dotted_key_into_a_table_that_a_header_made_above_it_is_found() {
        let text = "[a.b.c]\nz = 9\n[a]\nb.ct = 1\n";
        assert_eq!(
            header_table_error_of(text),
            Some(HeaderTableError {
                start: 18,
                end: 22,
                table: names(&["a", "b"]),
                array: false,
                rest: names(&["ct"]),
            })
        );
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
    fn a_dotted_key_is_read_with_its_parts_and_its_end() {
        assert_eq!(
            dotted_key_at("a . \"b.c\".'d' = 1", 0),
            Some((names(&["a", "b.c", "d"]), 13))
        );
        assert_eq!(
            dotted_key_at("\"a\\\"b\" = 1", 0),
            Some((names(&["a\"b"]), 6))
        );
        assert_eq!(dotted_key_at("= 1", 0), None);
        assert_eq!(dotted_key_at("\"a\nb\" = 1", 0), None);
        assert_eq!(dotted_key_at("'a", 0), None);
    }

    #[test]
    fn the_last_header_is_the_current_table() {
        let document = ImDocument::parse("[a]\n[b.c]\n[[d]]\n[a.e]\n").unwrap();
        let (_, names_of_current) = current_table(document.as_table());
        assert_eq!(names_of_current, names(&["a", "e"]));
        let document = ImDocument::parse("x = 1\n").unwrap();
        let (_, names_of_current) = current_table(document.as_table());
        assert!(names_of_current.is_empty());
    }
}
