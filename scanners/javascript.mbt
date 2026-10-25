// Port of the javascript grammar's src/scanner.c (v0.25.0).

///|
const JS_AUTOMATIC_SEMICOLON : Int32 = 0

///|
const JS_TEMPLATE_CHARS : Int32 = 1

///|
const JS_TERNARY_QMARK : Int32 = 2

///|
const JS_HTML_COMMENT : Int32 = 3

///|
const JS_LOGICAL_OR : Int32 = 4

///|
const JS_ESCAPE_SEQUENCE : Int32 = 5

///|
const JS_REGEX_PATTERN : Int32 = 6

///|
const JS_JSX_TEXT : Int32 = 7

///|
/// `tree_sitter_javascript_external_scanner_create` returns NULL; the scanner
/// is stateless and serializes nothing.
fn javascript_scanner() -> @runtime.ExternalScanner {
  {
    scan: javascript_scan,
    serialize: _ => 0,
    deserialize: _ => (),
    destroy: () => (),
  }
}

///|
fn javascript_scan_template_chars(lexer : @runtime.Lexer) -> Bool {
  lexer.result_symbol = JS_TEMPLATE_CHARS
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
/// `WhitespaceResult`.
priv enum JsWhitespaceResult {
  /// Semicolon is illegal, ie a syntax error occurred
  Reject
  /// Unclear if semicolon will be legal, continue
  NoNewline
  /// Semicolon is legal, assuming a comment was encountered
  Accept
}

///|
/// `consume`: if false, only consume enough to check if comment indicates
/// semicolon-legality.
fn javascript_scan_whitespace_and_comments(
  lexer : @runtime.Lexer,
  scanned_comment : Ref[Bool],
  consume : Bool,
) -> JsWhitespaceResult {
  let mut saw_block_newline = false
  for ;; {
    while iswspace(lexer.lookahead) {
      lexer.advance(true)
    }
    if lexer.lookahead == '/' {
      lexer.advance(true)
      if lexer.lookahead == '/' {
        lexer.advance(true)
        while lexer.lookahead != 0 &&
              lexer.lookahead != '\n' &&
              lexer.lookahead != 0x2028 &&
              lexer.lookahead != 0x2029 {
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
              scanned_comment.val = true
              if lexer.lookahead != '/' && !consume {
                return if saw_block_newline { Accept } else { NoNewline }
              }
              break
            }
          } else if lexer.lookahead == '\n' ||
            lexer.lookahead == 0x2028 ||
            lexer.lookahead == 0x2029 {
            saw_block_newline = true
            lexer.advance(true)
          } else {
            lexer.advance(true)
          }
        }
      } else {
        return Reject
      }
    } else {
      return Accept
    }
  }
}

///|
fn javascript_scan_automatic_semicolon(
  lexer : @runtime.Lexer,
  comment_condition : Bool,
  scanned_comment : Ref[Bool],
) -> Bool {
  lexer.result_symbol = JS_AUTOMATIC_SEMICOLON
  lexer.mark_end()
  for ;; {
    if lexer.lookahead == 0 {
      return true
    }
    if lexer.lookahead == '/' {
      let result = javascript_scan_whitespace_and_comments(
        lexer, scanned_comment, false,
      )
      if result is Reject {
        return false
      }
      if result is Accept &&
        comment_condition &&
        lexer.lookahead != ',' &&
        lexer.lookahead != '=' {
        return true
      }
    }
    if lexer.lookahead == '}' {
      return true
    }
    if lexer.is_at_included_range_start() {
      return true
    }
    if lexer.lookahead == '\n' ||
      lexer.lookahead == 0x2028 ||
      lexer.lookahead == 0x2029 {
      break
    }
    if !iswspace(lexer.lookahead) {
      return false
    }
    lexer.advance(true)
  }
  lexer.advance(true)
  if javascript_scan_whitespace_and_comments(lexer, scanned_comment, true)
    is Reject {
    return false
  }
  match lexer.lookahead {
    '`'
    | ','
    | ':'
    | ';'
    | '*'
    | '%'
    | '>'
    | '<'
    | '='
    | '['
    | '('
    | '?'
    | '^'
    | '|'
    | '&'
    | '/' => return false
    // Insert a semicolon before decimals literals but not otherwise.
    '.' => {
      lexer.advance(true)
      return iswdigit(lexer.lookahead)
    }
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
fn javascript_scan_ternary_qmark(lexer : @runtime.Lexer) -> Bool {
  for ;; {
    if !iswspace(lexer.lookahead) {
      break
    }
    lexer.advance(true)
  }
  if lexer.lookahead == '?' {
    lexer.advance(false)
    if lexer.lookahead == '?' {
      return false
    }
    lexer.mark_end()
    lexer.result_symbol = JS_TERNARY_QMARK
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
fn javascript_scan_html_comment(lexer : @runtime.Lexer) -> Bool {
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
  lexer.result_symbol = JS_HTML_COMMENT
  lexer.mark_end()
  true
}

///|
fn javascript_scan_jsx_text(lexer : @runtime.Lexer) -> Bool {
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
  lexer.result_symbol = JS_JSX_TEXT
  saw_text
}

///|
fn javascript_scan(
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[JS_TEMPLATE_CHARS] {
    if valid_symbols[JS_AUTOMATIC_SEMICOLON] {
      return false
    }
    return javascript_scan_template_chars(lexer)
  }
  if valid_symbols[JS_JSX_TEXT] && javascript_scan_jsx_text(lexer) {
    return true
  }
  if valid_symbols[JS_AUTOMATIC_SEMICOLON] {
    let scanned_comment = Ref(false)
    let ret = javascript_scan_automatic_semicolon(
      lexer,
      !valid_symbols[JS_LOGICAL_OR],
      scanned_comment,
    )
    if !ret &&
      !scanned_comment.val &&
      valid_symbols[JS_TERNARY_QMARK] &&
      lexer.lookahead == '?' {
      return javascript_scan_ternary_qmark(lexer)
    }
    return ret
  }
  if valid_symbols[JS_TERNARY_QMARK] {
    return javascript_scan_ternary_qmark(lexer)
  }
  if valid_symbols[JS_HTML_COMMENT] &&
    !valid_symbols[JS_LOGICAL_OR] &&
    !valid_symbols[JS_ESCAPE_SEQUENCE] &&
    !valid_symbols[JS_REGEX_PATTERN] {
    return javascript_scan_html_comment(lexer)
  }
  false
}
