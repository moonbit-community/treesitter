// Port of tree-sitter crates/generate/src/render.rs: `add_parser_export`'s
// `TSLanguage` initializer, built as a `@language.Language` from the same
// tables `RenderedParser::print_c` prints. Arrays are laid out exactly as the
// C arrays they mirror, including designated initializers (a later
// initializer for the same index wins, as in C) and zero-filled gaps. Fields
// the C initializer leaves out (`NULL`, or absent for the ABI version) are
// empty arrays, zero, or `""`. Every value is converted to the width of the C
// field or array element it initializes (`uint16_t`, `uint8_t`, ...), as the
// C compiler does, and strings are the values of the C string literals.

///|
fn RenderedParser::to_language(self : RenderedParser) -> @language.Language {
  let with_reserved_words = self.abi_version >= abi_version_with_reserved_words
  let parse_table = Array::make(self.large_state_count * self.symbol_count, 0)
  for i, row in self.large_states {
    let base = i * self.symbol_count
    for entry in row.nonterminals {
      parse_table[base + entry.0] = c_uint16(entry.1)
    }
    for entry in row.terminals {
      parse_table[base + entry.0] = c_uint16(entry.1)
    }
  }
  let small_parse_table = []
  for groups in self.small_states {
    small_parse_table.push(c_uint16(groups.length()))
    for group in groups {
      small_parse_table.push(c_uint16(group.value))
      small_parse_table.push(c_uint16(group.symbols.length()))
      for symbol in group.symbols {
        small_parse_table.push(c_uint16(symbol))
      }
    }
  }
  let parse_actions : Array[@language.ParseActionEntry] = []
  for list in self.parse_actions {
    // The C compiler truncates these fields to the widths of the
    // `TSParseActionEntry` union; do the same.
    parse_actions.push(
      @language.ParseActionEntry::Entry(
        count=list.actions.length(),
        reusable=list.reusable,
      ).normalized(),
    )
    for action in list.actions {
      parse_actions.push(action.normalized())
    }
  }
  let has_fields = !self.field_names.is_empty()
  let field_map_entries = []
  if has_fields {
    for row in self.field_map_rows {
      for entry in row.1 {
        field_map_entries.push(@language.FieldMapEntry::{
          field_id: c_uint16(entry.field_id),
          child_index: c_uint8(entry.child_index),
          inherited: entry.inherited,
        })
      }
    }
  }
  let alias_map = []
  for entry in self.alias_map {
    let (symbol, public_symbol, alias_ids) = entry
    alias_map.push(c_uint16(symbol))
    alias_map.push(c_uint16(1 + alias_ids.length()))
    alias_map.push(c_uint16(public_symbol))
    for alias_id in alias_ids {
      alias_map.push(c_uint16(alias_id))
    }
  }
  alias_map.push(0)
  let alias_sequences = Array::make(
    self.production_id_count * self.max_alias_sequence_length,
    0,
  )
  for i, alias_sequence in self.alias_sequences {
    for j, alias in alias_sequence {
      if alias is Some(alias) {
        alias_sequences[i * self.max_alias_sequence_length + j] = c_uint16(
          alias,
        )
      }
    }
  }
  let external_scanner_states = []
  for externals in self.external_lex_states {
    let row = Array::make(self.external_token_count, false)
    for index in externals {
      row[index] = true
    }
    external_scanner_states.push_iter(row.iter())
  }
  let reserved_words = []
  if with_reserved_words && self.reserved_word_sets.length() > 1 {
    for set in self.reserved_word_sets {
      for i in 0..<self.max_reserved_word_set_size {
        reserved_words.push(c_uint16(set.get(i).unwrap_or(0)))
      }
    }
  }
  let emit_supertypes = with_reserved_words && !self.supertype_rows.is_empty()
  let supertype_symbols = []
  let supertype_map_slices : Array[@language.MapSlice] = []
  let supertype_map_entries = []
  if emit_supertypes {
    for row in self.supertype_rows {
      let (supertype, subtypes) = row
      supertype_symbols.push(c_uint16(supertype))
      while supertype_map_slices.length() <= supertype {
        supertype_map_slices.push({ index: 0, length: 0, })
      }
      supertype_map_slices[supertype] = {
        index: c_uint16(supertype_map_entries.length()),
        length: c_uint16(subtypes.length()),
      }
      for subtype in subtypes {
        supertype_map_entries.push(c_uint16(subtype))
      }
    }
  }
  let (major_version, minor_version, patch_version) = if with_reserved_words {
    self.metadata.unwrap_or((0, 0, 0))
  } else {
    (0, 0, 0)
  }
  {
    abi_version: self.abi_version,
    symbol_count: self.symbol_count,
    alias_count: self.alias_count,
    token_count: self.token_count,
    external_token_count: self.external_token_count,
    state_count: self.state_count,
    large_state_count: self.large_state_count,
    production_id_count: self.production_id_count,
    field_count: self.field_names.length(),
    max_alias_sequence_length: c_uint16(self.max_alias_sequence_length),
    parse_table,
    small_parse_table,
    small_parse_table_map: self.small_state_indices,
    parse_actions,
    // C string literals: `sanitize_string`'s escapes as the C compiler
    // decodes them, cut at the first NUL.
    symbol_names: self.symbol_names.map(name => {
      c_string_literal_value(Generator::sanitize_str(name))
    }),
    // Field names and the language name are printed without escaping.
    field_names: if has_fields {
      [""] + self.field_names.map(c_string_literal_value)
    } else {
      []
    },
    field_map_slices: if has_fields {
      self.field_map_slices.map(slice => {
        index: c_uint16(slice.index),
        length: c_uint16(slice.length),
      })
    } else {
      []
    },
    field_map_entries,
    symbol_metadata: self.symbol_metadata,
    public_symbol_map: self.public_symbol_map.map(c_uint16),
    alias_map,
    alias_sequences,
    lex_modes: self.lex_modes.map(mode => {
      // `(TSStateId)(-1)` initializes `lex_state` only.
      match mode {
        Some(mode) =>
          {
            lex_state: c_uint16(mode.lex_state),
            external_lex_state: c_uint16(mode.external_lex_state),
            reserved_word_set_id: c_uint16(mode.reserved_word_set_id),
          }
        None =>
          { lex_state: 65535, external_lex_state: 0, reserved_word_set_id: 0 }
      }
    }),
    lex_fn: c_lex_program(self.lex_fn),
    keyword_lex_fn: self.keyword_lex_fn.map(c_lex_program),
    keyword_capture_token: c_uint16(self.keyword_capture_token.unwrap_or(0)),
    external_scanner: {
      states: external_scanner_states,
      symbol_map: self.external_scanner_symbol_map.map(c_uint16),
    },
    primary_state_ids: self.primary_state_ids.map(c_uint16),
    name: if with_reserved_words {
      c_string_literal_value(self.language_name)
    } else {
      ""
    },
    reserved_words,
    max_reserved_word_set_size: if with_reserved_words {
      c_uint16(self.max_reserved_word_set_size)
    } else {
      0
    },
    supertype_count: self.supertype_rows.length(),
    supertype_symbols,
    supertype_map_slices,
    supertype_map_entries,
    metadata: {
      major_version: c_uint8(major_version),
      minor_version: c_uint8(minor_version),
      patch_version: c_uint8(patch_version),
    },
  }
}

