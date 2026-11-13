// Port of tree-sitter crates/generate/src/grammars.rs.

///|
/// Declaration order defines the derived ordering (matches upstream).
#derive(Eq, Hash, Compare, Debug)
pub(all) enum VariableType {
  Hidden
  Auxiliary
  Anonymous
  Named
}

///|
pub fn VariableType::is_visible(self : VariableType) -> Bool {
  self is (Named | Anonymous)
}

///|
#derive(Eq, Debug)
pub(all) struct Variable {
  name : StrId
  root : RuleId
}

///|
#derive(Eq, Hash, Compare, Debug)
pub(all) enum PrecedenceEntry {
  Name(StrId)
  Symbol(StrId)
}

///|
#derive(Debug)
pub(all) struct ReservedWordContext {
  name : StrId
  roots : Array[RuleId]
}

///|
/// The parsed grammar.
pub(all) struct InputGrammar {
  pool : RulePool
  mut name : StrId
  mut variables : Array[Variable]
  mut external_roots : Array[RuleId]
  mut extra_roots : Array[RuleId]
  mut reserved_sets : Array[ReservedWordContext]
  mut supertype_names : Array[StrId]
  mut conflict_names : Array[Array[StrId]]
  mut inline_names : Array[StrId]
  mut word_name : StrId?
  mut precedence_orderings : Array[Array[PrecedenceEntry]]
}

///|
pub fn InputGrammar::new() -> InputGrammar {
  {
    pool: RulePool::new(),
    name: empty_str_id,
    variables: [],
    external_roots: [],
    extra_roots: [],
    reserved_sets: [],
    supertype_names: [],
    conflict_names: [],
    inline_names: [],
    word_name: None,
    precedence_orderings: [],
  }
}

///|
#derive(Eq, Debug)
pub(all) struct LexicalVariable {
  name : StrId
  kind : VariableType
  implicit_precedence : Int32
  start_state : Int32
}

///|
#derive(Eq, Debug)
pub(all) struct LexicalGrammar {
  nfa : Nfa
  variables : Array[LexicalVariable]
}

///|
pub fn LexicalGrammar::new() -> LexicalGrammar {
  { nfa: Nfa::new(), variables: [], }
}

///|
/// Indices of the variables owning `state_ids`, skipping consecutive repeats.
pub fn LexicalGrammar::variable_indices_for_nfa_states(
  self : LexicalGrammar,
  state_ids : ArrayView[Int32],
) -> Array[Int32] {
  let result = []
  let mut prev : Int32? = None
  for state_id in state_ids {
    let variable_id = self.variable_index_for_nfa_state(state_id)
    if prev != Some(variable_id) {
      prev = Some(variable_id)
      result.push(variable_id)
    }
  }
  result
}

