// Ports of the scanner.c files of upstream's test/fixtures/test_grammars
// whose scanners keep state in their payload (tree-sitter 0.28.0, pinned at
// 4a412a01a0147d0f50bf7e749572fa632d1ab203).

// --- external_tokens/scanner.c ---

///|
/// `enum { percent_string, percent_string_start, percent_string_end }`.
priv struct ExternalTokensScanner {
  mut open_delimiter : Int32
  mut close_delimiter : Int32
  /// `uint32_t`.
  mut depth : UInt32
}

///|
/// The state lives only in the payload: `serialize` returns 0.
fn external_tokens_scanner() -> @runtime.ExternalScanner {
  let scanner : ExternalTokensScanner = {
    open_delimiter: 0,
    close_delimiter: 0,
    depth: 0,
  }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: _ => 0,
    deserialize: _ => (),
    destroy: () => (),
  }
}

///|
fn ExternalTokensScanner::scan(
  self : ExternalTokensScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  let percent_string = 0
  let percent_string_start = 1
  let percent_string_end = 2
  if valid_symbols[percent_string] {
    while lexer.lookahead == ' ' ||
          lexer.lookahead == '\t' ||
          lexer.lookahead == '\n' ||
          lexer.lookahead == '\r' {
      lexer.advance(true)
    }
    if lexer.lookahead != '%' {
      return false
    }
    lexer.advance(false)
    match lexer.lookahead {
      '(' => {
        self.open_delimiter = '('
        self.close_delimiter = ')'
        self.depth = 1
      }
      '[' => {
        self.open_delimiter = '['
        self.close_delimiter = ']'
        self.depth = 1
      }
      '{' => {
        self.open_delimiter = '{'
        self.close_delimiter = '}'
        self.depth = 1
      }
      _ => return false
    }
    lexer.advance(false)
    for ;; {
      if self.depth == 0 {
        lexer.log("Found a percent string")
        lexer.result_symbol = percent_string
        return true
      }
      if lexer.lookahead == self.open_delimiter {
        self.depth += 1
      } else if lexer.lookahead == self.close_delimiter {
        self.depth -= 1
      } else if lexer.lookahead == '#' {
        lexer.advance(false)
        if lexer.lookahead == '{' {
          lexer.advance(false)
          lexer.result_symbol = percent_string_start
          return true
        }
      }
      lexer.advance(false)
    }
  } else if valid_symbols[percent_string_end] {
    if lexer.lookahead != '}' {
      return false
    }
    lexer.advance(false)
    for ;; {
      if self.depth == 0 {
        lexer.result_symbol = percent_string_end
        return true
      }
      if lexer.lookahead == self.open_delimiter {
        self.depth += 1
      } else if lexer.lookahead == self.close_delimiter {
        self.depth -= 1
      }
      lexer.advance(false)
    }
  }
  false
}

// --- external_unicode_column_alignment/scanner.c ---

///|
/// `enum { LIST_START, LIST_ITEM, LIST_END }`.
priv struct ExternalUnicodeColumnAlignmentScanner {
  /// `int32_t`.
  mut column : Int32
}

///|
fn external_unicode_column_alignment_scanner() -> @runtime.ExternalScanner {
  let scanner : ExternalUnicodeColumnAlignmentScanner = { column: -1, }
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => {
      // memcpy(buffer, &scanner->column, sizeof(int32_t))
      let column = scanner.column
      buffer[0] = column.to_byte()
      buffer[1] = (column >> 8).to_byte()
      buffer[2] = (column >> 16).to_byte()
      buffer[3] = (column >> 24).to_byte()
      4
    },
    deserialize: buffer => {
      scanner.column = -1
      if buffer.length() > 0 {
        scanner.column = buffer[0].to_int() |
          (buffer[1].to_int() << 8) |
          (buffer[2].to_int() << 16) |
          (buffer[3].to_int() << 24)
      }
    },
    destroy: () => (),
  }
}

///|
fn ExternalUnicodeColumnAlignmentScanner::scan(
  self : ExternalUnicodeColumnAlignmentScanner,
  lexer : @runtime.Lexer,
  _valid_symbols : ArrayView[Bool],
) -> Bool {
  let list_start = 0
  let list_item = 1
  let list_end = 2
  // U+25A1 is unicode codepoint □
  while iswspace(lexer.lookahead) || 0x25A1 == lexer.lookahead {
    lexer.advance(true)
  }
  if ('-' : Int32) == lexer.lookahead {
    let column = lexer.get_column().reinterpret_as_int()
    if -1 == self.column {
      lexer.result_symbol = list_start
      self.column = column
      return true
    } else if column == self.column {
      lexer.result_symbol = list_item
      lexer.advance(false)
      return true
    } else {
      lexer.result_symbol = list_end
      self.column = -1
      return true
    }
  }
  if lexer.eof() && -1 != self.column {
    lexer.result_symbol = list_end
    self.column = -1
    return true
  }
  false
}

// --- uses_current_column/scanner.c ---

///|
/// The C payload is
///
/// ```c
/// typedef struct {
///   uint8_t queued_dedent_count;
///   uint8_t indent_count;
///   int8_t indents[32];
/// } Scanner;
/// ```
///
/// and the scanner indexes `indents` without bounds checks: with
/// `indent_count == 0`, `indents[indent_count - 1]` reads `indent_count`
/// itself, and in error recovery (every token valid) each scan pushes another
/// indent, so `indent_count` (a `uint8_t`) runs past 32 and the C scanner
/// writes into the heap beyond its 34-byte allocation. To reproduce this, the
/// payload is kept as raw bytes (`indents[i]` at offset `2 + i`) extended to
/// the whole range a `uint8_t` index can reach (offsets 1..257). This matches
/// C as long as nothing else in the C process touches the overrun bytes; on
/// the mutated inputs tested both runtimes then behave identically (including
/// hanging in the dedent loop).
priv struct UsesCurrentColumnScanner {
  mem : FixedArray[Byte]
}