///|
/// The value of an integer constant converted to `uint16_t`.
fn c_uint16(value : Int) -> Int {
  value & 0xFFFF
}

///|
/// The value of an integer constant converted to `uint8_t`.
fn c_uint8(value : Int) -> Int {
  value & 0xFF
}

///|
/// The lex function `program` describes, with the states and symbols it
/// assigns converted to `TSStateId` and `TSSymbol`, as the C code does
/// (`state = n`, `lexer->result_symbol = n`, the `uint16_t` `ADVANCE_MAP`).
/// A state whose id does not fit in a `TSStateId` is then unreachable, like
/// its `case` label in the C `switch (state)`.
fn c_lex_program(program : @language.LexProgram) -> @language.LexProgram {
  {
    states: program.states.map(state => {
      accept_token: state.accept_token.map(c_uint16),
      eof_advance: state.eof_advance.map(c_uint16),
      advance_map: state.advance_map.map(entry => (entry.0, c_uint16(entry.1))),
      transitions: state.transitions.map(transition => {
        ..transition,
        state: c_uint16(transition.state),
      }),
    }),
    large_character_sets: program.large_character_sets,
  }
}

///|
/// The string a C string literal with contents `literal` denotes, as a
/// `const char *` read up to its first NUL, with UTF-8 source and execution
/// character sets. Escapes follow C11: an octal escape takes up to three
/// octal digits and a hexadecimal escape every following hexadecimal digit
/// (an out-of-range value, which clang rejects, keeps its low 8 bits, as GCC
/// does); `\u`/`\U` name a code point, also below U+00A0 (as in C23). Bytes
/// that are not UTF-8 decode to U+FFFD.
fn c_string_literal_value(literal : String) -> String {
  let bytes = Buffer(size_hint=literal.length())
  let chars = literal.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    i += 1
    if c != '\\' || i >= n {
      bytes.write_char_utf8(c)
      continue
    }
    let e = chars[i]
    i += 1
    let byte = match e {
      'a' => 7
      'b' => 8
      'f' => 12
      'n' => 10
      'r' => 13
      't' => 9
      'v' => 11
      '0'..='7' => {
        let mut value = e.to_int() - '0'.to_int()
        let mut digits = 1
        while digits < 3 && i < n && chars[i] is ('0'..='7') {
          value = value * 8 + (chars[i].to_int() - '0'.to_int())
          i += 1
          digits += 1
        }
        value & 0xFF
      }
      'x' => {
        let mut value = 0
        while i < n && c_hex_digit(chars[i]) is Some(d) {
          value = ((value << 4) | d) & 0xFFFF
          i += 1
        }
        value & 0xFF
      }
      'u' | 'U' => {
        let len = if e == 'u' { 4 } else { 8 }
        let mut value = 0
        let mut digits = 0
        while digits < len && i < n && c_hex_digit(chars[i]) is Some(d) {
          value = (value << 4) | d
          i += 1
          digits += 1
        }
        match value.to_char() {
          Some(ch) => bytes.write_char_utf8(ch)
          None => bytes.write_char_utf8('\u{FFFD}')
        }
        continue
      }
      // `\"`, `\'`, `\?`, `\\`, and unknown escapes (which compilers warn
      // about) denote the character itself.
      _ => {
        bytes.write_char_utf8(e)
        continue
      }
    }
    bytes.write_byte(byte.to_byte())
  }
  let data = bytes.to_bytes()
  let mut end = 0
  while end < data.length() && data[end] != 0 {
    end += 1
  }
  @utf8.decode_lossy(data[0:end])
}

///|
fn c_hex_digit(c : Char) -> Int? {
  match c {
    '0'..='9' => Some(c.to_int() - '0'.to_int())
    'a'..='f' => Some(c.to_int() - 'a'.to_int() + 10)
    'A'..='F' => Some(c.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}