///|
/// The NFA is built in reverse (accept state first, entry state last), so each
/// variable's `start_state` is the highest NFA state allocated for it. These
/// values are monotonically increasing, so binary search for the first
/// variable whose `start_state >= state_id`.
pub fn LexicalGrammar::variable_index_for_nfa_state(
  self : LexicalGrammar,
  state_id : Int32,
) -> Int32 {
  let mut lo = 0
  let mut hi = self.variables.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if self.variables[mid].start_state < state_id {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// Sentinel meaning no reserved word set at all. Only the augmented start
/// production carries it, and it must never index the reserved-sets table.
pub let no_reserved_words : Int32 = 65535

///|
/// A production step. Upstream packs this into 20 bytes; the fields here hold
/// the same information and compare/hash the same way.
#derive(Eq, Hash, Debug)
pub(all) struct ProductionStep {
  symbol : Symbol
  precedence : Precedence
  associativity : Associativity?
  alias : Alias?
  field : StrId?
  reserved : Int32
}

///|
pub fn ProductionStep::pack(
  symbol : Symbol,
  prec : Precedence,
  assoc : Associativity?,
  alias : Alias?,
  field : StrId?,
  reserved : Int32,
) -> ProductionStep {
  { symbol, precedence: prec, associativity: assoc, alias, field, reserved, }
}

///|
pub fn ProductionStep::non_terminal_index(self : ProductionStep) -> Int32? {
  self.symbol.non_terminal_index()
}

///|
pub fn ProductionStep::with_precedence(
  self : ProductionStep,
  prec : Precedence,
) -> ProductionStep {
  { ..self, precedence: prec, }
}

///|
pub fn ProductionStep::with_associativity(
  self : ProductionStep,
  assoc : Associativity?,
) -> ProductionStep {
  { ..self, associativity: assoc, }
}

///|
pub fn ProductionStep::with_alias(
  self : ProductionStep,
  alias : Alias?,
) -> ProductionStep {
  { ..self, alias, }
}

///|
pub fn ProductionStep::with_field(
  self : ProductionStep,
  field : StrId?,
) -> ProductionStep {
  { ..self, field, }
}

///|
pub fn ProductionStep::with_reserved(
  self : ProductionStep,
  reserved : Int32,
) -> ProductionStep {
  { ..self, reserved, }
}

///|
pub fn ProductionStep::with_symbol(
  self : ProductionStep,
  symbol : Symbol,
) -> ProductionStep {
  { ..self, symbol, }
}

///|
pub fn ProductionStep::child_type(
  self : ProductionStep,
  default_aliases : AliasMap,
) -> ChildType {
  match self.alias {
    Some(alias) => Aliased(alias)
    None =>
      match default_aliases.get(self.symbol) {
        Some(alias) => Aliased(alias)
        None => Normal(self.symbol)
      }
  }
}

///|
#derive(Eq, Hash, Compare, Debug)
pub(all) enum ChildType {
  Normal(Symbol)
  Aliased(Alias)
}

///|
#derive(Eq, Hash, Compare, Debug)
pub(all) struct ReservedWordSetId(Int32)

///|
/// A flattened production: a step range, its dynamic precedence, and whether
/// its reduce action is gated on end-of-input lookahead.
#derive(Eq, Hash, Debug)
pub(all) struct Production {
  steps_start : Int32
  steps_len : Int32
  dynamic_precedence : Int32
  requires_eof_lookahead : Bool
}

///|
pub fn Production::contents(
  self : Production,
  steps : Array[ProductionStep],
) -> ProdRef {
  {
    steps: steps[self.steps_start:self.steps_start + self.steps_len],
    dynamic_precedence: self.dynamic_precedence,
    requires_eof_lookahead: self.requires_eof_lookahead,
  }
}

///|
/// Flattened output: one backing store of steps, productions as ranges into it,
/// and per-variable production ranges `[start, end)`.
pub(all) struct ProductionStore {
  steps : Array[ProductionStep]
  productions : Array[Production]
  var_prods : Array[(Int32, Int32)]
}

///|
pub fn ProductionStore::new() -> ProductionStore {
  { steps: [], productions: [], var_prods: [], }
}

///|
pub fn ProductionStore::production(
  self : ProductionStore,
  id : Int32,
) -> ProdRef {
  self.productions[id].contents(self.steps)
}

///|
#derive(Eq, Debug)
pub(all) struct InlinedProductionRange {
  start : Int32
  end : Int32
}

///|
/// Records replacement production ids when inline rule references are expanded.
pub(all) struct InlinedProductionMap {
  map : Map[(Int32, Int32), Array[Int32]]
  mut fully_inlined : Map[Int32, InlinedProductionRange]
  mut fully_inlined_ids : Array[Int32]
}

///|
pub fn InlinedProductionMap::new() -> InlinedProductionMap {
  { map: Map([]), fully_inlined: Map([]), fully_inlined_ids: [], }
}

///|
pub fn InlinedProductionMap::discard_fully_inlined(
  self : InlinedProductionMap,
) -> Unit {
  self.fully_inlined = Map([])
  self.fully_inlined_ids = []
}

///|
pub fn InlinedProductionMap::fully_inlined_prod_ids(
  self : InlinedProductionMap,
  prod_id : Int32,
) -> ArrayView[Int32]? {
  match self.fully_inlined.get(prod_id) {
    Some(range) => Some(self.fully_inlined_ids[range.start:range.end])
    None => None
  }
}

///|
pub fn InlinedProductionMap::inlined_prod_ids(
  self : InlinedProductionMap,
  prod_id : Int32,
  step_index : Int32,
) -> Array[Int32]? {
  self.map.get((prod_id, step_index))
}

///|
#derive(Eq, Debug)
pub(all) struct SyntaxVariable {
  name : StrId
  kind : VariableType
}

///|
pub fn SyntaxVariable::is_auxiliary(self : SyntaxVariable) -> Bool {
  self.kind is Auxiliary
}

///|
pub fn SyntaxVariable::is_hidden(self : SyntaxVariable) -> Bool {
  self.kind is (Hidden | Auxiliary)
}

///|
#derive(Eq, Debug)
pub(all) struct ExternalToken {
  name : StrId
  kind : VariableType
  corresponding_internal_token : Symbol?
}

///|
pub(all) struct SyntaxGrammar {
  variables : Array[SyntaxVariable]
  extra_symbols : Array[Symbol]
  expected_conflicts : Array[Array[Symbol]]
  external_tokens : Array[ExternalToken]
  supertype_symbols : Array[Symbol]
  variables_to_inline : Array[Symbol]
  word_token : Symbol?
  precedence_orderings : Array[Array[PrecedenceEntry]]
  reserved_word_sets : Array[TokenSet]
  steps : Array[ProductionStep]
  productions : Array[Production]
  var_prods : Array[(Int32, Int32)]
}

///|
pub fn SyntaxGrammar::production(self : SyntaxGrammar, id : Int32) -> ProdRef {
  self.productions[id].contents(self.steps)
}

///|
/// The pooled production ids belonging to a variable, as `[start, end)`.
pub fn SyntaxGrammar::variable_prod_ids(
  self : SyntaxGrammar,
  variable_index : Int32,
) -> (Int32, Int32) {
  self.var_prods[variable_index]
}

///|
/// A production's contents, with its steps borrowed from wherever they're stored.
pub(all) struct ProdRef {
  steps : ArrayView[ProductionStep]
  dynamic_precedence : Int32
  requires_eof_lookahead : Bool
}

///|
pub fn ProdRef::first_symbol(self : ProdRef) -> Symbol? {
  match self.steps.get(0) {
    Some(step) => Some(step.symbol)
    None => None
  }
}

///|
pub impl Eq for ProdRef with fn equal(self, other) {
  if self.dynamic_precedence != other.dynamic_precedence ||
    self.requires_eof_lookahead != other.requires_eof_lookahead ||
    self.steps.length() != other.steps.length() {
    return false
  }
  for i in 0..<self.steps.length() {
    if self.steps[i] != other.steps[i] {
      return false
    }
  }
  true
}

///|
pub impl Hash for ProdRef with fn hash_combine(self, hasher) {
  hasher.combine_int(self.steps.length())
  for step in self.steps {
    hasher.combine(step)
  }
  hasher.combine_int(self.dynamic_precedence)
  hasher.combine_bool(self.requires_eof_lookahead)
}
