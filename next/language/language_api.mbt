// Port of tree-sitter lib/src/language.c and lib/src/language.h.

///|
pub let ts_builtin_sym_error_repeat : Int32 = 65534

///|
pub let language_version_with_reserved_words : Int32 = 15

///|
pub let language_version_with_primary_states : Int32 = 14

///|
/// `TableEntry`: the actions for a state/symbol pair are
/// `parse_actions[actions_start:actions_start + action_count]`.
pub(all) struct TableEntry {
  actions_start : Int32
  action_count : Int32
  is_reusable : Bool
} derive(Eq, Debug)

///|
pub fn Language::actions_of(
  self : Language,
  entry : TableEntry,
) -> ArrayView[ParseActionEntry] {
  self.parse_actions[entry.actions_start:entry.actions_start +
  entry.action_count]
}

///|
pub fn Language::table_entry(
  self : Language,
  state : Int32,
  symbol : Int32,
) -> TableEntry {
  if symbol == ts_builtin_sym_error || symbol == ts_builtin_sym_error_repeat {
    { actions_start: 0, action_count: 0, is_reusable: false, }
  } else {
    let action_index = self.lookup(state, symbol)
    guard self.parse_actions[action_index] is Entry(count~, reusable~) else {
      abort("parse action index does not point at an entry header")
    }
    {
      actions_start: action_index + 1,
      action_count: count,
      is_reusable: reusable,
    }
  }
}

///|
/// `ts_language_actions`.
pub fn Language::actions(
  self : Language,
  state : Int32,
  symbol : Int32,
) -> ArrayView[ParseActionEntry] {
  self.actions_of(self.table_entry(state, symbol))
}

///|
pub fn Language::has_reduce_action(
  self : Language,
  state : Int32,
  symbol : Int32,
) -> Bool {
  let entry = self.table_entry(state, symbol)
  entry.action_count > 0 &&
  self.parse_actions[entry.actions_start] is Reduce(..)
}

///|
/// Lookup the table value for a given symbol and state.
///
/// For non-terminal symbols, the table value represents a successor state.
/// For terminal symbols, it represents an index in the actions table. For
/// 'large' parse states, this is a direct lookup. For 'small' parse states,
/// this requires searching through the symbol groups to find the given symbol.
pub fn Language::lookup(
  self : Language,
  state : Int32,
  symbol : Int32,
) -> Int32 {
  if state >= self.large_state_count {
    let index = self.small_parse_table_map[state - self.large_state_count]
    let data = self.small_parse_table
    let mut i = index
    let group_count = data[i]
    i += 1
    for _ in 0..<group_count {
      let section_value = data[i]
      let symbol_count = data[i + 1]
      i += 2
      for _ in 0..<symbol_count {
        if data[i] == symbol {
          return section_value
        }
        i += 1
      }
    }
    0
  } else {
    self.parse_table[state * self.symbol_count + symbol]
  }
}

///|
pub fn Language::has_actions(
  self : Language,
  state : Int32,
  symbol : Int32,
) -> Bool {
  self.lookup(state, symbol) != 0
}

///|
priv enum LookaheadPhase {
  /// No `next()` yet.
  Fresh
  /// Last `next()` returned true.
  Positioned
  /// Last `next()` returned false.
  Done
} derive(Eq)

///|
/// Iterate over all of the symbols that are valid in the given state
/// (`LookaheadIterator`).
pub struct LookaheadIterator {
  priv mut language : Language
  priv mut data : Int32
  priv mut group_end : Int32
  priv mut table_value : Int32
  priv mut group_count : Int32
  priv mut is_small_state : Bool
  priv mut phase : LookaheadPhase
  priv mut actions_start : Int32
  priv mut symbol : Int32
  priv mut next_state : Int32
  priv mut action_count : Int32
}

///|
/// `ts_language_lookaheads`.
pub fn Language::lookaheads(
  self : Language,
  state : Int32,
) -> LookaheadIterator {
  let is_small_state = state >= self.large_state_count
  let mut data = 0
  let mut group_end = 0
  let mut group_count = 0
  if is_small_state {
    data = self.small_parse_table_map[state - self.large_state_count]
    group_end = data + 1
    group_count = self.small_parse_table[data]
  } else {
    data = state * self.symbol_count
  }
  {
    language: self,
    data,
    group_end,
    table_value: 0,
    group_count,
    is_small_state,
    phase: Fresh,
    actions_start: 0,
    symbol: 65535,
    next_state: 0,
    action_count: 0,
  }
}

