// Port of tree-sitter-ruby src/scanner.c (v0.23.1)
// tree-sitter-ruby is distributed under the MIT license (see NOTICE).

///|
/// `TokenType`.
const RUBY_LINE_BREAK : Int32 = 0

///|
const RUBY_NO_LINE_BREAK : Int32 = 1

// Delimited literals

///|
const RUBY_SIMPLE_SYMBOL : Int32 = 2

///|
const RUBY_STRING_START : Int32 = 3

///|
const RUBY_SYMBOL_START : Int32 = 4

///|
const RUBY_SUBSHELL_START : Int32 = 5

///|
const RUBY_REGEX_START : Int32 = 6

///|
const RUBY_STRING_ARRAY_START : Int32 = 7

///|
const RUBY_SYMBOL_ARRAY_START : Int32 = 8

///|
const RUBY_HEREDOC_BODY_START : Int32 = 9

///|
const RUBY_STRING_CONTENT : Int32 = 10

///|
const RUBY_HEREDOC_CONTENT : Int32 = 11

///|
const RUBY_STRING_END : Int32 = 12

///|
const RUBY_HEREDOC_BODY_END : Int32 = 13

///|
const RUBY_HEREDOC_START : Int32 = 14

// Whitespace-sensitive tokens

///|
const RUBY_FORWARD_SLASH : Int32 = 15

///|
const RUBY_BLOCK_AMPERSAND : Int32 = 16

///|
const RUBY_SPLAT_STAR : Int32 = 17

///|
const RUBY_UNARY_MINUS : Int32 = 18

///|
const RUBY_UNARY_MINUS_NUM : Int32 = 19

///|
const RUBY_BINARY_MINUS : Int32 = 20

///|
const RUBY_BINARY_STAR : Int32 = 21

///|
const RUBY_SINGLETON_CLASS_LEFT_ANGLE_LEFT_ANGLE : Int32 = 22

///|
const RUBY_HASH_KEY_SYMBOL : Int32 = 23

///|
const RUBY_IDENTIFIER_SUFFIX : Int32 = 24

///|
const RUBY_CONSTANT_SUFFIX : Int32 = 25

///|
const RUBY_HASH_SPLAT_STAR_STAR : Int32 = 26

///|
const RUBY_BINARY_STAR_STAR : Int32 = 27

///|
const RUBY_ELEMENT_REFERENCE_BRACKET : Int32 = 28

///|
const RUBY_SHORT_INTERPOLATION : Int32 = 29

///|
const RUBY_NONE : Int32 = 30

///|
priv struct RubyLiteral {
  mut type_ : Int32
  mut open_delimiter : Int32
  mut close_delimiter : Int32
  mut nesting_depth : Int32
  mut allows_interpolation : Bool
}

///|
/// `Literal literal = {0};`
fn ruby_literal_new() -> RubyLiteral {
  {
    type_: 0,
    open_delimiter: 0,
    close_delimiter: 0,
    nesting_depth: 0,
    allows_interpolation: false,
  }
}

///|
/// `word` is a `typedef Array(char) String;`, holding C `char` values
/// (signed, -128..=127).
priv struct RubyHeredoc {
  mut word : Array[Int32]
  mut end_word_indentation_allowed : Bool
  mut allows_interpolation : Bool
  mut started : Bool
}

///|
priv struct RubyScanner {
  mut has_leading_whitespace : Bool
  literal_stack : Array[RubyLiteral]
  open_heredocs : Array[RubyHeredoc]
}

///|
let ruby_non_identifier_chars : FixedArray[Int32] = [
  '\u{0}', '\n', '\r', '\t', ' ', ':', ';', '`', '"', '\'', '@', '$', '#', '.', ',',
  '|', '^', '&', '<', '=', '>', '+', '-', '*', '/', '\\', '%', '?', '!', '~', '(',
  ')', '[', ']', '{', '}',
]

///|
fn RubyScanner::skip(self : RubyScanner, lexer : @runtime.Lexer) -> Unit {
  self.has_leading_whitespace = true
  lexer.advance(true)
}

///|
fn RubyScanner::reset(self : RubyScanner) -> Unit {
  self.literal_stack.clear()
  self.open_heredocs.clear()
}

///|
fn ruby_bool_byte(b : Bool) -> Byte {
  if b {
    1
  } else {
    0
  }
}

