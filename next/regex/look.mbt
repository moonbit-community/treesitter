// Look-around assertions, as defined by regex-automata's `LookMatcher`
// (regex-automata 0.4, `util/look.rs`) with `\n` as the line terminator.

///|
fn look_matches(look : @hir.Look, hay : BytesView, at : Int32) -> Bool {
  let len = hay.length()
  match look {
    Start => at == 0
    End => at == len
    StartLF => at == 0 || hay[at - 1] == b'\n'
    EndLF => at == len || hay[at] == b'\n'
    StartCRLF =>
      at == 0 ||
      hay[at - 1] == b'\n' ||
      (hay[at - 1] == b'\r' && (at >= len || hay[at] != b'\n'))
    EndCRLF =>
      at == len ||
      hay[at] == b'\r' ||
      (hay[at] == b'\n' && (at == 0 || hay[at - 1] != b'\r'))
    WordAscii => word_byte_before(hay, at) != word_byte_after(hay, at)
    WordAsciiNegate => word_byte_before(hay, at) == word_byte_after(hay, at)
    WordUnicode => word_char_rev(hay, at) != word_char_fwd(hay, at)
    WordUnicodeNegate => {
      // Neither `\b` nor `\B` is satisfied inside invalid UTF-8.
      let before = if at > 0 {
        if !decode_last_ok(hay, at) {
          return false
        }
        word_char_rev(hay, at)
      } else {
        false
      }
      let after = if at < len {
        if decode_utf8(hay, at).0 < 0 {
          return false
        }
        word_char_fwd(hay, at)
      } else {
        false
      }
      before == after
    }
    WordStartAscii => !word_byte_before(hay, at) && word_byte_after(hay, at)
    WordEndAscii => word_byte_before(hay, at) && !word_byte_after(hay, at)
    WordStartUnicode => !word_char_rev(hay, at) && word_char_fwd(hay, at)
    WordEndUnicode => word_char_rev(hay, at) && !word_char_fwd(hay, at)
    WordStartHalfAscii => !word_byte_before(hay, at)
    WordEndHalfAscii => !word_byte_after(hay, at)
    WordStartHalfUnicode => {
      let before = if at > 0 {
        if !decode_last_ok(hay, at) {
          return false
        }
        word_char_rev(hay, at)
      } else {
        false
      }
      !before
    }
    WordEndHalfUnicode => {
      let after = if at < len {
        if decode_utf8(hay, at).0 < 0 {
          return false
        }
        word_char_fwd(hay, at)
      } else {
        false
      }
      !after
    }
  }
}

///|
fn is_word_byte(b : Byte) -> Bool {
  (b >= b'a' && b <= b'z') ||
  (b >= b'A' && b <= b'Z') ||
  (b >= b'0' && b <= b'9') ||
  b == b'_'
}

///|
fn word_byte_before(hay : BytesView, at : Int32) -> Bool {
  at > 0 && is_word_byte(hay[at - 1])
}

///|
fn word_byte_after(hay : BytesView, at : Int32) -> Bool {
  at < hay.length() && is_word_byte(hay[at])
}

///|
/// `is_word_char::fwd`: whether a well-formed encoding of a `\w` code point
/// starts at `at`.
fn word_char_fwd(hay : BytesView, at : Int32) -> Bool {
  let (cp, _) = decode_utf8(hay, at)
  cp >= 0 && @hir.is_word_character(cp)
}

///|
/// `is_word_char::rev` (regex-syntax table variant, the one compiled into
/// `regex`): whether `utf8::decode_last(&hay[..at])` yields a `\w` code
/// point.
fn word_char_rev(hay : BytesView, at : Int32) -> Bool {
  let cp = decode_last(hay, at)
  cp >= 0 && @hir.is_word_character(cp)
}

///|
/// Whether regex-automata's `utf8::decode_last(&hay[..at])` succeeds.
fn decode_last_ok(hay : BytesView, at : Int32) -> Bool {
  decode_last(hay, at) >= 0
}

///|
/// regex-automata's `utf8::decode_last(&hay[..at])`: step back over at most
/// three continuation bytes and decode the first code point from there (which
/// need not end at `at`). Returns -1 when that fails or `at` is 0.
fn decode_last(hay : BytesView, at : Int32) -> Int32 {
  if at == 0 {
    return -1
  }
  let limit = if at >= 4 { at - 4 } else { 0 }
  let mut start = at - 1
  while start > limit && !is_leading_or_invalid_byte(hay[start]) {
    start -= 1
  }
  decode_utf8(hay[0:at], start).0
}

///|
fn is_leading_or_invalid_byte(b : Byte) -> Bool {
  (b & 0b1100_0000) != 0b1000_0000
}
