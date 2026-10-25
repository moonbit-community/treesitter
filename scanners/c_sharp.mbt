// Port of tree-sitter-c-sharp src/scanner.c (v0.23.5)
// tree-sitter-c-sharp is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`.
const CS_OPT_SEMI : Int32 = 0

///|
const CS_INTERPOLATION_REGULAR_START : Int32 = 1

///|
const CS_INTERPOLATION_VERBATIM_START : Int32 = 2

///|
const CS_INTERPOLATION_RAW_START : Int32 = 3

///|
const CS_INTERPOLATION_START_QUOTE : Int32 = 4

///|
const CS_INTERPOLATION_END_QUOTE : Int32 = 5

///|
const CS_INTERPOLATION_OPEN_BRACE : Int32 = 6

///|
const CS_INTERPOLATION_CLOSE_BRACE : Int32 = 7

///|
const CS_INTERPOLATION_STRING_CONTENT : Int32 = 8

///|
const CS_RAW_STRING_START : Int32 = 9

///|
const CS_RAW_STRING_END : Int32 = 10

///|
const CS_RAW_STRING_CONTENT : Int32 = 11

///|
/// `StringType`.
const CS_REGULAR : Int32 = 1

///|
const CS_VERBATIM : Int32 = 2

///|
const CS_RAW : Int32 = 4

///|
/// `Interpolation`. The `uint8_t` counts are kept in 0..=255.
priv struct CsInterpolation {
  dollar_count : Int32
  mut open_brace_count : Int32
  mut quote_count : Int32
  mut string_type : Int32
}

///|
fn CsInterpolation::is_regular(self : CsInterpolation) -> Bool {
  (self.string_type & CS_REGULAR) != 0
}

///|
fn CsInterpolation::is_verbatim(self : CsInterpolation) -> Bool {
  (self.string_type & CS_VERBATIM) != 0
}

///|
fn CsInterpolation::is_raw(self : CsInterpolation) -> Bool {
  (self.string_type & CS_RAW) != 0
}

///|
priv struct CsScanner {
  /// `uint8_t quote_count`.
  mut quote_count : Int32
  interpolation_stack : Array[CsInterpolation]
}

///|
/// `uint8_t` increment.
fn cs_inc(x : Int32) -> Int32 {
  (x + 1) & 0xFF
}

///|
fn CsScanner::serialize(self : CsScanner, buffer : FixedArray[Byte]) -> Int32 {
  if self.interpolation_stack.length() * 4 + 2 > SERIALIZATION_BUFFER_SIZE {
    return 0
  }
  let mut size = 0
  buffer[size] = self.quote_count.to_byte()
  size += 1
  buffer[size] = self.interpolation_stack.length().to_byte()
  size += 1
  for interpolation in self.interpolation_stack {
    buffer[size] = interpolation.dollar_count.to_byte()
    size += 1
    buffer[size] = interpolation.open_brace_count.to_byte()
    size += 1
    buffer[size] = interpolation.quote_count.to_byte()
    size += 1
    buffer[size] = interpolation.string_type.to_byte()
    size += 1
  }
  size
}

///|
fn CsScanner::deserialize(self : CsScanner, buffer : BytesView) -> Unit {
  let length = buffer.length()
  self.quote_count = 0
  self.interpolation_stack.clear()
  let mut size = 0
  if length > 0 {
    self.quote_count = buffer[size].to_int()
    size += 1
    let stack_size = buffer[size].to_int()
    size += 1
    for _ in 0..<stack_size {
      let interpolation : CsInterpolation = {
        dollar_count: buffer[size].to_int(),
        open_brace_count: buffer[size + 1].to_int(),
        quote_count: buffer[size + 2].to_int(),
        string_type: buffer[size + 3].to_int(),
      }
      size += 4
      self.interpolation_stack.push(interpolation)
    }
  }
  guard size == length else { abort("assert(size == length)") }
}

