// Port of tree-sitter lib/src/lexer.h and lib/src/lexer.c.

///|
priv struct ColumnData {
  mut value : UInt32
  mut valid : Bool
}

///|
let byte_order_mark : Int32 = 0xFEFF

///|
let default_range : Range = {
  start_point: { row: 0, column: 0, },
  end_point: { row: 0xFFFFFFFFU, column: 0xFFFFFFFFU, },
  start_byte: 0,
  end_byte: 0xFFFFFFFFU,
}

///|
/// The lexer state. Its public methods form the `TSLexer` interface used by
/// lex functions and external scanners.
pub(all) struct Lexer {
  /// `TSLexer.lookahead`.
  mut lookahead : Int32
  /// `TSLexer.result_symbol`.
  mut result_symbol : Int32
  priv mut current_position : Length
  priv mut token_start_position : Length
  priv mut token_end_position : Length
  priv mut included_ranges : Array[Range]
  /// The current chunk, meaningful only when `has_chunk` (C: `chunk` is
  /// non-NULL).
  priv mut chunk : BytesView
  priv mut has_chunk : Bool
  priv mut input : Input
  priv mut logger : Logger?
  priv mut current_included_range_index : Int32
  priv mut chunk_start : UInt32
  priv mut chunk_size : UInt32
  priv mut lookahead_size : UInt32
  priv mut did_get_column : Bool
  priv column_data : ColumnData
  /// `debug_buffer`: every log message is formatted into it, and the parser
  /// also passes it to the external scanner's `serialize`.
  priv debug_buffer : FixedArray[Byte]
}

///|
/// The effect of `snprintf(self->debug_buffer, 1024, ...)` producing
/// `message`: its UTF-8 bytes, truncated to 1023, followed by a NUL.
///
/// Returns the message as the Rust binding's logger callback receives it:
/// the C string in the buffer (up to its first NUL), or `None` when that is
/// not valid UTF-8 (a multi-byte character cut by the truncation), in which
/// case `CStr::to_str` fails and the binding drops the message.
fn Lexer::write_debug_buffer(self : Lexer, message : String) -> String? {
  let bytes = @utf8.encode(message)
  let n = if bytes.length() < self.debug_buffer.length() {
    bytes.length()
  } else {
    self.debug_buffer.length() - 1
  }
  for i in 0..<n {
    self.debug_buffer[i] = bytes[i]
  }
  self.debug_buffer[n] = 0
  if self.debug_message_length() == bytes.length() {
    return Some(message)
  }
  try @utf8.decode(self.debug_message()) catch {
    _ => None
  } noraise {
    message => Some(message)
  }
}

///|
/// The length of the C string in the debug buffer.
fn Lexer::debug_message_length(self : Lexer) -> Int32 {
  for i in 0..<self.debug_buffer.length() {
    if self.debug_buffer[i] == 0 {
      return i
    }
  }
  self.debug_buffer.length()
}

///|
/// The C string in the debug buffer, without its NUL.
fn Lexer::debug_message(self : Lexer) -> Bytes {
  let buffer = self.debug_buffer
  Bytes::makei(self.debug_message_length(), i => buffer[i])
}

///|
fn Lexer::log_char(self : Lexer, message : String, character : Int32) -> Unit {
  if self.logger is Some(log) {
    let text = if 32 <= character && character < 127 {
      "\{message} character:'\{Int::unsafe_to_char(character)}'"
    } else {
      "\{message} character:\{character}"
    }
    if self.write_debug_buffer(text) is Some(text) {
      log(Lex, text)
    }
  }
}

///|
/// Sets the column data to the given value and marks it valid.
fn Lexer::set_column_data(self : Lexer, val : UInt32) -> Unit {
  self.column_data.valid = true
  self.column_data.value = val
}

///|
/// Increments the value of the column data; no-op if invalid.
fn Lexer::increment_column_data(self : Lexer) -> Unit {
  if self.column_data.valid {
    self.column_data.value += 1
  }
}

///|
/// Marks the column data as invalid.
fn Lexer::invalidate_column_data(self : Lexer) -> Unit {
  self.column_data.valid = false
  self.column_data.value = 0
}

///|
/// `ts_lexer__eof`: the lexer has consumed all of its available ranges.
pub fn Lexer::eof(self : Lexer) -> Bool {
  self.current_included_range_index == self.included_ranges.length()
}

///|
/// Clear the currently stored chunk of source code, because the lexer's
/// position has changed.
fn Lexer::clear_chunk(self : Lexer) -> Unit {
  self.chunk = b""[:]
  self.has_chunk = false
  self.chunk_size = 0
  self.chunk_start = 0
}

