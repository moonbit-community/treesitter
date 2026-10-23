///|
/// Symbols with actions or nonterminal transitions in a parse state, in symbol
/// order. Includes terminal extras, whose implicit transitions leave the state
/// unchanged. Invalid states have no lookaheads.
pub fn Language::lookahead(self : Language, state : Int32) -> Array[Int32] {
  guard self.states.get(state) is Some(row) else { return [] }
  let symbols : Map[Int32, Bool] = Map([])
  for symbol, actions in row.actions {
    if !actions.is_empty() {
      symbols[symbol] = true
    }
  }
  for symbol, _ in row.gotos {
    symbols[symbol] = true
  }
  for symbol in self.extras {
    if self.symbols[symbol].terminal {
      symbols[symbol] = true
    }
  }
  let result = symbols.keys().to_array()
  result.sort()
  result
}

///|
/// Inspect a shift or nonterminal transition without performing reductions.
/// Uses the last action in a conflict, as the upstream language API does.
/// Implicit terminal extras keep the current state. Nonterminal extras enter
/// their auxiliary table before shifting. None denotes an invalid input or a
/// transition that requires reduction/acceptance; state zero is a valid state.
pub fn Language::next_state(
  self : Language,
  state : Int32,
  symbol : Int32,
) -> Int32? {
  guard self.symbols.get(symbol) is Some(info) else { return None }
  guard self.states.get(state) is Some(row) else { return None }
  if !info.terminal {
    return row.gotos.get(symbol)
  }
  let mut current = state
  let visited : Map[Int32, Bool] = Map([])
  while !visited.contains(current) {
    visited[current] = true
    match self.states[current].actions.get(symbol) {
      Some(actions) =>
        match actions.last() {
          Some(Shift(next)) => return Some(next)
          Some(EnterExtra(next)) => current = next
          _ => return None
        }
      None =>
        return if self.extras.contains(symbol) { Some(current) } else { None }
    }
  }
  None
}

///|
/// A resettable iterator over a language's valid lookahead symbols. There is no
/// current symbol before the first successful advance or after exhaustion.
pub struct LookaheadIterator {
  priv mut language : Language
  priv mut symbols : Array[Int32]
  priv mut index : Int32
}

///|
pub fn Language::lookahead_iterator(
  self : Language,
  state : Int32,
) -> LookaheadIterator? {
  guard self.states.get(state) is Some(_) else { return None }
  Some({ language: self, symbols: self.lookahead(state), index: -1, })
}

///|
pub fn LookaheadIterator::language(self : LookaheadIterator) -> Language {
  self.language
}

///|
pub fn LookaheadIterator::next(self : LookaheadIterator) -> Int32? {
  if self.index < self.symbols.length() {
    self.index += 1
  }
  self.current_symbol()
}

///|
pub fn LookaheadIterator::current_symbol(self : LookaheadIterator) -> Int32? {
  self.symbols.get(self.index)
}

///|
pub fn LookaheadIterator::current_symbol_name(
  self : LookaheadIterator,
) -> String? {
  self.current_symbol().map(symbol => self.language.symbols[symbol].name)
}

///|
/// Reset the iterator and clear its current symbol. An invalid state leaves
/// the iterator, including its current position, unchanged.
pub fn LookaheadIterator::reset_state(
  self : LookaheadIterator,
  state : Int32,
) -> Bool {
  self.reset(self.language, state)
}

///|
/// Switch language and state. Invalid states leave the iterator unchanged.
pub fn LookaheadIterator::reset(
  self : LookaheadIterator,
  language : Language,
  state : Int32,
) -> Bool {
  guard language.states.get(state) is Some(_) else { return false }
  self.symbols = language.lookahead(state)
  self.language = language
  self.index = -1
  true
}
