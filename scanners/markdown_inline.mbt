// Port of tree-sitter-markdown tree-sitter-markdown-inline/src/scanner.c
// (v0.5.4).
// tree-sitter-markdown is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`. For explanation of the tokens see grammar.js
const MDI_ERROR : Int32 = 0

///|
const MDI_TRIGGER_ERROR : Int32 = 1

///|
const MDI_CODE_SPAN_START : Int32 = 2

///|
const MDI_CODE_SPAN_CLOSE : Int32 = 3

///|
const MDI_EMPHASIS_OPEN_STAR : Int32 = 4

///|
const MDI_EMPHASIS_OPEN_UNDERSCORE : Int32 = 5

///|
const MDI_EMPHASIS_CLOSE_STAR : Int32 = 6

///|
const MDI_EMPHASIS_CLOSE_UNDERSCORE : Int32 = 7

///|
const MDI_LAST_TOKEN_WHITESPACE : Int32 = 8

///|
const MDI_LAST_TOKEN_PUNCTUATION : Int32 = 9

///|
const MDI_STRIKETHROUGH_OPEN : Int32 = 10

///|
const MDI_STRIKETHROUGH_CLOSE : Int32 = 11

///|
const MDI_LATEX_SPAN_START : Int32 = 12

///|
const MDI_LATEX_SPAN_CLOSE : Int32 = 13

///|
const MDI_UNCLOSED_SPAN : Int32 = 14

///|
/// Determines if a character is punctuation as defined by the markdown spec.
fn mdi_is_punctuation(chr : Int32) -> Bool {
  (chr >= '!' && chr <= '/') ||
  (chr >= ':' && chr <= '@') ||
  (chr >= '[' && chr <= '`') ||
  (chr >= '{' && chr <= '~')
}

// State bitflags used with `Scanner.state`

// TODO: `STATE_EMPHASIS_DELIMITER_MOD_3 = 0x3` is unused upstream.

///|
/// Current delimiter run is opening
const MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN : Int32 = 0x1 << 2

///|
/// Convenience function to emit the error token. This is done to stop invalid
/// parse branches. Specifically:
/// 1. When encountering a newline after a line break that ended a paragraph,
///    and no new block has been opened.
/// 2. When encountering a new block after a soft line break.
/// 3. When a `$._trigger_error` token is valid, which is used to stop parse
///    branches through normal tree-sitter grammar rules.
///
/// See also the `$._soft_line_break` and `$._paragraph_end_newline` tokens in
/// grammar.js
fn mdi_error(lexer : @runtime.Lexer) -> Bool {
  lexer.result_symbol = MDI_ERROR
  true
}

///|
/// The `uint8_t` fields hold values in 0..=255.
priv struct MdiScanner {
  /// Parser state flags
  mut state : Int32
  mut code_span_delimiter_length : Int32
  mut latex_span_delimiter_length : Int32
  /// The number of characters remaining in the currrent emphasis delimiter
  /// run.
  mut num_emphasis_delimiters_left : Int32
}

///|
/// Write the whole state of a Scanner to a byte buffer
fn MdiScanner::serialize(self : MdiScanner, buffer : FixedArray[Byte]) -> Int32 {
  let mut size = 0
  buffer[size] = self.state.to_byte()
  size += 1
  buffer[size] = self.code_span_delimiter_length.to_byte()
  size += 1
  buffer[size] = self.latex_span_delimiter_length.to_byte()
  size += 1
  buffer[size] = self.num_emphasis_delimiters_left.to_byte()
  size += 1
  size
}

///|
/// Read the whole state of a Scanner from a byte buffer
/// `serizalize` and `deserialize` should be fully symmetric.
fn MdiScanner::deserialize(self : MdiScanner, buffer : BytesView) -> Unit {
  self.state = 0
  self.code_span_delimiter_length = 0
  self.latex_span_delimiter_length = 0
  self.num_emphasis_delimiters_left = 0
  if buffer.length() > 0 {
    let mut size = 0
    self.state = buffer[size].to_int()
    size += 1
    self.code_span_delimiter_length = buffer[size].to_int()
    size += 1
    self.latex_span_delimiter_length = buffer[size].to_int()
    size += 1
    self.num_emphasis_delimiters_left = buffer[size].to_int()
  }
}