///|
fn UsesCurrentColumnScanner::queued_dedent_count(
  self : UsesCurrentColumnScanner,
) -> Int32 {
  self.mem[0].to_int()
}

///|
fn UsesCurrentColumnScanner::set_queued_dedent_count(
  self : UsesCurrentColumnScanner,
  value : Int32,
) -> Unit {
  self.mem[0] = value.to_byte()
}

///|
fn UsesCurrentColumnScanner::indent_count(
  self : UsesCurrentColumnScanner,
) -> Int32 {
  self.mem[1].to_int()
}

///|
fn UsesCurrentColumnScanner::set_indent_count(
  self : UsesCurrentColumnScanner,
  value : Int32,
) -> Unit {
  self.mem[1] = value.to_byte()
}

///|
/// `self->indents[i]`, an `int8_t`.
fn UsesCurrentColumnScanner::indent(
  self : UsesCurrentColumnScanner,
  i : Int32,
) -> Int32 {
  let offset = 2 + i
  if offset < 0 || offset >= self.mem.length() {
    abort("uses_current_column: indents[\{i}] is outside the allocation")
  }
  let value = self.mem[offset].to_int()
  if value >= 128 {
    value - 256
  } else {
    value
  }
}

///|
fn UsesCurrentColumnScanner::set_indent(
  self : UsesCurrentColumnScanner,
  i : Int32,
  value : Int32,
) -> Unit {
  let offset = 2 + i
  if offset < 0 || offset >= self.mem.length() {
    abort("uses_current_column: indents[\{i}] is outside the allocation")
  }
  self.mem[offset] = value.to_byte()
}

///|
fn uses_current_column_scanner() -> @runtime.ExternalScanner {
  let scanner : UsesCurrentColumnScanner = { mem: FixedArray::make(258, 0), }
  scanner.set_queued_dedent_count(0)
  scanner.set_indent_count(1)
  scanner.set_indent(0, 0)
  {
    scan: (lexer, valid_symbols) => scanner.scan(lexer, valid_symbols),
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => (),
  }
}

///|
fn UsesCurrentColumnScanner::serialize(
  self : UsesCurrentColumnScanner,
  buffer : FixedArray[Byte],
) -> Int32 {
  buffer[0] = self.queued_dedent_count().to_byte()
  for i in 0..<self.indent_count() {
    buffer[i + 1] = self.indent(i).to_byte()
  }
  self.indent_count() + 1
}

///|
fn UsesCurrentColumnScanner::deserialize(
  self : UsesCurrentColumnScanner,
  buffer : BytesView,
) -> Unit {
  if buffer.length() > 0 {
    self.set_queued_dedent_count(buffer[0].to_int())
    self.set_indent_count(buffer.length() - 1)
    for i in 0..<self.indent_count() {
      self.set_indent(i, buffer[i + 1].to_int())
    }
  } else {
    self.set_queued_dedent_count(0)
    self.set_indent_count(1)
    self.set_indent(0, 0)
  }
}

///|
fn UsesCurrentColumnScanner::scan(
  self : UsesCurrentColumnScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  let indent = 0
  let dedent = 1
  let newline = 2
  lexer.mark_end()

  // If dedents were found in a previous run, and are valid now,
  // then return a dedent.
  if self.queued_dedent_count() > 0 && valid_symbols[dedent] {
    lexer.result_symbol = dedent
    self.set_queued_dedent_count(self.queued_dedent_count() - 1)
    return true
  }

  // If an indent is valid, then add an entry to the indent stack
  // for the current column, and return an indent.
  if valid_symbols[indent] {
    while iswspace(lexer.lookahead) {
      lexer.advance(false)
    }
    let column = lexer.get_column()
    // `column > self->indents[...]` converts the `int8_t` to `uint32_t`.
    if column > self.indent(self.indent_count() - 1).reinterpret_as_uint() {
      let i = self.indent_count()
      self.set_indent_count(i + 1)
      self.set_indent(i, column.reinterpret_as_int() - 2)
      lexer.result_symbol = indent
      return true
    } else {
      return false
    }
  }

  // If at the end of a statement, then get the current indent
  // level and pop some number of entries off of the indent stack.
  if valid_symbols[newline] || valid_symbols[dedent] {
    while iswspace(lexer.lookahead) && lexer.lookahead != '\n' {
      lexer.advance(false)
    }
    if lexer.lookahead == '\n' {
      lexer.advance(false)
      let mut next_column : UInt32 = 0
      for ;; {
        if lexer.lookahead == ' ' {
          next_column += 1
          lexer.advance(false)
        } else if lexer.lookahead == '\n' {
          next_column = 0
          lexer.advance(false)
        } else {
          break
        }
      }
      let mut dedent_count : UInt32 = 0
      while next_column <
            self.indent(self.indent_count() - 1).reinterpret_as_uint() {
        dedent_count += 1
        self.set_indent_count(self.indent_count() - 1)
      }
      if dedent_count > 0 && valid_symbols[dedent] {
        lexer.result_symbol = dedent
        return true
      } else if valid_symbols[newline] {
        self.set_queued_dedent_count(
          self.queued_dedent_count() + dedent_count.reinterpret_as_int(),
        )
        lexer.result_symbol = newline
        return true
      }
    }
  }
  false
}
