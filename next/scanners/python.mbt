// Port of tree-sitter-python src/scanner.c (v0.23.6)
// tree-sitter-python is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`.
const PY_NEWLINE : Int32 = 0

///|
const PY_INDENT : Int32 = 1

///|
const PY_DEDENT : Int32 = 2

///|
const PY_STRING_START : Int32 = 3

///|
const PY_STRING_CONTENT : Int32 = 4

///|
const PY_ESCAPE_INTERPOLATION : Int32 = 5

///|
const PY_STRING_END : Int32 = 6

///|
const PY_COMMENT : Int32 = 7

///|
const PY_CLOSE_PAREN : Int32 = 8

///|
const PY_CLOSE_BRACKET : Int32 = 9

///|
const PY_CLOSE_BRACE : Int32 = 10

///|
const PY_EXCEPT : Int32 = 11

///|
/// `Flags`.
const PY_SINGLE_QUOTE : Int32 = 0x01

///|
const PY_DOUBLE_QUOTE : Int32 = 0x02

///|
const PY_BACK_QUOTE : Int32 = 0x04

///|
const PY_RAW : Int32 = 0x08

///|
const PY_FORMAT : Int32 = 0x10

///|
const PY_TRIPLE : Int32 = 0x20

///|
const PY_BYTES : Int32 = 0x40

///|
/// `typedef struct { char flags; } Delimiter;` is represented by its flags
/// byte (0..=255).
fn py_is_format(delimiter : Int32) -> Bool {
  (delimiter & PY_FORMAT) != 0
}

///|
fn py_is_raw(delimiter : Int32) -> Bool {
  (delimiter & PY_RAW) != 0
}

///|
fn py_is_triple(delimiter : Int32) -> Bool {
  (delimiter & PY_TRIPLE) != 0
}

///|
fn py_is_bytes(delimiter : Int32) -> Bool {
  (delimiter & PY_BYTES) != 0
}

///|
fn py_end_character(delimiter : Int32) -> Int32 {
  if (delimiter & PY_SINGLE_QUOTE) != 0 {
    return '\''
  }
  if (delimiter & PY_DOUBLE_QUOTE) != 0 {
    return '"'
  }
  if (delimiter & PY_BACK_QUOTE) != 0 {
    return '`'
  }
  0
}

///|
fn py_set_end_character(delimiter : Int32, character : Int32) -> Int32 {
  match character {
    '\'' => delimiter | PY_SINGLE_QUOTE
    '"' => delimiter | PY_DOUBLE_QUOTE
    '`' => delimiter | PY_BACK_QUOTE
    _ => abort("assert(false)")
  }
}

///|
priv struct PyScanner {
  /// `Array(uint16_t) indents`.
  indents : Array[Int32]
  /// `Array(Delimiter) delimiters`.
  delimiters : Array[Int32]
  mut inside_f_string : Bool
}

