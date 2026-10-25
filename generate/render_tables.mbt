// Port of tree-sitter crates/generate/src/render.rs: the tables computed by
// upstream's `add_*` methods, gathered into one value that both
// `render_c_code` and `render_language` are derived from.
//
// Every symbol reference is the numeric value of upstream's C identifier
// (`symbol_ids[symbol]`, `alias_ids[alias]`); the C printer converts it back
// through `idents`, so a wrong value shows up as a `parser.c` difference.

///|
priv struct LargeStateRow {
  /// `[symbol] = STATE(state)` lines, in emission order.
  nonterminals : Array[(Int32, Int32)]
  /// `[symbol] = ACTIONS(index)` lines, in emission order.
  terminals : Array[(Int32, Int32)]
}

///|
/// One `STATE(value)`/`ACTIONS(value)` group of a small parse state.
priv struct SmallStateGroup {
  value : Int32
  is_state : Bool
  symbols : Array[Int32]
}

///|
/// One `ts_parse_actions` entry: its index, reusable bit and actions.
priv struct ParseActionList {
  index : Int32
  reusable : Bool
  actions : Array[@language.ParseActionEntry]
}

///|
priv struct RenderedParser {
  abi_version : Int32
  language_name : String
  /// C identifier of every symbol value (symbols, then aliases).
  idents : Array[String]
  /// Values of `parse_table.symbols`, in their order.
  symbol_values : Array[Int32]
  symbol_count : Int32
  alias_count : Int32
  token_count : Int32
  external_token_count : Int32
  state_count : Int32
  large_state_count : Int32
  production_id_count : Int32
  max_alias_sequence_length : Int32
  max_reserved_word_set_size : Int32
  /// Indexed by symbol value; unsanitized.
  symbol_names : Array[String]
  public_symbol_map : Array[Int32]
  symbol_metadata : Array[@language.SymbolMetadata]
  /// Without upstream's `NULL` entry.
  field_names : Array[String]
  /// One per production id.
  field_map_slices : Array[@language.MapSlice]
  /// `ts_field_map_entries` rows `(row_index, entries)`, excluding the empty
  /// row 0.
  field_map_rows : Array[(Int32, Array[@language.FieldMapEntry])]
  /// One per production id; `None` for unaliased steps.
  alias_sequences : Array[Array[Int32?]]
  /// `ts_non_terminal_alias_map` groups: `(symbol, public symbol, aliases)`.
  alias_map : Array[(Int32, Int32, Array[Int32])]
  primary_state_ids : Array[Int32]
  /// `(supertype, subtypes)`, in emission order; empty unless emitted.
  supertype_rows : Array[(Int32, Array[Int32])]
  large_character_set_names : Array[String]
  lex_fn : @language.LexProgram
  keyword_lex_fn : @language.LexProgram?
  /// `None` for the `(TSStateId)(-1)` mode of end-of-non-terminal-extra states.
  lex_modes : Array[@language.LexMode?]
  /// All reserved word sets, set 0 being the empty set.
  reserved_word_sets : Array[Array[Int32]]
  large_states : Array[LargeStateRow]
  small_states : Array[Array[SmallStateGroup]]
  small_state_indices : Array[Int32]
  parse_actions : Array[ParseActionList]
  external_token_ids : Array[String]
  external_scanner_symbol_map : Array[Int32]
  /// External token indices of each external lex state.
  external_lex_states : Array[Array[Int32]]
  keyword_capture_token : Int32?
  metadata : (Int32, Int32, Int32)?
}

