// Port of tree-sitter-jsdoc src/scanner.c (v0.23.2)
// tree-sitter-jsdoc is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`.
const JSDOC_TYPE_TOKEN : Int32 = 0

///|
/// Scan to the next balanced `}` character.
fn jsdoc_scan_for_type(lexer : @runtime.Lexer) -> Bool {
  let mut stack = 0
  while true {
    if lexer.eof() {
      return false
    }
    match lexer.lookahead {
      '{' => stack += 1
      '}' => {
        stack -= 1
        if stack == -1 {
          return true
        }
      }
      '\n' | '\u{0}' =>
        // Something's gone wrong.
        return false
      _ => ()
    }
    lexer.advance(false)
  }
  false
}

///|
fn jsdoc_scanner() -> @runtime.ExternalScanner {
  {
    scan: (lexer, valid_symbols) => {
      if valid_symbols[JSDOC_TYPE_TOKEN] && jsdoc_scan_for_type(lexer) {
        lexer.result_symbol = JSDOC_TYPE_TOKEN
        lexer.mark_end()
        return true
      }
      false
    },
    serialize: _ => 0,
    deserialize: _ => (),
    destroy: () => (),
  }
}