///|
fn RubyScanner::serialize(
  self : RubyScanner,
  buffer : FixedArray[Byte],
) -> Int32 {
  let mut size = 0
  if self.literal_stack.length() * 5 + 2 >= SERIALIZATION_BUFFER_SIZE {
    return 0
  }
  buffer[size] = self.literal_stack.length().to_byte()
  size += 1
  for literal in self.literal_stack {
    buffer[size] = literal.type_.to_byte()
    size += 1
    buffer[size] = literal.open_delimiter.to_byte()
    size += 1
    buffer[size] = literal.close_delimiter.to_byte()
    size += 1
    buffer[size] = literal.nesting_depth.to_byte()
    size += 1
    buffer[size] = ruby_bool_byte(literal.allows_interpolation)
    size += 1
  }
  buffer[size] = self.open_heredocs.length().to_byte()
  size += 1
  for heredoc in self.open_heredocs {
    if size + 2 + heredoc.word.length() >= SERIALIZATION_BUFFER_SIZE {
      return 0
    }
    buffer[size] = ruby_bool_byte(heredoc.end_word_indentation_allowed)
    size += 1
    buffer[size] = ruby_bool_byte(heredoc.allows_interpolation)
    size += 1
    buffer[size] = ruby_bool_byte(heredoc.started)
    size += 1
    buffer[size] = heredoc.word.length().to_byte()
    size += 1
    for i, c in heredoc.word {
      buffer[size + i] = c.to_byte()
    }
    size += heredoc.word.length()
  }
  size
}

///|
fn RubyScanner::deserialize(self : RubyScanner, buffer : BytesView) -> Unit {
  let length = buffer.length()
  let mut size = 0
  self.has_leading_whitespace = false
  self.reset()
  if length == 0 {
    return
  }
  let literal_depth = buffer[size].to_int()
  size += 1
  for _ in 0..<literal_depth {
    let literal = ruby_literal_new()
    // `(TokenType)(buffer[size++])`: a signed `char`.
    literal.type_ = to_c_char(buffer[size].to_int())
    size += 1
    literal.open_delimiter = buffer[size].to_int()
    size += 1
    literal.close_delimiter = buffer[size].to_int()
    size += 1
    literal.nesting_depth = buffer[size].to_int()
    size += 1
    literal.allows_interpolation = buffer[size] != 0
    size += 1
    self.literal_stack.push(literal)
  }
  let open_heredoc_count = buffer[size].to_int()
  size += 1
  for _ in 0..<open_heredoc_count {
    let heredoc : RubyHeredoc = {
      word: [],
      end_word_indentation_allowed: false,
      allows_interpolation: false,
      started: false,
    }
    heredoc.end_word_indentation_allowed = buffer[size] != 0
    size += 1
    heredoc.allows_interpolation = buffer[size] != 0
    size += 1
    heredoc.started = buffer[size] != 0
    size += 1
    let word_length = buffer[size].to_int()
    size += 1
    for i in 0..<word_length {
      heredoc.word.push(to_c_char(buffer[size + i].to_int()))
    }
    size += word_length
    self.open_heredocs.push(heredoc)
  }
  guard size == length else { abort("assert(size == length)") }
}

///|
fn RubyScanner::scan_whitespace(
  self : RubyScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  let heredoc_body_start_is_valid = self.open_heredocs.length() > 0 &&
    !self.open_heredocs[0].started &&
    valid_symbols[RUBY_HEREDOC_BODY_START]
  let mut crossed_newline = false
  for ;; {
    if !valid_symbols[RUBY_NO_LINE_BREAK] &&
      valid_symbols[RUBY_LINE_BREAK] &&
      lexer.is_at_included_range_start() {
      lexer.mark_end()
      lexer.result_symbol = RUBY_LINE_BREAK
      return true
    }
    match lexer.lookahead {
      ' ' | '\t' => self.skip(lexer)
      '\r' =>
        if heredoc_body_start_is_valid {
          lexer.result_symbol = RUBY_HEREDOC_BODY_START
          self.open_heredocs[0].started = true
          return true
        } else {
          self.skip(lexer)
        }
      '\n' =>
        if heredoc_body_start_is_valid {
          lexer.result_symbol = RUBY_HEREDOC_BODY_START
          self.open_heredocs[0].started = true
          return true
        } else if !valid_symbols[RUBY_NO_LINE_BREAK] &&
          valid_symbols[RUBY_LINE_BREAK] &&
          !crossed_newline {
          lexer.mark_end()
          lexer.advance(false)
          crossed_newline = true
        } else {
          self.skip(lexer)
        }
      '\\' => {
        lexer.advance(false)
        if lexer.lookahead == '\r' {
          self.skip(lexer)
        }
        if iswspace(lexer.lookahead) {
          self.skip(lexer)
        } else {
          return false
        }
      }
      _ => {
        if crossed_newline {
          if lexer.lookahead != '.' &&
            lexer.lookahead != '&' &&
            lexer.lookahead != '#' {
            lexer.result_symbol = RUBY_LINE_BREAK
          } else if lexer.lookahead == '.' {
            // Don't return LINE_BREAK for the call operator (`.`) but do return one for range
            // operators
            // (`..` and `...`)
            lexer.advance(false)
            if !lexer.eof() && lexer.lookahead == '.' {
              lexer.result_symbol = RUBY_LINE_BREAK
            } else {
              return false
            }
          }
        }
        return true
      }
    }
  }
}