///|
/// Upstream `Generator::generate`, minus the printing.
fn Generator::generate(self : Generator) -> RenderedParser raise RenderError {
  self.init()
  self.assign_symbol_order()
  let idents = self.symbol_identifiers()
  let value_of_ident : Map[String, Int32] = Map([])
  for value, ident in idents {
    if !value_of_ident.contains(ident) {
      value_of_ident[ident] = value
    }
  }
  let symbol_values = self.parse_table.symbols.map(s => self.symbol_order[s])
  let (symbol_names, public_symbol_map, symbol_metadata) = self.symbol_lists(
    idents.length(),
  )
  let (field_map_slices, field_map_rows) = self.field_sequences()
  let (parse_actions, large_states, small_states, small_state_indices) = self.parse_tables()
  let supertype_rows = if self.abi_version >= abi_version_with_reserved_words &&
    !self.supertype_map.is_empty() {
    self.supertype_rows(value_of_ident)
  } else {
    []
  }
  let mut max_reserved_word_set_size = 0
  for set in self.reserved_word_sets {
    if set.len() > max_reserved_word_set_size {
      max_reserved_word_set_size = set.len()
    }
  }
  let lex_fn = self.lex_program(self.main_lex_table)
  let keyword_lex_fn = if self.syntax_grammar.word_token is Some(_) {
    Some(self.lex_program(self.keyword_lex_table))
  } else {
    None
  }
  {
    abi_version: self.abi_version,
    language_name: self.language_name,
    idents,
    symbol_values,
    symbol_count: self.parse_table.symbols.length(),
    alias_count: self.unique_aliases.length(),
    token_count: self.token_count(),
    external_token_count: self.syntax_grammar.external_tokens.length(),
    state_count: self.parse_table.states.length(),
    large_state_count: self.large_state_count,
    production_id_count: self.parse_table.production_infos.length(),
    max_alias_sequence_length: self.parse_table.max_aliased_production_length,
    max_reserved_word_set_size,
    symbol_names,
    public_symbol_map,
    symbol_metadata,
    field_names: self.field_names.map(id => self.str_pool.resolve(id)),
    field_map_slices,
    field_map_rows,
    alias_sequences: self.parse_table.production_infos.map(info => {
      info.alias_sequence.map(alias => {
        match alias {
          Some(alias) => Some(value_of_ident[self.alias_ids[alias]])
          None => None
        }
      })
    }),
    alias_map: self.non_terminal_alias_map(value_of_ident),
    primary_state_ids: self.primary_state_ids(),
    supertype_rows,
    large_character_set_names: self.large_character_set_info.map(info => {
      info.constant_name
    }),
    lex_fn,
    keyword_lex_fn,
    lex_modes: self.lex_modes(),
    reserved_word_sets: self.reserved_word_sets.map(set => {
      set.iter().map(token => self.symbol_value(token))
    }),
    large_states,
    small_states,
    small_state_indices,
    parse_actions,
    external_token_ids: Array::makei(
      self.syntax_grammar.external_tokens.length(),
      i => self.external_token_id(i),
    ),
    external_scanner_symbol_map: self.external_scanner_symbol_map(),
    external_lex_states: self.parse_table.external_lex_states.map(set => {
      set.externals()
    }),
    keyword_capture_token: match self.syntax_grammar.word_token {
      Some(token) => Some(self.symbol_value(token))
      None => None
    },
    metadata: self.metadata,
  }
}

///|
/// The identifiers of `add_symbol_enum`, indexed by value.
fn Generator::symbol_identifiers(self : Generator) -> Array[String] {
  let idents = Array::make(
    self.parse_table.symbols.length() + self.unique_aliases.length(),
    "",
  )
  idents[0] = self.symbol_ids[symbol_end]
  for symbol in self.parse_table.symbols {
    idents[self.symbol_order[symbol]] = self.symbol_ids[symbol]
  }
  for i, alias in self.unique_aliases {
    idents[self.parse_table.symbols.length() + i] = self.alias_ids[alias]
  }
  idents
}

///|
/// `TOKEN_COUNT` of `add_stats`.
fn Generator::token_count(self : Generator) -> Int32 {
  let mut count = 0
  for symbol in self.parse_table.symbols {
    let is_token = match symbol.kind {
      Terminal | End => true
      External =>
        self.syntax_grammar.external_tokens[symbol.index].corresponding_internal_token
        is None
      EndOfNonTerminalExtra | NonTerminal => false
    }
    if is_token {
      count += 1
    }
  }
  count
}

