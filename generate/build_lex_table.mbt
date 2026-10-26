// Port of tree-sitter crates/generate/src/build_tables/build_lex_table.rs.

///|
pub const LARGE_CHARACTER_RANGE_COUNT : Int32 = 8

///|
priv struct LexTables {
  main_lex_table : LexTable
  keyword_lex_table : LexTable
  large_character_sets : Array[(Symbol?, CharacterSet)]
}

///|
fn build_lex_table(
  parse_table : ParseTable,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  keywords : TokenSet,
  coincident_token_index : CoincidentTokenIndex,
  token_conflict_map : TokenConflictMap,
  str_pool : StrPool,
) -> LexTables {
  let keyword_lex_table = if syntax_grammar.word_token is Some(_) {
    let builder = LexTableBuilder::new(lexical_grammar)
    ignore(builder.add_state_for_tokens(keywords, str_pool))
    builder.table
  } else {
    LexTable::new()
  }
  let parse_state_ids_by_token_set : Array[(TokenSet, Array[Int32])] = []
  for i, state in parse_table.states {
    let tokens = TokenSet::new()
    let candidates = state.terminal_entries.keys()
    for token in state.reserved_words.iter() {
      candidates.push(token)
    }
    for token in candidates {
      match token.kind {
        Terminal =>
          if keywords.contains(token) {
            if syntax_grammar.word_token is Some(word_token) {
              tokens.insert(word_token)
            }
          } else {
            tokens.insert(token)
          }
        End => tokens.insert(token)
        External | EndOfNonTerminalExtra | NonTerminal => ()
      }
    }
    let mut did_merge = false
    for entry in parse_state_ids_by_token_set {
      if merge_token_set(
          entry.0,
          tokens,
          token_conflict_map,
          coincident_token_index,
        ) {
        did_merge = true
        entry.1.push(i)
        break
      }
    }
    if !did_merge {
      parse_state_ids_by_token_set.push((tokens, [i]))
    }
  }
  let builder = LexTableBuilder::new(lexical_grammar)
  for entry in parse_state_ids_by_token_set {
    let (tokens, parse_state_ids) = entry
    let lex_state_id = builder.add_state_for_tokens(tokens, str_pool)
    for id in parse_state_ids {
      parse_table.states[id].lex_state_id = lex_state_id
    }
  }
  let main_lex_table = builder.table
  builder.table = LexTable::new()
  minimize_lex_table(main_lex_table, parse_table)
  sort_states(main_lex_table, parse_table)
  let large_character_sets : Array[(Symbol?, CharacterSet)] = []
  for variable_ix in 0..<lexical_grammar.variables.length() {
    let symbol = Symbol::terminal(variable_ix)
    builder.reset()
    ignore(
      builder.add_state_for_tokens(TokenSet::from_array([symbol]), str_pool),
    )
    for state in builder.table.states {
      let characters = CharacterSet::empty()
      for advance in state.advance_actions {
        let (chars, action) = advance
        if action.in_main_token {
          characters.add_in_place(chars)
          continue
        }
        if chars.range_count() > LARGE_CHARACTER_RANGE_COUNT &&
          !large_character_sets.iter().any(entry => entry.1 == chars) {
          large_character_sets.push((None, chars.copy()))
        }
      }
      if characters.range_count() > LARGE_CHARACTER_RANGE_COUNT &&
        !large_character_sets.iter().any(entry => entry.1 == characters) {
        large_character_sets.push((Some(symbol), characters))
      }
    }
  }
  { main_lex_table, keyword_lex_table, large_character_sets, }
}

///|
priv struct LexQueueEntry {
  state_id : Int32
  nfa_states : Array[Int32]
  eof_valid : Bool
}

///|
priv struct LexTableBuilder {
  lexical_grammar : LexicalGrammar
  cursor : NfaCursor
  mut table : LexTable
  state_queue : Array[LexQueueEntry]
  mut state_queue_head : Int32
  state_ids_by_nfa_state_set : Map[(Array[Int32], Bool), Int32]
}

