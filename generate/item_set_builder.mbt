// Port of tree-sitter crates/generate/src/build_tables/item_set_builder.rs.

///|
priv struct TransitiveClosureAddition {
  item : ParseItem
  info : AdditionInfo
  /// `item`'s rank, which locates its entry in a closure.
  rank : Int32
}

///|
/// `FollowSetInfo` with an interned lookahead set and word-token membership precomputed.
priv struct AdditionInfo {
  lookaheads : Int32
  reserved_lookaheads : Int32
  propagates_lookaheads : Bool
  contains_word : Bool
} derive(Eq, Hash)

///|
/// the mutable accumulator for a non-terminal's follow set. `lookaheads` is a
/// working `TokenSet` that can be unioned incrementally during traversal, to be
/// interned into `AdditionInfo` once complete.
priv struct FollowSetInfo {
  lookaheads : TokenSet
  mut reserved_lookaheads : Int32
  mut propagates_lookaheads : Bool
}

///|
priv struct ParseItemSetBuilder {
  syntax_grammar : SyntaxGrammar
  first_sets : Map[Symbol, TokenSet]
  /// Gives each symbol its slot in `first_set_ids` and `reserved_first_set_ids`.
  symbol_indexer : SymbolIndexer
  /// Each FIRST set interned, for closure propagation by id, by
  /// `SymbolIndexer::index`.
  mut first_set_ids : FixedArray[Int32]
  reserved_first_sets : Map[Symbol, Int32]
  /// `reserved_first_sets`, by `SymbolIndexer::index`.
  mut reserved_first_set_ids : FixedArray[Int32]
  last_sets : Map[Symbol, TokenSet]
  /// Upstream's `inlines`: the inlined production map, keyed by production id and
  /// step index packed into one key.
  inlined_prod_ids_by_key : Map[Int64, Array[Int32]]
  key_map : ItemKeyMap
  lookaheads : LookaheadSetPool
  mut transitive_closure_additions : Array[Array[TransitiveClosureAddition]]
  /// Scratch for `Self::transitive_closure`.
  mut closure_scratch : ClosureEntries
}

///|
/// Pushes `value` unless `vector` already has it. `indices` holds the
/// elements of `vector`, for the lookup.
fn push_unique(
  vector : Array[(ParseItem, AdditionInfo)],
  indices : Map[(ParseItem, AdditionInfo), Unit],
  value : (ParseItem, AdditionInfo),
) -> Unit {
  if !indices.contains(value) {
    indices[value] = ()
    vector.push(value)
  }
}

///|
/// Everything that `ParseItem`'s `Eq` and `Ord` compare between items at their first step,
/// which have nothing before their dot. The fields are in the order that `Ord`
/// compares them, so the derived `Ord` orders keys the way it orders their items.
priv struct FirstStepKey {
  variable_index : Int32
  /// `keys[0].cmp`.
  cmp : Int32
} derive(Eq, Compare, Hash)

///|
fn FirstStepKey::new(item : ParseItem) -> FirstStepKey {
  // INVARIANT: only items at their first step are ranked
  guard item.step_index == 0 && !item.has_preceding_inherited_fields else {
    abort("only items at their first step are ranked")
  }
  { variable_index: item.variable_index, cmp: item.dot_cmp, }
}

///|
/// The rank (an item's position among all the items that a closure can hold at their first
/// step, in item order) of every item that a closure can hold at its first step, by key.
priv struct FirstStepRanks(Map[FirstStepKey, Int32])

///|
/// Ranks `items`, which are all at their first step.
fn FirstStepRanks::new(items : Array[ParseItem]) -> FirstStepRanks {
  let keys = items.map(FirstStepKey::new)
  keys.sort()
  dedup(keys)
  let map = Map([])
  for rank, key in keys {
    map[key] = rank
  }
  FirstStepRanks(map)
}

///|
fn FirstStepRanks::len(self : FirstStepRanks) -> Int32 {
  self.0.length()
}

///|
/// The rank of `item`, which must be one of the items these were built from.
fn FirstStepRanks::rank(self : FirstStepRanks, item : ParseItem) -> Int32 {
  // INVARIANT: every item at its first step has a rank
  self.0.get(FirstStepKey::new(item)).unwrap()
}

