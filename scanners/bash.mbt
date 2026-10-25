// Port of tree-sitter-bash src/scanner.c (v0.25.0)
// tree-sitter-bash is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`.
const BASH_HEREDOC_START : Int32 = 0

///|
const BASH_SIMPLE_HEREDOC_BODY : Int32 = 1

///|
const BASH_HEREDOC_BODY_BEGINNING : Int32 = 2

///|
const BASH_HEREDOC_CONTENT : Int32 = 3

///|
const BASH_HEREDOC_END : Int32 = 4

///|
const BASH_FILE_DESCRIPTOR : Int32 = 5

///|
const BASH_EMPTY_VALUE : Int32 = 6

///|
const BASH_CONCAT : Int32 = 7

///|
const BASH_VARIABLE_NAME : Int32 = 8

///|
const BASH_TEST_OPERATOR : Int32 = 9

///|
const BASH_REGEX : Int32 = 10

///|
const BASH_REGEX_NO_SLASH : Int32 = 11

///|
const BASH_REGEX_NO_SPACE : Int32 = 12

///|
const BASH_EXPANSION_WORD : Int32 = 13

///|
const BASH_EXTGLOB_PATTERN : Int32 = 14

///|
const BASH_BARE_DOLLAR : Int32 = 15

///|
const BASH_BRACE_START : Int32 = 16

///|
const BASH_IMMEDIATE_DOUBLE_HASH : Int32 = 17

///|
const BASH_EXTERNAL_EXPANSION_SYM_HASH : Int32 = 18

///|
const BASH_EXTERNAL_EXPANSION_SYM_BANG : Int32 = 19

///|
const BASH_EXTERNAL_EXPANSION_SYM_EQUAL : Int32 = 20

///|
const BASH_CLOSING_BRACE : Int32 = 21

///|
const BASH_CLOSING_BRACKET : Int32 = 22

///|
const BASH_HEREDOC_ARROW : Int32 = 23

///|
const BASH_HEREDOC_ARROW_DASH : Int32 = 24

///|
const BASH_NEWLINE : Int32 = 25

///|
const BASH_OPENING_PAREN : Int32 = 26

///|
/// Unused by the scanner; kept to mirror `enum TokenType`.
#warnings("-unused_value")
const BASH_ESAC : Int32 = 27

///|
const BASH_ERROR_RECOVERY : Int32 = 28

///|
/// `typedef Array(char) String;` holds C `char` values (signed, -128..=127).
priv struct BashHeredoc {
  mut is_raw : Bool
  mut started : Bool
  mut allows_indent : Bool
  delimiter : Array[Int32]
  current_leading_word : Array[Int32]
}

///|
fn bash_heredoc_new() -> BashHeredoc {
  {
    is_raw: false,
    started: false,
    allows_indent: false,
    delimiter: [],
    current_leading_word: [],
  }
}

///|
priv struct BashScanner {
  /// `uint8_t last_glob_paren_depth`.
  mut last_glob_paren_depth : Int32
  mut ext_was_in_double_quote : Bool
  mut ext_saw_outside_quote : Bool
  heredocs : Array[BashHeredoc]
}

///|
fn bash_in_error_recovery(valid_symbols : ArrayView[Bool]) -> Bool {
  valid_symbols[BASH_ERROR_RECOVERY]
}

///|
fn bash_reset_string(string : Array[Int32]) -> Unit {
  if string.length() > 0 {
    string.clear()
  }
}

///|
fn BashHeredoc::reset(self : BashHeredoc) -> Unit {
  self.is_raw = false
  self.started = false
  self.allows_indent = false
  bash_reset_string(self.delimiter)
}

///|
fn BashScanner::reset(self : BashScanner) -> Unit {
  for heredoc in self.heredocs {
    heredoc.reset()
  }
}

///|
fn bash_bool_byte(b : Bool) -> Byte {
  if b {
    1
  } else {
    0
  }
}

///|
fn BashScanner::serialize(
  self : BashScanner,
  buffer : FixedArray[Byte],
) -> Int32 {
  let mut size = 0
  buffer[size] = self.last_glob_paren_depth.to_byte()
  size += 1
  buffer[size] = bash_bool_byte(self.ext_was_in_double_quote)
  size += 1
  buffer[size] = bash_bool_byte(self.ext_saw_outside_quote)
  size += 1
  buffer[size] = self.heredocs.length().to_byte()
  size += 1
  for heredoc in self.heredocs {
    if size + 3 + 4 + heredoc.delimiter.length() >= SERIALIZATION_BUFFER_SIZE {
      return 0
    }
    buffer[size] = bash_bool_byte(heredoc.is_raw)
    size += 1
    buffer[size] = bash_bool_byte(heredoc.started)
    size += 1
    buffer[size] = bash_bool_byte(heredoc.allows_indent)
    size += 1
    // memcpy of the little-endian `uint32_t` size.
    let n = heredoc.delimiter.length()
    for k in 0..<4 {
      buffer[size + k] = (n >> (8 * k)).to_byte()
    }
    size += 4
    if n > 0 {
      for i in 0..<n {
        buffer[size + i] = heredoc.delimiter[i].to_byte()
      }
      size += n
    }
  }
  size
}

