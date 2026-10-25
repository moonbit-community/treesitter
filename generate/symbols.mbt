// Port of the symbol types in tree-sitter crates/generate/src/rules.rs.

///|
/// Declaration order is significant: it defines the derived ordering, which
/// matches upstream's `#[derive(Ord)]` on `SymbolType`.
pub(all) enum SymbolType {
  External
  End
  EndOfNonTerminalExtra
  Terminal
  NonTerminal
} derive(Eq, Hash, Compare, Debug)

///|
pub(all) enum Associativity {
  Left
  Right
} derive(Eq, Hash, Compare, Debug)

///|
pub(all) struct Alias {
  value : StrId
  is_named : Bool
} derive(Eq, Hash, Compare, Debug)

///|
pub fn Alias::kind(self : Alias) -> VariableType {
  if self.is_named {
    Named
  } else {
    Anonymous
  }
}

///|
pub(all) enum Precedence {
  /// Upstream `Precedence::None`.
  NoPrecedence
  Integer(Int)
  Name(StrId)
} derive(Eq, Hash, Compare, Debug)

///|
/// A grammar symbol: a kind together with that kind's index into its own table.
#valtype
pub(all) struct Symbol {
  kind : SymbolType
  index : Int
} derive(Eq, Compare, Debug)

///|
pub impl Hash for Symbol with hash_combine(self, hasher) {
  hasher.combine(self.kind)
  hasher.combine_int(self.index)
}

///|
/// Without `Hasher`'s allocation: symbols key many hot maps.
pub impl Hash for Symbol with hash(self) {
  hash_finish(hash_mix(hash_mix(HASH_SEED, self.kind.ordinal()), self.index))
}

///|
/// The position of this kind in declaration order.
fn SymbolType::ordinal(self : SymbolType) -> Int {
  match self {
    External => 0
    End => 1
    EndOfNonTerminalExtra => 2
    Terminal => 3
    NonTerminal => 4
  }
}

///|
/// A hash code for a symbol. Distinct only for indices below 2^28, so it
/// must not be used as a lossless map key.
fn Symbol::code(self : Symbol) -> Int {
  (self.kind.ordinal() << 28) | self.index
}

///|
pub let symbol_end : Symbol = { kind: End, index: 0 }

///|
pub let symbol_end_of_nonterminal_extra : Symbol = {
  kind: EndOfNonTerminalExtra,
  index: 0,
}

///|
pub fn Symbol::non_terminal(index : Int) -> Symbol {
  { kind: NonTerminal, index }
}

///|
pub fn Symbol::terminal(index : Int) -> Symbol {
  { kind: Terminal, index }
}

///|
pub fn Symbol::external(index : Int) -> Symbol {
  { kind: External, index }
}

///|
pub fn Symbol::is_non_terminal(self : Symbol) -> Bool {
  self.kind is NonTerminal
}

///|
pub fn Symbol::is_terminal(self : Symbol) -> Bool {
  self.kind is Terminal
}

///|
pub fn Symbol::is_external(self : Symbol) -> Bool {
  self.kind is External
}

///|
pub fn Symbol::is_eof(self : Symbol) -> Bool {
  self.kind is End
}

///|
pub fn Symbol::external_index(self : Symbol) -> Int? {
  if self.kind is External {
    Some(self.index)
  } else {
    None
  }
}

///|
pub fn Symbol::terminal_index(self : Symbol) -> Int? {
  if self.kind is Terminal {
    Some(self.index)
  } else {
    None
  }
}

///|
pub fn Symbol::non_terminal_index(self : Symbol) -> Int? {
  if self.kind is NonTerminal {
    Some(self.index)
  } else {
    None
  }
}

///|
/// A set of terminal, external and end tokens.
pub struct TokenSet {
  priv terminal_bits : BitVec
  priv external_bits : BitVec
  priv mut eof : Bool
  priv mut end_of_nonterminal_extra : Bool
}

///|
pub fn TokenSet::new() -> TokenSet {
  {
    terminal_bits: BitVec::new(),
    external_bits: BitVec::new(),
    eof: false,
    end_of_nonterminal_extra: false,
  }
}

///|
pub fn TokenSet::copy(self : TokenSet) -> TokenSet {
  {
    terminal_bits: self.terminal_bits.copy(),
    external_bits: self.external_bits.copy(),
    eof: self.eof,
    end_of_nonterminal_extra: self.end_of_nonterminal_extra,
  }
}

///|
pub fn TokenSet::from_array(symbols : Array[Symbol]) -> TokenSet {
  let result = TokenSet::new()
  for symbol in symbols {
    result.insert(symbol)
  }
  result
}

///|
/// Terminals, then externals, then EOF, then the end of a non-terminal extra.
pub fn TokenSet::iter(self : TokenSet) -> Array[Symbol] {
  let result = []
  for i in set_bits(self.terminal_bits.words()) {
    result.push(Symbol::terminal(i))
  }
  for i in set_bits(self.external_bits.words()) {
    result.push(Symbol::external(i))
  }
  if self.eof {
    result.push(symbol_end)
  }
  if self.end_of_nonterminal_extra {
    result.push(symbol_end_of_nonterminal_extra)
  }
  result
}

