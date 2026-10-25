// Port of the character predicates of regex-syntax 0.8.11 src/lib.rs that
// the parser uses, plus the Rust `char` methods it relies on
// (`is_whitespace`, `is_alphabetic`, `is_alphanumeric`). The latter come
// from the Rust standard library of the pinned toolchain (1.97.1, Unicode
// 17.0.0, `rust_char_tables.mbt`), not from the crate's Unicode 16.0.0 tables.

///|
/// Returns true if the given character has significance in a regex.
///
/// Generally speaking, these are the only characters which _must_ be
/// escaped in order to match their literal meaning.
pub fn is_meta_character(c : Char) -> Bool {
  match c {
    '\\'
    | '.'
    | '+'
    | '*'
    | '?'
    | '('
    | ')'
    | '|'
    | '['
    | ']'
    | '{'
    | '}'
    | '^'
    | '$'
    | '#'
    | '&'
    | '-'
    | '~' => true
    _ => false
  }
}

///|
/// Returns true if the given character can be escaped in a regex.
///
/// This returns true in all cases that `is_meta_character` returns true, but
/// also returns true in some cases where `is_meta_character` returns false.
/// For example, `%` is not a meta character, but it is escapable. That is,
/// `%` and `\%` both match a literal `%` in all contexts.
pub fn is_escapeable_character(c : Char) -> Bool {
  // Certainly escapable if it's a meta character.
  if is_meta_character(c) {
    return true
  }
  // Any character that isn't ASCII is definitely not escapable. There's
  // no real need to allow things like \☃ right?
  if c.to_int() > 0x7F {
    return false
  }
  // Otherwise, we basically say that everything is escapable unless it's a
  // letter or digit. Things like \3 are either octal (when enabled) or an
  // error, and we should keep it that way. Otherwise, letters are reserved
  // for adding new syntax in a backwards compatible way.
  match c {
    '0'..<='9' | 'A'..<='Z' | 'a'..<='z' => false
    // While not currently supported, we keep these as not escapable to
    // give us some flexibility with respect to supporting the \< and
    // \> word boundary assertions in the future. By rejecting them as
    // escapable, \< and \> will result in a parse error. Thus, we can
    // turn them into something else in the future without it being a
    // backwards incompatible change.
    //
    // OK, now we support \< and \>, and we need to retain them as *not*
    // escapable here since the escape sequence is significant.
    '<' | '>' => false
    _ => true
  }
}

///|
/// Returns true if and only if the given character is an ASCII word
/// character.
pub fn is_word_byte(c : Byte) -> Bool {
  match c {
    b'_' | b'0'..<=b'9' | b'a'..<=b'z' | b'A'..<=b'Z' => true
    _ => false
  }
}

///|
/// Whether `c` is in one of the sorted, disjoint inclusive `ranges`.
fn ranges_contain(ranges : FixedArray[(Int, Int)], c : Char) -> Bool {
  let cp = c.to_int()
  let mut lo = 0
  let mut hi = ranges.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let (start, end) = ranges[mid]
    if cp < start {
      hi = mid
    } else if cp > end {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Rust `char::is_whitespace`.
fn is_whitespace(c : Char) -> Bool {
  ranges_contain(rust_whitespace_ranges, c)
}

///|
/// Rust `char::is_alphabetic`.
fn is_alphabetic(c : Char) -> Bool {
  ranges_contain(rust_alphabetic_ranges, c)
}

///|
/// Rust `char::is_alphanumeric`: `is_alphabetic` or `is_numeric`.
fn is_alphanumeric(c : Char) -> Bool {
  ranges_contain(rust_alphabetic_ranges, c) ||
  ranges_contain(rust_numeric_ranges, c)
}

///|
/// The number of bytes `c` needs in UTF-8 (Rust `char::len_utf8`).
pub fn len_utf8(c : Char) -> Int32 {
  let cp = c.to_int()
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