///|
fn ruby_scan_operator(lexer : @runtime.Lexer) -> Bool {
  match lexer.lookahead {
    // <, <=, <<, <=>
    '<' => {
      lexer.advance(false)
      if lexer.lookahead == '<' {
        lexer.advance(false)
      } else if lexer.lookahead == '=' {
        lexer.advance(false)
        if lexer.lookahead == '>' {
          lexer.advance(false)
        }
      }
      true
    }
    // >, >=, >>
    '>' => {
      lexer.advance(false)
      if lexer.lookahead == '>' || lexer.lookahead == '=' {
        lexer.advance(false)
      }
      true
    }
    // ==, ===, =~
    '=' => {
      lexer.advance(false)
      if lexer.lookahead == '~' {
        lexer.advance(false)
        return true
      }
      if lexer.lookahead == '=' {
        lexer.advance(false)
        if lexer.lookahead == '=' {
          lexer.advance(false)
        }
        return true
      }
      false
    }
    // +, -, ~, +@, -@, ~@
    '+' | '-' | '~' => {
      lexer.advance(false)
      if lexer.lookahead == '@' {
        lexer.advance(false)
      }
      true
    }
    // ..
    '.' => {
      lexer.advance(false)
      if lexer.lookahead == '.' {
        lexer.advance(false)
        return true
      }
      false
    }
    // &, ^, |, /, %`
    '&' | '^' | '|' | '/' | '%' | '`' => {
      lexer.advance(false)
      true
    }
    // !, !=, !~
    '!' => {
      lexer.advance(false)
      if lexer.lookahead == '=' || lexer.lookahead == '~' {
        lexer.advance(false)
      }
      true
    }
    // *, **
    '*' => {
      lexer.advance(false)
      if lexer.lookahead == '*' {
        lexer.advance(false)
      }
      true
    }
    // [], []=
    '[' => {
      lexer.advance(false)
      if lexer.lookahead == ']' {
        lexer.advance(false)
      } else {
        return false
      }
      if lexer.lookahead == '=' {
        lexer.advance(false)
      }
      true
    }
    _ => false
  }
}

///|
/// `is_iden_char((char)c)`: `memchr` compares the low byte of `c`.
fn ruby_is_iden_char(c : Int32) -> Bool {
  let byte = c & 0xFF
  for x in ruby_non_identifier_chars {
    if x == byte {
      return false
    }
  }
  true
}

///|
fn ruby_scan_symbol_identifier(lexer : @runtime.Lexer) -> Bool {
  if lexer.lookahead == '@' {
    lexer.advance(false)
    if lexer.lookahead == '@' {
      lexer.advance(false)
    }
  } else if lexer.lookahead == '$' {
    lexer.advance(false)
  }
  if ruby_is_iden_char(lexer.lookahead) {
    lexer.advance(false)
  } else if !ruby_scan_operator(lexer) {
    return false
  }
  while ruby_is_iden_char(lexer.lookahead) {
    lexer.advance(false)
  }
  if lexer.lookahead == '?' || lexer.lookahead == '!' {
    lexer.advance(false)
  }
  if lexer.lookahead == '=' {
    lexer.mark_end()
    lexer.advance(false)
    if lexer.lookahead != '>' {
      lexer.mark_end()
    }
  }
  true
}

