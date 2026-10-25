// Port of tree-sitter crates/generate/src/tables.rs.

///|
/// Constructor order defines the derived ordering (matches upstream).
pub(all) enum ParseAction {
  Accept
  Shift(state~ : Int, is_repetition~ : Bool)
  ShiftExtra
  Recover
  Reduce(
    symbol~ : Symbol,
    child_count~ : Int,
    dynamic_precedence~ : Int,
    production_id~ : Int
  )
} derive(Eq, Hash, Compare, Debug)

///|
pub(all) enum GotoAction {
  Goto(Int)
  ShiftExtra
} derive(Eq, Hash, Debug)

///|
/// Index of an action list in an `ActionListPool`, plus the entry's reusable bit.
pub(all) struct ActionListId {
  index : Int
  reusable : Bool
} derive(Eq, Hash, Debug)

///|
pub fn ActionListId::new(index : Int, reusable : Bool) -> ActionListId {
  { index, reusable }
}

///|
pub fn ActionListId::with_reusable(
  self : ActionListId,
  reusable : Bool,
) -> ActionListId {
  { ..self, reusable, }
}

///|
pub struct ActionListPool {
  mut lists : Array[Array[ParseAction]]
}

///|
pub fn ActionListPool::new() -> ActionListPool {
  { lists: [] }
}

///|
pub fn ActionListPool::push(
  self : ActionListPool,
  list : Array[ParseAction],
) -> Int {
  let index = self.lists.length()
  self.lists.push(list.copy())
  index
}

///|
pub fn ActionListPool::get(
  self : ActionListPool,
  id : ActionListId,
) -> Array[ParseAction] {
  self.lists[id.index]
}

///|
pub fn ActionListPool::get_index(
  self : ActionListPool,
  index : Int,
) -> Array[ParseAction] {
  self.lists[index]
}

///|
pub fn ActionListPool::len(self : ActionListPool) -> Int {
  self.lists.length()
}

///|
pub fn ActionListPool::intern(
  self : ActionListPool,
  dedup : Map[Array[ParseAction], Int],
  list : Array[ParseAction],
) -> Int {
  match dedup.get(list) {
    Some(index) => index
    None => {
      let index = self.push(list)
      dedup[list.copy()] = index
      index
    }
  }
}

///|
/// Renumber the pool so that ids are assigned in first-use order across the
/// states' terminal entries, with the empty list first.
pub fn ActionListPool::canonicalize(
  self : ActionListPool,
  states : Array[ParseState],
) -> Unit {
  let old_lists = self.lists
  self.lists = []
  let ids : Map[Array[ParseAction], Int] = Map([])
  ignore(self.intern(ids, []))
  let old_to_new = Array::make(old_lists.length(), -1)
  for state in states {
    let entries = state.terminal_entries
    for i in 0..<entries.len() {
      let (symbol, id) = entries.get_index(i)
      let old_index = id.index
      let mut new_index = old_to_new[old_index]
      if new_index == -1 {
        new_index = self.intern(ids, old_lists[old_index])
        old_to_new[old_index] = new_index
      }
      entries.set_index(i, symbol, ActionListId::new(new_index, id.reusable))
    }
  }
}

///|
/// An insertion-ordered association list keyed by symbol.
pub struct ParseStateEntries[V] {
  priv entries : Array[(Symbol, V)]
}

///|
pub fn[V] ParseStateEntries::new() -> ParseStateEntries[V] {
  { entries: [] }
}

///|
pub fn[V] ParseStateEntries::len(self : ParseStateEntries[V]) -> Int {
  self.entries.length()
}

///|
pub fn[V] ParseStateEntries::items(
  self : ParseStateEntries[V],
) -> Array[(Symbol, V)] {
  self.entries
}

///|
pub fn[V] ParseStateEntries::keys(self : ParseStateEntries[V]) -> Array[Symbol] {
  self.entries.map(e => e.0)
}

///|
pub fn[V] ParseStateEntries::values(self : ParseStateEntries[V]) -> Array[V] {
  self.entries.map(e => e.1)
}

///|
pub fn[V] ParseStateEntries::get(
  self : ParseStateEntries[V],
  symbol : Symbol,
) -> V? {
  for entry in self.entries {
    if entry.0 == symbol {
      return Some(entry.1)
    }
  }
  None
}

///|
pub fn[V] ParseStateEntries::get_index(
  self : ParseStateEntries[V],
  index : Int,
) -> (Symbol, V) {
  self.entries[index]
}

///|
pub fn[V] ParseStateEntries::set_index(
  self : ParseStateEntries[V],
  index : Int,
  symbol : Symbol,
  value : V,
) -> Unit {
  self.entries[index] = (symbol, value)
}

///|
pub fn[V] ParseStateEntries::contains_key(
  self : ParseStateEntries[V],
  symbol : Symbol,
) -> Bool {
  self.entries.iter().any(e => e.0 == symbol)
}

///|
pub fn[V] ParseStateEntries::insert(
  self : ParseStateEntries[V],
  symbol : Symbol,
  value : V,
) -> Unit {
  for i, entry in self.entries {
    if entry.0 == symbol {
      self.entries[i] = (symbol, value)
      return
    }
  }
  self.entries.push((symbol, value))
}

