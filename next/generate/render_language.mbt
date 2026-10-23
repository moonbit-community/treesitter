// Port of tree-sitter crates/generate/src/render.rs: `add_parser_export`'s
// `TSLanguage` initializer, built as a `@language.Language` from the same
// tables `RenderedParser::print_c` prints. Arrays are laid out exactly as the
// C arrays they mirror, including designated initializers (a later
// initializer for the same index wins, as in C) and zero-filled gaps. Fields
// the C initializer leaves out (`NULL`, or absent for the ABI version) are
// empty arrays, zero, or `""`.

///|
fn RenderedParser::to_language(self : RenderedParser) -> @language.Language {
  let with_reserved_words = self.abi_version >= abi_version_with_reserved_words
  let parse_table = Array::make(self.large_state_count * self.symbol_count, 0)
  for i, row in self.large_states {
    let base = i * self.symbol_count
    for entry in row.nonterminals {
      parse_table[base + entry.0] = entry.1
    }
    for entry in row.terminals {
      parse_table[base + entry.0] = entry.1
    }
  }
  let small_parse_table = []
  for groups in self.small_states {
    small_parse_table.push(groups.length())
    for group in groups {
      small_parse_table.push(group.value)
      small_parse_table.push(group.symbols.length())
      for symbol in group.symbols {
        small_parse_table.push(symbol)
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
        field_map_entries.push(entry)
      }
    }
  }
  let alias_map = []
  for entry in self.alias_map {
    let (symbol, public_symbol, alias_ids) = entry
    alias_map.push(symbol)
    alias_map.push(1 + alias_ids.length())
    alias_map.push(public_symbol)
    for alias_id in alias_ids {
      alias_map.push(alias_id)
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
        alias_sequences[i * self.max_alias_sequence_length + j] = alias
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
        reserved_words.push(set.get(i).unwrap_or(0))
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
      supertype_symbols.push(supertype)
      while supertype_map_slices.length() <= supertype {
        supertype_map_slices.push({ index: 0, length: 0, })
      }
      supertype_map_slices[supertype] = {
        index: supertype_map_entries.length(),
        length: subtypes.length(),
      }
      for subtype in subtypes {
        supertype_map_entries.push(subtype)
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
    max_alias_sequence_length: self.max_alias_sequence_length,
    parse_table,
    small_parse_table,
    small_parse_table_map: self.small_state_indices,
    parse_actions,
    symbol_names: self.symbol_names,
    field_names: if has_fields {
      [""] + self.field_names
    } else {
      []
    },
    field_map_slices: if has_fields {
      self.field_map_slices
    } else {
      []
    },
    field_map_entries,
    symbol_metadata: self.symbol_metadata,
    public_symbol_map: self.public_symbol_map,
    alias_map,
    alias_sequences,
    lex_modes: self.lex_modes.map(mode => {
      // `(TSStateId)(-1)` initializes `lex_state` only.
      mode.unwrap_or({
        lex_state: 65535,
        external_lex_state: 0,
        reserved_word_set_id: 0,
      })
    }),
    lex_fn: self.lex_fn,
    keyword_lex_fn: self.keyword_lex_fn,
    keyword_capture_token: self.keyword_capture_token.unwrap_or(0),
    external_scanner: {
      states: external_scanner_states,
      symbol_map: self.external_scanner_symbol_map,
    },
    primary_state_ids: self.primary_state_ids,
    name: if with_reserved_words {
      self.language_name
    } else {
      ""
    },
    reserved_words,
    max_reserved_word_set_size: if with_reserved_words {
      self.max_reserved_word_set_size
    } else {
      0
    },
    supertype_count: self.supertype_rows.length(),
    supertype_symbols,
    supertype_map_slices,
    supertype_map_entries,
    metadata: { major_version, minor_version, patch_version, },
  }
}
