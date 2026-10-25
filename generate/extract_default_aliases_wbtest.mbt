// Tests ported from tree-sitter crates/generate/src/prepare_grammar/extract_default_aliases.rs.

///|
fn add_lexical_variable(
  pool : RulePool,
  variables : Array[LexicalVariable],
  name : String,
) -> Symbol {
  let symbol = Symbol::terminal(variables.length())
  variables.push({
    name: pool.intern(name),
    kind: Anonymous,
    implicit_precedence: 0,
    start_state: 0,
  })
  symbol
}

///|
fn aliased(pool : RulePool, symbol : Symbol, name : String) -> ProductionStep {
  let value = pool.intern(name)
  ProductionStep::pack(
    symbol,
    NoPrecedence,
    None,
    Some({ value, is_named: true, }),
    None,
    0,
  )
}

///|
test "extract_simple_aliases" {
  let pool = RulePool::new()
  let dummy = pool.intern("_")
  let root = pool.blank()
  let lexical_variables = []
  let t0 = add_lexical_variable(pool, lexical_variables, "t0")
  let t1 = add_lexical_variable(pool, lexical_variables, "t1")
  let t2 = add_lexical_variable(pool, lexical_variables, "t2")
  let t3 = add_lexical_variable(pool, lexical_variables, "t3")

  // v1: every token aliased.
  let v1 = [
    aliased(pool, t0, "a1"),
    aliased(pool, t1, "a2"),
    aliased(pool, t2, "a3"),
    aliased(pool, t3, "a4"),
  ]
  // v2: t0 same alias, t1 unaliased, t2 aliased differently, t3 aliased twice as a6
  let v2 = [
    aliased(pool, t0, "a1"),
    plain(t1),
    aliased(pool, t2, "a5"),
    aliased(pool, t3, "a6"),
    aliased(pool, t3, "a6"),
  ]
  let out = ProductionStore::new()
  for steps in [v1, v2] {
    let ps = out.productions.length()
    let steps_start = out.steps.length()
    for step in steps {
      out.steps.push(step)
    }
    out.productions.push({
      steps_start,
      steps_len: steps.length(),
      dynamic_precedence: 0,
      requires_eof_lookahead: false,
    })
    out.var_prods.push((ps, out.productions.length()))
  }
  let g = pool_grammar(pool, Array::makei(2, _ => { name: dummy, root, }))
  let meta = ExtractedGrammarMeta::default()
  let pool_map = extract_default_aliases(g, meta, lexical_variables, out)

  // t0 -> a1, t2 -> a3 (v1 wins the tie from appearing first), t3 -> a6 (used twice)
  // t1 -> none (appears unaliased in v2).
  let default = (s : Symbol) => {
    pool_map.get(s).map(a => (g.pool.resolve(a.value), a.is_named))
  }
  assert_eq(pool_map.length(), 3)
  assert_eq(default(Symbol::terminal(0)), Some(("a1", true)))
  assert_eq(default(Symbol::terminal(2)), Some(("a3", true)))
  assert_eq(default(Symbol::terminal(3)), Some(("a6", true)))
  assert_eq(default(Symbol::terminal(1)), None)

  // Steps carrying their symbol's default are cleared. The rest keep their alias.
  let step_alias = (i : Int32) => {
    out.steps[i].alias.map(a => (g.pool.resolve(a.value), a.is_named))
  }
  assert_eq(step_alias(0), None) //               v1 t0(a1) = default
  assert_eq(step_alias(1), Some(("a2", true))) // v1 t1(a2), no default
  assert_eq(step_alias(2), None) //               v1 t2(a3) = default
  assert_eq(step_alias(3), Some(("a4", true))) // v1 t3(a4) != a6
  assert_eq(step_alias(4), None) //               v2 t0(a1) = default
  assert_eq(step_alias(5), None) //               v2 t1 unaliased
  assert_eq(step_alias(6), Some(("a5", true))) // v2 t2(a5) != a3
  assert_eq(step_alias(7), None) //               v2 t3(a6) = default
  assert_eq(step_alias(8), None) //               v2 t3(a6) = default
}
