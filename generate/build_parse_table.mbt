// Port of tree-sitter crates/generate/src/build_tables/build_parse_table.rs.

///|
/// For conflict reporting, each parse state is associated with the auxiliary (repeat)
/// symbols in progress along the path to that state, and their parents: the non-auxiliary
/// rules that were using them. Auxiliary symbols can't be named in the grammar's
/// `conflicts`, so a conflict inside a repeat rule is reported in terms of its parents.
///
/// A state's context only holds the auxiliary symbols at a dot in that state, and links
/// to its predecessor: the context of the state that first led to it. Successor states
/// share a context, and a lookup follows the predecessors back to the most recent state
/// that used the symbol.
///
/// Context ids are dense 0-based indices into `contexts`.
priv struct AuxiliarySymbolContexts {
  contexts : Array[AuxiliaryContext]
  /// Every context's (auxiliary symbol, parent set) pairs.
  entries : Array[(Int32, Int32)]
  /// Symbols of every distinct parent set, concatenated in intern order.
  parent_symbols : Array[Symbol]
  /// Each parent set's `(start, len)` slice of `parent_symbols`, by parent set id.
  parent_sets : Array[(Int32, Int32)]
  /// Parent set ids of every distinct parent set.
  parent_set_ids : Map[SymbolListKey, Int32]
}

///|
/// A list of symbols as a map key, hashed without `Hasher`'s allocation.
priv struct SymbolListKey(Array[Symbol])

///|
impl Eq for SymbolListKey with fn equal(self, other) {
  self.0 == other.0
}

///|
impl Hash for SymbolListKey with fn hash_combine(self, hasher) {
  hasher.combine_int(Hash::hash(self))
}

///|
impl Hash for SymbolListKey with fn hash(self) {
  let mut acc = hash_mix(HASH_SEED, self.0.length())
  for symbol in self.0 {
    acc = hash_mix(acc, symbol.code())
  }
  hash_finish(acc)
}

///|
/// An auxiliary use: an auxiliary symbol's index in the upper half, and the index of
/// the rule using it in the lower half, so that uses sort like `(symbol, parent)`
/// pairs.
fn auxiliary_use(symbol : Int32, parent : Int32) -> Int64 {
  (symbol.to_int64() << 32) | parent.to_int64()
}

///|
/// One state's slice of `AuxiliarySymbolContexts::entries`, and its predecessor.
priv struct AuxiliaryContext {
  predecessor : Int32?
  start : Int32
  len : Int32
}

///|
fn AuxiliarySymbolContexts::new() -> AuxiliarySymbolContexts {
  {
    contexts: [],
    entries: [],
    parent_symbols: [],
    parent_sets: [],
    parent_set_ids: {},
  }
}

///|
/// Adds the context of a state whose predecessor is `predecessor`. `uses` pairs each
/// auxiliary symbol at a dot in the state with the rule of an item using it. Auxiliary
/// rules aren't parents, but a symbol used only by auxiliary rules still gets an (empty)
/// entry, which hides any earlier one.
fn AuxiliarySymbolContexts::push(
  self : AuxiliarySymbolContexts,
  grammar : SyntaxGrammar,
  predecessor : Int32?,
  uses : Array[Int64],
) -> Int32? {
  if uses.is_empty() {
    return predecessor
  }
  uses.sort()
  dedup(uses)
  let start = self.entries.length()
  let parents : Array[Symbol] = []
  let mut group_start = 0
  while group_start < uses.length() {
    let mut group_end = group_start + 1
    let symbol = (uses[group_start] >> 32).to_int()
    while group_end < uses.length() &&
          (uses[group_end] >> 32).to_int() == symbol {
      group_end += 1
    }
    parents.clear()
    for i in group_start..<group_end {
      let parent = uses[i].to_int()
      if !grammar.variables[parent].is_auxiliary() {
        parents.push(Symbol::non_terminal(parent))
      }
    }
    let parent_set = self.intern(parents)
    self.entries.push((symbol, parent_set))
    group_start = group_end
  }
  let id = self.contexts.length()
  self.contexts.push({ predecessor, start, len: self.entries.length() - start, })
  Some(id)
}

///|
/// Returns the parents of `symbol` in the most recent state that had it at a dot, along
/// the path to the state whose context is `context`.
fn AuxiliarySymbolContexts::parents(
  self : AuxiliarySymbolContexts,
  context : Int32?,
  symbol : Int32,
) -> ArrayView[Symbol]? {
  let mut context = context
  while context is Some(id) {
    let { predecessor, start, len, } = self.contexts[id]
    for i in start..<(start + len) {
      let (s, parent_set) = self.entries[i]
      if s == symbol {
        let (set_start, set_len) = self.parent_sets[parent_set]
        return Some(self.parent_symbols[set_start:set_start + set_len])
      }
    }
    context = predecessor
  }
  None
}

///|
/// Returns the id of the parent set `parents`, interning it if it's new.
fn AuxiliarySymbolContexts::intern(
  self : AuxiliarySymbolContexts,
  parents : Array[Symbol],
) -> Int32 {
  match self.parent_set_ids.get(SymbolListKey(parents)) {
    Some(id) => id
    None => {
      let id = self.parent_sets.length()
      self.parent_sets.push((self.parent_symbols.length(), parents.length()))
      for symbol in parents {
        self.parent_symbols.push(symbol)
      }
      self.parent_set_ids[SymbolListKey(parents.copy())] = id
      id
    }
  }
}

///|
priv struct ParseStateInfo {
  preceding_symbols_by_id : Array[Array[Symbol]]
  item_sets_by_ids : Array[ParseItemSet]
  lookaheads : LookaheadSetPool
}

///|
fn ParseStateInfo::item_set(self : ParseStateInfo, id : Int32) -> ParseItemSet {
  self.item_sets_by_ids[id]
}

///|
priv struct ReductionInfo {
  mut precedence : Precedence
  symbols : Array[Symbol]
  mut has_left_assoc : Bool
  mut has_right_assoc : Bool
  mut has_non_assoc : Bool
}

///|
fn ReductionInfo::default() -> ReductionInfo {
  {
    precedence: NoPrecedence,
    symbols: [],
    has_left_assoc: false,
    has_right_assoc: false,
    has_non_assoc: false,
  }
}

///|
/// Resets this to the default, keeping the `symbols` buffer.
fn ReductionInfo::clear(self : ReductionInfo) -> Unit {
  self.symbols.clear()
  self.precedence = NoPrecedence
  self.has_left_assoc = false
  self.has_right_assoc = false
  self.has_non_assoc = false
}

///|
/// The reductions on each lookahead of the state that `add_actions` is working on.
priv struct ReductionInfos {
  /// Gives each lookahead its slot in `infos`.
  indexer : SymbolIndexer
  /// Each lookahead's reductions, by `SymbolIndexer::index`. Only the lookaheads with a
  /// reduction in the current state are up to date: `add_actions` clears a lookahead's info at
  /// its first reduction in each state.
  infos : Array[ReductionInfo]
}

///|
fn ReductionInfos::new(indexer : SymbolIndexer) -> ReductionInfos {
  {
    indexer,
    infos: Array::makei(indexer.token_count(), _ => ReductionInfo::default()),
  }
}

///|
/// The reductions on `lookahead`.
fn ReductionInfos::get(
  self : ReductionInfos,
  lookahead : Symbol,
) -> ReductionInfo {
  self.infos[self.indexer.index(lookahead)]
}