///|
fn BashScanner::deserialize(self : BashScanner, buffer : BytesView) -> Unit {
  let length = buffer.length()
  if length == 0 {
    self.reset()
  } else {
    let mut size = 0
    self.last_glob_paren_depth = buffer[size].to_int()
    size += 1
    self.ext_was_in_double_quote = buffer[size] != 0
    size += 1
    self.ext_saw_outside_quote = buffer[size] != 0
    size += 1
    let heredoc_count = buffer[size].to_int()
    size += 1
    for i in 0..<heredoc_count {
      let heredoc = if i < self.heredocs.length() {
        self.heredocs[i]
      } else {
        let new_heredoc = bash_heredoc_new()
        self.heredocs.push(new_heredoc)
        new_heredoc
      }
      heredoc.is_raw = buffer[size] != 0
      size += 1
      heredoc.started = buffer[size] != 0
      size += 1
      heredoc.allows_indent = buffer[size] != 0
      size += 1
      let mut n = 0
      for k in 0..<4 {
        n = n | (buffer[size + k].to_int() << (8 * k))
      }
      size += 4
      heredoc.delimiter.clear()
      if n > 0 {
        for j in 0..<n {
          heredoc.delimiter.push(to_c_char(buffer[size + j].to_int()))
        }
        size += n
      }
    }
    guard size == length else { abort("assert(size == length)") }
  }
}

///|
/// Consume a "word" in POSIX parlance, and returns it unquoted.
///
/// This is an approximate implementation that doesn't deal with any
/// POSIX-mandated substitution, and assumes the default value for
/// IFS.
fn bash_advance_word(
  lexer : @runtime.Lexer,
  unquoted_word : Array[Int32],
) -> Bool {
  let mut empty = true
  let mut quote = 0
  if lexer.lookahead == '\'' || lexer.lookahead == '"' {
    quote = lexer.lookahead
    lexer.advance(false)
  }
  while lexer.lookahead != 0 &&
        !(if quote != 0 {
          lexer.lookahead == quote ||
          lexer.lookahead == '\r' ||
          lexer.lookahead == '\n'
        } else {
          iswspace(lexer.lookahead)
        }) {
    if lexer.lookahead == '\\' {
      lexer.advance(false)
      if lexer.lookahead == 0 {
        return false
      }
    }
    empty = false
    unquoted_word.push(to_c_char(lexer.lookahead))
    lexer.advance(false)
  }
  unquoted_word.push(0)
  if quote != 0 && lexer.lookahead == quote {
    lexer.advance(false)
  }
  !empty
}

///|
fn bash_scan_bare_dollar(lexer : @runtime.Lexer) -> Bool {
  while iswspace(lexer.lookahead) && lexer.lookahead != '\n' && !lexer.eof() {
    lexer.advance(true)
  }
  if lexer.lookahead == '$' {
    lexer.advance(false)
    lexer.result_symbol = BASH_BARE_DOLLAR
    lexer.mark_end()
    return iswspace(lexer.lookahead) || lexer.eof() || lexer.lookahead == '"'
  }
  false
}

///|
fn bash_scan_heredoc_start(
  heredoc : BashHeredoc,
  lexer : @runtime.Lexer,
) -> Bool {
  while iswspace(lexer.lookahead) {
    lexer.advance(true)
  }
  lexer.result_symbol = BASH_HEREDOC_START
  heredoc.is_raw = lexer.lookahead == '\'' ||
    lexer.lookahead == '"' ||
    lexer.lookahead == '\\'
  let found_delimiter = bash_advance_word(lexer, heredoc.delimiter)
  if !found_delimiter {
    bash_reset_string(heredoc.delimiter)
    return false
  }
  found_delimiter
}

///|
/// `strcmp(a, b) == 0` on NUL-terminated `char` arrays.
fn bash_strcmp_eq(a : Array[Int32], b : Array[Int32]) -> Bool {
  for i = 0; ; i = i + 1 {
    let x = a[i] & 0xFF
    let y = b[i] & 0xFF
    if x != y {
      return false
    }
    if x == 0 {
      return true
    }
  }
}

///|
fn bash_scan_heredoc_end_identifier(
  heredoc : BashHeredoc,
  lexer : @runtime.Lexer,
) -> Bool {
  bash_reset_string(heredoc.current_leading_word)
  // Scan the first 'n' characters on this line, to see if they match the
  // heredoc delimiter
  let mut size = 0
  if heredoc.delimiter.length() > 0 {
    while lexer.lookahead != 0 &&
          lexer.lookahead != '\n' &&
          heredoc.delimiter[size] == lexer.lookahead &&
          heredoc.current_leading_word.length() < heredoc.delimiter.length() {
      heredoc.current_leading_word.push(to_c_char(lexer.lookahead))
      lexer.advance(false)
      size += 1
    }
  }
  heredoc.current_leading_word.push(0)
  if heredoc.delimiter.length() == 0 {
    false
  } else {
    bash_strcmp_eq(heredoc.current_leading_word, heredoc.delimiter)
  }
}

