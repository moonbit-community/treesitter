// Tests ported from tree-sitter crates/generate/src/prepare_grammar/extract_tokens.rs.
//
// Everything checked here is decided by `extract_tokens` itself, before
// `PendingTokenExtraction::expand_and_commit` runs `expand_tokens`. The
// upstream tests' post-commit assertions are in
// `prepare_grammar_e2e_wbtest.mbt`.

///|
fn str(p : RulePool, t : String) -> RuleId {
  leaf(p, t)
}

///|
fn pat(p : RulePool, t : String) -> RuleId {
  pattern(p, t)
}

///|
fn n_sym(p : RulePool, n : String) -> RuleId {
  named(p, n)
}

///|
fn extract_pending(g : InputGrammar) -> PendingTokenExtraction raise {
  let meta = intern_symbols(g, [])
  extract_tokens(g, meta)
}

///|
fn lexical_names(
  pending : PendingTokenExtraction,
) -> Array[(String, VariableType)] {
  pending.lexical_variables.map(v => {
    (pending.grammar.pool.resolve(v.name), v.kind)
  })
}

///|
/// rule_0: repeat(seq("a", /b/, choice(rule_1, rule_2, token(repeat(choice("c", "d"))))))
/// rule_1: /e/
/// rule_2: /b/
/// rule_3: seq(rule_2, blank)
fn extraction_grammar() -> InputGrammar {
  let pool = RulePool::new()
  let r0 = {
    let a = str(pool, "a")
    let b = pat(pool, "b")
    let (r1, r2) = (n_sym(pool, "rule_1"), n_sym(pool, "rule_2"))
    let tok = {
      let (c, d) = (str(pool, "c"), str(pool, "d"))
      let cd = pool.choice([c, d])
      let rep = pool.repeat(cd)
      pool.token(rep)
    }
    let ch = pool.choice([r1, r2, tok])
    let sq = pool.seq([a, b, ch])
    pool.repeat(sq)
  }
  let r1 = pat(pool, "e")
  let r2 = pat(pool, "b")
  let r3 = {
    let (r, bl) = (n_sym(pool, "rule_2"), pool.blank())
    pool.seq([r, bl])
  }
  let variables : Array[Variable] = [
    { name: pool.intern("rule_0"), root: r0, },
    { name: pool.intern("rule_1"), root: r1, },
    { name: pool.intern("rule_2"), root: r2, },
    { name: pool.intern("rule_3"), root: r3, },
  ]
  pool_grammar(pool, variables)
}

///|
test "extraction (pending)" {
  let grammar = extraction_grammar()
  let pending = extract_pending(grammar)

  // Token extraction must preserve each original token body until lexical
  // expansion runs.
  let roots = pending.lexical_variables.map(v => v.root)
  let pool = pending.grammar.pool
  let e0 = str(pool, "a")
  assert_true(pool.subtree_eq(roots[0], e0))
  let e1 = pat(pool, "b")
  assert_true(pool.subtree_eq(roots[1], e1))
  let e2 = {
    let (c, d) = (str(pool, "c"), str(pool, "d"))
    let cd = pool.choice([c, d])
    pool.repeat(cd)
  }
  assert_true(pool.subtree_eq(roots[2], e2))
  let e3 = pat(pool, "e")
  assert_true(pool.subtree_eq(roots[3], e3))

  // rule_1 was absorbed into the lexical grammar, rule_0, rule_2, and rule_3 remain
  assert_eq(variable_names(grammar), ["rule_0", "rule_2", "rule_3"])
  assert_eq(pending.meta.kinds, [Named, Named, Named])
  // `/e/` is used in exactly one place (as rule_1's whole body), so rule_1
  // was absorbed into the lexical grammar (and donated its name to the token).
  assert_eq(lexical_names(pending), [
    ("a", Anonymous),
    ("rule_0_token1", Auxiliary),
    ("rule_0_token2", Auxiliary),
    ("rule_1", Named),
  ])
  // rule_1 (index 1) became terminal 3; rule_2 and rule_3 shift down by one.
  assert_eq(pending.syntax_variable_replacements.get(1), Some(3))
  assert_eq(pending.syntax_variable_shift, [0, 0, 1, 1])
}

///|
test "start_rule_is_token (pending)" {
  // The start rule is a bare token. The token is extracted, but the start
  // rule is never absorbed. It stays as a reference to terminal 0.
  let pool = RulePool::new()
  let r0 = str(pool, "hello")
  let variables : Array[Variable] = [{ name: pool.intern("rule_0"), root: r0, }]
  let grammar = pool_grammar(pool, variables)
  let pending = extract_pending(grammar)
  let root = pending.lexical_variables[0].root
  let expected = str(pending.grammar.pool, "hello")
  assert_true(pending.grammar.pool.subtree_eq(root, expected))
  assert_eq(variable_names(grammar), ["rule_0"])
  assert_eq(lexical_names(pending), [("hello", Anonymous)])
  assert_eq(pending.rewrites, [(r0, 0)])
}

///|
test "extracting_extra_symbols (pending)" {
  // extras split two ways:
  //  - the `comment` ref (absorbed into a token) becomes an extra terminal
  //  - the bare " " string becomes a separator
  let pool = RulePool::new()
  let r0 = str(pool, "x")
  let comment = pat(pool, "//.*")
  let sep = str(pool, " ")
  let extra_ref = n_sym(pool, "comment")
  let variables : Array[Variable] = [
    { name: pool.intern("rule_0"), root: r0, },
    { name: pool.intern("comment"), root: comment, },
  ]
  let grammar = pool_grammar(pool, variables)
  grammar.extra_roots = [sep, extra_ref]
  let pending = extract_pending(grammar)

  // The single use `comment` rule `//.*` is absorbed as `terminal(1)`, so
  // its extra reference becomes `extra_symbols[0]`.
  assert_eq(pending.separator_roots.length(), 1)
  let separator_root = pending.separator_roots[0]
  // the " " string routes to separators, not a token symbol
  let expected = str(pending.grammar.pool, " ")
  assert_true(pending.grammar.pool.subtree_eq(separator_root, expected))
  assert_eq(pending.meta.extra_symbols, [Symbol::terminal(1)])
}