///|
/// The contents of `add_symbol_names_list`, `add_unique_symbol_map` and
/// `add_symbol_metadata_list`, indexed by symbol value.
fn Generator::symbol_lists(
  self : Generator,
  count : Int32,
) -> (Array[String], Array[Int32], Array[@language.SymbolMetadata]) {
  let names = Array::make(count, "")
  let public_symbols = Array::make(count, 0)
  let metadata : Array[@language.SymbolMetadata] = Array::make(count, {
    visible: false,
    named: false,
    supertype: false,
  })
  for symbol in self.parse_table.symbols {
    let value = self.symbol_order[symbol]
    names[value] = self.str_pool.resolve(
      match self.default_aliases.get(symbol) {
        Some(alias) => alias.value
        None => self.metadata_for_symbol(symbol).0
      },
    )
    public_symbols[value] = self.symbol_order[self.symbol_map[symbol]]
    metadata[value] = match self.default_aliases.get(symbol) {
      Some(alias) => { visible: true, named: alias.is_named, supertype: false, }
      None =>
        match self.metadata_for_symbol(symbol).1 {
          Named => { visible: true, named: true, supertype: false, }
          Anonymous => { visible: true, named: false, supertype: false, }
          Hidden =>
            {
              visible: false,
              named: true,
              supertype: self.syntax_grammar.supertype_symbols.contains(symbol),
            }
          Auxiliary => { visible: false, named: false, supertype: false, }
        }
    }
  }
  for i, alias in self.unique_aliases {
    let value = self.parse_table.symbols.length() + i
    names[value] = self.str_pool.resolve(alias.value)
    public_symbols[value] = value
    metadata[value] = {
      visible: true,
      named: alias.is_named,
      supertype: false,
    }
  }
  (names, public_symbols, metadata)
}

///|
/// `add_non_terminal_alias_map`.
fn Generator::non_terminal_alias_map(
  self : Generator,
  value_of_ident : Map[String, Int32],
) -> Array[(Int32, Int32, Array[Int32])] {
  // Upstream `FxHashMap`, sorted by symbol before use.
  let alias_ids_by_symbol : Map[Symbol, Array[String]] = Map([])
  // Include appended productions, where inlining can copy an alias onto
  // the symbols that replace the inlined step.
  for step in self.syntax_grammar.steps {
    if step.alias is Some(alias) &&
      step.symbol.kind is NonTerminal &&
      Some(alias) != self.default_aliases.get(step.symbol) &&
      self.symbol_ids.contains(step.symbol) &&
      self.alias_ids.get(alias) is Some(alias_id) {
      let alias_ids = match alias_ids_by_symbol.get(step.symbol) {
        Some(ids) => ids
        None => {
          let ids = []
          alias_ids_by_symbol[step.symbol] = ids
          ids
        }
      }
      if Generator::insertion_point(alias_ids, id => {
          Generator::compare_strs(id, alias_id)
        })
        is Some(i) {
        alias_ids.insert(i, alias_id)
      }
    }
  }
  let entries = alias_ids_by_symbol.to_array()
  // Upstream `sort_unstable_by_key` on distinct symbols.
  stable_sort_by(entries, (a, b) => a.0.compare(b.0))
  entries.map(entry => {
    let (symbol, alias_ids) = entry
    (
      self.symbol_order[symbol],
      self.symbol_order[self.symbol_map[symbol]],
      alias_ids.map(id => value_of_ident[id]),
    )
  })
}

///|
/// `add_primary_state_id_list`: the "primary state" for every state in the
/// grammar, the first encountered state with the same `core_id`.
fn Generator::primary_state_ids(self : Generator) -> Array[Int32] {
  let first_state_for_each_core_id : Map[Int32, Int32] = Map([])
  let result = []
  for idx, state in self.parse_table.states {
    let primary_state = match first_state_for_each_core_id.get(state.core_id) {
      Some(primary) => primary
      None => {
        first_state_for_each_core_id[state.core_id] = idx
        idx
      }
    }
    result.push(primary_state)
  }
  result
}

