// Port of tree-sitter-markdown tree-sitter-markdown/src/scanner.c (v0.5.4).
// tree-sitter-markdown is distributed under the MIT license (see NOTICE).

///|
/// `enum TokenType`. For explanation of the tokens see grammar.js
const MD_LINE_ENDING : Int32 = 0

///|
const MD_SOFT_LINE_ENDING : Int32 = 1

///|
const MD_BLOCK_CLOSE : Int32 = 2

///|
const MD_BLOCK_CONTINUATION : Int32 = 3

///|
const MD_BLOCK_QUOTE_START : Int32 = 4

///|
const MD_INDENTED_CHUNK_START : Int32 = 5

///|
const MD_ATX_H1_MARKER : Int32 = 6

///|
#warnings("-unused_value")
const MD_ATX_H2_MARKER : Int32 = 7

///|
#warnings("-unused_value")
const MD_ATX_H3_MARKER : Int32 = 8

///|
#warnings("-unused_value")
const MD_ATX_H4_MARKER : Int32 = 9

///|
#warnings("-unused_value")
const MD_ATX_H5_MARKER : Int32 = 10

///|
const MD_ATX_H6_MARKER : Int32 = 11

///|
const MD_SETEXT_H1_UNDERLINE : Int32 = 12

///|
const MD_SETEXT_H2_UNDERLINE : Int32 = 13

///|
const MD_THEMATIC_BREAK : Int32 = 14

///|
const MD_LIST_MARKER_MINUS : Int32 = 15

///|
const MD_LIST_MARKER_PLUS : Int32 = 16

///|
const MD_LIST_MARKER_STAR : Int32 = 17

///|
const MD_LIST_MARKER_PARENTHESIS : Int32 = 18

///|
const MD_LIST_MARKER_DOT : Int32 = 19

///|
const MD_LIST_MARKER_MINUS_DONT_INTERRUPT : Int32 = 20

///|
const MD_LIST_MARKER_PLUS_DONT_INTERRUPT : Int32 = 21

///|
const MD_LIST_MARKER_STAR_DONT_INTERRUPT : Int32 = 22

///|
const MD_LIST_MARKER_PARENTHESIS_DONT_INTERRUPT : Int32 = 23

///|
const MD_LIST_MARKER_DOT_DONT_INTERRUPT : Int32 = 24

///|
const MD_FENCED_CODE_BLOCK_START_BACKTICK : Int32 = 25

///|
const MD_FENCED_CODE_BLOCK_START_TILDE : Int32 = 26

///|
const MD_BLANK_LINE_START : Int32 = 27

///|
const MD_FENCED_CODE_BLOCK_END_BACKTICK : Int32 = 28

///|
const MD_FENCED_CODE_BLOCK_END_TILDE : Int32 = 29

///|
const MD_HTML_BLOCK_1_START : Int32 = 30

///|
const MD_HTML_BLOCK_1_END : Int32 = 31

///|
const MD_HTML_BLOCK_2_START : Int32 = 32

///|
const MD_HTML_BLOCK_3_START : Int32 = 33

///|
const MD_HTML_BLOCK_4_START : Int32 = 34

///|
const MD_HTML_BLOCK_5_START : Int32 = 35

///|
const MD_HTML_BLOCK_6_START : Int32 = 36

///|
const MD_HTML_BLOCK_7_START : Int32 = 37

///|
const MD_CLOSE_BLOCK : Int32 = 38

///|
const MD_NO_INDENTED_CHUNK : Int32 = 39

///|
const MD_ERROR : Int32 = 40

///|
const MD_TRIGGER_ERROR : Int32 = 41

///|
const MD_TOKEN_EOF : Int32 = 42

///|
const MD_MINUS_METADATA : Int32 = 43

///|
const MD_PLUS_METADATA : Int32 = 44

///|
const MD_PIPE_TABLE_START : Int32 = 45

///|
const MD_PIPE_TABLE_LINE_ENDING : Int32 = 46

///|
const MD_NUM_TOKEN_TYPES : Int32 = 47

///|
/// `enum Block`: description of a block on the block stack.
///
/// LIST_ITEM is a list item with minimal indentation (content begins at indent
/// level 2) while LIST_ITEM_MAX_INDENTATION represents a list item with maximal
/// indentation without being considered a indented code block.
///
/// ANONYMOUS represents any block that whose close is not handled by the
/// external s.
///
/// Blocks are C enum values (`int`); 3..=16 are
/// LIST_ITEM_1_INDENTATION..=LIST_ITEM_14_INDENTATION.
const MD_BLOCK_QUOTE : Int32 = 0

///|
const MD_INDENTED_CODE_BLOCK : Int32 = 1

///|
const MD_LIST_ITEM : Int32 = 2

///|
const MD_LIST_ITEM_MAX_INDENTATION : Int32 = 17

///|
const MD_FENCED_CODE_BLOCK : Int32 = 18

///|
const MD_ANONYMOUS : Int32 = 19

///|
/// `sizeof(Block)`.
const MD_SIZEOF_BLOCK : Int32 = 4

///|
/// Determines if a character is punctuation as defined by the markdown spec.
/// `chr` is a C `char` (signed here, see `to_c_char`).
fn md_is_punctuation(chr : Int32) -> Bool {
  (chr >= '!' && chr <= '/') ||
  (chr >= ':' && chr <= '@') ||
  (chr >= '[' && chr <= '`') ||
  (chr >= '{' && chr <= '~')
}

///|
/// Determines if a character is an ASCII digit.
fn md_is_ascii_digit(chr : Int32) -> Bool {
  chr >= '0' && chr <= '9'
}

///|
/// Returns the indentation level which lines of a list item should have at
/// minimum. Should only be called with blocks for which `is_list_item` returns
/// true.
fn md_list_item_indentation(block : Int32) -> Int32 {
  (block - MD_LIST_ITEM + 2) & 0xFF
}

///|
let md_html_tag_names_rule_1 : FixedArray[String] = ["pre", "script", "style"]

///|
let md_html_tag_names_rule_7 : FixedArray[String] = [
  "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption",
  "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt",
  "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset", "h1",
  "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend",
  "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup",
  "option", "p", "param", "section", "source", "summary", "table", "tbody", "td",
  "tfoot", "th", "thead", "title", "tr", "track", "ul",
]

///|
/// For explanation of the tokens see grammar.js
let md_paragraph_interrupt_symbols : FixedArray[Bool] = [
  false, // LINE_ENDING,
   false, // SOFT_LINE_ENDING,
   false, // BLOCK_CLOSE,
   false, // BLOCK_CONTINUATION,
   true, // BLOCK_QUOTE_START,
   false, // INDENTED_CHUNK_START,
   true, // ATX_H1_MARKER,
   true, // ATX_H2_MARKER,
   true, // ATX_H3_MARKER,
   true, // ATX_H4_MARKER,
   true, // ATX_H5_MARKER,
   true, // ATX_H6_MARKER,
   true, // SETEXT_H1_UNDERLINE,
   true, // SETEXT_H2_UNDERLINE,
   true, // THEMATIC_BREAK,
   true, // LIST_MARKER_MINUS,
   true, // LIST_MARKER_PLUS,
   true, // LIST_MARKER_STAR,
   true, // LIST_MARKER_PARENTHESIS,
   true, // LIST_MARKER_DOT,
   false, // LIST_MARKER_MINUS_DONT_INTERRUPT,
   false, // LIST_MARKER_PLUS_DONT_INTERRUPT,
   false, // LIST_MARKER_STAR_DONT_INTERRUPT,
   false, // LIST_MARKER_PARENTHESIS_DONT_INTERRUPT,
   false, // LIST_MARKER_DOT_DONT_INTERRUPT,
   true, // FENCED_CODE_BLOCK_START_BACKTICK,
   true, // FENCED_CODE_BLOCK_START_TILDE,
   true, // BLANK_LINE_START,
   false, // FENCED_CODE_BLOCK_END_BACKTICK,
   false, // FENCED_CODE_BLOCK_END_TILDE,
   true, // HTML_BLOCK_1_START,
   false, // HTML_BLOCK_1_END,
   true, // HTML_BLOCK_2_START,
   true, // HTML_BLOCK_3_START,
   true, // HTML_BLOCK_4_START,
   true, // HTML_BLOCK_5_START,
   true, // HTML_BLOCK_6_START,
   false, // HTML_BLOCK_7_START,
   false, // CLOSE_BLOCK,
   false, // NO_INDENTED_CHUNK,
   false, // ERROR,
   false, // TRIGGER_ERROR,
   false, // EOF,
   false, // MINUS_METADATA,
   false, // PLUS_METADATA,
   true, // PIPE_TABLE_START,
   false, // PIPE_TABLE_LINE_ENDING,
]

