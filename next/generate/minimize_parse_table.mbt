// Port of tree-sitter crates/generate/src/build_tables/minimize_parse_table.rs.

// A `SymbolKey` is a symbol's position from `SymbolIndexer::index`. Positions follow
// `Symbol`'s order, so keys sort like their symbols. Keys are plain `Int`s here.

///|
/// A sorted list for each parse state, all in one buffer.
priv struct StateLists[T] {
  items : Array[T]
  /// Where each state's list starts in `items`, by state id, then where the last one ends.
  /// State `i`'s list is `items[starts[i]..starts[i + 1]]`.
  starts : Array[Int32]
}

///|
/// Collects one list per state, in state order, each sorted by `key`. Keys are
/// distinct within a list, so the sort is total.
fn[T] StateLists::collect(
  lists : Array[Array[T]],
  key : (T) -> Int32,
) -> StateLists[T] {
  let starts = Array(capacity=lists.length() + 1)
  starts.push(0)
  let items = []
  for list in lists {
    list.sort_by_key(key)
    for item in list {
      items.push(item)
    }
    starts.push(items.length())
  }
  { items, starts, }
}

///|
/// The list of `state`.
fn[T] StateLists::get(self : StateLists[T], state : ParseState) -> ArrayView[T] {
  let id = state.id
  self.items[self.starts[id]:self.starts[id + 1]]
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
    for symbol in state.terminal_entries.keys() {
      if symbol.terminal_index() is Some(index) {
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
  /// Each state's terminal entries, sorted by symbol.
  entry_maps : StateLists[(Int32, ActionListId)]
  bits : ConflictBits
  /// A hash of each state's reserved words and terminal entries, apart from its shift
  /// targets, whose groups change as groups split.
  static_signatures : Array[Int32]
  /// Each state's shift targets, sorted by symbol.
  shift_maps : StateLists[(Int32, Int32)]
  /// Scratch for `compatible_with_all`.
  kept : KeptStates
}

///|
fn ConflictPass::new(
  minimizer : Minimizer,
  shift_maps : StateLists[(Int32, Int32)],
) -> ConflictPass {
  // Precompute sorted terminal entry references for merge-join in states_conflict.
  // entry_maps.get(state)[i] = (symbol_key, action_list_id). Keys are symbol positions
  // for easy comparison.
  let entry_maps = StateLists::collect(
    minimizer.parse_table.states.map(state => {
      state.terminal_entries
      .items()
      .map(entry => (minimizer.indexer.index(entry.0), entry.1))
    }),
    entry => entry.0,
  )

  // Hash each state's terminal entries once, apart from its shift targets, whose groups
  // change as groups split.
  let static_signatures = minimizer.parse_table.states.map(state => {
    let hasher = Hasher()
    hasher.combine(state.reserved_words)
    for entry in entry_maps.get(state) {
      let (key, id) = entry
      hasher.combine_int(key)
      for action in minimizer.parse_table.action_lists.get(id) {
        match action {
          Shift(is_repetition~, ..) => hasher.combine_bool(is_repetition)
          action => hasher.combine(action)
        }
      }
    }
    hasher.finalize()
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
  match self.minimizer.indexer.symbol(key).terminal_index() {
    Some(index) =>
      (self.bits.state_row_word(state.id, index / 64) & (1UL << (index % 64))) !=
      0
    None =>
      self.entry_maps.get(state).binary_search_by(e => e.0.compare(key))
      is Ok(_)
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
  for entry in self.entry_maps.get(state) {
    let (key, action_list) = entry
    let token = kept_states.tokens[key]
    if token.action_list is Some(kept_action_list) &&
      self.minimizer.entries_conflict(
        kept_action_list, action_list, group_ids_by_state_id,
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
  kept_states.merged_tokens.iter().all(key => self.can_take(state, key))
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
  /// The action list of the first merged state with this token.
  mut action_list : ActionListId?
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
  { action_list: None, count: 0, addable: 0, }
}

///|
fn KeptToken::reset(self : KeptToken) -> Unit {
  self.action_list = None
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
  states : Array[ParseState],
  entry_maps : StateLists[(Int32, ActionListId)],
) -> Unit {
  for i in self.merged_count..<kept.length() {
    let state_id = kept[i]
    for entry in entry_maps.get(states[state_id]) {
      let (key, action_list) = entry
      let token = self.tokens[key]
      if token.action_list is None {
        token.action_list = Some(action_list)
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
      let hasher = Hasher()
      hasher.combine_int(self.static_signatures[state.id])
      for entry in self.shift_maps.get(state) {
        hasher.combine_int(group_ids_by_state_id[entry.1])
      }
      Some(hasher.finalize())
    },
    // Whether two states have the same reserved words and terminal entries, with shift
    // targets compared by group. Then `Minimizer::states_conflict` never separates them,
    // and separates either from exactly the same states.
    equivalent: (left, right, group_ids_by_state_id) => {
      let entries1 = self.entry_maps.get(left)
      let entries2 = self.entry_maps.get(right)
      let action_lists = self.minimizer.parse_table.action_lists
      if left.reserved_words != right.reserved_words ||
        entries1.length() != entries2.length() {
        return false
      }
      for i in 0..<entries1.length() {
        let (key1, id1) = entries1[i]
        let (key2, id2) = entries2[i]
        if key1 != key2 {
          return false
        }
        if id1.index == id2.index {
          continue
        }
        let actions1 = action_lists.get(id1)
        let actions2 = action_lists.get(id2)
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
      self.kept.merge(kept, self.minimizer.parse_table.states, self.entry_maps)
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
  shift_maps : StateLists[(Int32, Int32)]
  /// Each state's nonterminal entries, sorted by symbol.
  nonterminal_maps : StateLists[(Int32, GotoAction)]
}

///|
fn SuccessorPass::new(
  minimizer : Minimizer,
  shift_maps : StateLists[(Int32, Int32)],
) -> SuccessorPass {
  // Store only the symbol index: all nonterminal entries share the same kind,
  // so index alone is sufficient for sorting and comparison.
  let nonterminal_maps = StateLists::collect(
    minimizer.parse_table.states.map(state => {
      state.nonterminal_entries
      .items()
      .map(entry => (entry.0.non_terminal_index().unwrap(), entry.1))
    }),
    entry => entry.0,
  )
  { minimizer, shift_maps, nonterminal_maps, }
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
      let hasher = Hasher()
      for entry in self.shift_maps.get(state) {
        hasher.combine_int(entry.0)
        hasher.combine_int(group_ids_by_state_id[entry.1])
      }
      for entry in self.nonterminal_maps.get(state) {
        hasher.combine_int(entry.0)
        match entry.1 {
          Goto(successor) => {
            hasher.combine_int(1)
            hasher.combine_int(group_ids_by_state_id[successor])
          }
          ShiftExtra => hasher.combine_int(0)
        }
      }
      Some(hasher.finalize())
    },
    // Whether two states shift and go to on the same symbols, with successors in the same
    // groups. Then `Minimizer::state_successors_differ` never separates them, and separates
    // either from exactly the same states.
    equivalent: (left, right, group_ids_by_state_id) => {
      let shifts1 = self.shift_maps.get(left)
      let shifts2 = self.shift_maps.get(right)
      let gotos1 = self.nonterminal_maps.get(left)
      let gotos2 = self.nonterminal_maps.get(right)
      if shifts1.length() != shifts2.length() ||
        gotos1.length() != gotos2.length() {
        return false
      }
      for i in 0..<shifts1.length() {
        let (key1, s1) = shifts1[i]
        let (key2, s2) = shifts2[i]
        if key1 != key2 ||
          group_ids_by_state_id[s1] != group_ids_by_state_id[s2] {
          return false
        }
      }
      for i in 0..<gotos1.length() {
        let (index1, action1) = gotos1[i]
        let (index2, action2) = gotos2[i]
        if index1 != index2 {
          return false
        }
        let same = match (action1, action2) {
          (Goto(s1), Goto(s2)) =>
            group_ids_by_state_id[s1] == group_ids_by_state_id[s2]
          (ShiftExtra, ShiftExtra) => true
          _ => false
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
    for entry in state.terminal_entries.items() {
      for action in self.parse_table.action_lists.get(entry.1) {
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
        let (symbol, old_id) = state.terminal_entries.get_index(i)
        let actions = action_lists.get(old_id).copy()
        let mut changed = false
        for k, action in actions {
          // A Shift onto a unit-reduction state (one whose only action reduces a
          // single `symbol`) can skip it. Shift then reduce then goto is equivalent
          // to shifting straight to the the goto target for `symbol` in this case.
          if action is Shift(state=target, is_repetition~) &&
            unit_reduction_symbols_by_state.get(target) is Some(symbol) &&
            state.nonterminal_entries.get(symbol) is Some(Goto(new_target)) &&
            new_target != target {
            actions[k] = Shift(state=new_target, is_repetition~)
            changed = true
            done = false
          }
        }
        if changed {
          let index = action_lists.intern(action_list_ids, actions)
          state.terminal_entries.set_index(
            i,
            symbol,
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
  let shift_maps = StateLists::collect(
    self.parse_table.states.map(state => {
      let list = []
      for entry in state.terminal_entries.items() {
        if self.parse_table.action_lists.get(entry.1).last()
          is Some(Shift(state=s, ..)) {
          list.push((self.indexer.index(entry.0), s))
        }
      }
      list
    }),
    entry => entry.0,
  )
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
  for state_ids in state_ids_by_group_id {
    // Initialize the new state based on the first old state in the group.
    let parse_state = self.parse_table.states[state_ids[0]]
    self.parse_table.states[state_ids[0]] = ParseState::new()
    set_positions(parse_state.terminal_entries, positions, self.indexer)
    set_positions(parse_state.nonterminal_entries, positions, self.indexer)

    // Extend the new state with all of the actions from the other old states
    // in the group.
    for k in 1..<state_ids.length() {
      let state_id = state_ids[k]
      let other_parse_state = self.parse_table.states[state_id]
      self.parse_table.states[state_id] = ParseState::new()
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
      for symbol in parse_state.terminal_entries.keys() {
        ignore(parse_state.reserved_words.remove(symbol))
      }
    }
    for symbol in parse_state.terminal_entries.keys() {
      positions[self.indexer.index(symbol)] = None
    }
    for symbol in parse_state.nonterminal_entries.keys() {
      positions[self.indexer.index(symbol)] = None
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
  entry_maps : StateLists[(Int32, ActionListId)],
  bits : ConflictBits,
) -> Bool {
  let entries1 = entry_maps.get(state1)
  let entries2 = entry_maps.get(state2)
  let len1 = entries1.length()
  let len2 = entries2.length()
  let mut i = 0
  let mut j = 0
  while i < len1 || j < len2 {
    let ord = if i < len1 && j < len2 {
      entries1[i].0.compare(entries2[j].0)
    } else if i < len1 {
      -1
    } else {
      1
    }
    if ord == 0 {
      let e1 = entries1[i]
      let e2 = entries2[j]
      if self.entries_conflict(e1.1, e2.1, group_ids_by_state_id) is Some(_) {
        // (Upstream logs the conflict at debug level.)
        return true
      }
      i += 1
      j += 1
    } else if ord < 0 {
      let e1 = entries1[i]
      if self.token_conflicts(state2, bits, e1.0) is Some(_) {
        return true
      }
      i += 1
    } else {
      let e2 = entries2[j]
      if self.token_conflicts(state1, bits, e2.0) is Some(_) {
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
  shift_maps : StateLists[(Int32, Int32)],
  nonterminal_maps : StateLists[(Int32, GotoAction)],
) -> Bool {
  let shifts1 = shift_maps.get(state1)
  let shifts2 = shift_maps.get(state2)
  let mut i = 0
  let mut j = 0
  while i < shifts1.length() && j < shifts2.length() {
    let (k1, s1) = shifts1[i]
    let (k2, s2) = shifts2[j]
    if k1 < k2 {
      i += 1
    } else if k1 > k2 {
      j += 1
    } else {
      let group1 = group_ids_by_state_id[s1]
      let group2 = group_ids_by_state_id[s2]
      if group1 != group2 {
        // (Upstream logs the split at debug level.)
        return true
      }
      i += 1
      j += 1
    }
  }
  let nonterms1 = nonterminal_maps.get(state1)
  let nonterms2 = nonterminal_maps.get(state2)
  let mut i = 0
  let mut j = 0
  while i < nonterms1.length() && j < nonterms2.length() {
    let (idx1, s1) = nonterms1[i]
    let (idx2, s2) = nonterms2[j]
    if idx1 < idx2 {
      i += 1
    } else if idx1 > idx2 {
      j += 1
    } else {
      match (s1, s2) {
        (ShiftExtra, ShiftExtra) => ()
        (Goto(s1), Goto(s2)) => {
          let group1 = group_ids_by_state_id[s1]
          let group2 = group_ids_by_state_id[s2]
          if group1 != group2 {
            return true
          }
        }
        _ => return true
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
  id1 : ActionListId,
  id2 : ActionListId,
  group_ids_by_state_id : Array[Int32],
) -> Conflict? {
  // To be compatible, entries need to have the same actions.
  if id1.index == id2.index {
    None
  } else {
    self.action_lists_conflict(id1, id2, group_ids_by_state_id)
  }
}

///|
/// `Self::entries_conflict` for entries with different action lists.
fn Minimizer::action_lists_conflict(
  self : Minimizer,
  id1 : ActionListId,
  id2 : ActionListId,
  group_ids_by_state_id : Array[Int32],
) -> Conflict? {
  let actions1 = self.parse_table.action_lists.get(id1)
  let actions2 = self.parse_table.action_lists.get(id2)
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
  let symbol = self.indexer.symbol(new_token)
  let (new_token_index, new_token_is_terminal) = match symbol.kind {
    EndOfNonTerminalExtra => return Some(EndOfNonTerminalExtra)
    // Do not add external tokens, as they could conflict lexically with
    // any of the state's existing lookahead tokens.
    External => return Some(ExternalToken)
    End => (0, false)
    Terminal => (symbol.index, true)
    NonTerminal => abort("unreachable")
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
  for position, symbol in entries.keys() {
    positions[indexer.index(symbol)] = Some(position)
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
  for entry in other.items() {
    let (symbol, value) = entry
    let index = indexer.index(symbol)
    match positions[index] {
      Some(position) => entries.set_index(position, symbol, value)
      None => {
        positions[index] = Some(entries.len())
        entries.push(symbol, value)
      }
    }
  }
}