///|
/// `delimiter_length` is the `uint8_t *` argument: it is read and written
/// through `get_length`/`set_length`.
fn mdi_parse_leaf_delimiter(
  lexer : @runtime.Lexer,
  get_length : () -> Int32,
  set_length : (Int32) -> Unit,
  valid_symbols : ArrayView[Bool],
  delimiter : Int32,
  open_token : Int32,
  close_token : Int32,
) -> Bool {
  // `uint8_t level`.
  let mut level = 0
  while lexer.lookahead == delimiter {
    lexer.advance(false)
    level = (level + 1) & 0xFF
  }
  lexer.mark_end()
  if level == get_length() && valid_symbols[close_token] {
    set_length(0)
    lexer.result_symbol = close_token
    return true
  }
  if valid_symbols[open_token] {
    // Parse ahead to check if there is a closing delimiter
    let mut close_level = 0
    while !lexer.eof() {
      if lexer.lookahead == delimiter {
        close_level += 1
      } else {
        if close_level == level {
          // Found a matching delimiter
          break
        }
        close_level = 0
      }
      lexer.advance(false)
    }
    if close_level == level {
      set_length(level)
      lexer.result_symbol = open_token
      return true
    }
    if valid_symbols[MDI_UNCLOSED_SPAN] {
      lexer.result_symbol = MDI_UNCLOSED_SPAN
      return true
    }
  }
  false
}

///|
fn MdiScanner::parse_backtick(
  self : MdiScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  mdi_parse_leaf_delimiter(
    lexer,
    () => self.code_span_delimiter_length,
    v => self.code_span_delimiter_length = v,
    valid_symbols,
    '`',
    MDI_CODE_SPAN_START,
    MDI_CODE_SPAN_CLOSE,
  )
}

///|
fn MdiScanner::parse_dollar(
  self : MdiScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  mdi_parse_leaf_delimiter(
    lexer,
    () => self.latex_span_delimiter_length,
    v => self.latex_span_delimiter_length = v,
    valid_symbols,
    '$',
    MDI_LATEX_SPAN_START,
    MDI_LATEX_SPAN_CLOSE,
  )
}

///|
fn MdiScanner::parse_star(
  self : MdiScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  lexer.advance(false)
  // If `num_emphasis_delimiters_left` is not zero then we already decided
  // that this should be part of an emphasis delimiter run, so interpret it as
  // such.
  if self.num_emphasis_delimiters_left > 0 {
    // The `STATE_EMPHASIS_DELIMITER_IS_OPEN` state flag tells us wether it
    // should be open or close.
    if (self.state & MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN) != 0 &&
      valid_symbols[MDI_EMPHASIS_OPEN_STAR] {
      self.state = self.state & (MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN ^ 0xFF)
      lexer.result_symbol = MDI_EMPHASIS_OPEN_STAR
      self.num_emphasis_delimiters_left -= 1
      return true
    }
    if valid_symbols[MDI_EMPHASIS_CLOSE_STAR] {
      lexer.result_symbol = MDI_EMPHASIS_CLOSE_STAR
      self.num_emphasis_delimiters_left -= 1
      return true
    }
  }
  lexer.mark_end()
  // Otherwise count the number of stars
  // `uint8_t star_count`.
  let mut star_count = 1
  while lexer.lookahead == '*' {
    star_count = (star_count + 1) & 0xFF
    lexer.advance(false)
  }
  let line_end = lexer.lookahead == '\n' ||
    lexer.lookahead == '\r' ||
    lexer.eof()
  if valid_symbols[MDI_EMPHASIS_OPEN_STAR] ||
    valid_symbols[MDI_EMPHASIS_CLOSE_STAR] {
    // The desicion made for the first star also counts for all the
    // following stars in the delimiter run. Rembemer how many there are.
    self.num_emphasis_delimiters_left = (star_count - 1) & 0xFF
    // Look ahead to the next symbol (after the last star) to find out if it
    // is whitespace punctuation or other.
    let next_symbol_whitespace = line_end ||
      lexer.lookahead == ' ' ||
      lexer.lookahead == '\t'
    let next_symbol_punctuation = mdi_is_punctuation(lexer.lookahead)
    // Information about the last token is in valid_symbols. See grammar.js
    // for these tokens for how this is done.
    if valid_symbols[MDI_EMPHASIS_CLOSE_STAR] &&
      !valid_symbols[MDI_LAST_TOKEN_WHITESPACE] &&
      (
        !valid_symbols[MDI_LAST_TOKEN_PUNCTUATION] ||
        next_symbol_punctuation ||
        next_symbol_whitespace
      ) {
      // Closing delimiters take precedence
      self.state = self.state & (MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN ^ 0xFF)
      lexer.result_symbol = MDI_EMPHASIS_CLOSE_STAR
      return true
    }
    if !next_symbol_whitespace &&
      (
        !next_symbol_punctuation ||
        valid_symbols[MDI_LAST_TOKEN_PUNCTUATION] ||
        valid_symbols[MDI_LAST_TOKEN_WHITESPACE]
      ) {
      self.state = self.state | MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN
      lexer.result_symbol = MDI_EMPHASIS_OPEN_STAR
      return true
    }
  }
  false
}