///|
/// Call the lexer's input callback to obtain a new chunk of source code for
/// the current position.
fn Lexer::get_chunk(self : Lexer) -> Unit {
  self.chunk_start = self.current_position.bytes
  let chunk = (self.input.read)(
    self.current_position.bytes,
    self.current_position.extent,
  )
  self.chunk = chunk
  self.has_chunk = true
  self.chunk_size = chunk.length().reinterpret_as_uint()
  if self.chunk_size == 0 {
    self.current_included_range_index = self.included_ranges.length()
    self.chunk = b""[:]
    self.has_chunk = false
  }
}

///|
fn Lexer::decode(self : Lexer, chunk : BytesView) -> (UInt32, Int32) {
  match self.input.encoding {
    UTF8 => decode_utf8(chunk)
    UTF16LE => decode_utf16_le(chunk)
    UTF16BE => decode_utf16_be(chunk)
    Custom =>
      match self.input.decode {
        Some(decode) => decode(chunk)
        None => decode_utf8(chunk)
      }
  }
}

///|
/// Decode the next unicode character in the current chunk of source code.
/// This assumes that the lexer has already retrieved a chunk of source code
/// that spans the current position.
fn Lexer::get_lookahead(self : Lexer) -> Unit {
  let position_in_chunk = self.current_position.bytes - self.chunk_start
  let size = self.chunk_size - position_in_chunk
  if size == 0 {
    self.lookahead_size = 1
    self.lookahead = 0
    return
  }
  if !self.has_chunk {
    abort("no chunk")
  }
  let data = self.chunk
  let chunk = data[position_in_chunk.reinterpret_as_int():self.chunk_size.reinterpret_as_int()]
  if self.input.encoding is UTF8 && chunk[0] < 0x80 {
    self.lookahead = chunk[0].to_int()
    self.lookahead_size = 1
    return
  }
  let (lookahead_size, lookahead) = self.decode(chunk)
  self.lookahead_size = lookahead_size
  self.lookahead = lookahead
  // If this chunk ended in the middle of a multi-byte character, try again
  // with a fresh chunk.
  if self.lookahead == ts_decode_error && size < 4 {
    self.get_chunk()
    let chunk = if self.has_chunk { self.chunk } else { b""[:] }
    // Upstream decodes even an empty chunk here; the decoders read at least
    // one byte, so an empty chunk is treated as an invalid character.
    let (lookahead_size, lookahead) = if chunk.length() == 0 {
      (0U, ts_decode_error)
    } else {
      self.decode(chunk)
    }
    self.lookahead_size = lookahead_size
    self.lookahead = lookahead
  }
  if self.lookahead == ts_decode_error {
    self.lookahead_size = 1
  }
}

///|
fn Lexer::goto(self : Lexer, position : Length) -> Unit {
  if position.bytes != self.current_position.bytes {
    self.invalidate_column_data()
  }
  self.current_position = position
  // Move to the first valid position at or after the given position.
  let mut found_included_range = false
  for i, included_range in self.included_ranges {
    if included_range.end_byte > self.current_position.bytes &&
      included_range.end_byte > included_range.start_byte {
      if included_range.start_byte >= self.current_position.bytes {
        self.current_position = {
          bytes: included_range.start_byte,
          extent: included_range.start_point,
        }
      }
      self.current_included_range_index = i
      found_included_range = true
      break
    }
  }
  if found_included_range {
    // If the current position is outside of the current chunk of text, then
    // clear out the current chunk of text.
    if self.has_chunk &&
      (
        self.current_position.bytes < self.chunk_start ||
        self.current_position.bytes >= self.chunk_start + self.chunk_size
      ) {
      self.clear_chunk()
    }
    self.lookahead_size = 0
    self.lookahead = 0
  } else {
    // If the given position is beyond any of included ranges, move to the
    // EOF state - past the end of the included ranges.
    self.current_included_range_index = self.included_ranges.length()
    let last_included_range = self.included_ranges[self.included_ranges.length() -
      1]
    self.current_position = {
      bytes: last_included_range.end_byte,
      extent: last_included_range.end_point,
    }
    self.clear_chunk()
    self.lookahead_size = 1
    self.lookahead = 0
  }
}