///|
/// The item sets of a state's successors, one for each symbol that follows a dot in the state.
priv struct SuccessorSets {
  /// Gives each symbol its slot in `sets`.
  indexer : SymbolIndexer
  /// Each symbol's successor item set, by `SymbolIndexer::index`.
  sets : Array[ParseItemSet?]
  /// The positions of the symbols that have a set in `sets`, as bits.
  occupied : FixedArray[UInt64]
  /// The positions of the symbols that have a set in `sets`, once sorted.
  symbols : Array[Int32]
  /// Empty item sets to build successors in, so that most successors don't allocate.
  pool : Array[ParseItemSet]
}

///|
fn SuccessorSets::new(indexer : SymbolIndexer) -> SuccessorSets {
  {
    indexer,
    sets: Array::make(indexer.symbol_count(), None),
    occupied: FixedArray::make((indexer.symbol_count() + 63) / 64, 0),
    symbols: [],
    pool: [],
  }
}

///|
/// The item set of the successor after `symbol`, added if it's new.
fn SuccessorSets::item_set(
  self : SuccessorSets,
  symbol : Symbol,
) -> ParseItemSet {
  let index = self.indexer.index(symbol)
  match self.sets[index] {
    Some(set) => set
    None => {
      self.occupied[index / 64] = self.occupied[index / 64] |
        (1UL << (index % 64))
      let set = match self.pool.pop() {
        Some(set) => set
        None => ParseItemSet::new()
      }
      self.sets[index] = Some(set)
      set
    }
  }
}

///|
/// Sorts the positions of the symbols that have a set into symbol order, for
/// `Self::take`. Symbols are distinct, so the order is total. Positions follow
/// symbol order.
fn SuccessorSets::sorted_positions(self : SuccessorSets) -> Array[Int32] {
  self.symbols.clear()
  for w in 0..<self.occupied.length() {
    let mut word = self.occupied[w]
    while word != 0 {
      self.symbols.push(w * 64 + word.ctz())
      word = word & (word - 1)
    }
    self.occupied[w] = 0
  }
  self.symbols
}

///|
/// Takes out the set at a position from `Self::sorted_positions`.
fn SuccessorSets::take(self : SuccessorSets, index : Int32) -> ParseItemSet {
  // INVARIANT: every symbol in `symbols` has a set
  let set = self.sets[index].unwrap()
  self.sets[index] = None
  set
}

///|
/// Takes back a set from `Self::take` that no state kept, to build later
/// successors in.
fn SuccessorSets::recycle(self : SuccessorSets, set : ParseItemSet) -> Unit {
  set.clear()
  self.pool.push(set)
}

///|
priv struct ParseStateQueueEntry {
  state_id : Int32
  preceding_auxiliary_context : Int32?
}

///|
/// Upstream `ParseTableEntry`: an action list and its reusable flag.
priv struct ParseTableEntry {
  actions : Array[ParseAction]
  reusable : Bool
}

///|
fn ParseTableEntry::new() -> ParseTableEntry {
  { reusable: true, actions: [], }
}

///|
/// Upstream's `IndexMap<Symbol, ParseTableEntry>` for `ParseTableBuilder::terminal_entries`:
/// entries in insertion order, found by `SymbolIndexer::index`. Entries are reused across
/// states, so that most states don't allocate them.
priv struct TerminalEntryMap {
  indexer : SymbolIndexer
  /// The position of each symbol's entry, by `SymbolIndexer::index`, or `-1`.
  positions : FixedArray[Int32]
  /// The symbols, in insertion order.
  keys : Array[Symbol]
  /// The entries, by position. Entries past `keys.length()` are spares.
  values : Array[ParseTableEntry]
}

///|
fn TerminalEntryMap::new(indexer : SymbolIndexer) -> TerminalEntryMap {
  {
    indexer,
    positions: FixedArray::make(indexer.token_count(), -1),
    keys: [],
    values: [],
  }
}

///|
fn TerminalEntryMap::length(self : TerminalEntryMap) -> Int32 {
  self.keys.length()
}

///|
fn TerminalEntryMap::contains(self : TerminalEntryMap, symbol : Symbol) -> Bool {
  self.positions[self.indexer.index(symbol)] >= 0
}

///|
fn TerminalEntryMap::get(
  self : TerminalEntryMap,
  symbol : Symbol,
) -> ParseTableEntry? {
  let position = self.positions[self.indexer.index(symbol)]
  if position >= 0 {
    Some(self.values[position])
  } else {
    None
  }
}

///|
/// `entry(symbol).or_insert_with(ParseTableEntry::new)`.
fn TerminalEntryMap::get_or_insert_new(
  self : TerminalEntryMap,
  symbol : Symbol,
) -> ParseTableEntry {
  let index = self.indexer.index(symbol)
  let position = self.positions[index]
  if position >= 0 {
    return self.values[position]
  }
  let position = self.keys.length()
  self.positions[index] = position
  self.keys.push(symbol)
  if position < self.values.length() {
    // A spare from an earlier state: `clear` emptied its actions.
    self.values[position]
  } else {
    let entry = ParseTableEntry::new()
    self.values.push(entry)
    entry
  }
}

///|
/// Removes every entry, keeping them as spares.
fn TerminalEntryMap::clear(self : TerminalEntryMap) -> Unit {
  for position, symbol in self.keys {
    self.positions[self.indexer.index(symbol)] = -1
    self.values[position].actions.clear()
  }
  self.keys.clear()
}

///|
/// `ActionList::keep_last`.
fn action_list_keep_last(actions : Array[ParseAction]) -> Unit {
  if actions.length() > 1 {
    let last = actions[actions.length() - 1]
    actions.clear()
    actions.push(last)
  }
}

///|
priv struct ParseTableBuilder {
  item_set_builder : ParseItemSetBuilder
  syntax_grammar : SyntaxGrammar
  lexical_grammar : LexicalGrammar
  variable_info : Array[VariableInfo]
  /// Upstream's `core_ids_by_core`: finds core ids by the cores of the states in
  /// `states_by_core_id`.
  core_ids_by_core : HashIndex
  /// The first state with each core, by core id.
  states_by_core_id : Array[Int32]
  /// Upstream's `IndexMap<ParseItemSet, ParseStateId>`: an index for lookups, of the
  /// item sets in `item_sets_by_id`, which are by insertion index.
  state_ids_by_item_set : HashIndex
  item_sets_by_id : Array[ParseItemSet]
  preceding_symbols_by_id : Array[Array[Symbol]]
  production_info_ids_by_prod_id : Array[Int32?]
  parse_state_queue : Array[ParseStateQueueEntry]
  mut parse_state_queue_head : Int32
  auxiliary_contexts : AuxiliarySymbolContexts
  non_terminal_extra_states : Array[(Symbol, Int32)]
  /// Upstream's `FxHashSet<Vec<Symbol>>`, only iterated to be sorted.
  actual_conflicts : Map[Array[Symbol], Unit]
  parse_table : ParseTable
  /// The pool index of each action list interned into `parse_table` so far.
  action_list_ids : Map[ActionListKey, Int32]
  /// A reusable `ActionListId` for each pool index, shared by every entry with that
  /// list (they're immutable), so that entries don't each allocate one.
  reusable_action_list_ids : Array[ActionListId]
  /// A `Goto` for each state id, shared like `reusable_action_list_ids`.
  gotos : Array[GotoAction]
  /// A non-repetition `Shift` for each state id, shared like `gotos`.
  shifts : Array[ParseAction]
  /// Scratch for `add_actions`: the lookaheads with conflicts in the state it's working
  /// on. Empty between states.
  lookaheads_with_conflicts : TokenSet
  /// Scratch for `add_actions`: the one-symbol list of a reduction's symbol.
  reduce_symbols : Array[Symbol]
  /// Scratch for `build`: the preceding symbols of the state being built.
  preceding_symbols : Array[Symbol]
  /// Scratch for `handle_conflict`: the items in the conflict.
  conflicting_items : Array[ParseItem]
  /// Scratch for `add_actions`: the entries that can take part in a conflict.
  conflict_candidates : Array[ParseItemSetEntry]
  str_pool : StrPool
  /// Scratch for `add_actions`: The terminal entries of the state it's working on. They are
  /// interned into the table once the state is complete.
  terminal_entries : TerminalEntryMap
  /// Scratch for `add_actions`: The successor item sets of the state currently being built.
  successor_sets : SuccessorSets
  /// Scratch for `add_actions`: The reductions on each lookahead of the state currently being
  /// built.
  reduction_infos : ReductionInfos
}

