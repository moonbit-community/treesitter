///|
fn ascii_whitespace(byte : Byte) -> Bool {
  byte is (b' ' | b'\t' | b'\n' | b'\r' | b'\x0c')
}

///|
// Return the valid prefix and the malformed subsequence's length. None means
// an incomplete scalar at the end, matching Rust's UTF-8 validation errors.
fn utf8_prefix(bytes : Bytes, start : Int32, end : Int32) -> (Int32, Int32?) {
  let mut offset = start
  while offset < end {
    let first = bytes[offset].to_int()
    let width = if first < 0x80 {
      1
    } else if first >= 0xc2 && first <= 0xdf {
      2
    } else if first >= 0xe0 && first <= 0xef {
      3
    } else if first >= 0xf0 && first <= 0xf4 {
      4
    } else {
      return (offset, Some(1))
    }
    for i in 1..<width {
      if offset + i >= end {
        return (offset, None)
      }
      let byte = bytes[offset + i].to_int()
      if byte < 0x80 ||
        byte > 0xbf ||
        (
          i == 1 &&
          (
            (first == 0xe0 && byte < 0xa0) ||
            (first == 0xed && byte > 0x9f) ||
            (first == 0xf0 && byte < 0x90) ||
            (first == 0xf4 && byte > 0x8f)
          )
        ) {
        return (offset, Some(i))
      }
    }
    offset += width
  }
  (end, Some(0))
}

///|
fn line_range(
  source : Bytes,
  line_start : Int32,
  max_length : Int32,
) -> (Int32, Int32) {
  let mut start = line_start
  while start < source.length() && ascii_whitespace(source[start]) {
    start += 1
  }
  let limit = start + Int32::min(max_length, source.length() - start)
  let mut end = start
  while end < limit && source[end] != b'\n' {
    end += 1
  }
  if end == limit {
    end = utf8_prefix(source, start, limit).0
  }
  while end > start && ascii_whitespace(source[end - 1]) {
    end -= 1
  }
  (start, end)
}

///|
// Upstream's LossyUtf8 iterator replaces each malformed subsequence, but stops
// without yielding its last chunk if that chunk ends with an incomplete scalar.
fn utf16_len(source : Bytes, start : Int32, end : Int32) -> Int32 {
  let mut offset = start
  let mut length = 0
  while offset < end {
    let (valid_end, error_length) = utf8_prefix(source, offset, end)
    guard error_length is Some(error_length) else { break }
    while offset < valid_end {
      let (scalar, size) = @lex.decode(source, offset)
      length += if scalar > 0xffff { 2 } else { 1 }
      offset += size
    }
    if error_length > 0 {
      length += 1
      offset += error_length
    }
  }
  length
}
