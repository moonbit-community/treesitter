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
  parent_set_ids : Map[Array[Symbol], Int32]
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
  uses : Array[(Int32, Int32)],
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
    while group_end < uses.length() && uses[group_end].0 == uses[group_start].0 {
      group_end += 1
    }
    parents.clear()
    for i in group_start..<group_end {
      let parent = uses[i].1
      if !grammar.variables[parent].is_auxiliary() {
        parents.push(Symbol::non_terminal(parent))
      }
    }
    let parent_set = self.intern(parents)
    let symbol = uses[group_start].0
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
  match self.parent_set_ids.get(parents) {
    Some(id) => id
    None => {
      let id = self.parent_sets.length()
      self.parent_sets.push((self.parent_symbols.length(), parents.length()))
      for symbol in parents {
        self.parent_symbols.push(symbol)
      }
      self.parent_set_ids[parents.copy()] = id
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
  /// The symbols that have a set in `sets`, in the order their sets were added.
  symbols : Array[Symbol]
}

///|
fn SuccessorSets::new(indexer : SymbolIndexer) -> SuccessorSets {
  { indexer, sets: Array::make(indexer.symbol_count(), None), symbols: [], }
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
      self.symbols.push(symbol)
      let set = ParseItemSet::new()
      self.sets[index] = Some(set)
      set
    }
  }
}

