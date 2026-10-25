// A compact serialization of `Language`, for embedding the tables of a
// grammar in MoonBit source (the grammar modules under grammars/ and the
// output of `tree-sitter build`). It has no upstream equivalent: C parsers
// embed the tables as array initializers in parser.c.
//
// Layers, outermost first:
//
// 1. Text (`to_compact_base64`, `from_compact_base64`): standard base64
//    (RFC 4648, with padding) of the container. The decoder ignores ASCII
//    whitespace, so the text may be split over the lines of a multi-line
//    string literal.
// 2. Container (`to_compact`, `from_compact`): the byte `compact_format_version`,
//    the length of the raw stream as an unsigned LEB128 varint, then the raw
//    stream compressed with a byte-oriented LZ77 (`lz_compress`).
// 3. Raw stream: the fields of `Language` in declaration order, as unsigned
//    LEB128 varints (`u`), zigzag-encoded signed varints (`s`) where a value
//    may be negative or is a difference, and the compositions below.
//
// Raw stream compositions:
// - `ints`: `u` length, then `u` per element.
// - `sparse`: `u` length, `u` number of non-zero elements, then per non-zero
//   element `u` (index - previous non-zero index - 1) and `u` value. Used for
//   the mostly-zero row-major tables (`parse_table`, `alias_sequences`).
// - `deltas`: `u` length, then `s` (element - previous element), the first
//   relative to 0 (`small_parse_table_map`, which increases).
// - `index deltas`: `u` length, then `s` (index - element)
//   (`public_symbol_map`, `primary_state_ids`, mostly the identity or close
//   to it).
// - `string`: `u` number of characters, then `u` per character code.
// - `bools`: `u` length, then one byte (0 or 1) per element.
// - `ParseActionEntry`: a tag byte, then: `Entry`: tag 0 (not reusable) or 1
//   (reusable), `u` count; `Shift`: tag 2 + extra + 2 * repetition, `u`
//   state; `Reduce`: tag 6, `u` symbol, `u` child count, `s` dynamic
//   precedence, `u` production id; `Accept`: tag 7; `Recover`: tag 8.
// - `FieldMapEntry`: `u` field id, `u` (child index * 2 + inherited).
// - `MapSlice`: `u` index, `u` length.
// - `SymbolMetadata`: `u` (visible + 2 * named + 4 * supertype).
// - `LexMode`: `u` lex state, `u` external lex state, `u` reserved word set.
// - ranges (a `CharacterRange` list): `u` count, then per range `s` (start -
//   previous range's end, the first relative to 0) and `u` (end - start).
// - `RangeCondition`: `u` (range count * 2 + is_included), then the ranges
//   as above without their count.
// - `LexProgram`: `u` state count; per state `u` flags (1: accept token,
//   2: eof advance), `u` accept token, `u` eof advance state (when
//   present), `u` advance map length and `u` (character, state) per entry,
//   `u` transition count and per transition `u` flags (1: skip, 2: large
//   set, 4: large set guarded by `!eof`, 8: asserted, 16: negated), `u`
//   state, `u` large set index, asserted and negated conditions (when
//   present); then `u` large character set count and the ranges of each.
// - `keyword_lex_fn`: a byte 0 (absent) or 1 followed by the program.
// - `metadata`: `u` major, minor and patch version.

///|
/// The version of the compact format written by `Language::to_compact`.
pub let compact_format_version : Int = 1

///|
/// A malformed or unsupported compact language.
pub(all) suberror CompactError {
  CompactError(String)
} derive(Debug)

///|
pub impl Show for CompactError with fn output(self, logger) {
  let CompactError(message) = self
  logger.write_string("invalid compact language: \{message}")
}

// ---------------------------------------------------------------------------
// Writing

///|
priv struct CompactWriter {
  buf : @buffer.Buffer
}

///|
fn CompactWriter::uint(self : CompactWriter, value : Int) -> Unit raise {
  if value < 0 {
    raise CompactError("negative value \{value} in an unsigned field")
  }
  let mut v = value
  while v >= 0x80 {
    self.buf.write_byte(((v & 0x7f) | 0x80).to_byte())
    v = v >> 7
  }
  self.buf.write_byte(v.to_byte())
}

