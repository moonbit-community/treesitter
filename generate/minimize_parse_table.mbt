// Port of tree-sitter crates/generate/src/build_tables/minimize_parse_table.rs.

// A `SymbolKey` is a symbol's position from `SymbolIndexer::index`. Positions follow
// `Symbol`'s order, so keys sort like their symbols. Keys are plain `Int`s here.

///|
/// A sorted list for each parse state, all in one buffer. Every list item is a
/// pair of `Int`s: a key (which the list is sorted by) and a value, kept in two
/// parallel arrays.
priv struct StateLists {
  keys : FixedArray[Int32]
  values : FixedArray[Int32]
  /// Where each state's list starts, by state id, then where the last one ends.
  /// State `i`'s list is `keys[starts[i]..starts[i + 1]]` (and the same of `values`).
  starts : FixedArray[Int32]
}

///|
/// Builds `StateLists`: one list per state, in state order.
priv struct StateListsBuilder {
  /// Each item, with its key in the upper half and its value in the lower half,
  /// so that sorting sorts by key.
  packed : Array[Int64]
  starts : Array[Int32]
}

///|
fn StateListsBuilder::new(state_count : Int32) -> StateListsBuilder {
  let starts = Array(capacity=state_count + 1)
  starts.push(0)
  { packed: [], starts, }
}

///|
/// Adds an item to the current state's list.
fn StateListsBuilder::push(
  self : StateListsBuilder,
  key : Int32,
  value : Int32,
) -> Unit {
  self.packed.push((key.to_int64() << 32) | (value.to_int64() & 0xFFFFFFFFL))
}

///|
/// Ends the current state's list, sorting it by key. Keys are distinct within a
/// list, so the sort is total.
fn StateListsBuilder::end_list(self : StateListsBuilder) -> Unit {
  let start = self.starts[self.starts.length() - 1]
  self.packed.mut_view(start~).sort()
  self.starts.push(self.packed.length())
}

///|
fn StateListsBuilder::finish(self : StateListsBuilder) -> StateLists {
  {
    keys: FixedArray::makei(self.packed.length(), i => {
      (self.packed[i] >> 32).to_int()
    }),
    values: FixedArray::makei(self.packed.length(), i => self.packed[i].to_int()),
    starts: FixedArray::from_array(self.starts),
  }
}

///|
/// Where the list of the state with this id starts.
fn StateLists::start(self : StateLists, id : Int32) -> Int32 {
  self.starts[id]
}

///|
/// Where the list of the state with this id ends.
fn StateLists::end(self : StateLists, id : Int32) -> Int32 {
  self.starts[id + 1]
}

///|
/// The position of `key` in the list of the state with this id, or `-1`.
fn StateLists::find(self : StateLists, id : Int32, key : Int32) -> Int32 {
  let mut low = self.starts[id]
  let mut high = self.starts[id + 1]
  while low < high {
    let mid = low + (high - low) / 2
    let k = self.keys[mid]
    if k < key {
      low = mid + 1
    } else if k > key {
      high = mid
    } else {
      return mid
    }
  }
  -1
}

///|
fn minimize_parse_table(
  parse_table : ParseTable,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  simple_aliases : AliasMap,
  token_conflict_map : TokenConflictMap,
  keywords : TokenSet,
  str_pool : StrPool,
  optimizations : OptLevel,
) -> Unit {
  let minimizer = Minimizer::{
    parse_table,
    syntax_grammar,
    lexical_grammar,
    indexer: SymbolIndexer::new(syntax_grammar, lexical_grammar),
    token_conflict_map,
    keywords,
    simple_aliases,
    str_pool,
  }
  if optimizations.merge_states {
    minimizer.merge_compatible_states()
  }
  minimizer.remove_unit_reductions()
  minimizer.remove_unused_states()
  minimizer.reorder_states_by_descending_size()
}

///|
/// Word-aligned bitsets precomputed for `token_conflicts`, all indexed by terminal
/// index. `state_terminals` and `conflict_rows` are flattened two dimensional vectors:
/// row `i` spans `[i * row_words, (i + 1) * row_words)`.
priv struct ConflictBits {
  row_words : Int32
  /// Per state: which terminals have entries
  state_terminals : FixedArray[UInt64]
  /// Per token: which terminals it lexically conflicts with
  conflict_rows : FixedArray[UInt64]
  /// The keyword set.
  keywords : FixedArray[UInt64]
  /// Tokens that are also external tokens.
  internal_external : FixedArray[UInt64]
  /// The grammar's word token, as a key and as its bit in a row, if it's a terminal. An
  /// external word token has no keywords (see `identify_keywords`).
  word_token : (Int32, Int32)?
}

///|
fn bit_is_set(bits : FixedArray[UInt64], index : Int32) -> Bool {
  (bits[index / 64] & (1UL << (index % 64))) != 0
}

