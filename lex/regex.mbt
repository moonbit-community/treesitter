///|
pub(all) enum Expr {
  Empty
  Chars(CharSet)
  Concat(Array[Expr])
  Alt(Array[Expr])
  Many(Expr)
} derive(Debug, Eq)

///|
pub extend Expr with Eq::{equal, not_equal}

///|
pub extend Expr with @debug.Debug::{to_repr}

///|
pub suberror RegexError {
  InvalidRegex(Int32, String)
} derive(Debug)

///|
pub extend RegexError with @debug.Debug::{to_repr}

///|
priv struct Reader {
  chars : Array[Char]
  mut pos : Int32
  mut insensitive : Bool
  mut dotall : Bool
  mut unicode : Bool
  mut extended : Bool
  mut crlf : Bool
  mut depth : Int32
  capture_names : Map[String, Bool]
}

///|
fn Reader::peek(self : Reader) -> Char? {
  if self.extended {
    for ;; {
      while self.chars.get(self.pos)
            is Some(' ' | '\t' | '\r' | '\n' | '\u{000b}' | '\u{000c}') {
        self.pos += 1
      }
      if self.chars.get(self.pos) != Some('#') {
        break
      }
      while self.chars.get(self.pos) is Some(c) && c != '\n' {
        self.pos += 1
      }
    }
  }
  self.chars.get(self.pos)
}

///|
fn Reader::take(self : Reader) -> Char raise RegexError {
  match self.chars.get(self.pos) {
    None => raise InvalidRegex(self.pos, "unexpected end of pattern")
    Some(c) => {
      self.pos += 1
      c
    }
  }
}

///|
pub fn literal(value : String) -> Expr {
  Concat(
    value
    .iter()
    .map(c => Chars(CharSet::new([(c.to_int(), c.to_int())])))
    .to_array(),
  )
}

///|
/// Parse the regular subset accepted by the lexical generator. Unsupported
/// assertions fail explicitly.
pub fn parse(pattern : String, flags~ : String = "") -> Expr raise RegexError {
  for flag in flags {
    if !(flag is ('i' | 's' | 'u' | 'm' | 'x' | 'R' | 'U')) {
      raise InvalidRegex(0, "unsupported regex flag '\{flag}'")
    }
  }
  let reader : Reader = {
    chars: pattern.iter().to_array(),
    pos: 0,
    insensitive: flags.contains("i"),
    dotall: flags.contains("s"),
    unicode: true,
    extended: flags.contains("x"),
    crlf: flags.contains("R"),
    depth: 0,
    capture_names: Map([]),
  }
  let expr = reader.alternative()
  if reader.peek() != None {
    raise InvalidRegex(reader.pos, "unexpected closing parenthesis")
  }
  expr
}

///|
fn Reader::alternative(self : Reader) -> Expr raise RegexError {
  let choices = [self.sequence()]
  while self.peek() == Some('|') {
    self.pos += 1
    choices.push(self.sequence())
  }
  if choices.length() == 1 {
    choices[0]
  } else {
    Alt(choices)
  }
}

///|
fn Reader::sequence(self : Reader) -> Expr raise RegexError {
  let items = []
  while self.peek() is Some(c) && c != ')' && c != '|' {
    let expr = self.atom()
    let repeated = match self.peek() {
      Some('*') => {
        self.pos += 1
        Many(expr)
      }
      Some('+') => {
        self.pos += 1
        Concat([expr, Many(expr)])
      }
      Some('?') => {
        self.pos += 1
        Alt([expr, Empty])
      }
      Some('{') => {
        self.pos += 1
        let min = self.number()
        let max = if self.peek() == Some(',') {
          self.pos += 1
          if self.peek() == Some('}') {
            None
          } else {
            Some(self.number())
          }
        } else {
          Some(min)
        }
        if self.take() != '}' {
          raise InvalidRegex(self.pos, "expected '}'")
        }
        if max is Some(n) && n < min {
          raise InvalidRegex(self.pos, "reversed repetition bounds")
        }
        let parts = Array::make(min, expr)
        match max {
          None => parts.push(Many(expr))
          Some(n) =>
            for _ in min..<n {
              parts.push(Alt([expr, Empty]))
            }
        }
        Concat(parts)
      }
      _ => expr
    }
    if self.peek() == Some('?') {
      // The lexical DFA always selects the longest match, as upstream does.
      self.pos += 1
    }
    items.push(repeated)
  }
  if items.is_empty() {
    Empty
  } else {
    Concat(items)
  }
}

///|
fn Reader::number(self : Reader) -> Int32 raise RegexError {
  let start = self.pos
  let mut n = 0
  while self.peek() is Some('0'..<='9' as c) {
    self.pos += 1
    n = n * 10 + c.to_int() - 48
    if n > 1000 {
      raise InvalidRegex(start, "repetition bound exceeds 1000")
    }
  }
  if self.pos == start {
    raise InvalidRegex(start, "expected repetition count")
  }
  n
}