///|
/// Takes the sets out in symbol order, leaving this empty for the next state.
fn SuccessorSets::take_all(
  self : SuccessorSets,
) -> Array[(Symbol, ParseItemSet)] {
  // Symbols are distinct, so the order is total.
  self.symbols.sort()
  let result = self.symbols.map(symbol => {
    let index = self.indexer.index(symbol)
    // INVARIANT: every symbol in `symbols` has a set
    let set = self.sets[index].unwrap()
    self.sets[index] = None
    (symbol, set)
  })
  self.symbols.clear()
  result
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
  core_ids_by_core : Map[ParseItemSetCore, Int32]
  /// Upstream's `IndexMap<ParseItemSet, ParseStateId>`: the map for lookups,
  /// and `item_sets_by_id` for access by insertion index.
  state_ids_by_item_set : Map[ParseItemSet, Int32]
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
  action_list_ids : Map[Array[ParseAction], Int32]
  str_pool : StrPool
  /// Scratch for `add_actions`: The terminal entries of the state it's working on. They are
  /// interned into the table once the state is complete.
  terminal_entries : Map[Symbol, ParseTableEntry]
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
    state_ids_by_item_set: {},
    item_sets_by_id: [],
    core_ids_by_core: {},
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
    str_pool,
    terminal_entries: {},
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
    self.add_parse_state([], None, {
      entries: [
        {
          item: ParseItem::start(self.item_set_builder.key_map),
          lookaheads: end_lookaheads,
          following_reserved_word_set: 0,
        },
      ],
    }),
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
      let entry = non_terminal_extra_item_sets_by_first_terminal
        .get_or_init(production.first_symbol().unwrap(), ParseItemSet::new)
        .insert({
          variable_index: extra_index,
          prod_id,
          step_index: 1,
          keys: self.item_set_builder.key_map.keys_for(prod_id),
          has_preceding_inherited_fields: false,
        })
      entry.lookaheads = self.item_set_builder.lookaheads.insert(
        entry.lookaheads,
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
    self.add_actions(
      self.preceding_symbols_by_id[entry.state_id].copy(),
      entry.preceding_auxiliary_context,
      entry.state_id,
      item_set,
    )
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
fn ParseTableBuilder::add_parse_state(
  self : ParseTableBuilder,
  preceding_symbols : Array[Symbol],
  preceding_auxiliary_context : Int32?,
  item_set : ParseItemSet,
) -> Int32 {
  match self.state_ids_by_item_set.get(item_set) {
    // If an equivalent item set has already been processed, then return
    // the existing parse state index.
    Some(id) => id
    // Otherwise, insert a new parse state and add it to the queue of
    // parse states to populate.
    None => {
      let core = item_set.core()
      let core_count = self.core_ids_by_core.length()
      let core_id = self.core_ids_by_core.get_or_init(core, () => core_count)
      let state_id = self.parse_table.states.length()
      self.preceding_symbols_by_id.push(preceding_symbols.copy())
      let state = ParseState::new()
      state.id = state_id
      state.core_id = core_id
      self.parse_table.states.push(state)
      self.parse_state_queue.push({ state_id, preceding_auxiliary_context, })
      // The successor sets that reach here are never touched again, so the
      // map can keep them without the clone upstream makes.
      self.state_ids_by_item_set[item_set] = state_id
      self.item_sets_by_id.push(item_set)
      state_id
    }
  }
}

///|
fn ParseTableBuilder::add_actions(
  self : ParseTableBuilder,
  preceding_symbols : Array[Symbol],
  preceding_auxiliary_context : Int32?,
  state_id : Int32,
  item_set : ParseItemSet,
) -> Unit raise ParseTableBuilderError {
  let lookaheads_with_conflicts = TokenSet::new()
  let auxiliary_uses : Array[(Int32, Int32)] = []

  // Each item in the item set contributes to either or a Shift action or a Reduce
  // action in this state.
  for entry in item_set.entries {
    let { item, lookaheads, following_reserved_word_set: reserved_lookaheads, } = entry
    // If the item is unfinished, then this state has a transition for the item's
    // next symbol. Advance the item to its next step and insert the resulting
    // item into the successor item set.
    if item.symbol(self.syntax_grammar) is Some(next_symbol) {
      let mut successor = item.successor()
      if next_symbol.non_terminal_index() is Some(non_terminal_index) {
        let index = non_terminal_index
        let variable = self.syntax_grammar.variables[index]

        // Keep track of where auxiliary non-terminals (repeat symbols) are
        // used within visible symbols. This information may be needed later
        // for conflict resolution.
        if variable.is_auxiliary() {
          let parent = item.variable_index
          auxiliary_uses.push((non_terminal_index, parent))
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
          successor = { ..successor, has_preceding_inherited_fields: true, }
        }
      }
      let successor_set = self.successor_sets.item_set(next_symbol)
      let successor_entry = successor_set.insert(successor)
      successor_entry.lookaheads = self.item_set_builder.lookaheads.union(
        successor_entry.lookaheads,
        lookaheads,
      )
      if reserved_lookaheads > successor_entry.following_reserved_word_set {
        successor_entry.following_reserved_word_set = reserved_lookaheads
      }
    } else {
      // If the item is finished, then add a Reduce action to this state based
      // on this item.
      let symbol = Symbol::non_terminal(item.variable_index)
      let action : ParseAction = if item.is_augmented() {
        Accept
      } else {
        let production_id = self.get_production_id(item)
        Reduce(
          symbol~,
          child_count=item.step_index,
          dynamic_precedence=item.production(self.syntax_grammar).dynamic_precedence,
          production_id~,
        )
      }
      let precedence = item.precedence(self.syntax_grammar)
      let associativity = item.associativity(self.syntax_grammar)
      let requires_eof_lookahead = item.production(self.syntax_grammar).requires_eof_lookahead
      if requires_eof_lookahead {
        self.parse_table.states[state_id].has_eof_gated_reduce = true
      }
      for lookahead in self.item_set_builder.lookaheads.get(lookaheads).iter() {
        if requires_eof_lookahead && lookahead != symbol_end {
          continue
        }
        let table_entry = self.terminal_entries.get_or_init(
          lookahead,
          ParseTableEntry::new,
        )
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
            [symbol],
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
  let successors = self.successor_sets.take_all()
  // Non-terminals come last in symbol order.
  for successor in successors {
    let (symbol, next_item_set) = successor
    if symbol.non_terminal_index() is Some(_) {
      continue
    }
    preceding_symbols.push(symbol)
    let next_state_id = self.add_parse_state(
      preceding_symbols, auxiliary_context, next_item_set,
    )
    ignore(preceding_symbols.pop())
    if self.terminal_entries.get(symbol) is Some(e) && !e.actions.is_empty() {
      lookaheads_with_conflicts.insert(symbol)
    }
    self.terminal_entries.get_or_init(symbol, ParseTableEntry::new).actions.push(
      Shift(state=next_state_id, is_repetition=false),
    )
  }
  for successor in successors {
    let (symbol, next_item_set) = successor
    if symbol.non_terminal_index() is None {
      continue
    }
    preceding_symbols.push(symbol)
    let next_state_id = self.add_parse_state(
      preceding_symbols, auxiliary_context, next_item_set,
    )
    ignore(preceding_symbols.pop())
    self.parse_table.states[state_id].nonterminal_entries.push(
      symbol,
      Goto(next_state_id),
    )
  }

  // For any symbol with multiple actions, perform conflict resolution.
  // This will either
  // * choose one action over the others using precedence or associativity
  // * keep multiple actions if this conflict has been whitelisted in the grammar
  // * fail, terminating the parser generation process
  if !lookaheads_with_conflicts.is_empty() {
    // Only fnished items and items past their first step can take part in a
    // conflict. Most of a closure is neither, so find those items once per state.
    let candidates = item_set.entries.filter(entry => {
      entry.item.step_index > 0 || entry.item.is_done()
    })
    for symbol in lookaheads_with_conflicts.iter() {
      self.handle_conflict(
        candidates, preceding_symbols, auxiliary_context, symbol,
      )
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
      // NOTE: upstream collects these into an `FxHashSet<u32>` and lists them
      // in its iteration order. Here they are listed in the order they're first
      // found, which only differs when several rules are involved.
      let parent_symbols : Array[Int32] = []
      for entry in item_set.entries {
        let item = entry.item
        if !item.is_augmented() &&
          item.step_index > 0 &&
          !parent_symbols.contains(item.variable_index) {
          parent_symbols.push(item.variable_index)
        }
      }
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
      ignore(
        self.terminal_entries.get_or_init(terminal, () => {
          reusable: true,
          actions: [Shift(state=state_id, is_repetition=false)],
        }),
      )
    }

    // Add ShiftExtra actions for the terminal extra tokens. These actions
    // are added to every state except for those at the ends of non-terminal
    // extras.
    for extra_token in self.syntax_grammar.extra_symbols {
      match extra_token.kind {
        NonTerminal => state.nonterminal_entries.insert(extra_token, ShiftExtra)
        Terminal | External =>
          ignore(
            self.terminal_entries.get_or_init(extra_token, () => {
              reusable: true,
              actions: [ShiftExtra],
            }),
          )
        End | EndOfNonTerminalExtra => abort("unreachable")
      }
    }
  }
  if self.syntax_grammar.word_token is Some(keyword_capture_token) {
    let mut reserved_word_set_id : Int32? = None
    for entry in item_set.entries {
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
  for symbol, entry in self.terminal_entries {
    let index = self.parse_table.action_lists.intern(
      self.action_list_ids,
      entry.actions,
    )
    state.terminal_entries.push(
      symbol,
      ActionListId::new(index, entry.reusable),
    )
  }
  self.terminal_entries.clear()
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
  let conflicting_items : Array[ParseItem] = []
  let insert_item = (item : ParseItem) => {
    if conflicting_items.binary_search(item) is Err(i) {
      conflicting_items.insert(i, item)
    }
  }
  for candidate in candidates {
    let item = candidate.item
    if item.step(self.syntax_grammar) is Some(step) {
      if item.step_index > 0 &&
        self.item_set_builder
        .first_set(step.symbol)
        .contains(conflicting_lookahead) {
        if item.variable_index != augmented_variable_index {
          insert_item(item)
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
      item.variable_index != augmented_variable_index {
      insert_item(item)
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
  let precedence_entry_matches = (
    entry : PrecedenceEntry,
    precedence : Precedence,
    symbols : Array[Symbol],
  ) => {
    match entry {
      Name(n) =>
        match precedence {
          Name(p) => n == p
          _ => false
        }
      Symbol(n) =>
        symbols
        .iter()
        .any(s => {
          match s.kind {
            NonTerminal => grammar.variables[s.index].name == n
            _ => false
          }
        })
    }
  }
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
          let matches_left = precedence_entry_matches(entry, left, left_symbols)
          let matches_right = precedence_entry_matches(
            entry, right, right_symbols,
          )
          if matches_left {
            saw_left = true
            if saw_right {
              return -1
            }
          } else if matches_right {
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
