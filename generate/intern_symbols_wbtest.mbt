// Tests ported from tree-sitter crates/generate/src/prepare_grammar/intern_symbols.rs.

///|
test "basic_interning" {
  let grammar = {
    // x: choice(y, _z)
    // y: _z
    // _z: "a"
    let pool = RulePool::new()
    let (y_str, z_str) = (pool.intern("y"), pool.intern("_z"))
    let y = pool.named_symbol(y_str)
    let z = pool.named_symbol(z_str)
    let a = pool.intern("a")
    let x_root = pool.choice([y, z])
    let y_root = pool.named_symbol(z_str)
    let z_root = pool.string(a)
    let variables : Array[Variable] = [
      { name: pool.intern("x"), root: x_root, },
      { name: pool.intern("y"), root: y_root, },
      { name: pool.intern("_z"), root: z_root, },
    ]
    pool_grammar(pool, variables)
  }
  let meta = intern_symbols(grammar, [])

  // x's body was `choice(y, _z)` -> `choice(nt1, nt2)`
  guard grammar.pool.node(grammar.variables[0].root) is Choice(range) else {
    fail("Expected choice")
  }
  let x_children = grammar.pool
    .child_slice(range)
    .iter()
    .map(c => grammar.pool.node(c))
    .to_array()
  assert_eq(x_children, [nt(1), nt(2)])

  // y's body was _z -> nt2
  assert_eq(grammar.pool.node(grammar.variables[1].root), nt(2))

  // z's body (a string) is untouched, it remains hidden
  assert_true(grammar.pool.node(grammar.variables[2].root) is String(_))
  assert_eq(meta.kinds, [Named, Named, Hidden])
}

///|
test "interning_external_token_names" {
  // w: choice(x, y, z)
  // x: "a"
  // y: "b"
  // externals: [y, z]
  let pool = RulePool::new()
  let (x_str, y_str, z_str) = (
    pool.intern("x"),
    pool.intern("y"),
    pool.intern("z"),
  )
  let x_ns = pool.named_symbol(x_str)
  let y_ns = pool.named_symbol(y_str)
  let z_ns = pool.named_symbol(z_str)
  let w_root = pool.choice([x_ns, y_ns, z_ns])
  let (a, b) = (pool.intern("a"), pool.intern("b"))
  let x_root = pool.string(a)
  let y_root = pool.string(b)
  let variables : Array[Variable] = [
    { name: pool.intern("w"), root: w_root, },
    { name: pool.intern("x"), root: x_root, },
    { name: pool.intern("y"), root: y_root, },
  ]
  let grammar = pool_grammar(pool, variables)
  let ext_y = grammar.pool.named_symbol(y_str)
  let ext_z = grammar.pool.named_symbol(z_str)
  grammar.external_roots = [ext_y, ext_z]
  let meta = intern_symbols(grammar, [])

  // w: x -> nt1, y -> nt2 (var shadows the external), z -> ext1
  guard grammar.pool.node(grammar.variables[0].root) is Choice(range) else {
    fail("Expected choice")
  }
  let w_children = grammar.pool
    .child_slice(range)
    .iter()
    .map(c => grammar.pool.node(c))
    .to_array()
  assert_eq(w_children, [nt(1), nt(2), ext(1)])

  // x and y bodies (bare strings) are left alone
  assert_true(grammar.pool.node(grammar.variables[1].root) is String(_))
  assert_true(grammar.pool.node(grammar.variables[2].root) is String(_))

  // The external roots resolve the same way: y -> nt2 (shadow), z -> ext1
  assert_eq(grammar.pool.node(grammar.external_roots[0]), nt(2))
  assert_eq(grammar.pool.node(grammar.external_roots[1]), ext(1))

  // external token metadata carries the correct names and kinds
  let externals = meta.external_tokens.map(e => {
    let (sid, kind) = e
    (sid.map(s => grammar.pool.resolve(s)), kind)
  })
  assert_eq(externals, [(Some("y"), Named), (Some("z"), Named)])
}

///|
test "grammar_with_undefined_symbols" {
  // x references y, which is undefined
  let pool = RulePool::new()
  let y_str = pool.intern("y")
  let x_root = pool.named_symbol(y_str)
  let variables : Array[Variable] = [{ name: pool.intern("x"), root: x_root, }]
  let grammar = pool_grammar(pool, variables)
  try intern_symbols(grammar, []) catch {
    e => assert_eq(e, Undefined("y"))
  } noraise {
    _ => fail("Expected an error but got none")
  }
}

///|
test "supertype_and_inline_conflict" {
  // v1: _v2
  // _v2: choice("a", "b")
  // supertypes: [_v2]
  // inline: [_v2]
  let pool = RulePool::new()
  let v2 = pool.intern("_v2")
  let v1_root = pool.named_symbol(v2)
  let v2_root = {
    let (a, b) = (pool.intern("a"), pool.intern("b"))
    let (sa, sb) = (pool.string(a), pool.string(b))
    pool.choice([sa, sb])
  }
  let variables : Array[Variable] = [
    { name: pool.intern("v1"), root: v1_root, },
    { name: v2, root: v2_root, },
  ]
  let grammar = pool_grammar(pool, variables)
  grammar.supertype_names = [v2]
  grammar.inline_names = [v2]
  let diagnostics = []
  let meta = intern_symbols(grammar, diagnostics)

  // The supertype entry is dropped with a warning, and the rule stays inlined.
  assert_eq(meta.supertypes, [])
  assert_eq(meta.inline, [Symbol::non_terminal(1)])
  assert_eq(diagnostics, [SupertypeInlined(name="_v2")])
}

///|
test "meta_paths" {
  // x: "a"
  // y: "b"
  // supertypes: [y]
  // word: y
  // conflicts: [x, y]
  // inline: [x, nonexistent]
  let pool = RulePool::new()
  let (a, b) = (pool.intern("a"), pool.intern("b"))
  let (x, y) = (pool.intern("x"), pool.intern("y"))
  let x_root = pool.string(a)
  let y_root = pool.string(b)
  let variables : Array[Variable] = [
    { name: x, root: x_root, },
    { name: y, root: y_root, },
  ]
  let grammar = pool_grammar(pool, variables)
  let nonexistent = grammar.pool.intern("nonexistent")
  grammar.supertype_names = [y]
  grammar.word_name = Some(y)
  grammar.conflict_names = [[x, y]]
  grammar.inline_names = [x, nonexistent]
  let meta = intern_symbols(grammar, [])

  // y is a supertype, so it's reclassified as hidden
  assert_eq(meta.kinds, [Named, Hidden])
  assert_eq(meta.supertypes, [Symbol::non_terminal(1)])
  assert_eq(meta.word, Some(Symbol::non_terminal(1)))
  assert_eq(meta.conflicts, [[Symbol::non_terminal(0), Symbol::non_terminal(1)]])
  // unknown inline names are silently skipped
  assert_eq(meta.inline, [Symbol::non_terminal(0)])
}