///|
fn ConflictBits::new(minimizer : Minimizer) -> ConflictBits {
  // Precompute word-aligned bitsets so `token_conflicts` can test a candidate
  // token against a whole state's terminals.
  //   - per state: which terminal indices have entries
  //   - per token: which terminal indices it lexically conflicts with
  //   - the keyword set as bits
  let n_terminals = minimizer.lexical_grammar.variables.length()
  let row_words = (n_terminals + 63) / 64
  let state_terminals : FixedArray[UInt64] = FixedArray::make(
    minimizer.parse_table.states.length() * row_words,
    0,
  )
  for s, state in minimizer.parse_table.states {
    let base = s * row_words
    for k in 0..<state.terminal_entries.len() {
      if state.terminal_entries.symbol_at(k).terminal_index() is Some(index) {
        set_bit(state_terminals, base * 64 + index)
      }
    }
  }
  let conflict_rows : FixedArray[UInt64] = FixedArray::make(
    n_terminals * row_words,
    0,
  )
  for i in 0..<n_terminals {
    let base = i * row_words
    for j in 0..<n_terminals {
      if minimizer.token_conflict_map.does_conflict(i, j) {
        set_bit(conflict_rows, base * 64 + j)
      }
    }
  }
  let keywords : FixedArray[UInt64] = FixedArray::make(row_words, 0)
  for symbol in minimizer.keywords.iter() {
    if symbol.terminal_index() is Some(index) {
      set_bit(keywords, index)
    }
  }
  let internal_external : FixedArray[UInt64] = FixedArray::make(row_words, 0)
  for external in minimizer.syntax_grammar.external_tokens {
    if external.corresponding_internal_token is Some(token) &&
      token.terminal_index() is Some(index) {
      set_bit(internal_external, index)
    }
  }
  {
    row_words,
    state_terminals,
    conflict_rows,
    keywords,
    internal_external,
    word_token: match minimizer.syntax_grammar.word_token {
      Some(word) =>
        match word.terminal_index() {
          Some(index) => Some((minimizer.indexer.index(word), index))
          None => None
        }
      None => None
    },
  }
}

///|
fn ConflictBits::conflict_row_word(
  self : ConflictBits,
  token : Int32,
  w : Int32,
) -> UInt64 {
  self.conflict_rows[token * self.row_words + w]
}

///|
fn ConflictBits::state_row_word(
  self : ConflictBits,
  state : Int32,
  w : Int32,
) -> UInt64 {
  self.state_terminals[state * self.row_words + w]
}

///|
/// The first pass of `Minimizer::merge_compatible_states`: splits states whose terminal
/// entries can't be merged.
priv struct ConflictPass {
  minimizer : Minimizer
  /// Each state's terminal entries, sorted by symbol: keys, and the index of each
  /// entry's action list.
  entry_maps : StateLists
  bits : ConflictBits
  /// A hash of each state's reserved words and terminal entries, apart from its shift
  /// targets, whose groups change as groups split.
  static_signatures : Array[Int32]
  /// Each state's shift targets, sorted by symbol.
  shift_maps : StateLists
  /// Scratch for `compatible_with_all`.
  kept : KeptStates
}

///|
fn ConflictPass::new(
  minimizer : Minimizer,
  shift_maps : StateLists,
) -> ConflictPass {
  // Precompute sorted terminal entry references for merge-join in states_conflict.
  // Keys are symbol positions for easy comparison.
  let states = minimizer.parse_table.states
  let builder = StateListsBuilder::new(states.length())
  for state in states {
    for k in 0..<state.terminal_entries.len() {
      builder.push(minimizer.indexer.index(state.terminal_entries.symbol_at(k)), state.terminal_entries.value_at(k).index)
    }
    builder.end_list()
  }
  let entry_maps = builder.finish()

  // Hash each state's terminal entries once, apart from its shift targets, whose groups
  // change as groups split.
  // (Of the reserved words, only their count is hashed: a signature may leave out
  // some of what `equivalent` compares.)
  let static_signatures = states.map(state => {
    let mut acc = hash_mix(HASH_SEED, state.reserved_words.len())
    for i in entry_maps.start(state.id)..<entry_maps.end(state.id) {
      acc = hash_mix(acc, entry_maps.keys[i])
      for
        action in minimizer.parse_table.action_lists.get_index(
          entry_maps.values[i],
        ) {
        acc = match action {
          Shift(is_repetition~, ..) =>
            hash_mix(acc, if is_repetition { 1 } else { 0 })
          action => parse_action_hash_mix(acc, action)
        }
      }
    }
    hash_finish(acc)
  })
  {
    minimizer,
    entry_maps,
    bits: ConflictBits::new(minimizer),
    static_signatures,
    shift_maps,
    kept: KeptStates::new(minimizer.indexer),
  }
}

///|
/// Whether the state has an entry for `key`.
fn ConflictPass::has_token(
  self : ConflictPass,
  state : ParseState,
  key : Int32,
) -> Bool {
  let index = self.minimizer.indexer.terminal_index_of(key)
  if index >= 0 {
    (self.bits.state_row_word(state.id, index / 64) & (1UL << (index % 64))) !=
    0
  } else {
    self.entry_maps.find(state.id, key) >= 0
  }
}

///|
/// Whether `key` can be added to `target`, or `target` already has it.
fn ConflictPass::can_take(
  self : ConflictPass,
  target : ParseState,
  key : Int32,
) -> Bool {
  self.has_token(target, key) ||
  self.minimizer.token_conflicts(target, self.bits, key) is None
}