///|
fn CompactWriter::sint(self : CompactWriter, value : Int) -> Unit {
  // Zigzag, computed in 64 bits so that every Int is representable.
  let v = value.to_int64()
  let mut z = ((v << 1) ^ (v >> 63)).reinterpret_as_uint64()
  while z >= 0x80UL {
    self.buf.write_byte(((z & 0x7fUL) | 0x80UL).to_byte())
    z = z >> 7
  }
  self.buf.write_byte(z.to_byte())
}

///|
fn CompactWriter::byte(self : CompactWriter, value : Int) -> Unit {
  self.buf.write_byte(value.to_byte())
}

///|
fn CompactWriter::bool(self : CompactWriter, value : Bool) -> Unit {
  self.byte(if value { 1 } else { 0 })
}

///|
fn CompactWriter::ints(
  self : CompactWriter,
  values : Array[Int],
) -> Unit raise {
  self.uint(values.length())
  for v in values {
    self.uint(v)
  }
}

///|
fn CompactWriter::sparse(
  self : CompactWriter,
  values : Array[Int],
) -> Unit raise {
  self.uint(values.length())
  let mut nonzero = 0
  for v in values {
    if v != 0 {
      nonzero += 1
    }
  }
  self.uint(nonzero)
  let mut previous = -1
  for i, v in values {
    if v != 0 {
      self.uint(i - previous - 1)
      self.uint(v)
      previous = i
    }
  }
}

///|
fn CompactWriter::deltas(
  self : CompactWriter,
  values : Array[Int],
) -> Unit raise {
  self.uint(values.length())
  let mut previous = 0
  for v in values {
    self.sint(v - previous)
    previous = v
  }
}

///|
fn CompactWriter::index_deltas(
  self : CompactWriter,
  values : Array[Int],
) -> Unit raise {
  self.uint(values.length())
  for i, v in values {
    self.sint(i - v)
  }
}

///|
fn CompactWriter::string(self : CompactWriter, value : String) -> Unit raise {
  let chars = value.to_array()
  self.uint(chars.length())
  for c in chars {
    self.uint(c.to_int())
  }
}

///|
fn CompactWriter::strings(
  self : CompactWriter,
  values : Array[String],
) -> Unit raise {
  self.uint(values.length())
  for v in values {
    self.string(v)
  }
}

///|
fn CompactWriter::bools(
  self : CompactWriter,
  values : Array[Bool],
) -> Unit raise {
  self.uint(values.length())
  for v in values {
    self.bool(v)
  }
}

///|
fn CompactWriter::map_slices(
  self : CompactWriter,
  values : Array[MapSlice],
) -> Unit raise {
  self.uint(values.length())
  for s in values {
    self.uint(s.index)
    self.uint(s.length)
  }
}

///|
fn CompactWriter::range_list(
  self : CompactWriter,
  ranges : Array[CharacterRange],
) -> Unit raise {
  let mut previous = 0
  for r in ranges {
    self.sint(r.start - previous)
    self.uint(r.end - r.start)
    previous = r.end
  }
}

///|
fn CompactWriter::range_condition(
  self : CompactWriter,
  condition : RangeCondition,
) -> Unit raise {
  self.uint(
    condition.ranges.length() * 2 + (if condition.is_included { 1 } else { 0 }),
  )
  self.range_list(condition.ranges)
}

///|
fn CompactWriter::lex_program(
  self : CompactWriter,
  program : LexProgram,
) -> Unit raise {
  self.uint(program.states.length())
  for state in program.states {
    let flags = (if state.accept_token is Some(_) { 1 } else { 0 }) |
      (if state.eof_advance is Some(_) { 2 } else { 0 })
    self.uint(flags)
    if state.accept_token is Some(symbol) {
      self.uint(symbol)
    }
    if state.eof_advance is Some(next) {
      self.uint(next)
    }
    self.uint(state.advance_map.length())
    for entry in state.advance_map {
      self.uint(entry.0)
      self.uint(entry.1)
    }
    self.uint(state.transitions.length())
    for t in state.transitions {
      let c = t.condition
      let flags = (if t.skip { 1 } else { 0 }) |
        (match c.large_set {
          Some((_, true)) => 2 | 4
          Some((_, false)) => 2
          None => 0
        }) |
        (if c.asserted is Some(_) { 8 } else { 0 }) |
        (if c.negated is Some(_) { 16 } else { 0 })
      self.uint(flags)
      self.uint(t.state)
      if c.large_set is Some((index, _)) {
        self.uint(index)
      }
      if c.asserted is Some(condition) {
        self.range_condition(condition)
      }
      if c.negated is Some(condition) {
        self.range_condition(condition)
      }
    }
  }
  self.uint(program.large_character_sets.length())
  for set in program.large_character_sets {
    self.uint(set.length())
    self.range_list(set)
  }
}

