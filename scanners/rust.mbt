// Port of the rust grammar's src/scanner.c (v0.24.0).

///|
const RUST_STRING_CONTENT : Int32 = 0

///|
const RUST_RAW_STRING_LITERAL_START : Int32 = 1

///|
const RUST_RAW_STRING_LITERAL_CONTENT : Int32 = 2

///|
const RUST_RAW_STRING_LITERAL_END : Int32 = 3

///|
const RUST_FLOAT_LITERAL : Int32 = 4

///|
const RUST_BLOCK_OUTER_DOC_MARKER : Int32 = 5

///|
const RUST_BLOCK_INNER_DOC_MARKER : Int32 = 6

///|
const RUST_BLOCK_COMMENT_CONTENT : Int32 = 7

///|
const RUST_LINE_DOC_CONTENT : Int32 = 8

///|
const RUST_ERROR_SENTINEL : Int32 = 9

///|
priv struct RustScanner {
  /// `uint8_t`.
  mut opening_hash_count : Byte
}

///|
fn rust_scanner() -> @runtime.ExternalScanner {
  let scanner : RustScanner = { opening_hash_count: 0, }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => {
      buffer[0] = scanner.opening_hash_count
      1
    },
    deserialize: buffer => {
      scanner.opening_hash_count = 0
      if buffer.length() == 1 {
        scanner.opening_hash_count = buffer[0]
      }
    },
    destroy: () => (),
  }
}

///|
fn rust_is_num_char(c : Int32) -> Bool {
  c == '_' || iswdigit(c)
}

///|
fn rust_process_string(lexer : @runtime.Lexer) -> Bool {
  let mut has_content = false
  for ;; {
    if lexer.lookahead == '"' || lexer.lookahead == '\\' {
      break
    }
    if lexer.eof() {
      return false
    }
    has_content = true
    lexer.advance(false)
  }
  lexer.result_symbol = RUST_STRING_CONTENT
  lexer.mark_end()
  has_content
}

///|
fn RustScanner::scan_raw_string_start(
  self : RustScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  if lexer.lookahead == 'b' || lexer.lookahead == 'c' {
    lexer.advance(false)
  }
  if lexer.lookahead != 'r' {
    return false
  }
  lexer.advance(false)
  let mut opening_hash_count : Byte = 0
  while lexer.lookahead == '#' {
    lexer.advance(false)
    // `uint8_t` increment wraps.
    opening_hash_count = opening_hash_count + 1
  }
  if lexer.lookahead != '"' {
    return false
  }
  lexer.advance(false)
  self.opening_hash_count = opening_hash_count
  lexer.result_symbol = RUST_RAW_STRING_LITERAL_START
  true
}

///|
fn RustScanner::scan_raw_string_content(
  self : RustScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  for ;; {
    if lexer.eof() {
      return false
    }
    if lexer.lookahead == '"' {
      lexer.mark_end()
      lexer.advance(false)
      let mut hash_count = 0
      while lexer.lookahead == '#' &&
            hash_count < self.opening_hash_count.to_int() {
        lexer.advance(false)
        hash_count += 1
      }
      if hash_count == self.opening_hash_count.to_int() {
        lexer.result_symbol = RUST_RAW_STRING_LITERAL_CONTENT
        return true
      }
    } else {
      lexer.advance(false)
    }
  }
}

///|
fn RustScanner::scan_raw_string_end(
  self : RustScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  lexer.advance(false)
  for _ in 0..<self.opening_hash_count.to_int() {
    lexer.advance(false)
  }
  lexer.result_symbol = RUST_RAW_STRING_LITERAL_END
  true
}