///|
/// `compatible_with_all`, with the kept states merged into `kept_states`.
fn ConflictPass::compatible_with_merged(
  self : ConflictPass,
  kept_states : KeptStates,
  state : ParseState,
  kept : ArrayView[Int32],
  group_ids_by_state_id : Array[Int32],
) -> Bool {
  let states = self.minimizer.parse_table.states
  let entry_maps = self.entry_maps
  for i in entry_maps.start(state.id)..<entry_maps.end(state.id) {
    let key = entry_maps.keys[i]
    let action_list = entry_maps.values[i]
    let token = kept_states.tokens[key]
    if token.action_list >= 0 &&
      self.minimizer.entries_conflict(
        token.action_list,
        action_list,
        group_ids_by_state_id,
      )
      is Some(_) {
      return false
    }
    if token.count < kept.length() &&
      !kept_states.addable_to_all(key, kept, kept_id => {
        self.can_take(states[kept_id], key)
      }) {
      return false
    }
  }
  for key in kept_states.merged_tokens {
    if !self.can_take(state, key) {
      return false
    }
  }
  true
}

///|
/// What the states kept so far in a group of the conflict pass have in common, to check a state
/// against all of them at once. Kept states never need to be split from each other, so any two
/// agree on every token they share, and one entry per token stands for all of them.
priv struct KeptStates {
  /// What the merged states have for each token, by `SymbolIndexer::index`.
  tokens : Array[KeptToken]
  /// How many of the kept states are merged into `tokens`.
  mut merged_count : Int32
  /// The tokens that some merged state has.
  merged_tokens : Array[Int32]
  /// The tokens that have been checked against kept states lacking them.
  checked_tokens : Array[Int32]
}

///|
/// What the kept states have for a token. See `KeptStates`.
priv struct KeptToken {
  /// The index of the action list of the first merged state with this token, or
  /// `-1`.
  mut action_list : Int32
  /// How many merged states have this token.
  mut count : Int32
  /// Whether this token can be added to the kept states that lack it, as far as
  /// they've been checked, in order: to each of the first this many kept
  /// states (upstream's `Addable::UpTo`), or not to one of them (`-1`,
  /// upstream's `Addable::Blocked`).
  mut addable : Int32
}

///|
fn KeptToken::default() -> KeptToken {
  { action_list: -1, count: 0, addable: 0, }
}

///|
fn KeptToken::reset(self : KeptToken) -> Unit {
  self.action_list = -1
  self.count = 0
  self.addable = 0
}

///|
fn KeptStates::new(indexer : SymbolIndexer) -> KeptStates {
  {
    tokens: Array::makei(indexer.token_count(), _ => KeptToken::default()),
    merged_count: 0,
    merged_tokens: [],
    checked_tokens: [],
  }
}

///|
/// Forgets the kept states, for the next group.
fn KeptStates::clear(self : KeptStates) -> Unit {
  for key in self.merged_tokens {
    self.tokens[key].reset()
  }
  for key in self.checked_tokens {
    self.tokens[key].reset()
  }
  self.merged_tokens.clear()
  self.checked_tokens.clear()
  self.merged_count = 0
}

///|
/// Merges the entries of the kept states that aren't merged yet.
fn KeptStates::merge(
  self : KeptStates,
  kept : ArrayView[Int32],
  entry_maps : StateLists,
) -> Unit {
  for i in self.merged_count..<kept.length() {
    let state_id = kept[i]
    for j in entry_maps.start(state_id)..<entry_maps.end(state_id) {
      let key = entry_maps.keys[j]
      let token = self.tokens[key]
      if token.action_list < 0 {
        token.action_list = entry_maps.values[j]
        self.merged_tokens.push(key)
      }
      token.count += 1
    }
  }
  self.merged_count = kept.length()
}

///|
/// Whether `key` can be added to every kept state that lacks it, asking `can_take` about
/// each kept state at most once per group: the answer doesn't depend on the state being
/// checked.
fn KeptStates::addable_to_all(
  self : KeptStates,
  key : Int32,
  kept : ArrayView[Int32],
  can_take : (Int32) -> Bool,
) -> Bool {
  let token = self.tokens[key]
  let checked = token.addable
  if checked < 0 {
    return false
  }
  if checked == 0 {
    self.checked_tokens.push(key)
  }
  for i in checked..<kept.length() {
    if !can_take(kept[i]) {
      token.addable = -1
      return false
    }
  }
  token.addable = kept.length()
  true
}