///|
fn RubyScanner::scan_open_delimiter(
  self : RubyScanner,
  lexer : @runtime.Lexer,
  literal : RubyLiteral,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  match lexer.lookahead {
    '"' => {
      literal.type_ = RUBY_STRING_START
      literal.close_delimiter = lexer.lookahead
      literal.open_delimiter = literal.close_delimiter
      literal.allows_interpolation = true
      lexer.advance(false)
      true
    }
    '\'' => {
      literal.type_ = RUBY_STRING_START
      literal.close_delimiter = lexer.lookahead
      literal.open_delimiter = literal.close_delimiter
      literal.allows_interpolation = false
      lexer.advance(false)
      true
    }
    '`' => {
      if !valid_symbols[RUBY_SUBSHELL_START] {
        return false
      }
      literal.type_ = RUBY_SUBSHELL_START
      literal.close_delimiter = lexer.lookahead
      literal.open_delimiter = literal.close_delimiter
      literal.allows_interpolation = true
      lexer.advance(false)
      true
    }
    '/' => {
      if !valid_symbols[RUBY_REGEX_START] {
        return false
      }
      literal.type_ = RUBY_REGEX_START
      literal.close_delimiter = lexer.lookahead
      literal.open_delimiter = literal.close_delimiter
      literal.allows_interpolation = true
      lexer.advance(false)
      if valid_symbols[RUBY_FORWARD_SLASH] {
        if !self.has_leading_whitespace {
          return false
        }
        if lexer.lookahead == ' ' ||
          lexer.lookahead == '\t' ||
          lexer.lookahead == '\n' ||
          lexer.lookahead == '\r' {
          return false
        }
        if lexer.lookahead == '=' {
          return false
        }
      }
      true
    }
    '%' => {
      lexer.advance(false)
      match lexer.lookahead {
        's' => {
          if !valid_symbols[RUBY_SIMPLE_SYMBOL] {
            return false
          }
          literal.type_ = RUBY_SYMBOL_START
          literal.allows_interpolation = false
          lexer.advance(false)
        }
        'r' => {
          if !valid_symbols[RUBY_REGEX_START] {
            return false
          }
          literal.type_ = RUBY_REGEX_START
          literal.allows_interpolation = true
          lexer.advance(false)
        }
        'x' => {
          if !valid_symbols[RUBY_SUBSHELL_START] {
            return false
          }
          literal.type_ = RUBY_SUBSHELL_START
          literal.allows_interpolation = true
          lexer.advance(false)
        }
        'q' => {
          if !valid_symbols[RUBY_STRING_START] {
            return false
          }
          literal.type_ = RUBY_STRING_START
          literal.allows_interpolation = false
          lexer.advance(false)
        }
        'Q' => {
          if !valid_symbols[RUBY_STRING_START] {
            return false
          }
          literal.type_ = RUBY_STRING_START
          literal.allows_interpolation = true
          lexer.advance(false)
        }
        'w' => {
          if !valid_symbols[RUBY_STRING_ARRAY_START] {
            return false
          }
          literal.type_ = RUBY_STRING_ARRAY_START
          literal.allows_interpolation = false
          lexer.advance(false)
        }
        'i' => {
          if !valid_symbols[RUBY_SYMBOL_ARRAY_START] {
            return false
          }
          literal.type_ = RUBY_SYMBOL_ARRAY_START
          literal.allows_interpolation = false
          lexer.advance(false)
        }
        'W' => {
          if !valid_symbols[RUBY_STRING_ARRAY_START] {
            return false
          }
          literal.type_ = RUBY_STRING_ARRAY_START
          literal.allows_interpolation = true
          lexer.advance(false)
        }
        'I' => {
          if !valid_symbols[RUBY_SYMBOL_ARRAY_START] {
            return false
          }
          literal.type_ = RUBY_SYMBOL_ARRAY_START
          literal.allows_interpolation = true
          lexer.advance(false)
        }
        _ => {
          if !valid_symbols[RUBY_STRING_START] {
            return false
          }
          literal.type_ = RUBY_STRING_START
          literal.allows_interpolation = true
        }
      }
      match lexer.lookahead {
        '(' => {
          literal.open_delimiter = '('
          literal.close_delimiter = ')'
        }
        '[' => {
          literal.open_delimiter = '['
          literal.close_delimiter = ']'
        }
        '{' => {
          literal.open_delimiter = '{'
          literal.close_delimiter = '}'
        }
        '<' => {
          literal.open_delimiter = '<'
          literal.close_delimiter = '>'
        }
        '\r' | '\n' | ' ' | '\t' =>
          // If the `/` operator is valid, then so is the `%` operator, which means
          // that a `%` followed by whitespace should be considered an operator,
          // not a percent string.
          if valid_symbols[RUBY_FORWARD_SLASH] {
            return false
          }
        '|'
        | '!'
        | '#'
        | '/'
        | '\\'
        | '@'
        | '$'
        | '%'
        | '^'
        | '&'
        | '*'
        | ')'
        | ']'
        | '}'
        | '>'
        // TODO: Implement %= as external rule and re-enable = as a valid
        // unbalanced delimiter. That will be necessary due to ambiguity
        // between &= assignment operator and %=...= as string
        // content delimiter.
        // case '=':
        | '+'
        | '-'
        | '~'
        | '`'
        | ','
        | '.'
        | '?'
        | ':'
        | ';'
        | '_'
        | '"'
        | '\'' => {
          literal.open_delimiter = lexer.lookahead
          literal.close_delimiter = lexer.lookahead
        }
        _ => return false
      }
      lexer.advance(false)
      true
    }
    _ => false
  }
}

