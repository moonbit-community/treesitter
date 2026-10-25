// Port of tree-sitter crates/generate/src/build_tables/item.rs.

///|
let start_steps : Array[ProductionStep] = [
  ProductionStep::pack(
    Symbol::non_terminal(0),
    NoPrecedence,
    None,
    None,
    None,
    no_reserved_words,
  ),
]

///|
/// Upstream `START_PRODUCTION_ID` (`u32::MAX`). Production ids are never
/// ordered, so any value outside the grammar's ids works.
let start_production_id : Int32 = -1

///|
/// Upstream's augmented start item has `variable_index == u32::MAX`, which
/// orders after every real variable index. This keeps that order.
let augmented_variable_index : Int32 = 0x7FFFFFFF

///|
fn start_production() -> ProdRef {
  {
    steps: start_steps[:],
    dynamic_precedence: 0,
    requires_eof_lookahead: false,
  }
}

///|
/// Precomputed identity keys for one `(production, dot)` pair.
///
/// `cmp` is the rank of the content tuple `Ord` compared (dynamic precedence,
/// `requires_eof_lookahead`, length, precedence/associativity at the dot, then
/// completed steps' aliases and fields and remaining steps in full). Equal ranks
/// hold _exactly_ when the tuple is equal, so it doubles as the equality class
/// for items without preceding inherited fields. `eq_with_syms` subdivides `cmp`
/// by the completed steps' symbols, which participate in equality only when
/// `has_preceding_inherited_fields` is set.
priv struct DotKeys {
  mut cmp : Int32
  mut eq_with_syms : Int32
  /// Where the production's steps start in the grammar's `steps` (or in
  /// `start_steps`, for the augmented start production). (Not a key: cached here
  /// so that items can find their steps.)
  steps_start : Int32
}

///|
/// Identity keys for every `(production, dot)` in a grammar (all grammar productions,
/// every inlined production, and the augmented start production).
priv struct ItemKeyMap {
  keys : Array[FixedArray[DotKeys]]
  start : FixedArray[DotKeys]
}

///|
fn ItemKeyMap::new(grammar : SyntaxGrammar, str_pool : StrPool) -> ItemKeyMap {
  let prod = (slot : Int32) => {
    if slot == 0 {
      start_production()
    } else {
      grammar.production(slot - 1)
    }
  }
  let slot_count = grammar.productions.length() + 1
  let contents : Array[(Int32, Int32)] = []
  for pi in 0..<slot_count {
    for dot in 0..<=prod(pi).steps.length() {
      contents.push((pi, dot))
    }
  }
  let content = (pair : (Int32, Int32)) => ItemContent::{
    production: prod(pair.0),
    dot: pair.1,
    str_pool,
  }
  // Upstream sorts with `sort_unstable_by`. Pairs with equal content tie, and
  // their order decides how `eq_with_syms` numbers their symbol classes below.
  rust_sort_unstable_by(contents, (a, b) => content(a).cmp(content(b)) < 0)
  let slot_keys : Array[FixedArray[DotKeys]] = Array::makei(slot_count, pi => {
    let steps_start = if pi == 0 {
      0
    } else {
      grammar.productions[pi - 1].steps_start
    }
    FixedArray::makei(prod(pi).steps.length() + 1, _ => {
      cmp: 0,
      eq_with_syms: 0,
      steps_start,
    })
  })
  // Dense ids in sorted order: equal content shares an id, distinct content gets the next up
  let mut cmp_id = 0
  let mut prev : (Int32, Int32)? = None
  for pair in contents {
    if prev is Some(p) && content(p).cmp(content(pair)) != 0 {
      cmp_id += 1
    }
    slot_keys[pair.0][pair.1].cmp = cmp_id
    prev = Some(pair)
  }

  // Refine each cmp class by preceding symbols:  read only under
  // `has_preceding_inherited_fields`.
  let sym_classes : Map[(Int32, Array[Symbol]), Int32] = Map([])
  for pair in contents {
    let (pi, dot) = pair
    let steps = prod(pi).steps
    let syms = Array::makei(dot, i => steps[i].symbol)
    let next = sym_classes.length()
    let keys = slot_keys[pi][dot]
    keys.eq_with_syms = sym_classes.get_or_init((keys.cmp, syms), () => next)
  }
  let start = slot_keys.remove(0)
  { keys: slot_keys, start, }
}

