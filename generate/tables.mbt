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
#valtype
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
      let id = entries.value_at(i)
      let old_index = id.index
      let mut new_index = old_to_new[old_index]
      if new_index == -1 {
        new_index = self.intern(ids, old_lists[old_index])
        old_to_new[old_index] = new_index
      }
      entries.set_value_at(i, ActionListId::new(new_index, id.reusable))
    }
  }
}

///|
/// An insertion-ordered association list keyed by symbol. The symbols and the
/// values are kept in parallel arrays, so that entries aren't boxed.
pub struct ParseStateEntries[V] {
  priv syms : Array[Symbol]
  priv vals : Array[V]
}

///|
pub fn[V] ParseStateEntries::new() -> ParseStateEntries[V] {
  { syms: [], vals: [] }
}

///|
/// Makes room for `additional` more entries.
fn[V] ParseStateEntries::reserve(
  self : ParseStateEntries[V],
  additional : Int,
) -> Unit {
  self.syms.reserve_capacity(self.syms.length() + additional)
  self.vals.reserve_capacity(self.vals.length() + additional)
}

///|
pub fn[V] ParseStateEntries::len(self : ParseStateEntries[V]) -> Int {
  self.syms.length()
}

///|
/// The entries as pairs, in order. (A new array: prefer `symbol_at` and
/// `value_at`.)
pub fn[V] ParseStateEntries::items(
  self : ParseStateEntries[V],
) -> Array[(Symbol, V)] {
  Array::makei(self.syms.length(), i => (self.syms[i], self.vals[i]))
}

///|
pub fn[V] ParseStateEntries::keys(self : ParseStateEntries[V]) -> Array[Symbol] {
  self.syms.copy()
}

///|
pub fn[V] ParseStateEntries::values(self : ParseStateEntries[V]) -> Array[V] {
  self.vals.copy()
}

///|
/// The symbol of the entry at `index`.
pub fn[V] ParseStateEntries::symbol_at(
  self : ParseStateEntries[V],
  index : Int,
) -> Symbol {
  self.syms[index]
}

///|
/// The value of the entry at `index`.
pub fn[V] ParseStateEntries::value_at(
  self : ParseStateEntries[V],
  index : Int,
) -> V {
  self.vals[index]
}

///|
/// Replaces the value of the entry at `index`, keeping its symbol.
pub fn[V] ParseStateEntries::set_value_at(
  self : ParseStateEntries[V],
  index : Int,
  value : V,
) -> Unit {
  self.vals[index] = value
}

///|
/// The index of `symbol`'s entry, or `-1`.
fn[V] ParseStateEntries::position(
  self : ParseStateEntries[V],
  symbol : Symbol,
) -> Int {
  for i, s in self.syms {
    if s == symbol {
      return i
    }
  }
  -1
}

///|
pub fn[V] ParseStateEntries::get(
  self : ParseStateEntries[V],
  symbol : Symbol,
) -> V? {
  let i = self.position(symbol)
  if i >= 0 {
    Some(self.vals[i])
  } else {
    None
  }
}

///|
pub fn[V] ParseStateEntries::get_index(
  self : ParseStateEntries[V],
  index : Int,
) -> (Symbol, V) {
  (self.syms[index], self.vals[index])
}

///|
pub fn[V] ParseStateEntries::set_index(
  self : ParseStateEntries[V],
  index : Int,
  symbol : Symbol,
  value : V,
) -> Unit {
  self.syms[index] = symbol
  self.vals[index] = value
}

///|
pub fn[V] ParseStateEntries::contains_key(
  self : ParseStateEntries[V],
  symbol : Symbol,
) -> Bool {
  self.position(symbol) >= 0
}

///|
pub fn[V] ParseStateEntries::insert(
  self : ParseStateEntries[V],
  symbol : Symbol,
  value : V,
) -> Unit {
  let i = self.position(symbol)
  if i >= 0 {
    self.vals[i] = value
  } else {
    self.syms.push(symbol)
    self.vals.push(value)
  }
}

///|
pub fn[V] ParseStateEntries::insert_if_missing(
  self : ParseStateEntries[V],
  symbol : Symbol,
  value : V,
) -> Unit {
  if !self.contains_key(symbol) {
    self.syms.push(symbol)
    self.vals.push(value)
  }
}

///|
pub fn[V] ParseStateEntries::push(
  self : ParseStateEntries[V],
  symbol : Symbol,
  value : V,
) -> Unit {
  self.syms.push(symbol)
  self.vals.push(value)
}

///|
pub fn[V] ParseStateEntries::copy(
  self : ParseStateEntries[V],
) -> ParseStateEntries[V] {
  { syms: self.syms.copy(), vals: self.vals.copy() }
}

///|
pub fn[V] ParseStateEntries::clear(self : ParseStateEntries[V]) -> Unit {
  self.syms.clear()
  self.vals.clear()
}

///|
pub fn[V] ParseStateEntries::retain(
  self : ParseStateEntries[V],
  f : (Symbol, V) -> Bool,
) -> Unit {
  let mut kept = 0
  for i in 0..<self.syms.length() {
    let symbol = self.syms[i]
    let value = self.vals[i]
    if f(symbol, value) {
      self.syms[kept] = symbol
      self.vals[kept] = value
      kept += 1
    }
  }
  self.syms.truncate(kept)
  self.vals.truncate(kept)
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
  let terminal_entries = self.terminal_entries
  for i in 0..<terminal_entries.len() {
    for action in pool.get(terminal_entries.value_at(i)) {
      if action is Shift(state~, ..) {
        result.push(state)
      }
    }
  }
  let nonterminal_entries = self.nonterminal_entries
  for i in 0..<nonterminal_entries.len() {
    if nonterminal_entries.value_at(i) is Goto(state) {
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
  let entries = self.nonterminal_entries
  // Pairs of an entry's index and its new target.
  let updates : Array[Int] = []
  for index in 0..<entries.len() {
    if entries.value_at(index) is Goto(other_state) {
      let result = f(other_state, self)
      if result != other_state {
        updates.push(index)
        updates.push(result)
      }
    }
  }
  for i in 0..<(updates.length() / 2) {
    entries.set_value_at(updates[2 * i], Goto(updates[2 * i + 1]))
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
    let entries = state.terminal_entries
    for i in 0..<entries.len() {
      referenced[entries.value_at(i).index] = true
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
