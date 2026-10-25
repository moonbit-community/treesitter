// Port of serde_json 1.0.154 src/read.rs: `StrRead` (a `SliceRead` over the
// UTF-8 bytes of the input) and the string escape handling.

///|
/// `Position`: a 1-based line and the byte column within it.
priv struct Position {
  line : Int32
  column : Int32
}

///|
/// `SliceRead::position_of_index`.
fn Deserializer::position_of_index(self : Deserializer, i : Int32) -> Position {
  let mut start_of_line = 0
  let mut line = 1
  for j in 0..<i {
    if self.slice[j] == b'\n' {
      start_of_line = j + 1
      line += 1
    }
  }
  { line, column: i - start_of_line, }
}

///|
fn Deserializer::position(self : Deserializer) -> Position {
  self.position_of_index(self.index)
}

///|
fn Deserializer::peek_position(self : Deserializer) -> Position {
  let i = if self.index + 1 < self.slice.length() {
    self.index + 1
  } else {
    self.slice.length()
  }
  self.position_of_index(i)
}

///|
/// The `error` function of read.rs: an error at the current position.
fn Deserializer::read_error(self : Deserializer, code : ErrorCode) -> JsonError {
  let position = self.position()
  JsonError(code~, line=position.line, column=position.column)
}

///|
fn is_escape(ch : Byte, including_control_characters : Bool) -> Bool {
  ch == b'"' || ch == b'\\' || (including_control_characters && ch < b'\x20')
}

///|
/// `SliceRead::skip_to_escape`: advance to the next `"`, `\` or (when
/// `forbid_control_characters`) control character.
fn Deserializer::skip_to_escape(
  self : Deserializer,
  forbid_control_characters : Bool,
) -> Unit {
  let slice = self.slice
  let n = slice.length()
  let mut i = self.index
  while i < n && !is_escape(slice[i], forbid_control_characters) {
    i += 1
  }
  self.index = i
}

///|
/// `StrRead::parse_str`: the contents of a string whose opening quote has
/// been consumed, with escapes decoded and validated.
fn Deserializer::parse_str(self : Deserializer) -> String raise JsonError {
  let scratch = self.scratch
  scratch.reset()
  let mut start = self.index
  for ;; {
    self.skip_to_escape(true)
    if self.index == self.slice.length() {
      raise self.read_error(EofWhileParsingString)
    }
    match self.slice[self.index] {
      b'"' => {
        let s = if scratch.length() == 0 {
          @utf8.decode_lossy(self.slice[start:self.index])
        } else {
          scratch.write_bytesview(self.slice[start:self.index])
          @utf8.decode_lossy(scratch.contents())
        }
        self.index += 1
        return s
      }
      b'\\' => {
        scratch.write_bytesview(self.slice[start:self.index])
        self.index += 1
        self.parse_escape(scratch)
        start = self.index
      }
      _ => {
        self.index += 1
        raise self.read_error(ControlCharacterWhileParsingString)
      }
    }
  }
}

///|
/// `SliceRead::ignore_str`: skip a string whose opening quote has been
/// consumed. Unicode escapes are not checked for surrogate pairing.
fn Deserializer::ignore_str(self : Deserializer) -> Unit raise JsonError {
  for ;; {
    self.skip_to_escape(true)
    if self.index == self.slice.length() {
      raise self.read_error(EofWhileParsingString)
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
      _ => raise self.read_error(ControlCharacterWhileParsingString)
    }
  }
}

///|
/// `next_or_eof`.
fn Deserializer::next_or_eof(self : Deserializer) -> Byte raise JsonError {
  if self.index < self.slice.length() {
    let ch = self.slice[self.index]
    self.index += 1
    ch
  } else {
    raise self.read_error(EofWhileParsingString)
  }
}

///|
/// `peek_or_eof`.
fn Deserializer::peek_or_eof(self : Deserializer) -> Byte raise JsonError {
  if self.index < self.slice.length() {
    self.slice[self.index]
  } else {
    raise self.read_error(EofWhileParsingString)
  }
}

///|
/// `parse_escape` with `validate`: the escape after a consumed `\`.
fn Deserializer::parse_escape(
  self : Deserializer,
  scratch : @buffer.Buffer,
) -> Unit raise JsonError {
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
    b'u' => self.parse_unicode_escape(scratch)
    _ => raise self.read_error(InvalidEscape)
  }
}

///|
/// `parse_unicode_escape` with `validate`.
fn Deserializer::parse_unicode_escape(
  self : Deserializer,
  scratch : @buffer.Buffer,
) -> Unit raise JsonError {
  let n = self.decode_hex_escape()
  if n >= 0xDC00 && n <= 0xDFFF {
    raise self.read_error(LoneLeadingSurrogateInHexEscape)
  }
  if n < 0xD800 || n > 0xDBFF {
    push_wtf8_codepoint(n, scratch)
    return
  }
  let n1 = n
  if self.peek_or_eof() == b'\\' {
    self.index += 1
  } else {
    self.index += 1
    raise self.read_error(UnexpectedEndOfHexEscape)
  }
  if self.peek_or_eof() == b'u' {
    self.index += 1
  } else {
    self.index += 1
    raise self.read_error(UnexpectedEndOfHexEscape)
  }
  let n2 = self.decode_hex_escape()
  if n2 < 0xDC00 || n2 > 0xDFFF {
    raise self.read_error(LoneLeadingSurrogateInHexEscape)
  }
  let n = (((n1 - 0xD800) << 10) | (n2 - 0xDC00)) + 0x1_0000
  push_wtf8_codepoint(n, scratch)
}

///|
/// `push_wtf8_codepoint`: the UTF-8 encoding of `n`.
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
/// `ignore_escape`.
fn Deserializer::ignore_escape(self : Deserializer) -> Unit raise JsonError {
  let ch = self.next_or_eof()
  match ch {
    b'"' | b'\\' | b'/' | b'b' | b'f' | b'n' | b'r' | b't' => ()
    // At this point we don't care if the codepoint is valid. We just want
    // to consume it.
    b'u' => ignore(self.decode_hex_escape())
    _ => raise self.read_error(InvalidEscape)
  }
}

///|
/// `SliceRead::decode_hex_escape`: four hexadecimal digits.
fn Deserializer::decode_hex_escape(
  self : Deserializer,
) -> Int32 raise JsonError {
  if self.index + 4 <= self.slice.length() {
    let mut value = 0
    let mut valid = true
    for k in 0..<4 {
      match hex_value(self.slice[self.index + k]) {
        Some(d) => value = (value << 4) | d
        None => valid = false
      }
    }
    self.index += 4
    if valid {
      value
    } else {
      raise self.read_error(InvalidEscape)
    }
  } else {
    self.index = self.slice.length()
    raise self.read_error(EofWhileParsingString)
  }
}

///|
fn hex_value(b : Byte) -> Int32? {
  match b {
    b'0'..<=b'9' => Some(b.to_int() - '0'.to_int())
    b'A'..<=b'F' => Some(b.to_int() - 'A'.to_int() + 10)
    b'a'..<=b'f' => Some(b.to_int() - 'a'.to_int() + 10)
    _ => None
  }
}