///|
fn LexTableBuilder::new(lexical_grammar : LexicalGrammar) -> LexTableBuilder {
  {
    lexical_grammar,
    cursor: NfaCursor::new(lexical_grammar.nfa, []),
    table: LexTable::new(),
    state_queue: [],
    state_queue_head: 0,
    state_ids_by_nfa_state_set: {},
  }
}

///|
fn LexTableBuilder::reset(self : LexTableBuilder) -> Unit {
  self.table = LexTable::new()
  self.state_queue.clear()
  self.state_queue_head = 0
  self.state_ids_by_nfa_state_set.clear()
}

///|
fn LexTableBuilder::add_state_for_tokens(
  self : LexTableBuilder,
  tokens : TokenSet,
  _str_pool : StrPool,
) -> Int32 {
  let mut eof_valid = false
  let nfa_states = []
  for token in tokens.iter() {
    match token.kind {
      Terminal =>
        nfa_states.push(self.lexical_grammar.variables[token.index].start_state)
      End => eof_valid = true
      External | EndOfNonTerminalExtra | NonTerminal => abort("unreachable")
    }
  }
  let (state_id, _is_new) = self.add_state(nfa_states, eof_valid)
  // (Upstream logs the entry point state's tokens at debug level when it's new.)
  while self.state_queue_head < self.state_queue.length() {
    let { state_id, nfa_states, eof_valid, } = self.state_queue[self.state_queue_head]
    self.state_queue_head += 1
    self.populate_state(state_id, nfa_states, eof_valid)
  }
  self.state_queue.clear()
  self.state_queue_head = 0
  state_id
}

///|
fn LexTableBuilder::add_state(
  self : LexTableBuilder,
  nfa_states : Array[Int32],
  eof_valid : Bool,
) -> (Int32, Bool) {
  self.cursor.reset(nfa_states)
  let key = (self.cursor.state_ids, eof_valid)
  match self.state_ids_by_nfa_state_set.get(key) {
    Some(id) => (id, false)
    None => {
      let state_id = self.table.states.length()
      self.table.states.push(LexState::new())
      let state_ids = self.cursor.state_ids.copy()
      self.state_queue.push({
        state_id,
        nfa_states: state_ids.copy(),
        eof_valid,
      })
      self.state_ids_by_nfa_state_set[(state_ids, eof_valid)] = state_id
      (state_id, true)
    }
  }
}

///|
fn LexTableBuilder::populate_state(
  self : LexTableBuilder,
  state_id : Int32,
  nfa_states : Array[Int32],
  eof_valid : Bool,
) -> Unit {
  self.cursor.force_reset(nfa_states)

  // The EOF state is represented as an empty list of NFA states.
  let mut completion : (Int32, Int32)? = None
  for item in self.cursor.completions() {
    let (id, prec) = item
    if completion is Some((prev_id, prev_precedence)) &&
      TokenConflictMap::prefer_token(
        self.lexical_grammar,
        (prev_precedence, prev_id),
        (prec, id),
      ) {
      continue
    }
    completion = Some((id, prec))
  }
  let (transitions, has_sep) = self.cursor.transitions_and_any_sep()

  // If EOF is a valid lookahead token, add a transition predicated on the null
  // character that leads to the empty set of NFA states.
  if eof_valid {
    let (next_state_id, _) = self.add_state([], false)
    self.table.states[state_id].eof_action = Some({
      state: next_state_id,
      in_main_token: true,
    })
  }
  for transition in transitions {
    if completion is Some((completed_id, completed_precedence)) &&
      !TokenConflictMap::prefer_transition(
        self.lexical_grammar,
        transition,
        completed_id,
        completed_precedence,
        has_sep,
      ) {
      continue
    }
    let (next_state_id, _) = self.add_state(
      transition.states,
      eof_valid && transition.is_separator,
    )
    self.table.states[state_id].advance_actions.push(
      (
        transition.characters,
        { state: next_state_id, in_main_token: !transition.is_separator, },
      ),
    )
  }
  if completion is Some((complete_id, _)) {
    self.table.states[state_id].accept_action = Some(
      Symbol::terminal(complete_id),
    )
  } else if self.cursor.state_ids.is_empty() {
    // NOTE: like upstream, this reads the cursor as the last `add_state` left it.
    self.table.states[state_id].accept_action = Some(symbol_end)
  }
}

