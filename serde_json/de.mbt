// Port of serde_json 1.0.154 src/de.rs: the `Deserializer` over a string
// (`serde_json::from_str`), without the `float_roundtrip`,
// `arbitrary_precision`, `raw_value` and `unbounded_depth` features (the
// feature set Tree-sitter's crates enable). serde's visitors are `Visitor`
// values whose missing methods behave as serde's provided ones.

///|
/// `serde_json::Deserializer<StrRead>`.
pub struct Deserializer {
  priv slice : Bytes
  priv mut index : Int32
  priv scratch : @buffer.Buffer
  priv mut remaining_depth : Int32
}

///|
/// `Deserializer::from_str`.
pub fn Deserializer::from_str(s : String) -> Deserializer {
  { slice: @utf8.encode(s), index: 0, scratch: Buffer(), remaining_depth: 128, }
}

///|
/// `serde_json::from_str`: deserialize with `f`, then check that only
/// whitespace follows.
pub fn[T] from_str(
  s : String,
  f : (Deserializer) -> T raise JsonError,
) -> T raise JsonError {
  let de = Deserializer::from_str(s)
  let value = f(de)
  de.end()
  value
}

///|
/// `Deserializer::end`.
pub fn Deserializer::end(self : Deserializer) -> Unit raise JsonError {
  if self.parse_whitespace() is Some(_) {
    raise self.peek_error(TrailingCharacters)
  }
}

///|
fn Deserializer::peek(self : Deserializer) -> Byte? {
  if self.index < self.slice.length() {
    Some(self.slice[self.index])
  } else {
    None
  }
}

///|
fn Deserializer::peek_or_null(self : Deserializer) -> Byte {
  if self.index < self.slice.length() {
    self.slice[self.index]
  } else {
    b'\x00'
  }
}

///|
fn Deserializer::eat_char(self : Deserializer) -> Unit {
  self.index += 1
}

///|
fn Deserializer::next_char(self : Deserializer) -> Byte? {
  if self.index < self.slice.length() {
    let ch = self.slice[self.index]
    self.index += 1
    Some(ch)
  } else {
    None
  }
}

///|
fn Deserializer::next_char_or_null(self : Deserializer) -> Byte {
  match self.next_char() {
    Some(ch) => ch
    None => b'\x00'
  }
}

///|
/// Error caused by a byte from `next_char()`.
pub fn Deserializer::error(self : Deserializer, code : ErrorCode) -> JsonError {
  let position = self.position()
  JsonError(code~, line=position.line, column=position.column)
}

///|
/// Error caused by a byte from `peek()`.
pub fn Deserializer::peek_error(
  self : Deserializer,
  code : ErrorCode,
) -> JsonError {
  let position = self.peek_position()
  JsonError(code~, line=position.line, column=position.column)
}

///|
/// `Deserializer::fix_position`: give `err` the current position if it has
/// none.
pub fn Deserializer::fix_position(
  self : Deserializer,
  err : JsonError,
) -> JsonError {
  err.fix_position(code => self.error(code))
}

///|
/// Returns the first non-whitespace byte without consuming it, or `None` if
/// EOF is encountered.
fn Deserializer::parse_whitespace(self : Deserializer) -> Byte? {
  let slice = self.slice
  let n = slice.length()
  while self.index < n {
    match slice[self.index] {
      b' ' | b'\n' | b'\t' | b'\r' => self.index += 1
      other => return Some(other)
    }
  }
  None
}

///|
fn Deserializer::parse_ident(
  self : Deserializer,
  ident : Bytes,
) -> Unit raise JsonError {
  for expected in ident {
    match self.next_char() {
      None => raise self.error(EofWhileParsingValue)
      Some(next) => if next != expected { raise self.error(ExpectedSomeIdent) }
    }
  }
}