///|
/// Whether the token opens a new block, i.e. pushes onto `open_blocks`.
fn md_opens_block(token : Int32) -> Bool {
  match token {
    MD_BLOCK_QUOTE_START
    | MD_INDENTED_CHUNK_START
    | MD_LIST_MARKER_MINUS
    | MD_LIST_MARKER_PLUS
    | MD_LIST_MARKER_STAR
    | MD_LIST_MARKER_PARENTHESIS
    | MD_LIST_MARKER_DOT
    | MD_LIST_MARKER_MINUS_DONT_INTERRUPT
    | MD_LIST_MARKER_PLUS_DONT_INTERRUPT
    | MD_LIST_MARKER_STAR_DONT_INTERRUPT
    | MD_LIST_MARKER_PARENTHESIS_DONT_INTERRUPT
    | MD_LIST_MARKER_DOT_DONT_INTERRUPT
    | MD_FENCED_CODE_BLOCK_START_BACKTICK
    | MD_FENCED_CODE_BLOCK_START_TILDE
    | MD_HTML_BLOCK_1_START
    | MD_HTML_BLOCK_2_START
    | MD_HTML_BLOCK_3_START
    | MD_HTML_BLOCK_4_START
    | MD_HTML_BLOCK_5_START
    | MD_HTML_BLOCK_6_START
    | MD_HTML_BLOCK_7_START => true
    _ => false
  }
}

///|
/// The serialized state is 5 bytes followed by the open blocks. No new blocks
/// are opened once there are this many.
const MD_MAX_OPEN_BLOCKS : Int32 = (SERIALIZATION_BUFFER_SIZE - 5) /
  MD_SIZEOF_BLOCK

// State bitflags used with `Scanner.state`

///|
/// Currently matching (at the beginning of a line)
const MD_STATE_MATCHING : Int32 = 0x1 << 0

///|
/// Last line break was inside a paragraph
const MD_STATE_WAS_SOFT_LINE_BREAK : Int32 = 0x1 << 1

///|
/// Block should be closed after next line break
const MD_STATE_CLOSE_BLOCK : Int32 = 0x1 << 4

///|
/// C `x &= ~flag` on a `uint8_t`.
fn md_clear(x : Int32, flag : Int32) -> Int32 {
  x & (flag ^ 0xFF)
}

///|
/// The `uint8_t` fields hold values in 0..=255.
priv struct MdScanner {
  /// A stack of open blocks in the current parse state (`Block` values).
  open_blocks : Array[Int32]
  /// Parser state flags
  mut state : Int32
  /// Number of blocks that have been matched so far. Only changes during
  /// matching and is reset after every line ending
  mut matched : Int32
  /// Consumed but "unused" indentation. Sometimes a tab needs to be "split" to
  /// be used in multiple tokens.
  mut indentation : Int32
  /// The current column. Used to decide how many spaces a tab should equal
  mut column : Int32
  /// The delimiter length of the currently open fenced code block
  mut fenced_code_block_delimiter_length : Int32
  mut simulate : Bool
}

///|
fn MdScanner::push_block(self : MdScanner, b : Int32) -> Unit {
  self.open_blocks.push(b)
}

///|
/// C `items[--size]`; on an empty stack C reads out of bounds and wraps
/// `size`, here it aborts.
fn MdScanner::pop_block(self : MdScanner) -> Int32 {
  match self.open_blocks.pop() {
    Some(b) => b
    None => abort("pop_block on an empty block stack")
  }
}

///|
/// Write the whole state of a Scanner to a byte buffer
fn MdScanner::serialize(self : MdScanner, buffer : FixedArray[Byte]) -> Int32 {
  let mut size = 0
  buffer[size] = self.state.to_byte()
  size += 1
  buffer[size] = self.matched.to_byte()
  size += 1
  buffer[size] = self.indentation.to_byte()
  size += 1
  buffer[size] = self.column.to_byte()
  size += 1
  buffer[size] = self.fenced_code_block_delimiter_length.to_byte()
  size += 1
  let mut blocks_count = self.open_blocks.length()
  let max_blocks_count = (SERIALIZATION_BUFFER_SIZE - size) / MD_SIZEOF_BLOCK
  if blocks_count > max_blocks_count {
    blocks_count = max_blocks_count
  }
  if blocks_count > 0 {
    // `memcpy` of the `Block` (little-endian `int`) items.
    for i in 0..<blocks_count {
      let b = self.open_blocks[i]
      buffer[size + i * 4] = b.to_byte()
      buffer[size + i * 4 + 1] = (b >> 8).to_byte()
      buffer[size + i * 4 + 2] = (b >> 16).to_byte()
      buffer[size + i * 4 + 3] = (b >> 24).to_byte()
    }
    size += blocks_count * MD_SIZEOF_BLOCK
  }
  size
}

///|
/// Read the whole state of a Scanner from a byte buffer
/// `serizalize` and `deserialize` should be fully symmetric.
fn MdScanner::deserialize(self : MdScanner, buffer : BytesView) -> Unit {
  let length = buffer.length()
  self.open_blocks.clear()
  self.state = 0
  self.matched = 0
  self.indentation = 0
  self.column = 0
  self.fenced_code_block_delimiter_length = 0
  if length > 0 {
    let mut size = 0
    self.state = buffer[size].to_int()
    size += 1
    self.matched = buffer[size].to_int()
    size += 1
    self.indentation = buffer[size].to_int()
    size += 1
    self.column = buffer[size].to_int()
    size += 1
    self.fenced_code_block_delimiter_length = buffer[size].to_int()
    size += 1
    let blocks_size = length - size
    if blocks_size > 0 {
      let blocks_count = blocks_size / MD_SIZEOF_BLOCK
      for i in 0..<blocks_count {
        let at = size + i * 4
        self.open_blocks.push(
          buffer[at].to_int() |
          (buffer[at + 1].to_int() << 8) |
          (buffer[at + 2].to_int() << 16) |
          (buffer[at + 3].to_int() << 24),
        )
      }
    }
  }
}

///|
fn MdScanner::mark_end(self : MdScanner, lexer : @runtime.Lexer) -> Unit {
  if !self.simulate {
    lexer.mark_end()
  }
}