///|
fn ruby_scan_heredoc_word(
  lexer : @runtime.Lexer,
  heredoc : RubyHeredoc,
) -> Unit {
  let word = []
  let mut quote = 0
  match lexer.lookahead {
    '\'' | '"' | '`' => {
      quote = lexer.lookahead
      lexer.advance(false)
      while lexer.lookahead != quote && !lexer.eof() {
        word.push(to_c_char(lexer.lookahead))
        lexer.advance(false)
      }
      lexer.advance(false)
    }
    _ =>
      if iswalnum(lexer.lookahead) || lexer.lookahead == '_' {
        word.push(to_c_char(lexer.lookahead))
        lexer.advance(false)
        while iswalnum(lexer.lookahead) || lexer.lookahead == '_' {
          word.push(to_c_char(lexer.lookahead))
          lexer.advance(false)
        }
      }
  }
  heredoc.word = word
  heredoc.allows_interpolation = quote != '\''
}

///|
/// `strchr("!@&`'+~=/\\,;.<>*$?:\"", c) != NULL`: `strchr` searches for the
/// low byte of `c` and also finds the terminating NUL.
fn ruby_strchr_short_interpolation(c : Int32) -> Bool {
  let byte = c & 0xFF
  if byte == 0 {
    return true
  }
  for x in "!@&`'+~=/\\,;.<>*$?:\"" {
    if x.to_int() == byte {
      return true
    }
  }
  false
}

///|
fn ruby_scan_short_interpolation(
  lexer : @runtime.Lexer,
  has_content : Bool,
  content_symbol : Int32,
) -> Bool {
  let start = to_c_char(lexer.lookahead)
  if start == '@' || start == '$' {
    if has_content {
      lexer.result_symbol = content_symbol
      return true
    }
    lexer.mark_end()
    lexer.advance(false)
    let mut is_short_interpolation = false
    if start == '$' {
      if ruby_strchr_short_interpolation(lexer.lookahead) {
        is_short_interpolation = true
      } else if lexer.lookahead == '-' {
        lexer.advance(false)
        is_short_interpolation = iswalpha(lexer.lookahead) ||
          lexer.lookahead == '_'
      } else {
        is_short_interpolation = iswalnum(lexer.lookahead) ||
          lexer.lookahead == '_'
      }
    }
    if start == '@' {
      if lexer.lookahead == '@' {
        lexer.advance(false)
      }
      is_short_interpolation = ruby_is_iden_char(lexer.lookahead) &&
        !iswdigit(lexer.lookahead)
    }
    if is_short_interpolation {
      lexer.result_symbol = RUBY_SHORT_INTERPOLATION
      return true
    }
  }
  false
}