///|
/// The entries of a closure while `ParseItemSetBuilder::transitive_closure` builds it:
/// found by item as they're added, and taken out in item order once it's complete.
///
/// Items are ordered by `step_index` first, so the items at their first step come before
/// all the others. Most of a closure's items are at their first step, and each of those has
/// a rank and a slot for its entry. The rest are kernel items past their first
/// step, which are found by hash and sorted.
priv struct ClosureEntries {
  /// The rank of every item that can be in `first_step`.
  ranks : FirstStepRanks
  /// The entry of each first-step item in the closure, by rank.
  first_step : Array[ParseItemSetEntry?]
  /// The ranks that have an entry in `first_step`, to find those without scanning it.
  occupied : BitVec
  /// The number of entries in `first_step`.
  mut first_step_len : Int32
  /// The entries of the items past their first step, in the order they were added.
  later : Array[ParseItemSetEntry]
  /// The positions of `later`'s entries, by their items.
  later_indices : Map[ParseItem, Int32]
  /// Entries of finished closures, to reuse for new ones.
  spares : Array[ParseItemSetEntry]
}

///|
fn ClosureEntries::new(ranks : FirstStepRanks) -> ClosureEntries {
  let occupied = BitVec::new()
  occupied.resize(ranks.len(), false)
  {
    first_step: Array::make(ranks.len(), None),
    ranks,
    occupied,
    first_step_len: 0,
    later: [],
    later_indices: {},
    spares: [],
  }
}

///|
/// The entry of `addition`'s item, added if it's new.
fn ClosureEntries::addition_entry(
  self : ClosureEntries,
  addition : TransitiveClosureAddition,
) -> ParseItemSetEntry {
  self.first_step_entry(addition.rank, addition.item)
}

///|
/// The entry of `item`, from the closure's kernel, added if it's new.
fn ClosureEntries::kernel_entry(
  self : ClosureEntries,
  item : ParseItem,
) -> ParseItemSetEntry {
  // A kernel's items are past their first step, except for the start item.
  if item.step_index == 0 {
    let rank = self.ranks.rank(item)
    self.first_step_entry(rank, item)
  } else {
    self.later_entry(item)
  }
}

///|
/// The entry of `item`, which is at its first step and has the given rank, added if it's
/// new.
fn ClosureEntries::first_step_entry(
  self : ClosureEntries,
  rank : Int32,
  item : ParseItem,
) -> ParseItemSetEntry {
  match self.first_step[rank] {
    Some(entry) => entry
    None => {
      self.occupied.set(rank, true)
      self.first_step_len += 1
      let entry = self.new_entry(item)
      self.first_step[rank] = Some(entry)
      entry
    }
  }
}

///|
/// The entry of `item`, which is past its first step, added if it's new.
fn ClosureEntries::later_entry(
  self : ClosureEntries,
  item : ParseItem,
) -> ParseItemSetEntry {
  match self.later_indices.get(item) {
    Some(index) => self.later[index]
    None => {
      let index = self.later.length()
      self.later_indices[item] = index
      let entry = self.new_entry(item)
      self.later.push(entry)
      entry
    }
  }
}