///|
fn CompactWriter::parse_action(
  self : CompactWriter,
  entry : ParseActionEntry,
) -> Unit raise {
  match entry {
    Entry(count~, reusable~) => {
      self.byte(if reusable { 1 } else { 0 })
      self.uint(count)
    }
    Shift(state~, extra~, repetition~) => {
      self.byte(
        2 + (if extra { 1 } else { 0 }) + (if repetition { 2 } else { 0 }),
      )
      self.uint(state)
    }
    Reduce(symbol~, child_count~, dynamic_precedence~, production_id~) => {
      self.byte(6)
      self.uint(symbol)
      self.uint(child_count)
      self.sint(dynamic_precedence)
      self.uint(production_id)
    }
    Accept => self.byte(7)
    Recover => self.byte(8)
  }
}

///|
/// The raw stream (layer 3) of a language.
fn write_raw(language : Language) -> Bytes raise {
  let w = CompactWriter::{ buf: @buffer.Buffer(size_hint=1 << 16), }
  let l = language
  w.uint(l.abi_version)
  w.uint(l.symbol_count)
  w.uint(l.alias_count)
  w.uint(l.token_count)
  w.uint(l.external_token_count)
  w.uint(l.state_count)
  w.uint(l.large_state_count)
  w.uint(l.production_id_count)
  w.uint(l.field_count)
  w.uint(l.max_alias_sequence_length)
  w.sparse(l.parse_table)
  w.ints(l.small_parse_table)
  w.deltas(l.small_parse_table_map)
  w.uint(l.parse_actions.length())
  for entry in l.parse_actions {
    w.parse_action(entry)
  }
  w.strings(l.symbol_names)
  w.strings(l.field_names)
  w.map_slices(l.field_map_slices)
  w.uint(l.field_map_entries.length())
  for e in l.field_map_entries {
    w.uint(e.field_id)
    // Packed with `inherited` into one unsigned `Int`, so the index must be
    // in 0..=0x3FFFFFFF (upstream's is a `uint8_t`).
    if e.child_index < 0 || e.child_index > 0x3FFFFFFF {
      raise CompactError("child index \{e.child_index} out of range")
    }
    w.uint(e.child_index * 2 + (if e.inherited { 1 } else { 0 }))
  }
  w.uint(l.symbol_metadata.length())
  for m in l.symbol_metadata {
    w.uint(
      (if m.visible { 1 } else { 0 }) |
      (if m.named { 2 } else { 0 }) |
      (if m.supertype { 4 } else { 0 }),
    )
  }
  w.index_deltas(l.public_symbol_map)
  w.ints(l.alias_map)
  w.sparse(l.alias_sequences)
  w.uint(l.lex_modes.length())
  for m in l.lex_modes {
    w.uint(m.lex_state)
    w.uint(m.external_lex_state)
    w.uint(m.reserved_word_set_id)
  }
  w.lex_program(l.lex_fn)
  match l.keyword_lex_fn {
    Some(program) => {
      w.byte(1)
      w.lex_program(program)
    }
    None => w.byte(0)
  }
  w.uint(l.keyword_capture_token)
  w.bools(l.external_scanner.states)
  w.ints(l.external_scanner.symbol_map)
  w.index_deltas(l.primary_state_ids)
  w.string(l.name)
  w.ints(l.reserved_words)
  w.uint(l.max_reserved_word_set_size)
  w.uint(l.supertype_count)
  w.ints(l.supertype_symbols)
  w.map_slices(l.supertype_map_slices)
  w.ints(l.supertype_map_entries)
  w.uint(l.metadata.major_version)
  w.uint(l.metadata.minor_version)
  w.uint(l.metadata.patch_version)
  w.buf.to_bytes()
}

