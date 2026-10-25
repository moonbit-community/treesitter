// Port of serde_json 1.0.154 src/read.rs: `SliceRead` (which `StrRead`
// delegates to) with the string, escape and position functions.

///|
/// `read::Position`.
priv struct Position {
  line : Int32
  column : Int32
}

///|
/// `SliceRead` over the UTF-8 bytes of a `&str`.
priv struct SliceRead {
  slice : Bytes
  mut index : Int32
}

///|
fn SliceRead::new(slice : Bytes) -> SliceRead {
  { slice, index: 0, }
}

///|
fn SliceRead::position_of_index(self : SliceRead, i : Int32) -> Position {
  let mut start_of_line = 0
  for j = i - 1; j >= 0; j = j - 1 {
    if self.slice[j] == b'\n' {
      start_of_line = j + 1
      break
    }
  }
  let mut line = 1
  for j in 0..<start_of_line {
    if self.slice[j] == b'\n' {
      line += 1
    }
  }
  { line, column: i - start_of_line, }
}

///|
fn is_escape(ch : Byte, including_control_characters : Bool) -> Bool {
  ch == b'"' || ch == b'\\' || (including_control_characters && ch < 0x20)
}

///|
/// Advance to the next `"`, `\` or (if `forbid_control_characters`) control
/// character.
fn SliceRead::skip_to_escape(
  self : SliceRead,
  forbid_control_characters : Bool,
) -> Unit {
  while self.index < self.slice.length() &&
        !is_escape(self.slice[self.index], forbid_control_characters) {
    self.index += 1
  }
}

///|
/// `parse_str_bytes` with `validate = true` and `as_str`: the input is a
/// `&str`, so the bytes are valid UTF-8.
fn SliceRead::parse_str(self : SliceRead) -> String raise SerdeJsonError {
  let scratch = Buffer()
  // Index of the first byte not yet copied into the scratch space.
  let mut start = self.index
  for ;; {
    self.skip_to_escape(true)
    if self.index == self.slice.length() {
      raise self.error(EofWhileParsingString)
    }
    match self.slice[self.index] {
      b'"' => {
        scratch.write_bytesview(self.slice[start:self.index])
        self.index += 1
        return @utf8.decode_lossy(scratch.contents())
      }
      b'\\' => {
        scratch.write_bytesview(self.slice[start:self.index])
        self.index += 1
        self.parse_escape(true, scratch)
        start = self.index
      }
      _ => {
        self.index += 1
        raise self.error(ControlCharacterWhileParsingString)
      }
    }
  }
}

///|
fn SliceRead::next(self : SliceRead) -> Byte? {
  if self.index < self.slice.length() {
    let ch = self.slice[self.index]
    self.index += 1
    Some(ch)
  } else {
    None
  }
}

///|
fn SliceRead::peek(self : SliceRead) -> Byte? {
  if self.index < self.slice.length() {
    Some(self.slice[self.index])
  } else {
    None
  }
}

///|
fn SliceRead::discard(self : SliceRead) -> Unit {
  self.index += 1
}

///|
fn SliceRead::position(self : SliceRead) -> Position {
  self.position_of_index(self.index)
}

///|
fn SliceRead::peek_position(self : SliceRead) -> Position {
  // Cap it at slice.len() just in case the most recent call was next() and
  // it returned the last byte.
  let i = if self.index + 1 < self.slice.length() {
    self.index + 1
  } else {
    self.slice.length()
  }
  self.position_of_index(i)
}

///|
fn SliceRead::ignore_str(self : SliceRead) -> Unit raise SerdeJsonError {
  for ;; {
    self.skip_to_escape(true)
    if self.index == self.slice.length() {
      raise self.error(EofWhileParsingString)
    }
    match self.slice[self.index] {
      b'"' => {
        self.index += 1
        return
      }
      b'\\' => {
        self.index += 1
        self.ignore_escape()
      }
      _ => raise self.error(ControlCharacterWhileParsingString)
    }
  }
}

///|
fn SliceRead::decode_hex_escape(self : SliceRead) -> Int32 raise SerdeJsonError {
  if self.index + 4 <= self.slice.length() {
    let s = self.slice
    let i = self.index
    self.index += 4
    match decode_four_hex_digits(s[i], s[i + 1], s[i + 2], s[i + 3]) {
      Some(val) => val
      None => raise self.error(InvalidEscape)
    }
  } else {
    self.index = self.slice.length()
    raise self.error(EofWhileParsingString)
  }
}

///|
/// `read::error`.
fn SliceRead::error(self : SliceRead, reason : ErrorCode) -> SerdeJsonError {
  let position = self.position()
  SerdeJsonError::syntax(reason, position.line, position.column)
}

///|
fn SliceRead::next_or_eof(self : SliceRead) -> Byte raise SerdeJsonError {
  match self.next() {
    Some(b) => b
    None => raise self.error(EofWhileParsingString)
  }
}

///|
fn SliceRead::peek_or_eof(self : SliceRead) -> Byte raise SerdeJsonError {
  match self.peek() {
    Some(b) => b
    None => raise self.error(EofWhileParsingString)
  }
}