///|
/// Upstream `ParseTableBuilderError`; `to_string` gives its `Display` text.
pub(all) suberror ParseTableBuilderError {
  Conflict(ConflictError)
  AmbiguousExtra(AmbiguousExtraError)
  ImproperNonTerminalExtra(String)
  StateCount(Int32)
}

///|
pub(all) struct ConflictError {
  symbol_sequence : Array[String]
  conflicting_lookahead : String
  possible_interpretations : Array[Interpretation]
  possible_resolutions : Array[Resolution]
} derive(Eq, Debug)

///|
pub(all) struct Interpretation {
  preceding_symbols : Array[String]
  variable_name : String
  production_step_symbols : Array[String]
  step_index : Int32
  done : Bool
  conflicting_lookahead : String
  precedence : String?
  associativity : String?
  requires_eof_lookahead : Bool
} derive(Eq, Debug)

///|
pub(all) enum Resolution {
  Precedence(symbols~ : Array[String])
  Associativity(symbols~ : Array[String])
  AddConflict(symbols~ : Array[String])
} derive(Eq, Debug)

///|
pub(all) struct AmbiguousExtraError {
  parent_symbols : Array[String]
} derive(Eq, Debug)

///|
pub impl Show for ParseTableBuilderError with fn output(self, logger) {
  match self {
    Conflict(error) =>
      logger.write_string(
        "Unresolved conflict for symbol sequence:\n\n\{error}",
      )
    AmbiguousExtra(error) =>
      logger.write_string(
        "Extra rules must have unambiguous endings. Conflicting rules: \{error}",
      )
    ImproperNonTerminalExtra(name) =>
      logger.write_string(
        "The non-terminal rule `\{name}` is used in a non-terminal `extra` rule, which is not allowed.",
      )
    StateCount(count) =>
      logger.write_string("State count `\{count}` exceeds the max value 65535.")
  }
}

///|
/// The number of `char`s in `s`, like Rust's `s.chars().count()`.
fn char_count(s : String) -> Int32 {
  let mut n = 0
  for _ in s {
    n += 1
  }
  n
}

///|
pub impl Show for ConflictError with fn output(self, f) {
  for symbol in self.symbol_sequence {
    f.write_string("  \{symbol}")
  }
  f.write_string("  •  \{self.conflicting_lookahead}  …\n\n")
  f.write_string("Possible interpretations:\n\n")
  let interpretations = self.possible_interpretations.map(i => {
    let line = i.to_string()
    let annotations = []
    match (i.precedence, i.associativity) {
      (Some(precedence), Some(associativity)) =>
        annotations.push(
          "(precedence: \{precedence}, associativity: \{associativity})",
        )
      (Some(precedence), None) =>
        annotations.push("(precedence: \{precedence})")
      _ => ()
    }
    if i.requires_eof_lookahead {
      annotations.push("(reduces only at end of input)")
    }
    let prec_line = if annotations.is_empty() {
      None
    } else {
      Some(annotations.join("  "))
    }
    (line, prec_line)
  })
  let mut max_interpretation_length = 0
  for i in interpretations {
    let n = char_count(i.0)
    if n > max_interpretation_length {
      max_interpretation_length = n
    }
  }
  // Equal elements are identical, so any sort gives upstream's order.
  interpretations.sort_by((a, b) => {
    let c = rust_str_cmp(a.0, b.0)
    if c != 0 {
      return c
    }
    match (a.1, b.1) {
      (None, None) => 0
      (None, Some(_)) => -1
      (Some(_), None) => 1
      (Some(x), Some(y)) => rust_str_cmp(x, y)
    }
  })
  for i, interpretation in interpretations {
    let (line, prec_suffix) = interpretation
    f.write_string("  \{i + 1}:")
    f.write_string(line)
    if prec_suffix is Some(prec_suffix) {
      let width = max_interpretation_length - char_count(line)
      let width = (if width > 0 { width } else { 0 }) + 2
      f.write_string(" ".repeat(width))
      f.write_string(prec_suffix)
    }
    f.write_string("\n")
  }
  f.write_string("\nPossible resolutions:\n\n")
  for i, resolution in self.possible_resolutions {
    f.write_string("  \{i + 1}:  \{resolution}\n")
  }
}

///|
pub impl Show for Interpretation with fn output(self, f) {
  for symbol in self.preceding_symbols {
    f.write_string("  \{symbol}")
  }
  f.write_string("  (\{self.variable_name}")
  for i, symbol in self.production_step_symbols {
    if i == self.step_index {
      f.write_string("  •")
    }
    f.write_string("  \{symbol}")
  }
  f.write_string(")")
  if self.done {
    f.write_string("  •  \{self.conflicting_lookahead}  …")
  }
}

///|
pub impl Show for Resolution with fn output(self, f) {
  match self {
    Precedence(symbols~) => {
      f.write_string("Specify a higher precedence in ")
      for i, symbol in symbols {
        if i > 0 {
          f.write_string(" and ")
        }
        f.write_string("`\{symbol}`")
      }
      f.write_string(" than in the other rules.")
    }
    Associativity(symbols~) => {
      f.write_string("Specify a left or right associativity in ")
      for i, symbol in symbols {
        if i > 0 {
          f.write_string(", ")
        }
        f.write_string("`\{symbol}`")
      }
    }
    AddConflict(symbols~) => {
      f.write_string("Add a conflict for these rules: ")
      for i, symbol in symbols {
        if i > 0 {
          f.write_string(", ")
        }
        f.write_string("`\{symbol}`")
      }
    }
  }
}

///|
pub impl Show for AmbiguousExtraError with fn output(self, f) {
  for i, symbol in self.parent_symbols {
    if i > 0 {
      f.write_string(", ")
    }
    f.write_string(symbol)
  }
}

///|
fn ParseTableBuilder::new(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  item_set_builder : ParseItemSetBuilder,
  variable_info : Array[VariableInfo],
  str_pool : StrPool,
) -> ParseTableBuilder {
  let symbol_indexer = SymbolIndexer::new(syntax_grammar, lexical_grammar)
  let actual_conflicts = Map([])
  for conflict in syntax_grammar.expected_conflicts {
    actual_conflicts[conflict.copy()] = ()
  }
  let parse_table = ParseTable::new()
  parse_table.max_aliased_production_length = 1
  {
    syntax_grammar,
    lexical_grammar,
    item_set_builder,
    variable_info,
    non_terminal_extra_states: [],
    state_ids_by_item_set: HashIndex::new(),
    item_sets_by_id: [],
    core_ids_by_core: HashIndex::new(),
    states_by_core_id: [],
    preceding_symbols_by_id: [],
    production_info_ids_by_prod_id: Array::make(
      syntax_grammar.productions.length(),
      None,
    ),
    parse_state_queue: [],
    parse_state_queue_head: 0,
    auxiliary_contexts: AuxiliarySymbolContexts::new(),
    actual_conflicts,
    parse_table,
    action_list_ids: {},
    reusable_action_list_ids: [],
    gotos: [],
    shifts: [],
    lookaheads_with_conflicts: TokenSet::new(),
    reduce_symbols: [symbol_end],
    preceding_symbols: [],
    conflicting_items: [],
    conflict_candidates: [],
    str_pool,
    terminal_entries: TerminalEntryMap::new(symbol_indexer),
    successor_sets: SuccessorSets::new(symbol_indexer),
    reduction_infos: ReductionInfos::new(symbol_indexer),
  }
}