///|
fn ConflictPass::criterion(self : ConflictPass) -> SplitCriterion[ParseState] {
  {
    should_split: (left, right, group_ids_by_state_id) => {
      self.minimizer.states_conflict(
        left,
        right,
        group_ids_by_state_id,
        self.entry_maps,
        self.bits,
      )
    },
    signature: (state, group_ids_by_state_id) => {
      let shift_maps = self.shift_maps
      let mut acc = hash_mix(HASH_SEED, self.static_signatures[state.id])
      for i in shift_maps.start(state.id)..<shift_maps.end(state.id) {
        acc = hash_mix(acc, group_ids_by_state_id[shift_maps.values[i]])
      }
      Some(hash_finish(acc))
    },
    // Whether two states have the same reserved words and terminal entries, with shift
    // targets compared by group. Then `Minimizer::states_conflict` never separates them,
    // and separates either from exactly the same states.
    equivalent: (left, right, group_ids_by_state_id) => {
      let entry_maps = self.entry_maps
      let start1 = entry_maps.start(left.id)
      let start2 = entry_maps.start(right.id)
      let len = entry_maps.end(left.id) - start1
      let action_lists = self.minimizer.parse_table.action_lists
      if left.reserved_words != right.reserved_words ||
        len != entry_maps.end(right.id) - start2 {
        return false
      }
      for i in 0..<len {
        if entry_maps.keys[start1 + i] != entry_maps.keys[start2 + i] {
          return false
        }
        let id1 = entry_maps.values[start1 + i]
        let id2 = entry_maps.values[start2 + i]
        if id1 == id2 {
          continue
        }
        let actions1 = action_lists.get_index(id1)
        let actions2 = action_lists.get_index(id2)
        if actions1.length() != actions2.length() {
          return false
        }
        for k in 0..<actions1.length() {
          let same = match (actions1[k], actions2[k]) {
            (
              Shift(state=s1, is_repetition=is_repetition1),
              Shift(state=s2, is_repetition=is_repetition2),
            ) =>
              group_ids_by_state_id[s1] == group_ids_by_state_id[s2] &&
              is_repetition1 == is_repetition2
            (action1, action2) => action1 == action2
          }
          if !same {
            return false
          }
        }
      }
      true
    },
    start_group: () => self.kept.clear(),
    // Checks `state` against what the kept states have in common, which covers everything
    // `Minimizer::states_conflict` compares:
    // - the tokens `state` shares with kept states, whose entries all agree.
    // - `state`'s tokens that some kept state lacks, which must be addable to it.
    // - the kept states' tokens that `state` lacks, which must be addable to `state`.
    compatible_with_all: (state, kept, group_ids_by_state_id) => {
      self.kept.merge(kept, self.entry_maps)
      self.compatible_with_merged(self.kept, state, kept, group_ids_by_state_id)
    },
  }
}

///|
/// The second pass of `Minimizer::merge_compatible_states`, repeated until nothing splits:
/// splits states whose successors are in different groups.
priv struct SuccessorPass {
  minimizer : Minimizer
  /// Each state's shift targets, sorted by symbol.
  shift_maps : StateLists
  /// Each state's nonterminal entries, sorted by symbol: nonterminal indices, and each
  /// entry's `Goto` target, or `-1` for `ShiftExtra`.
  nonterminal_maps : StateLists
}

///|
fn SuccessorPass::new(
  minimizer : Minimizer,
  shift_maps : StateLists,
) -> SuccessorPass {
  // Store only the symbol index: all nonterminal entries share the same kind,
  // so index alone is sufficient for sorting and comparison.
  let states = minimizer.parse_table.states
  let builder = StateListsBuilder::new(states.length())
  for state in states {
    for k in 0..<state.nonterminal_entries.len() {
      builder.push(
        state.nonterminal_entries.symbol_at(k).non_terminal_index().unwrap(),
        match state.nonterminal_entries.value_at(k) {
          Goto(successor) => successor
          ShiftExtra => -1
        },
      )
    }
    builder.end_list()
  }
  { minimizer, shift_maps, nonterminal_maps: builder.finish(), }
}

///|
fn SuccessorPass::criterion(self : SuccessorPass) -> SplitCriterion[ParseState] {
  {
    should_split: (left, right, group_ids_by_state_id) => {
      self.minimizer.state_successors_differ(
        left,
        right,
        group_ids_by_state_id,
        self.shift_maps,
        self.nonterminal_maps,
      )
    },
    signature: (state, group_ids_by_state_id) => {
      let shift_maps = self.shift_maps
      let nonterminal_maps = self.nonterminal_maps
      let mut acc = HASH_SEED
      for i in shift_maps.start(state.id)..<shift_maps.end(state.id) {
        acc = hash_mix(acc, shift_maps.keys[i])
        acc = hash_mix(acc, group_ids_by_state_id[shift_maps.values[i]])
      }
      for i in nonterminal_maps.start(state.id)..<nonterminal_maps.end(state.id) {
        acc = hash_mix(acc, nonterminal_maps.keys[i])
        let successor = nonterminal_maps.values[i]
        acc = if successor >= 0 {
          hash_mix(hash_mix(acc, 1), group_ids_by_state_id[successor])
        } else {
          hash_mix(acc, 0)
        }
      }
      Some(hash_finish(acc))
    },
    // Whether two states shift and go to on the same symbols, with successors in the same
    // groups. Then `Minimizer::state_successors_differ` never separates them, and separates
    // either from exactly the same states.
    equivalent: (left, right, group_ids_by_state_id) => {
      let shift_maps = self.shift_maps
      let nonterminal_maps = self.nonterminal_maps
      let shifts1 = shift_maps.start(left.id)
      let shifts2 = shift_maps.start(right.id)
      let shift_count = shift_maps.end(left.id) - shifts1
      let gotos1 = nonterminal_maps.start(left.id)
      let gotos2 = nonterminal_maps.start(right.id)
      let goto_count = nonterminal_maps.end(left.id) - gotos1
      if shift_count != shift_maps.end(right.id) - shifts2 ||
        goto_count != nonterminal_maps.end(right.id) - gotos2 {
        return false
      }
      for i in 0..<shift_count {
        if shift_maps.keys[shifts1 + i] != shift_maps.keys[shifts2 + i] ||
          group_ids_by_state_id[shift_maps.values[shifts1 + i]] !=
          group_ids_by_state_id[shift_maps.values[shifts2 + i]] {
          return false
        }
      }
      for i in 0..<goto_count {
        if nonterminal_maps.keys[gotos1 + i] !=
          nonterminal_maps.keys[gotos2 + i] {
          return false
        }
        let s1 = nonterminal_maps.values[gotos1 + i]
        let s2 = nonterminal_maps.values[gotos2 + i]
        let same = if s1 >= 0 && s2 >= 0 {
          group_ids_by_state_id[s1] == group_ids_by_state_id[s2]
        } else {
          s1 < 0 && s2 < 0
        }
        if !same {
          return false
        }
      }
      true
    },
    start_group: () => (),
    compatible_with_all: (_, _, _) => false,
  }
}

