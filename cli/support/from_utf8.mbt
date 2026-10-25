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