///|
fn ParseTableBuilder::build(
  self : ParseTableBuilder,
  diagnostics : Array[Diagnostic],
) -> (ParseTable, ParseStateInfo) raise ParseTableBuilderError {
  // Ensure that the empty alias sequence has index 0.
  self.parse_table.production_infos.push({
    alias_sequence: [],
    field_map: @sorted_map.SortedMap([]),
  })

  // Add the error state at index 0.
  ignore(self.add_parse_state([], None, ParseItemSet::new()))

  // Add the starting state at index 1.
  let end_lookaheads = self.item_set_builder.lookaheads.singleton(symbol_end)
  ignore(
    self.add_parse_state(
      [],
      None,
      ParseItemSet::singleton(
        ParseItem::start(self.item_set_builder.key_map),
        end_lookaheads,
        0,
      ),
    ),
  )

  // Compute the possible item sets for non-terminal extras.
  let non_terminal_extra_item_sets_by_first_terminal : @sorted_map.SortedMap[
    Symbol,
    ParseItemSet,
  ] = @sorted_map.SortedMap([])
  for extra in self.syntax_grammar.extra_symbols {
    guard extra.non_terminal_index() is Some(extra_index) else { continue }
    let (start, end) = self.syntax_grammar.variable_prod_ids(extra_index)
    for prod_id in start..<end {
      let production = self.syntax_grammar.production(prod_id)
      let item_set = non_terminal_extra_item_sets_by_first_terminal.get_or_init(
        production.first_symbol().unwrap(),
        ParseItemSet::new,
      )
      let entry = item_set.insert(
        ParseItem::new(
          variable_index=extra_index,
          prod_id~,
          step_index=1,
          keys=self.item_set_builder.key_map.keys_for(prod_id),
          has_preceding_inherited_fields=false,
        ),
      )
      item_set.lookaheads[entry] = self.item_set_builder.lookaheads.insert(
        item_set.lookaheads[entry],
        symbol_end_of_nonterminal_extra,
      )
    }
  }

  // Add a state for each starting terminal of a non-terminal extra rule.
  for terminal, item_set in non_terminal_extra_item_sets_by_first_terminal {
    if terminal.non_terminal_index() is Some(_) {
      raise ImproperNonTerminalExtra(self.symbol_name(terminal))
    }

    // Add the parse state, and *then* push the terminal and the state id into the
    // list of nonterminal extra states
    let state_id = self.add_parse_state([], None, item_set)
    self.non_terminal_extra_states.push((terminal, state_id))
  }
  while self.parse_state_queue_head < self.parse_state_queue.length() {
    let entry = self.parse_state_queue[self.parse_state_queue_head]
    self.parse_state_queue_head += 1
    // The dedup-map key is each state's kernel (the GOTO result, pre closure).
    // Two states are identical iff their kernels match.
    let kernel = self.item_sets_by_id[entry.state_id]
    let item_set = self.item_set_builder.transitive_closure(kernel)
    let preceding_symbols = self.preceding_symbols
    preceding_symbols.clear()
    preceding_symbols.append(self.preceding_symbols_by_id[entry.state_id])
    self.add_actions(
      preceding_symbols,
      entry.preceding_auxiliary_context,
      entry.state_id,
      item_set,
    )
    // `add_actions` keeps none of the closure's entries.
    self.item_set_builder.closure_scratch.recycle(item_set)
  }
  if !self.actual_conflicts.is_empty() {
    let conflicts = []
    for conf, _ in self.actual_conflicts {
      conflicts.push(conf.map(s => self.symbol_name(s)))
    }
    // Equal elements are identical, so any sort gives upstream's order.
    conflicts.sort_by(compare_string_lists)
    diagnostics.push(UnnecessaryConflicts(conflicts))
  }
  (
    self.parse_table,
    {
      preceding_symbols_by_id: self.preceding_symbols_by_id,
      item_sets_by_ids: self.item_sets_by_id,
      lookaheads: self.item_set_builder.lookaheads,
    },
  )
}

///|
/// Rust's `Ord` for `Vec<Box<str>>`.
fn compare_string_lists(a : Array[String], b : Array[String]) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let c = rust_str_cmp(a[i], b[i])
    if c != 0 {
      return c
    }
  }
  a.length().compare(b.length())
}

///|
/// An action list as a key of `ParseTableBuilder::action_list_ids`, hashed without
/// `Hasher`'s allocation.
priv struct ActionListKey(Array[ParseAction])

///|
impl Eq for ActionListKey with fn equal(self, other) {
  self.0 == other.0
}

///|
impl Hash for ActionListKey with fn hash_combine(self, hasher) {
  hasher.combine_int(Hash::hash(self))
}

///|
impl Hash for ActionListKey with fn hash(self) {
  let mut acc = hash_mix(HASH_SEED, self.0.length())
  for action in self.0 {
    acc = parse_action_hash_mix(acc, action)
  }
  hash_finish(acc)
}

///|
/// Mixes `action` into a `hash_mix` accumulator.
fn parse_action_hash_mix(acc : UInt32, action : ParseAction) -> UInt32 {
  match action {
    Accept => hash_mix(acc, 0)
    Shift(state~, is_repetition~) =>
      hash_mix(
        hash_mix(hash_mix(acc, 1), state),
        if is_repetition {
          1
        } else {
          0
        },
      )
    ShiftExtra => hash_mix(acc, 2)
    Recover => hash_mix(acc, 3)
    Reduce(symbol~, child_count~, dynamic_precedence~, production_id~) =>
      hash_mix(
        hash_mix(
          hash_mix(hash_mix(hash_mix(acc, 4), symbol.code()), child_count),
          dynamic_precedence,
        ),
        production_id,
      )
  }
}

///|
/// `ActionListId::new(index, reusable)`.
fn ParseTableBuilder::action_list_id(
  self : ParseTableBuilder,
  index : Int32,
  reusable : Bool,
) -> ActionListId {
  if !reusable {
    return ActionListId::new(index, reusable)
  }
  while self.reusable_action_list_ids.length() <= index {
    self.reusable_action_list_ids.push(
      ActionListId::new(self.reusable_action_list_ids.length(), true),
    )
  }
  self.reusable_action_list_ids[index]
}

///|
/// `Shift(state=state_id, is_repetition=false)`, shared like `reusable_action_list_ids`.
fn ParseTableBuilder::shift(
  self : ParseTableBuilder,
  state_id : Int32,
) -> ParseAction {
  while self.shifts.length() <= state_id {
    self.shifts.push(Shift(state=self.shifts.length(), is_repetition=false))
  }
  self.shifts[state_id]
}

///|
/// `Goto(state_id)`.
fn ParseTableBuilder::goto(
  self : ParseTableBuilder,
  state_id : Int32,
) -> GotoAction {
  while self.gotos.length() <= state_id {
    self.gotos.push(Goto(self.gotos.length()))
  }
  self.gotos[state_id]
}

///|
/// `self.parse_table.action_lists.intern(self.action_list_ids, actions)`.
fn ParseTableBuilder::intern_action_list(
  self : ParseTableBuilder,
  actions : Array[ParseAction],
) -> Int32 {
  match self.action_list_ids.get(ActionListKey(actions)) {
    Some(index) => index
    None => {
      let index = self.parse_table.action_lists.push(actions)
      self.action_list_ids[ActionListKey(actions.copy())] = index
      index
    }
  }
}