///|
/// Why two states can't be merged: either their entries for a token differ, or a token that
/// only one of them has can't be added to the other. (Upstream only reads the
/// variants to log them at debug level.)
#warnings("-unused_constructor")
priv enum Conflict {
  /// Their entries have different numbers of actions.
  ActionCounts
  /// Their entries shift to these states, which are in different groups.
  SplitSuccessors(Int32, Int32)
  /// Their entries have different actions.
  UnequalActions
  /// The token ends a non-terminal extra.
  EndOfNonTerminalExtra
  /// The token is external, so it could conflict lexically with any of the other state's.
  ExternalToken
  /// The token is both internal and external.
  InternalExternalToken
  /// The token conflicts lexically with this terminal, which the other state has.
  Lexical(Int32)
}

///|
#warnings("-unused_field")
priv struct Minimizer {
  parse_table : ParseTable
  syntax_grammar : SyntaxGrammar
  lexical_grammar : LexicalGrammar
  /// Gives each symbol its key.
  indexer : SymbolIndexer
  token_conflict_map : TokenConflictMap
  keywords : TokenSet
  simple_aliases : AliasMap
  str_pool : StrPool
}

///|
fn Minimizer::remove_unit_reductions(self : Minimizer) -> Unit {
  let aliased_symbols : Map[Symbol, Unit] = Map([])
  // Include appended productions, where inlining can copy an alias onto
  // the symbols that replace the inlined step.
  for step in self.syntax_grammar.steps {
    if step.alias is Some(_) {
      aliased_symbols[step.symbol] = ()
    }
  }
  let unit_reduction_symbols_by_state : Map[Int32, Symbol] = Map([])
  for i, state in self.parse_table.states {
    if state.has_eof_gated_reduce {
      continue
    }
    let mut only_unit_reductions = true
    let mut unit_reduction_symbol : Symbol? = None
    for k in 0..<state.terminal_entries.len() {
      for action in self.parse_table.action_lists.get(state.terminal_entries.value_at(k)) {
        match action {
          ShiftExtra => continue
          Reduce(child_count=1, production_id=0, symbol~, ..) if !self.simple_aliases.contains(
              symbol,
            ) &&
            !self.syntax_grammar.supertype_symbols.contains(symbol) &&
            !self.syntax_grammar.extra_symbols.contains(symbol) &&
            !aliased_symbols.contains(symbol) &&
            (
              symbol.non_terminal_index() is Some(index) &&
              self.syntax_grammar.variables[index].kind != Named
            ) &&
            (
              unit_reduction_symbol is None ||
              unit_reduction_symbol == Some(symbol)
            ) => {
            unit_reduction_symbol = Some(symbol)
            continue
          }
          _ => ()
        }
        only_unit_reductions = false
        break
      }
      if !only_unit_reductions {
        break
      }
    }
    if unit_reduction_symbol is Some(symbol) && only_unit_reductions {
      unit_reduction_symbols_by_state[i] = symbol
    }
  }
  if unit_reduction_symbols_by_state.is_empty() {
    return
  }
  let action_list_ids : Map[Array[ParseAction], Int32] = Map([])
  let states = self.parse_table.states
  let action_lists = self.parse_table.action_lists
  for state_index in 0..<states.length() {
    let mut done = false
    while !done {
      done = true
      let state = states[state_index]
      state.update_nonterminal_references((other_state_id, state) => {
        match unit_reduction_symbols_by_state.get(other_state_id) {
          None => other_state_id
          Some(symbol) => {
            done = false
            match state.nonterminal_entries.get(symbol) {
              Some(Goto(state_id)) => state_id
              _ => other_state_id
            }
          }
        }
      })
      for i in 0..<state.terminal_entries.len() {
        let old_id = state.terminal_entries.value_at(i)
        // The list is only copied once it changes.
        let mut actions = action_lists.get(old_id)
        let mut changed = false
        for k in 0..<actions.length() {
          // A Shift onto a unit-reduction state (one whose only action reduces a
          // single `symbol`) can skip it. Shift then reduce then goto is equivalent
          // to shifting straight to the the goto target for `symbol` in this case.
          if actions[k] is Shift(state=target, is_repetition~) &&
            unit_reduction_symbols_by_state.get(target) is Some(symbol) &&
            state.nonterminal_entries.get(symbol) is Some(Goto(new_target)) &&
            new_target != target {
            if !changed {
              actions = actions.copy()
            }
            actions[k] = Shift(state=new_target, is_repetition~)
            changed = true
            done = false
          }
        }
        if changed {
          let index = action_lists.intern(action_list_ids, actions)
          state.terminal_entries.set_value_at(
            i,
            ActionListId::new(index, old_id.reusable),
          )
        }
      }
    }
  }
}