///|
/// `ts_lookahead_iterator__next`.
pub fn LookaheadIterator::next(self : LookaheadIterator) -> Bool {
  if self.phase == Done {
    return false
  }
  let language = self.language
  // For small parse states, valid symbols are listed explicitly, grouped by
  // their value. There's no need to look up the actions again until moving to
  // the next group.
  if self.is_small_state {
    let table = language.small_parse_table
    self.data += 1
    if self.data == self.group_end {
      if self.group_count == 0 {
        self.phase = Done
        return false
      }
      self.group_count -= 1
      self.table_value = table[self.data]
      self.data += 1
      let symbol_count = table[self.data]
      self.data += 1
      self.group_end = self.data + symbol_count
      self.symbol = table[self.data]
    } else {
      self.symbol = table[self.data]
      self.phase = Positioned
      return true
    }
  } else {
    // For large parse states, iterate through every symbol until one is found
    // that has valid actions.
    let row = self.data
    let mut symbol = if self.phase == Fresh { 0 } else { self.symbol + 1 }
    while symbol < language.symbol_count &&
          language.parse_table[row + symbol] == 0 {
      symbol += 1
    }
    if symbol >= language.symbol_count {
      self.phase = Done
      return false
    }
    self.symbol = symbol
    self.table_value = language.parse_table[row + symbol]
  }
  // Depending on if the symbol is terminal or non-terminal, the table value
  // either represents a list of actions or a successor state.
  if self.symbol < language.token_count {
    guard language.parse_actions[self.table_value] is Entry(count~, ..) else {
      abort("parse action index does not point at an entry header")
    }
    self.action_count = count
    self.actions_start = self.table_value + 1
    self.next_state = 0
  } else {
    self.action_count = 0
    self.next_state = self.table_value
  }
  self.phase = Positioned
  true
}

///|
pub fn LookaheadIterator::current_symbol(self : LookaheadIterator) -> Int32 {
  self.symbol
}

///|
pub fn LookaheadIterator::next_state(self : LookaheadIterator) -> Int32 {
  self.next_state
}

///|
pub fn LookaheadIterator::actions(
  self : LookaheadIterator,
) -> ArrayView[ParseActionEntry] {
  self.language.parse_actions[self.actions_start:self.actions_start +
  self.action_count]
}

///|
pub fn LookaheadIterator::language(self : LookaheadIterator) -> Language {
  self.language
}

///|
/// `ts_lookahead_iterator_current_symbol_name`.
pub fn LookaheadIterator::current_symbol_name(
  self : LookaheadIterator,
) -> String? {
  if self.phase != Positioned {
    return None
  }
  self.language.symbol_name(self.symbol)
}

///|
/// `ts_lookahead_iterator_new`.
pub fn LookaheadIterator::new(
  language : Language,
  state : Int32,
) -> LookaheadIterator? {
  if state >= language.state_count {
    return None
  }
  Some(language.lookaheads(state))
}

///|
/// `ts_lookahead_iterator_reset_state`.
pub fn LookaheadIterator::reset_state(
  self : LookaheadIterator,
  state : Int32,
) -> Bool {
  if state >= self.language.state_count {
    return false
  }
  self.reset_to(self.language.lookaheads(state))
  true
}

///|
/// `ts_lookahead_iterator_reset`.
pub fn LookaheadIterator::reset(
  self : LookaheadIterator,
  language : Language,
  state : Int32,
) -> Bool {
  if state >= language.state_count {
    return false
  }
  self.reset_to(language.lookaheads(state))
  true
}

///|
fn LookaheadIterator::reset_to(
  self : LookaheadIterator,
  other : LookaheadIterator,
) -> Unit {
  self.language = other.language
  self.data = other.data
  self.group_end = other.group_end
  self.table_value = other.table_value
  self.group_count = other.group_count
  self.is_small_state = other.is_small_state
  self.phase = other.phase
  self.actions_start = other.actions_start
  self.symbol = other.symbol
  self.next_state = other.next_state
  self.action_count = other.action_count
}

///|
/// Whether the state is a "primary state". If this returns false, another
/// state behaves identically to this one with respect to query analysis.
pub fn Language::state_is_primary(self : Language, state : Int32) -> Bool {
  if self.abi_version >= language_version_with_primary_states {
    state == self.primary_state_ids[state]
  } else {
    true
  }
}

///|
/// `ts_language_enabled_external_tokens`: the offset of the enabled-token row
/// in `external_scanner.states`, or `None` for external scanner state 0.
pub fn Language::enabled_external_tokens(
  self : Language,
  external_scanner_state : Int32,
) -> ArrayView[Bool]? {
  if external_scanner_state == 0 {
    None
  } else {
    let start = self.external_token_count * external_scanner_state
    Some(self.external_scanner.states[start:start + self.external_token_count])
  }
}