///|
fn BashScanner::scan_heredoc_content(
  self : BashScanner,
  lexer : @runtime.Lexer,
  middle_type : Int32,
  end_type : Int32,
) -> Bool {
  let mut did_advance = false
  let heredoc = self.heredocs[self.heredocs.length() - 1]
  for ;; {
    match lexer.lookahead {
      '\u{0}' => {
        if lexer.eof() && did_advance {
          heredoc.reset()
          lexer.result_symbol = end_type
          return true
        }
        return false
      }
      '\\' => {
        did_advance = true
        lexer.advance(false)
        lexer.advance(false)
      }
      '$' => {
        if heredoc.is_raw {
          did_advance = true
          lexer.advance(false)
          continue
        }
        if did_advance {
          lexer.mark_end()
          lexer.result_symbol = middle_type
          heredoc.started = true
          lexer.advance(false)
          if iswalpha(lexer.lookahead) ||
            lexer.lookahead == '{' ||
            lexer.lookahead == '(' {
            return true
          }
          continue
        }
        if middle_type == BASH_HEREDOC_BODY_BEGINNING && lexer.get_column() == 0 {
          lexer.result_symbol = middle_type
          heredoc.started = true
          return true
        }
        return false
      }
      '\n' => {
        if !did_advance {
          lexer.advance(true)
        } else {
          lexer.advance(false)
        }
        did_advance = true
        if heredoc.allows_indent {
          while iswspace(lexer.lookahead) {
            lexer.advance(false)
          }
        }
        lexer.result_symbol = if heredoc.started {
          middle_type
        } else {
          end_type
        }
        lexer.mark_end()
        if bash_scan_heredoc_end_identifier(heredoc, lexer) {
          if lexer.result_symbol == BASH_HEREDOC_END {
            ignore(self.heredocs.pop())
          }
          return true
        }
      }
      _ => {
        if lexer.get_column() == 0 {
          // an alternative is to check the starting column of the
          // heredoc body and track that statefully
          while iswspace(lexer.lookahead) {
            if did_advance {
              lexer.advance(false)
            } else {
              lexer.advance(true)
            }
          }
          if end_type != BASH_SIMPLE_HEREDOC_BODY {
            lexer.result_symbol = middle_type
            if bash_scan_heredoc_end_identifier(heredoc, lexer) {
              return true
            }
          }
          if end_type == BASH_SIMPLE_HEREDOC_BODY {
            lexer.result_symbol = end_type
            lexer.mark_end()
            if bash_scan_heredoc_end_identifier(heredoc, lexer) {
              return true
            }
          }
        }
        did_advance = true
        lexer.advance(false)
      }
    }
  }
}