///|
/// Convenience function to emit the error token. This is done to stop invalid
/// parse branches. Specifically:
/// 1. When encountering a newline after a line break that ended a paragraph,
///    and no new block has been opened.
/// 2. When encountering a new block after a soft line break.
/// 3. When a `$._trigger_error` token is valid, which is used to stop parse
///    branches through normal tree-sitter grammar rules.
///
/// See also the `$._soft_line_break` and `$._paragraph_end_newline` tokens in
/// grammar.js
fn md_error(lexer : @runtime.Lexer) -> Bool {
  lexer.result_symbol = MD_ERROR
  true
}

///|
/// Advance the lexer one character
/// Also keeps track of the current column, counting tabs as spaces with tab
/// stop 4 See https://github.github.com/gfm/#tabs
///
/// Returns the C `size_t`; callers only add it to `uint8_t`s.
fn MdScanner::advance(self : MdScanner, lexer : @runtime.Lexer) -> Int32 {
  let mut size = 1
  if lexer.lookahead == '\t' {
    size = 4 - self.column
    self.column = 0
  } else {
    self.column = (self.column + 1) % 4
  }
  lexer.advance(false)
  size
}

///|
/// `s->indentation += advance(s, lexer)`.
fn MdScanner::advance_indentation(
  self : MdScanner,
  lexer : @runtime.Lexer,
) -> Unit {
  let size = self.advance(lexer)
  self.indentation = (self.indentation + size) & 0xFF
}

///|
/// Try to match the given block, i.e. consume all tokens that belong to the
/// block. These are
/// 1. indentation for list items and indented code blocks
/// 2. '>' for block quotes
/// Returns true if the block is matched and false otherwise
fn MdScanner::match_(
  self : MdScanner,
  lexer : @runtime.Lexer,
  block : Int32,
) -> Bool {
  match block {
    MD_INDENTED_CODE_BLOCK => {
      while self.indentation < 4 {
        if lexer.lookahead == ' ' || lexer.lookahead == '\t' {
          self.advance_indentation(lexer)
        } else {
          break
        }
      }
      if self.indentation >= 4 &&
        lexer.lookahead != '\n' &&
        lexer.lookahead != '\r' {
        self.indentation -= 4
        return true
      }
    }
    MD_LIST_ITEM..<=MD_LIST_ITEM_MAX_INDENTATION => {
      while self.indentation < md_list_item_indentation(block) {
        if lexer.lookahead == ' ' || lexer.lookahead == '\t' {
          self.advance_indentation(lexer)
        } else {
          break
        }
      }
      if self.indentation >= md_list_item_indentation(block) {
        self.indentation -= md_list_item_indentation(block)
        return true
      }
      if lexer.lookahead == '\n' || lexer.lookahead == '\r' {
        self.indentation = 0
        return true
      }
    }
    MD_BLOCK_QUOTE => {
      while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
        self.advance_indentation(lexer)
      }
      if lexer.lookahead == '>' {
        ignore(self.advance(lexer))
        self.indentation = 0
        if lexer.lookahead == ' ' || lexer.lookahead == '\t' {
          let size = self.advance(lexer)
          self.indentation = (self.indentation + size - 1) & 0xFF
        }
        return true
      }
    }
    MD_FENCED_CODE_BLOCK | MD_ANONYMOUS => return true
    _ => ()
  }
  false
}

///|
fn MdScanner::parse_fenced_code_block(
  self : MdScanner,
  delimiter : Int32,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  // Nothing to emit for this delimiter here; bail before counting the
  // (possibly long) run, which would otherwise be O(n^2) across a paragraph.
  if (if delimiter == '`' {
      !valid_symbols[MD_FENCED_CODE_BLOCK_START_BACKTICK] &&
      !valid_symbols[MD_FENCED_CODE_BLOCK_END_BACKTICK]
    } else {
      !valid_symbols[MD_FENCED_CODE_BLOCK_START_TILDE] &&
      !valid_symbols[MD_FENCED_CODE_BLOCK_END_TILDE]
    }) {
    return false
  }
  // count the number of backticks
  // `uint8_t level`.
  let mut level = 0
  while lexer.lookahead == delimiter {
    ignore(self.advance(lexer))
    level = (level + 1) & 0xFF
  }
  self.mark_end(lexer)
  // If this is able to close a fenced code block then that is the only valid
  // interpretation. It can only close a fenced code block if the number of
  // backticks is at least the number of backticks of the opening delimiter.
  // Also it cannot be indented more than 3 spaces.
  if (if delimiter == '`' {
      valid_symbols[MD_FENCED_CODE_BLOCK_END_BACKTICK]
    } else {
      valid_symbols[MD_FENCED_CODE_BLOCK_END_TILDE]
    }) &&
    self.indentation < 4 &&
    level >= self.fenced_code_block_delimiter_length {
    while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      ignore(self.advance(lexer))
    }
    let is_eof = lexer.eof()
    if is_eof {
      // A closing fence may end the input without a line ending. Nothing
      // follows to consume the trailing whitespace, so it joins the token.
      self.mark_end(lexer)
    }
    if lexer.lookahead == '\n' || lexer.lookahead == '\r' || is_eof {
      self.fenced_code_block_delimiter_length = 0
      lexer.result_symbol = if delimiter == '`' {
        MD_FENCED_CODE_BLOCK_END_BACKTICK
      } else {
        MD_FENCED_CODE_BLOCK_END_TILDE
      }
      return true
    }
  }
  // If this could be the start of a fenced code block, check if the info
  // string contains any backticks.
  if (if delimiter == '`' {
      valid_symbols[MD_FENCED_CODE_BLOCK_START_BACKTICK]
    } else {
      valid_symbols[MD_FENCED_CODE_BLOCK_START_TILDE]
    }) &&
    level >= 3 {
    let mut info_string_has_backtick = false
    if delimiter == '`' {
      while lexer.lookahead != '\n' && lexer.lookahead != '\r' && !lexer.eof() {
        if lexer.lookahead == '`' {
          info_string_has_backtick = true
          break
        }
        ignore(self.advance(lexer))
      }
    }
    // If it does not then choose to interpret this as the start of a fenced
    // code block.
    if !info_string_has_backtick {
      lexer.result_symbol = if delimiter == '`' {
        MD_FENCED_CODE_BLOCK_START_BACKTICK
      } else {
        MD_FENCED_CODE_BLOCK_START_TILDE
      }
      if !self.simulate {
        self.push_block(MD_FENCED_CODE_BLOCK)
      }
      // Remember the length of the delimiter for later, since we need it
      // to decide whether a sequence of backticks can close the block.
      self.fenced_code_block_delimiter_length = level
      self.indentation = 0
      return true
    }
  }
  false
}