///|
/// An entry for `item`, with no lookaheads yet.
fn ClosureEntries::new_entry(
  self : ClosureEntries,
  item : ParseItem,
) -> ParseItemSetEntry {
  match self.spares.pop() {
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
}

///|
/// Takes back the entries of a closure from `Self::take_item_set` that is no longer
/// used, to reuse for later closures.
fn ClosureEntries::recycle(
  self : ClosureEntries,
  item_set : ParseItemSet,
) -> Unit {
  for entry in item_set.entries {
    self.spares.push(entry)
  }
  item_set.entries.clear()
}

///|
/// Takes the entries out in item order, leaving this empty for the next closure.
fn ClosureEntries::take_item_set(self : ClosureEntries) -> ParseItemSet {
  let entries = Array(capacity=self.first_step_len + self.later.length())
  let words = self.occupied.words()
  for wi in 0..<words.length() {
    let mut word = words[wi]
    while word != 0 {
      let rank = wi * 64 + word.ctz()
      word = word & (word - 1)
      // INVARIANT: occupied ranks have entries
      entries.push(self.first_step[rank].unwrap())
      self.first_step[rank] = None
    }
  }
  self.occupied.unset_all()
  self.first_step_len = 0
  // Past their first step, these all come after the entries above. Their items
  // are distinct, so the order is total.
  self.later.sort_by((a, b) => Compare::compare(a.item, b.item))
  for entry in self.later {
    entries.push(entry)
  }
  self.later.clear()
  self.later_indices.clear()
  { entries, }
}

///|
fn ParseItemSetBuilder::new(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  inlines : InlinedProductionMap,
  key_map : ItemKeyMap,
) -> ParseItemSetBuilder {
  let result = {
    syntax_grammar,
    first_sets: {},
    symbol_indexer: SymbolIndexer::new(syntax_grammar, lexical_grammar),
    first_set_ids: [],
    reserved_first_sets: {},
    reserved_first_set_ids: [],
    last_sets: {},
    inlined_prod_ids_by_key: {},
    key_map,
    lookaheads: LookaheadSetPool::new(),
    transitive_closure_additions: [],
    closure_scratch: ClosureEntries::new(FirstStepRanks({})),
  }

  for key, ids in inlines.map {
    result.inlined_prod_ids_by_key[inlined_prod_ids_key(key.0, key.1)] = ids
  }

  // For each grammar symbol, populate the FIRST and LAST sets: the set of
  // terminals that appear at the beginning and end that symbol's productions,
  // respectively.
  // For a terminal symbol, the FIRST and LAST sets just consist of the
  // terminal itself.
  let n_terminals = lexical_grammar.variables.length()
  let n_externals = syntax_grammar.external_tokens.length()
  for i in 0..<n_terminals {
    let symbol = Symbol::terminal(i)
    let set = TokenSet::new()
    set.insert(symbol)
    result.first_sets[symbol] = set.copy()
    result.last_sets[symbol] = set
    result.reserved_first_sets[symbol] = 0
  }
  for i in 0..<n_externals {
    let symbol = Symbol::external(i)
    let set = TokenSet::new()
    set.insert(symbol)
    result.first_sets[symbol] = set.copy()
    result.last_sets[symbol] = set
    result.reserved_first_sets[symbol] = 0
  }

  // The FIRST set of a non-terminal `i` is the union of the FIRST sets
  // of all the symbols that appear at the beginnings of i's productions. Some
  // of these symbols may themselves be non-terminals, so this is a recursive
  // definition.
  //
  // Rather than computing these sets using recursion, we use an explicit stack
  // called `symbols_to_process`.
  let symbols_to_process : Array[Int32] = []
  let processed_non_terminals : Map[Int32, Unit] = Map([])
  for i in 0..<syntax_grammar.variables.length() {
    let root_index = i
    let symbol = Symbol::non_terminal(i)
    let first_set = result.first_sets.get_or_init(symbol, TokenSet::new)
    let mut reserved_first_set = result.reserved_first_sets.get_or_default(
      symbol, 0,
    )
    processed_non_terminals.clear()
    symbols_to_process.clear()
    symbols_to_process.push(root_index)
    while symbols_to_process.pop() is Some(index) {
      let (start, end) = syntax_grammar.variable_prod_ids(index)
      for prod_id in start..<end {
        if syntax_grammar.production(prod_id).steps.get(0) is Some(step) {
          let symbol = step.symbol
          match symbol.kind {
            Terminal | External => first_set.insert(symbol)
            NonTerminal => {
              let index = symbol.index
              if !processed_non_terminals.contains(index) {
                processed_non_terminals[index] = ()
                symbols_to_process.push(index)
              }
            }
            End | EndOfNonTerminalExtra => abort("unreachable")
          }
          if step.reserved > reserved_first_set {
            reserved_first_set = step.reserved
          }
        }
      }
    }
    result.reserved_first_sets[symbol] = reserved_first_set

    // The LAST set is defined in a similar way to the FIRST set.
    let last_set = result.last_sets.get_or_init(symbol, TokenSet::new)
    processed_non_terminals.clear()
    symbols_to_process.clear()
    symbols_to_process.push(root_index)
    while symbols_to_process.pop() is Some(index) {
      let (start, end) = syntax_grammar.variable_prod_ids(index)
      for prod_id in start..<end {
        if syntax_grammar.production(prod_id).steps.last() is Some(step) {
          let symbol = step.symbol
          match symbol.kind {
            Terminal | External => last_set.insert(symbol)
            NonTerminal => {
              let index = symbol.index
              if !processed_non_terminals.contains(index) {
                processed_non_terminals[index] = ()
                symbols_to_process.push(index)
              }
            }
            End | EndOfNonTerminalExtra => abort("unreachable")
          }
        }
      }
    }
  }

  // Intern each FIRST set so closure propagation can union by id. (Upstream
  // iterates a hash map here, so the ids are in hash order; ids are only ever
  // compared for equality, so their numbering is unobservable.)
  let symbol_count = result.symbol_indexer.symbol_count()
  result.first_set_ids = FixedArray::make(symbol_count, -1)
  for symbol, set in result.first_sets {
    result.first_set_ids[result.symbol_indexer.index(symbol)] = result.lookaheads.intern_ref(
      set,
    )
  }
  result.reserved_first_set_ids = FixedArray::make(symbol_count, -1)
  for symbol, id in result.reserved_first_sets {
    result.reserved_first_set_ids[result.symbol_indexer.index(symbol)] = id
  }

  // To compute an item set's transitive closure, we find each item in the set
  // whose next symbol is a non-terminal, and we add new items to the set for
  // each of that symbol's productions. These productions might themselves begin
  // with non-terminals, so the process continues recursively. In this process,
  // the total set of entries that get added depends only on two things:
  //
  //   * the non-terminal symbol that occurs next in each item
  //
  //   * the set of terminals that can follow that non-terminal symbol in the item
  //
  // So we can avoid a lot of duplicated recursive work by precomputing, for each
  // non-terminal symbol `i`, a final list of *additions* that must be made to an
  // item set when symbol `i` occurs as the next symbol in one if its core items.
  // The structure of a precomputed *addition* is as follows:
  //
  //   * `item` - the new item that must be added as part of the expansion of the symbol `i`.
  //
  //   * `lookaheads` - the set of possible lookahead tokens that can always come after `item`
  //     in an expansion of symbol `i`.
  //
  //   * `reserved_lookaheads` - the set of reserved lookahead tokens that can always come
  //     after `item` in the expansion of symbol `i`.
  //
  //   * `propagates_lookaheads` - a boolean indicating whether or not `item` can occur at the
  //     *end* of the expansion of symbol `i`, so that i's own current lookahead tokens can
  //     occur after `item`.
  //
  // Rather than computing these additions recursively, we use an explicit stack.
  let empty_lookaheads = TokenSet::new()
  let eof_lookaheads = TokenSet::new()
  eof_lookaheads.insert(symbol_end)
  let stack : Array[(Int32, TokenSet, Int32, Bool)] = []
  // Upstream's `FxHashMap` is iterated below; the additions it produces are
  // only ever combined with commutative unions and maxima, so their order is
  // unobservable and insertion order serves as well.
  let follow_set_info_by_non_terminal : Map[Int32, FollowSetInfo] = Map([])
  let additions : Array[Array[(ParseItem, AdditionInfo)]] = Array::makei(
    syntax_grammar.variables.length(),
    _ => [],
  )
  let addition_indices : Map[(ParseItem, AdditionInfo), Unit] = Map([])
  for i, additions_for_non_terminal in additions {
    // First, build up a map whose keys are all of the non-terminals that can
    // appear at the beginning of non-terminal `i`, and whose values store
    // information about the tokens that can follow those non-terminals.
    stack.clear()
    stack.push((i, empty_lookaheads, 0, true))
    follow_set_info_by_non_terminal.clear()
    while stack.pop()
          is Some(
            (sym_ix, lookaheads, reserved_word_set_id, propagates_lookaheads)
          ) {
      let mut did_add = false
      let info = follow_set_info_by_non_terminal.get_or_init(sym_ix, () => {
        lookaheads: TokenSet::new(),
        reserved_lookaheads: 0,
        propagates_lookaheads: false,
      })
      if info.lookaheads.insert_all(lookaheads) {
        did_add = true
      }
      if reserved_word_set_id > info.reserved_lookaheads {
        info.reserved_lookaheads = reserved_word_set_id
        did_add = true
      }
      if propagates_lookaheads && !info.propagates_lookaheads {
        did_add = true
      }
      info.propagates_lookaheads = info.propagates_lookaheads ||
        propagates_lookaheads
      if !did_add {
        continue
      }
      let (start, end) = syntax_grammar.variable_prod_ids(sym_ix)
      for prod_id in start..<end {
        let production = syntax_grammar.production(prod_id)
        if production.first_symbol() is Some(first) &&
          first.non_terminal_index() is Some(index) {
          if production.steps.get(1) is Some(next_step) {
            stack.push(
              (
                index,
                result.first_sets[next_step.symbol],
                result.reserved_first_sets[next_step.symbol],
                false,
              ),
            )
          } else if production.requires_eof_lookahead {
            stack.push((index, eof_lookaheads, 0, false))
          } else {
            stack.push(
              (index, lookaheads, reserved_word_set_id, propagates_lookaheads),
            )
          }
        }
      }
    }

    // Store all of those non-terminals' productions, along with their associated
    // lookahead info, as *additions* associated with non-terminal `i`.
    addition_indices.clear()
    for variable_index, follow_set_info in follow_set_info_by_non_terminal {
      let non_terminal = Symbol::non_terminal(variable_index)
      if syntax_grammar.variables_to_inline.contains(non_terminal) {
        continue
      }
      let info : AdditionInfo = {
        lookaheads: result.lookaheads.intern_ref(follow_set_info.lookaheads),
        reserved_lookaheads: follow_set_info.reserved_lookaheads,
        propagates_lookaheads: follow_set_info.propagates_lookaheads,
        contains_word: match syntax_grammar.word_token {
          Some(w) => follow_set_info.lookaheads.contains(w)
          None => false
        },
      }
      let (start, end) = syntax_grammar.variable_prod_ids(variable_index)
      for prod_id in start..<end {
        let item = ParseItem::new(
          variable_index~,
          prod_id~,
          keys=key_map.keys_for(prod_id),
          step_index=0,
          has_preceding_inherited_fields=false,
        )
        match result.inlined_prod_ids(item.prod_id, item.step_index) {
          Some(ids) =>
            for id in ids {
              let item_info = if syntax_grammar.production(id).requires_eof_lookahead {
                {
                  lookaheads: result.lookaheads.intern_ref(eof_lookaheads),
                  reserved_lookaheads: 0,
                  propagates_lookaheads: false,
                  contains_word: false,
                }
              } else {
                info
              }
              push_unique(
                additions_for_non_terminal,
                addition_indices,
                (
                  item.substitute_production(id, key_map.keys_for(id)),
                  item_info,
                ),
              )
            }
          None => {
            let item_info = if syntax_grammar.production(prod_id).requires_eof_lookahead {
              {
                lookaheads: result.lookaheads.intern_ref(eof_lookaheads),
                reserved_lookaheads: 0,
                propagates_lookaheads: false,
                contains_word: false,
              }
            } else {
              info
            }
            push_unique(
              additions_for_non_terminal,
              addition_indices,
              (item, item_info),
            )
          }
        }
      }
    }
  }

  // Besides these additions, the only item a closure holds at its first step is the start
  // item, in the start state's kernel.
  let ranked_items = []
  for additions_for_non_terminal in additions {
    for addition in additions_for_non_terminal {
      ranked_items.push(addition.0)
    }
  }
  ranked_items.push(ParseItem::start(key_map))
  let ranks = FirstStepRanks::new(ranked_items)
  result.transitive_closure_additions = additions.map(additions_for_non_terminal => {
    additions_for_non_terminal.map(addition => {
      let (item, info) = addition
      { item, info, rank: ranks.rank(item), }
    })
  })
  result.closure_scratch = ClosureEntries::new(ranks)
  result
}

///|
fn ParseItemSetBuilder::transitive_closure(
  self : ParseItemSetBuilder,
  item_set : ParseItemSet,
) -> ParseItemSet {
  for entry in item_set.entries {
    match self.inlined_prod_ids(entry.item.prod_id, entry.item.step_index) {
      Some(ids) =>
        for id in ids {
          self.add_item({
            item: entry.item.substitute_production(
              id,
              self.key_map.keys_for(id),
            ),
            lookaheads: entry.lookaheads,
            following_reserved_word_set: entry.following_reserved_word_set,
          })
        }
      None => self.add_item(entry)
    }
  }
  self.closure_scratch.take_item_set()
}

///|
fn inlined_prod_ids_key(prod_id : Int32, step_index : Int32) -> Int64 {
  (prod_id.to_int64() << 32) | step_index.to_int64()
}

///|
/// `self.inlines.inlined_prod_ids(prod_id, step_index)`, without building a tuple key.
fn ParseItemSetBuilder::inlined_prod_ids(
  self : ParseItemSetBuilder,
  prod_id : Int32,
  step_index : Int32,
) -> Array[Int32]? {
  self.inlined_prod_ids_by_key.get(inlined_prod_ids_key(prod_id, step_index))
}

///|
fn ParseItemSetBuilder::first_set(
  self : ParseItemSetBuilder,
  symbol : Symbol,
) -> TokenSet {
  // The interned copy of `self.first_sets[symbol]`, found without hashing.
  self.lookaheads.get(self.first_set_ids[self.symbol_indexer.index(symbol)])
}

///|
fn ParseItemSetBuilder::reserved_first_set(
  self : ParseItemSetBuilder,
  symbol : Symbol,
) -> TokenSet? {
  match self.reserved_first_sets.get(symbol) {
    Some(id) => Some(self.syntax_grammar.reserved_word_sets[id])
    None => None
  }
}

///|
fn ParseItemSetBuilder::last_set(
  self : ParseItemSetBuilder,
  symbol : Symbol,
) -> TokenSet {
  self.last_sets[symbol]
}

///|
fn ParseItemSetBuilder::add_item(
  self : ParseItemSetBuilder,
  entry : ParseItemSetEntry,
) -> Unit {
  if entry.item.step(self.syntax_grammar) is Some(step) &&
    step.non_terminal_index() is Some(index) {
    // `entry.item.successor(..).step()`, without building the successor.
    let next_step = entry.item.step_at(
      self.syntax_grammar,
      entry.item.step_index + 1,
    )

    // Determine which tokens can follow this non-terminal.
    let mut following_tokens = entry.lookaheads
    let mut following_reserved_tokens = entry.following_reserved_word_set
    if next_step is Some(next_step) {
      let key = self.symbol_indexer.index(next_step.symbol)
      following_tokens = self.first_set_ids[key]
      following_reserved_tokens = self.reserved_first_set_ids[key]
    }

    // Use the pre-computed *additions* to expand the non-terminal.
    for addition in self.transitive_closure_additions[index] {
      let e = self.closure_scratch.addition_entry(addition)
      e.lookaheads = self.lookaheads.union(
        e.lookaheads,
        addition.info.lookaheads,
      )
      if addition.info.contains_word &&
        addition.info.reserved_lookaheads > e.following_reserved_word_set {
        e.following_reserved_word_set = addition.info.reserved_lookaheads
      }
      if addition.info.propagates_lookaheads {
        e.lookaheads = self.lookaheads.union(e.lookaheads, following_tokens)
        if self.syntax_grammar.word_token is Some(word_token) &&
          self.lookaheads.get(following_tokens).contains(word_token) &&
          following_reserved_tokens > e.following_reserved_word_set {
          e.following_reserved_word_set = following_reserved_tokens
        }
      }
    }
  }
  let e = self.closure_scratch.kernel_entry(entry.item)
  e.lookaheads = self.lookaheads.union(e.lookaheads, entry.lookaheads)
  if entry.following_reserved_word_set > e.following_reserved_word_set {
    e.following_reserved_word_set = entry.following_reserved_word_set
  }
}