///|
/// `add_field_sequences`: the field map slice of each production and the
/// non-empty rows of `ts_field_map_entries`.
fn Generator::field_sequences(
  self : Generator,
) -> (Array[@language.MapSlice], Array[(Int32, Array[@language.FieldMapEntry])]) {
  if self.field_names.is_empty() {
    return ([], [])
  }
  let flat_field_maps : Array[(Int32, Array[(StrId, FieldLocation)])] = []
  let next_flat_field_map_index = Ref(0)
  ignore(
    Generator::get_field_map_id([], flat_field_maps, next_flat_field_map_index),
  )
  let field_map_ids = []
  for production_info in self.parse_table.production_infos {
    if production_info.field_map.is_empty() {
      field_map_ids.push((0, 0))
    } else {
      let flat_field_map = []
      for entry in production_info.field_map.iter() {
        let (field_name, locations) = entry
        for location in locations {
          flat_field_map.push((field_name, location))
        }
      }
      stable_sort_by(flat_field_map, (a, b) => {
        Generator::compare_strs(
          self.str_pool.resolve(a.0),
          self.str_pool.resolve(b.0),
        )
      })
      let field_map_len = flat_field_map.length()
      field_map_ids.push(
        (
          Generator::get_field_map_id(
            flat_field_map, flat_field_maps, next_flat_field_map_index,
          ),
          field_map_len,
        ),
      )
    }
  }
  let slices : Array[@language.MapSlice] = field_map_ids.map(id => {
    index: id.0,
    length: id.1,
  })
  let rows = []
  for i, row in flat_field_maps {
    if i == 0 {
      continue
    }
    let (row_index, field_pairs) = row
    rows.push(
      (
        row_index,
        field_pairs.map(pair => {
          let (field_name, location) = pair
          let entry : @language.FieldMapEntry = {
            field_id: self.field_names.search(field_name).unwrap() + 1,
            child_index: location.index,
            inherited: location.inherited,
          }
          entry
        }),
      ),
    )
  }
  (slices, rows)
}

///|
fn Generator::get_field_map_id(
  flat_field_map : Array[(StrId, FieldLocation)],
  flat_field_maps : Array[(Int32, Array[(StrId, FieldLocation)])],
  next_flat_field_map_index : Ref[Int32],
) -> Int32 {
  for entry in flat_field_maps {
    if entry.1 == flat_field_map {
      return entry.0
    }
  }
  let result = next_flat_field_map_index.val
  next_flat_field_map_index.val += flat_field_map.length()
  flat_field_maps.push((result, flat_field_map))
  result
}

///|
/// `add_supertype_map`: each supertype with its subtypes, both ordered by C
/// identifier as upstream's `BTreeMap<String, _>`/`BTreeSet<String>`.
fn Generator::supertype_rows(
  self : Generator,
  value_of_ident : Map[String, Int32],
) -> Array[(Int32, Array[Int32])] {
  self.supertype_map.map(entry => {
    let (supertype, subtypes) = entry
    let idents : Array[String] = []
    for subtype in subtypes {
      match subtype {
        Normal(symbol) =>
          if self.symbol_ids.get(symbol) is Some(id) {
            idents.push(id)
          }
        Aliased(alias) =>
          match self.alias_ids.get(alias) {
            Some(id) => idents.push(id)
            None =>
              for symbol in self.symbols_for_alias(alias) {
                if self.symbol_ids.get(symbol) is Some(id) {
                  idents.push(id)
                }
              }
          }
      }
    }
    stable_sort_by(idents, Generator::compare_strs)
    dedup(idents)
    (value_of_ident[supertype], idents.map(id => value_of_ident[id]))
  })
}

