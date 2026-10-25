// Port of tree-sitter-css src/scanner.c (v0.25.0)
// tree-sitter-css is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`.
const CSS_DESCENDANT_OP : Int32 = 0

///|
const CSS_PSEUDO_CLASS_SELECTOR_COLON : Int32 = 1

///|
const CSS_ERROR_RECOVERY : Int32 = 2

///|
fn css_scan(lexer : @runtime.Lexer, valid_symbols : ArrayView[Bool]) -> Bool {
  if valid_symbols[CSS_ERROR_RECOVERY] {
    return false
  }
  if iswspace(lexer.lookahead) && valid_symbols[CSS_DESCENDANT_OP] {
    lexer.result_symbol = CSS_DESCENDANT_OP
    lexer.advance(true)
    while iswspace(lexer.lookahead) {
      lexer.advance(true)
    }
    lexer.mark_end()
    if lexer.lookahead == '#' ||
      lexer.lookahead == '.' ||
      lexer.lookahead == '[' ||
      lexer.lookahead == '-' ||
      lexer.lookahead == '*' ||
      iswalnum(lexer.lookahead) {
      return true
    }
    if lexer.lookahead == ':' {
      lexer.advance(false)
      if iswspace(lexer.lookahead) {
        return false
      }
      for ;; {
        if lexer.lookahead == ';' || lexer.lookahead == '}' || lexer.eof() {
          return false
        }
        if lexer.lookahead == '{' {
          return true
        }
        lexer.advance(false)
      }
    }
  }
  if valid_symbols[CSS_PSEUDO_CLASS_SELECTOR_COLON] {
    while iswspace(lexer.lookahead) {
      lexer.advance(true)
    }
    if lexer.lookahead == ':' {
      lexer.advance(false)
      if lexer.lookahead == ':' {
        return false
      }
      lexer.mark_end()
      lexer.result_symbol = CSS_PSEUDO_CLASS_SELECTOR_COLON

      // We need a `{` to be a pseudo class selector, a `;` indicates a property.
      // This does not apply if we're in a comment, however.
      let mut in_comment = false
      while lexer.lookahead != ';' && lexer.lookahead != '}' && !lexer.eof() {
        lexer.advance(false)
        if lexer.lookahead == '{' && !in_comment {
          return true
        }
        if lexer.lookahead == '/' && !in_comment {
          lexer.advance(false)
          if lexer.lookahead == '*' {
            in_comment = true
          }
        } else if lexer.lookahead == '*' && in_comment {
          lexer.advance(false)
          if lexer.lookahead == '/' {
            in_comment = false
          }
        }
      }

      // If we're at eof, and we happened to *not* find an opening brace to indicate we have a pseudo class
      // selector, we should *still* return one at EOF. This will improve error recovery, and the malformed code
      // can be parsed as an erroneous pseudo-class selector, rather than an erroneous property.
      return lexer.eof()
    }
  }
  false
}

///|
fn css_scanner() -> @runtime.ExternalScanner {
  {
    scan: (lexer, valid_symbols) => css_scan(lexer, valid_symbols),
    serialize: _ => 0,
    deserialize: _ => (),
    destroy: () => (),
  }
}
