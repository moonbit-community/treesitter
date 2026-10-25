// Port of the error `Formatter` and `Spans` of regex-syntax 0.8.11
// src/error.rs: the `Display` text of a `regex_syntax::Error`, which
// `regex::Error::Syntax` carries.

///|
/// `str::lines`: split on `\n`, dropping a trailing `\r` from each line and
/// the empty string after a final `\n`.
fn str_lines(s : String) -> Array[String] {
  let lines = []
  if s.is_empty() {
    return lines
  }
  let parts = s.split("\n").map(p => p.to_owned()).to_array()
  if s.has_suffix("\n") {
    ignore(parts.pop())
  }
  for part in parts {
    lines.push(
      if part.has_suffix("\r") {
        part[:part.length() - 1].to_owned()
      } else {
        part
      },
    )
  }
  lines
}

///|
fn repeat_char(c : Char, count : Int32) -> String {
  let sb = StringBuilder()
  for _ in 0..<count {
    sb.write_char(c)
  }
  sb.to_string()
}

///|
priv struct Spans {
  pattern : String
  line_number_width : Int32
  by_line : Array[Array[@ast.Span]]
  multi_line : Array[@ast.Span]
}

///|
fn span_compare(a : @ast.Span, b : @ast.Span) -> Int32 {
  let c = a.start.compare(b.start)
  if c != 0 {
    c
  } else {
    a.end.compare(b.end)
  }
}

///|
fn Spans::new(
  pattern : String,
  span : @ast.Span,
  aux_span : @ast.Span?,
) -> Spans {
  let mut line_count = str_lines(pattern).length()
  // If the pattern ends with a `\n` literal, then our line count is
  // off by one, since a span can occur immediately after the last `\n`,
  // which is consider to be an additional line.
  if pattern.has_suffix("\n") {
    line_count += 1
  }
  let line_number_width = if line_count <= 1 {
    0
  } else {
    line_count.to_string().length()
  }
  let spans : Spans = {
    pattern,
    line_number_width,
    by_line: Array::makei(line_count, _ => []),
    multi_line: [],
  }
  spans.add(span)
  if aux_span is Some(span) {
    spans.add(span)
  }
  spans
}

///|
fn Spans::add(self : Spans, span : @ast.Span) -> Unit {
  if span.is_one_line() {
    let i = span.start.line - 1 // because lines are 1-indexed
    self.by_line[i].push(span)
    self.by_line[i].sort_by(span_compare)
  } else {
    self.multi_line.push(span)
    self.multi_line.sort_by(span_compare)
  }
}

///|
fn Spans::notate(self : Spans) -> String {
  let notated = StringBuilder()
  for i, line in str_lines(self.pattern) {
    if self.line_number_width > 0 {
      notated.write_string(self.left_pad_line_number(i + 1))
      notated.write_string(": ")
    } else {
      notated.write_string("    ")
    }
    notated.write_string(line)
    notated.write_char('\n')
    if self.notate_line(i) is Some(notes) {
      notated.write_string(notes)
      notated.write_char('\n')
    }
  }
  notated.to_string()
}

///|
fn Spans::notate_line(self : Spans, i : Int32) -> String? {
  let spans = self.by_line[i]
  if spans.is_empty() {
    return None
  }
  let notes = StringBuilder()
  notes.write_string(repeat_char(' ', self.line_number_padding()))
  let mut pos = 0
  for span in spans {
    while pos < span.start.column - 1 {
      notes.write_char(' ')
      pos += 1
    }
    let note_len = if span.end.column > span.start.column {
      span.end.column - span.start.column
    } else {
      0
    }
    for _ in 0..<(if note_len > 1 { note_len } else { 1 }) {
      notes.write_char('^')
      pos += 1
    }
  }
  Some(notes.to_string())
}

///|
fn Spans::left_pad_line_number(self : Spans, n : Int32) -> String {
  let n = n.to_string()
  repeat_char(' ', self.line_number_width - n.length()) + n
}

///|
fn Spans::line_number_padding(self : Spans) -> Int32 {
  if self.line_number_width == 0 {
    4
  } else {
    2 + self.line_number_width
  }
}

///|
/// `Formatter`'s `Display`.
fn format_error(
  pattern : String,
  err : String,
  span : @ast.Span,
  aux_span : @ast.Span?,
) -> String {
  let f = StringBuilder()
  let spans = Spans::new(pattern, span, aux_span)
  if pattern.contains("\n") {
    let divider = repeat_char('~', 79)
    f.write_string("regex parse error:\n")
    f.write_string("\{divider}\n")
    f.write_string(spans.notate())
    f.write_string("\{divider}\n")
    // If we have error spans that cover multiple lines, then we just
    // note the line numbers.
    if !spans.multi_line.is_empty() {
      let notes = spans.multi_line.map(span => {
        "on line \{span.start.line} (column \{span.start.column}) through line \{span.end.line} (column \{span.end.column - 1})"
      })
      f.write_string("\{notes.join("\n")}\n")
    }
    f.write_string("error: \{err}")
  } else {
    f.write_string("regex parse error:\n")
    f.write_string(spans.notate())
    f.write_string("error: \{err}")
  }
  f.to_string()
}

///|
/// The `Display` text of a `regex_syntax::Error` wrapping an AST error.
fn format_ast_error(err : @ast.AstError) -> String {
  format_error(
    err.pattern(),
    err.kind().to_string(),
    err.span(),
    err.auxiliary_span(),
  )
}

///|
/// The `Display` text of a `regex_syntax::Error` wrapping an HIR error.
fn format_hir_error(err : @hir.HirError) -> String {
  format_error(err.pattern(), err.kind().to_string(), err.span(), None)
}
