// Port of the typescript grammar's common/scanner.h (v0.23.2), shared by the
// typescript and tsx scanners.

///|
const TS_AUTOMATIC_SEMICOLON : Int32 = 0

///|
const TS_TEMPLATE_CHARS : Int32 = 1

///|
const TS_TERNARY_QMARK : Int32 = 2

///|
const TS_HTML_COMMENT : Int32 = 3

///|
const TS_LOGICAL_OR : Int32 = 4

///|
const TS_ESCAPE_SEQUENCE : Int32 = 5

///|
const TS_REGEX_PATTERN : Int32 = 6

///|
const TS_JSX_TEXT : Int32 = 7

///|
const TS_FUNCTION_SIGNATURE_AUTOMATIC_SEMICOLON : Int32 = 8

///|
fn typescript_scan_template_chars(lexer : @runtime.Lexer) -> Bool {
  lexer.result_symbol = TS_TEMPLATE_CHARS
  for has_content = false; ; has_content = true {
    lexer.mark_end()
    match lexer.lookahead {
      '`' => return has_content
      '\u{0}' => return false
      '$' => {
        lexer.advance(false)
        if lexer.lookahead == '{' {
          return has_content
        }
      }
      '\\' => return has_content
      _ => lexer.advance(false)
    }
  }
}