///|
/// Serialize this language in the compact binary format (layer 2: version
/// byte, raw length, LZ77-compressed raw stream). Raises if a field that the
/// format stores unsigned is negative, which a generated language never has.
pub fn Language::to_compact(self : Language) -> Bytes raise CompactError {
  let raw = write_raw(self) catch {
    CompactError(_) as e => raise e
    e => raise CompactError(e.to_string())
  }
  let w = CompactWriter::{ buf: @buffer.Buffer(size_hint=raw.length() / 4), }
  w.byte(compact_format_version)
  w.uint(raw.length()) catch {
    _ => ()
  }
  w.buf.write_bytes(lz_compress(raw))
  w.buf.to_bytes()
}

///|
/// `to_compact` as base64 text (layer 1), on a single line.
pub fn Language::to_compact_base64(
  self : Language,
) -> String raise CompactError {
  base64_encode(self.to_compact())
}

// ---------------------------------------------------------------------------
// Reading

///|
priv struct CompactReader {
  data : FixedArray[Byte]
  mut pos : Int
}

///|
fn CompactReader::byte(self : CompactReader) -> Int raise CompactError {
  if self.pos >= self.data.length() {
    raise CompactError("unexpected end of data")
  }
  let b = self.data[self.pos].to_int()
  self.pos += 1
  b
}

///|
fn CompactReader::uint(self : CompactReader) -> Int raise CompactError {
  let mut result = 0
  let mut shift = 0
  for ;; {
    let b = self.byte()
    if shift > 28 || (shift == 28 && (b & 0x7f) > 7) {
      raise CompactError("varint out of range")
    }
    result = result | ((b & 0x7f) << shift)
    if b < 0x80 {
      break
    }
    shift += 7
  }
  result
}

///|
fn CompactReader::sint(self : CompactReader) -> Int raise CompactError {
  // The zigzag encoding of an `Int` has at most 32 bits; anything longer
  // (whose high bits would otherwise be dropped) is rejected.
  let mut z = 0UL
  let mut shift = 0
  for ;; {
    let b = self.byte()
    if shift > 28 || (shift == 28 && (b & 0x7f) > 15) {
      raise CompactError("varint out of range")
    }
    z = z | ((b & 0x7f).to_uint64() << shift)
    if b < 0x80 {
      break
    }
    shift += 7
  }
  let v = (z >> 1).reinterpret_as_int64() ^ -(z & 1UL).reinterpret_as_int64()
  v.to_int()
}

///|
fn CompactReader::bool(self : CompactReader) -> Bool raise CompactError {
  match self.byte() {
    0 => false
    1 => true
    b => raise CompactError("invalid boolean \{b}")
  }
}

///|
/// A length, checked against the remaining data so that corrupt input cannot
/// request a huge allocation: each element takes at least `min_bytes` bytes.
fn CompactReader::length(
  self : CompactReader,
  min_bytes~ : Int = 1,
) -> Int raise CompactError {
  let n = self.uint()
  if min_bytes > 0 && n > (self.data.length() - self.pos) / min_bytes {
    raise CompactError("length \{n} exceeds the data")
  }
  n
}

///|
fn CompactReader::ints(self : CompactReader) -> Array[Int] raise CompactError {
  let n = self.length()
  let result = Array::make(n, 0)
  for i in 0..<n {
    result[i] = self.uint()
  }
  result
}

///|
fn CompactReader::sparse(
  self : CompactReader,
) -> Array[Int] raise CompactError {
  // A sparse array may be much longer than its encoding, so its length is
  // bounded by the declared size limit below instead of the data length.
  let n = self.length(min_bytes=0)
  if n > 1 << 28 {
    raise CompactError("sparse array length \{n} is too large")
  }
  let nonzero = self.length(min_bytes=2)
  let result = Array::make(n, 0)
  let mut index = -1
  for _ in 0..<nonzero {
    // `index + gap + 1 < n`, compared before adding (which could overflow).
    let gap = self.uint()
    if gap >= n - 1 - index {
      raise CompactError("sparse index out of range")
    }
    index = index + gap + 1
    result[index] = self.uint()
  }
  result
}

///|
fn CompactReader::deltas(
  self : CompactReader,
) -> Array[Int] raise CompactError {
  let n = self.length()
  let result = Array::make(n, 0)
  let mut previous = 0
  for i in 0..<n {
    previous = previous + self.sint()
    result[i] = previous
  }
  result
}

