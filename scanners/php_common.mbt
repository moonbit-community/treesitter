// Port of the php grammar's common/scanner.h (v0.24.2), shared by the php and
// php_only scanners.

///|
const PHP_AUTOMATIC_SEMICOLON : Int32 = 0

///|
const PHP_ENCAPSED_STRING_CHARS : Int32 = 1

///|
const PHP_ENCAPSED_STRING_CHARS_AFTER_VARIABLE : Int32 = 2

///|
const PHP_EXECUTION_STRING_CHARS : Int32 = 3

///|
const PHP_EXECUTION_STRING_CHARS_AFTER_VARIABLE : Int32 = 4

///|
const PHP_ENCAPSED_STRING_CHARS_HEREDOC : Int32 = 5

///|
const PHP_ENCAPSED_STRING_CHARS_AFTER_VARIABLE_HEREDOC : Int32 = 6

///|
const PHP_EOF_TOKEN : Int32 = 7

///|
const PHP_HEREDOC_START : Int32 = 8

///|
const PHP_HEREDOC_END : Int32 = 9

///|
const PHP_NOWDOC_STRING : Int32 = 10

///|
/// Unused token used to indicate error recovery mode
const PHP_SENTINEL_ERROR : Int32 = 11

///|
/// `string_eq` on `String` = `Array(int32_t)`.
fn php_string_eq(a : Array[Int32], other : Array[Int32]) -> Bool {
  if a.length() != other.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != other[i] {
      return false
    }
  }
  true
}

///|
priv struct PhpHeredoc {
  mut end_word_indentation_allowed : Bool
  mut word : Array[Int32]
}

///|
fn php_heredoc_new() -> PhpHeredoc {
  { end_word_indentation_allowed: false, word: [], }
}

///|
/// `Scanner`. Note that `deserialize` never shrinks `heredocs`: entries past
/// the deserialized count are only reset, exactly as in the C scanner.
/// `has_leading_whitespace` is written but never read, as in C.
#warnings("-unused_field")
priv struct PhpScanner {
  mut has_leading_whitespace : Bool
  heredocs : Array[PhpHeredoc]
}

///|
fn PhpHeredoc::reset(self : PhpHeredoc) -> Unit {
  self.word = []
  self.end_word_indentation_allowed = false
}

///|
fn PhpScanner::serialize(self : PhpScanner, buffer : FixedArray[Byte]) -> Int32 {
  let mut size = 0
  // `(char)scanner->heredocs.size` keeps the low byte.
  buffer[size] = self.heredocs.length().to_byte()
  size += 1
  for heredoc in self.heredocs {
    let word_size = php_word_size(heredoc.word.length())
    if php_heredoc_overflows(size, word_size) {
      return 0
    }
    buffer[size] = if heredoc.end_word_indentation_allowed { 1 } else { 0 }
    size += 1
    php_write_i32(buffer, size, heredoc.word.length())
    size += 4
    if heredoc.word.length() > 0 {
      // `memcpy` of `word_size` bytes.
      for k in 0..<(word_size / 4).reinterpret_as_int() {
        php_write_i32(buffer, size, heredoc.word[k])
        size += 4
      }
    }
  }
  size
}

///|
/// `heredoc->word.size * sizeof(heredoc->word.contents[0])` stored in an
/// `unsigned`: it wraps modulo 2^32.
fn php_word_size(word_length : Int32) -> UInt {
  word_length.reinterpret_as_uint() * 4
}

///|
/// `size + 5 + word_size >= TREE_SITTER_SERIALIZATION_BUFFER_SIZE` in
/// `unsigned` arithmetic.
fn php_heredoc_overflows(size : Int32, word_size : UInt) -> Bool {
  size.reinterpret_as_uint() + 5 + word_size >=
  SERIALIZATION_BUFFER_SIZE.reinterpret_as_uint()
}

///|
fn php_write_i32(buffer : FixedArray[Byte], at : Int32, value : Int32) -> Unit {
  buffer[at] = value.to_byte()
  buffer[at + 1] = (value >> 8).to_byte()
  buffer[at + 2] = (value >> 16).to_byte()
  buffer[at + 3] = (value >> 24).to_byte()
}

///|
fn php_read_i32(buffer : BytesView, at : Int32) -> Int32 {
  buffer[at].to_int() |
  (buffer[at + 1].to_int() << 8) |
  (buffer[at + 2].to_int() << 16) |
  (buffer[at + 3].to_int() << 24)
}