///|
/// The keys slice (indexed by `dot`) for a production of this grammar.
fn ItemKeyMap::keys_for(self : ItemKeyMap, id : Int32) -> FixedArray[DotKeys] {
  if id == start_production_id {
    self.start
  } else {
    self.keys[id]
  }
}

///|
fn ItemKeyMap::start_keys(self : ItemKeyMap) -> FixedArray[DotKeys] {
  self.start
}

///|
/// The content tuple that `ParseItem`'s `Ord` (and flagless `Eq`) observe, evaluated on
/// `(production, dot)` directly. Ranking the set of all keys by this order makes
/// the dense `cmp` order-preserving. Item ordering only ever compares same-dot pairs,
/// and the dot comparison keeps the order total across dots so ranks are well defined.
priv struct ItemContent {
  production : ProdRef
  dot : Int32
  str_pool : StrPool
}

///|
fn ItemContent::prec(self : ItemContent) -> Precedence {
  if self.dot > 0 {
    self.production.steps[self.dot - 1].precedence
  } else {
    NoPrecedence
  }
}

///|
fn ItemContent::assoc(self : ItemContent) -> Associativity? {
  if self.dot > 0 {
    self.production.steps[self.dot - 1].associativity
  } else {
    None
  }
}

///|
fn ItemContent::prec_cmp(
  self : ItemContent,
  a : Precedence,
  b : Precedence,
) -> Int32 {
  match (a, b) {
    (NoPrecedence, NoPrecedence) => 0
    (Integer(a), Integer(b)) => a.compare(b)
    (Name(a), Name(b)) =>
      rust_str_cmp(self.str_pool.resolve(a), self.str_pool.resolve(b))
    (NoPrecedence, _) | (Integer(_), Name(_)) => -1
    (_, NoPrecedence) | (Name(_), Integer(_)) => 1
  }
}

///|
fn ItemContent::alias_cmp(
  self : ItemContent,
  a : ProductionStep,
  b : ProductionStep,
) -> Int32 {
  match (a.alias, b.alias) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) => {
      let c = rust_str_cmp(
        self.str_pool.resolve(x.value),
        self.str_pool.resolve(y.value),
      )
      if c != 0 {
        c
      } else {
        x.is_named.compare(y.is_named)
      }
    }
  }
}

///|
fn ItemContent::field_cmp(
  self : ItemContent,
  a : ProductionStep,
  b : ProductionStep,
) -> Int32 {
  match (a.field, b.field) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) =>
      rust_str_cmp(self.str_pool.resolve(x), self.str_pool.resolve(y))
  }
}

///|
fn ItemContent::step_cmp(
  self : ItemContent,
  a : ProductionStep,
  b : ProductionStep,
) -> Int32 {
  let c = a.symbol.compare(b.symbol)
  if c != 0 {
    return c
  }
  let c = self.prec_cmp(a.precedence, b.precedence)
  if c != 0 {
    return c
  }
  let c = assoc_cmp(a.associativity, b.associativity)
  if c != 0 {
    return c
  }
  let c = self.alias_cmp(a, b)
  if c != 0 {
    return c
  }
  let c = self.field_cmp(a, b)
  if c != 0 {
    return c
  }
  a.reserved.compare(b.reserved)
}

///|
/// Rust's derived `Ord` for `Option<Associativity>`.
fn assoc_cmp(a : Associativity?, b : Associativity?) -> Int32 {
  match (a, b) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) => x.compare(y)
  }
}

///|
/// Rust's `str` ordering: lexicographic by UTF-8 bytes, which is the order of
/// code points. UTF-16 code units are remapped so that surrogates (which only
/// encode code points above U+FFFF) order after U+E000..U+FFFF.
fn rust_str_cmp(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a[i].to_int()
    let y = b[i].to_int()
    if x != y {
      return utf16_order_key(x).compare(utf16_order_key(y))
    }
  }
  a.length().compare(b.length())
}

