// Port of `LossyUtf8` and `format_sexp` from tree-sitter
// lib/binding_rust/lib.rs.

///|
/// An iterator over the UTF-8 decoded chunks of a byte string, yielding
/// `"\u{FFFD}"` for each invalid sequence.
pub struct LossyUtf8 {
  priv mut bytes : BytesView
  priv mut in_replacement : Bool
}

///|
/// Create a lossy UTF-8 iterator over `bytes`.
pub fn LossyUtf8::new(bytes : BytesView) -> LossyUtf8 {
  { bytes, in_replacement: false, }
}

///|
/// The next chunk: a maximal valid run of text, or a replacement character.
pub fn LossyUtf8::next(self : LossyUtf8) -> String? {
  if self.bytes.length() == 0 {
    return None
  }
  if self.in_replacement {
    self.in_replacement = false
    return Some("\u{fffd}")
  }
  try @hir.from_utf8(self.bytes) catch {
    Utf8Error(valid_up_to=error_start, error_len~) =>
      match error_len {
        Some(error_len) =>
          if error_start > 0 {
            let result = @utf8.decode_lossy(self.bytes[:error_start])
            self.bytes = self.bytes[error_start + error_len:]
            self.in_replacement = true
            Some(result)
          } else {
            self.bytes = self.bytes[error_len:]
            Some("\u{fffd}")
          }
        None => None
      }
  } noraise {
    _ => {
      let valid = @utf8.decode_lossy(self.bytes)
      self.bytes = b""[:]
      Some(valid)
    }
  }
}

///|
/// Iterate the remaining chunks.
pub fn LossyUtf8::iter(self : LossyUtf8) -> Iter[String] {
  Iter::new(() => self.next())
}

///|
/// Pretty-print an S-expression produced by [`Node::to_sexp`], one node per
/// line, indenting nested nodes by two spaces per level starting at
/// `initial_indent_level` (upstream's `{:#}` formatting of a node).
pub fn format_sexp(sexp : String, initial_indent_level : Int32) -> String {
  let chars = sexp.iter().to_array()
  let mut pos = 0
  let mut indent_level = initial_indent_level
  let formatted = StringBuilder()
  let mut has_field = false
  let mut quote = '\u{0}'
  let mut saw_paren = false
  let mut did_last = false
  let scratch = StringBuilder()
  let peek = () => if pos < chars.length() { Some(chars[pos]) } else { None }
  let fetch_next_str = () => {
    scratch.reset()
    while pos < chars.length() {
      let c = chars[pos]
      pos += 1
      if c == '\'' || c == '"' {
        quote = c
      } else if c == ' ' || (c == ')' && quote != '\u{0}') {
        if peek() is Some(next_c) && next_c == quote {
          scratch.write_char(c)
          scratch.write_char(next_c)
          pos += 1
          quote = '\u{0}'
          continue
        }
        break
      }
      if c == ')' {
        saw_paren = true
        break
      }
      scratch.write_char(c)
    }
    // at the end
    if peek() is None && scratch.is_empty() {
      if saw_paren {
        // but did we see a ) before ending?
        saw_paren = false
        return true
      }
      if !did_last {
        // but did we account for the end empty string as if we're splitting?
        did_last = true
        return true
      }
      return false
    }
    true
  }
  let indent = () => {
    for _ in 0..<indent_level {
      formatted.write_string("  ")
    }
  }
  while fetch_next_str() {
    let s = scratch.to_string()
    if s.is_empty() && indent_level > 0 {
      // ")"
      indent_level -= 1
      formatted.write_string(")")
    } else if s.has_prefix("(") {
      if has_field {
        has_field = false
      } else {
        if indent_level > 0 {
          formatted.write_string("\n")
          indent()
        }
        indent_level += 1
      }
      // "(node_name"
      formatted.write_string(s)
      // "(MISSING node_name" or "(UNEXPECTED 'x'"
      if s.has_prefix("(MISSING") || s.has_prefix("(UNEXPECTED") {
        guard fetch_next_str() else { abort("unexpected end of S-expression") }
        let next = scratch.to_string()
        if next.is_empty() {
          while indent_level > 0 {
            indent_level -= 1
            formatted.write_string(")")
          }
        } else {
          formatted.write_string(" \{next}")
        }
      }
    } else if s.has_suffix(":") {
      // "field:"
      formatted.write_string("\n")
      indent()
      formatted.write_string("\{s} ")
      has_field = true
      indent_level += 1
    }
  }
  formatted.to_string()
}
