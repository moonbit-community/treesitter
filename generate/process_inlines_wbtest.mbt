// Tests ported from tree-sitter crates/generate/src/prepare_grammar/process_inlines.rs.

///|
fn make_lexical_variables_through(
  pool : RulePool,
  last_index : Int32,
) -> Array[LexicalVariable] {
  Array::makei(last_index + 1, i => {
    name: pool.intern("t\{i}"),
    kind: Anonymous,
    implicit_precedence: 0,
    start_state: 0,
  })
}

///|
/// Append one variable's productions to `out` and record its production id range.
fn add_variable(
  out : ProductionStore,
  prods : Array[(Array[ProductionStep], Int32)],
) -> Unit {
  let start = out.productions.length()
  for prod in prods {
    let (steps, dynamic_prec) = prod
    let steps_start = out.steps.length()
    for step in steps {
      out.steps.push(step)
    }
    out.productions.push({
      steps_start,
      steps_len: steps.length(),
      dynamic_precedence: dynamic_prec,
      requires_eof_lookahead: false,
    })
  }
  out.var_prods.push((start, out.productions.length()))
}

///|
/// Inlining results recorded at `(prod_id, step)`: the replacement ids and each
/// one's steps and dynamic precedence.
fn inlined(
  out : ProductionStore,
  map : InlinedProductionMap,
  prod_id : Int32,
  step : Int32,
) -> (Array[Int32], Array[(Array[ProductionStep], Int32)])? {
  match map.map.get((prod_id, step)) {
    None => None
    Some(ids) => {
      let prods = ids.map(id => {
        let p = out.productions[id]
        (
          out.steps[p.steps_start:p.steps_start + p.steps_len].to_owned(),
          p.dynamic_precedence,
        )
      })
      Some((ids.copy(), prods))
    }
  }
}

///|
fn decorated(
  pool : RulePool,
  symbol : Symbol,
  prec : Precedence,
  assoc : Associativity?,
  alias : String?,
) -> ProductionStep {
  let alias = alias.map(name => { value: pool.intern(name), is_named: true, })
  ProductionStep::pack(symbol, prec, assoc, alias, None, 0)
}

///|
test "basic_inlining" {
  // var0: [t10, nt1, t11] (nt1 is inlined)
  // var1: [t12, t13] | [t14]
  let out = ProductionStore::new()
  add_variable(out, [
    (
      [
        plain(Symbol::terminal(10)),
        plain(Symbol::non_terminal(1)),
        plain(Symbol::terminal(11)),
      ],
      0,
    ),
  ])
  add_variable(out, [
    ([plain(Symbol::terminal(12)), plain(Symbol::terminal(13))], 0),
    ([plain(Symbol::terminal(14))], -2),
  ])
  let g = InputGrammar::new()
  let meta = {
    ..ExtractedGrammarMeta::default(),
    inline: [Symbol::non_terminal(1)],
  }
  let lexical_variables = make_lexical_variables_through(g.pool, 14)
  let map = process_inlines(g, meta, lexical_variables, out)
  let prod0 = out.var_prods[0].0

  // Nothing to inline at step 0.
  assert_true(inlined(out, map, prod0, 0) is None)

  // Inlining variable 1 yields two productions.
  guard inlined(out, map, prod0, 1) is Some((_, prods)) else { fail("") }
  assert_eq(prods, [
    (
      [
        plain(Symbol::terminal(10)),
        plain(Symbol::terminal(12)),
        plain(Symbol::terminal(13)),
        plain(Symbol::terminal(11)),
      ],
      0,
    ),
    (
      [
        plain(Symbol::terminal(10)),
        plain(Symbol::terminal(14)),
        plain(Symbol::terminal(11)),
      ],
      -2,
    ),
  ])
}

///|
test "nested_inlining" {
  // var0: [t10, nt1, t11, nt2, t12]    (nt1, nt2 inlined)
  // var1: [t13] | [nt3, t14]           (nt3 inlined)
  // var2: [t15]
  // var3: [t16]
  let out = ProductionStore::new()
  add_variable(out, [
    (
      [
        plain(Symbol::terminal(10)),
        plain(Symbol::non_terminal(1)),
        plain(Symbol::terminal(11)),
        plain(Symbol::non_terminal(2)),
        plain(Symbol::terminal(12)),
      ],
      0,
    ),
  ])
  add_variable(out, [
    ([plain(Symbol::terminal(13))], 0),
    ([plain(Symbol::non_terminal(3)), plain(Symbol::terminal(14))], 0),
  ])
  add_variable(out, [([plain(Symbol::terminal(15))], 0)])
  add_variable(out, [([plain(Symbol::terminal(16))], 0)])
  let g = InputGrammar::new()
  let meta = {
    ..ExtractedGrammarMeta::default(),
    inline: [
      Symbol::non_terminal(1),
      Symbol::non_terminal(2),
      Symbol::non_terminal(3),
    ],
  }
  let lexical_variables = make_lexical_variables_through(g.pool, 16)
  let map = process_inlines(g, meta, lexical_variables, out)
  let prod0 = out.var_prods[0].0
  guard inlined(out, map, prod0, 1) is Some((ids, prods)) else { fail("") }
  assert_eq(prods, [
    (
      [
        plain(Symbol::terminal(10)),
        plain(Symbol::terminal(13)),
        plain(Symbol::terminal(11)),
        plain(Symbol::non_terminal(2)),
        plain(Symbol::terminal(12)),
      ],
      0,
    ),
    (
      [
        plain(Symbol::terminal(10)),
        plain(Symbol::terminal(16)),
        plain(Symbol::terminal(14)),
        plain(Symbol::terminal(11)),
        plain(Symbol::non_terminal(2)),
        plain(Symbol::terminal(12)),
      ],
      0,
    ),
  ])

  // nt2, now at step 3
  guard inlined(out, map, ids[0], 3) is Some((_, prods)) else { fail("") }
  assert_eq(prods, [
    (
      [
        plain(Symbol::terminal(10)),
        plain(Symbol::terminal(13)),
        plain(Symbol::terminal(11)),
        plain(Symbol::terminal(15)),
        plain(Symbol::terminal(12)),
      ],
      0,
    ),
  ])
}