///|
fn utf16_order_key(unit : Int32) -> Int32 {
  if unit >= 0xE000 {
    unit - 0x800
  } else if unit >= 0xD800 {
    unit + 0x2000
  } else {
    unit
  }
}

///|
fn ItemContent::cmp(self : ItemContent, other : ItemContent) -> Int32 {
  let c = self.production.dynamic_precedence.compare(
    other.production.dynamic_precedence,
  )
  if c != 0 {
    return c
  }
  let c = self.production.requires_eof_lookahead.compare(
    other.production.requires_eof_lookahead,
  )
  if c != 0 {
    return c
  }
  let c = self.production.steps
    .length()
    .compare(other.production.steps.length())
  if c != 0 {
    return c
  }
  let c = self.prec_cmp(self.prec(), other.prec())
  if c != 0 {
    return c
  }
  let c = assoc_cmp(self.assoc(), other.assoc())
  if c != 0 {
    return c
  }
  let c = self.dot.compare(other.dot)
  if c != 0 {
    return c
  }
  let steps_a = self.production.steps
  let steps_b = other.production.steps
  for i in 0..<steps_a.length() {
    let sa = steps_a[i]
    let sb = steps_b[i]
    let o = if i < self.dot {
      let o = self.alias_cmp(sa, sb)
      if o != 0 {
        o
      } else {
        self.field_cmp(sa, sb)
      }
    } else {
      self.step_cmp(sa, sb)
    }
    if o != 0 {
      return o
    }
  }
  0
}

///|
/// A `ParseItem` represents an in-progress match of a single production in a grammar.
/// Stored by value, like upstream's `Copy` item.
#valtype
priv struct ParseItem {
  /// The index of the parent rule within the grammar.
  variable_index : Int32
  /// The number of symbols that have already been matched.
  step_index : Int32
  /// The id of the production being matched.
  prod_id : Int32
  /// Where the production's steps start in the grammar's `steps` (or in
  /// `start_steps`, for the augmented start production).
  steps_start : Int32
  /// The number of steps in the production.
  steps_len : Int32
  /// A boolean indicating whether any of the already-matched children were
  /// hidden nodes and had fields. Ordinarily, a parse item's behavior is not
  /// affected by the symbols of its preceding children; it only needs to
  /// keep track of their fields and aliases.
  ///
  /// Take for example these two items:
  ///   X -> a b • c
  ///   X -> a g • c
  ///
  /// They can be considered equivalent, for the purposes of parse table
  /// generation, because they entail the same actions. But if this flag is
  /// true, then the item's set of inherited fields may depend on the specific
  /// symbols of its preceding children.
  has_preceding_inherited_fields : Bool
  /// The production's identity keys at `step_index`, copied here so that
  /// comparing items doesn't have to look them up.
  dot_cmp : Int32
  /// See `dot_cmp`.
  dot_eq_with_syms : Int32
}

///|
fn ParseItem::new(
  variable_index~ : Int32,
  prod_id~ : Int32,
  keys~ : FixedArray[DotKeys],
  step_index~ : Int32,
  has_preceding_inherited_fields~ : Bool,
) -> ParseItem {
  {
    variable_index,
    prod_id,
    steps_start: keys[0].steps_start,
    steps_len: keys.length() - 1,
    step_index,
    has_preceding_inherited_fields,
    dot_cmp: keys[step_index].cmp,
    dot_eq_with_syms: keys[step_index].eq_with_syms,
  }
}

///|
/// Interned lookahead set ids are plain indices into a `LookaheadSetPool`. Ids
/// are canonical, so id equality is equivalent to underlying `TokenSet` equality.
let lookahead_set_pool_empty : Int32 = 0