///|
fn RubyScanner::scan_heredoc_content(
  self : RubyScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  let heredoc = self.open_heredocs[0]
  let mut position_in_word = 0
  let mut look_for_heredoc_end = true
  let mut has_content = false
  for ;; {
    if position_in_word == heredoc.word.length() {
      if !has_content {
        lexer.mark_end()
      }
      while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
        lexer.advance(false)
      }
      if lexer.lookahead == '\n' || lexer.lookahead == '\r' {
        if has_content {
          lexer.result_symbol = RUBY_HEREDOC_CONTENT
        } else {
          heredoc.word.clear()
          self.open_heredocs.remove(0) |> ignore
          lexer.result_symbol = RUBY_HEREDOC_BODY_END
        }
        return true
      }
      has_content = true
      position_in_word = 0
    }
    if lexer.eof() {
      lexer.mark_end()
      if has_content {
        lexer.result_symbol = RUBY_HEREDOC_CONTENT
      } else {
        heredoc.word.clear()
        self.open_heredocs.remove(0) |> ignore
        lexer.result_symbol = RUBY_HEREDOC_BODY_END
      }
      return true
    }
    if lexer.lookahead == heredoc.word[position_in_word] && look_for_heredoc_end {
      lexer.advance(false)
      position_in_word += 1
    } else {
      position_in_word = 0
      look_for_heredoc_end = false
      if heredoc.allows_interpolation && lexer.lookahead == '\\' {
        if has_content {
          lexer.result_symbol = RUBY_HEREDOC_CONTENT
          return true
        }
        return false
      }
      if heredoc.allows_interpolation && lexer.lookahead == '#' {
        lexer.mark_end()
        lexer.advance(false)
        if lexer.lookahead == '{' {
          if has_content {
            lexer.result_symbol = RUBY_HEREDOC_CONTENT
            return true
          }
          return false
        }
        if ruby_scan_short_interpolation(
            lexer,
            has_content,
            RUBY_HEREDOC_CONTENT,
          ) {
          return true
        }
      } else if lexer.lookahead == '\r' || lexer.lookahead == '\n' {
        if lexer.lookahead == '\r' {
          lexer.advance(false)
          if lexer.lookahead == '\n' {
            lexer.advance(false)
          }
        } else {
          lexer.advance(false)
        }
        has_content = true
        look_for_heredoc_end = true
        while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
          lexer.advance(false)
          if !heredoc.end_word_indentation_allowed {
            look_for_heredoc_end = false
          }
        }
        lexer.mark_end()
      } else {
        has_content = true
        lexer.advance(false)
        lexer.mark_end()
      }
    }
  }
}

///|
fn RubyScanner::scan_literal_content(
  self : RubyScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  let literal = self.literal_stack[self.literal_stack.length() - 1]
  let mut has_content = false
  let stop_on_space = literal.type_ == RUBY_SYMBOL_ARRAY_START ||
    literal.type_ == RUBY_STRING_ARRAY_START
  for ;; {
    if stop_on_space && iswspace(lexer.lookahead) {
      if has_content {
        lexer.mark_end()
        lexer.result_symbol = RUBY_STRING_CONTENT
        return true
      }
      return false
    }
    if lexer.lookahead == literal.close_delimiter {
      lexer.mark_end()
      if literal.nesting_depth == 1 {
        if has_content {
          lexer.result_symbol = RUBY_STRING_CONTENT
        } else {
          lexer.advance(false)
          if literal.type_ == RUBY_REGEX_START {
            while iswlower(lexer.lookahead) {
              lexer.advance(false)
            }
          }
          ignore(self.literal_stack.pop())
          lexer.result_symbol = RUBY_STRING_END
          lexer.mark_end()
        }
        return true
      }
      literal.nesting_depth -= 1
      lexer.advance(false)
    } else if lexer.lookahead == literal.open_delimiter {
      literal.nesting_depth += 1
      lexer.advance(false)
    } else if literal.allows_interpolation && lexer.lookahead == '#' {
      lexer.mark_end()
      lexer.advance(false)
      if lexer.lookahead == '{' {
        if has_content {
          lexer.result_symbol = RUBY_STRING_CONTENT
          return true
        }
        return false
      }
      if ruby_scan_short_interpolation(lexer, has_content, RUBY_STRING_CONTENT) {
        return true
      }
    } else if lexer.lookahead == '\\' {
      if literal.allows_interpolation {
        if has_content {
          lexer.mark_end()
          lexer.result_symbol = RUBY_STRING_CONTENT
          return true
        }
        return false
      }
      lexer.advance(false)
      lexer.advance(false)
    } else if lexer.eof() {
      lexer.advance(false)
      lexer.mark_end()
      return false
    } else {
      lexer.advance(false)
    }
    has_content = true
  }
}