///|
fn PyScanner::scan(
  self : PyScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  let error_recovery_mode = valid_symbols[PY_STRING_CONTENT] &&
    valid_symbols[PY_INDENT]
  let within_brackets = valid_symbols[PY_CLOSE_BRACE] ||
    valid_symbols[PY_CLOSE_PAREN] ||
    valid_symbols[PY_CLOSE_BRACKET]
  let mut advanced_once = false
  if valid_symbols[PY_ESCAPE_INTERPOLATION] &&
    self.delimiters.length() > 0 &&
    (lexer.lookahead == '{' || lexer.lookahead == '}') &&
    !error_recovery_mode {
    let delimiter = self.delimiters[self.delimiters.length() - 1]
    if py_is_format(delimiter) {
      lexer.mark_end()
      let is_left_brace = lexer.lookahead == '{'
      lexer.advance(false)
      advanced_once = true
      if (lexer.lookahead == '{' && is_left_brace) ||
        (lexer.lookahead == '}' && !is_left_brace) {
        lexer.advance(false)
        lexer.mark_end()
        lexer.result_symbol = PY_ESCAPE_INTERPOLATION
        return true
      }
      return false
    }
  }
  if valid_symbols[PY_STRING_CONTENT] &&
    self.delimiters.length() > 0 &&
    !error_recovery_mode {
    let delimiter = self.delimiters[self.delimiters.length() - 1]
    let end_char = py_end_character(delimiter)
    let mut has_content = advanced_once
    while lexer.lookahead != 0 {
      if (advanced_once || lexer.lookahead == '{' || lexer.lookahead == '}') &&
        py_is_format(delimiter) {
        lexer.mark_end()
        lexer.result_symbol = PY_STRING_CONTENT
        return has_content
      }
      if lexer.lookahead == '\\' {
        if py_is_raw(delimiter) {
          // Step over the backslash.
          lexer.advance(false)
          // Step over any escaped quotes.
          if lexer.lookahead == py_end_character(delimiter) ||
            lexer.lookahead == '\\' {
            lexer.advance(false)
          }
          // Step over newlines
          if lexer.lookahead == '\r' {
            lexer.advance(false)
            if lexer.lookahead == '\n' {
              lexer.advance(false)
            }
          } else if lexer.lookahead == '\n' {
            lexer.advance(false)
          }
          continue
        }
        if py_is_bytes(delimiter) {
          lexer.mark_end()
          lexer.advance(false)
          if lexer.lookahead == 'N' ||
            lexer.lookahead == 'u' ||
            lexer.lookahead == 'U' {
            // In bytes string, \N{...}, \uXXXX and \UXXXXXXXX are
            // not escape sequences
            // https://docs.python.org/3/reference/lexical_analysis.html#string-and-bytes-literals
            lexer.advance(false)
          } else {
            lexer.result_symbol = PY_STRING_CONTENT
            return has_content
          }
        } else {
          lexer.mark_end()
          lexer.result_symbol = PY_STRING_CONTENT
          return has_content
        }
      } else if lexer.lookahead == end_char {
        if py_is_triple(delimiter) {
          lexer.mark_end()
          lexer.advance(false)
          if lexer.lookahead == end_char {
            lexer.advance(false)
            if lexer.lookahead == end_char {
              if has_content {
                lexer.result_symbol = PY_STRING_CONTENT
              } else {
                lexer.advance(false)
                lexer.mark_end()
                ignore(self.delimiters.pop())
                lexer.result_symbol = PY_STRING_END
                self.inside_f_string = false
              }
              return true
            }
            lexer.mark_end()
            lexer.result_symbol = PY_STRING_CONTENT
            return true
          }
          lexer.mark_end()
          lexer.result_symbol = PY_STRING_CONTENT
          return true
        }
        if has_content {
          lexer.result_symbol = PY_STRING_CONTENT
        } else {
          lexer.advance(false)
          ignore(self.delimiters.pop())
          lexer.result_symbol = PY_STRING_END
          self.inside_f_string = false
        }
        lexer.mark_end()
        return true
      } else if lexer.lookahead == '\n' &&
        has_content &&
        !py_is_triple(delimiter) {
        return false
      }
      lexer.advance(false)
      has_content = true
    }
  }
  lexer.mark_end()
  let mut found_end_of_line = false
  // `uint32_t indent_length`.
  let mut indent_length : UInt32 = 0
  let mut first_comment_indent_length = -1
  for ;; {
    if lexer.lookahead == '\n' {
      found_end_of_line = true
      indent_length = 0
      lexer.advance(true)
    } else if lexer.lookahead == ' ' {
      indent_length += 1
      lexer.advance(true)
    } else if lexer.lookahead == '\r' || lexer.lookahead == '\u{c}' {
      indent_length = 0
      lexer.advance(true)
    } else if lexer.lookahead == '\t' {
      indent_length += 8
      lexer.advance(true)
    } else if lexer.lookahead == '#' &&
      (
        valid_symbols[PY_INDENT] ||
        valid_symbols[PY_DEDENT] ||
        valid_symbols[PY_NEWLINE] ||
        valid_symbols[PY_EXCEPT]
      ) {
      // If we haven't found an EOL yet,
      // then this is a comment after an expression:
      //   foo = bar # comment
      // Just return, since we don't want to generate an indent/dedent
      // token.
      if !found_end_of_line {
        return false
      }
      if first_comment_indent_length == -1 {
        first_comment_indent_length = indent_length.reinterpret_as_int()
      }
      while lexer.lookahead != 0 && lexer.lookahead != '\n' {
        lexer.advance(true)
      }
      lexer.advance(true)
      indent_length = 0
    } else if lexer.lookahead == '\\' {
      lexer.advance(true)
      if lexer.lookahead == '\r' {
        lexer.advance(true)
      }
      if lexer.lookahead == '\n' || lexer.eof() {
        lexer.advance(true)
      } else {
        return false
      }
    } else if lexer.eof() {
      indent_length = 0
      found_end_of_line = true
      break
    } else {
      break
    }
  }
  if found_end_of_line {
    if self.indents.length() > 0 {
      // `uint16_t current_indent_length`.
      let current_indent_length = self.indents[self.indents.length() - 1]
      if valid_symbols[PY_INDENT] &&
        indent_length > current_indent_length.reinterpret_as_uint() {
        // `array_push` of a `uint32_t` into an `Array(uint16_t)`.
        self.indents.push(indent_length.reinterpret_as_int() & 0xFFFF)
        lexer.result_symbol = PY_INDENT
        return true
      }
      let next_tok_is_string_start = lexer.lookahead == '"' ||
        lexer.lookahead == '\'' ||
        lexer.lookahead == '`'
      if (
          valid_symbols[PY_DEDENT] ||
          (
            !valid_symbols[PY_NEWLINE] &&
            !(valid_symbols[PY_STRING_START] && next_tok_is_string_start) &&
            !within_brackets
          )
        ) &&
        indent_length < current_indent_length.reinterpret_as_uint() &&
        !self.inside_f_string &&
        // Wait to create a dedent token until we've consumed any
        // comments
        // whose indentation matches the current block.
        first_comment_indent_length < current_indent_length {
        ignore(self.indents.pop())
        lexer.result_symbol = PY_DEDENT
        return true
      }
    }
    if valid_symbols[PY_NEWLINE] && !error_recovery_mode {
      lexer.result_symbol = PY_NEWLINE
      return true
    }
  }
  if first_comment_indent_length == -1 && valid_symbols[PY_STRING_START] {
    let mut delimiter = 0
    let mut has_flags = false
    while lexer.lookahead != 0 {
      if lexer.lookahead == 'f' || lexer.lookahead == 'F' {
        delimiter = delimiter | PY_FORMAT
      } else if lexer.lookahead == 'r' || lexer.lookahead == 'R' {
        delimiter = delimiter | PY_RAW
      } else if lexer.lookahead == 'b' || lexer.lookahead == 'B' {
        delimiter = delimiter | PY_BYTES
      } else if lexer.lookahead != 'u' && lexer.lookahead != 'U' {
        break
      }
      has_flags = true
      lexer.advance(false)
    }
    if lexer.lookahead == '`' {
      delimiter = py_set_end_character(delimiter, '`')
      lexer.advance(false)
      lexer.mark_end()
    } else if lexer.lookahead == '\'' {
      delimiter = py_set_end_character(delimiter, '\'')
      lexer.advance(false)
      lexer.mark_end()
      if lexer.lookahead == '\'' {
        lexer.advance(false)
        if lexer.lookahead == '\'' {
          lexer.advance(false)
          lexer.mark_end()
          delimiter = delimiter | PY_TRIPLE
        }
      }
    } else if lexer.lookahead == '"' {
      delimiter = py_set_end_character(delimiter, '"')
      lexer.advance(false)
      lexer.mark_end()
      if lexer.lookahead == '"' {
        lexer.advance(false)
        if lexer.lookahead == '"' {
          lexer.advance(false)
          lexer.mark_end()
          delimiter = delimiter | PY_TRIPLE
        }
      }
    }
    if py_end_character(delimiter) != 0 {
      self.delimiters.push(delimiter)
      lexer.result_symbol = PY_STRING_START
      self.inside_f_string = py_is_format(delimiter)
      return true
    }
    if has_flags {
      return false
    }
  }
  false
}

