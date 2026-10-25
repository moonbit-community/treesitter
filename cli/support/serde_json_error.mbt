// Port of serde_json 1.0.154 src/error.rs (the parts the CLI uses), with
// serde's `de::Error` provided methods (`invalid_length`, `missing_field`,
// `duplicate_field`) and serde_json's `JsonUnexpected`.

///|
/// `serde_json::error::ErrorCode`. `Io` holds the display text of the
/// `io::Error`.
pub(all) enum ErrorCode {
  Message(String)
  Io(String)
  EofWhileParsingList
  EofWhileParsingObject
  EofWhileParsingString
  EofWhileParsingValue
  ExpectedColon
  ExpectedListCommaOrEnd
  ExpectedObjectCommaOrEnd
  ExpectedSomeIdent
  ExpectedSomeValue
  ExpectedDoubleQuote
  InvalidEscape
  InvalidNumber
  NumberOutOfRange
  InvalidUnicodeCodePoint
  ControlCharacterWhileParsingString
  KeyMustBeAString
  ExpectedNumericKey
  FloatKeyMustBeFinite
  LoneLeadingSurrogateInHexEscape
  TrailingComma
  TrailingCharacters
  UnexpectedEndOfHexEscape
  RecursionLimitExceeded
} derive(Eq, Debug)

///|
pub impl Show for ErrorCode with fn output(self, logger) {
  logger.write_string(
    match self {
      Message(msg) => msg
      Io(err) => err
      EofWhileParsingList => "EOF while parsing a list"
      EofWhileParsingObject => "EOF while parsing an object"
      EofWhileParsingString => "EOF while parsing a string"
      EofWhileParsingValue => "EOF while parsing a value"
      ExpectedColon => "expected `:`"
      ExpectedListCommaOrEnd => "expected `,` or `]`"
      ExpectedObjectCommaOrEnd => "expected `,` or `}`"
      ExpectedSomeIdent => "expected ident"
      ExpectedSomeValue => "expected value"
      ExpectedDoubleQuote => "expected `\"`"
      InvalidEscape => "invalid escape"
      InvalidNumber => "invalid number"
      NumberOutOfRange => "number out of range"
      InvalidUnicodeCodePoint => "invalid unicode code point"
      ControlCharacterWhileParsingString =>
        "control character (\\u0000-\\u001F) found while parsing a string"
      KeyMustBeAString => "key must be a string"
      ExpectedNumericKey =>
        "invalid value: expected key to be a number in quotes"
      FloatKeyMustBeFinite => "float key must be finite (got NaN or +/-inf)"
      LoneLeadingSurrogateInHexEscape => "lone leading surrogate in hex escape"
      TrailingComma => "trailing comma"
      TrailingCharacters => "trailing characters"
      UnexpectedEndOfHexEscape => "unexpected end of hex escape"
      RecursionLimitExceeded => "recursion limit exceeded"
    },
  )
}

///|
/// `serde_json::Error`: an error code and the 1-based line and 0-based byte
/// column where it occurred (line 0 when the position is unknown, as for
/// errors of `from_value` and errors raised by a `Visitor`).
pub(all) suberror SerdeJsonError {
  SerdeJsonError(code~ : ErrorCode, line~ : Int32, column~ : Int32)
} derive(Eq, Debug)

///|
/// `Display for ErrorImpl`.
pub impl Show for SerdeJsonError with fn output(self, logger) {
  let SerdeJsonError(code~, line~, column~) = self
  if line == 0 {
    logger.write_string("\{code}")
  } else {
    logger.write_string("\{code} at line \{line} column \{column}")
  }
}

///|
pub fn SerdeJsonError::line(self : SerdeJsonError) -> Int32 {
  let SerdeJsonError(line~, ..) = self
  line
}

///|
pub fn SerdeJsonError::column(self : SerdeJsonError) -> Int32 {
  let SerdeJsonError(column~, ..) = self
  column
}

///|
/// `Error::syntax`.
pub fn SerdeJsonError::syntax(
  code : ErrorCode,
  line : Int32,
  column : Int32,
) -> SerdeJsonError {
  SerdeJsonError(code~, line~, column~)
}

///|
/// `Error::io`.
pub fn SerdeJsonError::io(message : String) -> SerdeJsonError {
  SerdeJsonError(code=Io(message), line=0, column=0)
}

///|
/// `Error::fix_position`: give a positionless error the position computed
/// by `f`.
fn SerdeJsonError::fix_position(
  self : SerdeJsonError,
  f : (ErrorCode) -> SerdeJsonError,
) -> SerdeJsonError {
  let SerdeJsonError(code~, line~, ..) = self
  if line == 0 {
    f(code)
  } else {
    self
  }
}