///|
fn MdScanner::parse_star(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  // Nothing to emit here; bail before scanning the (possibly long) run of
  // `*`, which would otherwise be O(n^2) across a paragraph.
  if !valid_symbols[MD_THEMATIC_BREAK] &&
    !valid_symbols[MD_LIST_MARKER_STAR] &&
    !valid_symbols[MD_LIST_MARKER_STAR_DONT_INTERRUPT] {
    return false
  }
  ignore(self.advance(lexer))
  self.mark_end(lexer)
  // Otherwise count the number of stars permitting whitespaces between them.
  let mut star_count = 1
  // Also remember how many stars there are before the first whitespace...
  // ...and how many spaces follow the first star.
  // `uint8_t extra_indentation`.
  let mut extra_indentation = 0
  for ;; {
    if lexer.lookahead == '*' {
      if star_count == 1 &&
        extra_indentation >= 1 &&
        valid_symbols[MD_LIST_MARKER_STAR] {
        // If we get to this point then the token has to be at least
        // this long. We need to call `mark_end` here in case we decide
        // later that this is a list item.
        self.mark_end(lexer)
      }
      star_count += 1
      ignore(self.advance(lexer))
    } else if lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      if star_count == 1 {
        extra_indentation = (extra_indentation + self.advance(lexer)) & 0xFF
      } else {
        ignore(self.advance(lexer))
      }
    } else {
      break
    }
  }
  let line_end = lexer.lookahead == '\n' || lexer.lookahead == '\r'
  let mut dont_interrupt = false
  if star_count == 1 && line_end {
    extra_indentation = 1
    // line is empty so don't interrupt paragraphs if this is a list marker
    dont_interrupt = self.matched == self.open_blocks.length()
  }
  // If there were at least 3 stars then this could be a thematic break
  let thematic_break = star_count >= 3 && line_end
  // If there was a star and at least one space after that star then this
  // could be a list marker.
  let list_marker_star = star_count >= 1 && extra_indentation >= 1
  if valid_symbols[MD_THEMATIC_BREAK] && thematic_break && self.indentation < 4 {
    // If a thematic break is valid then it takes precedence
    lexer.result_symbol = MD_THEMATIC_BREAK
    self.mark_end(lexer)
    self.indentation = 0
    return true
  }
  if (if dont_interrupt {
      valid_symbols[MD_LIST_MARKER_STAR_DONT_INTERRUPT]
    } else {
      valid_symbols[MD_LIST_MARKER_STAR]
    }) &&
    list_marker_star {
    // List markers take precedence over emphasis markers
    // If star_count > 1 then we already called mark_end at the right point.
    // Otherwise the token should go until this point.
    if star_count == 1 {
      self.mark_end(lexer)
    }
    // Not counting one space...
    extra_indentation = (extra_indentation - 1) & 0xFF
    // ... check if the list item begins with an indented code block
    if extra_indentation <= 3 {
      // If not then calculate the indentation level of the list item
      // content as indentation of list marker + indentation after list
      // marker - 1
      extra_indentation = (extra_indentation + self.indentation) & 0xFF
      self.indentation = 0
    } else {
      // Otherwise the indentation level is just the indentation of the
      // list marker. We keep the indentation after the list marker for
      // later blocks.
      let temp = self.indentation
      self.indentation = extra_indentation
      extra_indentation = temp
    }
    if !self.simulate {
      self.push_block(MD_LIST_ITEM + extra_indentation)
    }
    lexer.result_symbol = if dont_interrupt {
      MD_LIST_MARKER_STAR_DONT_INTERRUPT
    } else {
      MD_LIST_MARKER_STAR
    }
    return true
  }
  false
}

///|
fn MdScanner::parse_thematic_break_underscore(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  // Same as above for a run of `_` (only THEMATIC_BREAK is emittable here).
  if !valid_symbols[MD_THEMATIC_BREAK] {
    return false
  }
  ignore(self.advance(lexer))
  self.mark_end(lexer)
  let mut underscore_count = 1
  for ;; {
    if lexer.lookahead == '_' {
      underscore_count += 1
      ignore(self.advance(lexer))
    } else if lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      ignore(self.advance(lexer))
    } else {
      break
    }
  }
  let line_end = lexer.lookahead == '\n' || lexer.lookahead == '\r'
  if underscore_count >= 3 && line_end && valid_symbols[MD_THEMATIC_BREAK] {
    lexer.result_symbol = MD_THEMATIC_BREAK
    self.mark_end(lexer)
    self.indentation = 0
    return true
  }
  false
}

///|
fn MdScanner::parse_block_quote(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[MD_BLOCK_QUOTE_START] {
    ignore(self.advance(lexer))
    self.indentation = 0
    if lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      let size = self.advance(lexer)
      self.indentation = (self.indentation + size - 1) & 0xFF
    }
    lexer.result_symbol = MD_BLOCK_QUOTE_START
    if !self.simulate {
      self.push_block(MD_BLOCK_QUOTE)
    }
    return true
  }
  false
}

///|
fn MdScanner::parse_atx_heading(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[MD_ATX_H1_MARKER] && self.indentation <= 3 {
    self.mark_end(lexer)
    // `uint16_t level`.
    let mut level = 0
    while lexer.lookahead == '#' && level <= 6 {
      ignore(self.advance(lexer))
      level += 1
    }
    if level <= 6 &&
      (
        lexer.lookahead == ' ' ||
        lexer.lookahead == '\t' ||
        lexer.lookahead == '\n' ||
        lexer.lookahead == '\r'
      ) {
      lexer.result_symbol = MD_ATX_H1_MARKER + (level - 1)
      self.indentation = 0
      self.mark_end(lexer)
      return true
    }
  }
  false
}

///|
fn MdScanner::parse_setext_underline(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if valid_symbols[MD_SETEXT_H1_UNDERLINE] &&
    self.matched == self.open_blocks.length() {
    self.mark_end(lexer)
    while lexer.lookahead == '=' {
      ignore(self.advance(lexer))
    }
    while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      ignore(self.advance(lexer))
    }
    if lexer.lookahead == '\n' || lexer.lookahead == '\r' {
      lexer.result_symbol = MD_SETEXT_H1_UNDERLINE
      self.mark_end(lexer)
      return true
    }
  }
  false
}

///|
fn MdScanner::parse_plus(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if self.indentation <= 3 &&
    (
      valid_symbols[MD_LIST_MARKER_PLUS] ||
      valid_symbols[MD_LIST_MARKER_PLUS_DONT_INTERRUPT] ||
      valid_symbols[MD_PLUS_METADATA]
    ) {
    ignore(self.advance(lexer))
    if valid_symbols[MD_PLUS_METADATA] && lexer.lookahead == '+' {
      ignore(self.advance(lexer))
      if lexer.lookahead != '+' {
        return false
      }
      ignore(self.advance(lexer))
      while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
        ignore(self.advance(lexer))
      }
      if lexer.lookahead != '\n' && lexer.lookahead != '\r' {
        return false
      }
      for ;; {
        // advance over newline
        if lexer.lookahead == '\r' {
          ignore(self.advance(lexer))
          if lexer.lookahead == '\n' {
            ignore(self.advance(lexer))
          }
        } else {
          ignore(self.advance(lexer))
        }
        // check for pluses
        let mut plus_count = 0
        while lexer.lookahead == '+' {
          plus_count += 1
          ignore(self.advance(lexer))
        }
        if plus_count == 3 {
          // if exactly 3 check if next symbol (after eventual
          // whitespace) is newline
          while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
            ignore(self.advance(lexer))
          }
          if lexer.lookahead == '\r' || lexer.lookahead == '\n' {
            // if so also consume newline
            if lexer.lookahead == '\r' {
              ignore(self.advance(lexer))
              if lexer.lookahead == '\n' {
                ignore(self.advance(lexer))
              }
            } else {
              ignore(self.advance(lexer))
            }
            self.mark_end(lexer)
            lexer.result_symbol = MD_PLUS_METADATA
            return true
          }
        }
        // otherwise consume rest of line
        while lexer.lookahead != '\n' && lexer.lookahead != '\r' && !lexer.eof() {
          ignore(self.advance(lexer))
        }
        // if end of file is reached, then this is not metadata
        if lexer.eof() {
          break
        }
      }
    } else {
      // `uint8_t extra_indentation`.
      let mut extra_indentation = 0
      while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
        extra_indentation = (extra_indentation + self.advance(lexer)) & 0xFF
      }
      let mut dont_interrupt = false
      if lexer.lookahead == '\r' || lexer.lookahead == '\n' {
        extra_indentation = 1
        dont_interrupt = true
      }
      dont_interrupt = dont_interrupt &&
        self.matched == self.open_blocks.length()
      if extra_indentation >= 1 &&
        (if dont_interrupt {
          valid_symbols[MD_LIST_MARKER_PLUS_DONT_INTERRUPT]
        } else {
          valid_symbols[MD_LIST_MARKER_PLUS]
        }) {
        lexer.result_symbol = if dont_interrupt {
          MD_LIST_MARKER_PLUS_DONT_INTERRUPT
        } else {
          MD_LIST_MARKER_PLUS
        }
        extra_indentation = (extra_indentation - 1) & 0xFF
        if extra_indentation <= 3 {
          extra_indentation = (extra_indentation + self.indentation) & 0xFF
          self.indentation = 0
        } else {
          let temp = self.indentation
          self.indentation = extra_indentation
          extra_indentation = temp
        }
        if !self.simulate {
          self.push_block(MD_LIST_ITEM + extra_indentation)
        }
        return true
      }
    }
  }
  false
}

