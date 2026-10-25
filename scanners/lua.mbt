// Port of tree-sitter-lua src/scanner.c (v0.5.0)
// tree-sitter-lua is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`.
const LUA_BLOCK_COMMENT_START : Int32 = 0

///|
const LUA_BLOCK_COMMENT_CONTENT : Int32 = 1

///|
const LUA_BLOCK_COMMENT_END : Int32 = 2

///|
const LUA_BLOCK_STRING_START : Int32 = 3

///|
const LUA_BLOCK_STRING_CONTENT : Int32 = 4

///|
const LUA_BLOCK_STRING_END : Int32 = 5

///|
fn lua_consume_char(c : Int32, lexer : @runtime.Lexer) -> Bool {
  if lexer.lookahead != c {
    return false
  }
  lexer.advance(false)
  true
}

///|
/// Returns a `uint8_t` count (wraps at 256).
fn lua_consume_and_count_char(c : Int32, lexer : @runtime.Lexer) -> Int32 {
  let mut count = 0
  while lexer.lookahead == c {
    count = (count + 1) & 0xFF
    lexer.advance(false)
  }
  count
}

///|
fn lua_skip_whitespaces(lexer : @runtime.Lexer) -> Unit {
  while iswspace(lexer.lookahead) {
    lexer.advance(true)
  }
}

///|
priv struct LuaScanner {
  /// `char ending_char` (signed, -128..=127).
  mut ending_char : Int32
  /// `uint8_t level_count`.
  mut level_count : Int32
}

///|
fn LuaScanner::reset_state(self : LuaScanner) -> Unit {
  self.ending_char = 0
  self.level_count = 0
}

///|
fn LuaScanner::serialize(self : LuaScanner, buffer : FixedArray[Byte]) -> Int32 {
  buffer[0] = self.ending_char.to_byte()
  buffer[1] = self.level_count.to_byte()
  2
}

///|
fn LuaScanner::deserialize(self : LuaScanner, buffer : BytesView) -> Unit {
  let length = buffer.length()
  if length == 0 {
    return
  }
  self.ending_char = to_c_char(buffer[0].to_int())
  if length == 1 {
    return
  }
  self.level_count = buffer[1].to_int()
}

///|
fn LuaScanner::scan_block_start(
  self : LuaScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  if lua_consume_char('[', lexer) {
    let level = lua_consume_and_count_char('=', lexer)
    if lua_consume_char('[', lexer) {
      self.level_count = level
      return true
    }
  }
  false
}

///|
fn LuaScanner::scan_block_end(
  self : LuaScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  if lua_consume_char(']', lexer) {
    let level = lua_consume_and_count_char('=', lexer)
    if self.level_count == level && lua_consume_char(']', lexer) {
      return true
    }
  }
  false
}

///|
fn LuaScanner::scan_block_content(
  self : LuaScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  while lexer.lookahead != 0 {
    if lexer.lookahead == ']' {
      lexer.mark_end()
      if self.scan_block_end(lexer) {
        return true
      }
    } else {
      lexer.advance(false)
    }
  }
  false
}

///|
fn LuaScanner::scan_comment_start(
  self : LuaScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  if lua_consume_char('-', lexer) && lua_consume_char('-', lexer) {
    lexer.mark_end()
    if self.scan_block_start(lexer) {
      lexer.mark_end()
      lexer.result_symbol = LUA_BLOCK_COMMENT_START
      return true
    }
  }
  false
}

///|
fn LuaScanner::scan_comment_content(
  self : LuaScanner,
  lexer : @runtime.Lexer,
) -> Bool {
  if self.ending_char == 0 {
    // block comment
    if self.scan_block_content(lexer) {
      lexer.result_symbol = LUA_BLOCK_COMMENT_CONTENT
      return true
    }
    return false
  }
  while lexer.lookahead != 0 {
    if lexer.lookahead == self.ending_char {
      self.reset_state()
      lexer.result_symbol = LUA_BLOCK_COMMENT_CONTENT
      return true
    }
    lexer.advance(false)
  }
  false
}

///|
fn LuaScanner::scan(
  self : LuaScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[LUA_BLOCK_STRING_END] && self.scan_block_end(lexer) {
    self.reset_state()
    lexer.result_symbol = LUA_BLOCK_STRING_END
    return true
  }
  if valid_symbols[LUA_BLOCK_STRING_CONTENT] && self.scan_block_content(lexer) {
    lexer.result_symbol = LUA_BLOCK_STRING_CONTENT
    return true
  }
  if valid_symbols[LUA_BLOCK_COMMENT_END] &&
    self.ending_char == 0 &&
    self.scan_block_end(lexer) {
    self.reset_state()
    lexer.result_symbol = LUA_BLOCK_COMMENT_END
    return true
  }
  if valid_symbols[LUA_BLOCK_COMMENT_CONTENT] &&
    self.scan_comment_content(lexer) {
    return true
  }
  lua_skip_whitespaces(lexer)
  if valid_symbols[LUA_BLOCK_STRING_START] && self.scan_block_start(lexer) {
    lexer.result_symbol = LUA_BLOCK_STRING_START
    return true
  }
  if valid_symbols[LUA_BLOCK_COMMENT_START] {
    if self.scan_comment_start(lexer) {
      return true
    }
  }
  false
}

///|
fn lua_scanner() -> @runtime.ExternalScanner {
  // `ts_calloc(1, sizeof(Scanner))`.
  let scanner : LuaScanner = { ending_char: 0, level_count: 0, }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => (),
  }
}