///|
/// `add_lex_modes`.
fn Generator::lex_modes(self : Generator) -> Array[@language.LexMode?] {
  let result : Array[@language.LexMode?] = []
  for i, state in self.parse_table.states {
    if state.is_end_of_non_terminal_extra() {
      result.push(None)
    } else {
      result.push(
        Some({
          lex_state: state.lex_state_id,
          external_lex_state: state.external_lex_state_id,
          reserved_word_set_id: if self.abi_version >=
            abi_version_with_reserved_words {
            self.reserved_word_set_ids_by_parse_state[i]
          } else {
            0
          },
        }),
      )
    }
  }
  result
}

///|
/// `add_external_scanner_symbol_map`.
fn Generator::external_scanner_symbol_map(self : Generator) -> Array[Int32] {
  Array::makei(self.syntax_grammar.external_tokens.length(), i => {
    let token = self.syntax_grammar.external_tokens[i]
    let id_token = token.corresponding_internal_token.unwrap_or(
      Symbol::external(i),
    )
    self.symbol_value(id_token)
  })
}

///|
/// `add_parse_table`: the action lists, large states and small states.
fn Generator::parse_tables(
  self : Generator,
) -> (
  Array[ParseActionList],
  Array[LargeStateRow],
  Array[Array[SmallStateGroup]],
  Array[Int32],
) raise RenderError {
  // Upstream `FxHashMap`, sorted by index before use.
  let parse_table_entries : Map[ActionListId, Int32] = Map([])
  let next_parse_action_list_index = Ref(0)

  // Parse action lists zero is for the default value, when a symbol is not valid.
  // `canonicalize` guarantees pool index 0 is the empty list.
  ignore(
    self.get_parse_action_list_id(
      ActionListId::new(0, false),
      parse_table_entries,
      next_parse_action_list_index,
    ),
  )
  let large_states = []
  for i, state in self.parse_table.states {
    if i >= self.large_state_count {
      break
    }
    // Ensure the entries are in a deterministic order, since they are
    // internally represented as a hash map.
    let terminal_entries = state.terminal_entries.items().copy()
    let nonterminal_entries = state.nonterminal_entries.items().copy()
    stable_sort_by(terminal_entries, (a, b) => {
      Generator::compare_options(
        self.symbol_order.get(a.0),
        self.symbol_order.get(b.0),
      )
    })
    stable_sort_by(nonterminal_entries, (a, b) => a.0.compare(b.0))
    let nonterminals = nonterminal_entries.map(entry => {
      let (symbol, action) = entry
      (
        self.symbol_value(symbol),
        match action {
          Goto(state) => state
          ShiftExtra => i
        },
      )
    })
    let terminals = terminal_entries.map(entry => {
      let (symbol, id) = entry
      let entry_id = self.get_parse_action_list_id(
        id, parse_table_entries, next_parse_action_list_index,
      )
      (self.symbol_value(symbol), entry_id)
    })
    large_states.push({ nonterminals, terminals, })
  }
  let small_states = []
  let small_state_indices = []
  if self.large_state_count < self.parse_table.states.length() {
    let mut next_table_index = 0
    for state_index in self.large_state_count..<self.parse_table.states.length() {
      let state = self.parse_table.states[state_index]
      small_state_indices.push(next_table_index)
      // Upstream `FxHashMap<(u32, SymbolType), Vec<Symbol>>`, sorted below.
      let symbols_by_value : Map[(Int32, SymbolType), Array[Symbol]] = Map([])
      let terminal_entries = state.terminal_entries.items().copy()
      stable_sort_by(terminal_entries, (a, b) => {
        Generator::compare_options(
          self.symbol_order.get(a.0),
          self.symbol_order.get(b.0),
        )
      })

      // In a given parse state, many lookahead symbols have the same actions.
      // So in the "small state" representation, group symbols by their action
      // in order to avoid repeating the action.
      for entry in terminal_entries {
        let (symbol, id) = entry
        let entry_id = self.get_parse_action_list_id(
          id, parse_table_entries, next_parse_action_list_index,
        )
        Generator::push_grouped(symbols_by_value, (entry_id, Terminal), symbol)
      }
      for entry in state.nonterminal_entries.items() {
        let (symbol, action) = entry
        let state_id = match action {
          Goto(i) => i
          ShiftExtra =>
            self.large_state_count + small_state_indices.length() - 1
        }
        Generator::push_grouped(
          symbols_by_value,
          (state_id, NonTerminal),
          symbol,
        )
      }
      let values_with_symbols = symbols_by_value.to_array()
      // Upstream `sort_unstable_by_key` on distinct `(value, kind)` keys.
      stable_sort_by(values_with_symbols, (a, b) => {
        let ((a_value, a_kind), a_symbols) = a
        let ((b_value, b_kind), b_symbols) = b
        let c = a_symbols.length().compare(b_symbols.length())
        if c != 0 {
          return c
        }
        let c = a_kind.compare(b_kind)
        if c != 0 {
          return c
        }
        let c = a_value.compare(b_value)
        if c != 0 {
          return c
        }
        a_symbols[0].compare(b_symbols[0])
      })
      next_table_index += 1
      let groups = []
      for entry in values_with_symbols {
        let ((value, kind), symbols) = entry
        next_table_index += 2 + symbols.length()
        // Upstream `sort_unstable` on distinct symbols.
        symbols.mut_view().stable_sort()
        groups.push({
          value,
          is_state: kind is NonTerminal,
          symbols: symbols.map(symbol => self.symbol_value(symbol)),
        })
      }
      small_states.push(groups)
    }
  }
  if next_parse_action_list_index.val >= 65535 {
    raise ParseTable(next_parse_action_list_index.val)
  }
  let entries = parse_table_entries.to_array()
  stable_sort_by(entries, (a, b) => a.1.compare(b.1))
  let parse_actions = entries.map(entry => {
    let (id, index) = entry
    {
      index,
      reusable: id.reusable,
      actions: self.parse_table.action_lists
      .get(id)
      .map(action => self.parse_action_entry(action)),
    }
  })
  (parse_actions, large_states, small_states, small_state_indices)
}

