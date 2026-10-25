// Ports of the scanner.c files of upstream's test/fixtures/test_grammars
// (tree-sitter 0.28.0, pinned at 4a412a01a0147d0f50bf7e749572fa632d1ab203;
// these grammars are part of the tree-sitter repository and have no separate
// version in test/fixtures/fixtures.json). The stateful scanners are in
// test_grammars_stateful.mbt.
//
// Each C scanner whose `create` returns NULL becomes a stateless scanner
// object whose `serialize` returns the C return value without writing.

///|
/// The external scanner of the test grammar named `name`, if it has one.
fn test_grammar_scanner(name : String) -> @runtime.ExternalScannerFactory? {
  match name {
    "depends_on_column" => Some(depends_on_column_scanner)
    "depends_on_column_failed_scan" =>
      Some(depends_on_column_failed_scan_scanner)
    "depends_on_column_repetition" => Some(depends_on_column_repetition_scanner)
    "epsilon_external_extra_tokens" =>
      Some(epsilon_external_extra_tokens_scanner)
    "epsilon_external_tokens" => Some(epsilon_external_tokens_scanner)
    "external_and_internal_anonymous_tokens" =>
      Some(external_and_internal_anonymous_tokens_scanner)
    "external_and_internal_tokens" => Some(external_and_internal_tokens_scanner)
    "external_extra_tokens" => Some(external_extra_tokens_scanner)
    "external_lookahead_eof_boundary" =>
      Some(external_lookahead_eof_boundary_scanner)
    "external_tokens" => Some(external_tokens_scanner)
    "external_unicode_column_alignment" =>
      Some(external_unicode_column_alignment_scanner)
    "external_word_token" => Some(external_word_token_scanner)
    "get_col_eof" => Some(get_col_eof_scanner)
    "get_col_should_hang_not_crash" =>
      Some(get_col_should_hang_not_crash_scanner)
    "inverted_external_token" => Some(inverted_external_token_scanner)
    "uses_current_column" => Some(uses_current_column_scanner)
    "utf16_surrogate_oob" => Some(utf16_surrogate_oob_scanner)
    "wasm_realloc_clobber_region" => Some(wasm_realloc_clobber_region_scanner)
    "wasm_realloc_overflow_heap" => Some(wasm_realloc_overflow_heap_scanner)
    _ => None
  }
}

///|
/// A scanner whose payload is NULL and whose `serialize` returns
/// `serialized_length` without writing to the buffer.
fn stateless_test_scanner(
  scan : (@runtime.Lexer, ArrayView[Bool]) -> Bool,
  serialized_length~ : Int32 = 0,
) -> @runtime.ExternalScanner {
  {
    scan,
    serialize: _ => serialized_length,
    deserialize: _ => (),
    destroy: () => (),
  }
}

// --- depends_on_column/scanner.c ---

///|
/// `enum TokenType { ODD_COLUMN, EVEN_COLUMN }`. The scanner is stateless.
fn depends_on_column_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, _valid_symbols) => {
    lexer.result_symbol = if lexer.get_column() % 2 != 0 { 0 } else { 1 }
    true
  })
}

// --- depends_on_column_failed_scan/scanner.c ---

///|
/// `enum TokenType { HEAD }`.
fn depends_on_column_failed_scan_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, _valid_symbols) => {
    if lexer.lookahead != 'x' || lexer.get_column() != 0 {
      return false
    }
    lexer.result_symbol = 0
    lexer.advance(false)
    true
  })
}

// --- depends_on_column_repetition/scanner.c ---

///|
/// `enum TokenType { HEAD, TAIL }`.
fn depends_on_column_repetition_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, _valid_symbols) => {
    if lexer.lookahead != 'x' {
      return false
    }
    lexer.result_symbol = if lexer.get_column() == 0 { 0 } else { 1 }
    lexer.advance(false)
    true
  })
}

// --- epsilon_external_extra_tokens/scanner.c ---

///|
/// `enum TokenType { COMMENT }`.
fn epsilon_external_extra_tokens_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, _valid_symbols) => {
    lexer.result_symbol = 0
    true
  })
}

// --- epsilon_external_tokens/scanner.c ---

///|
/// `enum TokenType { ZERO_WIDTH_TOKEN }`.
fn epsilon_external_tokens_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, _valid_symbols) => {
    lexer.result_symbol = 0
    true
  })
}

// --- external_and_internal_anonymous_tokens/scanner.c and
// --- external_and_internal_tokens/scanner.c (identical scan functions) ---

///|
/// `enum { STRING, LINE_BREAK }`.
fn external_and_internal_tokens_scan(
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  let string = 0
  let line_break = 1
  // If a line-break is a valid lookahead token, only skip spaces.
  if valid_symbols[line_break] {
    while lexer.lookahead == ' ' || lexer.lookahead == '\r' {
      lexer.advance(true)
    }
    if lexer.lookahead == '\n' {
      lexer.advance(false)
      lexer.result_symbol = line_break
      return true
    }
  }

  // If a line-break is not a valid lookahead token, skip line breaks as well
  // as spaces.
  if valid_symbols[string] {
    while lexer.lookahead == ' ' ||
          lexer.lookahead == '\r' ||
          lexer.lookahead == '\n' {
      lexer.advance(true)
    }
    if lexer.lookahead == '\'' {
      lexer.advance(false)
      while lexer.lookahead != '\'' {
        lexer.advance(false)
      }
      lexer.advance(false)
      lexer.result_symbol = string
      return true
    }
  }
  false
}

///|
fn external_and_internal_anonymous_tokens_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner(external_and_internal_tokens_scan)
}

///|
fn external_and_internal_tokens_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner(external_and_internal_tokens_scan)
}