///|
fn PhpScanner::deserialize(self : PhpScanner, buffer : BytesView) -> Unit {
  let mut size = 0
  self.has_leading_whitespace = false
  for heredoc in self.heredocs {
    heredoc.reset()
  }
  if buffer.length() == 0 {
    return
  }
  let open_heredoc_count = buffer[size].to_int()
  size += 1
  for i in 0..<open_heredoc_count {
    let heredoc = if i < self.heredocs.length() {
      self.heredocs[i]
    } else {
      let new_heredoc = php_heredoc_new()
      self.heredocs.push(new_heredoc)
      new_heredoc
    }
    heredoc.end_word_indentation_allowed = buffer[size] != 0
    size += 1
    let word_length = php_read_i32(buffer, size)
    size += 4
    if word_length != 0 {
      heredoc.word = Array::makei(word_length, k => {
        php_read_i32(buffer, size + k * 4)
      })
      size += word_length * 4
    }
  }
  if size != buffer.length() {
    abort("php scanner: assert(size == length) failed")
  }
}

///|
fn php_scan_whitespace(lexer : @runtime.Lexer) -> Bool {
  for ;; {
    while iswspace(lexer.lookahead) {
      lexer.advance(false)
    }
    if lexer.lookahead == '/' {
      lexer.advance(false)
      if lexer.lookahead == '/' {
        lexer.advance(false)
        while lexer.lookahead != 0 && lexer.lookahead != '\n' {
          lexer.advance(false)
        }
      } else {
        return false
      }
    } else {
      return true
    }
  }
}

///|
fn php_is_valid_name_char(lexer : @runtime.Lexer) -> Bool {
  iswalnum(lexer.lookahead) || lexer.lookahead == '_' || lexer.lookahead >= 0x80
}

///|
fn php_is_escapable_sequence(lexer : @runtime.Lexer) -> Bool {
  // Note: remember to also update the escape_sequence rule in the
  // main grammar whenever changing this method
  let letter = lexer.lookahead
  if letter == 'n' ||
    letter == 'r' ||
    letter == 't' ||
    letter == 'v' ||
    letter == 'e' ||
    letter == 'f' ||
    letter == '\\' ||
    letter == '$' ||
    letter == '"' {
    return true
  }

  // Hex
  if letter == 'x' {
    lexer.advance(false)
    return iswxdigit(lexer.lookahead)
  }

  // Unicode
  if letter == 'u' {
    return true // We handle the case where this is not really an escape
    // sequence in grammar.js - this is needed to support the
    // edge case "\u{$a}" in which case "\u" is to be
    // interpreted as characters and {$a} as a variable
  }

  // Octal
  iswdigit(lexer.lookahead) && lexer.lookahead >= '0' && lexer.lookahead <= '7'
}

///|
fn php_scan_heredoc_word(lexer : @runtime.Lexer) -> Array[Int32] {
  let result = []
  while php_is_valid_name_char(lexer) {
    result.push(lexer.lookahead)
    lexer.advance(false)
  }
  result
}

///|
fn PhpScanner::scan_nowdoc_string(
  self : PhpScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  let mut has_consumed_content = false
  if self.heredocs.length() == 0 {
    return false
  }

  // While PHP requires the nowdoc end tag to be the very first on a new line,
  // there may be an arbitrary amount of whitespace before the closing token
  while iswspace(lexer.lookahead) {
    lexer.advance(false)
    has_consumed_content = true
  }
  let mut end_tag_matched = false
  let heredoc_tag = self.heredocs[self.heredocs.length() - 1].word
  for i in 0..<heredoc_tag.length() {
    if lexer.lookahead != heredoc_tag[i] {
      break
    }
    lexer.advance(false)
    has_consumed_content = true
    end_tag_matched = i == heredoc_tag.length() - 1 &&
      (
        iswspace(lexer.lookahead) ||
        lexer.lookahead == ';' ||
        lexer.lookahead == ',' ||
        lexer.lookahead == ')'
      )
  }
  if end_tag_matched {
    // There may be an arbitrary amount of white space after the end tag
    while iswspace(lexer.lookahead) &&
          lexer.lookahead != '\r' &&
          lexer.lookahead != '\n' {
      lexer.advance(false)
      has_consumed_content = true
    }

    // Return to allow the end tag parsing if we've encountered an end tag
    // at a valid position
    if lexer.lookahead == ';' ||
      lexer.lookahead == ',' ||
      lexer.lookahead == ')' ||
      lexer.lookahead == '\n' ||
      lexer.lookahead == '\r' {
      // , and ) is needed to support heredoc in function arguments
      return false
    }
  }
  for has_content = has_consumed_content; ; has_content = true {
    lexer.mark_end()
    match lexer.lookahead {
      '\n' | '\r' => return has_content
      _ => {
        if lexer.eof() {
          return false
        }
        lexer.advance(false)
      }
    }
  }
}