///|
fn BashScanner::scan(
  self : BashScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[BASH_CONCAT] && !bash_in_error_recovery(valid_symbols) {
    if !(lexer.lookahead == 0 ||
      iswspace(lexer.lookahead) ||
      lexer.lookahead == '>' ||
      lexer.lookahead == '<' ||
      lexer.lookahead == ')' ||
      lexer.lookahead == '(' ||
      lexer.lookahead == ';' ||
      lexer.lookahead == '&' ||
      lexer.lookahead == '|' ||
      (lexer.lookahead == '}' && valid_symbols[BASH_CLOSING_BRACE]) ||
      (lexer.lookahead == ']' && valid_symbols[BASH_CLOSING_BRACKET])) {
      lexer.result_symbol = BASH_CONCAT
      // So for a`b`, we want to return a concat. We check if the
      // 2nd backtick has whitespace after it, and if it does we
      // return concat.
      if lexer.lookahead == '`' {
        lexer.mark_end()
        lexer.advance(false)
        while lexer.lookahead != '`' && !lexer.eof() {
          lexer.advance(false)
        }
        if lexer.eof() {
          return false
        }
        if lexer.lookahead == '`' {
          lexer.advance(false)
        }
        return iswspace(lexer.lookahead) || lexer.eof()
      }
      // strings w/ expansions that contains escaped quotes or
      // backslashes need this to return a concat
      if lexer.lookahead == '\\' {
        lexer.mark_end()
        lexer.advance(false)
        if lexer.lookahead == '"' ||
          lexer.lookahead == '\'' ||
          lexer.lookahead == '\\' {
          return true
        }
        if lexer.eof() {
          return false
        }
      } else {
        return true
      }
    }
    if iswspace(lexer.lookahead) &&
      valid_symbols[BASH_CLOSING_BRACE] &&
      !valid_symbols[BASH_EXPANSION_WORD] {
      lexer.result_symbol = BASH_CONCAT
      return true
    }
  }
  if valid_symbols[BASH_IMMEDIATE_DOUBLE_HASH] &&
    !bash_in_error_recovery(valid_symbols) {
    // advance two # and ensure not } after
    if lexer.lookahead == '#' {
      lexer.mark_end()
      lexer.advance(false)
      if lexer.lookahead == '#' {
        lexer.advance(false)
        if lexer.lookahead != '}' {
          lexer.result_symbol = BASH_IMMEDIATE_DOUBLE_HASH
          lexer.mark_end()
          return true
        }
      }
    }
  }
  if valid_symbols[BASH_EXTERNAL_EXPANSION_SYM_HASH] &&
    !bash_in_error_recovery(valid_symbols) {
    if lexer.lookahead == '#' ||
      lexer.lookahead == '=' ||
      lexer.lookahead == '!' {
      lexer.result_symbol = if lexer.lookahead == '#' {
        BASH_EXTERNAL_EXPANSION_SYM_HASH
      } else if lexer.lookahead == '!' {
        BASH_EXTERNAL_EXPANSION_SYM_BANG
      } else {
        BASH_EXTERNAL_EXPANSION_SYM_EQUAL
      }
      lexer.advance(false)
      lexer.mark_end()
      while lexer.lookahead == '#' ||
            lexer.lookahead == '=' ||
            lexer.lookahead == '!' {
        lexer.advance(false)
      }
      while iswspace(lexer.lookahead) {
        lexer.advance(true)
      }
      if lexer.lookahead == '}' {
        return true
      }
      return false
    }
  }
  if valid_symbols[BASH_EMPTY_VALUE] {
    if iswspace(lexer.lookahead) ||
      lexer.eof() ||
      lexer.lookahead == ';' ||
      lexer.lookahead == '&' {
      lexer.result_symbol = BASH_EMPTY_VALUE
      return true
    }
  }
  if (
      valid_symbols[BASH_HEREDOC_BODY_BEGINNING] ||
      valid_symbols[BASH_SIMPLE_HEREDOC_BODY]
    ) &&
    self.heredocs.length() > 0 &&
    !self.heredocs[self.heredocs.length() - 1].started &&
    !bash_in_error_recovery(valid_symbols) {
    return self.scan_heredoc_content(
      lexer,
      BASH_HEREDOC_BODY_BEGINNING,
      BASH_SIMPLE_HEREDOC_BODY,
    )
  }
  if valid_symbols[BASH_HEREDOC_END] && self.heredocs.length() > 0 {
    let heredoc = self.heredocs[self.heredocs.length() - 1]
    if bash_scan_heredoc_end_identifier(heredoc, lexer) {
      heredoc.current_leading_word.clear()
      heredoc.delimiter.clear()
      ignore(self.heredocs.pop())
      lexer.result_symbol = BASH_HEREDOC_END
      return true
    }
  }
  if valid_symbols[BASH_HEREDOC_CONTENT] &&
    self.heredocs.length() > 0 &&
    self.heredocs[self.heredocs.length() - 1].started &&
    !bash_in_error_recovery(valid_symbols) {
    return self.scan_heredoc_content(
      lexer,
      BASH_HEREDOC_CONTENT,
      BASH_HEREDOC_END,
    )
  }
  if valid_symbols[BASH_HEREDOC_START] &&
    !bash_in_error_recovery(valid_symbols) &&
    self.heredocs.length() > 0 {
    return bash_scan_heredoc_start(
      self.heredocs[self.heredocs.length() - 1],
      lexer,
    )
  }
  if valid_symbols[BASH_TEST_OPERATOR] && !valid_symbols[BASH_EXPANSION_WORD] {
    while iswspace(lexer.lookahead) && lexer.lookahead != '\n' {
      lexer.advance(true)
    }
    if lexer.lookahead == '\\' {
      if valid_symbols[BASH_EXTGLOB_PATTERN] {
        return self.scan_extglob_pattern(lexer, valid_symbols)
      }
      if valid_symbols[BASH_REGEX_NO_SPACE] {
        return self.scan_regex(lexer, valid_symbols)
      }
      lexer.advance(true)
      if lexer.eof() {
        return false
      }
      if lexer.lookahead == '\r' {
        lexer.advance(true)
        if lexer.lookahead == '\n' {
          lexer.advance(true)
        }
      } else if lexer.lookahead == '\n' {
        lexer.advance(true)
      } else {
        return false
      }
      while iswspace(lexer.lookahead) {
        lexer.advance(true)
      }
    }
    if lexer.lookahead == '\n' && !valid_symbols[BASH_NEWLINE] {
      lexer.advance(true)
      while iswspace(lexer.lookahead) {
        lexer.advance(true)
      }
    }
    if lexer.lookahead == '-' {
      lexer.advance(false)
      let mut advanced_once = false
      while iswalpha(lexer.lookahead) {
        advanced_once = true
        lexer.advance(false)
      }
      if iswspace(lexer.lookahead) && advanced_once {
        lexer.mark_end()
        lexer.advance(false)
        if lexer.lookahead == '}' && valid_symbols[BASH_CLOSING_BRACE] {
          if valid_symbols[BASH_EXPANSION_WORD] {
            lexer.mark_end()
            lexer.result_symbol = BASH_EXPANSION_WORD
            return true
          }
          return false
        }
        lexer.result_symbol = BASH_TEST_OPERATOR
        return true
      }
      if iswspace(lexer.lookahead) && valid_symbols[BASH_EXTGLOB_PATTERN] {
        lexer.result_symbol = BASH_EXTGLOB_PATTERN
        return true
      }
    }
    if valid_symbols[BASH_BARE_DOLLAR] &&
      !bash_in_error_recovery(valid_symbols) &&
      bash_scan_bare_dollar(lexer) {
      return true
    }
  }
  if (
      valid_symbols[BASH_VARIABLE_NAME] ||
      valid_symbols[BASH_FILE_DESCRIPTOR] ||
      valid_symbols[BASH_HEREDOC_ARROW]
    ) &&
    !valid_symbols[BASH_REGEX_NO_SLASH] &&
    !bash_in_error_recovery(valid_symbols) {
    for ;; {
      if (
          lexer.lookahead == ' ' ||
          lexer.lookahead == '\t' ||
          lexer.lookahead == '\r' ||
          (lexer.lookahead == '\n' && !valid_symbols[BASH_NEWLINE])
        ) &&
        !valid_symbols[BASH_EXPANSION_WORD] {
        lexer.advance(true)
      } else if lexer.lookahead == '\\' {
        lexer.advance(true)
        if lexer.eof() {
          lexer.mark_end()
          lexer.result_symbol = BASH_VARIABLE_NAME
          return true
        }
        if lexer.lookahead == '\r' {
          lexer.advance(true)
        }
        if lexer.lookahead == '\n' {
          lexer.advance(true)
        } else {
          if lexer.lookahead == '\\' && valid_symbols[BASH_EXPANSION_WORD] {
            return bash_scan_expansion_word(lexer, valid_symbols)
          }
          return false
        }
      } else {
        break
      }
    }

    // no '*', '@', '?', '-', '$', '0', '_'
    if !valid_symbols[BASH_EXPANSION_WORD] &&
      (
        lexer.lookahead == '*' ||
        lexer.lookahead == '@' ||
        lexer.lookahead == '?' ||
        lexer.lookahead == '-' ||
        lexer.lookahead == '0' ||
        lexer.lookahead == '_'
      ) {
      lexer.mark_end()
      lexer.advance(false)
      if lexer.lookahead == '=' ||
        lexer.lookahead == '[' ||
        lexer.lookahead == ':' ||
        lexer.lookahead == '-' ||
        lexer.lookahead == '%' ||
        lexer.lookahead == '#' ||
        lexer.lookahead == '/' {
        return false
      }
      if valid_symbols[BASH_EXTGLOB_PATTERN] && iswspace(lexer.lookahead) {
        lexer.mark_end()
        lexer.result_symbol = BASH_EXTGLOB_PATTERN
        return true
      }
    }
    if valid_symbols[BASH_HEREDOC_ARROW] && lexer.lookahead == '<' {
      lexer.advance(false)
      if lexer.lookahead == '<' {
        lexer.advance(false)
        if lexer.lookahead == '-' {
          lexer.advance(false)
          let heredoc = bash_heredoc_new()
          heredoc.allows_indent = true
          self.heredocs.push(heredoc)
          lexer.result_symbol = BASH_HEREDOC_ARROW_DASH
        } else if lexer.lookahead == '<' || lexer.lookahead == '=' {
          return false
        } else {
          let heredoc = bash_heredoc_new()
          self.heredocs.push(heredoc)
          lexer.result_symbol = BASH_HEREDOC_ARROW
        }
        return true
      }
      return false
    }
    let mut is_number = true
    if iswdigit(lexer.lookahead) {
      lexer.advance(false)
    } else if iswalpha(lexer.lookahead) || lexer.lookahead == '_' {
      is_number = false
      lexer.advance(false)
    } else {
      if lexer.lookahead == '{' {
        return bash_scan_brace_start(lexer, valid_symbols)
      }
      if valid_symbols[BASH_EXPANSION_WORD] {
        return bash_scan_expansion_word(lexer, valid_symbols)
      }
      if valid_symbols[BASH_EXTGLOB_PATTERN] {
        return self.scan_extglob_pattern(lexer, valid_symbols)
      }
      return false
    }
    for ;; {
      if iswdigit(lexer.lookahead) {
        lexer.advance(false)
      } else if iswalpha(lexer.lookahead) || lexer.lookahead == '_' {
        is_number = false
        lexer.advance(false)
      } else {
        break
      }
    }
    if is_number &&
      valid_symbols[BASH_FILE_DESCRIPTOR] &&
      (lexer.lookahead == '>' || lexer.lookahead == '<') {
      lexer.result_symbol = BASH_FILE_DESCRIPTOR
      return true
    }
    if valid_symbols[BASH_VARIABLE_NAME] {
      if lexer.lookahead == '+' {
        lexer.mark_end()
        lexer.advance(false)
        if lexer.lookahead == '=' ||
          lexer.lookahead == ':' ||
          valid_symbols[BASH_CLOSING_BRACE] {
          lexer.result_symbol = BASH_VARIABLE_NAME
          return true
        }
        return false
      }
      if lexer.lookahead == '/' {
        return false
      }
      if lexer.lookahead == '=' ||
        lexer.lookahead == '[' ||
        (
          lexer.lookahead == ':' &&
          !valid_symbols[BASH_CLOSING_BRACE] &&
          !valid_symbols[BASH_OPENING_PAREN]
        ) || // TODO(amaanq): more cases for regular word chars but not variable
        // names for function words, only handling : for now? #235
        lexer.lookahead == '%' ||
        (lexer.lookahead == '#' && !is_number) ||
        lexer.lookahead == '@' ||
        (lexer.lookahead == '-' && valid_symbols[BASH_CLOSING_BRACE]) {
        lexer.mark_end()
        lexer.result_symbol = BASH_VARIABLE_NAME
        return true
      }
      if lexer.lookahead == '?' {
        lexer.mark_end()
        lexer.advance(false)
        lexer.result_symbol = BASH_VARIABLE_NAME
        return iswalpha(lexer.lookahead)
      }
    }
    return false
  }
  if valid_symbols[BASH_BARE_DOLLAR] &&
    !bash_in_error_recovery(valid_symbols) &&
    bash_scan_bare_dollar(lexer) {
    return true
  }
  self.scan_regex(lexer, valid_symbols)
}

