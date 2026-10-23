// Helpers shared by the tests ported from the upstream `prepare_grammar`
// modules (each upstream test module defines its own copies).

///|
/// Upstream's `#[derive(Default)]` on `ExtractedGrammarMeta`, used by tests.
fn ExtractedGrammarMeta::default() -> ExtractedGrammarMeta {
  {
    kinds: [],
    extra_symbols: [],
    external_tokens: [],
    reserved_sets: [],
    supertypes: [],
    conflicts: [],
    inline: [],
    word: None,
  }
}

///|
fn named(pool : RulePool, name : String) -> RuleId {
  let id = pool.intern(name)
  pool.named_symbol(id)
}

///|
fn leaf(pool : RulePool, s : String) -> RuleId {
  let id = pool.intern(s)
  pool.string(id)
}

///|
fn pattern(pool : RulePool, value : String) -> RuleId {
  let value = pool.intern(value)
  let flags = pool.intern("")
  pool.pattern(value, flags)
}

///|
fn term(pool : RulePool, i : Int32) -> RuleId {
  pool.push_node(Sym(Symbol::terminal(i)))
}

///|
fn non_term(pool : RulePool, i : Int32) -> RuleId {
  pool.push_node(Sym(Symbol::non_terminal(i)))
}

///|
fn nt(index : Int32) -> Rule {
  Sym(Symbol::non_terminal(index))
}

///|
fn ext(index : Int32) -> Rule {
  Sym(Symbol::external(index))
}

///|
fn pool_grammar(pool : RulePool, variables : Array[Variable]) -> InputGrammar {
  { ..InputGrammar::new(), pool, variables, }
}

///|
fn build_grammar(build : (RulePool) -> Array[Variable]) -> InputGrammar {
  let pool = RulePool::new()
  let variables = build(pool)
  pool_grammar(pool, variables)
}

///|
fn variable_names(g : InputGrammar) -> Array[String] {
  g.variables.map(v => g.pool.resolve(v.name))
}

///|
fn plain(symbol : Symbol) -> ProductionStep {
  ProductionStep::pack(symbol, NoPrecedence, None, None, None, 0)
}