///|
/// Interner for lookahead `TokenSet`s. Item-set entries store ids.
priv struct LookaheadSetPool {
  sets : Array[TokenSet]
  ids : Map[TokenSet, Int32]
  /// Keyed by both ids, packed (smaller first).
  union_memo : Map[Int64, Int32]
  /// Keyed by `insert_memo_key`: the id and the complete symbol, packed.
  insert_memo : Map[Int64, Int32]
  /// `insert_memo` for the (in practice unreachable) ids that do not fit
  /// in `insert_memo_key`.
  insert_memo_wide : Map[(Int32, Int32, Int32), Int32]
  /// Each set's `TokenSet::iter`, by id, once asked for.
  symbol_lists : Array[Array[Symbol]?]
}

///|
fn LookaheadSetPool::new() -> LookaheadSetPool {
  let pool = {
    sets: [],
    ids: {},
    union_memo: {},
    insert_memo: {},
    insert_memo_wide: {},
    symbol_lists: [],
  }
  ignore(pool.intern(TokenSet::new()))
  pool
}

///|
fn LookaheadSetPool::get(self : LookaheadSetPool, id : Int32) -> TokenSet {
  self.sets[id]
}

///|
/// The symbols of the set with this id, as `TokenSet::iter` lists them. The
/// list is shared: callers must not change it.
fn LookaheadSetPool::symbols(
  self : LookaheadSetPool,
  id : Int32,
) -> Array[Symbol] {
  match self.symbol_lists[id] {
    Some(symbols) => symbols
    None => {
      let symbols = self.sets[id].iter()
      self.symbol_lists[id] = Some(symbols)
      symbols
    }
  }
}

///|
/// Interns `set`, which the pool takes ownership of.
fn LookaheadSetPool::intern(self : LookaheadSetPool, set : TokenSet) -> Int32 {
  match self.ids.get(set) {
    Some(index) => index
    None => {
      let index = self.sets.length()
      self.sets.push(set)
      self.symbol_lists.push(None)
      self.ids[set] = index
      index
    }
  }
}

///|
fn LookaheadSetPool::intern_ref(
  self : LookaheadSetPool,
  set : TokenSet,
) -> Int32 {
  match self.ids.get(set) {
    Some(index) => index
    None => self.intern(set.copy())
  }
}

///|
fn LookaheadSetPool::singleton(
  self : LookaheadSetPool,
  symbol : Symbol,
) -> Int32 {
  self.insert(lookahead_set_pool_empty, symbol)
}

///|
fn LookaheadSetPool::insert(
  self : LookaheadSetPool,
  id : Int32,
  symbol : Symbol,
) -> Int32 {
  if self.get(id).contains(symbol) {
    return id
  }
  // Upstream keys the memo by `(id, symbol)`; the packed key must be
  // lossless (`Symbol::code` is not: it only has 28 index bits).
  if id >= INSERT_MEMO_MAX_ID {
    let key = (id, symbol.kind.ordinal(), symbol.index)
    if self.insert_memo_wide.get(key) is Some(result) {
      return result
    }
    let set = self.get(id).copy()
    set.insert(symbol)
    let result = self.intern(set)
    self.insert_memo_wide[key] = result
    return result
  }
  let key = insert_memo_key(id, symbol)
  if self.insert_memo.get(key) is Some(result) {
    return result
  }
  let set = self.get(id).copy()
  set.insert(symbol)
  let result = self.intern(set)
  self.insert_memo[key] = result
  result
}

///|
/// Ids below this bound pack losslessly into `insert_memo_key`.
const INSERT_MEMO_MAX_ID : Int32 = 0x20000000

///|
/// `(id, symbol)` packed into 64 bits: 29 bits of id, 3 bits of symbol kind
/// and the 31 bits of a non-negative symbol index.
fn insert_memo_key(id : Int32, symbol : Symbol) -> Int64 {
  (id.to_int64() << 34) |
  (symbol.kind.ordinal().to_int64() << 31) |
  symbol.index.to_int64()
}