///|
/// The code from the C label `regex:` up to the label `extglob_pattern:`
/// (which it falls through to).
fn BashScanner::scan_regex(
  self : BashScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if (
      valid_symbols[BASH_REGEX] ||
      valid_symbols[BASH_REGEX_NO_SLASH] ||
      valid_symbols[BASH_REGEX_NO_SPACE]
    ) &&
    !bash_in_error_recovery(valid_symbols) {
    if valid_symbols[BASH_REGEX] || valid_symbols[BASH_REGEX_NO_SPACE] {
      while iswspace(lexer.lookahead) {
        lexer.advance(true)
      }
    }
    if (lexer.lookahead != '"' && lexer.lookahead != '\'') ||
      (
        (lexer.lookahead == '$' || lexer.lookahead == '\'') &&
        valid_symbols[BASH_REGEX_NO_SLASH]
      ) ||
      (lexer.lookahead == '\'' && valid_symbols[BASH_REGEX_NO_SPACE]) {
      if lexer.lookahead == '$' && valid_symbols[BASH_REGEX_NO_SLASH] {
        lexer.mark_end()
        lexer.advance(false)
        if lexer.lookahead == '(' {
          return false
        }
      }
      lexer.mark_end()
      let mut done = false
      let mut advanced_once = false
      let mut found_non_alnumdollarunderdash = false
      let mut last_was_escape = false
      let mut in_single_quote = false
      let mut paren_depth : UInt32 = 0
      let mut bracket_depth : UInt32 = 0
      let mut brace_depth : UInt32 = 0
      while !done {
        if in_single_quote {
          if lexer.lookahead == '\'' {
            in_single_quote = false
            lexer.advance(false)
            lexer.mark_end()
          }
        }
        match lexer.lookahead {
          '\\' => last_was_escape = true
          '\u{0}' => return false
          '(' => {
            paren_depth += 1
            last_was_escape = false
          }
          '[' => {
            bracket_depth += 1
            last_was_escape = false
          }
          '{' => {
            if !last_was_escape {
              brace_depth += 1
            }
            last_was_escape = false
          }
          ')' => {
            if paren_depth == 0 {
              done = true
            }
            paren_depth -= 1
            last_was_escape = false
          }
          ']' => {
            if bracket_depth == 0 {
              done = true
            }
            bracket_depth -= 1
            last_was_escape = false
          }
          '}' => {
            if brace_depth == 0 {
              done = true
            }
            brace_depth -= 1
            last_was_escape = false
          }
          '\'' => {
            // Enter or exit a single-quoted string.
            in_single_quote = !in_single_quote
            lexer.advance(false)
            advanced_once = true
            last_was_escape = false
            continue
          }
          _ => last_was_escape = false
        }
        if !done {
          if valid_symbols[BASH_REGEX] {
            let was_space = !in_single_quote && iswspace(lexer.lookahead)
            lexer.advance(false)
            advanced_once = true
            if !was_space || paren_depth > 0 {
              lexer.mark_end()
            }
          } else if valid_symbols[BASH_REGEX_NO_SLASH] {
            if lexer.lookahead == '/' {
              lexer.mark_end()
              lexer.result_symbol = BASH_REGEX_NO_SLASH
              return advanced_once
            }
            if lexer.lookahead == '\\' {
              lexer.advance(false)
              advanced_once = true
              if !lexer.eof() &&
                lexer.lookahead != '[' &&
                lexer.lookahead != '/' {
                lexer.advance(false)
                lexer.mark_end()
              }
            } else {
              let was_space = !in_single_quote && iswspace(lexer.lookahead)
              lexer.advance(false)
              advanced_once = true
              if !was_space {
                lexer.mark_end()
              }
            }
          } else if valid_symbols[BASH_REGEX_NO_SPACE] {
            if lexer.lookahead == '\\' {
              found_non_alnumdollarunderdash = true
              lexer.advance(false)
              if !lexer.eof() {
                lexer.advance(false)
              }
            } else if lexer.lookahead == '$' {
              lexer.mark_end()
              lexer.advance(false)
              // do not parse a command
              // substitution
              if lexer.lookahead == '(' {
                return false
              }
              // end $ always means regex, e.g.
              // 99999999$
              if iswspace(lexer.lookahead) {
                lexer.result_symbol = BASH_REGEX_NO_SPACE
                lexer.mark_end()
                return true
              }
            } else {
              let was_space = !in_single_quote && iswspace(lexer.lookahead)
              if was_space && paren_depth == 0 {
                lexer.mark_end()
                lexer.result_symbol = BASH_REGEX_NO_SPACE
                return found_non_alnumdollarunderdash
              }
              if !iswalnum(lexer.lookahead) &&
                lexer.lookahead != '$' &&
                lexer.lookahead != '-' &&
                lexer.lookahead != '_' {
                found_non_alnumdollarunderdash = true
              }
              lexer.advance(false)
            }
          }
        }
      }
      lexer.result_symbol = if valid_symbols[BASH_REGEX_NO_SLASH] {
        BASH_REGEX_NO_SLASH
      } else if valid_symbols[BASH_REGEX_NO_SPACE] {
        BASH_REGEX_NO_SPACE
      } else {
        BASH_REGEX
      }
      if valid_symbols[BASH_REGEX] && !advanced_once {
        return false
      }
      return true
    }
  }
  self.scan_extglob_pattern(lexer, valid_symbols)
}