///|
fn CsScanner::scan(
  self : CsScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  // `uint8_t brace_advanced`, `uint8_t quote_count`.
  let mut brace_advanced = 0
  let mut quote_count = 0
  let mut did_advance = false

  // error recovery, gives better trees this way
  if valid_symbols[CS_OPT_SEMI] && valid_symbols[CS_INTERPOLATION_REGULAR_START] {
    return false
  }
  if valid_symbols[CS_OPT_SEMI] {
    lexer.result_symbol = CS_OPT_SEMI
    if lexer.lookahead == ';' {
      lexer.advance(false)
    }
    return true
  }
  if valid_symbols[CS_RAW_STRING_START] {
    while iswspace(lexer.lookahead) {
      lexer.advance(true)
    }
    if lexer.lookahead == '"' {
      while lexer.lookahead == '"' {
        lexer.advance(false)
        quote_count = cs_inc(quote_count)
      }
      if quote_count >= 3 {
        lexer.result_symbol = CS_RAW_STRING_START
        self.quote_count = quote_count
        return true
      }
    }
  }
  if valid_symbols[CS_RAW_STRING_END] && lexer.lookahead == '"' {
    while lexer.lookahead == '"' {
      lexer.advance(false)
      quote_count = cs_inc(quote_count)
    }
    if quote_count == self.quote_count {
      lexer.result_symbol = CS_RAW_STRING_END
      self.quote_count = 0
      return true
    }
    did_advance = quote_count > 0
  }
  if valid_symbols[CS_RAW_STRING_CONTENT] {
    while lexer.lookahead != 0 {
      if lexer.lookahead == '"' {
        lexer.mark_end()
        quote_count = 0
        while lexer.lookahead == '"' {
          lexer.advance(false)
          quote_count = cs_inc(quote_count)
        }
        if quote_count == self.quote_count {
          lexer.result_symbol = CS_RAW_STRING_CONTENT
          return true
        }
      }
      lexer.advance(false)
      did_advance = true
    }
    lexer.mark_end()
    lexer.result_symbol = CS_RAW_STRING_CONTENT
    return true
  }
  if valid_symbols[CS_INTERPOLATION_REGULAR_START] ||
    valid_symbols[CS_INTERPOLATION_VERBATIM_START] ||
    valid_symbols[CS_INTERPOLATION_RAW_START] {
    while iswspace(lexer.lookahead) {
      lexer.advance(true)
    }
    // `uint8_t dollar_advanced`.
    let mut dollar_advanced = 0
    let mut is_verbatim = false
    if lexer.lookahead == '@' {
      is_verbatim = true
      lexer.advance(false)
    }
    while lexer.lookahead == '$' && quote_count == 0 {
      lexer.advance(false)
      dollar_advanced = cs_inc(dollar_advanced)
    }
    if dollar_advanced > 0 && (lexer.lookahead == '"' || lexer.lookahead == '@') {
      lexer.result_symbol = CS_INTERPOLATION_REGULAR_START
      let interpolation : CsInterpolation = {
        dollar_count: dollar_advanced,
        open_brace_count: 0,
        quote_count: 0,
        string_type: 0,
      }
      if is_verbatim || lexer.lookahead == '@' {
        if lexer.lookahead == '@' {
          lexer.advance(false)
          is_verbatim = true
        }
        lexer.result_symbol = CS_INTERPOLATION_VERBATIM_START
        interpolation.string_type = CS_VERBATIM
      }
      lexer.mark_end()
      lexer.advance(false)
      if lexer.lookahead == '"' && !is_verbatim {
        lexer.advance(false)
        if lexer.lookahead == '"' {
          lexer.result_symbol = CS_INTERPOLATION_RAW_START
          interpolation.string_type = interpolation.string_type | CS_RAW
          self.interpolation_stack.push(interpolation)
        }
        // If we find 1 or 3 quotes, we push an interpolation.
        // If there's only two quotes, that's just an empty string
      } else {
        interpolation.string_type = interpolation.string_type | CS_REGULAR
        self.interpolation_stack.push(interpolation)
      }
      return true
    }
  }
  if valid_symbols[CS_INTERPOLATION_START_QUOTE] &&
    self.interpolation_stack.length() > 0 {
    let current_interpolation = self.interpolation_stack[self.interpolation_stack.length() -
      1]
    if current_interpolation.is_verbatim() || current_interpolation.is_regular() {
      if lexer.lookahead == '"' {
        lexer.advance(false)
        current_interpolation.quote_count = cs_inc(
          current_interpolation.quote_count,
        )
      }
    } else {
      while lexer.lookahead == '"' {
        lexer.advance(false)
        current_interpolation.quote_count = cs_inc(
          current_interpolation.quote_count,
        )
      }
    }
    lexer.result_symbol = CS_INTERPOLATION_START_QUOTE
    return current_interpolation.quote_count > 0
  }
  if valid_symbols[CS_INTERPOLATION_END_QUOTE] &&
    self.interpolation_stack.length() > 0 {
    let current_interpolation = self.interpolation_stack[self.interpolation_stack.length() -
      1]
    while lexer.lookahead == '"' {
      lexer.advance(false)
      quote_count = cs_inc(quote_count)
    }
    if quote_count == current_interpolation.quote_count {
      lexer.result_symbol = CS_INTERPOLATION_END_QUOTE
      ignore(self.interpolation_stack.pop())
      return true
    }
    did_advance = quote_count > 0
  }
  if valid_symbols[CS_INTERPOLATION_OPEN_BRACE] &&
    self.interpolation_stack.length() > 0 {
    let current_interpolation = self.interpolation_stack[self.interpolation_stack.length() -
      1]
    while lexer.lookahead == '{' &&
          brace_advanced < current_interpolation.dollar_count {
      lexer.advance(false)
      brace_advanced = cs_inc(brace_advanced)
    }
    if brace_advanced > 0 &&
      brace_advanced == current_interpolation.dollar_count &&
      (brace_advanced == 0 || lexer.lookahead != '{') {
      current_interpolation.open_brace_count = brace_advanced
      lexer.result_symbol = CS_INTERPOLATION_OPEN_BRACE
      return true
    }
  }
  if valid_symbols[CS_INTERPOLATION_CLOSE_BRACE] &&
    self.interpolation_stack.length() > 0 {
    // A new `uint8_t brace_advanced` shadows the outer one.
    let mut brace_advanced = 0
    let current_interpolation = self.interpolation_stack[self.interpolation_stack.length() -
      1]
    while iswspace(lexer.lookahead) {
      lexer.advance(false)
    }
    while lexer.lookahead == '}' {
      lexer.advance(false)
      brace_advanced = cs_inc(brace_advanced)
      if brace_advanced == current_interpolation.open_brace_count {
        current_interpolation.open_brace_count = 0
        lexer.result_symbol = CS_INTERPOLATION_CLOSE_BRACE
        return true
      }
    }
    return false
  }
  if valid_symbols[CS_INTERPOLATION_STRING_CONTENT] &&
    self.interpolation_stack.length() > 0 {
    lexer.result_symbol = CS_INTERPOLATION_STRING_CONTENT
    let current_interpolation = self.interpolation_stack[self.interpolation_stack.length() -
      1]
    while lexer.lookahead != 0 {
      // top-down approach, first see if it's raw
      if current_interpolation.is_raw() {
        if lexer.lookahead == '"' {
          lexer.mark_end()
          lexer.advance(false)
          if lexer.lookahead == '"' {
            lexer.advance(false)
            // `uint8_t quote_advanced`.
            let mut quote_advanced = 2
            while lexer.lookahead == '"' {
              quote_advanced = cs_inc(quote_advanced)
              lexer.advance(false)
            }
            if quote_advanced == current_interpolation.quote_count {
              return did_advance
            }
          }
        }
        if lexer.lookahead == '{' {
          lexer.mark_end()
          while lexer.lookahead == '{' &&
                brace_advanced < current_interpolation.open_brace_count {
            lexer.advance(false)
            brace_advanced = cs_inc(brace_advanced)
          }
          if brace_advanced == current_interpolation.open_brace_count &&
            (brace_advanced == 0 || lexer.lookahead != '{') {
            return did_advance
          }
        }
      } else if current_interpolation.is_verbatim() {
        // then verbatim, since it could be verbatim + raw, but run the raw branch first
        if lexer.lookahead == '"' {
          lexer.mark_end()
          lexer.advance(false)
          if lexer.lookahead == '"' {
            lexer.advance(false)
            continue
          }
          return did_advance
        }
        if lexer.lookahead == '{' {
          lexer.mark_end()
          while lexer.lookahead == '{' &&
                brace_advanced < current_interpolation.open_brace_count {
            lexer.advance(false)
            brace_advanced = cs_inc(brace_advanced)
          }
          if brace_advanced == current_interpolation.open_brace_count &&
            (brace_advanced == 0 || lexer.lookahead != '{') {
            return did_advance
          }
        }
      } else if current_interpolation.is_regular() {
        // finally regular
        if lexer.lookahead == '\\' ||
          lexer.lookahead == '\n' ||
          lexer.lookahead == '"' {
          lexer.mark_end()
          return did_advance
        }
        if lexer.lookahead == '{' {
          lexer.mark_end()
          while lexer.lookahead == '{' &&
                brace_advanced < current_interpolation.open_brace_count {
            lexer.advance(false)
            brace_advanced = cs_inc(brace_advanced)
          }
          if brace_advanced == current_interpolation.open_brace_count &&
            (brace_advanced == 0 || lexer.lookahead != '{') {
            // if we're in a brace we're not allowed to
            // collect more than the open_brace_count
            return did_advance
          }
        }
      }
      if lexer.lookahead != '{' {
        brace_advanced = 0
      }
      lexer.advance(false)
      did_advance = true
    }
    lexer.mark_end()
    return did_advance
  }
  false
}

///|
fn c_sharp_scanner() -> @runtime.ExternalScanner {
  let scanner : CsScanner = { quote_count: 0, interpolation_stack: [], }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => (),
  }
}