///|
fn ParseTableBuilder::add_parse_state(
  self : ParseTableBuilder,
  preceding_symbols : Array[Symbol],
  preceding_auxiliary_context : Int32?,
  item_set : ParseItemSet,
) -> Int32 {
  let hash = Hash::hash(item_set)
  match self.find_state(item_set, hash) {
    // If an equivalent item set has already been processed, then return
    // the existing parse state index.
    Some(id) => id
    // Otherwise, insert a new parse state and add it to the queue of
    // parse states to populate.
    None => {
      let state_id = self.parse_table.states.length()
      let core_id = self.core_id(item_set, state_id)
      self.preceding_symbols_by_id.push(preceding_symbols.copy())
      let state = ParseState::new()
      state.id = state_id
      state.core_id = core_id
      self.parse_table.states.push(state)
      self.parse_state_queue.push({ state_id, preceding_auxiliary_context, })
      // Successor sets are built in recycled buffers: keep an exactly sized copy
      // (upstream's clone), so that the buffers stay in use.
      self.state_ids_by_item_set.insert_new(hash, state_id)
      self.item_sets_by_id.push(item_set.copy())
      state_id
    }
  }
}

///|
/// The id of the state whose item set is `item_set`, which hashes to `hash`, if any.
fn ParseTableBuilder::find_state(
  self : ParseTableBuilder,
  item_set : ParseItemSet,
  hash : Int32,
) -> Int32? {
  let index = self.state_ids_by_item_set
  let mut slot = index.first_slot(hash)
  while index.ids[slot] >= 0 {
    let id = index.ids[slot]
    if index.hashes[slot] == hash && self.item_sets_by_id[id] == item_set {
      return Some(id)
    }
    slot = index.next_slot(slot)
  }
  None
}

///|
/// The core id of `item_set`'s core, which is new unless an earlier state has it:
/// `core_ids_by_core.entry(core).or_insert(core_count)`. `state_id` is the id of the
/// new state with this item set.
fn ParseTableBuilder::core_id(
  self : ParseTableBuilder,
  item_set : ParseItemSet,
  state_id : Int32,
) -> Int32 {
  let index = self.core_ids_by_core
  let hash = item_set.core_hash()
  let mut slot = index.first_slot(hash)
  while index.ids[slot] >= 0 {
    let id = index.ids[slot]
    if index.hashes[slot] == hash &&
      self.item_sets_by_id[self.states_by_core_id[id]].same_core(item_set) {
      return id
    }
    slot = index.next_slot(slot)
  }
  let id = self.states_by_core_id.length()
  self.states_by_core_id.push(state_id)
  index.insert_new(hash, id)
  id
}