///|
fn Reader::atom(self : Reader) -> Expr raise RegexError {
  match self.take() {
    '(' => self.group()
    '[' => Chars(self.character_class())
    '.' => {
      if !self.unicode {
        raise InvalidRegex(self.pos, "non-ASCII byte classes are not supported")
      }
      Chars(
        if self.dotall {
          CharSet::new([(0, 0x10ffff)])
        } else {
          CharSet::new(
            if self.crlf {
              [(10, 10), (13, 13)]
            } else {
              [(10, 10)]
            },
          ).complement()
        },
      )
    }
    '\\' => Chars(self.check_ascii(self.fold(self.escape())))
    '^' | '$' =>
      raise InvalidRegex(
        self.pos - 1,
        "anchors are not supported in lexical rules",
      )
    '*' | '+' | '?' | '{' | '}' | ']' =>
      raise InvalidRegex(self.pos - 1, "unexpected regex metacharacter")
    c => Chars(self.fold(CharSet::new([(c.to_int(), c.to_int())])))
  }
}

///|
fn Reader::fold(self : Reader, chars : CharSet) -> CharSet {
  if self.insensitive && !self.unicode {
    let ranges = chars.ranges.copy()
    for code in 65..<91 {
      if chars.contains(code) {
        ranges.push((code + 32, code + 32))
      }
      if chars.contains(code + 32) {
        ranges.push((code, code))
      }
    }
    CharSet::new(ranges)
  } else if self.insensitive {
    chars.case_fold()
  } else {
    chars
  }
}

///|
fn Reader::hex(self : Reader, count : Int32) -> Int32 raise RegexError {
  let mut n = 0
  for _ in 0..<count {
    let c = self.take()
    let digit = match c {
      '0'..<='9' => c.to_int() - 48
      'a'..<='f' => c.to_int() - 87
      'A'..<='F' => c.to_int() - 55
      _ => raise InvalidRegex(self.pos - 1, "expected hex digit")
    }
    n = n * 16 + digit
  }
  n
}

///|
fn Reader::escape(self : Reader) -> CharSet raise RegexError {
  let c = self.take()
  let digits = if self.unicode {
    unicode_digits()
  } else {
    CharSet::new([(48, 57)])
  }
  let word = if self.unicode {
    unicode_word()
  } else {
    CharSet::new([(48, 57), (65, 90), (95, 95), (97, 122)])
  }
  let whitespace = if self.unicode {
    unicode_space()
  } else {
    CharSet::new([(9, 13), (32, 32)])
  }
  let codepoint = match c {
    'd' => return digits
    'D' => return digits.complement()
    'w' => return word
    'W' => return word.complement()
    's' => return whitespace
    'S' => return whitespace.complement()
    'n' => 10
    'r' => 13
    't' => 9
    'f' => 12
    'v' => 11
    '0' => 0
    'x' => self.hex(2)
    'u' =>
      if self.peek() == Some('{') {
        self.pos += 1
        let mut n = 0
        let start = self.pos
        while self.peek() != Some('}') {
          if self.pos - start >= 6 {
            raise InvalidRegex(start, "Unicode escape is too long")
          }
          n = n * 16 + self.hex(1)
        }
        if self.pos == start {
          raise InvalidRegex(start, "empty Unicode escape")
        }
        self.pos += 1
        n
      } else {
        self.hex(4)
      }
    'p' | 'P' => {
      if !self.unicode {
        raise InvalidRegex(self.pos, "Unicode properties require Unicode mode")
      }
      let name = StringBuilder()
      if self.peek() == Some('{') {
        self.pos += 1
        while self.peek() != Some('}') {
          name.write_char(self.take())
        }
        self.pos += 1
      } else {
        name.write_char(self.take())
      }
      let chars = match unicode_property(name.to_string()) {
        Some(chars) => self.fold(chars)
        None =>
          raise InvalidRegex(self.pos, "unknown Unicode property '\{name}'")
      }
      return if c == 'P' { chars.complement() } else { chars }
    }
    'b' | 'B' | '1'..<='9' =>
      raise InvalidRegex(
        self.pos - 1,
        "assertions and backreferences are not supported",
      )
    'a'..<='z' | 'A'..<='Z' =>
      raise InvalidRegex(self.pos - 1, "unknown character escape")
    _ => c.to_int()
  }
  if codepoint > 0x10ffff || (codepoint >= 0xd800 && codepoint <= 0xdfff) {
    raise InvalidRegex(self.pos, "escape is not a Unicode scalar")
  }
  CharSet::new([(codepoint, codepoint)])
}