///|
fn Minimizer::merge_compatible_states(self : Minimizer) -> Unit {
  let mut max_core_id = 0
  for state in self.parse_table.states {
    if state.core_id > max_core_id {
      max_core_id = state.core_id
    }
  }
  let core_count = 1 + max_core_id

  // Initially group the states by their parse item set core.
  let group_ids_by_state_id = Array(capacity=self.parse_table.states.length())
  let state_ids_by_group_id : Array[Array[Int32]] = Array::makei(core_count, _ => {
    []
  })
  for i, state in self.parse_table.states {
    state_ids_by_group_id[state.core_id].push(i)
    group_ids_by_state_id.push(state.core_id)
  }

  // Precompute per-state sorted shift actions, for both passes.
  // State actions are stable across loop iterations; only group assignments change.
  // Keys are symbol positions, for single-instruction comparison.
  let builder = StateListsBuilder::new(self.parse_table.states.length())
  for state in self.parse_table.states {
    for k in 0..<state.terminal_entries.len() {
      if self.parse_table.action_lists.get(state.terminal_entries.value_at(k)).last()
        is Some(Shift(state=s, ..)) {
        builder.push(self.indexer.index(state.terminal_entries.symbol_at(k)), s)
      }
    }
    builder.end_list()
  }
  let shift_maps = builder.finish()
  let conflict_pass = ConflictPass::new(self, shift_maps)
  ignore(
    split_state_id_groups(
      self.parse_table.states,
      state_ids_by_group_id,
      group_ids_by_state_id,
      0,
      conflict_pass.criterion(),
    ),
  )
  let successor_pass = SuccessorPass::new(self, shift_maps).criterion()
  while split_state_id_groups(
          self.parse_table.states,
          state_ids_by_group_id,
          group_ids_by_state_id,
          0,
          successor_pass,
        ) {

  }
  let error_group_index = state_ids_by_group_id
    .search_by(g => g.contains(0))
    .unwrap()
  let start_group_index = state_ids_by_group_id
    .search_by(g => g.contains(1))
    .unwrap()
  state_ids_by_group_id.swap(error_group_index, 0)
  state_ids_by_group_id.swap(start_group_index, 1)

  // Create a list of new parse states: one state for each group of old states.
  let new_states = Array(capacity=state_ids_by_group_id.length())
  // Scratch for merging: the position of each symbol's entry in the new state, by
  // `SymbolIndexer::index`.
  let positions : Array[Int32?] = Array::make(self.indexer.symbol_count(), None)
  // What upstream's `mem::take` leaves behind. The old states are never read again,
  // so one placeholder does for all of them.
  let taken = ParseState::new()
  for state_ids in state_ids_by_group_id {
    // Initialize the new state based on the first old state in the group.
    let parse_state = self.parse_table.states[state_ids[0]]
    self.parse_table.states[state_ids[0]] = taken
    set_positions(parse_state.terminal_entries, positions, self.indexer)
    set_positions(parse_state.nonterminal_entries, positions, self.indexer)

    // Extend the new state with all of the actions from the other old states
    // in the group.
    for k in 1..<state_ids.length() {
      let state_id = state_ids[k]
      let other_parse_state = self.parse_table.states[state_id]
      self.parse_table.states[state_id] = taken
      parse_state.has_eof_gated_reduce = parse_state.has_eof_gated_reduce ||
        other_parse_state.has_eof_gated_reduce
      merge_entries(
        parse_state.terminal_entries,
        other_parse_state.terminal_entries,
        positions,
        self.indexer,
      )
      merge_entries(
        parse_state.nonterminal_entries,
        other_parse_state.nonterminal_entries,
        positions,
        self.indexer,
      )
      ignore(
        parse_state.reserved_words.insert_all(other_parse_state.reserved_words),
      )
      for k in 0..<parse_state.terminal_entries.len() {
        ignore(parse_state.reserved_words.remove(parse_state.terminal_entries.symbol_at(k)))
      }
    }
    for k in 0..<parse_state.terminal_entries.len() {
      positions[self.indexer.index(parse_state.terminal_entries.symbol_at(k))] = None
    }
    for k in 0..<parse_state.nonterminal_entries.len() {
      positions[self.indexer.index(parse_state.nonterminal_entries.symbol_at(k))] = None
    }

    // Update the new state's outgoing references using the new grouping.
    parse_state.update_nonterminal_references((state_id, _) => {
      group_ids_by_state_id[state_id]
    })
    new_states.push(parse_state)
  }
  self.parse_table.states = new_states
  self.parse_table.remap_terminal_references(state_id => {
    group_ids_by_state_id[state_id]
  })
}

