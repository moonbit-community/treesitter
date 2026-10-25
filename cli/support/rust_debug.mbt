// Rust's `Debug` formatting of `str` and `char` (Rust 1.97.1 core
// `fmt/mod.rs` and `char/methods.rs`): `char::escape_debug_ext` with
// grapheme-extended characters escaped, as both `<str as Debug>` and
// `<char as Debug>` call it.

///|
/// `c.is_grapheme_extended() || !is_printable(c)`: the characters that
/// `escape_debug_ext` escapes as `\u{..}` (rust_debug_table.mbt).
fn debug_needs_unicode_escape(c : Char) -> Bool {
  let code = c.to_int()
  // Binary search over the (first, last) pairs.
  let n = debug_unicode_escaped.length() / 2
  for lo = 0, hi = n; lo < hi; {
    let mid = lo + (hi - lo) / 2
    if code < debug_unicode_escaped[2 * mid] {
      continue lo, mid
    } else if code > debug_unicode_escaped[2 * mid + 1] {
      continue mid + 1, hi
    } else {
      break true
    }
  } nobreak {
    false
  }
}

///|
/// `EscapeDebugExtArgs`: which quotes `escape_debug_ext` escapes.
fn write_escape_debug(
  sb : StringBuilder,
  c : Char,
  escape_single_quote~ : Bool,
  escape_double_quote~ : Bool,
) -> Unit {
  match c {
    '\u{0}' => sb.write_string("\\0")
    '\t' => sb.write_string("\\t")
    '\r' => sb.write_string("\\r")
    '\n' => sb.write_string("\\n")
    '\\' => sb.write_string("\\\\")
    '"' if escape_double_quote => sb.write_string("\\\"")
    '\'' if escape_single_quote => sb.write_string("\\'")
    _ =>
      if debug_needs_unicode_escape(c) {
        // `EscapeDebug::unicode`: `\u{` + lowercase hex without leading
        // zeros + `}`.
        sb.write_string("\\u{\{c.to_int().to_string(radix=16)}}")
      } else {
        sb.write_char(c)
      }
  }
}

///|
/// `<str as Debug>::fmt`: the string in double quotes, escaped.
pub fn rust_debug_str(s : StringView) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    write_escape_debug(
      sb,
      c,
      escape_single_quote=false,
      escape_double_quote=true,
    )
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// `<char as Debug>::fmt`: the character in single quotes, escaped.
pub fn rust_debug_char(c : Char) -> String {
  let sb = StringBuilder()
  sb.write_char('\'')
  write_escape_debug(
    sb,
    c,
    escape_single_quote=true,
    escape_double_quote=false,
  )
  sb.write_char('\'')
  sb.to_string()
}