///|
test "inlining_with_precedence_and_alias" {
  // var0: [ nt1{prec 1, left}, t10, nt2{alias outer} ]     (nt1, nt2 inlined)
  // var1: [ r11{prec 2, alias inner}, t12 ]
  // var2: [ t13 ]
  let pool = RulePool::new()
  let out = ProductionStore::new()
  add_variable(out, [
    (
      [
        decorated(pool, Symbol::non_terminal(1), Integer(1), Some(Left), None),
        plain(Symbol::terminal(10)),
        decorated(
          pool,
          Symbol::non_terminal(2),
          NoPrecedence,
          None,
          Some("outer_alias"),
        ),
      ],
      0,
    ),
  ])
  add_variable(out, [
    (
      [
        decorated(
          pool,
          Symbol::terminal(11),
          Integer(2),
          None,
          Some("inner_alias"),
        ),
        plain(Symbol::terminal(12)),
      ],
      0,
    ),
  ])
  add_variable(out, [([plain(Symbol::terminal(13))], 0)])
  let g = InputGrammar::new()
  let meta = {
    ..ExtractedGrammarMeta::default(),
    inline: [Symbol::non_terminal(1), Symbol::non_terminal(2)],
  }
  let lexical_variables = make_lexical_variables_through(g.pool, 13)
  let map = process_inlines(g, meta, lexical_variables, out)
  let prod0 = out.var_prods[0].0
  guard inlined(out, map, prod0, 0) is Some((ids, prods)) else { fail("") }
  assert_eq(prods, [
    (
      [
        // The first inlined step keeps its own precedence and alias.
        decorated(
          pool,
          Symbol::terminal(11),
          Integer(2),
          None,
          Some("inner_alias"),
        ),
        // The last inlined step inherits the inlined step's precedence.
        decorated(pool, Symbol::terminal(12), Integer(1), Some(Left), None),
        plain(Symbol::terminal(10)),
        decorated(
          pool,
          Symbol::non_terminal(2),
          NoPrecedence,
          None,
          Some("outer_alias"),
        ),
      ],
      0,
    ),
  ])
  guard inlined(out, map, ids[0], 3) is Some((_, prods)) else { fail("") }
  assert_eq(prods, [
    (
      [
        decorated(
          pool,
          Symbol::terminal(11),
          Integer(2),
          None,
          Some("inner_alias"),
        ),
        decorated(pool, Symbol::terminal(12), Integer(1), Some(Left), None),
        plain(Symbol::terminal(10)),
        // Every inlined step inherits the inlined step's alias
        decorated(
          pool,
          Symbol::terminal(13),
          NoPrecedence,
          None,
          Some("outer_alias"),
        ),
      ],
      0,
    ),
  ])
}

///|
test "error_when_inlining_tokens" {
  let pool = RulePool::new()
  let name = pool.intern("something")
  let g = { ..InputGrammar::new(), pool, }
  let meta = {
    ..ExtractedGrammarMeta::default(),
    inline: [Symbol::terminal(0)],
  }
  let lexical_variables : Array[LexicalVariable] = [
    { name, kind: Named, implicit_precedence: 0, start_state: 0, },
  ]
  let out = ProductionStore::new()
  try process_inlines(g, meta, lexical_variables, out) catch {
    err => assert_eq(err, Token("something"))
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "error_when_inlining_removes_all_productions" {
  // var0: [nt1]
  // var1: [nt2, t10] (nt2 is inlined)
  // var2: one empty eof-gated production, like a flattened `_eof: _ => eof()`
  // Inlining var2 into var1 drops var1's only production.
  let out = ProductionStore::new()
  add_variable(out, [([plain(Symbol::non_terminal(1))], 0)])
  add_variable(out, [
    ([plain(Symbol::non_terminal(2)), plain(Symbol::terminal(10))], 0),
  ])
  let start = out.productions.length()
  out.productions.push({
    steps_start: out.steps.length(),
    steps_len: 0,
    dynamic_precedence: 0,
    requires_eof_lookahead: true,
  })
  out.var_prods.push((start, start + 1))
  let pool = RulePool::new()
  let variables = ["rule0", "rule1", "rule2"].map(name => {
    let name = pool.intern(name)
    let root = pool.push_node(Blank)
    { name, root, }
  })
  let lexical_variables = make_lexical_variables_through(pool, 10)
  let g = pool_grammar(pool, variables)
  let meta = {
    ..ExtractedGrammarMeta::default(),
    inline: [Symbol::non_terminal(2)],
  }
  try process_inlines(g, meta, lexical_variables, out) catch {
    err => assert_eq(err, NoReachableProductions("rule1"))
  } noraise {
    _ => fail("expected an error")
  }
}