///|
pub fn TokenSet::terminals(self : TokenSet) -> Array[Int] {
  set_bits(self.terminal_bits.words())
}

///|
pub fn TokenSet::externals(self : TokenSet) -> Array[Int] {
  set_bits(self.external_bits.words())
}

///|
pub fn TokenSet::terminal_bits_words(self : TokenSet) -> Array[UInt64] {
  self.terminal_bits.words()
}

///|
pub fn TokenSet::contains(self : TokenSet, symbol : Symbol) -> Bool {
  match symbol.kind {
    NonTerminal => abort("Cannot store non-terminals in a TokenSet")
    Terminal => self.terminal_bits.get(symbol.index).unwrap_or(false)
    External => self.external_bits.get(symbol.index).unwrap_or(false)
    End => self.eof
    EndOfNonTerminalExtra => self.end_of_nonterminal_extra
  }
}

///|
pub fn TokenSet::contains_terminal(self : TokenSet, index : Int) -> Bool {
  self.terminal_bits.get(index).unwrap_or(false)
}

///|
pub fn TokenSet::insert(self : TokenSet, other : Symbol) -> Unit {
  let vec = match other.kind {
    NonTerminal => abort("Cannot store non-terminals in a TokenSet")
    Terminal => self.terminal_bits
    External => self.external_bits
    End => {
      self.eof = true
      return
    }
    EndOfNonTerminalExtra => {
      self.end_of_nonterminal_extra = true
      return
    }
  }
  if other.index >= vec.len() {
    vec.resize(other.index + 1, false)
  }
  vec.set(other.index, true)
}

///|
pub fn TokenSet::remove(self : TokenSet, other : Symbol) -> Bool {
  let vec = match other.kind {
    NonTerminal => abort("Cannot store non-terminals in a TokenSet")
    Terminal => self.terminal_bits
    External => self.external_bits
    End =>
      return if self.eof {
        self.eof = false
        true
      } else {
        false
      }
    EndOfNonTerminalExtra =>
      return if self.end_of_nonterminal_extra {
        self.end_of_nonterminal_extra = false
        true
      } else {
        false
      }
  }
  if other.index < vec.len() && vec.at(other.index) {
    vec.set(other.index, false)
    while vec.last() == Some(false) {
      ignore(vec.pop())
    }
    return true
  }
  false
}

///|
pub fn TokenSet::is_empty(self : TokenSet) -> Bool {
  if self.eof || self.end_of_nonterminal_extra {
    return false
  }
  for w in self.terminal_bits.words() {
    if w != 0 {
      return false
    }
  }
  for w in self.external_bits.words() {
    if w != 0 {
      return false
    }
  }
  true
}

///|
pub fn TokenSet::len(self : TokenSet) -> Int {
  let mut n = (if self.eof { 1 } else { 0 }) +
    (if self.end_of_nonterminal_extra { 1 } else { 0 })
  for w in self.terminal_bits.words() {
    n += w.popcnt()
  }
  for w in self.external_bits.words() {
    n += w.popcnt()
  }
  n
}

///|
pub fn TokenSet::insert_all_terminals(
  self : TokenSet,
  other : TokenSet,
) -> Bool {
  self.terminal_bits.insert_all(other.terminal_bits)
}

///|
pub fn TokenSet::insert_all(self : TokenSet, other : TokenSet) -> Bool {
  let mut result = false
  if other.eof {
    result = result || !self.eof
    self.eof = true
  }
  if other.end_of_nonterminal_extra {
    result = result || !self.end_of_nonterminal_extra
    self.end_of_nonterminal_extra = true
  }
  if self.terminal_bits.insert_all(other.terminal_bits) {
    result = true
  }
  if self.external_bits.insert_all(other.external_bits) {
    result = true
  }
  result
}

///|
pub impl Eq for TokenSet with equal(self, other) {
  self.terminal_bits == other.terminal_bits &&
  self.external_bits == other.external_bits &&
  self.eof == other.eof &&
  self.end_of_nonterminal_extra == other.end_of_nonterminal_extra
}

///|
pub impl Hash for TokenSet with hash_combine(self, hasher) {
  self.terminal_bits.hash_combine(hasher)
  self.external_bits.hash_combine(hasher)
  hasher.combine_bool(self.eof)
  hasher.combine_bool(self.end_of_nonterminal_extra)
}

///|
pub impl Compare for TokenSet with compare(self, other) {
  let c = self.terminal_bits.compare(other.terminal_bits)
  if c != 0 {
    return c
  }
  let c = self.external_bits.compare(other.external_bits)
  if c != 0 {
    return c
  }
  let c = self.eof.compare(other.eof)
  if c != 0 {
    return c
  }
  self.end_of_nonterminal_extra.compare(other.end_of_nonterminal_extra)
}

///|
pub impl Debug for TokenSet with to_repr(self) {
  @debug.Repr(self.iter())
}