///|
test "extract_externals (pending)" {
  let pool = RulePool::new()
  // rule_0: seq(external_0, "a", rule_1, rule_2)
  let r0 = {
    let e = n_sym(pool, "external_0")
    let a = str(pool, "a")
    let (r1, r2) = (n_sym(pool, "rule_1"), n_sym(pool, "rule_2"))
    pool.seq([e, a, r1, r2])
  }
  let r1 = str(pool, "b")
  let r2 = str(pool, "c")
  // externals: [external_0, "a", rule_2]
  let e0 = n_sym(pool, "external_0")
  let ea = str(pool, "a")
  let er2 = n_sym(pool, "rule_2")
  let variables : Array[Variable] = [
    { name: pool.intern("rule_0"), root: r0, },
    { name: pool.intern("rule_1"), root: r1, },
    { name: pool.intern("rule_2"), root: r2, },
  ]
  let external_0 = pool.intern("external_0")
  let a = pool.intern("a")
  let rule_2 = pool.intern("rule_2")
  let grammar = pool_grammar(pool, variables)
  grammar.external_roots = [e0, ea, er2]
  let pending = extract_pending(grammar)
  assert_eq(pending.meta.external_tokens, [
    // a genuine external, no internal counterpart
    { name: external_0, kind: Named, corresponding_internal_token: None, },
    // "a" is also extracted internally (terminal 0), so it links to it
    {
      name: a,
      kind: Anonymous,
      corresponding_internal_token: Some(Symbol::terminal(0)),
    },
    // rule_2 shadowed a variable that got absorbed to terminal 2
    {
      name: rule_2,
      kind: Named,
      corresponding_internal_token: Some(Symbol::terminal(2)),
    },
  ])
}

///|
test "error_on_external_with_same_name_as_non_terminal" {
  let pool = RulePool::new()
  let r0 = {
    let (a, b) = (n_sym(pool, "rule_1"), n_sym(pool, "rule_2"))
    pool.seq([a, b])
  }
  let r1 = {
    let (a, b) = (n_sym(pool, "rule_2"), n_sym(pool, "rule_2"))
    pool.seq([a, b])
  }
  let r2 = str(pool, "a")
  let ext_ref = n_sym(pool, "rule_1")
  let variables : Array[Variable] = [
    { name: pool.intern("rule_0"), root: r0, },
    { name: pool.intern("rule_1"), root: r1, },
    { name: pool.intern("rule_2"), root: r2, },
  ]
  let grammar = pool_grammar(pool, variables)
  grammar.external_roots = [ext_ref]

  // rule_1 is a seq (not absorbable), so it stays a non-terminal. A non-terminal
  // non-terminal can't also be an external token.
  let meta = intern_symbols(grammar, [])
  try extract_tokens(grammar, meta) catch {
    err => assert_eq(err, ExternalTokenNonTerminal("rule_1"))
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "extraction_on_hidden_terminal (pending)" {
  // `_rule_1` is hidden and its token "a" is anonymous, so the absorption guard declines.
  // Both variables stay, and the anonymous token keeps its own name.
  let pool = RulePool::new()
  let r0 = n_sym(pool, "_rule_1")
  let r1 = str(pool, "a")
  let variables : Array[Variable] = [
    { name: pool.intern("rule_0"), root: r0, },
    { name: pool.intern("_rule_1"), root: r1, },
  ]
  let grammar = pool_grammar(pool, variables)
  let pending = extract_pending(grammar)
  let root = pending.lexical_variables[0].root
  let expected = str(pending.grammar.pool, "a")
  assert_true(pending.grammar.pool.subtree_eq(root, expected))
  assert_eq(variable_names(grammar), ["rule_0", "_rule_1"])
  assert_eq(pending.meta.kinds, [Named, Hidden])
  assert_eq(lexical_names(pending), [("a", Anonymous)])
  assert_true(pending.syntax_variable_replacements.is_empty())
}

///|
test "extraction_with_empty_string" {
  // An empty string outside the start rule is an error.
  let pool = RulePool::new()
  let r0 = n_sym(pool, "_rule_1")
  let r1 = str(pool, "")
  let variables : Array[Variable] = [
    { name: pool.intern("rule_0"), root: r0, },
    { name: pool.intern("_rule_1"), root: r1, },
  ]
  let grammar = pool_grammar(pool, variables)
  let meta = intern_symbols(grammar, [])
  try extract_tokens(grammar, meta) catch {
    err => assert_eq(err, EmptyString("_rule_1"))
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "non_terminal word token error text" {
  let err : ExtractTokensError = WordToken({
    symbol_name: "a",
    conflicting_symbol_name: Some("b"),
  })
  inspect(
    err.to_string(),
    content=(
      #|Non-terminal symbol 'a' cannot be used as the word token, because its rule is duplicated in 'b'
      #|
    ),
  )
  let err : ExtractTokensError = WordToken({
    symbol_name: "a",
    conflicting_symbol_name: None,
  })
  inspect(
    err.to_string(),
    content=(
      #|Non-terminal symbol 'a' cannot be used as the word token
      #|
    ),
  )
}