///|
fn CompactReader::index_deltas(
  self : CompactReader,
) -> Array[Int] raise CompactError {
  let n = self.length()
  let result = Array::make(n, 0)
  for i in 0..<n {
    result[i] = i - self.sint()
  }
  result
}

///|
fn CompactReader::string(self : CompactReader) -> String raise CompactError {
  let n = self.length()
  let sb = StringBuilder(size_hint=n)
  for _ in 0..<n {
    let code = self.uint()
    if code > 0x10FFFF {
      raise CompactError("invalid character code \{code}")
    }
    sb.write_char(code.unsafe_to_char())
  }
  sb.to_string()
}

///|
fn CompactReader::strings(
  self : CompactReader,
) -> Array[String] raise CompactError {
  let n = self.length()
  Array::makei(n, _ => self.string())
}

///|
fn CompactReader::bools(self : CompactReader) -> Array[Bool] raise CompactError {
  let n = self.length()
  Array::makei(n, _ => self.bool())
}

///|
fn CompactReader::map_slices(
  self : CompactReader,
) -> Array[MapSlice] raise CompactError {
  let n = self.length(min_bytes=2)
  Array::makei(n, _ => {
    let index = self.uint()
    let length = self.uint()
    { index, length, }
  })
}

///|
fn CompactReader::range_list(
  self : CompactReader,
  n : Int,
) -> Array[CharacterRange] raise CompactError {
  let mut previous = 0
  Array::makei(n, _ => {
    let start = previous + self.sint()
    let end = start + self.uint()
    previous = end
    { start, end, }
  })
}

///|
fn CompactReader::range_condition(
  self : CompactReader,
) -> RangeCondition raise CompactError {
  let header = self.uint()
  let n = header >> 1
  if n > (self.data.length() - self.pos) / 2 {
    raise CompactError("length \{n} exceeds the data")
  }
  let ranges = self.range_list(n)
  { ranges, is_included: (header & 1) == 1, }
}

///|
fn CompactReader::lex_program(
  self : CompactReader,
) -> LexProgram raise CompactError {
  let state_count = self.length(min_bytes=3)
  let states = Array::makei(state_count, _ => {
    let flags = self.uint()
    let accept_token = if (flags & 1) != 0 { Some(self.uint()) } else { None }
    let eof_advance = if (flags & 2) != 0 { Some(self.uint()) } else { None }
    let map_length = self.length(min_bytes=2)
    let advance_map = Array::makei(map_length, _ => {
      let c = self.uint()
      let s = self.uint()
      (c, s)
    })
    let transition_count = self.length(min_bytes=2)
    let transitions = Array::makei(transition_count, _ => {
      let flags = self.uint()
      let state = self.uint()
      let large_set = if (flags & 2) != 0 {
        Some((self.uint(), (flags & 4) != 0))
      } else {
        None
      }
      let asserted = if (flags & 8) != 0 {
        Some(self.range_condition())
      } else {
        None
      }
      let negated = if (flags & 16) != 0 {
        Some(self.range_condition())
      } else {
        None
      }
      LexTransition::{
        condition: { large_set, asserted, negated, },
        state,
        skip: (flags & 1) != 0,
      }
    })
    LexStateCode::{ accept_token, eof_advance, advance_map, transitions, }
  })
  let set_count = self.length()
  let large_character_sets = Array::makei(set_count, _ => {
    let n = self.length(min_bytes=2)
    self.range_list(n)
  })
  { states, large_character_sets, }
}

///|
fn CompactReader::parse_action(
  self : CompactReader,
) -> ParseActionEntry raise CompactError {
  match self.byte() {
    tag if tag <= 1 => Entry(count=self.uint(), reusable=tag == 1)
    tag if tag <= 5 =>
      Shift(
        state=self.uint(),
        extra=((tag - 2) & 1) != 0,
        repetition=((tag - 2) & 2) != 0,
      )
    6 => {
      let symbol = self.uint()
      let child_count = self.uint()
      let dynamic_precedence = self.sint()
      let production_id = self.uint()
      Reduce(symbol~, child_count~, dynamic_precedence~, production_id~)
    }
    7 => Accept
    8 => Recover
    tag => raise CompactError("invalid parse action tag \{tag}")
  }
}

