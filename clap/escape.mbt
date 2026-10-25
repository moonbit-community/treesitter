// Port of clap_builder 4.6.7 `util/escape.rs`, with Rust's `Debug for str`
// (core `fmt/mod.rs` and `char::escape_debug_ext`) that it formats with.

///|
/// `Escape::needs_escaping`: the value is empty or contains a character with
/// the White_Space property (`char::is_whitespace`, which core's
/// `Char::is_whitespace` implements identically).
fn needs_escaping(s : String) -> Bool {
  s.is_empty() || s.iter().any(c => c.is_whitespace())
}

///|
/// `Display for Escape` / `Escape::to_cow`: values that need escaping are
/// printed with `Debug` quoting.
fn escape(s : String) -> String {
  if needs_escaping(s) {
    debug_str(s)
  } else {
    s
  }
}

///|
/// Rust's `<str as Debug>::fmt`: every character goes through
/// `char::escape_debug_ext` with `escape_grapheme_extended: true`,
/// `escape_single_quote: false` and `escape_double_quote: true`.
fn debug_str(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '\u{0}' => sb.write_string("\\0")
      '\t' => sb.write_string("\\t")
      '\r' => sb.write_string("\\r")
      '\n' => sb.write_string("\\n")
      '\\' => sb.write_string("\\\\")
      '"' => sb.write_string("\\\"")
      _ =>
        if is_debug_unicode_escaped(c) {
          // `EscapeDebug::unicode`: `\u{` + the lowercase hexadecimal code
          // point without leading zeros + `}`.
          sb.write_string("\\u{")
          sb.write_string(c.to_int().to_string(radix=16))
          sb.write_char('}')
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_char('"')
  sb.to_string()
}