///|
fn PyScanner::serialize(self : PyScanner, buffer : FixedArray[Byte]) -> Int32 {
  let mut size = 0
  buffer[size] = if self.inside_f_string { 1 } else { 0 }
  size += 1
  let mut delimiter_count = self.delimiters.length()
  if delimiter_count > 255 {
    delimiter_count = 255
  }
  buffer[size] = delimiter_count.to_byte()
  size += 1
  for i in 0..<delimiter_count {
    buffer[size + i] = self.delimiters[i].to_byte()
  }
  size += delimiter_count
  let mut iter = 1
  while iter < self.indents.length() && size < SERIALIZATION_BUFFER_SIZE {
    buffer[size] = self.indents[iter].to_byte()
    size += 1
    iter += 1
  }
  size
}

///|
fn PyScanner::deserialize(self : PyScanner, buffer : BytesView) -> Unit {
  let length = buffer.length()
  self.delimiters.clear()
  self.indents.clear()
  self.indents.push(0)
  if length > 0 {
    let mut size = 0
    self.inside_f_string = buffer[size] != 0
    size += 1
    let delimiter_count = buffer[size].to_int()
    size += 1
    if delimiter_count > 0 {
      for i in 0..<delimiter_count {
        self.delimiters.push(buffer[size + i].to_int())
      }
      size += delimiter_count
    }
    while size < length {
      self.indents.push(buffer[size].to_int())
      size += 1
    }
  }
}

///|
fn python_scanner() -> @runtime.ExternalScanner {
  let scanner : PyScanner = {
    indents: [],
    delimiters: [],
    inside_f_string: false,
  }
  scanner.deserialize(b""[:])
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => (),
  }
}