///|
fn PhpScanner::scan_encapsed_part_string(
  self : PhpScanner,
  lexer : @runtime.Lexer,
  is_after_variable : Bool,
  is_heredoc : Bool,
  is_execution_string : Bool,
) -> Bool {
  let mut has_consumed_content = false
  if is_heredoc && self.heredocs.length() > 0 {
    // While PHP requires the heredoc end tag to be the very first on a new
    // line, there may be an arbitrary amount of whitespace before the
    // closing token However, we should not consume \r or \n
    while iswspace(lexer.lookahead) &&
          lexer.lookahead != '\r' &&
          lexer.lookahead != '\n' {
      lexer.advance(false)
      has_consumed_content = true
    }
    let heredoc_tag = self.heredocs[self.heredocs.length() - 1].word
    let mut end_tag_matched = false
    for i in 0..<heredoc_tag.length() {
      if lexer.lookahead != heredoc_tag[i] {
        break
      }
      has_consumed_content = true
      lexer.advance(false)
      end_tag_matched = i == heredoc_tag.length() - 1 &&
        (
          iswspace(lexer.lookahead) ||
          lexer.lookahead == ';' ||
          lexer.lookahead == ',' ||
          lexer.lookahead == ')'
        )
    }
    if end_tag_matched {
      // There may be an arbitrary amount of white space after the end tag
      // However, we should not consume \r or \n
      while iswspace(lexer.lookahead) &&
            lexer.lookahead != '\r' &&
            lexer.lookahead != '\n' {
        lexer.advance(false)
        has_consumed_content = true
      }

      // Return to allow the end tag parsing if we've encountered an end
      // tag at a valid position
      if lexer.lookahead == ';' ||
        lexer.lookahead == ',' ||
        lexer.lookahead == ')' ||
        lexer.lookahead == '\n' ||
        lexer.lookahead == '\r' {
        // , and ) is needed to support heredoc in function arguments
        return false
      }
    }
  }
  let mut is_after_variable = is_after_variable
  for has_content = has_consumed_content; ; has_content = true {
    lexer.mark_end()
    // A C `break` out of the switch is the end of the match arm here.
    match lexer.lookahead {
      '"' => {
        if !is_heredoc && !is_execution_string {
          return has_content
        }
        lexer.advance(false)
      }
      '`' => {
        if is_execution_string {
          return has_content
        }
        lexer.advance(false)
      }
      '\n' | '\r' => {
        if is_heredoc {
          return has_content
        }
        lexer.advance(false)
      }
      '\\' => {
        lexer.advance(false)

        // \{ should not be interpreted as an escape sequence, but both
        // should be consumed as normal characters
        if lexer.lookahead == '{' {
          lexer.advance(false)
        } else if is_execution_string && lexer.lookahead == '`' {
          return has_content
        } else if is_heredoc && lexer.lookahead == '\\' {
          lexer.advance(false)
        } else if php_is_escapable_sequence(lexer) {
          return has_content
        }
      }
      '$' => {
        lexer.advance(false)
        if (php_is_valid_name_char(lexer) && !iswdigit(lexer.lookahead)) ||
          lexer.lookahead == '{' {
          return has_content
        }
      }
      '-' if is_after_variable => {
        lexer.advance(false)
        if lexer.lookahead == '>' {
          lexer.advance(false)
          if php_is_valid_name_char(lexer) {
            return has_content
          }
        }
      }
      // `case '-'` without `is_after_variable` falls through to `case '['`.
      '-' | '[' => {
        if is_after_variable {
          return has_content
        }
        lexer.advance(false)
      }
      '{' => {
        lexer.advance(false)
        if lexer.lookahead == '$' {
          return has_content
        }
      }
      _ => {
        if lexer.eof() {
          return false
        }
        lexer.advance(false)
      }
    }
    is_after_variable = false
  }
}