// --- external_extra_tokens/scanner.c ---

///|
/// `enum { COMMENT }`.
fn external_extra_tokens_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, _valid_symbols) => {
    while lexer.lookahead == ' ' {
      lexer.advance(true)
    }
    if lexer.lookahead == '#' {
      lexer.advance(false)
      while lexer.lookahead != '\n' {
        lexer.advance(false)
      }
      lexer.result_symbol = 0
      return true
    }
    false
  })
}

// --- external_lookahead_eof_boundary/scanner.c ---

///|
/// `enum { OPEN_DELIM, CLOSE_DELIM, UNCLOSED_DELIM }`.
fn external_lookahead_eof_boundary_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, valid_symbols) => {
    let open_delim = 0
    let close_delim = 1
    let unclosed_delim = 2
    if lexer.lookahead != '`' {
      return false
    }
    lexer.advance(false)
    lexer.mark_end()

    // Mid-span: emit the closer.
    if valid_symbols[close_delim] {
      lexer.result_symbol = close_delim
      return true
    }

    // At an opener: peek past mark_end for a matching '`'. The eof()
    // probe makes the result depend on the current included ranges.
    if valid_symbols[open_delim] {
      while !lexer.eof() {
        if lexer.lookahead == '`' {
          lexer.result_symbol = open_delim
          return true
        }
        lexer.advance(false)
      }
      if valid_symbols[unclosed_delim] {
        lexer.result_symbol = unclosed_delim
        return true
      }
    }
    false
  })
}

// --- external_word_token/scanner.c ---

///|
fn external_word_token_is_word_char(c : Int32) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
/// `enum TokenType { IDENTIFIER }`.
fn external_word_token_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, valid_symbols) => {
    let identifier = 0
    if !valid_symbols[identifier] {
      return false
    }
    while lexer.lookahead == ' ' ||
          lexer.lookahead == '\t' ||
          lexer.lookahead == '\r' ||
          lexer.lookahead == '\n' {
      lexer.advance(true)
    }
    if !external_word_token_is_word_char(lexer.lookahead) {
      return false
    }
    while external_word_token_is_word_char(lexer.lookahead) {
      lexer.advance(false)
    }
    lexer.result_symbol = identifier
    true
  })
}

// --- get_col_eof/scanner.c ---

///|
/// `enum TokenType { CHAR }`.
fn get_col_eof_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, valid_symbols) => {
    let char = 0
    if lexer.eof() {
      return false
    }
    if valid_symbols[char] {
      lexer.advance(false)
      ignore(lexer.get_column())
      lexer.result_symbol = char
      lexer.mark_end()
      return true
    }
    false
  })
}

// --- get_col_should_hang_not_crash/scanner.c ---

///|
/// Loops forever by design.
fn get_col_should_hang_not_crash_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, _valid_symbols) => {
    for ;; {
      lexer.advance(false)
      ignore(lexer.get_column())
    }
  })
}

// --- inverted_external_token/scanner.c ---

///|
/// `enum { LINE_BREAK }`. Its `serialize` returns `true` (1) without writing,
/// so the serialized state is whatever byte the parser's buffer holds.
fn inverted_external_token_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner(serialized_length=1, (lexer, _valid_symbols) => {
    let line_break = 0
    while lexer.lookahead == ' ' || lexer.lookahead == '\r' {
      lexer.advance(true)
    }
    if lexer.lookahead == '\n' {
      lexer.advance(false)

      // Mark the end of the line break token.
      lexer.mark_end()

      // Skip whitespace *after* having marked the end.
      while lexer.lookahead == ' ' ||
            lexer.lookahead == '\n' ||
            lexer.lookahead == '\r' {
        lexer.advance(true)
      }
      if lexer.lookahead != '.' {
        lexer.result_symbol = line_break
        return true
      }
    }
    false
  })
}

// --- utf16_surrogate_oob/scanner.c ---

///|
/// `enum TokenType { SURROGATE, SUPPLEMENTARY }`.
fn utf16_surrogate_oob_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, valid_symbols) => {
    let surrogate = 0
    let supplementary = 1
    let c = lexer.lookahead

    // Raw surrogate code point (0xD800-0xDFFF): the decoder returned an unpaired
    // surrogate, which is what happens when a lead surrogate is at the end of a chunk.
    if c >= 0xD800 && c <= 0xDFFF && valid_symbols[surrogate] {
      lexer.advance(false)
      lexer.mark_end()
      lexer.result_symbol = surrogate
      return true
    }

    // Supplementary-plane character (>0xFFFF): the decoder formed a character from
    // a surrogate pair.
    if c > 0xFFFF && valid_symbols[supplementary] {
      lexer.advance(false)
      lexer.mark_end()
      lexer.result_symbol = supplementary
      return true
    }
    false
  })
}

// --- wasm_realloc_clobber_region/scanner.c ---

///|
/// `enum TokenType { ZERO_WIDTH_TOKEN }`. The C `create` exercises
/// malloc/realloc/free (checking a wasm allocator bug) and returns NULL; it
/// has no observable effect natively.
fn wasm_realloc_clobber_region_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, _valid_symbols) => {
    lexer.result_symbol = 0
    true
  })
}

// --- wasm_realloc_overflow_heap/scanner.c ---

///|
/// `enum TokenType { ZERO_WIDTH_TOKEN }`. The C `create` exercises
/// malloc/realloc/free and returns NULL; no observable effect natively.
fn wasm_realloc_overflow_heap_scanner() -> @runtime.ExternalScanner {
  stateless_test_scanner((lexer, _valid_symbols) => {
    lexer.result_symbol = 0
    true
  })
}