///|
/// `peek_invalid_type`: an `invalid type` error for the value that starts at
/// the next byte, which is consumed (unless it is a sequence or a map).
fn Deserializer::peek_invalid_type(
  self : Deserializer,
  expected : String,
) -> JsonError {
  let err = match self.peek_or_null() {
    b'n' => {
      self.eat_char()
      self.parse_ident(b"ull") catch {
        err => return err
      }
      invalid_type(Unexpected::Unit, expected)
    }
    b't' => {
      self.eat_char()
      self.parse_ident(b"rue") catch {
        err => return err
      }
      invalid_type(Unexpected::Bool(true), expected)
    }
    b'f' => {
      self.eat_char()
      self.parse_ident(b"alse") catch {
        err => return err
      }
      invalid_type(Unexpected::Bool(false), expected)
    }
    b'-' => {
      self.eat_char()
      let n = self.parse_any_number(false) catch { err => return err }
      n.invalid_type(expected)
    }
    b'0'..<=b'9' => {
      let n = self.parse_any_number(true) catch { err => return err }
      n.invalid_type(expected)
    }
    b'"' => {
      self.eat_char()
      let s = self.parse_str() catch { err => return err }
      invalid_type(Unexpected::Str(s), expected)
    }
    b'[' => invalid_type(Unexpected::Seq, expected)
    b'{' => invalid_type(Unexpected::Map, expected)
    _ => self.peek_error(ExpectedSomeValue)
  }
  self.fix_position(err)
}

///|
/// `check_recursion!`'s entry: fails when the nesting limit is reached.
fn Deserializer::enter_nested(self : Deserializer) -> Unit raise JsonError {
  self.remaining_depth -= 1
  if self.remaining_depth == 0 {
    raise self.peek_error(RecursionLimitExceeded)
  }
}

///|
/// The common tail of serde_json's `deserialize_*` methods: an error raised
/// by `body` that has no position yet (a visitor's error) gets the current
/// position.
fn[T] Deserializer::fixing(
  self : Deserializer,
  body : () -> T raise JsonError,
) -> T raise JsonError {
  body() catch {
    err => raise self.fix_position(err)
  }
}

///|
/// The `[` arm of `deserialize_any`/`deserialize_seq`/`deserialize_struct`.
fn[T] Deserializer::visit_seq_here(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  self.enter_nested()
  self.eat_char()
  let ret = Ok(visitor.seq({ de: self, first: true, })) catch { e => Err(e) }
  self.remaining_depth += 1
  let end = Ok(self.end_seq()) catch { e => Err(e) }
  match (ret, end) {
    (Ok(ret), Ok(_)) => ret
    (Err(err), _) | (_, Err(err)) => raise err
  }
}

///|
/// The `{` arm of `deserialize_any`/`deserialize_map`/`deserialize_struct`.
fn[T] Deserializer::visit_map_here(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  self.enter_nested()
  self.eat_char()
  let ret = Ok(visitor.map({ de: self, first: true, })) catch { e => Err(e) }
  self.remaining_depth += 1
  let end = Ok(self.end_map()) catch { e => Err(e) }
  match (ret, end) {
    (Ok(ret), Ok(_)) => ret
    (Err(err), _) | (_, Err(err)) => raise err
  }
}

///|
/// `Deserializer::deserialize_any`.
pub fn[T] Deserializer::deserialize_any(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  guard self.parse_whitespace() is Some(peek) else {
    raise self.peek_error(EofWhileParsingValue)
  }
  self.fixing(() => {
    match peek {
      b'n' => {
        self.eat_char()
        self.parse_ident(b"ull")
        visitor.unit()
      }
      b't' => {
        self.eat_char()
        self.parse_ident(b"rue")
        visitor.bool(true)
      }
      b'f' => {
        self.eat_char()
        self.parse_ident(b"alse")
        visitor.bool(false)
      }
      b'-' => {
        self.eat_char()
        let n = self.parse_any_number(false)
        n.visit(visitor)
      }
      b'0'..<=b'9' => {
        let n = self.parse_any_number(true)
        n.visit(visitor)
      }
      b'"' => {
        self.eat_char()
        let s = self.parse_str()
        visitor.str(s)
      }
      b'[' => self.visit_seq_here(visitor)
      b'{' => self.visit_map_here(visitor)
      _ => raise self.peek_error(ExpectedSomeValue)
    }
  })
}