///|
fn Minimizer::states_conflict(
  self : Minimizer,
  state1 : ParseState,
  state2 : ParseState,
  group_ids_by_state_id : Array[Int32],
  entry_maps : StateLists,
  bits : ConflictBits,
) -> Bool {
  let mut i = entry_maps.start(state1.id)
  let end1 = entry_maps.end(state1.id)
  let mut j = entry_maps.start(state2.id)
  let end2 = entry_maps.end(state2.id)
  while i < end1 || j < end2 {
    let ord = if i < end1 && j < end2 {
      entry_maps.keys[i].compare(entry_maps.keys[j])
    } else if i < end1 {
      -1
    } else {
      1
    }
    if ord == 0 {
      if self.entries_conflict(
          entry_maps.values[i],
          entry_maps.values[j],
          group_ids_by_state_id,
        )
        is Some(_) {
        // (Upstream logs the conflict at debug level.)
        return true
      }
      i += 1
      j += 1
    } else if ord < 0 {
      if self.token_conflicts(state2, bits, entry_maps.keys[i]) is Some(_) {
        return true
      }
      i += 1
    } else {
      if self.token_conflicts(state1, bits, entry_maps.keys[j]) is Some(_) {
        return true
      }
      j += 1
    }
  }
  false
}

///|
fn Minimizer::state_successors_differ(
  _self : Minimizer,
  state1 : ParseState,
  state2 : ParseState,
  group_ids_by_state_id : Array[Int32],
  shift_maps : StateLists,
  nonterminal_maps : StateLists,
) -> Bool {
  let mut i = shift_maps.start(state1.id)
  let end1 = shift_maps.end(state1.id)
  let mut j = shift_maps.start(state2.id)
  let end2 = shift_maps.end(state2.id)
  while i < end1 && j < end2 {
    let k1 = shift_maps.keys[i]
    let k2 = shift_maps.keys[j]
    if k1 < k2 {
      i += 1
    } else if k1 > k2 {
      j += 1
    } else {
      let group1 = group_ids_by_state_id[shift_maps.values[i]]
      let group2 = group_ids_by_state_id[shift_maps.values[j]]
      if group1 != group2 {
        // (Upstream logs the split at debug level.)
        return true
      }
      i += 1
      j += 1
    }
  }
  let mut i = nonterminal_maps.start(state1.id)
  let end1 = nonterminal_maps.end(state1.id)
  let mut j = nonterminal_maps.start(state2.id)
  let end2 = nonterminal_maps.end(state2.id)
  while i < end1 && j < end2 {
    let idx1 = nonterminal_maps.keys[i]
    let idx2 = nonterminal_maps.keys[j]
    if idx1 < idx2 {
      i += 1
    } else if idx1 > idx2 {
      j += 1
    } else {
      // A `Goto` target, or `-1` for `ShiftExtra`.
      let s1 = nonterminal_maps.values[i]
      let s2 = nonterminal_maps.values[j]
      if s1 >= 0 && s2 >= 0 {
        let group1 = group_ids_by_state_id[s1]
        let group2 = group_ids_by_state_id[s2]
        if group1 != group2 {
          return true
        }
      } else if s1 >= 0 || s2 >= 0 {
        return true
      }
      i += 1
      j += 1
    }
  }
  false
}

///|
/// Why two entries for the same token can't be merged.
fn Minimizer::entries_conflict(
  self : Minimizer,
  id1 : Int32,
  id2 : Int32,
  group_ids_by_state_id : Array[Int32],
) -> Conflict? {
  // To be compatible, entries need to have the same actions.
  if id1 == id2 {
    None
  } else {
    self.action_lists_conflict(id1, id2, group_ids_by_state_id)
  }
}

///|
/// `Self::entries_conflict` for entries with different action lists.
fn Minimizer::action_lists_conflict(
  self : Minimizer,
  id1 : Int32,
  id2 : Int32,
  group_ids_by_state_id : Array[Int32],
) -> Conflict? {
  let actions1 = self.parse_table.action_lists.get_index(id1)
  let actions2 = self.parse_table.action_lists.get_index(id2)
  if actions1.length() != actions2.length() {
    return Some(ActionCounts)
  }
  for i in 0..<actions1.length() {
    let action1 = actions1[i]
    let action2 = actions2[i]
    // Two shift actions are equivalent if their destinations are in the same group.
    if (action1, action2)
      is (
        Shift(state=s1, is_repetition=is_repetition1),
        Shift(state=s2, is_repetition=is_repetition2),
      ) {
      let group1 = group_ids_by_state_id[s1]
      let group2 = group_ids_by_state_id[s2]
      if group1 == group2 && is_repetition1 == is_repetition2 {
        continue
      }
      return Some(SplitSuccessors(s1, s2))
    } else if action1 != action2 {
      return Some(UnequalActions)
    }
  }
  None
}

