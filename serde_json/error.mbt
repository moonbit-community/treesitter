// Port of serde_json 1.0.154 src/error.rs (the parts a `from_str`
// deserialization can produce) and of the `serde::de::Error` constructors of
// serde_core 1.0.229 that serde_derive's generated code calls.

///|
/// `serde_json::error::ErrorCode`, minus `Io`.
pub(all) enum ErrorCode {
  /// Catchall for a syntax error or a `serde::de::Error::custom` message.
  Message(String)
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
/// `serde_json::Error`: an error code and the 1-based line and the column (a
/// byte offset within the line) where it was detected. Line 0 means the error
/// has no position yet; `Show` then prints the code alone, otherwise
/// `"{code} at line {line} column {column}"`.
pub suberror JsonError {
  JsonError(code~ : ErrorCode, line~ : Int32, column~ : Int32)
} derive(Eq, Debug)

///|
pub impl Show for JsonError with fn output(self, logger) {
  let JsonError(code~, line~, column~) = self
  if line == 0 {
    logger.write_string(code.to_string())
  } else {
    logger.write_string("\{code} at line \{line} column \{column}")
  }
}

///|
pub fn JsonError::code(self : JsonError) -> ErrorCode {
  let JsonError(code~, ..) = self
  code
}

///|
pub fn JsonError::line(self : JsonError) -> Int32 {
  let JsonError(line~, ..) = self
  line
}

///|
pub fn JsonError::column(self : JsonError) -> Int32 {
  let JsonError(column~, ..) = self
  column
}

///|
/// `Error::syntax`.
pub fn JsonError::syntax(
  code : ErrorCode,
  line : Int32,
  column : Int32,
) -> JsonError {
  JsonError(code~, line~, column~)
}

///|
/// `Error::fix_position`: an error without a position gets the one `f` makes
/// from its code.
pub fn JsonError::fix_position(
  self : JsonError,
  f : (ErrorCode) -> JsonError,
) -> JsonError {
  let JsonError(code~, line~, ..) = self
  if line == 0 {
    f(code)
  } else {
    self
  }
}

///|
/// `de::Error::custom` (serde_json's `make_error`): a message that ends with
/// `" at line L column C"` is split into the message and that position.
pub fn JsonError::custom(msg : String) -> JsonError {
  match parse_line_col(msg) {
    Some((msg, line, column)) => JsonError(code=Message(msg), line~, column~)
    None => JsonError(code=Message(msg), line=0, column=0)
  }
}

///|
/// `parse_line_col`: the message without its `" at line L column C"` suffix,
/// and `L` and `C`.
fn parse_line_col(msg : String) -> (String, Int32, Int32)? {
  let suffix = " at line "
  guard msg.rev_find(suffix) is Some(start_of_suffix) else { return None }
  let start_of_line = start_of_suffix + suffix.length()
  let mut end_of_line = start_of_line
  while end_of_line < msg.length() && is_digit(msg[end_of_line]) {
    end_of_line += 1
  }
  let column_text = " column "
  guard msg[end_of_line:].has_prefix(column_text) else { return None }
  let start_of_column = end_of_line + column_text.length()
  let mut end_of_column = start_of_column
  while end_of_column < msg.length() && is_digit(msg[end_of_column]) {
    end_of_column += 1
  }
  if end_of_column < msg.length() {
    return None
  }
  guard parse_usize(msg, start_of_line, end_of_line) is Some(line) else {
    return None
  }
  guard parse_usize(msg, start_of_column, end_of_column) is Some(column) else {
    return None
  }
  Some((msg[:start_of_suffix].to_owned(), line, column))
}

///|
fn is_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// `usize::from_str` of the ASCII digits `s[start:end]`, which fails when they
/// are empty. (A value that does not fit an `Int` also fails here; serde_json's
/// `usize` would accept it, but no message of this port ends with one.)
fn parse_usize(s : String, start : Int32, end : Int32) -> Int32? {
  if start == end {
    return None
  }
  let mut value = 0L
  for i in start..<end {
    value = value * 10 + (s[i].to_int() - '0').to_int64()
    if value > 0x7FFFFFFFL {
      return None
    }
  }
  Some(value.to_int())
}

// The `serde::de::Error` provided methods -------------------------------------

///|
/// `de::Error::invalid_type` (serde_json's override, with `JsonUnexpected`).
pub fn invalid_type(unexp : Unexpected, expected : String) -> JsonError {
  JsonError::custom(
    "invalid type: \{unexp.json_display()}, expected \{expected}",
  )
}

///|
/// `de::Error::invalid_value` (serde_json's override, with `JsonUnexpected`).
pub fn invalid_value(unexp : Unexpected, expected : String) -> JsonError {
  JsonError::custom(
    "invalid value: \{unexp.json_display()}, expected \{expected}",
  )
}

///|
/// `de::Error::invalid_length`.
pub fn invalid_length(len : Int32, expected : String) -> JsonError {
  JsonError::custom("invalid length \{len}, expected \{expected}")
}

///|
/// `de::Error::missing_field`.
pub fn missing_field(field : String) -> JsonError {
  JsonError::custom("missing field `\{field}`")
}

///|
/// `de::Error::duplicate_field`.
pub fn duplicate_field(field : String) -> JsonError {
  JsonError::custom("duplicate field `\{field}`")
}

///|
/// `de::Error::unknown_variant`.
pub fn unknown_variant(variant : String, expected : Array[String]) -> JsonError {
  if expected.is_empty() {
    JsonError::custom("unknown variant `\{variant}`, there are no variants")
  } else {
    JsonError::custom(
      "unknown variant `\{variant}`, expected \{one_of(expected)}",
    )
  }
}

///|
/// `de::Error::unknown_field`.
pub fn unknown_field(field : String, expected : Array[String]) -> JsonError {
  if expected.is_empty() {
    JsonError::custom("unknown field `\{field}`, there are no fields")
  } else {
    JsonError::custom("unknown field `\{field}`, expected \{one_of(expected)}")
  }
}

///|
/// serde's `OneOf` display.
fn one_of(names : Array[String]) -> String {
  match names.length() {
    1 => "`\{names[0]}`"
    2 => "`\{names[0]}` or `\{names[1]}`"
    _ => "one of " + names.map(name => "`\{name}`").join(", ")
  }
}

///|
/// serde's `ExpectedInSeq` display, for `invalid_length` errors of a
/// sequence with elements left over.
pub fn expected_in_seq(count : Int32) -> String {
  if count == 1 {
    "1 element in sequence"
  } else {
    "\{count} elements in sequence"
  }
}

///|
/// serde's `ExpectedInMap` display.
pub fn expected_in_map(count : Int32) -> String {
  if count == 1 {
    "1 element in map"
  } else {
    "\{count} elements in map"
  }
}