///|
fn MdiScanner::parse_tilde(
  self : MdiScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  lexer.advance(false)
  // If `num_emphasis_delimiters_left` is not zero then we already decided
  // that this should be part of an emphasis delimiter run, so interpret it as
  // such.
  if self.num_emphasis_delimiters_left > 0 {
    // The `STATE_EMPHASIS_DELIMITER_IS_OPEN` state flag tells us wether it
    // should be open or close.
    if (self.state & MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN) != 0 &&
      valid_symbols[MDI_STRIKETHROUGH_OPEN] {
      self.state = self.state & (MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN ^ 0xFF)
      lexer.result_symbol = MDI_STRIKETHROUGH_OPEN
      self.num_emphasis_delimiters_left -= 1
      return true
    }
    if valid_symbols[MDI_STRIKETHROUGH_CLOSE] {
      lexer.result_symbol = MDI_STRIKETHROUGH_CLOSE
      self.num_emphasis_delimiters_left -= 1
      return true
    }
  }
  lexer.mark_end()
  // Otherwise count the number of tildes
  // `uint8_t star_count`.
  let mut star_count = 1
  while lexer.lookahead == '~' {
    star_count = (star_count + 1) & 0xFF
    lexer.advance(false)
  }
  let line_end = lexer.lookahead == '\n' ||
    lexer.lookahead == '\r' ||
    lexer.eof()
  if valid_symbols[MDI_STRIKETHROUGH_OPEN] ||
    valid_symbols[MDI_STRIKETHROUGH_CLOSE] {
    // The desicion made for the first star also counts for all the
    // following stars in the delimiter run. Rembemer how many there are.
    self.num_emphasis_delimiters_left = (star_count - 1) & 0xFF
    // Look ahead to the next symbol (after the last star) to find out if it
    // is whitespace punctuation or other.
    let next_symbol_whitespace = line_end ||
      lexer.lookahead == ' ' ||
      lexer.lookahead == '\t'
    let next_symbol_punctuation = mdi_is_punctuation(lexer.lookahead)
    // Information about the last token is in valid_symbols. See grammar.js
    // for these tokens for how this is done.
    if valid_symbols[MDI_STRIKETHROUGH_CLOSE] &&
      !valid_symbols[MDI_LAST_TOKEN_WHITESPACE] &&
      (
        !valid_symbols[MDI_LAST_TOKEN_PUNCTUATION] ||
        next_symbol_punctuation ||
        next_symbol_whitespace
      ) {
      // Closing delimiters take precedence
      self.state = self.state & (MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN ^ 0xFF)
      lexer.result_symbol = MDI_STRIKETHROUGH_CLOSE
      return true
    }
    if !next_symbol_whitespace &&
      (
        !next_symbol_punctuation ||
        valid_symbols[MDI_LAST_TOKEN_PUNCTUATION] ||
        valid_symbols[MDI_LAST_TOKEN_WHITESPACE]
      ) {
      self.state = self.state | MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN
      lexer.result_symbol = MDI_STRIKETHROUGH_OPEN
      return true
    }
  }
  false
}