///|
/// Parses a JSON escape sequence and appends it into the scratch space.
/// Assumes the previous byte read was a backslash.
fn SliceRead::parse_escape(
  self : SliceRead,
  validate : Bool,
  scratch : @buffer.Buffer,
) -> Unit raise SerdeJsonError {
  let ch = self.next_or_eof()
  match ch {
    b'"' => scratch.write_byte(b'"')
    b'\\' => scratch.write_byte(b'\\')
    b'/' => scratch.write_byte(b'/')
    b'b' => scratch.write_byte(b'\x08')
    b'f' => scratch.write_byte(b'\x0c')
    b'n' => scratch.write_byte(b'\n')
    b'r' => scratch.write_byte(b'\r')
    b't' => scratch.write_byte(b'\t')
    b'u' => self.parse_unicode_escape(validate, scratch)
    _ => raise self.error(InvalidEscape)
  }
}

///|
/// Parses a JSON `\u` escape and appends it into the scratch space. Assumes
/// `\u` has just been read.
fn SliceRead::parse_unicode_escape(
  self : SliceRead,
  validate : Bool,
  scratch : @buffer.Buffer,
) -> Unit raise SerdeJsonError {
  let mut n = self.decode_hex_escape()
  // Non-BMP characters are encoded as a sequence of two hex escapes,
  // representing UTF-16 surrogates. If deserializing a utf-8 string the
  // surrogates are required to be paired, whereas deserializing a byte
  // string accepts lone surrogates.
  if validate && n >= 0xDC00 && n <= 0xDFFF {
    // XXX: This is actually a trailing surrogate.
    raise self.error(LoneLeadingSurrogateInHexEscape)
  }
  for ;; {
    if n < 0xD800 || n > 0xDBFF {
      // Every u16 outside of the surrogate ranges is guaranteed to be a
      // legal char.
      push_wtf8_codepoint(n, scratch)
      return
    }
    // n is a leading surrogate, we now expect a trailing surrogate.
    let n1 = n
    if self.peek_or_eof() == b'\\' {
      self.discard()
    } else if validate {
      self.discard()
      raise self.error(UnexpectedEndOfHexEscape)
    } else {
      push_wtf8_codepoint(n1, scratch)
      return
    }
    if self.peek_or_eof() == b'u' {
      self.discard()
    } else if validate {
      self.discard()
      raise self.error(UnexpectedEndOfHexEscape)
    } else {
      push_wtf8_codepoint(n1, scratch)
      // The \ prior to this byte started an escape sequence, so we need to
      // parse that now.
      self.parse_escape(validate, scratch)
      return
    }
    let n2 = self.decode_hex_escape()
    if n2 < 0xDC00 || n2 > 0xDFFF {
      if validate {
        raise self.error(LoneLeadingSurrogateInHexEscape)
      }
      push_wtf8_codepoint(n1, scratch)
      // If n2 is a leading surrogate, we need to restart.
      n = n2
      continue
    }
    // This value is in range U+10000..=U+10FFFF, which is always a valid
    // codepoint.
    let n = (((n1 - 0xD800) << 10) | (n2 - 0xDC00)) + 0x1_0000
    push_wtf8_codepoint(n, scratch)
    return
  }
}

///|
fn push_wtf8_codepoint(n : Int32, scratch : @buffer.Buffer) -> Unit {
  if n < 0x80 {
    scratch.write_byte(n.to_byte())
  } else if n < 0x800 {
    scratch.write_byte((((n >> 6) & 0b0001_1111) | 0b1100_0000).to_byte())
    scratch.write_byte(((n & 0b0011_1111) | 0b1000_0000).to_byte())
  } else if n < 0x10000 {
    scratch.write_byte((((n >> 12) & 0b0000_1111) | 0b1110_0000).to_byte())
    scratch.write_byte((((n >> 6) & 0b0011_1111) | 0b1000_0000).to_byte())
    scratch.write_byte(((n & 0b0011_1111) | 0b1000_0000).to_byte())
  } else {
    scratch.write_byte((((n >> 18) & 0b0000_0111) | 0b1111_0000).to_byte())
    scratch.write_byte((((n >> 12) & 0b0011_1111) | 0b1000_0000).to_byte())
    scratch.write_byte((((n >> 6) & 0b0011_1111) | 0b1000_0000).to_byte())
    scratch.write_byte(((n & 0b0011_1111) | 0b1000_0000).to_byte())
  }
}

///|
/// Parses a JSON escape sequence and discards the value. Assumes the
/// previous byte read was a backslash.
fn SliceRead::ignore_escape(self : SliceRead) -> Unit raise SerdeJsonError {
  let ch = self.next_or_eof()
  match ch {
    b'"' | b'\\' | b'/' | b'b' | b'f' | b'n' | b'r' | b't' => ()
    b'u' =>
      // At this point we don't care if the codepoint is valid. We just want
      // to consume it.
      ignore(self.decode_hex_escape())
    _ => raise self.error(InvalidEscape)
  }
}

///|
fn decode_hex_val(val : Byte) -> Int32 {
  match val {
    b'0'..<=b'9' => (val - b'0').to_int()
    b'A'..<=b'F' => (val - b'A').to_int() + 10
    b'a'..<=b'f' => (val - b'a').to_int() + 10
    _ => -1
  }
}

///|
fn decode_four_hex_digits(a : Byte, b : Byte, c : Byte, d : Byte) -> Int32? {
  let a = decode_hex_val(a)
  let b = decode_hex_val(b)
  let c = decode_hex_val(c)
  let d = decode_hex_val(d)
  if a < 0 || b < 0 || c < 0 || d < 0 {
    None
  } else {
    Some((a << 12) | (b << 8) | (c << 4) | d)
  }
}