///|
/// Why `new_token` can't be added to `right_state`, if it can't.
fn Minimizer::token_conflicts(
  self : Minimizer,
  right_state : ParseState,
  bits : ConflictBits,
  new_token : Int32,
) -> Conflict? {
  // `self.indexer.symbol(new_token)`'s kind and index, without building the symbol.
  let terminal_index = self.indexer.terminal_index_of(new_token)
  let new_token_is_terminal = terminal_index >= 0
  // `End` uses terminal 0.
  let new_token_index = if new_token_is_terminal { terminal_index } else { 0 }
  if !new_token_is_terminal {
    match self.indexer.symbol(new_token).kind {
      EndOfNonTerminalExtra => return Some(EndOfNonTerminalExtra)
      // Do not add external tokens, as they could conflict lexically with
      // any of the state's existing lookahead tokens.
      External => return Some(ExternalToken)
      End => ()
      Terminal | NonTerminal => abort("unreachable")
    }
  }
  let is_reserved = if new_token_is_terminal {
    right_state.reserved_words.contains_terminal(new_token_index)
  } else {
    right_state.reserved_words.contains(symbol_end)
  }
  if is_reserved {
    return None
  }

  // Do not add tokens which are both internal and external. Their validity could
  // influence the behavior of the external scanner. `bits.internal_external` is
  // indexed by terminal index only.
  if new_token_is_terminal &&
    bit_is_set(bits.internal_external, new_token_index) {
    return Some(InternalExternalToken)
  }
  let new_token_is_word = match bits.word_token {
    Some((word, _)) => word == new_token
    None => false
  }
  let new_token_is_keyword = bits.word_token is Some(_) &&
    (if new_token_is_terminal {
      bit_is_set(bits.keywords, new_token_index)
    } else {
      self.keywords.contains(symbol_end)
    })
  // Do not add a token if it conflicts with an existing token. Test the candidate's
  // conflict row against the state's terminal bits, masking out the word/keyword
  // exemptions.
  for w in 0..<bits.row_words {
    let row_word = bits.conflict_row_word(new_token_index, w)
    let mut candidates = bits.state_row_word(right_state.id, w) & row_word
    if new_token_is_keyword &&
      bits.word_token is Some((_, word)) &&
      word / 64 == w {
      candidates = candidates & (1UL << (word % 64)).lnot()
    }
    if new_token_is_word {
      candidates = candidates & bits.keywords[w].lnot()
    }
    if candidates != 0 {
      return Some(Lexical(w * 64 + candidates.ctz()))
    }
  }
  None
}

///|
fn Minimizer::remove_unused_states(self : Minimizer) -> Unit {
  let state_usage_map = Array::make(self.parse_table.states.length(), false)
  state_usage_map[0] = true
  state_usage_map[1] = true
  for state in self.parse_table.states {
    for
      referenced_state in state.referenced_states(self.parse_table.action_lists) {
      state_usage_map[referenced_state] = true
    }
  }
  let mut removed_predecessor_count = 0
  let state_replacement_map = Array::make(self.parse_table.states.length(), 0)
  for state_id in 0..<self.parse_table.states.length() {
    state_replacement_map[state_id] = state_id - removed_predecessor_count
    if !state_usage_map[state_id] {
      removed_predecessor_count += 1
    }
  }
  let new_states = []
  for original_state_id, state in self.parse_table.states {
    if state_usage_map[original_state_id] {
      state.update_nonterminal_references((other_state_id, _) => {
        state_replacement_map[other_state_id]
      })
      new_states.push(state)
    }
  }
  self.parse_table.states = new_states
  self.parse_table.remap_terminal_references(state_id => {
    state_replacement_map[state_id]
  })
}

///|
fn Minimizer::reorder_states_by_descending_size(self : Minimizer) -> Unit {
  // Get a mapping of old state index -> new_state_index
  let old_ids_by_new_id = Array::makei(self.parse_table.states.length(), i => i)
  // Upstream sorts with `sort_unstable_by_key`, and states of the same size
  // tie, so this must be Rust's exact algorithm.
  rust_sort_unstable_by_key(old_ids_by_new_id, i => {
    // Don't change states 0 (the error state) or 1 (the start state).
    if i <= 1 {
      return i - 1000000
    }

    // Reorder all the other states by descending symbol count.
    let state = self.parse_table.states[i]
    -(state.terminal_entries.len() + state.nonterminal_entries.len())
  })

  // Get the inverse mapping
  let new_ids_by_old_id = Array::make(old_ids_by_new_id.length(), 0)
  for id, old_id in old_ids_by_new_id {
    new_ids_by_old_id[old_id] = id
  }

  // Reorder the parse states and update their references to reflect
  // the new ordering.
  self.parse_table.states = old_ids_by_new_id.map(old_id => {
    let state = self.parse_table.states[old_id]
    state.update_nonterminal_references((id, _) => new_ids_by_old_id[id])
    state
  })
  self.parse_table.remap_terminal_references(id => new_ids_by_old_id[id])
}

///|
/// Records the position of each of `entries`' symbols in `positions`, by
/// `SymbolIndexer::index`.
fn[V] set_positions(
  entries : ParseStateEntries[V],
  positions : Array[Int32?],
  indexer : SymbolIndexer,
) -> Unit {
  for position in 0..<entries.len() {
    positions[indexer.index(entries.symbol_at(position))] = Some(position)
  }
}

///|
/// Merges `other` into `entries` like `IndexMap::extend`: a symbol that `entries` already has
/// keeps its place and takes `other`'s value, and the rest are added in order. `positions` holds
/// the position of each of `entries`' symbols, by `SymbolIndexer::index`.
fn[V] merge_entries(
  entries : ParseStateEntries[V],
  other : ParseStateEntries[V],
  positions : Array[Int32?],
  indexer : SymbolIndexer,
) -> Unit {
  for k in 0..<other.len() {
    let symbol = other.symbol_at(k)
    let value = other.value_at(k)
    let index = indexer.index(symbol)
    match positions[index] {
      Some(position) => entries.set_value_at(position, value)
      None => {
        positions[index] = Some(entries.len())
        entries.push(symbol, value)
      }
    }
  }
}