///|
fn check_token_conflicts(
  i : Int32,
  set_without_terminal : TokenSet,
  token_conflict_map : TokenConflictMap,
  coincident_token_index : CoincidentTokenIndex,
) -> Bool {
  let wpr = token_conflict_map.row_words
  let row_start = i * wpr
  let set_bits = set_without_terminal.terminal_bits_words()
  let n = if set_bits.length() < wpr { set_bits.length() } else { wpr }

  // Does terminal i conflict with or match-prefix any terminal in the set?
  for w in 0..<n {
    if (token_conflict_map.conflict_or_prefix_bits[row_start + w] & set_bits[w]) !=
      0 {
      return true
    }
  }

  // Does terminal i overlap (in either direction) with any non-coincident terminal in the set?
  for w in 0..<n {
    let o = token_conflict_map.overlap_either_bits[row_start + w]
    let c = coincident_token_index.row_bits[row_start + w]
    if (o & set_bits[w] & c.lnot()) != 0 {
      return true
    }
  }
  false
}

///|
fn merge_token_set(
  tokens : TokenSet,
  other : TokenSet,
  token_conflict_map : TokenConflictMap,
  coincident_token_index : CoincidentTokenIndex,
) -> Bool {
  if tokens
    .terminals()
    .iter()
    .filter(index => !other.contains_terminal(index))
    .any(index => {
      check_token_conflicts(
        index, other, token_conflict_map, coincident_token_index,
      )
    }) {
    return false
  }
  if other
    .terminals()
    .iter()
    .filter(index => !tokens.contains_terminal(index))
    .any(index => {
      check_token_conflicts(
        index, tokens, token_conflict_map, coincident_token_index,
      )
    }) {
    return false
  }
  ignore(tokens.insert_all(other))
  true
}

///|
fn minimize_lex_table(table : LexTable, parse_table : ParseTable) -> Unit {
  // Initially group the states by their accept action and their
  // valid lookahead characters.
  let state_ids_by_signature : Map[
    (Bool, Symbol?, Bool, Array[(CharacterSet, Bool)]),
    Array[Int32],
  ] = Map([])
  for i, state in table.states {
    let signature = (
      i == 0,
      state.accept_action,
      state.eof_action is Some(_),
      state.advance_actions.map(advance => (advance.0, advance.1.in_main_token)),
    )
    state_ids_by_signature.get_or_init(signature, () => []).push(i)
  }
  // Upstream collects the groups in hash order and then sorts them. The groups
  // are disjoint, so the sort is total and the hash order unobservable.
  let state_ids_by_group_id = state_ids_by_signature.values().collect()
  state_ids_by_group_id.sort_by(compare_int_lists)
  let mut error_group_index = 0
  for index, group in state_ids_by_group_id {
    if group.contains(0) {
      error_group_index = index
      break
    }
  }
  state_ids_by_group_id.swap(error_group_index, 0)
  let group_ids_by_state_id = Array::make(table.states.length(), 0)
  for group_id, state_ids in state_ids_by_group_id {
    for state_id in state_ids {
      group_ids_by_state_id[state_id] = group_id
    }
  }
  let criterion = lex_state_split()
  while split_state_id_groups(
          table.states,
          state_ids_by_group_id,
          group_ids_by_state_id,
          1,
          criterion,
        ) {

  }
  let new_states = Array(capacity=state_ids_by_group_id.length())
  for state_ids in state_ids_by_group_id {
    let new_state = table.states[state_ids[0]]
    table.states[state_ids[0]] = LexState::new()
    new_state.advance_actions = new_state.advance_actions.map(advance => {
      let (chars, action) = advance
      (chars, { ..action, state: group_ids_by_state_id[action.state], })
    })
    if new_state.eof_action is Some(eof_action) {
      new_state.eof_action = Some({
        ..eof_action,
        state: group_ids_by_state_id[eof_action.state],
      })
    }
    new_states.push(new_state)
  }
  for state in parse_table.states {
    state.lex_state_id = group_ids_by_state_id[state.lex_state_id]
  }
  table.states = new_states
}