///|
fn Generator::push_grouped(
  groups : Map[(Int32, SymbolType), Array[Symbol]],
  key : (Int32, SymbolType),
  symbol : Symbol,
) -> Unit {
  match groups.get(key) {
    Some(symbols) => symbols.push(symbol)
    None => groups[key] = [symbol]
  }
}

///|
fn Generator::parse_action_entry(
  self : Generator,
  action : ParseAction,
) -> @language.ParseActionEntry {
  match action {
    Accept => Accept
    Recover => Recover
    ShiftExtra => Shift(state=0, extra=true, repetition=false)
    Shift(state~, is_repetition~) =>
      Shift(state~, extra=false, repetition=is_repetition)
    Reduce(symbol~, child_count~, dynamic_precedence~, production_id~) =>
      Reduce(
        symbol=self.symbol_value(symbol),
        child_count~,
        dynamic_precedence~,
        production_id~,
      )
  }
}

///|
fn Generator::get_parse_action_list_id(
  self : Generator,
  id : ActionListId,
  parse_action_list_offsets : Map[ActionListId, Int32],
  next_parse_action_list_index : Ref[Int32],
) -> Int32 {
  match parse_action_list_offsets.get(id) {
    Some(index) => index
    None => {
      let result = next_parse_action_list_index.val
      parse_action_list_offsets[id] = result
      next_parse_action_list_index.val += 1 +
        self.parse_table.action_lists.get(id).length()
      result
    }
  }
}

///|
/// Rust's `Option<usize>` ordering: `None` first.
fn Generator::compare_options(a : Int32?, b : Int32?) -> Int32 {
  match (a, b) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) => x.compare(y)
  }
}