///|
fn MdScanner::parse_ordered_list_marker(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if self.indentation <= 3 &&
    (
      valid_symbols[MD_LIST_MARKER_PARENTHESIS] ||
      valid_symbols[MD_LIST_MARKER_DOT] ||
      valid_symbols[MD_LIST_MARKER_PARENTHESIS_DONT_INTERRUPT] ||
      valid_symbols[MD_LIST_MARKER_DOT_DONT_INTERRUPT]
    ) {
    let mut digits = 1
    ignore(self.advance(lexer))
    while md_is_ascii_digit(lexer.lookahead) {
      digits += 1
      ignore(self.advance(lexer))
    }
    let mut dont_interrupt = digits > 1
    if digits <= 9 {
      let mut dot = false
      let mut parenthesis = false
      if lexer.lookahead == '.' {
        ignore(self.advance(lexer))
        dot = true
      } else if lexer.lookahead == ')' {
        ignore(self.advance(lexer))
        parenthesis = true
      }
      if dot || parenthesis {
        // `uint8_t extra_indentation`.
        let mut extra_indentation = 0
        while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
          extra_indentation = (extra_indentation + self.advance(lexer)) & 0xFF
        }
        let line_end = lexer.lookahead == '\n' || lexer.lookahead == '\r'
        if line_end {
          extra_indentation = 1
          dont_interrupt = true
        }
        dont_interrupt = dont_interrupt &&
          self.matched == self.open_blocks.length()
        let marker = if dot {
          if dont_interrupt {
            MD_LIST_MARKER_DOT_DONT_INTERRUPT
          } else {
            MD_LIST_MARKER_DOT
          }
        } else if dont_interrupt {
          MD_LIST_MARKER_PARENTHESIS_DONT_INTERRUPT
        } else {
          MD_LIST_MARKER_PARENTHESIS
        }
        if extra_indentation >= 1 && valid_symbols[marker] {
          lexer.result_symbol = marker
          extra_indentation = (extra_indentation - 1) & 0xFF
          if extra_indentation <= 3 {
            extra_indentation = (extra_indentation + self.indentation) & 0xFF
            self.indentation = 0
          } else {
            let temp = self.indentation
            self.indentation = extra_indentation
            extra_indentation = temp
          }
          if !self.simulate {
            self.push_block(MD_LIST_ITEM + extra_indentation + digits)
          }
          return true
        }
      }
    }
  }
  false
}

///|
fn MdScanner::parse_minus(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if self.indentation <= 3 &&
    (
      valid_symbols[MD_LIST_MARKER_MINUS] ||
      valid_symbols[MD_LIST_MARKER_MINUS_DONT_INTERRUPT] ||
      valid_symbols[MD_SETEXT_H2_UNDERLINE] ||
      valid_symbols[MD_THEMATIC_BREAK] ||
      valid_symbols[MD_MINUS_METADATA]
    ) {
    self.mark_end(lexer)
    let mut whitespace_after_minus = false
    let mut minus_after_whitespace = false
    let mut minus_count = 0
    // `uint8_t extra_indentation`.
    let mut extra_indentation = 0
    for ;; {
      if lexer.lookahead == '-' {
        if minus_count == 1 && extra_indentation >= 1 {
          self.mark_end(lexer)
        }
        minus_count += 1
        ignore(self.advance(lexer))
        minus_after_whitespace = whitespace_after_minus
      } else if lexer.lookahead == ' ' || lexer.lookahead == '\t' {
        if minus_count == 1 {
          extra_indentation = (extra_indentation + self.advance(lexer)) & 0xFF
        } else {
          ignore(self.advance(lexer))
        }
        whitespace_after_minus = true
      } else {
        break
      }
    }
    let line_end = lexer.lookahead == '\n' || lexer.lookahead == '\r'
    let mut dont_interrupt = false
    if minus_count == 1 && line_end {
      extra_indentation = 1
      dont_interrupt = true
    }
    dont_interrupt = dont_interrupt && self.matched == self.open_blocks.length()
    let thematic_break = minus_count >= 3 && line_end
    let underline = minus_count >= 1 &&
      !minus_after_whitespace &&
      line_end &&
      self.matched == self.open_blocks.length() // setext heading can not break lazy continuation
    let list_marker_minus = minus_count >= 1 && extra_indentation >= 1
    let mut success = false
    if valid_symbols[MD_SETEXT_H2_UNDERLINE] && underline {
      lexer.result_symbol = MD_SETEXT_H2_UNDERLINE
      self.mark_end(lexer)
      self.indentation = 0
      success = true
    } else if valid_symbols[MD_THEMATIC_BREAK] && thematic_break { // underline is false if list_marker_minus
      // is true
      lexer.result_symbol = MD_THEMATIC_BREAK
      self.mark_end(lexer)
      self.indentation = 0
      success = true
    } else if (if dont_interrupt {
        valid_symbols[MD_LIST_MARKER_MINUS_DONT_INTERRUPT]
      } else {
        valid_symbols[MD_LIST_MARKER_MINUS]
      }) &&
      list_marker_minus {
      if minus_count == 1 {
        self.mark_end(lexer)
      }
      extra_indentation = (extra_indentation - 1) & 0xFF
      if extra_indentation <= 3 {
        extra_indentation = (extra_indentation + self.indentation) & 0xFF
        self.indentation = 0
      } else {
        let temp = self.indentation
        self.indentation = extra_indentation
        extra_indentation = temp
      }
      if !self.simulate {
        self.push_block(MD_LIST_ITEM + extra_indentation)
      }
      lexer.result_symbol = if dont_interrupt {
        MD_LIST_MARKER_MINUS_DONT_INTERRUPT
      } else {
        MD_LIST_MARKER_MINUS
      }
      return true
    }
    if minus_count == 3 &&
      !minus_after_whitespace &&
      line_end &&
      valid_symbols[MD_MINUS_METADATA] {
      for ;; {
        // advance over newline
        if lexer.lookahead == '\r' {
          ignore(self.advance(lexer))
          if lexer.lookahead == '\n' {
            ignore(self.advance(lexer))
          }
        } else {
          ignore(self.advance(lexer))
        }
        // check for minuses
        minus_count = 0
        while lexer.lookahead == '-' {
          minus_count += 1
          ignore(self.advance(lexer))
        }
        if minus_count == 3 {
          // if exactly 3 check if next symbol (after eventual
          // whitespace) is newline
          while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
            ignore(self.advance(lexer))
          }
          if lexer.lookahead == '\r' || lexer.lookahead == '\n' {
            // if so also consume newline
            if lexer.lookahead == '\r' {
              ignore(self.advance(lexer))
              if lexer.lookahead == '\n' {
                ignore(self.advance(lexer))
              }
            } else {
              ignore(self.advance(lexer))
            }
            self.mark_end(lexer)
            lexer.result_symbol = MD_MINUS_METADATA
            return true
          }
        }
        // otherwise consume rest of line
        while lexer.lookahead != '\n' && lexer.lookahead != '\r' && !lexer.eof() {
          ignore(self.advance(lexer))
        }
        // if end of file is reached, then this is not metadata
        if lexer.eof() {
          break
        }
      }
    }
    if success {
      return true
    }
  }
  false
}