///|
/// Rust's `Ord` for `Vec<u32>`.
fn compare_int_lists(a : Array[Int32], b : Array[Int32]) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let c = a[i].compare(b[i])
    if c != 0 {
      return c
    }
  }
  a.length().compare(b.length())
}

///|
/// Separates lex states whose advance actions lead to different groups.
fn lex_state_split() -> SplitCriterion[LexState] {
  {
    ..SplitCriterion::simple(lex_states_differ),
    // The states of a group have the same advance actions apart from the states they lead
    // to, so states that don't need to be split lead to the same groups. Every kept state
    // leads to the same groups as the first one, and `state` was just found to as well.
    compatible_with_all: (_, _, _) => true,
  }
}

///|
fn lex_states_differ(
  left : LexState,
  right : LexState,
  group_ids_by_state_id : Array[Int32],
) -> Bool {
  let n = if left.advance_actions.length() < right.advance_actions.length() {
    left.advance_actions.length()
  } else {
    right.advance_actions.length()
  }
  for i in 0..<n {
    if group_ids_by_state_id[left.advance_actions[i].1.state] !=
      group_ids_by_state_id[right.advance_actions[i].1.state] {
      return true
    }
  }
  false
}

///|
/// Rust's derived `Ord` for `LexState`.
fn compare_lex_states(a : LexState, b : LexState) -> Int32 {
  let c = match (a.accept_action, b.accept_action) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) => x.compare(y)
  }
  if c != 0 {
    return c
  }
  let c = match (a.eof_action, b.eof_action) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) => x.compare(y)
  }
  if c != 0 {
    return c
  }
  let n = if a.advance_actions.length() < b.advance_actions.length() {
    a.advance_actions.length()
  } else {
    b.advance_actions.length()
  }
  for i in 0..<n {
    let (ca, aa) = a.advance_actions[i]
    let (cb, ab) = b.advance_actions[i]
    let c = ca.compare(cb)
    if c != 0 {
      return c
    }
    let c = aa.compare(ab)
    if c != 0 {
      return c
    }
  }
  a.advance_actions.length().compare(b.advance_actions.length())
}

///|
fn sort_states(table : LexTable, parse_table : ParseTable) -> Unit {
  // Get a mapping of old state index -> new_state_index
  let old_ids_by_new_id = Array::makei(table.states.length(), i => i)
  let rest = old_ids_by_new_id[1:].to_owned()
  stable_sort_by(rest, (a, b) => {
    compare_lex_states(table.states[a], table.states[b])
  })
  for i, id in rest {
    old_ids_by_new_id[i + 1] = id
  }

  // Get the inverse mapping
  let new_ids_by_old_id = Array::make(old_ids_by_new_id.length(), 0)
  for id, old_id in old_ids_by_new_id {
    new_ids_by_old_id[old_id] = id
  }

  // Reorder the parse states and update their references to reflect
  // the new ordering.
  table.states = old_ids_by_new_id.map(old_id => {
    let state = table.states[old_id]
    state.advance_actions = state.advance_actions.map(advance => {
      let (chars, action) = advance
      (chars, { ..action, state: new_ids_by_old_id[action.state], })
    })
    if state.eof_action is Some(eof_action) {
      state.eof_action = Some({
        ..eof_action,
        state: new_ids_by_old_id[eof_action.state],
      })
    }
    state
  })

  // Update the parse table's lex state references
  for state in parse_table.states {
    state.lex_state_id = new_ids_by_old_id[state.lex_state_id]
  }
}