///|
fn typescript_scan_whitespace_and_comments(
  lexer : @runtime.Lexer,
  scanned_comment : Ref[Bool],
) -> Bool {
  for ;; {
    while iswspace(lexer.lookahead) {
      lexer.advance(true)
    }
    if lexer.lookahead == '/' {
      lexer.advance(true)
      if lexer.lookahead == '/' {
        lexer.advance(true)
        while lexer.lookahead != 0 && lexer.lookahead != '\n' {
          lexer.advance(true)
        }
        scanned_comment.val = true
      } else if lexer.lookahead == '*' {
        lexer.advance(true)
        while lexer.lookahead != 0 {
          if lexer.lookahead == '*' {
            lexer.advance(true)
            if lexer.lookahead == '/' {
              lexer.advance(true)
              break
            }
          } else {
            lexer.advance(true)
          }
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
fn typescript_scan_automatic_semicolon(
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
  scanned_comment : Ref[Bool],
) -> Bool {
  lexer.result_symbol = TS_AUTOMATIC_SEMICOLON
  lexer.mark_end()
  for ;; {
    if lexer.lookahead == 0 {
      return true
    }
    if lexer.lookahead == '}' {
      // Automatic semicolon insertion breaks detection of object patterns
      // in a typed context:
      //   type F = ({a}: {a: number}) => number;
      // Therefore, disable automatic semicolons when followed by typing
      lexer.advance(true)
      while iswspace(lexer.lookahead) {
        lexer.advance(true)
      }
      if lexer.lookahead == ':' {
        return valid_symbols[TS_LOGICAL_OR] // Don't return false if we're in a ternary by checking if || is valid
      }
      return true
    }
    if !iswspace(lexer.lookahead) {
      return false
    }
    if lexer.lookahead == '\n' {
      break
    }
    lexer.advance(true)
  }
  lexer.advance(true)
  if !typescript_scan_whitespace_and_comments(lexer, scanned_comment) {
    return false
  }
  match lexer.lookahead {
    '`'
    | ','
    | '.'
    | ';'
    | '*'
    | '%'
    | '>'
    | '<'
    | '='
    | '?'
    | '^'
    | '|'
    | '&'
    | '/'
    | ':' => return false
    '{' =>
      if valid_symbols[TS_FUNCTION_SIGNATURE_AUTOMATIC_SEMICOLON] {
        return false
      }
    // Don't insert a semicolon before a '[' or '(', unless we're parsing
    // a type. Detect whether we're parsing a type or an expression using
    // the validity of a binary operator token.
    '(' | '[' => if valid_symbols[TS_LOGICAL_OR] { return false }
    // Insert a semicolon before `--` and `++`, but not before binary `+` or `-`.
    '+' => {
      lexer.advance(true)
      return lexer.lookahead == '+'
    }
    '-' => {
      lexer.advance(true)
      return lexer.lookahead == '-'
    }
    // Don't insert a semicolon before `!=`, but do insert one before a unary `!`.
    '!' => {
      lexer.advance(true)
      return lexer.lookahead != '='
    }
    // Don't insert a semicolon before `in` or `instanceof`, but do insert one
    // before an identifier.
    'i' => {
      lexer.advance(true)
      if lexer.lookahead != 'n' {
        return true
      }
      lexer.advance(true)
      if !iswalpha(lexer.lookahead) {
        return false
      }
      let stanceof = "stanceof"
      for i in 0..<8 {
        if lexer.lookahead != stanceof[i].to_int() {
          return true
        }
        lexer.advance(true)
      }
      if !iswalpha(lexer.lookahead) {
        return false
      }
    }
    _ => ()
  }
  true
}

///|
fn typescript_scan_ternary_qmark(lexer : @runtime.Lexer) -> Bool {
  for ;; {
    if !iswspace(lexer.lookahead) {
      break
    }
    lexer.advance(true)
  }
  if lexer.lookahead == '?' {
    lexer.advance(false)
    // Optional chaining.
    if lexer.lookahead == '?' || lexer.lookahead == '.' {
      return false
    }
    lexer.mark_end()
    lexer.result_symbol = TS_TERNARY_QMARK
    // TypeScript optional arguments contain the ?: sequence, possibly
    // with whitespace.
    for ;; {
      if !iswspace(lexer.lookahead) {
        break
      }
      lexer.advance(false)
    }
    if lexer.lookahead == ':' ||
      lexer.lookahead == ')' ||
      lexer.lookahead == ',' {
      return false
    }
    if lexer.lookahead == '.' {
      lexer.advance(false)
      if iswdigit(lexer.lookahead) {
        return true
      }
      return false
    }
    return true
  }
  false
}

///|
fn typescript_scan_closing_comment(lexer : @runtime.Lexer) -> Bool {
  while iswspace(lexer.lookahead) ||
        lexer.lookahead == 0x2028 ||
        lexer.lookahead == 0x2029 {
    lexer.advance(true)
  }
  let comment_start = "<!--"
  let comment_end = "-->"
  if lexer.lookahead == '<' {
    for i in 0..<4 {
      if lexer.lookahead != comment_start[i].to_int() {
        return false
      }
      lexer.advance(false)
    }
  } else if lexer.lookahead == '-' {
    for i in 0..<3 {
      if lexer.lookahead != comment_end[i].to_int() {
        return false
      }
      lexer.advance(false)
    }
  } else {
    return false
  }
  while lexer.lookahead != 0 &&
        lexer.lookahead != '\n' &&
        lexer.lookahead != 0x2028 &&
        lexer.lookahead != 0x2029 {
    lexer.advance(false)
  }
  lexer.result_symbol = TS_HTML_COMMENT
  lexer.mark_end()
  true
}

///|
fn typescript_scan_jsx_text(lexer : @runtime.Lexer) -> Bool {
  // saw_text will be true if we see any non-whitespace content, or any whitespace content that is not a newline and
  // does not immediately follow a newline.
  let mut saw_text = false
  // at_newline will be true if we are currently at a newline, or if we are at whitespace that is not a newline but
  // immediately follows a newline.
  let mut at_newline = false
  while lexer.lookahead != 0 &&
        lexer.lookahead != '<' &&
        lexer.lookahead != '>' &&
        lexer.lookahead != '{' &&
        lexer.lookahead != '}' &&
        lexer.lookahead != '&' {
    let is_wspace = iswspace(lexer.lookahead)
    if lexer.lookahead == '\n' {
      at_newline = true
    } else {
      // If at_newline is already true, and we see some whitespace, then it must stay true.
      // Otherwise, it should be false.
      //
      // See the table below to determine the logic for computing `saw_text`.
      //
      // |------------------------------------|
      // | at_newline | is_wspace | saw_text  |
      // |------------|-----------|-----------|
      // | false (0)  | false (0) | true  (1) |
      // | false (0)  | true  (1) | true  (1) |
      // | true  (1)  | false (0) | true  (1) |
      // | true  (1)  | true  (1) | false (0) |
      // |------------------------------------|
      at_newline = at_newline && is_wspace
      if !at_newline {
        saw_text = true
      }
    }
    lexer.advance(false)
  }
  lexer.result_symbol = TS_JSX_TEXT
  saw_text
}

///|
/// `external_scanner_scan`.
fn typescript_external_scanner_scan(
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[TS_TEMPLATE_CHARS] {
    if valid_symbols[TS_AUTOMATIC_SEMICOLON] {
      return false
    }
    return typescript_scan_template_chars(lexer)
  }
  if valid_symbols[TS_JSX_TEXT] && typescript_scan_jsx_text(lexer) {
    return true
  }
  if valid_symbols[TS_AUTOMATIC_SEMICOLON] ||
    valid_symbols[TS_FUNCTION_SIGNATURE_AUTOMATIC_SEMICOLON] {
    let scanned_comment = Ref(false)
    let ret = typescript_scan_automatic_semicolon(
      lexer, valid_symbols, scanned_comment,
    )
    if !ret &&
      !scanned_comment.val &&
      valid_symbols[TS_TERNARY_QMARK] &&
      lexer.lookahead == '?' {
      return typescript_scan_ternary_qmark(lexer)
    }
    return ret
  }
  if valid_symbols[TS_TERNARY_QMARK] {
    return typescript_scan_ternary_qmark(lexer)
  }
  if valid_symbols[TS_HTML_COMMENT] &&
    !valid_symbols[TS_LOGICAL_OR] &&
    !valid_symbols[TS_ESCAPE_SEQUENCE] &&
    !valid_symbols[TS_REGEX_PATTERN] {
    return typescript_scan_closing_comment(lexer)
  }
  false
}