///|
fn MdScanner::parse_html_block(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  if !(valid_symbols[MD_HTML_BLOCK_1_START] ||
    valid_symbols[MD_HTML_BLOCK_1_END] ||
    valid_symbols[MD_HTML_BLOCK_2_START] ||
    valid_symbols[MD_HTML_BLOCK_3_START] ||
    valid_symbols[MD_HTML_BLOCK_4_START] ||
    valid_symbols[MD_HTML_BLOCK_5_START] ||
    valid_symbols[MD_HTML_BLOCK_6_START] ||
    valid_symbols[MD_HTML_BLOCK_7_START]) {
    return false
  }
  ignore(self.advance(lexer))
  if lexer.lookahead == '?' && valid_symbols[MD_HTML_BLOCK_3_START] {
    ignore(self.advance(lexer))
    lexer.result_symbol = MD_HTML_BLOCK_3_START
    if !self.simulate {
      self.push_block(MD_ANONYMOUS)
    }
    return true
  }
  if lexer.lookahead == '!' {
    // could be block 2
    ignore(self.advance(lexer))
    if lexer.lookahead == '-' {
      // Block 2 ends at the first `-->`, which may overlap the opening
      // `<!--` as in `<!-->` and `<!--->`. For those, end the token
      // after `<!` so that the closing `-->` is left for the block.
      self.mark_end(lexer)
      let column = self.column
      ignore(self.advance(lexer))
      if lexer.lookahead != '-' || !valid_symbols[MD_HTML_BLOCK_2_START] {
        return false
      }
      ignore(self.advance(lexer))
      if lexer.lookahead == '>' || lexer.lookahead == '-' {
        self.column = column
      } else {
        self.mark_end(lexer)
      }
      lexer.result_symbol = MD_HTML_BLOCK_2_START
      if !self.simulate {
        self.push_block(MD_ANONYMOUS)
      }
      return true
    } else if lexer.lookahead >= 'A' &&
      lexer.lookahead <= 'Z' &&
      valid_symbols[MD_HTML_BLOCK_4_START] {
      ignore(self.advance(lexer))
      lexer.result_symbol = MD_HTML_BLOCK_4_START
      if !self.simulate {
        self.push_block(MD_ANONYMOUS)
      }
      return true
    } else if lexer.lookahead == '[' {
      ignore(self.advance(lexer))
      if lexer.lookahead == 'C' {
        ignore(self.advance(lexer))
        if lexer.lookahead == 'D' {
          ignore(self.advance(lexer))
          if lexer.lookahead == 'A' {
            ignore(self.advance(lexer))
            if lexer.lookahead == 'T' {
              ignore(self.advance(lexer))
              if lexer.lookahead == 'A' {
                ignore(self.advance(lexer))
                if lexer.lookahead == '[' &&
                  valid_symbols[MD_HTML_BLOCK_5_START] {
                  ignore(self.advance(lexer))
                  lexer.result_symbol = MD_HTML_BLOCK_5_START
                  if !self.simulate {
                    self.push_block(MD_ANONYMOUS)
                  }
                  return true
                }
              }
            }
          }
        }
      }
    }
  }
  let starting_slash = lexer.lookahead == '/'
  if starting_slash {
    ignore(self.advance(lexer))
  }
  // `char name[11]`.
  let name = StringBuilder()
  let mut name_length = 0
  while iswalpha(lexer.lookahead) {
    if name_length < 10 {
      // `(char)towlower(...)` of an ASCII letter.
      name.write_char(towlower(lexer.lookahead).unsafe_to_char())
      name_length += 1
    } else {
      name_length = 12
    }
    ignore(self.advance(lexer))
  }
  if name_length == 0 {
    return false
  }
  let mut tag_closed = false
  if name_length < 11 {
    let name = name.to_string()
    let next_symbol_valid = lexer.lookahead == ' ' ||
      lexer.lookahead == '\t' ||
      lexer.lookahead == '\n' ||
      lexer.lookahead == '\r' ||
      lexer.lookahead == '>'
    if next_symbol_valid {
      // try block 1 names
      for i in 0..<md_html_tag_names_rule_1.length() {
        if name == md_html_tag_names_rule_1[i] {
          if starting_slash {
            if valid_symbols[MD_HTML_BLOCK_1_END] {
              lexer.result_symbol = MD_HTML_BLOCK_1_END
              return true
            }
          } else if valid_symbols[MD_HTML_BLOCK_1_START] {
            lexer.result_symbol = MD_HTML_BLOCK_1_START
            if !self.simulate {
              self.push_block(MD_ANONYMOUS)
            }
            return true
          }
        }
      }
    }
    if !next_symbol_valid && lexer.lookahead == '/' {
      ignore(self.advance(lexer))
      if lexer.lookahead == '>' {
        ignore(self.advance(lexer))
        tag_closed = true
      }
    }
    if next_symbol_valid || tag_closed {
      // try block 2 names
      for i in 0..<md_html_tag_names_rule_7.length() {
        if name == md_html_tag_names_rule_7[i] &&
          valid_symbols[MD_HTML_BLOCK_6_START] {
          lexer.result_symbol = MD_HTML_BLOCK_6_START
          if !self.simulate {
            self.push_block(MD_ANONYMOUS)
          }
          return true
        }
      }
    }
  }
  if !valid_symbols[MD_HTML_BLOCK_7_START] {
    return false
  }
  if !tag_closed {
    // tag name (continued)
    while iswalnum(lexer.lookahead) || lexer.lookahead == '-' {
      ignore(self.advance(lexer))
    }
    if !starting_slash {
      // attributes
      let mut had_whitespace = false
      for ;; {
        // whitespace
        while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
          had_whitespace = true
          ignore(self.advance(lexer))
        }
        if lexer.lookahead == '/' {
          ignore(self.advance(lexer))
          break
        }
        if lexer.lookahead == '>' {
          break
        }
        // attribute name
        if !had_whitespace {
          return false
        }
        if !iswalpha(lexer.lookahead) &&
          lexer.lookahead != '_' &&
          lexer.lookahead != ':' {
          return false
        }
        had_whitespace = false
        ignore(self.advance(lexer))
        while iswalnum(lexer.lookahead) ||
              lexer.lookahead == '_' ||
              lexer.lookahead == '.' ||
              lexer.lookahead == ':' ||
              lexer.lookahead == '-' {
          ignore(self.advance(lexer))
        }
        // attribute value specification
        // optional whitespace
        while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
          had_whitespace = true
          ignore(self.advance(lexer))
        }
        // =
        if lexer.lookahead == '=' {
          ignore(self.advance(lexer))
          had_whitespace = false
          // optional whitespace
          while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
            ignore(self.advance(lexer))
          }
          // attribute value
          if lexer.lookahead == '\'' || lexer.lookahead == '"' {
            let delimiter = to_c_char(lexer.lookahead)
            ignore(self.advance(lexer))
            while lexer.lookahead != delimiter &&
                  lexer.lookahead != '\n' &&
                  lexer.lookahead != '\r' &&
                  !lexer.eof() {
              ignore(self.advance(lexer))
            }
            if lexer.lookahead != delimiter {
              return false
            }
            ignore(self.advance(lexer))
          } else {
            // unquoted attribute value
            let mut had_one = false
            while lexer.lookahead != ' ' &&
                  lexer.lookahead != '\t' &&
                  lexer.lookahead != '"' &&
                  lexer.lookahead != '\'' &&
                  lexer.lookahead != '=' &&
                  lexer.lookahead != '<' &&
                  lexer.lookahead != '>' &&
                  lexer.lookahead != '`' &&
                  lexer.lookahead != '\n' &&
                  lexer.lookahead != '\r' &&
                  !lexer.eof() {
              ignore(self.advance(lexer))
              had_one = true
            }
            if !had_one {
              return false
            }
          }
        }
      }
    } else {
      while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
        ignore(self.advance(lexer))
      }
    }
    if lexer.lookahead != '>' {
      return false
    }
    ignore(self.advance(lexer))
  }
  while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
    ignore(self.advance(lexer))
  }
  if lexer.lookahead == '\r' || lexer.lookahead == '\n' {
    lexer.result_symbol = MD_HTML_BLOCK_7_START
    if !self.simulate {
      self.push_block(MD_ANONYMOUS)
    }
    return true
  }
  false
}