///|
fn LookaheadSetPool::union(
  self : LookaheadSetPool,
  left : Int32,
  right : Int32,
) -> Int32 {
  if left == right || right == lookahead_set_pool_empty {
    return left
  }
  if left == lookahead_set_pool_empty {
    return right
  }
  let (low, high) = if left < right { (left, right) } else { (right, left) }
  let key = (low.to_int64() << 32) | high.to_int64()
  if self.union_memo.get(key) is Some(result) {
    return result
  }
  let set = self.get(low).copy()
  ignore(set.insert_all(self.get(high)))
  let result = self.intern(set)
  self.union_memo[key] = result
  result
}

///|
/// Represents a set of in-progress matches of productions in a grammar.
///
/// For each in-progress match, a set of "lookaheads" (tokens that are allowed to
/// *follow* the in-progress rule) are included. This object corresponds directly
/// to a state in the final parse table.
priv struct ParseItemSet {
  entries : Array[ParseItemSetEntry]
}

///|
priv struct ParseItemSetEntry {
  /// Only changes when an entry of a discarded set is reused.
  mut item : ParseItem
  mut lookaheads : Int32
  mut following_reserved_word_set : Int32
}

///|
/// A `ParseItemSetCore` is like a `ParseItemSet`, but without the lookahead
/// information. Parse states with the same core are candidates for merging.
priv struct ParseItemSetCore {
  entries : Array[ParseItem]
}

///|
fn ParseItemSet::new() -> ParseItemSet {
  { entries: [], }
}

///|
fn ParseItem::start(key_map : ItemKeyMap) -> ParseItem {
  ParseItem::new(
    variable_index=augmented_variable_index,
    prod_id=start_production_id,
    keys=key_map.start_keys(),
    step_index=0,
    has_preceding_inherited_fields=false,
  )
}

///|
/// The production being matched.
fn ParseItem::production(self : ParseItem, grammar : SyntaxGrammar) -> ProdRef {
  if self.prod_id == start_production_id {
    start_production()
  } else {
    grammar.production(self.prod_id)
  }
}

///|
fn ParseItem::step(
  self : ParseItem,
  grammar : SyntaxGrammar,
) -> ProductionStep? {
  self.step_at(grammar, self.step_index)
}

///|
/// `production(grammar).steps.get(index)` without building a `ProdRef`.
fn ParseItem::step_at(
  self : ParseItem,
  grammar : SyntaxGrammar,
  index : Int32,
) -> ProductionStep? {
  if index >= 0 && index < self.steps_len {
    if self.prod_id == start_production_id {
      Some(start_steps[index])
    } else {
      Some(grammar.steps[self.steps_start + index])
    }
  } else {
    None
  }
}

///|
fn ParseItem::symbol(self : ParseItem, grammar : SyntaxGrammar) -> Symbol? {
  match self.step(grammar) {
    Some(step) => Some(step.symbol)
    None => None
  }
}

///|
fn ParseItem::associativity(
  self : ParseItem,
  grammar : SyntaxGrammar,
) -> Associativity? {
  match self.prev_step(grammar) {
    Some(step) => step.associativity
    None => None
  }
}

///|
fn ParseItem::precedence(
  self : ParseItem,
  grammar : SyntaxGrammar,
) -> Precedence {
  match self.prev_step(grammar) {
    Some(step) => step.precedence
    None => NoPrecedence
  }
}

///|
fn ParseItem::prev_step(
  self : ParseItem,
  grammar : SyntaxGrammar,
) -> ProductionStep? {
  if self.step_index > 0 {
    self.step_at(grammar, self.step_index - 1)
  } else {
    None
  }
}

///|
fn ParseItem::is_done(self : ParseItem) -> Bool {
  self.step_index == self.steps_len
}

///|
fn ParseItem::is_augmented(self : ParseItem) -> Bool {
  self.variable_index == augmented_variable_index
}

///|
/// Create an item like this one, but advanced by one step.
fn ParseItem::successor(self : ParseItem, key_map : ItemKeyMap) -> ParseItem {
  let step_index = self.step_index + 1
  let keys = key_map.keys_for(self.prod_id)[step_index]
  {
    ..self,
    step_index,
    dot_cmp: keys.cmp,
    dot_eq_with_syms: keys.eq_with_syms,
  }
}