///|
fn rust_process_float_literal(lexer : @runtime.Lexer) -> Bool {
  lexer.result_symbol = RUST_FLOAT_LITERAL
  lexer.advance(false)
  while rust_is_num_char(lexer.lookahead) {
    lexer.advance(false)
  }
  let mut has_fraction = false
  let mut has_exponent = false
  if lexer.lookahead == '.' {
    has_fraction = true
    lexer.advance(false)
    if iswalpha(lexer.lookahead) {
      // The dot is followed by a letter: 1.max(2) => not a float but an integer
      return false
    }
    if lexer.lookahead == '.' {
      return false
    }
    while rust_is_num_char(lexer.lookahead) {
      lexer.advance(false)
    }
  }
  lexer.mark_end()
  if lexer.lookahead == 'e' || lexer.lookahead == 'E' {
    has_exponent = true
    lexer.advance(false)
    if lexer.lookahead == '+' || lexer.lookahead == '-' {
      lexer.advance(false)
    }
    if !rust_is_num_char(lexer.lookahead) {
      return true
    }
    lexer.advance(false)
    while rust_is_num_char(lexer.lookahead) {
      lexer.advance(false)
    }
    lexer.mark_end()
  }
  if !has_exponent && !has_fraction {
    return false
  }
  if lexer.lookahead != 'u' && lexer.lookahead != 'i' && lexer.lookahead != 'f' {
    return true
  }
  lexer.advance(false)
  if !iswdigit(lexer.lookahead) {
    return true
  }
  while iswdigit(lexer.lookahead) {
    lexer.advance(false)
  }
  lexer.mark_end()
  true
}

///|
fn rust_process_line_doc_content(lexer : @runtime.Lexer) -> Bool {
  lexer.result_symbol = RUST_LINE_DOC_CONTENT
  for ;; {
    if lexer.eof() {
      return true
    }
    if lexer.lookahead == '\n' {
      // Include the newline in the doc content node.
      // Line endings are useful for markdown injection.
      lexer.advance(false)
      return true
    }
    lexer.advance(false)
  }
}

///|
priv enum RustBlockCommentState {
  LeftForwardSlash
  LeftAsterisk
  Continuing
}

///|
priv struct RustBlockCommentProcessing {
  mut state : RustBlockCommentState
  /// `unsigned`.
  mut nesting_depth : UInt32
}

///|
fn rust_process_left_forward_slash(
  processing : RustBlockCommentProcessing,
  current : Int32,
) -> Unit {
  if current == '*' {
    processing.nesting_depth += 1
  }
  processing.state = Continuing
}

///|
fn rust_process_left_asterisk(
  processing : RustBlockCommentProcessing,
  current : Int32,
  lexer : @runtime.Lexer,
) -> Unit {
  if current == '*' {
    lexer.mark_end()
    processing.state = LeftAsterisk
    return
  }
  if current == '/' {
    processing.nesting_depth -= 1
  }
  processing.state = Continuing
}

///|
fn rust_process_continuing(
  processing : RustBlockCommentProcessing,
  current : Int32,
) -> Unit {
  match current {
    '/' => processing.state = LeftForwardSlash
    '*' => processing.state = LeftAsterisk
    _ => ()
  }
}