///|
fn RubyScanner::scan(
  self : RubyScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  self.has_leading_whitespace = false

  // Contents of literals, which match any character except for some close delimiter
  if !valid_symbols[RUBY_STRING_START] {
    if (valid_symbols[RUBY_STRING_CONTENT] || valid_symbols[RUBY_STRING_END]) &&
      self.literal_stack.length() > 0 {
      return self.scan_literal_content(lexer)
    }
    if (
        valid_symbols[RUBY_HEREDOC_CONTENT] ||
        valid_symbols[RUBY_HEREDOC_BODY_END]
      ) &&
      self.open_heredocs.length() > 0 {
      return self.scan_heredoc_content(lexer)
    }
  }

  // Whitespace
  lexer.result_symbol = RUBY_NONE
  if !self.scan_whitespace(lexer, valid_symbols) {
    return false
  }
  if lexer.result_symbol != RUBY_NONE {
    return true
  }
  match lexer.lookahead {
    '&' =>
      if valid_symbols[RUBY_BLOCK_AMPERSAND] {
        lexer.advance(false)
        if lexer.lookahead != '&' &&
          lexer.lookahead != '.' &&
          lexer.lookahead != '=' &&
          !iswspace(lexer.lookahead) {
          lexer.result_symbol = RUBY_BLOCK_AMPERSAND
          return true
        }
        return false
      }
    '<' =>
      if valid_symbols[RUBY_SINGLETON_CLASS_LEFT_ANGLE_LEFT_ANGLE] {
        lexer.advance(false)
        if lexer.lookahead == '<' {
          lexer.advance(false)
          lexer.result_symbol = RUBY_SINGLETON_CLASS_LEFT_ANGLE_LEFT_ANGLE
          return true
        }
        return false
      }
    '*' =>
      if valid_symbols[RUBY_SPLAT_STAR] ||
        valid_symbols[RUBY_BINARY_STAR] ||
        valid_symbols[RUBY_HASH_SPLAT_STAR_STAR] ||
        valid_symbols[RUBY_BINARY_STAR_STAR] {
        lexer.advance(false)
        if lexer.lookahead == '=' {
          return false
        }
        if lexer.lookahead == '*' {
          if valid_symbols[RUBY_HASH_SPLAT_STAR_STAR] ||
            valid_symbols[RUBY_BINARY_STAR_STAR] {
            lexer.advance(false)
            if lexer.lookahead == '=' {
              return false
            }
            if valid_symbols[RUBY_BINARY_STAR_STAR] &&
              !self.has_leading_whitespace {
              lexer.result_symbol = RUBY_BINARY_STAR_STAR
              return true
            }
            if valid_symbols[RUBY_HASH_SPLAT_STAR_STAR] &&
              !iswspace(lexer.lookahead) {
              lexer.result_symbol = RUBY_HASH_SPLAT_STAR_STAR
              return true
            }
            if valid_symbols[RUBY_BINARY_STAR_STAR] {
              lexer.result_symbol = RUBY_BINARY_STAR_STAR
              return true
            }
            if valid_symbols[RUBY_HASH_SPLAT_STAR_STAR] {
              lexer.result_symbol = RUBY_HASH_SPLAT_STAR_STAR
              return true
            }
            return false
          }
          return false
        }
        if valid_symbols[RUBY_BINARY_STAR] && !self.has_leading_whitespace {
          lexer.result_symbol = RUBY_BINARY_STAR
          return true
        }
        if valid_symbols[RUBY_SPLAT_STAR] && !iswspace(lexer.lookahead) {
          lexer.result_symbol = RUBY_SPLAT_STAR
          return true
        }
        if valid_symbols[RUBY_BINARY_STAR] {
          lexer.result_symbol = RUBY_BINARY_STAR
          return true
        }
        if valid_symbols[RUBY_SPLAT_STAR] {
          lexer.result_symbol = RUBY_SPLAT_STAR
          return true
        }
        return false
      }
    '-' =>
      if valid_symbols[RUBY_UNARY_MINUS] ||
        valid_symbols[RUBY_UNARY_MINUS_NUM] ||
        valid_symbols[RUBY_BINARY_MINUS] {
        lexer.advance(false)
        if lexer.lookahead != '=' && lexer.lookahead != '>' {
          if valid_symbols[RUBY_UNARY_MINUS_NUM] &&
            (!valid_symbols[RUBY_BINARY_STAR] || self.has_leading_whitespace) &&
            iswdigit(lexer.lookahead) {
            lexer.result_symbol = RUBY_UNARY_MINUS_NUM
            return true
          }
          if valid_symbols[RUBY_UNARY_MINUS] &&
            self.has_leading_whitespace &&
            !iswspace(lexer.lookahead) {
            lexer.result_symbol = RUBY_UNARY_MINUS
          } else if valid_symbols[RUBY_BINARY_MINUS] {
            lexer.result_symbol = RUBY_BINARY_MINUS
          } else {
            lexer.result_symbol = RUBY_UNARY_MINUS
          }
          return true
        }
        return false
      }
    ':' =>
      if valid_symbols[RUBY_SYMBOL_START] {
        let literal = ruby_literal_new()
        literal.type_ = RUBY_SYMBOL_START
        literal.nesting_depth = 1
        lexer.advance(false)
        match lexer.lookahead {
          '"' => {
            lexer.advance(false)
            literal.open_delimiter = '"'
            literal.close_delimiter = '"'
            literal.allows_interpolation = true
            self.literal_stack.push(literal)
            lexer.result_symbol = RUBY_SYMBOL_START
            return true
          }
          '\'' => {
            lexer.advance(false)
            literal.open_delimiter = '\''
            literal.close_delimiter = '\''
            literal.allows_interpolation = false
            self.literal_stack.push(literal)
            lexer.result_symbol = RUBY_SYMBOL_START
            return true
          }
          _ =>
            if ruby_scan_symbol_identifier(lexer) {
              lexer.result_symbol = RUBY_SIMPLE_SYMBOL
              return true
            }
        }
        return false
      }
    '[' =>
      // Treat a square bracket as an element reference if either:
      // * the bracket is not preceded by any whitespace
      // * an arbitrary expression is not valid at the current position.
      if valid_symbols[RUBY_ELEMENT_REFERENCE_BRACKET] &&
        (!self.has_leading_whitespace || !valid_symbols[RUBY_STRING_START]) {
        lexer.advance(false)
        lexer.result_symbol = RUBY_ELEMENT_REFERENCE_BRACKET
        return true
      }
    _ => ()
  }

  // Open delimiters for literals
  if (
      (
        valid_symbols[RUBY_HASH_KEY_SYMBOL] ||
        valid_symbols[RUBY_IDENTIFIER_SUFFIX]
      ) &&
      (iswalpha(lexer.lookahead) || lexer.lookahead == '_')
    ) ||
    (valid_symbols[RUBY_CONSTANT_SUFFIX] && iswupper(lexer.lookahead)) {
    let valid_identifier_symbol = if iswupper(lexer.lookahead) {
      RUBY_CONSTANT_SUFFIX
    } else {
      RUBY_IDENTIFIER_SUFFIX
    }
    while iswalnum(lexer.lookahead) || lexer.lookahead == '_' {
      lexer.advance(false)
    }
    if valid_symbols[RUBY_HASH_KEY_SYMBOL] && lexer.lookahead == ':' {
      lexer.mark_end()
      lexer.advance(false)
      if lexer.lookahead != ':' {
        lexer.result_symbol = RUBY_HASH_KEY_SYMBOL
        return true
      }
    } else if valid_symbols[valid_identifier_symbol] && lexer.lookahead == '!' {
      lexer.advance(false)
      if lexer.lookahead != '=' {
        lexer.result_symbol = valid_identifier_symbol
        return true
      }
    }
    return false
  }

  // Open delimiters for literals
  if valid_symbols[RUBY_STRING_START] {
    let literal = ruby_literal_new()
    literal.nesting_depth = 1
    if lexer.lookahead == '<' {
      lexer.advance(false)
      if lexer.lookahead != '<' {
        return false
      }
      lexer.advance(false)
      let heredoc : RubyHeredoc = {
        word: [],
        end_word_indentation_allowed: false,
        allows_interpolation: false,
        started: false,
      }
      if lexer.lookahead == '-' || lexer.lookahead == '~' {
        lexer.advance(false)
        heredoc.end_word_indentation_allowed = true
      }
      ruby_scan_heredoc_word(lexer, heredoc)
      if heredoc.word.length() == 0 {
        return false
      }
      self.open_heredocs.push(heredoc)
      lexer.result_symbol = RUBY_HEREDOC_START
      return true
    }
    if self.scan_open_delimiter(lexer, literal, valid_symbols) {
      self.literal_stack.push(literal)
      lexer.result_symbol = literal.type_
      return true
    }
    return false
  }
  false
}

///|
fn ruby_scanner() -> @runtime.ExternalScanner {
  let scanner : RubyScanner = {
    has_leading_whitespace: false,
    literal_stack: [],
    open_heredocs: [],
  }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => (),
  }
}