///|
/// `Deserializer::deserialize_bool`.
pub fn[T] Deserializer::deserialize_bool(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  guard self.parse_whitespace() is Some(peek) else {
    raise self.peek_error(EofWhileParsingValue)
  }
  self.fixing(() => {
    match peek {
      b't' => {
        self.eat_char()
        self.parse_ident(b"rue")
        visitor.bool(true)
      }
      b'f' => {
        self.eat_char()
        self.parse_ident(b"alse")
        visitor.bool(false)
      }
      _ => raise self.peek_invalid_type(visitor.expecting)
    }
  })
}

///|
/// `Deserializer::deserialize_number`, which every integer and float
/// `deserialize_*` method uses.
pub fn[T] Deserializer::deserialize_number(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  guard self.parse_whitespace() is Some(peek) else {
    raise self.peek_error(EofWhileParsingValue)
  }
  self.fixing(() => {
    match peek {
      b'-' => {
        self.eat_char()
        let n = self.parse_integer(false)
        n.visit(visitor)
      }
      b'0'..<=b'9' => {
        let n = self.parse_integer(true)
        n.visit(visitor)
      }
      _ => raise self.peek_invalid_type(visitor.expecting)
    }
  })
}

///|
/// `Deserializer::deserialize_str` (also `deserialize_string`,
/// `deserialize_char` and `deserialize_identifier`).
pub fn[T] Deserializer::deserialize_str(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  guard self.parse_whitespace() is Some(peek) else {
    raise self.peek_error(EofWhileParsingValue)
  }
  self.fixing(() => {
    match peek {
      b'"' => {
        self.eat_char()
        let s = self.parse_str()
        visitor.str(s)
      }
      _ => raise self.peek_invalid_type(visitor.expecting)
    }
  })
}

///|
/// `Deserializer::deserialize_option`.
pub fn[T] Deserializer::deserialize_option(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  match self.parse_whitespace() {
    Some(b'n') => {
      self.eat_char()
      self.parse_ident(b"ull")
      visitor.none()
    }
    _ => visitor.some(self)
  }
}

///|
/// `Deserializer::deserialize_unit`.
pub fn[T] Deserializer::deserialize_unit(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  guard self.parse_whitespace() is Some(peek) else {
    raise self.peek_error(EofWhileParsingValue)
  }
  self.fixing(() => {
    match peek {
      b'n' => {
        self.eat_char()
        self.parse_ident(b"ull")
        visitor.unit()
      }
      _ => raise self.peek_invalid_type(visitor.expecting)
    }
  })
}

///|
/// `Deserializer::deserialize_seq` (also `deserialize_tuple`).
pub fn[T] Deserializer::deserialize_seq(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  guard self.parse_whitespace() is Some(peek) else {
    raise self.peek_error(EofWhileParsingValue)
  }
  self.fixing(() => {
    match peek {
      b'[' => self.visit_seq_here(visitor)
      _ => raise self.peek_invalid_type(visitor.expecting)
    }
  })
}

///|
/// `Deserializer::deserialize_map`.
pub fn[T] Deserializer::deserialize_map(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  guard self.parse_whitespace() is Some(peek) else {
    raise self.peek_error(EofWhileParsingValue)
  }
  self.fixing(() => {
    match peek {
      b'{' => self.visit_map_here(visitor)
      _ => raise self.peek_invalid_type(visitor.expecting)
    }
  })
}

///|
/// `Deserializer::deserialize_struct`: a struct is read from a map or from a
/// sequence of its fields.
pub fn[T] Deserializer::deserialize_struct(
  self : Deserializer,
  visitor : Visitor[T],
) -> T raise JsonError {
  guard self.parse_whitespace() is Some(peek) else {
    raise self.peek_error(EofWhileParsingValue)
  }
  self.fixing(() => {
    match peek {
      b'[' => self.visit_seq_here(visitor)
      b'{' => self.visit_map_here(visitor)
      _ => raise self.peek_invalid_type(visitor.expecting)
    }
  })
}

///|
/// `Deserializer::deserialize_ignored_any`: skip a value without
/// materializing it (and without a nesting limit).
pub fn Deserializer::deserialize_ignored_any(
  self : Deserializer,
) -> Unit raise JsonError {
  self.ignore_value()
}

///|
fn Deserializer::parse_object_colon(
  self : Deserializer,
) -> Unit raise JsonError {
  match self.parse_whitespace() {
    Some(b':') => self.eat_char()
    Some(_) => raise self.peek_error(ExpectedColon)
    None => raise self.peek_error(EofWhileParsingObject)
  }
}