///|
/// `ParseItem { has_preceding_inherited_fields: true, ..self }`.
fn ParseItem::with_preceding_inherited_fields(self : ParseItem) -> ParseItem {
  if self.has_preceding_inherited_fields {
    return self
  }
  { ..self, has_preceding_inherited_fields: true }
}

///|
/// Create an item identical to this one, but with a different production.
/// This is used when dynamically "inlining" certain symbols in a production.
fn ParseItem::substitute_production(
  self : ParseItem,
  prod_id : Int32,
  keys : FixedArray[DotKeys],
) -> ParseItem {
  ParseItem::new(
    variable_index=self.variable_index,
    prod_id~,
    keys~,
    step_index=self.step_index,
    has_preceding_inherited_fields=self.has_preceding_inherited_fields,
  )
}

///|
fn ParseItemSet::insert(
  self : ParseItemSet,
  item : ParseItem,
) -> ParseItemSetEntry {
  self.insert_reusing(item, [])
}

///|
/// `Self::insert`, taking a new entry from `spares` if it has one.
fn ParseItemSet::insert_reusing(
  self : ParseItemSet,
  item : ParseItem,
  spares : Array[ParseItemSetEntry],
) -> ParseItemSetEntry {
  // `entries` is sorted with no duplicates, so an item that sorts after the last entry
  // belongs at the end, which is where the binary search would put it.
  //
  // Checking the end first pays off because items mostly arrive in order: `add_actions`
  // builds each successor set by advancing a sorted closure's items past the same symbol.
  // Items are ordered by step index, then rule, then their content at the dot. Advancing
  // adds one to every step index and keeps every rule, so only items of the same rule at
  // the same step can change places.
  let index = match self.entries.last() {
    None => self.entries.length()
    Some(last) if Compare::compare(last.item, item) < 0 => self.entries.length()
    _ =>
      match self.entries.binary_search_by(e => Compare::compare(e.item, item)) {
        Ok(i) => return self.entries[i]
        Err(i) => i
      }
  }
  let entry = match spares.pop() {
    Some(entry) => {
      entry.item = item
      entry.lookaheads = lookahead_set_pool_empty
      entry.following_reserved_word_set = 0
      entry
    }
    None =>
      {
        item,
        lookaheads: lookahead_set_pool_empty,
        following_reserved_word_set: 0,
      }
  }
  self.entries.insert(index, entry)
  entry
}

///|
fn ParseItemSet::core(self : ParseItemSet) -> ParseItemSetCore {
  { entries: self.entries.map(e => e.item), }
}

///|
fn prec_display(prec : Precedence, str_pool : StrPool) -> String {
  match prec {
    NoPrecedence => "none"
    Integer(i) => i.to_string()
    Name(sid) => "'\{str_pool.resolve(sid)}'"
  }
}

///|
fn assoc_debug(assoc : Associativity) -> String {
  match assoc {
    Left => "Left"
    Right => "Right"
  }
}

