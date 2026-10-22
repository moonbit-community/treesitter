///|
fn Reader::enter(self : Reader) -> Unit raise RegexError {
  self.depth += 1
  if self.depth > 128 {
    raise InvalidRegex(self.pos, "regex nesting exceeds 128")
  }
}

///|
fn Reader::check_ascii(
  self : Reader,
  chars : CharSet,
) -> CharSet raise RegexError {
  if !self.unicode && chars.ranges.any(r => r.1 > 127) {
    raise InvalidRegex(self.pos, "non-ASCII byte classes are not supported")
  }
  chars
}

///|
fn Reader::group(self : Reader) -> Expr raise RegexError {
  self.enter()
  let saved = (self.insensitive, self.dotall, self.unicode)
  if self.peek() == Some('?') {
    self.pos += 1
    let mut enabled = true
    let mut seen = ""
    let mut flags = 0
    while self.peek() is Some(c) && c != ':' && c != ')' {
      self.pos += 1
      if seen.contains(c.to_string()) {
        raise InvalidRegex(self.pos - 1, "duplicate inline flag")
      }
      seen += c.to_string()
      if c == '-' {
        enabled = false
        flags = 0
      } else {
        flags += 1
        match c {
          'i' => self.insensitive = enabled
          's' => self.dotall = enabled
          'u' => self.unicode = enabled
          _ =>
            raise InvalidRegex(
              self.pos - 1,
              "unsupported inline flag or lookaround",
            )
        }
      }
    }
    if !enabled && flags == 0 {
      raise InvalidRegex(self.pos, "dangling flag negation")
    }
    if self.peek() == Some(')') {
      if seen.is_empty() {
        raise InvalidRegex(self.pos, "empty flag group")
      }
      self.pos += 1
      self.depth -= 1
      return Empty
    }
    if self.take() != ':' {
      raise InvalidRegex(self.pos, "expected ':' after flags")
    }
  }
  let expr = self.alternative()
  if self.take() != ')' {
    raise InvalidRegex(self.pos, "expected ')' ")
  }
  self.insensitive = saved.0
  self.dotall = saved.1
  self.unicode = saved.2
  self.depth -= 1
  expr
}
