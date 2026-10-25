// `str::from_utf8`, used by `read_to_string` (fs.mbt) and the serde_json
// reader.

///|
/// `str::from_utf8`: `None` unless `bytes` is well-formed UTF-8 (no
/// overlong forms, surrogates or code points above U+10FFFF).
pub fn from_utf8(bytes : BytesView) -> String? {
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b0 = bytes[i].to_int()
    let (len, min) = if b0 < 0x80 {
      (1, 0)
    } else if b0 >= 0xC2 && b0 <= 0xDF {
      (2, 0x80)
    } else if b0 >= 0xE0 && b0 <= 0xEF {
      (3, 0x800)
    } else if b0 >= 0xF0 && b0 <= 0xF4 {
      (4, 0x10000)
    } else {
      return None
    }
    if i + len > n {
      return None
    }
    let mut cp = if len == 1 { b0 } else { b0 & (0xFF >> (len + 1)) }
    for k in 1..<len {
      let b = bytes[i + k].to_int()
      if (b & 0xC0) != 0x80 {
        return None
      }
      cp = (cp << 6) | (b & 0x3F)
    }
    if cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
      return None
    }
    i += len
  }
  Some(@utf8.decode_lossy(bytes))
}

///|
/// The `Display` of the `Utf8Error` of `str::from_utf8(bytes)` (also that
/// of `String::from_utf8`'s `FromUtf8Error`), or `None` when `bytes` is
/// well-formed UTF-8. Port of `run_utf8_validation` (core/src/str/
/// validations.rs): `valid_up_to` is the start of the first invalid
/// sequence, and `error_len` the number of bytes found invalid there (`None`
/// when the input ends inside a sequence that was valid so far).
pub fn utf8_error(bytes : BytesView) -> String? {
  let len = bytes.length()
  let mut index = 0
  while index < len {
    let old_offset = index
    let first = bytes[index].to_int()
    if first >= 128 {
      let width = if first >= 0xC2 && first <= 0xDF {
        2
      } else if first >= 0xE0 && first <= 0xEF {
        3
      } else if first >= 0xF0 && first <= 0xF4 {
        4
      } else {
        0
      }
      let incomplete = "incomplete utf-8 byte sequence from index \{old_offset}"
      let invalid = (n : Int32) => {
        "invalid utf-8 sequence of \{n} bytes from index \{old_offset}"
      }
      // `next!()`: the next byte, or the end of the input.
      let next = () => {
        index += 1
        if index >= len {
          None
        } else {
          Some(bytes[index].to_int())
        }
      }
      let is_continuation = (b : Int32) => (b & 0xC0) == 0x80
      match width {
        2 => {
          guard next() is Some(b) else { return Some(incomplete) }
          if !is_continuation(b) {
            return Some(invalid(1))
          }
        }
        3 => {
          guard next() is Some(b) else { return Some(incomplete) }
          let ok = match (first, b) {
            (0xE0, 0xA0..<=0xBF)
            | (0xE1..<=0xEC, 0x80..<=0xBF)
            | (0xED, 0x80..<=0x9F)
            | (0xEE..<=0xEF, 0x80..<=0xBF) => true
            _ => false
          }
          if !ok {
            return Some(invalid(1))
          }
          guard next() is Some(b) else { return Some(incomplete) }
          if !is_continuation(b) {
            return Some(invalid(2))
          }
        }
        4 => {
          guard next() is Some(b) else { return Some(incomplete) }
          let ok = match (first, b) {
            (0xF0, 0x90..<=0xBF)
            | (0xF1..<=0xF3, 0x80..<=0xBF)
            | (0xF4, 0x80..<=0x8F) => true
            _ => false
          }
          if !ok {
            return Some(invalid(1))
          }
          guard next() is Some(b) else { return Some(incomplete) }
          if !is_continuation(b) {
            return Some(invalid(2))
          }
          guard next() is Some(b) else { return Some(incomplete) }
          if !is_continuation(b) {
            return Some(invalid(3))
          }
        }
        _ => return Some(invalid(1))
      }
    }
    index += 1
  }
  None
}