///|
/// Upstream `ParseItemDisplay`.
fn ParseItem::display(
  self : ParseItem,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  str_pool : StrPool,
) -> String {
  let f = StringBuilder()
  if self.is_augmented() {
    f.write_string("START →")
  } else {
    f.write_string(
      "\{str_pool.resolve(syntax_grammar.variables[self.variable_index].name)} →",
    )
  }
  let production = self.production(syntax_grammar)
  for i, step in production.steps {
    let symbol = step.symbol
    if i == self.step_index {
      f.write_string(" •")
      if step.precedence != NoPrecedence ||
        step.associativity is Some(_) ||
        step.reserved != 0 {
        f.write_string(" (")
        if step.precedence != NoPrecedence {
          f.write_string(" \{prec_display(step.precedence, str_pool)}")
        }
        if step.associativity is Some(associativity) {
          f.write_string(" \{assoc_debug(associativity)}")
        }
        if step.reserved != 0 {
          f.write_string("reserved: \{step.reserved}")
        }
        f.write_string(" )")
      }
    }
    f.write_string(" ")
    match symbol.kind {
      Terminal =>
        match lexical_grammar.variables.get(symbol.index) {
          Some(variable) => f.write_string(str_pool.resolve(variable.name))
          None => f.write_string("terminal-\{symbol.index}")
        }
      External =>
        f.write_string(
          str_pool.resolve(syntax_grammar.external_tokens[symbol.index].name),
        )
      NonTerminal =>
        f.write_string(
          str_pool.resolve(syntax_grammar.variables[symbol.index].name),
        )
      End => f.write_string("<EOF>")
      EndOfNonTerminalExtra => f.write_string("<END_OF_NONTERMINAL_EXTRA>")
    }
    if step.alias is Some(alias) {
      f.write_string("@\{str_pool.resolve(alias.value)}")
    }
  }
  if self.is_done() {
    f.write_string(" •")
    if production.steps.last() is Some(step) {
      if step.associativity is Some(associativity) {
        if step.precedence == NoPrecedence {
          f.write_string(" (\{assoc_debug(associativity)})")
        } else {
          f.write_string(
            " (\{prec_display(step.precedence, str_pool)} \{assoc_debug(associativity)})",
          )
        }
      } else if step.precedence != NoPrecedence {
        f.write_string(" (\{prec_display(step.precedence, str_pool)})")
      }
    }
  }
  f.to_string()
}

///|
fn escape_invisible(c : Char) -> String? {
  match c {
    '\n' => Some("\\n")
    '\r' => Some("\\r")
    '\t' => Some("\\t")
    '\u{0}' => Some("\\0")
    '\\' => Some("\\\\")
    '\u{0b}' => Some("\\v")
    '\u{0c}' => Some("\\f")
    _ => None
  }
}

///|
fn display_variable_name(source : String) -> String {
  let acc = StringBuilder()
  for c in source {
    match escape_invisible(c) {
      Some(esc) => acc.write_string(esc)
      None => acc.write_char(c)
    }
  }
  acc.to_string()
}

///|
/// Upstream `TokenSetDisplay`.
fn token_set_display(
  set : TokenSet,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  str_pool : StrPool,
) -> String {
  let f = StringBuilder()
  f.write_string("[")
  for i, symbol in set.iter() {
    if i > 0 {
      f.write_string(", ")
    }
    match symbol.kind {
      Terminal =>
        match lexical_grammar.variables.get(symbol.index) {
          Some(variable) =>
            f.write_string(
              display_variable_name(str_pool.resolve(variable.name)),
            )
          None => f.write_string("terminal-\{symbol.index}")
        }
      External =>
        f.write_string(
          str_pool.resolve(syntax_grammar.external_tokens[symbol.index].name),
        )
      NonTerminal =>
        f.write_string(
          str_pool.resolve(syntax_grammar.variables[symbol.index].name),
        )
      End => f.write_string("<EOF>")
      EndOfNonTerminalExtra => f.write_string("<END_OF_NONTERMINAL_EXTRA>")
    }
  }
  f.write_string("]")
  f.to_string()
}

///|
/// Upstream `ParseItemSetDisplay`.
fn ParseItemSet::display(
  self : ParseItemSet,
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  str_pool : StrPool,
  lookaheads : LookaheadSetPool,
) -> String {
  let f = StringBuilder()
  for entry in self.entries {
    f.write_string(
      entry.item.display(syntax_grammar, lexical_grammar, str_pool),
    )
    f.write_string("\t")
    f.write_string(
      token_set_display(
        lookaheads.get(entry.lookaheads),
        syntax_grammar,
        lexical_grammar,
        str_pool,
      ),
    )
    if entry.following_reserved_word_set != 0 {
      f.write_string(
        "\treserved word set: \{entry.following_reserved_word_set}",
      )
    }
    f.write_string("\n")
  }
  f.to_string()
}

///|
impl Hash for ParseItem with fn hash_combine(self, hasher) {
  hasher.combine_int(self.variable_index)
  hasher.combine_int(self.step_index)

