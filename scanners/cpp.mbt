// Port of tree-sitter-cpp src/scanner.c (v0.23.4)
// tree-sitter-cpp is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`.
const CPP_RAW_STRING_DELIMITER : Int32 = 0

///|
const CPP_RAW_STRING_CONTENT : Int32 = 1

///|
/// The spec limits delimiters to 16 chars
const CPP_MAX_DELIMITER_LENGTH : Int32 = 16

///|
/// `sizeof(wchar_t)` on this platform (a signed 32-bit integer).
const CPP_SIZEOF_WCHAR_T : Int32 = 4

///|
priv struct CppScanner {
  /// `uint8_t delimiter_length`.
  mut delimiter_length : Int32
  /// `wchar_t delimiter[MAX_DELIMITER_LENGTH]`.
  delimiter : FixedArray[Int32]
}

///|
fn CppScanner::reset(self : CppScanner) -> Unit {
  self.delimiter_length = 0
  self.delimiter.fill(0)
}

///|
/// Scan the raw string delimiter in R"delimiter(content)delimiter"
fn CppScanner::scan_raw_string_delimiter(
  self : CppScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  if self.delimiter_length > 0 {
    // Closing delimiter: must exactly match the opening delimiter.
    // We already checked this when scanning content, but this is how we
    // know when to stop. We can't stop at ", because R"""hello""" is valid.
    for i in 0..<self.delimiter_length {
      if lexer.lookahead != self.delimiter[i] {
        return false
      }
      lexer.advance(false)
    }
    self.reset()
    return true
  }

  // Opening delimiter: record the d-char-sequence up to (.
  // d-char is any basic character except parens, backslashes, and spaces.
  for ;; {
    if self.delimiter_length >= CPP_MAX_DELIMITER_LENGTH ||
      lexer.eof() ||
      lexer.lookahead == '\\' ||
      iswspace(lexer.lookahead) {
      return false
    }
    if lexer.lookahead == '(' {
      // Rather than create a token for an empty delimiter, we fail and
      // let the grammar fall back to a delimiter-less rule.
      return self.delimiter_length > 0
    }
    self.delimiter[self.delimiter_length] = lexer.lookahead
    self.delimiter_length += 1
    lexer.advance(false)
  }
}

///|
/// Scan the raw string content in R"delimiter(content)delimiter"
fn CppScanner::scan_raw_string_content(
  self : CppScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  // The progress made through the delimiter since the last ')'.
  // The delimiter may not contain ')' so a single counter suffices.
  let mut delimiter_index = -1
  for ;; {
    // If we hit EOF, consider the content to terminate there.
    // This forms an incomplete raw_string_literal, and models the code
    // well.
    if lexer.eof() {
      lexer.mark_end()
      return true
    }
    if delimiter_index >= 0 {
      if delimiter_index == self.delimiter_length {
        if lexer.lookahead == '"' {
          return true
        }
        delimiter_index = -1
      } else if lexer.lookahead == self.delimiter[delimiter_index] {
        delimiter_index += 1
      } else {
        delimiter_index = -1
      }
    }
    if delimiter_index == -1 && lexer.lookahead == ')' {
      // The content doesn't include the )delimiter" part.
      // We must still scan through it, but exclude it from the token.
      lexer.mark_end()
      delimiter_index = 0
    }
    lexer.advance(false)
  }
}

///|
fn CppScanner::scan(
  self : CppScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[CPP_RAW_STRING_DELIMITER] &&
    valid_symbols[CPP_RAW_STRING_CONTENT] {
    // we're in error recovery
    return false
  }

  // No skipping leading whitespace: raw-string grammar is space-sensitive.
  if valid_symbols[CPP_RAW_STRING_DELIMITER] {
    lexer.result_symbol = CPP_RAW_STRING_DELIMITER
    return self.scan_raw_string_delimiter(lexer)
  }
  if valid_symbols[CPP_RAW_STRING_CONTENT] {
    lexer.result_symbol = CPP_RAW_STRING_CONTENT
    return self.scan_raw_string_content(lexer)
  }
  false
}

///|
fn CppScanner::serialize(self : CppScanner, buffer : FixedArray[Byte]) -> Int32 {
  // memcpy of `delimiter_length` little-endian wchar_t values.
  let size = self.delimiter_length * CPP_SIZEOF_WCHAR_T
  for i in 0..<self.delimiter_length {
    let c = self.delimiter[i]
    for k in 0..<CPP_SIZEOF_WCHAR_T {
      buffer[i * CPP_SIZEOF_WCHAR_T + k] = (c >> (8 * k)).to_byte()
    }
  }
  size
}

///|
fn CppScanner::deserialize(self : CppScanner, buffer : BytesView) -> Unit {
  let length = buffer.length()
  guard length % CPP_SIZEOF_WCHAR_T == 0 else {
    c_assert_fail(
      "length % sizeof(wchar_t) == 0 && \"Can't decode serialized delimiter!\"",
      "tree_sitter_cpp_external_scanner_deserialize",
      136,
    )
  }
  // `uint8_t` truncation of `length / sizeof(wchar_t)`.
  self.delimiter_length = (length / CPP_SIZEOF_WCHAR_T) & 0xFF
  if length > 0 {
    // memcpy(&scanner->delimiter[0], buffer, length)
    for i in 0..<(length / CPP_SIZEOF_WCHAR_T) {
      let mut c = 0
      for k in 0..<CPP_SIZEOF_WCHAR_T {
        c = c | (buffer[i * CPP_SIZEOF_WCHAR_T + k].to_int() << (8 * k))
      }
      self.delimiter[i] = c
    }
  }
}

///|
fn cpp_scanner() -> @runtime.ExternalScanner {
  let scanner : CppScanner = {
    delimiter_length: 0,
    delimiter: FixedArray::make(CPP_MAX_DELIMITER_LENGTH, 0),
  }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => (),
  }
}