///|
fn Deserializer::end_seq(self : Deserializer) -> Unit raise JsonError {
  match self.parse_whitespace() {
    Some(b']') => self.eat_char()
    Some(b',') => {
      self.eat_char()
      match self.parse_whitespace() {
        Some(b']') => raise self.peek_error(TrailingComma)
        _ => raise self.peek_error(TrailingCharacters)
      }
    }
    Some(_) => raise self.peek_error(TrailingCharacters)
    None => raise self.peek_error(EofWhileParsingList)
  }
}

///|
fn Deserializer::end_map(self : Deserializer) -> Unit raise JsonError {
  match self.parse_whitespace() {
    Some(b'}') => self.eat_char()
    Some(b',') => raise self.peek_error(TrailingComma)
    Some(_) => raise self.peek_error(TrailingCharacters)
    None => raise self.peek_error(EofWhileParsingObject)
  }
}

///|
/// `Deserializer::ignore_value`.
fn Deserializer::ignore_value(self : Deserializer) -> Unit raise JsonError {
  // The enclosing `[`/`{` frames, innermost last.
  let frames : Array[Byte] = []
  let mut enclosing : Byte? = None
  for ;; {
    guard self.parse_whitespace() is Some(peek) else {
      raise self.peek_error(EofWhileParsingValue)
    }
    let frame : Byte? = match peek {
      b'n' => {
        self.eat_char()
        self.parse_ident(b"ull")
        None
      }
      b't' => {
        self.eat_char()
        self.parse_ident(b"rue")
        None
      }
      b'f' => {
        self.eat_char()
        self.parse_ident(b"alse")
        None
      }
      b'-' => {
        self.eat_char()
        self.ignore_integer()
        None
      }
      b'0'..<=b'9' => {
        self.ignore_integer()
        None
      }
      b'"' => {
        self.eat_char()
        self.ignore_str()
        None
      }
      b'[' | b'{' as frame => {
        if enclosing is Some(e) {
          frames.push(e)
        }
        enclosing = None
        self.eat_char()
        Some(frame)
      }
      _ => raise self.peek_error(ExpectedSomeValue)
    }
    let (accept_comma, frame) = match frame {
      Some(frame) => (false, frame)
      None =>
        match enclosing {
          Some(frame) => {
            enclosing = None
            (true, frame)
          }
          None =>
            match frames.pop() {
              Some(frame) => (true, frame)
              None => return
            }
        }
    }
    let mut accept_comma = accept_comma
    let mut frame = frame
    for ;; {
      match self.parse_whitespace() {
        Some(b',') if accept_comma => {
          self.eat_char()
          break
        }
        Some(b']') if frame == b'[' => ()
        Some(b'}') if frame == b'{' => ()
        Some(_) =>
          if accept_comma {
            raise self.peek_error(
              if frame == b'[' {
                ExpectedListCommaOrEnd
              } else {
                ExpectedObjectCommaOrEnd
              },
            )
          } else {
            break
          }
        None =>
          raise self.peek_error(
            if frame == b'[' {
              EofWhileParsingList
            } else {
              EofWhileParsingObject
            },
          )
      }
      self.eat_char()
      frame = match frames.pop() {
        Some(frame) => frame
        None => return
      }
      accept_comma = true
    }
    if frame == b'{' {
      match self.parse_whitespace() {
        Some(b'"') => self.eat_char()
        Some(_) => raise self.peek_error(KeyMustBeAString)
        None => raise self.peek_error(EofWhileParsingObject)
      }
      self.ignore_str()
      match self.parse_whitespace() {
        Some(b':') => self.eat_char()
        Some(_) => raise self.peek_error(ExpectedColon)
        None => raise self.peek_error(EofWhileParsingObject)
      }
    }
    enclosing = Some(frame)
  }
}

///|
fn Deserializer::ignore_integer(self : Deserializer) -> Unit raise JsonError {
  match self.next_char_or_null() {
    b'0' =>
      if self.peek_or_null() is (b'0'..<=b'9') {
        raise self.peek_error(InvalidNumber)
      }
    b'1'..<=b'9' =>
      while self.peek_or_null() is (b'0'..<=b'9') {
        self.eat_char()
      }
    _ => raise self.error(InvalidNumber)
  }
  match self.peek_or_null() {
    b'.' => self.ignore_decimal()
    b'e' | b'E' => self.ignore_exponent()
    _ => ()
  }
}