///|
/// The code from the C label `extglob_pattern:` up to the label
/// `expansion_word:` (which it falls through to).
fn BashScanner::scan_extglob_pattern(
  self : BashScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[BASH_EXTGLOB_PATTERN] &&
    !bash_in_error_recovery(valid_symbols) {
    // first skip ws, then check for ? * + @ !
    while iswspace(lexer.lookahead) {
      lexer.advance(true)
    }
    if lexer.lookahead == '?' ||
      lexer.lookahead == '*' ||
      lexer.lookahead == '+' ||
      lexer.lookahead == '@' ||
      lexer.lookahead == '!' ||
      lexer.lookahead == '-' ||
      lexer.lookahead == ')' ||
      lexer.lookahead == '\\' ||
      lexer.lookahead == '.' ||
      lexer.lookahead == '[' ||
      iswalpha(lexer.lookahead) {
      if lexer.lookahead == '\\' {
        lexer.advance(false)
        if (iswspace(lexer.lookahead) || lexer.lookahead == '"') &&
          lexer.lookahead != '\r' &&
          lexer.lookahead != '\n' {
          lexer.advance(false)
        } else {
          return false
        }
      }
      if lexer.lookahead == ')' && self.last_glob_paren_depth == 0 {
        lexer.mark_end()
        lexer.advance(false)
        if iswspace(lexer.lookahead) {
          return false
        }
      }
      lexer.mark_end()
      let was_non_alpha = !iswalpha(lexer.lookahead)
      if lexer.lookahead != '[' {
        // no esac
        if lexer.lookahead == 'e' {
          lexer.mark_end()
          lexer.advance(false)
          if lexer.lookahead == 's' {
            lexer.advance(false)
            if lexer.lookahead == 'a' {
              lexer.advance(false)
              if lexer.lookahead == 'c' {
                lexer.advance(false)
                if iswspace(lexer.lookahead) {
                  return false
                }
              }
            }
          }
        } else {
          lexer.advance(false)
        }
      }

      // -\w is just a word, find something else special
      if lexer.lookahead == '-' {
        lexer.mark_end()
        lexer.advance(false)
        while iswalnum(lexer.lookahead) {
          lexer.advance(false)
        }
        if lexer.lookahead == ')' ||
          lexer.lookahead == '\\' ||
          lexer.lookahead == '.' {
          return false
        }
        lexer.mark_end()
      }

      // case item -) or *)
      if lexer.lookahead == ')' && self.last_glob_paren_depth == 0 {
        lexer.mark_end()
        lexer.advance(false)
        if iswspace(lexer.lookahead) {
          lexer.result_symbol = BASH_EXTGLOB_PATTERN
          return was_non_alpha
        }
      }
      if iswspace(lexer.lookahead) {
        lexer.mark_end()
        lexer.result_symbol = BASH_EXTGLOB_PATTERN
        self.last_glob_paren_depth = 0
        return true
      }
      if lexer.lookahead == '$' {
        lexer.mark_end()
        lexer.advance(false)
        if lexer.lookahead == '{' || lexer.lookahead == '(' {
          lexer.result_symbol = BASH_EXTGLOB_PATTERN
          return true
        }
      }
      if lexer.lookahead == '|' {
        lexer.mark_end()
        lexer.advance(false)
        lexer.result_symbol = BASH_EXTGLOB_PATTERN
        return true
      }
      if !iswalnum(lexer.lookahead) &&
        lexer.lookahead != '(' &&
        lexer.lookahead != '"' &&
        lexer.lookahead != '[' &&
        lexer.lookahead != '?' &&
        lexer.lookahead != '/' &&
        lexer.lookahead != '\\' &&
        lexer.lookahead != '_' &&
        lexer.lookahead != '*' {
        return false
      }
      let mut done = false
      let mut saw_non_alphadot = was_non_alpha
      let mut paren_depth : UInt32 = self.last_glob_paren_depth.reinterpret_as_uint()
      let mut bracket_depth : UInt32 = 0
      let mut brace_depth : UInt32 = 0
      while !done {
        match lexer.lookahead {
          '\u{0}' => return false
          '(' => paren_depth += 1
          '[' => bracket_depth += 1
          '{' => brace_depth += 1
          ')' => {
            if paren_depth == 0 {
              done = true
            }
            paren_depth -= 1
          }
          ']' => {
            if bracket_depth == 0 {
              done = true
            }
            bracket_depth -= 1
          }
          '}' => {
            if brace_depth == 0 {
              done = true
            }
            brace_depth -= 1
          }
          _ => ()
        }
        if lexer.lookahead == '|' {
          lexer.mark_end()
          lexer.advance(false)
          if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0 {
            lexer.result_symbol = BASH_EXTGLOB_PATTERN
            return true
          }
        }
        if !done {
          let was_space = iswspace(lexer.lookahead)
          if lexer.lookahead == '$' {
            lexer.mark_end()
            if !iswalpha(lexer.lookahead) &&
              lexer.lookahead != '.' &&
              lexer.lookahead != '\\' {
              saw_non_alphadot = true
            }
            lexer.advance(false)
            if lexer.lookahead == '(' || lexer.lookahead == '{' {
              lexer.result_symbol = BASH_EXTGLOB_PATTERN
              // `uint8_t` truncation of the `uint32_t` depth.
              self.last_glob_paren_depth = paren_depth.reinterpret_as_int() &
                0xFF
              return saw_non_alphadot
            }
          }
          if was_space {
            lexer.mark_end()
            lexer.result_symbol = BASH_EXTGLOB_PATTERN
            self.last_glob_paren_depth = 0
            return saw_non_alphadot
          }
          if lexer.lookahead == '"' {
            lexer.mark_end()
            lexer.result_symbol = BASH_EXTGLOB_PATTERN
            self.last_glob_paren_depth = 0
            return saw_non_alphadot
          }
          if lexer.lookahead == '\\' {
            if !iswalpha(lexer.lookahead) &&
              lexer.lookahead != '.' &&
              lexer.lookahead != '\\' {
              saw_non_alphadot = true
            }
            lexer.advance(false)
            if iswspace(lexer.lookahead) || lexer.lookahead == '"' {
              lexer.advance(false)
            }
          } else {
            if !iswalpha(lexer.lookahead) &&
              lexer.lookahead != '.' &&
              lexer.lookahead != '\\' {
              saw_non_alphadot = true
            }
            lexer.advance(false)
          }
          if !was_space {
            lexer.mark_end()
          }
        }
      }
      lexer.result_symbol = BASH_EXTGLOB_PATTERN
      self.last_glob_paren_depth = 0
      return saw_non_alphadot
    }
    self.last_glob_paren_depth = 0
    return false
  }
  bash_scan_expansion_word(lexer, valid_symbols)
}