///|
/// Actually advances the lexer. Does not log anything.
fn Lexer::do_advance(self : Lexer, skip : Bool) -> Unit {
  if self.lookahead_size != 0 {
    if self.lookahead == '\n' {
      self.current_position = {
        ..self.current_position,
        extent: { row: self.current_position.extent.row + 1, column: 0, },
      }
      self.set_column_data(0)
    } else {
      let is_bom = self.current_position.bytes == 0 &&
        self.lookahead == byte_order_mark
      if !is_bom {
        self.increment_column_data()
      }
      self.current_position = {
        ..self.current_position,
        extent: {
          ..self.current_position.extent,
          column: self.current_position.extent.column + self.lookahead_size,
        },
      }
    }
    self.current_position = {
      ..self.current_position,
      bytes: self.current_position.bytes + self.lookahead_size,
    }
  }
  let count = self.included_ranges.length()
  let mut current_range : Range? = Some(
    self.included_ranges[self.current_included_range_index],
  )
  while current_range is Some(range) &&
        (
          self.current_position.bytes >= range.end_byte ||
          range.end_byte == range.start_byte
        ) {
    if self.current_included_range_index < count {
      self.current_included_range_index += 1
    }
    if self.current_included_range_index < count {
      let next = self.included_ranges[self.current_included_range_index]
      current_range = Some(next)
      self.current_position = {
        bytes: next.start_byte,
        extent: next.start_point,
      }
    } else {
      current_range = None
      break
    }
  }
  if skip {
    self.token_start_position = self.current_position
  }
  if current_range is Some(_) {
    if self.current_position.bytes < self.chunk_start ||
      self.current_position.bytes >= self.chunk_start + self.chunk_size {
      self.get_chunk()
    }
    self.get_lookahead()
  } else {
    self.clear_chunk()
    self.lookahead = 0
    self.lookahead_size = 1
  }
}

///|
/// `TSLexer.advance`: advance to the next character in the source code,
/// retrieving a new chunk of source code if needed.
pub fn Lexer::advance(self : Lexer, skip : Bool) -> Unit {
  guard self.has_chunk else { return }
  let chunk = self.chunk
  if self.logger is Some(_) {
    if skip {
      self.log_char("skip", self.lookahead)
    } else {
      self.log_char("consume", self.lookahead)
    }
  }
  let next_position = self.current_position.bytes + 1
  let current_range_end = self.included_ranges[self.current_included_range_index].end_byte
  if self.input.encoding is UTF8 &&
    self.lookahead_size == 1 &&
    self.lookahead != '\n' &&
    next_position < current_range_end &&
    next_position < self.chunk_start + self.chunk_size {
    let next_byte = chunk[(next_position - self.chunk_start).reinterpret_as_int()]
    if next_byte < 0x80 {
      self.increment_column_data()
      self.current_position = {
        bytes: self.current_position.bytes + 1,
        extent: {
          ..self.current_position.extent,
          column: self.current_position.extent.column + 1,
        },
      }
      if skip {
        self.token_start_position = self.current_position
      }
      self.lookahead = next_byte.to_int()
      return
    }
  }
  self.do_advance(skip)
}

///|
/// `TSLexer.mark_end`: mark that a token match has completed. This can be
/// called multiple times if a longer match is found later.
pub fn Lexer::mark_end(self : Lexer) -> Unit {
  if !self.eof() {
    // If the lexer is right at the beginning of included range, then the
    // token should be considered to end at the *end* of the previous included
    // range, rather than here.
    let current_included_range = self.included_ranges[self.current_included_range_index]
    if self.current_included_range_index > 0 &&
      self.current_position.bytes == current_included_range.start_byte {
      let previous_included_range = self.included_ranges[self.current_included_range_index -
        1]
      self.token_end_position = {
        bytes: previous_included_range.end_byte,
        extent: previous_included_range.end_point,
      }
      return
    }
  }
  self.token_end_position = self.current_position
}

///|
/// `TSLexer.get_column`.
pub fn Lexer::get_column(self : Lexer) -> UInt32 {
  self.did_get_column = true
  if !self.column_data.valid {
    // Record current position
    let goal_byte = self.current_position.bytes
    // Back up to the beginning of the line
    let start_of_col : Length = {
      bytes: self.current_position.bytes - self.current_position.extent.column,
      extent: { row: self.current_position.extent.row, column: 0, },
    }
    self.goto(start_of_col)
    self.set_column_data(0)
    self.get_chunk()
    if !self.eof() {
      self.get_lookahead()
      // Advance to the recorded position
      while self.current_position.bytes < goal_byte &&
            !self.eof() &&
            self.has_chunk {
        self.do_advance(false)
        if self.eof() {
          break
        }
      }
    }
  }
  self.column_data.value
}

///|
/// `TSLexer.is_at_included_range_start`: is the lexer at a boundary between
/// two disjoint included ranges of source code?
pub fn Lexer::is_at_included_range_start(self : Lexer) -> Bool {
  if self.current_included_range_index < self.included_ranges.length() {
    let current_range = self.included_ranges[self.current_included_range_index]
    self.current_position.bytes == current_range.start_byte
  } else {
    false
  }
}

///|
/// `TSLexer.log`.
pub fn Lexer::log(self : Lexer, message : String) -> Unit {
  if self.logger is Some(log) {
    // Upstream formats into the 1024-byte debug buffer.
    if self.write_debug_buffer(message) is Some(message) {
      log(Lex, message)
    }
  }
}

