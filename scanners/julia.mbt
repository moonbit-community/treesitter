// Port of tree-sitter-julia src/scanner.c (v0.25.0)
// tree-sitter-julia is distributed under the MIT license (see NOTICE).

// Block comments and immediate parentheses are easy to parse, but strings
// require extra-attention.
//
// The main problems that arise when parsing strings are:
// 1. Triple quoted strings allow single quotes inside. e.g. """ "foo" """.
// 2. Strings can have arbitrary interpolations, including other strings.
//    e.g. "echo $("foo")"
// 3. Non-standard string literals don't allow interpolations or escape
//    sequences, but you can always write \" and \`.
// All of the above also applies to command literals.

///|
/// `enum TokenType`.
const JULIA_BLOCK_COMMENT_REST : Int32 = 0

///|
const JULIA_IMMEDIATE_PAREN : Int32 = 1

///|
const JULIA_IMMEDIATE_BRACKET : Int32 = 2

///|
const JULIA_IMMEDIATE_BRACE : Int32 = 3

///|
const JULIA_IMMEDIATE_STRING_START : Int32 = 4

///|
const JULIA_IMMEDIATE_COMMAND_START : Int32 = 5

///|
const JULIA_CONTENT_CMD_1 : Int32 = 6

///|
const JULIA_CONTENT_CMD_1_RAW : Int32 = 7

///|
const JULIA_CONTENT_CMD_3 : Int32 = 8

///|
const JULIA_CONTENT_CMD_3_RAW : Int32 = 9

///|
const JULIA_CONTENT_STR_1 : Int32 = 10

///|
const JULIA_CONTENT_STR_1_RAW : Int32 = 11

///|
const JULIA_CONTENT_STR_3 : Int32 = 12

///|
const JULIA_CONTENT_STR_3_RAW : Int32 = 13

///|
const JULIA_END_CMD : Int32 = 14

///|
const JULIA_END_STR : Int32 = 15

///|
fn julia_scan_content(
  lexer : @runtime.Lexer,
  content_symbol : Int32,
  end_char : Int32,
  n_delim : Int32,
  interp : Bool,
) -> Bool {
  let end_symbol = if end_char == '"' { JULIA_END_STR } else { JULIA_END_CMD }
  let mut has_content = false
  for ;; {
    let mut next = lexer.lookahead
    if next == 0 {
      break
    }
    lexer.mark_end()
    if interp && (next == '$' || next == '\\') {
      lexer.result_symbol = content_symbol
      return has_content
    } else if next == '\\' {
      // Parse backslash in raw strings (check escaped delimiters and '\\')
      lexer.advance(false)
      next = lexer.lookahead
      if next == end_char || next == '\\' {
        lexer.result_symbol = content_symbol
        return has_content
      }
    } else {
      let mut is_end_delimiter = true
      for i = 1; i <= n_delim; i = i + 1 {
        if lexer.lookahead == end_char {
          lexer.advance(false)
        } else {
          is_end_delimiter = false
          break
        }
      }
      if is_end_delimiter {
        if has_content {
          lexer.result_symbol = content_symbol
          return true
        } else {
          lexer.mark_end()
          lexer.result_symbol = end_symbol
          return true
        }
      }
    }
    lexer.advance(false)
    has_content = true
  }
  false
}

///|
fn julia_scan_block_comment(lexer : @runtime.Lexer) -> Bool {
  // NOTE: The first `#=` is scanned by tree-sitter
  let mut after_eq = false
  // `unsigned nesting_depth`.
  let mut nesting_depth : UInt32 = 1
  for ;; {
    match lexer.lookahead {
      '=' => {
        lexer.advance(false)
        after_eq = true
      }
      '#' => {
        lexer.advance(false)
        if after_eq {
          after_eq = false
          nesting_depth -= 1
          if nesting_depth == 0 {
            lexer.result_symbol = JULIA_BLOCK_COMMENT_REST
            return true
          }
        } else {
          after_eq = false
          if lexer.lookahead == '=' {
            lexer.advance(false)
            nesting_depth += 1
          }
        }
      }
      '\u{0}' => return false
      _ => {
        lexer.advance(false)
        after_eq = false
      }
    }
  }
}

///|
fn julia_scan(lexer : @runtime.Lexer, valid_symbols : ArrayView[Bool]) -> Bool {
  if valid_symbols[JULIA_IMMEDIATE_PAREN] && lexer.lookahead == '(' {
    lexer.result_symbol = JULIA_IMMEDIATE_PAREN
    return true
  } else if valid_symbols[JULIA_IMMEDIATE_BRACKET] && lexer.lookahead == '[' {
    lexer.result_symbol = JULIA_IMMEDIATE_BRACKET
    return true
  } else if valid_symbols[JULIA_IMMEDIATE_BRACE] && lexer.lookahead == '{' {
    lexer.result_symbol = JULIA_IMMEDIATE_BRACE
    return true
  } else if valid_symbols[JULIA_IMMEDIATE_STRING_START] &&
    lexer.lookahead == '"' {
    lexer.result_symbol = JULIA_IMMEDIATE_STRING_START
    return true
  } else if valid_symbols[JULIA_IMMEDIATE_COMMAND_START] &&
    lexer.lookahead == '`' {
    lexer.result_symbol = JULIA_IMMEDIATE_COMMAND_START
    return true
  }
  if valid_symbols[JULIA_BLOCK_COMMENT_REST] && julia_scan_block_comment(lexer) {
    return true
  }
  if valid_symbols[JULIA_CONTENT_STR_1] &&
    julia_scan_content(lexer, JULIA_CONTENT_STR_1, '"', 1, true) {
    return true
  }
  if valid_symbols[JULIA_CONTENT_STR_3] &&
    julia_scan_content(lexer, JULIA_CONTENT_STR_3, '"', 3, true) {
    return true
  }
  if valid_symbols[JULIA_CONTENT_CMD_1] &&
    julia_scan_content(lexer, JULIA_CONTENT_CMD_1, '`', 1, true) {
    return true
  }
  if valid_symbols[JULIA_CONTENT_CMD_3] &&
    julia_scan_content(lexer, JULIA_CONTENT_CMD_3, '`', 3, true) {
    return true
  }
  if valid_symbols[JULIA_CONTENT_STR_1_RAW] &&
    julia_scan_content(lexer, JULIA_CONTENT_STR_1_RAW, '"', 1, false) {
    return true
  }
  if valid_symbols[JULIA_CONTENT_STR_3_RAW] &&
    julia_scan_content(lexer, JULIA_CONTENT_STR_3_RAW, '"', 3, false) {
    return true
  }
  if valid_symbols[JULIA_CONTENT_CMD_1_RAW] &&
    julia_scan_content(lexer, JULIA_CONTENT_CMD_1_RAW, '`', 1, false) {
    return true
  }
  if valid_symbols[JULIA_CONTENT_CMD_3_RAW] &&
    julia_scan_content(lexer, JULIA_CONTENT_CMD_3_RAW, '`', 3, false) {
    return true
  }
  false
}

///|
fn julia_scanner() -> @runtime.ExternalScanner {
  {
    scan: (lexer, valid_symbols) => julia_scan(lexer, valid_symbols),
    serialize: _ => 0,
    deserialize: _ => (),
    destroy: () => (),
  }
}