///|
fn ParseTableBuilder::add_actions(
  self : ParseTableBuilder,
  preceding_symbols : Array[Symbol],
  preceding_auxiliary_context : Int32?,
  state_id : Int32,
  item_set : ParseItemSet,
) -> Unit raise ParseTableBuilderError {
  // Empty: emptied at the end of each state.
  let lookaheads_with_conflicts = self.lookaheads_with_conflicts
  let auxiliary_uses : Array[Int64] = []

  // Each item in the item set contributes to either or a Shift action or a Reduce
  // action in this state.
  for i in 0..<item_set.len() {
    let { item, lookaheads, following_reserved_word_set: reserved_lookaheads, } = item_set.entry(
      i,
    )
    // If the item is unfinished, then this state has a transition for the item's
    // next symbol. Advance the item to its next step and insert the resulting
    // item into the successor item set.
    if !item.is_done() {
      let next_symbol = item.symbol_at(self.syntax_grammar, item.step_index)
      let mut successor = item.successor(self.item_set_builder.key_map)
      if next_symbol.non_terminal_index() is Some(non_terminal_index) {
        let index = non_terminal_index
        let variable = self.syntax_grammar.variables[index]

        // Keep track of where auxiliary non-terminals (repeat symbols) are
        // used within visible symbols. This information may be needed later
        // for conflict resolution.
        if variable.is_auxiliary() {
          let parent = item.variable_index
          auxiliary_uses.push(auxiliary_use(non_terminal_index, parent))
        }

        // For most parse items, the symbols associated with the preceding children
        // don't matter: they have no effect on the REDUCE action that would be
        // performed at the end of the item. But the symbols *do* matter for
        // children that are hidden and have fields, because those fields are
        // "inherited" by the parent node.
        //
        // If this item has consumed a hidden child with fields, then the symbols
        // of its preceding children need to be taken into account when comparing
        // it with other items.
        if variable.is_hidden() && !self.variable_info[index].fields.is_empty() {
          successor = successor.with_preceding_inherited_fields()
        }
      }
      let successor_set = self.successor_sets.item_set(next_symbol)
      let successor_entry = successor_set.insert(successor)
      successor_set.lookaheads[successor_entry] = self.item_set_builder.lookaheads.union(
        successor_set.lookaheads[successor_entry],
        lookaheads,
      )
      if reserved_lookaheads >
        successor_set.following_reserved_word_sets[successor_entry] {
        successor_set.following_reserved_word_sets[successor_entry] = reserved_lookaheads
      }
    } else {
      // If the item is finished, then add a Reduce action to this state based
      // on this item.
      let symbol = Symbol::non_terminal(item.variable_index)
      let action : ParseAction = if item.is_augmented() {
        Accept
      } else {
        // These values are narrowed to u16 to reduce the size of
        // ParseAction. No real-world grammar approaches these limits.
        // (Upstream's `debug_assert!`s of the bounds are not reproduced: like
        // its release builds, `as u16` truncates.)
        let production_id = self.get_production_id(item)
        Reduce(
          symbol~,
          child_count=item.step_index & 0xFFFF,
          dynamic_precedence=item.dynamic_precedence(self.syntax_grammar),
          production_id=production_id & 0xFFFF,
        )
      }
      let precedence = item.precedence(self.syntax_grammar)
      let associativity = item.associativity(self.syntax_grammar)
      let requires_eof_lookahead = item.requires_eof_lookahead(self.syntax_grammar)
      if requires_eof_lookahead {
        self.parse_table.states[state_id].has_eof_gated_reduce = true
      }
      let symbols = self.reduce_symbols
      symbols[0] = symbol
      for lookahead in self.item_set_builder.lookaheads.symbols(lookaheads) {
        if requires_eof_lookahead && lookahead != symbol_end {
          continue
        }
        let table_entry = self.terminal_entries.get_or_insert_new(lookahead)
        let reduction_info = self.reduction_infos.get(lookahead)

        // While inserting Reduce actions, eagerly resolve conflicts related
        // to precedence: avoid inserting lower-precedence reductions, and
        // clear the action list when inserting higher-precedence reductions.
        if table_entry.actions.is_empty() {
          // This is the lookahead's first reduction in this state, so its info is
          // still from an earlier state.
          reduction_info.clear()
          table_entry.actions.push(action)
        } else {
          let ordering = ParseTableBuilder::compare_precedence(
            self.syntax_grammar,
            precedence,
            symbols,
            reduction_info.precedence,
            reduction_info.symbols,
          )
          if ordering > 0 {
            table_entry.actions.clear()
            table_entry.actions.push(action)
            ignore(lookaheads_with_conflicts.remove(lookahead))
            reduction_info.clear()
          } else if ordering == 0 {
            // Two items that reduce identically build the same tree, so
            // there is nothing for the user to resolve. Precedence is
            // still compared first, because an item that only repeats an
            // existing action can still outrank it and clear the entry.
            if !table_entry.actions.contains(action) {
              table_entry.actions.push(action)
              lookaheads_with_conflicts.insert(lookahead)
            }
          } else {
            continue
          }
        }
        reduction_info.precedence = precedence
        if reduction_info.symbols.binary_search(symbol) is Err(i) {
          reduction_info.symbols.insert(i, symbol)
        }
        match associativity {
          Some(Left) => reduction_info.has_left_assoc = true
          Some(Right) => reduction_info.has_right_assoc = true
          None => reduction_info.has_non_assoc = true
        }
      }
    }
  }
  let auxiliary_context = self.auxiliary_contexts.push(
    self.syntax_grammar,
    preceding_auxiliary_context,
    auxiliary_uses,
  )

  // Having computed the successor item sets for each symbol, add a new
  // parse state for each of these item sets, and add a corresponding Shift
  // action to this state.
  // Upstream visits the terminals' successors, then the non-terminals'. Non-terminals
  // come last in symbol order, so a single pass in symbol order does the same.
  let positions = self.successor_sets.sorted_positions()
  for position in positions {
    let symbol = self.successor_sets.indexer.symbol(position)
    let next_item_set = self.successor_sets.take(position)
    preceding_symbols.push(symbol)
    let next_state_id = self.add_parse_state(
      preceding_symbols, auxiliary_context, next_item_set,
    )
    ignore(preceding_symbols.pop())
    // `add_parse_state` keeps a copy of a new state's kernel.
    self.successor_sets.recycle(next_item_set)
    if symbol.non_terminal_index() is Some(_) {
      self.parse_table.states[state_id].nonterminal_entries.push(
        symbol,
        self.goto(next_state_id),
      )
    } else {
      if self.terminal_entries.get(symbol) is Some(e) && !e.actions.is_empty() {
        lookaheads_with_conflicts.insert(symbol)
      }
      self.terminal_entries.get_or_insert_new(symbol).actions.push(
        self.shift(next_state_id),
      )
    }
  }
  positions.clear()

  // For any symbol with multiple actions, perform conflict resolution.
  // This will either
  // * choose one action over the others using precedence or associativity
  // * keep multiple actions if this conflict has been whitelisted in the grammar
  // * fail, terminating the parser generation process
  if !lookaheads_with_conflicts.is_empty() {
    // Only fnished items and items past their first step can take part in a
    // conflict. Most of a closure is neither, so find those items once per state.
    let candidates = self.conflict_candidates
    candidates.clear()
    for i in 0..<item_set.len() {
      let item = item_set.items[i]
      if item.step_index > 0 || item.is_done() {
        candidates.push(item_set.entry(i))
      }
    }
    let symbols = lookaheads_with_conflicts.iter()
    for symbol in symbols {
      self.handle_conflict(
        candidates, preceding_symbols, auxiliary_context, symbol,
      )
    }
    for symbol in symbols {
      ignore(lookaheads_with_conflicts.remove(symbol))
    }
  }

  // Add actions for the grammar's `extra` symbols.
  let state = self.parse_table.states[state_id]
  // Same check as `ParseState::is_end_of_non_terminal_extra` for entries not in the table yet
  let is_end_of_non_terminal_extra = self.terminal_entries.contains(
    symbol_end_of_nonterminal_extra,
  )

  // If this state represents the end of a non-terminal extra rule, then make sure that
  // it doesn't have other successor states. Non-terminal extra rules must have
  // unambiguous endings.
  if is_end_of_non_terminal_extra {
    if self.terminal_entries.length() > 1 {
      let parent_symbol_ids : Array[Int32] = []
      for item in item_set.items {
        if !item.is_augmented() && item.step_index > 0 {
          parent_symbol_ids.push(item.variable_index)
        }
      }
      // Upstream collects these into an `FxHashSet<u32>`, so they're listed in
      // that set's iteration order.
      let parent_symbols = fx_hash_set_u32_order(parent_symbol_ids)
      let parent_symbol_names = parent_symbols.map(variable_index => {
        self.str_pool.resolve(
          self.syntax_grammar.variables[variable_index].name,
        )
      })
      raise AmbiguousExtra({ parent_symbols: parent_symbol_names, })
    }
  } else {
    // Add actions for the start tokens of each non-terminal extra rule.
    for extra_state in self.non_terminal_extra_states {
      let (terminal, state_id) = extra_state
      if !self.terminal_entries.contains(terminal) {
        self.terminal_entries.get_or_insert_new(terminal).actions.push(
          Shift(state=state_id, is_repetition=false),
        )
      }
    }

    // Add ShiftExtra actions for the terminal extra tokens. These actions
    // are added to every state except for those at the ends of non-terminal
    // extras.
    for extra_token in self.syntax_grammar.extra_symbols {
      match extra_token.kind {
        NonTerminal => state.nonterminal_entries.insert(extra_token, ShiftExtra)
        Terminal | External =>
          if !self.terminal_entries.contains(extra_token) {
            self.terminal_entries.get_or_insert_new(extra_token).actions.push(
              ShiftExtra,
            )
          }
        End | EndOfNonTerminalExtra => abort("unreachable")
      }
    }
  }
  if self.syntax_grammar.word_token is Some(keyword_capture_token) {
    let mut reserved_word_set_id : Int32? = None
    for i in 0..<item_set.len() {
      let entry = item_set.entry(i)
      let id = match entry.item.step(self.syntax_grammar) {
        Some(next_step) =>
          if next_step.symbol == keyword_capture_token {
            Some(next_step.reserved)
          } else {
            None
          }
        None =>
          if self.item_set_builder.lookaheads
            .get(entry.lookaheads)
            .contains(keyword_capture_token) {
            Some(entry.following_reserved_word_set)
          } else {
            None
          }
      }
      if id is Some(id) {
        reserved_word_set_id = match reserved_word_set_id {
          Some(max) if max >= id => Some(max)
          _ => Some(id)
        }
      }
    }
    if reserved_word_set_id is Some(reserved_word_set_id) {
      state.reserved_words = self.syntax_grammar.reserved_word_sets[reserved_word_set_id].copy()
    }
  }

  // Every state stays in the table until minimization, so store its terminal entries as
  // interned action lists.
  state.terminal_entries.reserve(self.terminal_entries.keys.length())
  for position, symbol in self.terminal_entries.keys {
    let entry = self.terminal_entries.values[position]
    let index = self.intern_action_list(entry.actions)
    state.terminal_entries.push(
      symbol,
      self.action_list_id(index, entry.reusable),
    )
  }
  self.terminal_entries.clear()
}

///|
/// The iteration order of an `FxHashSet<u32>` (Rust 1.97 `std`, 64-bit,
/// `rustc-hash` 2.1) collected from `values` in order. The set's table is
/// simulated: `std`'s hashbrown places each value by its hash, growing the
/// table as it fills, and iterates its buckets in index order.
fn fx_hash_set_u32_order(values : Array[Int32]) -> Array[Int32] {
  // An empty table has one (empty) bucket and no room.
  let mut slots : Array[Int32?] = [None]
  let mut growth_left = 0
  let mut items = 0
  for value in values {
    // `HashMap::insert` reserves room for one more item before looking
    // the value up.
    if growth_left == 0 {
      let new_capacity = {
        let full_capacity = fx_bucket_mask_to_capacity(slots.length() - 1)
        if items + 1 > full_capacity + 1 {
          items + 1
        } else {
          full_capacity + 1
        }
      }
      let new_slots : Array[Int32?] = Array::make(
        fx_capacity_to_buckets(new_capacity),
        None,
      )
      for slot in slots {
        if slot is Some(old) {
          new_slots[fx_find_insert_slot(new_slots, old)] = Some(old)
        }
      }
      growth_left = fx_bucket_mask_to_capacity(new_slots.length() - 1) - items
      slots = new_slots
    }
    if slots.contains(Some(value)) {
      continue
    }
    slots[fx_find_insert_slot(slots, value)] = Some(value)
    growth_left -= 1
    items += 1
  }
  let result = []
  for slot in slots {
    if slot is Some(value) {
      result.push(value)
    }
  }
  result
}