///|
/// `ts_language_alias_sequence`: the start offset into `alias_sequences`, or
/// `None` for production id 0.
pub fn Language::alias_sequence(
  self : Language,
  production_id : Int32,
) -> Int32? {
  if production_id != 0 {
    Some(production_id * self.max_alias_sequence_length)
  } else {
    None
  }
}

///|
pub fn Language::alias_at(
  self : Language,
  production_id : Int,
  child_index : Int,
) -> Int {
  if production_id != 0 {
    // Upstream indexes the flat array without checking the row bounds, so an
    // index past the row reads the next production's row. Past the end of
    // the array (undefined behavior in C) this returns 0.
    self.alias_sequences.get(
      production_id * self.max_alias_sequence_length + child_index,
    ).unwrap_or(0)
  } else {
    0
  }
}

///|
/// `ts_language_field_map`: `[start, end)` indices into `field_map_entries`.
pub fn Language::field_map(
  self : Language,
  production_id : Int32,
) -> (Int32, Int32) {
  if self.field_count == 0 {
    return (0, 0)
  }
  let slice = self.field_map_slices[production_id]
  (slice.index, slice.index + slice.length)
}

///|
/// `ts_language_aliases_for_symbol`: the public symbols a symbol may appear as.
pub fn Language::aliases_for_symbol(
  self : Language,
  original_symbol : Int32,
) -> ArrayView[Int32] {
  let mut result = self.public_symbol_map[original_symbol:original_symbol + 1]
  let mut idx = 0
  for ;; {
    let symbol = self.alias_map[idx]
    idx += 1
    if symbol == 0 || symbol > original_symbol {
      break
    }
    let count = self.alias_map[idx]
    idx += 1
    if symbol == original_symbol {
      result = self.alias_map[idx:idx + count]
      break
    }
    idx += count
  }
  result
}

///|
pub fn Language::symbol_count_with_aliases(self : Language) -> Int32 {
  self.symbol_count + self.alias_count
}

///|
/// `ts_language_supertypes`.
pub fn Language::supertypes(self : Language) -> ArrayView[Int32] {
  if self.abi_version >= language_version_with_reserved_words {
    self.supertype_symbols[0:self.supertype_count]
  } else {
    []
  }
}

///|
/// `ts_language_subtypes`.
pub fn Language::subtypes(
  self : Language,
  supertype : Int32,
) -> ArrayView[Int32] {
  if self.abi_version < language_version_with_reserved_words ||
    supertype >= self.symbol_count_with_aliases() ||
    !self.symbol_metadata_of(supertype).supertype {
    return []
  }
  let slice = self.supertype_map_slices[supertype]
  self.supertype_map_entries[slice.index:slice.index + slice.length]
}

///|
/// `ts_language_metadata`.
pub fn Language::language_metadata(self : Language) -> LanguageMetadata? {
  if self.abi_version >= language_version_with_reserved_words {
    Some(self.metadata)
  } else {
    None
  }
}

///|
/// `ts_language_name`.
pub fn Language::language_name(self : Language) -> String? {
  if self.abi_version >= language_version_with_reserved_words {
    Some(self.name)
  } else {
    None
  }
}

///|
/// `ts_language_lex_mode_for_state`. ABI 14 tables are converted to the ABI 15
/// layout when loaded, so this is a direct lookup.
pub fn Language::lex_mode_for_state(self : Language, state : Int32) -> LexMode {
  self.lex_modes[state]
}

///|
pub fn Language::is_reserved_word(
  self : Language,
  state : Int32,
  symbol : Int32,
) -> Bool {
  let lex_mode = self.lex_mode_for_state(state)
  if lex_mode.reserved_word_set_id > 0 {
    let start = lex_mode.reserved_word_set_id * self.max_reserved_word_set_size
    let end = start + self.max_reserved_word_set_size
    for i in start..<end {
      if self.reserved_words[i] == symbol {
        return true
      }
      if self.reserved_words[i] == 0 {
        break
      }
    }
  }
  false
}

///|
/// `ts_language_symbol_metadata`.
pub fn Language::symbol_metadata_of(
  self : Language,
  symbol : Int32,
) -> SymbolMetadata {
  if symbol == ts_builtin_sym_error {
    { visible: true, named: true, supertype: false, }
  } else if symbol == ts_builtin_sym_error_repeat {
    { visible: false, named: false, supertype: false, }
  } else {
    self.symbol_metadata[symbol]
  }
}