  // The already-matched children don't play any role in the parse state for
  // this item, unless any of the following are true:
  //   * the children have fields
  //   * the children have aliases
  //   * the children are hidden and represent rules that have fields.
  // See the docs for `has_preceding_inherited_fields`.
  // Preceding symbols participate only in `eq_with_syms`.
  if self.has_preceding_inherited_fields {
    hasher.combine_int(1)
    hasher.combine_int(self.dot_eq_with_syms)
  } else {
    hasher.combine_int(0)
    hasher.combine_int(self.dot_cmp)
  }
}

///|
/// `hash_combine`'s fields, without `Hasher`'s allocation.
impl Hash for ParseItem with fn hash(self) {
  hash_finish(self.hash_acc(HASH_SEED))
}

///|
/// Mixes what `hash_combine` combines into `acc`.
fn ParseItem::hash_acc(self : ParseItem, acc : UInt32) -> UInt32 {
  let acc = hash_mix(hash_mix(acc, self.variable_index), self.step_index)
  if self.has_preceding_inherited_fields {
    hash_mix(hash_mix(acc, 1), self.dot_eq_with_syms)
  } else {
    hash_mix(hash_mix(acc, 0), self.dot_cmp)
  }
}

///|
impl Eq for ParseItem with fn equal(self, other) {
  if self.variable_index != other.variable_index ||
    self.step_index != other.step_index ||
    self.has_preceding_inherited_fields != other.has_preceding_inherited_fields {
    return false
  }
  if self.has_preceding_inherited_fields {
    self.dot_eq_with_syms == other.dot_eq_with_syms
  } else {
    self.dot_cmp == other.dot_cmp
  }
}

///|
impl Compare for ParseItem with fn compare(self, other) {
  let c = self.step_index.compare(other.step_index)
  if c != 0 {
    return c
  }
  let c = self.variable_index.compare(other.variable_index)
  if c != 0 {
    return c
  }
  let c = self.dot_cmp.compare(other.dot_cmp)
  if c != 0 {
    return c
  }
  let c = self.has_preceding_inherited_fields.compare(
    other.has_preceding_inherited_fields,
  )
  if c != 0 {
    return c
  }
  if self.has_preceding_inherited_fields {
    self.dot_eq_with_syms.compare(other.dot_eq_with_syms)
  } else {
    0
  }
}

///|
impl Eq for ParseItemSetEntry with fn equal(self, other) {
  self.item == other.item &&
  self.lookaheads == other.lookaheads &&
  self.following_reserved_word_set == other.following_reserved_word_set
}

///|
impl Eq for ParseItemSet with fn equal(self, other) {
  if self.entries.length() != other.entries.length() {
    return false
  }
  for i, entry in self.entries {
    if entry != other.entries[i] {
      return false
    }
  }
  true
}

///|
impl Hash for ParseItemSet with fn hash_combine(self, hasher) {
  hasher.combine_int(self.entries.length())
  for entry in self.entries {
    hasher.combine(entry.item)
    hasher.combine_int(entry.lookaheads)
    hasher.combine_int(entry.following_reserved_word_set)
  }
}

///|
impl Hash for ParseItemSet with fn hash(self) {
  let mut acc = hash_mix(HASH_SEED, self.entries.length())
  for entry in self.entries {
    acc = entry.item.hash_acc(acc)
    acc = hash_mix(
      hash_mix(acc, entry.lookaheads),
      entry.following_reserved_word_set,
    )
  }
  hash_finish(acc)
}

///|
impl Eq for ParseItemSetCore with fn equal(self, other) {
  if self.entries.length() != other.entries.length() {
    return false
  }
  for i, item in self.entries {
    if item != other.entries[i] {
      return false
    }
  }
  true
}

///|
impl Hash for ParseItemSetCore with fn hash_combine(self, hasher) {
  hasher.combine_int(self.entries.length())
  for item in self.entries {
    hasher.combine(item)
  }
}

///|
impl Hash for ParseItemSetCore with fn hash(self) {
  let mut acc = hash_mix(HASH_SEED, self.entries.length())
  for item in self.entries {
    acc = item.hash_acc(acc)
  }
  hash_finish(acc)
}