///|
fn MdiScanner::parse_underscore(
  self : MdiScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  lexer.advance(false)
  // If `num_emphasis_delimiters_left` is not zero then we already decided
  // that this should be part of an emphasis delimiter run, so interpret it as
  // such.
  if self.num_emphasis_delimiters_left > 0 {
    // The `STATE_EMPHASIS_DELIMITER_IS_OPEN` state flag tells us wether it
    // should be open or close.
    if (self.state & MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN) != 0 &&
      valid_symbols[MDI_EMPHASIS_OPEN_UNDERSCORE] {
      self.state = self.state & (MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN ^ 0xFF)
      lexer.result_symbol = MDI_EMPHASIS_OPEN_UNDERSCORE
      self.num_emphasis_delimiters_left -= 1
      return true
    }
    if valid_symbols[MDI_EMPHASIS_CLOSE_UNDERSCORE] {
      lexer.result_symbol = MDI_EMPHASIS_CLOSE_UNDERSCORE
      self.num_emphasis_delimiters_left -= 1
      return true
    }
  }
  lexer.mark_end()
  // Otherwise count the number of stars
  // `uint8_t underscore_count`.
  let mut underscore_count = 1
  while lexer.lookahead == '_' {
    underscore_count = (underscore_count + 1) & 0xFF
    lexer.advance(false)
  }
  let line_end = lexer.lookahead == '\n' ||
    lexer.lookahead == '\r' ||
    lexer.eof()
  if valid_symbols[MDI_EMPHASIS_OPEN_UNDERSCORE] ||
    valid_symbols[MDI_EMPHASIS_CLOSE_UNDERSCORE] {
    // The desicion made for the first underscore also counts for all the
    // following underscores in the delimiter run. Rembemer how many there are.
    self.num_emphasis_delimiters_left = (underscore_count - 1) & 0xFF
    // Look ahead to the next symbol (after the last underscore) to find out if it
    // is whitespace punctuation or other.
    let next_symbol_whitespace = line_end ||
      lexer.lookahead == ' ' ||
      lexer.lookahead == '\t'
    let next_symbol_punctuation = mdi_is_punctuation(lexer.lookahead)
    // Information about the last token is in valid_symbols. See grammar.js
    // for these tokens for how this is done.
    if valid_symbols[MDI_EMPHASIS_CLOSE_UNDERSCORE] &&
      !valid_symbols[MDI_LAST_TOKEN_WHITESPACE] &&
      (
        !valid_symbols[MDI_LAST_TOKEN_PUNCTUATION] ||
        next_symbol_punctuation ||
        next_symbol_whitespace
      ) {
      // Closing delimiters take precedence
      self.state = self.state & (MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN ^ 0xFF)
      lexer.result_symbol = MDI_EMPHASIS_CLOSE_UNDERSCORE
      return true
    }
    if !next_symbol_whitespace &&
      (
        !next_symbol_punctuation ||
        valid_symbols[MDI_LAST_TOKEN_PUNCTUATION] ||
        valid_symbols[MDI_LAST_TOKEN_WHITESPACE]
      ) {
      self.state = self.state | MDI_STATE_EMPHASIS_DELIMITER_IS_OPEN
      lexer.result_symbol = MDI_EMPHASIS_OPEN_UNDERSCORE
      return true
    }
  }
  false
}

///|
fn MdiScanner::scan(
  self : MdiScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  // A normal tree-sitter rule decided that the current branch is invalid and
  // now "requests" an error to stop the branch
  if valid_symbols[MDI_TRIGGER_ERROR] {
    return mdi_error(lexer)
  }
  // Decide which tokens to consider based on the first non-whitespace
  // character
  match lexer.lookahead {
    // A backtick could mark the beginning or ending of a code span or a
    // fenced code block.
    '`' => self.parse_backtick(lexer, valid_symbols)
    '$' => self.parse_dollar(lexer, valid_symbols)
    // A star could either mark the beginning or ending of emphasis, a
    // list item or thematic break. This code is similar to the code for
    // '_' and '+'.
    '*' => self.parse_star(lexer, valid_symbols)
    '_' => self.parse_underscore(lexer, valid_symbols)
    '~' => self.parse_tilde(lexer, valid_symbols)
    _ => false
  }
}

///|
fn markdown_inline_scanner() -> @runtime.ExternalScanner {
  let scanner : MdiScanner = {
    state: 0,
    code_span_delimiter_length: 0,
    latex_span_delimiter_length: 0,
    num_emphasis_delimiters_left: 0,
  }
  scanner.deserialize(b""[:])
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => (),
  }
}