///|
fn Deserializer::ignore_decimal(self : Deserializer) -> Unit raise JsonError {
  self.eat_char()
  let mut at_least_one_digit = false
  while self.peek_or_null() is (b'0'..<=b'9') {
    self.eat_char()
    at_least_one_digit = true
  }
  if !at_least_one_digit {
    raise self.peek_error(InvalidNumber)
  }
  match self.peek_or_null() {
    b'e' | b'E' => self.ignore_exponent()
    _ => ()
  }
}

///|
fn Deserializer::ignore_exponent(self : Deserializer) -> Unit raise JsonError {
  self.eat_char()
  match self.peek_or_null() {
    b'+' | b'-' => self.eat_char()
    _ => ()
  }
  match self.next_char_or_null() {
    b'0'..<=b'9' => ()
    _ => raise self.error(InvalidNumber)
  }
  while self.peek_or_null() is (b'0'..<=b'9') {
    self.eat_char()
  }
}

// Sequences and maps ----------------------------------------------------------

///|
/// serde_json's `SeqAccess`.
pub struct SeqAccess {
  priv de : Deserializer
  priv mut first : Bool
}

///|
fn SeqAccess::has_next_element(self : SeqAccess) -> Bool raise JsonError {
  guard self.de.parse_whitespace() is Some(peek) else {
    raise self.de.peek_error(EofWhileParsingList)
  }
  if peek == b']' {
    false
  } else if self.first {
    self.first = false
    true
  } else if peek == b',' {
    self.de.eat_char()
    match self.de.parse_whitespace() {
      Some(b']') => raise self.de.peek_error(TrailingComma)
      Some(_) => true
      None => raise self.de.peek_error(EofWhileParsingValue)
    }
  } else {
    raise self.de.peek_error(ExpectedListCommaOrEnd)
  }
}

///|
/// `SeqAccess::next_element_seed`: `seed` deserializes the next element.
pub fn[T] SeqAccess::next_element(
  self : SeqAccess,
  seed : (Deserializer) -> T raise JsonError,
) -> T? raise JsonError {
  if self.has_next_element() {
    Some(seed(self.de))
  } else {
    None
  }
}

///|
/// serde_json's `MapAccess`.
pub struct MapAccess {
  priv de : Deserializer
  priv mut first : Bool
}

///|
fn MapAccess::has_next_key(self : MapAccess) -> Bool raise JsonError {
  guard self.de.parse_whitespace() is Some(peek) else {
    raise self.de.peek_error(EofWhileParsingObject)
  }
  if peek == b'}' {
    false
  } else if self.first {
    self.first = false
    if peek == b'"' {
      true
    } else {
      raise self.de.peek_error(KeyMustBeAString)
    }
  } else if peek == b',' {
    self.de.eat_char()
    match self.de.parse_whitespace() {
      Some(b'"') => true
      Some(b'}') => raise self.de.peek_error(TrailingComma)
      Some(_) => raise self.de.peek_error(KeyMustBeAString)
      None => raise self.de.peek_error(EofWhileParsingValue)
    }
  } else {
    raise self.de.peek_error(ExpectedObjectCommaOrEnd)
  }
}

///|
/// `MapAccess::next_key_seed` with a key deserialized as a string
/// (`MapKey::deserialize_any`, which `deserialize_str`, `deserialize_string`
/// and `deserialize_identifier` forward to): `visit_str` gets the key.
pub fn[T] MapAccess::next_key(
  self : MapAccess,
  visit_str : (String) -> T raise JsonError,
) -> T? raise JsonError {
  if self.has_next_key() {
    self.de.eat_char()
    let s = self.de.parse_str()
    Some(visit_str(s))
  } else {
    None
  }
}

///|
/// `MapAccess::next_value_seed`.
pub fn[T] MapAccess::next_value(
  self : MapAccess,
  seed : (Deserializer) -> T raise JsonError,
) -> T raise JsonError {
  self.de.parse_object_colon()
  seed(self.de)
}