///|
/// hashbrown's `capacity_to_buckets`.
fn fx_capacity_to_buckets(capacity : Int32) -> Int32 {
  if capacity < 8 {
    return if capacity < 4 { 4 } else { 8 }
  }
  let adjusted = capacity * 8 / 7
  let mut buckets = 1
  while buckets < adjusted {
    buckets *= 2
  }
  buckets
}

///|
/// hashbrown's `bucket_mask_to_capacity`.
fn fx_bucket_mask_to_capacity(bucket_mask : Int32) -> Int32 {
  if bucket_mask < 8 {
    bucket_mask
  } else {
    (bucket_mask + 1) / 8 * 7
  }
}

///|
/// hashbrown's `find_insert_slot`, with 8-byte control groups (NEON and
/// generic). A table smaller than a group sees its own buckets, then empty
/// padding, then a mirror of its first buckets.
fn fx_find_insert_slot(slots : Array[Int32?], value : Int32) -> Int32 {
  // `FxHasher::write_u32` then `finish`.
  let product = value.to_uint64() * 0xf1357aea2e62a9c5UL
  let hash = (product << 26) | (product >> 38)
  let buckets = slots.length()
  let mask = buckets - 1
  let mut pos = (hash & mask.to_uint64()).to_int()
  let mut stride = 0
  while true {
    for j in 0..<8 {
      let p = pos + j
      let empty = if buckets >= 8 {
        slots[p & mask] is None
      } else if p < buckets {
        slots[p] is None
      } else if p < 8 {
        true
      } else {
        slots[p - 8] is None
      }
      if empty {
        let index = p & mask
        if slots[index] is None {
          return index
        }
        // Only possible in a table smaller than a group: take the first empty
        // bucket instead.
        for i in 0..<buckets {
          if slots[i] is None {
            return i
          }
        }
      }
    }
    stride += 8
    pos = (pos + stride) & mask
  }
  abort("unreachable")
}

///|
fn ParseTableBuilder::handle_conflict(
  self : ParseTableBuilder,
  candidates : Array[ParseItemSetEntry],
  preceding_symbols : Array[Symbol],
  auxiliary_context : Int32?,
  conflicting_lookahead : Symbol,
) -> Unit raise ParseTableBuilderError {
  let entry = self.terminal_entries.get(conflicting_lookahead).unwrap()
  let reduction_info = self.reduction_infos.get(conflicting_lookahead)

  // Determine which items in the set conflict with each other, and the
  // precedences associated with SHIFT vs REDUCE actions. There won't
  // be multiple REDUCE actions with different precedences; that is
  // sorted out ahead of time in `add_actions`. But there can still be
  // REDUCE-REDUCE conflicts where all actions have the *same*
  // precedence, and there can still be SHIFT/REDUCE conflicts.
  let mut considered_associativity = false
  let shift_precedence : Array[(Precedence, Symbol)] = []
  // Upstream's `BTreeSet<&ParseItem>`: sorted, without duplicates.
  let conflicting_items = self.conflicting_items
  conflicting_items.clear()
  for candidate in candidates {
    let item = candidate.item
    if item.step(self.syntax_grammar) is Some(step) {
      if item.step_index > 0 &&
        self.item_set_builder
        .first_set(step.symbol)
        .contains(conflicting_lookahead) {
        if item.variable_index != augmented_variable_index &&
          conflicting_items.binary_search(item) is Err(i) {
          conflicting_items.insert(i, item)
        }
        let p = (
          item.precedence(self.syntax_grammar),
          Symbol::non_terminal(item.variable_index),
        )
        if shift_precedence.binary_search(p) is Err(i) {
          shift_precedence.insert(i, p)
        }
      }
    } else if self.item_set_builder.lookaheads
      .get(candidate.lookaheads)
      .contains(conflicting_lookahead) &&
      item.variable_index != augmented_variable_index &&
      conflicting_items.binary_search(item) is Err(i) {
      conflicting_items.insert(i, item)
    }
  }
  if entry.actions.last() is Some(Shift(state~, ..)) {
    // If all of the items in the conflict have the same parent symbol,
    // and that parent symbols is auxiliary, then this is just the intentional
    // ambiguity associated with a repeat rule. Resolve that class of ambiguity
    // by leaving it in the parse table, but marking the SHIFT action with
    // an `is_repetition` flag.
    let conflicting_variable_index = conflicting_items[0].variable_index
    if self.syntax_grammar.variables[conflicting_variable_index].is_auxiliary() &&
      conflicting_items
      .iter()
      .all(item => item.variable_index == conflicting_variable_index) {
      entry.actions[entry.actions.length() - 1] = Shift(
        state~,
        is_repetition=true,
      )
      return
    }

    // If the SHIFT action has higher precedence, remove all the REDUCE actions.
    let mut shift_is_less = false
    let mut shift_is_equal = false
    let mut shift_is_more = false
    for p in shift_precedence {
      let ordering = ParseTableBuilder::compare_precedence(
        self.syntax_grammar,
        p.0,
        [p.1],
        reduction_info.precedence,
        reduction_info.symbols,
      )
      if ordering > 0 {
        shift_is_more = true
      } else if ordering < 0 {
        shift_is_less = true
      } else {
        shift_is_equal = true
      }
    }
    if shift_is_more && !shift_is_less {
      action_list_keep_last(entry.actions)
    } else if shift_is_less && !shift_is_more {
      // If the REDUCE actions have higher precedence, remove the SHIFT action.
      //
      // Exception: if one SHIFT interpretation ties the REDUCE actions in
      // precedence while another has lower precedence, and the REDUCE
      // actions are purely right associative, honor that right
      // associativity by shifting rather than reducing. The
      // lower-precedence interpretation coexists with the tying one, so on
      // its own it must not force a REDUCE that would flip the tie to left
      // associative.
      if shift_is_equal &&
        !reduction_info.has_left_assoc &&
        !reduction_info.has_non_assoc &&
        reduction_info.has_right_assoc {
        action_list_keep_last(entry.actions)
      } else {
        ignore(entry.actions.pop())
        conflicting_items.retain(item => item.is_done())
      }
    } else if !shift_is_less && !shift_is_more {
      // If the SHIFT and REDUCE actions have the same precedence, consider
      // the REDUCE actions' associativity.
      considered_associativity = true

      // If all Reduce actions are left associative, remove the SHIFT action.
      // If all Reduce actions are right associative, remove the REDUCE actions.
      match
        (
          reduction_info.has_left_assoc,
          reduction_info.has_non_assoc,
          reduction_info.has_right_assoc,
        ) {
        (true, false, false) => {
          ignore(entry.actions.pop())
          conflicting_items.retain(item => item.is_done())
        }
        (false, false, true) => action_list_keep_last(entry.actions)
        _ => ()
      }
    }
  }

  // If all of the actions but one have been eliminated, then there's no problem.
  let entry = self.terminal_entries.get(conflicting_lookahead).unwrap()
  if entry.actions.length() == 1 {
    return
  }

  // Determine the set of parent symbols involved in this conflict.
  let actual_conflict : Array[Symbol] = []
  for item in conflicting_items {
    let symbol = Symbol::non_terminal(item.variable_index)
    if self.syntax_grammar.variables[item.variable_index].is_auxiliary() {
      for
        parent in self.auxiliary_contexts
        .parents(auxiliary_context, item.variable_index)
        .unwrap() {
        actual_conflict.push(parent)
      }
    } else {
      actual_conflict.push(symbol)
    }
  }
  actual_conflict.sort()
  dedup(actual_conflict)

  // If this set of symbols has been whitelisted, then there's no error.
  if self.syntax_grammar.expected_conflicts.contains(actual_conflict) {
    self.actual_conflicts.remove(actual_conflict)
    return
  }
  let symbol_sequence = preceding_symbols.map(symbol => self.symbol_name(symbol))
  let conflicting_lookahead_name = self.symbol_name(conflicting_lookahead)
  let interpretations = conflicting_items.map(item => {
    let preceding_symbols = preceding_symbols[0:preceding_symbols.length() -
      item.step_index]
      .iter()
      .map(symbol => self.symbol_name(symbol))
      .collect()
    let variable_name = self.str_pool.resolve(
      self.syntax_grammar.variables[item.variable_index].name,
    )
    let production_step_symbols = item.production(self.syntax_grammar).steps
      .iter()
      .map(step => self.symbol_name(step.symbol))
      .collect()
    let precedence = match item.precedence(self.syntax_grammar) {
      NoPrecedence => None
      _ =>
        Some(prec_display(item.precedence(self.syntax_grammar), self.str_pool))
    }
    let associativity = match item.associativity(self.syntax_grammar) {
      Some(assoc) => Some(assoc_debug(assoc))
      None => None
    }
    Interpretation::{
      preceding_symbols,
      variable_name,
      production_step_symbols,
      step_index: item.step_index,
      done: item.is_done(),
      conflicting_lookahead: conflicting_lookahead_name,
      precedence,
      associativity,
      requires_eof_lookahead: item.production(self.syntax_grammar).requires_eof_lookahead,
    }
  })
  let possible_resolutions = []
  let shift_items = []
  let reduce_items = []
  for item in conflicting_items {
    if item.is_done() {
      reduce_items.push(item)
    } else {
      shift_items.push(item)
    }
  }
  // Already sorted, as a subsequence of `conflicting_items`.
  let get_rule_names = (items : Array[ParseItem]) => {
    let mut last_rule_id = None
    let result = []
    for item in items {
      if last_rule_id == Some(item.variable_index) {
        continue
      }
      last_rule_id = Some(item.variable_index)
      result.push(self.symbol_name(Symbol::non_terminal(item.variable_index)))
    }
    result
  }
  if actual_conflict.length() > 1 {
    if !shift_items.is_empty() {
      let names = get_rule_names(shift_items)
      possible_resolutions.push(Resolution::Precedence(symbols=names))
    }
    for item in reduce_items {
      let name = self.symbol_name(Symbol::non_terminal(item.variable_index))
      possible_resolutions.push(Resolution::Precedence(symbols=[name]))
    }
  }
  if considered_associativity {
    let names = get_rule_names(reduce_items)
    possible_resolutions.push(Resolution::Associativity(symbols=names))
  }
  possible_resolutions.push(
    Resolution::AddConflict(
      symbols=actual_conflict.map(s => self.symbol_name(s)),
    ),
  )
  self.actual_conflicts[actual_conflict] = ()
  raise Conflict({
    symbol_sequence,
    conflicting_lookahead: conflicting_lookahead_name,
    possible_interpretations: interpretations,
    possible_resolutions,
  })
}

