// UTF-8 helpers with the semantics of Rust's `str::from_utf8`,
// `char::encode_utf8` and `core::str::Utf8Error`, which regex-syntax and the
// tree-sitter generator rely on.

///|
/// Encode `s` as UTF-8.
pub fn utf8_encode(s : String) -> Array[Byte] {
  let out = []
  for c in s {
    encode_utf8_into(c.to_int(), out)
  }
  out
}

///|
/// Append the UTF-8 encoding of code point `cp` to `out`.
pub fn encode_utf8_into(cp : Int32, out : Array[Byte]) -> Unit {
  if cp < 0x80 {
    out.push(cp.to_byte())
  } else if cp < 0x800 {
    out.push((0xC0 | (cp >> 6)).to_byte())
    out.push((0x80 | (cp & 0x3F)).to_byte())
  } else if cp < 0x10000 {
    out.push((0xE0 | (cp >> 12)).to_byte())
    out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
    out.push((0x80 | (cp & 0x3F)).to_byte())
  } else {
    out.push((0xF0 | (cp >> 18)).to_byte())
    out.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
    out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
    out.push((0x80 | (cp & 0x3F)).to_byte())
  }
}

///|
/// Rust `char::len_utf8` for a code point.
pub fn len_utf8(cp : Int32) -> Int32 {
  if cp < 0x80 {
    1
  } else if cp < 0x800 {
    2
  } else if cp < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// Rust `core::str::Utf8Error`.
pub(all) suberror Utf8Error {
  Utf8Error(valid_up_to~ : Int32, error_len~ : Int32?)
} derive(Eq, Debug)

///|
/// Rust's `Display` for `Utf8Error`.
pub impl Show for Utf8Error with fn output(self, f) {
  let Utf8Error(valid_up_to~, error_len~) = self
  match error_len {
    Some(error_len) =>
      f.write_string(
        "invalid utf-8 sequence of \{error_len} bytes from index \{valid_up_to}",
      )
    None =>
      f.write_string("incomplete utf-8 byte sequence from index \{valid_up_to}")
  }
}

///|
/// Rust's `utf8_char_width`.
fn utf8_char_width(b : Int32) -> Int32 {
  if b < 0x80 {
    1
  } else if b >= 0xC2 && b <= 0xDF {
    2
  } else if b >= 0xE0 && b <= 0xEF {
    3
  } else if b >= 0xF0 && b <= 0xF4 {
    4
  } else {
    0
  }
}

///|
/// Rust `core::str::from_utf8`: the decoded code points, or the error
/// `run_utf8_validation` reports.
pub fn from_utf8(v : BytesView) -> Array[Char] raise Utf8Error {
  let len = v.length()
  let mut index = 0
  let chars = []
  let cont = (b : Int32) => b >= 0x80 && b <= 0xBF
  while index < len {
    let old_offset = index
    let first = v[index].to_int()
    if first < 128 {
      chars.push(first.unsafe_to_char())
      index += 1
      continue
    }
    let next = () => {
      index += 1
      if index >= len {
        raise Utf8Error(valid_up_to=old_offset, error_len=None)
      }
      v[index].to_int()
    }
    let w = utf8_char_width(first)
    match w {
      2 => {
        let b1 = next()
        if !cont(b1) {
          raise Utf8Error(valid_up_to=old_offset, error_len=Some(1))
        }
        chars.push((((first & 0x1F) << 6) | (b1 & 0x3F)).unsafe_to_char())
      }
      3 => {
        let b1 = next()
        let ok = match (first, b1) {
          (0xE0, 0xA0..<=0xBF)
          | (0xE1..<=0xEC, 0x80..<=0xBF)
          | (0xED, 0x80..<=0x9F)
          | (0xEE..<=0xEF, 0x80..<=0xBF) => true
          _ => false
        }
        if !ok {
          raise Utf8Error(valid_up_to=old_offset, error_len=Some(1))
        }
        let b2 = next()
        if !cont(b2) {
          raise Utf8Error(valid_up_to=old_offset, error_len=Some(2))
        }
        chars.push(
          (((first & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)).unsafe_to_char(),
        )
      }
      4 => {
        let b1 = next()
        let ok = match (first, b1) {
          (0xF0, 0x90..<=0xBF)
          | (0xF1..<=0xF3, 0x80..<=0xBF)
          | (0xF4, 0x80..<=0x8F) => true
          _ => false
        }
        if !ok {
          raise Utf8Error(valid_up_to=old_offset, error_len=Some(1))
        }
        let b2 = next()
        if !cont(b2) {
          raise Utf8Error(valid_up_to=old_offset, error_len=Some(2))
        }
        let b3 = next()
        if !cont(b3) {
          raise Utf8Error(valid_up_to=old_offset, error_len=Some(3))
        }
        chars.push(
          (((first & 0x07) << 18) |
          ((b1 & 0x3F) << 12) |
          ((b2 & 0x3F) << 6) |
          (b3 & 0x3F)).unsafe_to_char(),
        )
      }
      _ => raise Utf8Error(valid_up_to=old_offset, error_len=Some(1))
    }
    index += 1
  }
  chars
}
