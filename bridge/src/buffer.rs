// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Sinter Authors

//! The writer of the result buffer: a 16-byte header, then records of
//! little-endian integers and length-prefixed strings.

/// The first four bytes of every result buffer.
pub(crate) const MAGIC: u32 = u32::from_le_bytes(*b"SBR1");

/// The `kind` field of a buffer that holds a parse tree.
pub(crate) const KIND_TREE: u32 = 1;

/// The `kind` field of a buffer that holds a SHA-256 digest.
pub(crate) const KIND_DIGEST: u32 = 2;

/// The `kind` field of a buffer that holds a failure.
pub(crate) const KIND_FAILURE: u32 = 5;

/// The `kind` field of a buffer of captures with match numbers.
pub(crate) const KIND_MATCHES: u32 = 6;

/// The `kind` field of a buffer that holds the error report of a tree.
pub(crate) const KIND_ERROR_REPORT: u32 = 7;

/// The `kind` field of a buffer that holds the response of an adapter.
pub(crate) const KIND_RESPONSE: u32 = 8;

pub(crate) fn put_u32(buffer: &mut Vec<u8>, value: u32) {
    buffer.extend_from_slice(&value.to_le_bytes());
}

pub(crate) fn put_u64(buffer: &mut Vec<u8>, value: u64) {
    buffer.extend_from_slice(&value.to_le_bytes());
}

/// A length that does not fit the 32-bit prefix of a string in the
/// result buffer.
#[derive(Debug, PartialEq, Eq)]
pub(crate) struct TooLong;

/// The 32-bit length prefix for a string of `len` bytes, or `TooLong`
/// when `len` does not fit 32 bits.
pub(crate) fn length_prefix(len: usize) -> Result<u32, TooLong> {
    u32::try_from(len).map_err(|_| TooLong)
}

pub(crate) fn put_bytes(buffer: &mut Vec<u8>, value: &[u8]) -> Result<(), TooLong> {
    put_u32(buffer, length_prefix(value.len())?);
    buffer.extend_from_slice(value);
    Ok(())
}

/// Write the 16-byte header. `set_count` fills the count in later.
pub(crate) fn put_header(buffer: &mut Vec<u8>, kind: u32) {
    put_u32(buffer, MAGIC);
    put_u32(buffer, kind);
    put_u32(buffer, 0);
    put_u32(buffer, 0);
}

pub(crate) fn set_count(buffer: &mut [u8], count: u32) {
    buffer[8..12].copy_from_slice(&count.to_le_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_length_prefix_holds_32_bits_and_refuses_more() {
        assert_eq!(length_prefix(0), Ok(0));
        assert_eq!(length_prefix(u32::MAX as usize), Ok(u32::MAX));
        let mut buffer = Vec::new();
        assert_eq!(put_bytes(&mut buffer, b"abc"), Ok(()));
        assert_eq!(buffer, vec![3, 0, 0, 0, b'a', b'b', b'c']);
    }

    #[test]
    #[cfg(target_pointer_width = "64")]
    fn a_length_over_32_bits_is_refused_and_not_truncated() {
        assert_eq!(length_prefix(u32::MAX as usize + 1), Err(TooLong));
        assert_eq!(length_prefix(usize::MAX), Err(TooLong));
    }

    #[test]
    fn a_u64_is_written_little_endian() {
        let mut buffer = Vec::new();
        put_u64(&mut buffer, 0x0102_0304_0506_0708);
        assert_eq!(buffer, vec![8, 7, 6, 5, 4, 3, 2, 1]);
    }

    #[test]
    fn the_header_holds_the_magic_the_kind_and_the_count() {
        let mut buffer = Vec::new();
        put_header(&mut buffer, KIND_MATCHES);
        set_count(&mut buffer, 3);
        assert_eq!(
            buffer,
            [*b"SBR1", 6u32.to_le_bytes(), 3u32.to_le_bytes(), [0; 4]].concat()
        );
    }
}
