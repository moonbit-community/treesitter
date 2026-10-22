///|
fn Reader::set_operator(self : Reader) -> Char? {
  match self.peek() {
    Some('&' | '-' | '~' as c) if self.chars.get(self.pos + 1) == Some(c) =>
      Some(c)
    _ => None
  }
}

///|
fn Reader::class_item(self : Reader) -> CharSet raise RegexError {
  let c = self.take()
  if c == '[' {
    if self.peek() == Some(':') {
      self.pos += 1
      self.ascii_class()
    } else {
      self.character_class()
    }
  } else if c == '\\' {
    self.escape()
  } else {
    CharSet::new([(c.to_int(), c.to_int())])
  }
}

///|
fn Reader::class_union(self : Reader) -> CharSet raise RegexError {
  let mut chars = CharSet::new([])
  while self.peek() != Some(']') && self.set_operator() is None {
    let nested = self.peek() == Some('[')
    let first = self.class_item()
    if self.peek() == Some('-') &&
      self.chars.get(self.pos + 1) != Some(']') &&
      self.set_operator() is None {
      self.pos += 1
      let last = self.class_item()
      if nested ||
        first.ranges.length() != 1 ||
        last.ranges.length() != 1 ||
        first.ranges[0].0 != first.ranges[0].1 ||
        last.ranges[0].0 != last.ranges[0].1 {
        raise InvalidRegex(
          self.pos,
          "range endpoints must be single characters",
        )
      }
      let lo = first.ranges[0].0
      let hi = last.ranges[0].0
      if lo > hi {
        raise InvalidRegex(self.pos, "reversed character range")
      }
      chars = chars.union(self.fold(CharSet::new([(lo, hi)])))
    } else {
      // Nested sets have already been folded before their set operations.
      chars = chars.union(if nested { first } else { self.fold(first) })
    }
  }
  chars
}

///|
fn Reader::character_class(self : Reader) -> CharSet raise RegexError {
  self.enter()
  let negative = self.peek() == Some('^')
  if negative {
    self.pos += 1
  }
  let initial = if self.peek() == Some(']') {
    self.pos += 1
    self.fold(CharSet::new([(93, 93)]))
  } else {
    CharSet::new([])
  }
  let mut chars = initial.union(self.class_union())
  while self.set_operator() is Some(operator) {
    self.pos += 2
    let right = self.class_union()
    chars = match operator {
      '&' => chars.intersection(right)
      '-' => chars.difference(right)
      _ => chars.symmetric_difference(right)
    }
  }
  if self.take() != ']' {
    raise InvalidRegex(self.pos, "expected ']' ")
  }
  self.depth -= 1
  self.check_ascii(if negative { chars.complement() } else { chars })
}

///|
fn Reader::ascii_class(self : Reader) -> CharSet raise RegexError {
  let negative = self.peek() == Some('^')
  if negative {
    self.pos += 1
  }
  let name = StringBuilder()
  while self.peek() != Some(':') {
    name.write_char(self.take())
  }
  self.pos += 1
  if self.take() != ']' {
    raise InvalidRegex(self.pos, "expected ':]' after ASCII class")
  }
  let ranges = match name.to_string() {
    "alnum" => [(48, 57), (65, 90), (97, 122)]
    "alpha" => [(65, 90), (97, 122)]
    "ascii" => [(0, 127)]
    "blank" => [(9, 9), (32, 32)]
    "cntrl" => [(0, 31), (127, 127)]
    "digit" => [(48, 57)]
    "graph" => [(33, 126)]
    "lower" => [(97, 122)]
    "print" => [(32, 126)]
    "punct" => [(33, 47), (58, 64), (91, 96), (123, 126)]
    "space" => [(9, 13), (32, 32)]
    "upper" => [(65, 90)]
    "word" => [(48, 57), (65, 90), (95, 95), (97, 122)]
    "xdigit" => [(48, 57), (65, 70), (97, 102)]
    _ => raise InvalidRegex(self.pos, "unknown ASCII character class")
  }
  let chars = self.fold(CharSet::new(ranges))
  if negative {
    chars.complement()
  } else {
    chars
  }
}