///|
/// `ts_language_public_symbol`.
pub fn Language::public_symbol(self : Language, symbol : Int32) -> Int32 {
  if symbol == ts_builtin_sym_error {
    return symbol
  }
  self.public_symbol_map[symbol]
}

///|
/// `ts_language_next_state`.
pub fn Language::next_state(
  self : Language,
  state : Int32,
  symbol : Int32,
) -> Int32 {
  if symbol == ts_builtin_sym_error ||
    symbol == ts_builtin_sym_error_repeat ||
    symbol >= self.symbol_count ||
    state >= self.state_count {
    0
  } else if symbol < self.token_count {
    let actions = self.actions(state, symbol)
    if actions.length() > 0 {
      if actions[actions.length() - 1] is Shift(state=next, extra~, ..) {
        return if extra { state } else { next }
      }
    }
    0
  } else {
    self.lookup(state, symbol)
  }
}

///|
/// `ts_language_symbol_name`.
pub fn Language::symbol_name(self : Language, symbol : Int32) -> String? {
  if symbol == ts_builtin_sym_error {
    Some("ERROR")
  } else if symbol == ts_builtin_sym_error_repeat {
    Some("_ERROR")
  } else if symbol < self.symbol_count_with_aliases() {
    Some(self.symbol_names[symbol])
  } else {
    None
  }
}

///|
/// `ts_language_symbol_for_name`.
pub fn Language::symbol_for_name(
  self : Language,
  string : StringView,
  is_named : Bool,
) -> Int32 {
  if is_named && string == "ERROR" {
    return ts_builtin_sym_error
  }
  let count = self.symbol_count_with_aliases() & 0xFFFF
  for i in 0..<count {
    let metadata = self.symbol_metadata_of(i)
    if (!metadata.visible && !metadata.supertype) || metadata.named != is_named {
      continue
    }
    if self.symbol_names[i][:] == string {
      return self.public_symbol_map[i]
    }
  }
  0
}

///|
pub(all) enum SymbolType {
  Regular
  Anonymous
  Supertype
  Auxiliary
} derive(Eq, Debug)

///|
/// `ts_language_symbol_type`.
pub fn Language::symbol_type(self : Language, symbol : Int32) -> SymbolType {
  let metadata = self.symbol_metadata_of(symbol)
  if metadata.named && metadata.visible {
    Regular
  } else if metadata.visible {
    Anonymous
  } else if metadata.supertype {
    Supertype
  } else {
    Auxiliary
  }
}

///|
/// `ts_language_field_name_for_id`.
pub fn Language::field_name_for_id(self : Language, id : Int32) -> String? {
  let count = self.field_count
  if count != 0 && id <= count {
    Some(self.field_names[id])
  } else {
    None
  }
}

///|
/// `ts_language_field_id_for_name`. Field names are sorted, so the search
/// stops at the first name that sorts after `name` (upstream's `strncmp`
/// returning -1).
pub fn Language::field_id_for_name(self : Language, name : StringView) -> Int32 {
  let count = self.field_count & 0xFFFF
  for i in 1..<(count + 1) {
    let field_name = self.field_names[i]
    // Upstream: `switch (strncmp(name, field_names[i], name_length))` with
    // `case 0` (exact match check) and `case -1: return 0`. The C library
    // returns the difference of the first differing bytes, so only a
    // difference of exactly -1 ends the search early.
    match strncmp(name, field_name, @utf8.encode(name).length()) {
      0 => if field_name[:] == name { return i }
      -1 => return 0
      _ => ()
    }
  }
  0
}

///|
/// C `strncmp` over UTF-8 bytes, returning the difference of the first
/// differing bytes (as the macOS/glibc implementations do).
fn strncmp(a : StringView, b : StringView, n : Int32) -> Int32 {
  let a = @utf8.encode(a)
  let b = @utf8.encode(b)
  for i in 0..<n {
    let ca = if i < a.length() { a[i].to_int() } else { 0 }
    let cb = if i < b.length() { b[i].to_int() } else { 0 }
    if ca != cb {
      return ca - cb
    }
    if ca == 0 {
      return 0
    }
  }
  0
}

///|
/// `alias_sequences[index]` with C's flat-array semantics: indexes past a
/// row read the next row; past the end of the array this returns 0.
pub fn Language::alias_sequence_value(self : Language, index : Int) -> Int {
  self.alias_sequences.get(index).unwrap_or(0)
}