///|
fn PhpScanner::scan(
  self : PhpScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  let is_error_recovery = valid_symbols[PHP_SENTINEL_ERROR]
  if is_error_recovery {
    return false
  }
  self.has_leading_whitespace = false
  lexer.mark_end()
  if valid_symbols[PHP_ENCAPSED_STRING_CHARS_AFTER_VARIABLE] {
    lexer.result_symbol = PHP_ENCAPSED_STRING_CHARS_AFTER_VARIABLE
    return self.scan_encapsed_part_string(
      lexer, true, // is_after_variable
       false, // is_heredoc
       false, // is_execution_string
    )
  }
  if valid_symbols[PHP_ENCAPSED_STRING_CHARS] {
    lexer.result_symbol = PHP_ENCAPSED_STRING_CHARS
    return self.scan_encapsed_part_string(
      lexer, false, // is_after_variable
       false, // is_heredoc
       false, // is_execution_string
    )
  }
  if valid_symbols[PHP_EXECUTION_STRING_CHARS_AFTER_VARIABLE] {
    lexer.result_symbol = PHP_EXECUTION_STRING_CHARS_AFTER_VARIABLE
    return self.scan_encapsed_part_string(
      lexer, true, // is_after_variable
       false, // is_heredoc
       true, // is_execution_string
    )
  }
  if valid_symbols[PHP_EXECUTION_STRING_CHARS] {
    lexer.result_symbol = PHP_EXECUTION_STRING_CHARS
    return self.scan_encapsed_part_string(
      lexer, false, // is_after_variable
       false, // is_heredoc
       true, // is_execution_string
    )
  }
  if valid_symbols[PHP_ENCAPSED_STRING_CHARS_AFTER_VARIABLE_HEREDOC] {
    lexer.result_symbol = PHP_ENCAPSED_STRING_CHARS_AFTER_VARIABLE_HEREDOC
    return self.scan_encapsed_part_string(
      lexer, true, // is_after_variable
       true, // is_heredoc
       false, // is_execution_string
    )
  }
  if valid_symbols[PHP_ENCAPSED_STRING_CHARS_HEREDOC] {
    lexer.result_symbol = PHP_ENCAPSED_STRING_CHARS_HEREDOC
    return self.scan_encapsed_part_string(
      lexer, false, // is_after_variable
       true, // is_heredoc
       false, // is_execution_string
    )
  }
  if valid_symbols[PHP_NOWDOC_STRING] {
    lexer.result_symbol = PHP_NOWDOC_STRING
    return self.scan_nowdoc_string(lexer)
  }
  if valid_symbols[PHP_HEREDOC_END] {
    lexer.result_symbol = PHP_HEREDOC_END
    if self.heredocs.length() == 0 {
      return false
    }
    let heredoc = self.heredocs[self.heredocs.length() - 1]
    while iswspace(lexer.lookahead) {
      lexer.advance(true)
    }
    let word = php_scan_heredoc_word(lexer)
    if !php_string_eq(word, heredoc.word) {
      return false
    }
    lexer.mark_end()
    ignore(self.heredocs.pop())
    return true
  }
  if !php_scan_whitespace(lexer) {
    return false
  }
  if valid_symbols[PHP_EOF_TOKEN] && lexer.eof() {
    lexer.result_symbol = PHP_EOF_TOKEN
    return true
  }
  if valid_symbols[PHP_HEREDOC_START] {
    lexer.result_symbol = PHP_HEREDOC_START
    let heredoc = php_heredoc_new()
    while iswspace(lexer.lookahead) {
      lexer.advance(true)
    }
    heredoc.word = php_scan_heredoc_word(lexer)
    if heredoc.word.length() == 0 {
      return false
    }
    lexer.mark_end()
    self.heredocs.push(heredoc)
    return true
  }
  if valid_symbols[PHP_AUTOMATIC_SEMICOLON] {
    lexer.result_symbol = PHP_AUTOMATIC_SEMICOLON
    if lexer.lookahead != '?' {
      return false
    }
    lexer.advance(false)
    return lexer.lookahead == '>'
  }
  false
}

///|
/// `external_scanner_create` and the other `external_scanner_*` wrappers.
fn php_external_scanner() -> @runtime.ExternalScanner {
  let scanner : PhpScanner = { has_leading_whitespace: false, heredocs: [], }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => scanner.heredocs.clear(),
  }
}