///|
fn read_raw(data : FixedArray[Byte]) -> Language raise CompactError {
  let r = CompactReader::{ data, pos: 0, }
  let abi_version = r.uint()
  let symbol_count = r.uint()
  let alias_count = r.uint()
  let token_count = r.uint()
  let external_token_count = r.uint()
  let state_count = r.uint()
  let large_state_count = r.uint()
  let production_id_count = r.uint()
  let field_count = r.uint()
  let max_alias_sequence_length = r.uint()
  let parse_table = r.sparse()
  let small_parse_table = r.ints()
  let small_parse_table_map = r.deltas()
  let action_count = r.length()
  let parse_actions = Array::makei(action_count, _ => r.parse_action())
  let symbol_names = r.strings()
  let field_names = r.strings()
  let field_map_slices = r.map_slices()
  let entry_count = r.length(min_bytes=2)
  let field_map_entries = Array::makei(entry_count, _ => {
    let field_id = r.uint()
    let packed = r.uint()
    FieldMapEntry::{
      field_id,
      child_index: packed >> 1,
      inherited: (packed & 1) == 1,
    }
  })
  let metadata_count = r.length()
  let symbol_metadata = Array::makei(metadata_count, _ => {
    let bits = r.uint()
    SymbolMetadata::{
      visible: (bits & 1) != 0,
      named: (bits & 2) != 0,
      supertype: (bits & 4) != 0,
    }
  })
  let public_symbol_map = r.index_deltas()
  let alias_map = r.ints()
  let alias_sequences = r.sparse()
  let mode_count = r.length(min_bytes=3)
  let lex_modes = Array::makei(mode_count, _ => {
    let lex_state = r.uint()
    let external_lex_state = r.uint()
    let reserved_word_set_id = r.uint()
    LexMode::{ lex_state, external_lex_state, reserved_word_set_id, }
  })
  let lex_fn = r.lex_program()
  let keyword_lex_fn = if r.bool() { Some(r.lex_program()) } else { None }
  let keyword_capture_token = r.uint()
  let states = r.bools()
  let symbol_map = r.ints()
  let primary_state_ids = r.index_deltas()
  let name = r.string()
  let reserved_words = r.ints()
  let max_reserved_word_set_size = r.uint()
  let supertype_count = r.uint()
  let supertype_symbols = r.ints()
  let supertype_map_slices = r.map_slices()
  let supertype_map_entries = r.ints()
  let major_version = r.uint()
  let minor_version = r.uint()
  let patch_version = r.uint()
  if r.pos != data.length() {
    raise CompactError("\{data.length() - r.pos} trailing bytes")
  }
  {
    abi_version,
    symbol_count,
    alias_count,
    token_count,
    external_token_count,
    state_count,
    large_state_count,
    production_id_count,
    field_count,
    max_alias_sequence_length,
    parse_table,
    small_parse_table,
    small_parse_table_map,
    parse_actions,
    symbol_names,
    field_names,
    field_map_slices,
    field_map_entries,
    symbol_metadata,
    public_symbol_map,
    alias_map,
    alias_sequences,
    lex_modes,
    lex_fn,
    keyword_lex_fn,
    keyword_capture_token,
    external_scanner: { states, symbol_map, },
    primary_state_ids,
    name,
    reserved_words,
    max_reserved_word_set_size,
    supertype_count,
    supertype_symbols,
    supertype_map_slices,
    supertype_map_entries,
    metadata: { major_version, minor_version, patch_version, },
  }
}

///|
/// Decode a language serialized by `Language::to_compact`.
pub fn Language::from_compact(data : BytesView) -> Language raise CompactError {
  let header = CompactReader::{
    data: FixedArray::from_iter(data.iter()),
    pos: 0,
  }
  read_container(header)
}

///|
fn read_container(header : CompactReader) -> Language raise CompactError {
  let version = header.byte()
  if version != compact_format_version {
    raise CompactError("unsupported format version \{version}")
  }
  let raw_length = header.uint()
  if raw_length > 1 << 30 {
    raise CompactError("raw length \{raw_length} is too large")
  }
  read_raw(lz_decompress(header.data, header.pos, raw_length))
}

///|
/// Decode the base64 text written by `Language::to_compact_base64`; ASCII
/// whitespace (for example the line breaks of a multi-line string literal) is
/// ignored.
pub fn Language::from_compact_base64(
  text : StringView,
) -> Language raise CompactError {
  read_container(CompactReader::{ data: base64_decode(text), pos: 0, })
}