///|
/// The code from the C label `expansion_word:` up to the label
/// `brace_start:` (which it falls through to).
fn bash_scan_expansion_word(
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[BASH_EXPANSION_WORD] {
    let mut advanced_once = false
    let mut advance_once_space = false
    for ;; {
      if lexer.lookahead == '"' {
        return false
      }
      if lexer.lookahead == '$' {
        lexer.mark_end()
        lexer.advance(false)
        if lexer.lookahead == '{' ||
          lexer.lookahead == '(' ||
          lexer.lookahead == '\'' ||
          iswalnum(lexer.lookahead) {
          lexer.result_symbol = BASH_EXPANSION_WORD
          return advanced_once
        }
        advanced_once = true
      }
      if lexer.lookahead == '}' {
        lexer.mark_end()
        lexer.result_symbol = BASH_EXPANSION_WORD
        return advanced_once || advance_once_space
      }
      if lexer.lookahead == '(' && !(advanced_once || advance_once_space) {
        lexer.mark_end()
        lexer.advance(false)
        while lexer.lookahead != ')' && !lexer.eof() {
          // if we find a $( or ${ assume this is valid and is
          // a garbage concatenation of some weird word + an
          // expansion
          // I wonder where this can fail
          if lexer.lookahead == '$' {
            lexer.mark_end()
            lexer.advance(false)
            if lexer.lookahead == '{' ||
              lexer.lookahead == '(' ||
              lexer.lookahead == '\'' ||
              iswalnum(lexer.lookahead) {
              lexer.result_symbol = BASH_EXPANSION_WORD
              return advanced_once
            }
            advanced_once = true
          } else {
            advanced_once = advanced_once || !iswspace(lexer.lookahead)
            advance_once_space = advance_once_space || iswspace(lexer.lookahead)
            lexer.advance(false)
          }
        }
        lexer.mark_end()
        if lexer.lookahead == ')' {
          advanced_once = true
          lexer.advance(false)
          lexer.mark_end()
          if lexer.lookahead == '}' {
            return false
          }
        } else {
          return false
        }
      }
      if lexer.lookahead == '\'' {
        return false
      }
      if lexer.eof() {
        return false
      }
      advanced_once = advanced_once || !iswspace(lexer.lookahead)
      advance_once_space = advance_once_space || iswspace(lexer.lookahead)
      lexer.advance(false)
    }
  }
  bash_scan_brace_start(lexer, valid_symbols)
}

///|
/// The code from the C label `brace_start:` to the end of `scan`.
fn bash_scan_brace_start(
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[BASH_BRACE_START] && !bash_in_error_recovery(valid_symbols) {
    while iswspace(lexer.lookahead) {
      lexer.advance(true)
    }
    if lexer.lookahead != '{' {
      return false
    }
    lexer.advance(false)
    lexer.mark_end()
    while isdigit(lexer.lookahead) {
      lexer.advance(false)
    }
    if lexer.lookahead != '.' {
      return false
    }
    lexer.advance(false)
    if lexer.lookahead != '.' {
      return false
    }
    lexer.advance(false)
    while isdigit(lexer.lookahead) {
      lexer.advance(false)
    }
    if lexer.lookahead != '}' {
      return false
    }
    lexer.result_symbol = BASH_BRACE_START
    return true
  }
  false
}

///|
fn bash_scanner() -> @runtime.ExternalScanner {
  let scanner : BashScanner = {
    last_glob_paren_depth: 0,
    ext_was_in_double_quote: false,
    ext_saw_outside_quote: false,
    heredocs: [],
  }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => (),
  }
}