///|
/// `de::Error::custom` (`make_error`).
pub fn SerdeJsonError::custom(msg : String) -> SerdeJsonError {
  match parse_line_col(msg) {
    Some((msg, line, column)) =>
      SerdeJsonError(code=Message(msg), line~, column~)
    None => SerdeJsonError(code=Message(msg), line=0, column=0)
  }
}

///|
/// `de::Error::invalid_type`.
pub fn SerdeJsonError::invalid_type(
  unexp : Unexpected,
  exp : String,
) -> SerdeJsonError {
  SerdeJsonError::custom("invalid type: \{unexp}, expected \{exp}")
}

///|
/// `de::Error::invalid_value`.
pub fn SerdeJsonError::invalid_value(
  unexp : Unexpected,
  exp : String,
) -> SerdeJsonError {
  SerdeJsonError::custom("invalid value: \{unexp}, expected \{exp}")
}

///|
/// `de::Error::invalid_length`.
pub fn SerdeJsonError::invalid_length(
  len : Int32,
  exp : String,
) -> SerdeJsonError {
  SerdeJsonError::custom("invalid length \{len}, expected \{exp}")
}

///|
/// `de::Error::missing_field`.
pub fn SerdeJsonError::missing_field(field : String) -> SerdeJsonError {
  SerdeJsonError::custom("missing field `\{field}`")
}

///|
/// `de::Error::duplicate_field`.
pub fn SerdeJsonError::duplicate_field(field : String) -> SerdeJsonError {
  SerdeJsonError::custom("duplicate field `\{field}`")
}

///|
/// Parse our own error message that looks like "{} at line {} column {}" to
/// work around erased-serde round-tripping the error through
/// `de::Error::custom`. Returns the message without that suffix.
fn parse_line_col(msg : String) -> (String, Int32, Int32)? {
  let suffix = " at line "
  guard msg.rev_find(suffix) is Some(start_of_suffix) else { return None }
  // Find start and end of line number.
  let start_of_line = start_of_suffix + suffix.length()
  let mut end_of_line = start_of_line
  while end_of_line < msg.length() && is_ascii_digit(msg[end_of_line]) {
    end_of_line += 1
  }
  let column_text = " column "
  guard msg[end_of_line:].has_prefix(column_text) else { return None }
  // Find start and end of column number.
  let start_of_column = end_of_line + column_text.length()
  let mut end_of_column = start_of_column
  while end_of_column < msg.length() && is_ascii_digit(msg[end_of_column]) {
    end_of_column += 1
  }
  if end_of_column < msg.length() {
    return None
  }
  // Parse numbers.
  guard parse_usize(msg, start_of_line, end_of_line) is Some(line) else {
    return None
  }
  guard parse_usize(msg, start_of_column, end_of_column) is Some(column) else {
    return None
  }
  Some((msg[:start_of_suffix].to_owned(), line, column))
}

///|
fn is_ascii_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// `usize::from_str` of ASCII digits `s[start:end]` (`None` when empty or
/// out of range).
fn parse_usize(s : String, start : Int32, end : Int32) -> Int32? {
  if start == end {
    return None
  }
  let mut n = 0L
  for i in start..<end {
    n = n * 10L + (s[i].to_int() - '0').to_int64()
    if n > 0x7FFFFFFFL {
      return None
    }
  }
  Some(n.to_int())
}

///|
/// `serde::de::Unexpected`.
pub(all) enum Unexpected {
  Bool(Bool)
  Unsigned(UInt64)
  Signed(Int64)
  Float(Double)
  Str(String)
  Unit
  Option
  Seq
  Map
} derive(Debug)

///|
/// `Display for JsonUnexpected`: serde's `Display for Unexpected` with
/// serde_json's `null` for the unit value and zmij's float formatting.
pub impl Show for Unexpected with fn output(self, logger) {
  match self {
    Bool(b) => logger.write_string("boolean `\{b}`")
    Unsigned(i) => logger.write_string("integer `\{i}`")
    Signed(i) => logger.write_string("integer `\{i}`")
    Float(f) => logger.write_string("floating point `\{zmij_format(f)}`")
    Str(s) => logger.write_string("string \{rust_debug_str(s)}")
    Unit => logger.write_string("null")
    Option => logger.write_string("Option value")
    Seq => logger.write_string("sequence")
    Map => logger.write_string("map")
  }
}