///|
fn MdScanner::parse_pipe_table(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  // unused
  ignore(valid_symbols)
  // PIPE_TABLE_START is zero width
  self.mark_end(lexer)
  // count number of cells
  let mut cell_count = 0
  // also remember if we see starting and ending pipes, as empty headers have
  // to have both
  let mut starting_pipe = false
  let mut ending_pipe = false
  let empty = true
  if lexer.lookahead == '|' {
    starting_pipe = true
    ignore(self.advance(lexer))
  }
  while lexer.lookahead != '\r' && lexer.lookahead != '\n' && !lexer.eof() {
    if lexer.lookahead == '|' {
      cell_count += 1
      ending_pipe = true
      ignore(self.advance(lexer))
    } else {
      if lexer.lookahead != ' ' && lexer.lookahead != '\t' {
        ending_pipe = false
      }
      if lexer.lookahead == '\\' {
        ignore(self.advance(lexer))
        if md_is_punctuation(to_c_char(lexer.lookahead)) {
          ignore(self.advance(lexer))
        }
      } else {
        ignore(self.advance(lexer))
      }
    }
  }
  if empty && cell_count == 0 && !(starting_pipe && ending_pipe) {
    return false
  }
  if !ending_pipe {
    cell_count += 1
  }

  // check the following line for a delimiter row
  // parse a newline
  if lexer.lookahead == '\n' {
    ignore(self.advance(lexer))
  } else if lexer.lookahead == '\r' {
    ignore(self.advance(lexer))
    if lexer.lookahead == '\n' {
      ignore(self.advance(lexer))
    }
  } else {
    return false
  }
  self.indentation = 0
  self.column = 0
  for ;; {
    if lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      self.advance_indentation(lexer)
    } else {
      break
    }
  }
  self.simulate = true
  // `uint8_t matched_temp`.
  let mut matched_temp = 0
  while matched_temp < (self.open_blocks.length() & 0xFF) {
    if self.match_(lexer, self.open_blocks[matched_temp]) {
      matched_temp += 1
    } else {
      return false
    }
  }

  // check if delimiter row has the same number of cells and at least one pipe
  let mut delimiter_cell_count = 0
  if lexer.lookahead == '|' {
    ignore(self.advance(lexer))
  }
  for ;; {
    while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      ignore(self.advance(lexer))
    }
    if lexer.lookahead == '|' {
      delimiter_cell_count += 1
      ignore(self.advance(lexer))
      continue
    }
    if lexer.lookahead == ':' {
      ignore(self.advance(lexer))
      if lexer.lookahead != '-' {
        return false
      }
    }
    let mut had_one_minus = false
    while lexer.lookahead == '-' {
      had_one_minus = true
      ignore(self.advance(lexer))
    }
    if had_one_minus {
      delimiter_cell_count += 1
    }
    if lexer.lookahead == ':' {
      if !had_one_minus {
        return false
      }
      ignore(self.advance(lexer))
    }
    while lexer.lookahead == ' ' || lexer.lookahead == '\t' {
      ignore(self.advance(lexer))
    }
    if lexer.lookahead == '|' {
      if !had_one_minus {
        delimiter_cell_count += 1
      }
      ignore(self.advance(lexer))
      continue
    }
    if lexer.lookahead != '\r' && lexer.lookahead != '\n' {
      return false
    } else {
      break
    }
  }
  // if the cell counts are not equal then this is not a table
  if cell_count != delimiter_cell_count {
    return false
  }
  lexer.result_symbol = MD_PIPE_TABLE_START
  true
}

