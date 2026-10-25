// Port of tree-sitter-toml src/scanner.c (v0.7.0)
// tree-sitter-toml is distributed under the MIT license (see NOTICE).

///|
/// `TokenType`.
const TOML_LINE_ENDING_OR_EOF : Int32 = 0

///|
const TOML_MULTILINE_BASIC_STRING_CONTENT : Int32 = 1

///|
const TOML_MULTILINE_BASIC_STRING_END : Int32 = 2

///|
const TOML_MULTILINE_LITERAL_STRING_CONTENT : Int32 = 3

///|
const TOML_MULTILINE_LITERAL_STRING_END : Int32 = 4

///|
/// `tree_sitter_toml_external_scanner_scan_multiline_string_end`.
fn toml_scan_multiline_string_end(
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
  delimiter : Int32,
  content_symbol : Int32,
  end_symbol : Int32,
) -> Bool {
  if !valid_symbols[end_symbol] || lexer.lookahead != delimiter {
    return false
  }
  lexer.advance(false)
  lexer.mark_end()
  if lexer.lookahead != delimiter {
    lexer.result_symbol = content_symbol
    return true
  }
  lexer.advance(false)
  if lexer.lookahead != delimiter {
    lexer.mark_end()
    lexer.result_symbol = content_symbol
    return true
  }
  lexer.advance(false)
  if lexer.lookahead != delimiter {
    lexer.mark_end()
    lexer.result_symbol = end_symbol
    return true
  }
  lexer.result_symbol = content_symbol
  true
}

///|
fn toml_scan(lexer : @runtime.Lexer, valid_symbols : ArrayView[Bool]) -> Bool {
  if toml_scan_multiline_string_end(
      lexer,
      valid_symbols,
      '"',
      TOML_MULTILINE_BASIC_STRING_CONTENT,
      TOML_MULTILINE_BASIC_STRING_END,
    ) ||
    toml_scan_multiline_string_end(
      lexer,
      valid_symbols,
      '\'',
      TOML_MULTILINE_LITERAL_STRING_CONTENT,
      TOML_MULTILINE_LITERAL_STRING_END,
    ) {
    return true
  }
  if valid_symbols[TOML_LINE_ENDING_OR_EOF] {
    lexer.result_symbol = TOML_LINE_ENDING_OR_EOF
    while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      lexer.advance(true)
    }
    if lexer.lookahead == 0 || lexer.lookahead == '\n' {
      return true
    }
    if lexer.lookahead == '\r' {
      lexer.advance(true)
      if lexer.lookahead == '\n' {
        return true
      }
    }
  }
  false
}

///|
fn toml_scanner() -> @runtime.ExternalScanner {
  {
    scan: (lexer, valid_symbols) => toml_scan(lexer, valid_symbols),
    serialize: _ => 0,
    deserialize: _ => (),
    destroy: () => (),
  }
}