///|
fn rust_process_block_comment(
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  // `(char)lexer->lookahead`: only the low byte is kept, so comparisons
  // against ASCII characters match any code point with that low byte.
  let mut first = to_c_char(lexer.lookahead)
  // The first character is stored so we can safely advance inside
  // these if blocks. However, because we only store one, we can only
  // safely advance 1 time. Since there's a chance that an advance could
  // happen in one state, we must advance in all states to ensure that
  // the program ends up in a sane state prior to processing the block
  // comment if need be.
  if valid_symbols[RUST_BLOCK_INNER_DOC_MARKER] && first == '!' {
    lexer.result_symbol = RUST_BLOCK_INNER_DOC_MARKER
    lexer.advance(false)
    return true
  }
  if valid_symbols[RUST_BLOCK_OUTER_DOC_MARKER] && first == '*' {
    lexer.advance(false)
    lexer.mark_end()
    // If the next token is a / that means that it's an empty block comment.
    if lexer.lookahead == '/' {
      return false
    }
    // If the next token is a * that means that this isn't a BLOCK_OUTER_DOC_MARKER
    // as BLOCK_OUTER_DOC_MARKER's only have 2 * not 3 or more.
    if lexer.lookahead != '*' {
      lexer.result_symbol = RUST_BLOCK_OUTER_DOC_MARKER
      return true
    }
  } else {
    lexer.advance(false)
  }
  if valid_symbols[RUST_BLOCK_COMMENT_CONTENT] {
    let processing : RustBlockCommentProcessing = {
      state: Continuing,
      nesting_depth: 1,
    }
    // Manually set the current state based on the first character
    match first {
      '*' => {
        processing.state = LeftAsterisk
        if lexer.lookahead == '/' {
          // This case can happen in an empty doc block comment
          // like /*!*/. The comment has no contents, so bail.
          return false
        }
      }
      '/' => processing.state = LeftForwardSlash
      _ => processing.state = Continuing
    }

    // For the purposes of actually parsing rust code, this
    // is incorrect as it considers an unterminated block comment
    // to be an error. However, for the purposes of syntax highlighting
    // this should be considered successful as otherwise you are not able
    // to syntax highlight a block of code prior to closing the
    // block comment
    while !lexer.eof() && processing.nesting_depth != 0 {
      // Set first to the current lookahead as that is the second character
      // as we force an advance in the above code when we are checking if we
      // need to handle a block comment inner or outer doc comment signifier
      // node
      first = to_c_char(lexer.lookahead)
      match processing.state {
        LeftForwardSlash => rust_process_left_forward_slash(processing, first)
        LeftAsterisk => rust_process_left_asterisk(processing, first, lexer)
        Continuing => {
          lexer.mark_end()
          rust_process_continuing(processing, first)
        }
      }
      lexer.advance(false)
      if first == '/' && processing.nesting_depth != 0 {
        lexer.mark_end()
      }
    }
    lexer.result_symbol = RUST_BLOCK_COMMENT_CONTENT
    return true
  }
  false
}

///|
fn RustScanner::scan(
  self : RustScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  // The documentation states that if the lexical analysis fails for some reason
  // they will mark every state as valid and pass it to the external scanner
  // However, we can't do anything to help them recover in that case so we
  // should just fail.
  if valid_symbols[RUST_ERROR_SENTINEL] {
    return false
  }
  if valid_symbols[RUST_BLOCK_COMMENT_CONTENT] ||
    valid_symbols[RUST_BLOCK_INNER_DOC_MARKER] ||
    valid_symbols[RUST_BLOCK_OUTER_DOC_MARKER] {
    return rust_process_block_comment(lexer, valid_symbols)
  }
  if valid_symbols[RUST_STRING_CONTENT] && !valid_symbols[RUST_FLOAT_LITERAL] {
    return rust_process_string(lexer)
  }
  if valid_symbols[RUST_LINE_DOC_CONTENT] {
    return rust_process_line_doc_content(lexer)
  }
  while iswspace(lexer.lookahead) {
    lexer.advance(true)
  }
  if valid_symbols[RUST_RAW_STRING_LITERAL_START] &&
    (lexer.lookahead == 'r' || lexer.lookahead == 'b' || lexer.lookahead == 'c') {
    return self.scan_raw_string_start(lexer)
  }
  if valid_symbols[RUST_RAW_STRING_LITERAL_CONTENT] {
    return self.scan_raw_string_content(lexer)
  }
  if valid_symbols[RUST_RAW_STRING_LITERAL_END] && lexer.lookahead == '"' {
    return self.scan_raw_string_end(lexer)
  }
  if valid_symbols[RUST_FLOAT_LITERAL] && iswdigit(lexer.lookahead) {
    return rust_process_float_literal(lexer)
  }
  false
}