///|
pub fn[V] ParseStateEntries::insert_if_missing(
  self : ParseStateEntries[V],
  symbol : Symbol,
  value : V,
) -> Unit {
  if !self.contains_key(symbol) {
    self.entries.push((symbol, value))
  }
}

///|
pub fn[V] ParseStateEntries::push(
  self : ParseStateEntries[V],
  symbol : Symbol,
  value : V,
) -> Unit {
  self.entries.push((symbol, value))
}

///|
pub fn[V] ParseStateEntries::copy(
  self : ParseStateEntries[V],
) -> ParseStateEntries[V] {
  { entries: self.entries.copy() }
}

///|
pub fn[V] ParseStateEntries::clear(self : ParseStateEntries[V]) -> Unit {
  self.entries.clear()
}

///|
pub fn[V] ParseStateEntries::retain(
  self : ParseStateEntries[V],
  f : (Symbol, V) -> Bool,
) -> Unit {
  self.entries.retain(e => f(e.0, e.1))
}

///|
pub type TerminalEntries = ParseStateEntries[ActionListId]

///|
pub type NonterminalEntries = ParseStateEntries[GotoAction]

///|
pub(all) struct ParseState {
  mut id : Int
  mut terminal_entries : TerminalEntries
  mut nonterminal_entries : NonterminalEntries
  mut reserved_words : TokenSet
  mut lex_state_id : Int
  mut external_lex_state_id : Int
  mut core_id : Int
  mut has_eof_gated_reduce : Bool
}

///|
pub fn ParseState::new() -> ParseState {
  {
    id: 0,
    terminal_entries: ParseStateEntries::new(),
    nonterminal_entries: ParseStateEntries::new(),
    reserved_words: TokenSet::new(),
    lex_state_id: 0,
    external_lex_state_id: 0,
    core_id: 0,
    has_eof_gated_reduce: false,
  }
}

///|
pub fn ParseState::is_end_of_non_terminal_extra(self : ParseState) -> Bool {
  self.terminal_entries.contains_key(symbol_end_of_nonterminal_extra)
}

///|
/// Shift targets of the terminal entries, then goto targets, in entry order.
pub fn ParseState::referenced_states(
  self : ParseState,
  pool : ActionListPool,
) -> Array[Int] {
  let result = []
  for entry in self.terminal_entries.items() {
    for action in pool.get(entry.1) {
      if action is Shift(state~, ..) {
        result.push(state)
      }
    }
  }
  for entry in self.nonterminal_entries.items() {
    if entry.1 is Goto(state) {
      result.push(state)
    }
  }
  result
}

///|
pub fn ParseState::update_nonterminal_references(
  self : ParseState,
  f : (Int, ParseState) -> Int,
) -> Unit {
  let updates = []
  for index, entry in self.nonterminal_entries.items() {
    if entry.1 is Goto(other_state) {
      let result = f(other_state, self)
      if result != other_state {
        updates.push((index, result))
      }
    }
  }
  for update in updates {
    let (index, new_state) = update
    let (symbol, _) = self.nonterminal_entries.get_index(index)
    self.nonterminal_entries.set_index(index, symbol, Goto(new_state))
  }
}

///|
pub(all) struct FieldLocation {
  index : Int
  inherited : Bool
} derive(Eq, Hash, Compare, Debug)

///|
pub(all) struct ProductionInfo {
  alias_sequence : Array[Alias?]
  /// Upstream: `BTreeMap<StrId, Vec<FieldLocation>>`, ordered by intern id.
  field_map : @sorted_map.SortedMap[StrId, Array[FieldLocation]]
} derive(Eq, Debug)

///|
pub(all) struct ParseTable {
  mut states : Array[ParseState]
  action_lists : ActionListPool
  mut symbols : Array[Symbol]
  mut production_infos : Array[ProductionInfo]
  mut max_aliased_production_length : Int
  mut external_lex_states : Array[TokenSet]
}

///|
pub fn ParseTable::new() -> ParseTable {
  {
    states: [],
    action_lists: ActionListPool::new(),
    symbols: [],
    production_infos: [],
    max_aliased_production_length: 0,
    external_lex_states: [],
  }
}

///|
/// Apply `f` to every shift target in action lists referenced by some state.
pub fn ParseTable::remap_terminal_references(
  self : ParseTable,
  f : (Int) -> Int,
) -> Unit {
  let referenced = Array::make(self.action_lists.len(), false)
  for state in self.states {
    for id in state.terminal_entries.values() {
      referenced[id.index] = true
    }
  }
  for index, list in self.action_lists.lists {
    if !referenced[index] {
      continue
    }
    for i, action in list {
      if action is Shift(state~, is_repetition~) {
        list[i] = Shift(state=f(state), is_repetition~)
      }
    }
  }
}

///|
pub(all) struct AdvanceAction {
  state : Int
  in_main_token : Bool
} derive(Eq, Hash, Compare, Debug)

///|
pub(all) struct LexState {
  mut accept_action : Symbol?
  mut eof_action : AdvanceAction?
  mut advance_actions : Array[(CharacterSet, AdvanceAction)]
} derive(Eq, Hash, Debug)

///|
pub fn LexState::new() -> LexState {
  { accept_action: None, eof_action: None, advance_actions: [] }
}

///|
pub(all) struct LexTable {
  mut states : Array[LexState]
} derive(Eq, Debug)

///|
pub fn LexTable::new() -> LexTable {
  { states: [] }
}