///|
/// `ts_lexer_init`.
pub fn Lexer::new() -> Lexer {
  let self = {
    lookahead: 0,
    result_symbol: 0,
    current_position: length_zero(),
    token_start_position: length_zero(),
    token_end_position: length_zero(),
    included_ranges: [],
    chunk: b""[:],
    has_chunk: false,
    input: no_input,
    logger: None,
    current_included_range_index: 0,
    chunk_start: 0,
    chunk_size: 0,
    lookahead_size: 0,
    did_get_column: false,
    column_data: { value: 0, valid: false, },
    debug_buffer: FixedArray::make(
      @language.tree_sitter_serialization_buffer_size, 0,
    ),
  }
  ignore(self.set_included_ranges([]))
  self
}

///|
/// `ts_lexer_set_input`.
pub fn Lexer::set_input(self : Lexer, input : Input) -> Unit {
  self.input = input
  self.clear_chunk()
  self.goto(self.current_position)
}

///|
/// The input of a lexer that has none (`Lexer::new`, `release_input`).
let no_input : Input = { read: (_, _) => b"", encoding: UTF8, decode: None, }

///|
/// Forget the input and its current chunk once a parse call returns. Upstream
/// keeps dangling pointers to them (the Rust binding's input payload ends
/// with the call); a retained closure would keep the source alive. Every
/// parse call starts with `set_input`, which clears the chunk anyway.
fn Lexer::release_input(self : Lexer) -> Unit {
  self.input = no_input
  self.clear_chunk()
}

///|
pub fn Lexer::set_logger(self : Lexer, logger : Logger?) -> Unit {
  self.logger = logger
}

///|
/// `ts_lexer_reset`: move the lexer to the given position. This doesn't do
/// any work if the parser is already at the given position.
pub fn Lexer::reset(self : Lexer, position : Length) -> Unit {
  if position.bytes != self.current_position.bytes {
    self.goto(position)
  }
}

///|
/// `ts_lexer_start`.
pub fn Lexer::start(self : Lexer) -> Unit {
  self.token_start_position = self.current_position
  self.token_end_position = length_undefined
  self.result_symbol = 0
  self.did_get_column = false
  if !self.eof() {
    if self.chunk_size == 0 {
      self.get_chunk()
    }
    if self.lookahead_size == 0 {
      self.get_lookahead()
    }
    if self.current_position.bytes == 0 {
      if self.lookahead == byte_order_mark {
        self.advance(true)
      }
      self.set_column_data(0)
    }
  }
}

///|
/// `ts_lexer_finish`: returns the updated `lookahead_end_byte`.
pub fn Lexer::finish(self : Lexer, lookahead_end_byte : UInt32) -> UInt32 {
  if length_is_undefined(self.token_end_position) {
    self.mark_end()
  }
  // If the token ended at an included range boundary, then its end position
  // will have been reset to the end of the preceding range. Reset the start
  // position to match.
  if self.token_end_position.bytes < self.token_start_position.bytes {
    self.token_start_position = self.token_end_position
  }
  let mut current_lookahead_end_byte = self.current_position.bytes + 1
  // In order to determine that a byte sequence is invalid UTF8 or UTF16, the
  // character decoding algorithm may have looked at the following byte.
  // Therefore, the next byte *after* the current (invalid) character affects
  // the interpretation of the current character.
  if self.lookahead == ts_decode_error {
    current_lookahead_end_byte += 4
  }
  if current_lookahead_end_byte > lookahead_end_byte {
    current_lookahead_end_byte
  } else {
    lookahead_end_byte
  }
}

///|
/// `ts_lexer_set_included_ranges`.
pub fn Lexer::set_included_ranges(self : Lexer, ranges : Array[Range]) -> Bool {
  let ranges = if ranges.is_empty() {
    [default_range]
  } else {
    let mut previous_byte : UInt32 = 0
    for range in ranges {
      if range.start_byte < previous_byte || range.end_byte < range.start_byte {
        return false
      }
      previous_byte = range.end_byte
    }
    ranges.copy()
  }
  self.included_ranges = ranges
  self.goto(self.current_position)
  true
}

///|
/// `ts_lexer_included_ranges`.
pub fn Lexer::included_ranges(self : Lexer) -> Array[Range] {
  self.included_ranges
}

///|
pub fn Lexer::current_position(self : Lexer) -> Length {
  self.current_position
}

///|
pub fn Lexer::token_start_position(self : Lexer) -> Length {
  self.token_start_position
}

///|
pub fn Lexer::token_end_position(self : Lexer) -> Length {
  self.token_end_position
}

///|
pub fn Lexer::did_get_column(self : Lexer) -> Bool {
  self.did_get_column
}

///|
pub fn Lexer::has_logger(self : Lexer) -> Bool {
  self.logger is Some(_)
}