///|
fn ParseTableBuilder::compare_precedence(
  grammar : SyntaxGrammar,
  left : Precedence,
  left_symbols : Array[Symbol],
  right : Precedence,
  right_symbols : Array[Symbol],
) -> Int32 {
  match (left, right) {
    // Integer precedences can be compared to other integer precedences,
    // and to the default precedence, which is zero.
    (Integer(l), Integer(r)) if l != 0 || r != 0 => l.compare(r)
    (Integer(l), NoPrecedence) if l != 0 => l.compare(0)
    (NoPrecedence, Integer(r)) if r != 0 => (0).compare(r)
    // Named precedences can be compared to other named precedences.
    _ => {
      for list in grammar.precedence_orderings {
        let mut saw_left = false
        let mut saw_right = false
        for entry in list {
          if precedence_entry_matches(grammar, entry, left, left_symbols) {
            saw_left = true
            if saw_right {
              return -1
            }
          } else if precedence_entry_matches(
              grammar, entry, right, right_symbols,
            ) {
            saw_right = true
            if saw_left {
              return 1
            }
          }
        }
      }
      0
    }
  }
}

///|
/// `compare_precedence`'s `precedence_entry_matches` closure. (`compare_precedence`
/// only evaluates the right side's match when the left side's doesn't hold, which is
/// unobservable: matching has no effects.)
fn precedence_entry_matches(
  grammar : SyntaxGrammar,
  entry : PrecedenceEntry,
  precedence : Precedence,
  symbols : Array[Symbol],
) -> Bool {
  match entry {
    Name(n) =>
      match precedence {
        Name(p) => n == p
        _ => false
      }
    Symbol(n) => {
      for s in symbols {
        if s.kind is NonTerminal && grammar.variables[s.index].name == n {
          return true
        }
      }
      false
    }
  }
}

///|
fn ParseTableBuilder::get_production_id(
  self : ParseTableBuilder,
  item : ParseItem,
) -> Int32 {
  if self.production_info_ids_by_prod_id[item.prod_id] is Some(id) {
    return id
  }
  let production_info : ProductionInfo = {
    alias_sequence: [],
    field_map: @sorted_map.SortedMap([]),
  }
  let steps = item.production(self.syntax_grammar).steps
  for i, step in steps {
    production_info.alias_sequence.push(step.alias)
    if step.field is Some(field_name) {
      production_info.field_map
      .get_or_init(field_name, () => [])
      .push({ index: i, inherited: false, })
    }
    if step.non_terminal_index() is Some(index) &&
      !self.syntax_grammar.variables[index].kind.is_visible() {
      let info = self.variable_info[index]
      // Upstream iterates an `FxHashMap` here. Each field name gets its own
      // list, so the iteration order is unobservable.
      for field_name, _ in info.fields {
        production_info.field_map
        .get_or_init(field_name, () => [])
        .push({ index: i, inherited: true, })
      }
    }
  }
  while production_info.alias_sequence.last() is Some(None) {
    ignore(production_info.alias_sequence.pop())
  }
  if steps.length() > self.parse_table.max_aliased_production_length {
    self.parse_table.max_aliased_production_length = steps.length()
  }
  let mut id = -1
  for index, seq in self.parse_table.production_infos {
    if seq == production_info {
      id = index
      break
    }
  }
  if id == -1 {
    self.parse_table.production_infos.push(production_info)
    id = self.parse_table.production_infos.length() - 1
  }
  self.production_info_ids_by_prod_id[item.prod_id] = Some(id)
  id
}

///|
fn ParseTableBuilder::symbol_name(
  self : ParseTableBuilder,
  symbol : Symbol,
) -> String {
  match symbol.kind {
    End | EndOfNonTerminalExtra => "EOF"
    External =>
      self.str_pool.resolve(
        self.syntax_grammar.external_tokens[symbol.index].name,
      )
    NonTerminal =>
      self.str_pool.resolve(self.syntax_grammar.variables[symbol.index].name)
    Terminal => {
      let variable = self.lexical_grammar.variables[symbol.index]
      if variable.kind == Named {
        self.str_pool.resolve(variable.name)
      } else {
        "'\{self.str_pool.resolve(variable.name)}'"
      }
    }
  }
}

///|
fn build_parse_table(
  syntax_grammar : SyntaxGrammar,
  lexical_grammar : LexicalGrammar,
  item_set_builder : ParseItemSetBuilder,
  variable_info : Array[VariableInfo],
  str_pool : StrPool,
  diagnostics : Array[Diagnostic],
) -> (ParseTable, ParseStateInfo) raise ParseTableBuilderError {
  ParseTableBuilder::new(
    syntax_grammar, lexical_grammar, item_set_builder, variable_info, str_pool,
  ).build(diagnostics)
}