///|
fn MdScanner::scan(
  self : MdScanner,
  lexer : @runtime.Lexer,
  valid_symbols : ArrayView[Bool],
) -> Bool {
  // Once `MAX_OPEN_BLOCKS` blocks are open, block markers are parsed as text
  let valid_symbols = if self.open_blocks.length() >= MD_MAX_OPEN_BLOCKS {
    let limited_valid_symbols = FixedArray::make(MD_NUM_TOKEN_TYPES, false)
    for i in 0..<MD_NUM_TOKEN_TYPES {
      limited_valid_symbols[i] = valid_symbols[i] && !md_opens_block(i)
    }
    limited_valid_symbols[:]
  } else {
    valid_symbols
  }
  // A normal tree-sitter rule decided that the current branch is invalid and
  // now "requests" an error to stop the branch
  if valid_symbols[MD_TRIGGER_ERROR] {
    return md_error(lexer)
  }

  // Close the inner most block after the next line break as requested. See
  // `$._close_block` in grammar.js
  if valid_symbols[MD_CLOSE_BLOCK] {
    self.state = self.state | MD_STATE_CLOSE_BLOCK
    lexer.result_symbol = MD_CLOSE_BLOCK
    return true
  }

  // if we are at the end of the file and there are still open blocks close
  // them all
  if lexer.eof() {
    if valid_symbols[MD_TOKEN_EOF] {
      lexer.result_symbol = MD_TOKEN_EOF
      return true
    }
    if self.open_blocks.length() > 0 {
      lexer.result_symbol = MD_BLOCK_CLOSE
      if !self.simulate {
        ignore(self.pop_block())
      }
      return true
    }
    return false
  }
  if (self.state & MD_STATE_MATCHING) == 0 {
    // Parse any preceeding whitespace and remember its length. This makes a
    // lot of parsing quite a bit easier.
    for ;; {
      if lexer.lookahead == ' ' || lexer.lookahead == '\t' {
        self.advance_indentation(lexer)
      } else {
        break
      }
    }
    // We are not matching. This is where the parsing logic for most
    // "normal" token is. Most importantly parsing logic for the start of
    // new blocks.
    if valid_symbols[MD_INDENTED_CHUNK_START] &&
      !valid_symbols[MD_NO_INDENTED_CHUNK] {
      if self.indentation >= 4 &&
        lexer.lookahead != '\n' &&
        lexer.lookahead != '\r' {
        lexer.result_symbol = MD_INDENTED_CHUNK_START
        if !self.simulate {
          self.push_block(MD_INDENTED_CODE_BLOCK)
        }
        self.indentation -= 4
        return true
      }
    }
    // Decide which tokens to consider based on the first non-whitespace
    // character
    match lexer.lookahead {
      '\r' | '\n' =>
        if valid_symbols[MD_BLANK_LINE_START] {
          // A blank line token is actually just 0 width, so do not
          // consume the characters
          lexer.result_symbol = MD_BLANK_LINE_START
          return true
        }
      // A backtick could mark the beginning or ending of a fenced
      // code block.
      '`' => return self.parse_fenced_code_block('`', lexer, valid_symbols)
      // A tilde could mark the beginning or ending of a fenced code
      // block.
      '~' => return self.parse_fenced_code_block('~', lexer, valid_symbols)
      // A star could either mark  a list item or a thematic break.
      // This code is similar to the code for '_' and '+'.
      '*' => return self.parse_star(lexer, valid_symbols)
      '_' => return self.parse_thematic_break_underscore(lexer, valid_symbols)
      // A '>' could mark the beginning of a block quote
      '>' => return self.parse_block_quote(lexer, valid_symbols)
      // A '#' could mark a atx heading
      '#' => return self.parse_atx_heading(lexer, valid_symbols)
      // A '=' could mark a setext underline
      '=' => return self.parse_setext_underline(lexer, valid_symbols)
      // A '+' could be a list marker
      '+' => return self.parse_plus(lexer, valid_symbols)
      // A number could be a list marker (if followed by a dot or a
      // parenthesis)
      '0'..<='9' => return self.parse_ordered_list_marker(lexer, valid_symbols)
      // A minus could mark a list marker, a thematic break or a
      // setext underline
      '-' => return self.parse_minus(lexer, valid_symbols)
      // A < could mark the beginning of a html block
      '<' => return self.parse_html_block(lexer, valid_symbols)
      _ => ()
    }
    if lexer.lookahead != '\r' &&
      lexer.lookahead != '\n' &&
      valid_symbols[MD_PIPE_TABLE_START] {
      return self.parse_pipe_table(lexer, valid_symbols)
    }
  } else { // we are in the state of trying to match all currently open blocks
    let mut partial_success = false
    while self.matched < (self.open_blocks.length() & 0xFF) {
      if self.matched == (self.open_blocks.length() & 0xFF) - 1 &&
        (self.state & MD_STATE_CLOSE_BLOCK) != 0 {
        if !partial_success {
          self.state = md_clear(self.state, MD_STATE_CLOSE_BLOCK)
        }
        break
      }
      if self.match_(lexer, self.open_blocks[self.matched]) {
        partial_success = true
        self.matched = (self.matched + 1) & 0xFF
      } else {
        if (self.state & MD_STATE_WAS_SOFT_LINE_BREAK) != 0 {
          self.state = md_clear(self.state, MD_STATE_MATCHING)
        }
        break
      }
    }
    if partial_success {
      if self.matched == self.open_blocks.length() {
        self.state = md_clear(self.state, MD_STATE_MATCHING)
      }
      lexer.result_symbol = MD_BLOCK_CONTINUATION
      return true
    }
    if (self.state & MD_STATE_WAS_SOFT_LINE_BREAK) == 0 {
      lexer.result_symbol = MD_BLOCK_CLOSE
      ignore(self.pop_block())
      if self.matched == self.open_blocks.length() {
        self.state = md_clear(self.state, MD_STATE_MATCHING)
      }
      return true
    }
  }

  // The parser just encountered a line break. Setup the state correspondingly
  if (
      valid_symbols[MD_LINE_ENDING] ||
      valid_symbols[MD_SOFT_LINE_ENDING] ||
      valid_symbols[MD_PIPE_TABLE_LINE_ENDING]
    ) &&
    (lexer.lookahead == '\n' || lexer.lookahead == '\r') {
    if lexer.lookahead == '\r' {
      ignore(self.advance(lexer))
      if lexer.lookahead == '\n' {
        ignore(self.advance(lexer))
      }
    } else {
      ignore(self.advance(lexer))
    }
    self.indentation = 0
    self.column = 0
    if (self.state & MD_STATE_CLOSE_BLOCK) == 0 &&
      (
        valid_symbols[MD_SOFT_LINE_ENDING] ||
        valid_symbols[MD_PIPE_TABLE_LINE_ENDING]
      ) {
      lexer.mark_end()
      for ;; {
        if lexer.lookahead == ' ' || lexer.lookahead == '\t' {
          self.advance_indentation(lexer)
        } else {
          break
        }
      }
      self.simulate = true
      let matched_temp = self.matched
      self.matched = 0
      let mut one_will_be_matched = false
      while self.matched < (self.open_blocks.length() & 0xFF) {
        if self.match_(lexer, self.open_blocks[self.matched]) {
          self.matched = (self.matched + 1) & 0xFF
          one_will_be_matched = true
        } else {
          break
        }
      }
      let all_will_be_matched = self.matched == self.open_blocks.length()
      if !lexer.eof() && !self.scan(lexer, md_paragraph_interrupt_symbols[:]) {
        self.matched = matched_temp
        // If the last line break ended a paragraph and no new block
        // opened, the last line break should have been a soft line
        // break Reset the counter for matched blocks
        self.matched = 0
        self.indentation = 0
        self.column = 0
        // If there is at least one open block, we should be in the
        // matching state. Also set the matching flag if a
        // `$._soft_line_break_marker` can be emitted so it does get
        // emitted.
        if one_will_be_matched {
          self.state = self.state | MD_STATE_MATCHING
        } else {
          self.state = md_clear(self.state, MD_STATE_MATCHING)
        }
        if valid_symbols[MD_PIPE_TABLE_LINE_ENDING] {
          if all_will_be_matched {
            lexer.result_symbol = MD_PIPE_TABLE_LINE_ENDING
            return true
          }
        } else {
          lexer.result_symbol = MD_SOFT_LINE_ENDING
          // reset some state variables
          self.state = self.state | MD_STATE_WAS_SOFT_LINE_BREAK
          return true
        }
      } else {
        self.matched = matched_temp
      }
      self.indentation = 0
      self.column = 0
    }
    if valid_symbols[MD_LINE_ENDING] {
      // If the last line break ended a paragraph and no new block opened,
      // the last line break should have been a soft line break Reset the
      // counter for matched blocks
      self.matched = 0
      // If there is at least one open block, we should be in the matching
      // state. Also set the matching flag if a
      // `$._soft_line_break_marker` can be emitted so it does get
      // emitted.
      if self.open_blocks.length() > 0 {
        self.state = self.state | MD_STATE_MATCHING
      } else {
        self.state = md_clear(self.state, MD_STATE_MATCHING)
      }
      // reset some state variables
      self.state = md_clear(self.state, MD_STATE_WAS_SOFT_LINE_BREAK)
      lexer.result_symbol = MD_LINE_ENDING
      return true
    }
  }
  false
}

///|
fn markdown_scanner() -> @runtime.ExternalScanner {
  let scanner : MdScanner = {
    open_blocks: [],
    state: 0,
    matched: 0,
    indentation: 0,
    column: 0,
    fenced_code_block_delimiter_length: 0,
    simulate: false,
  }
  // `_Static_assert(ATX_H6_MARKER == ATX_H1_MARKER + 5, "")`.
  if MD_ATX_H6_MARKER != MD_ATX_H1_MARKER + 5 {
    abort("assert(ATX_H6_MARKER == ATX_H1_MARKER + 5)")
  }
  scanner.deserialize(b""[:])
  {
    scan: (lexer, valid_symbols) => {
      scanner.simulate = false
      scanner.scan(lexer, valid_symbols)
    },
    serialize: buffer => scanner.serialize(buffer),
    deserialize: buffer => scanner.deserialize(buffer),
    destroy: () => scanner.open_blocks.clear(),
  }
}
