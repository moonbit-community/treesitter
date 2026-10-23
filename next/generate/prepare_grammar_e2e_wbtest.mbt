// End-to-end tests ported from tree-sitter crates/generate/src/prepare_grammar.rs
// and prepare_grammar/extract_tokens.rs. They run `expand_tokens` (directly or
// through `PendingTokenExtraction::expand_and_commit`), which is ported
// separately; remove the `#skip` attributes once it is integrated.

///|
fn extract(g : InputGrammar) -> (ExtractedGrammarMeta, LexicalGrammar) raise {
  extract_pending(g).expand_and_commit()
}

///|
fn prepare_error(g : InputGrammar) -> String? {
  try prepare_grammar(g, []) catch {
    e => Some(e.to_string())
  } noraise {
    _ => None
  }
}

///|
fn lexical_summary(
  prepared : PreparedGrammar,
) -> Array[(String, VariableType, Int32, Int32)] {
  prepared.lexical_grammar.variables.map(v => {
    (
      prepared.str_pool.resolve(v.name),
      v.kind,
      v.implicit_precedence,
      v.start_state,
    )
  })
}

///|
fn syntax_summary(prepared : PreparedGrammar) -> Array[(String, VariableType)] {
  prepared.syntax_grammar.variables.map(v => {
    (prepared.str_pool.resolve(v.name), v.kind)
  })
}

// extract_tokens.rs ------------------------------------------------------------

///|
test "extraction" {
  let grammar = extraction_grammar()
  let (ext, lexical_grammar) = extract(grammar)

  // rule_1 was absorbed into the lexical grammar, rule_0, rule_2, and rule_3 remain
  assert_eq(variable_names(grammar), ["rule_0", "rule_2", "rule_3"])
  assert_eq(ext.kinds, [Named, Named, Named])

  // rule_0: repeat(seq(terminal(0), terminal(1), choice(terminal(3), non_terminal(2),
  // terminal(2))))
  //  - Its leaves became terminals: "a"->t0, "b"->t1, token(...)->t2.
  //  - Its symbol refs changed: rule_1 was absorbed into the lexer (now t3),
  //  rule_2's index dropped to 1 because rule_1 was removed.
  let expected_r0 = {
    let p = grammar.pool
    let ch = {
      let (a, b, c) = (term(p, 3), non_term(p, 1), term(p, 2))
      p.choice([a, b, c])
    }
    let sq = {
      let (a, b) = (term(p, 0), term(p, 1))
      p.seq([a, b, ch])
    }
    p.repeat(sq)
  }
  assert_true(grammar.pool.subtree_eq(grammar.variables[0].root, expected_r0))

  // rule_2 is `/b/` -> terminal(1). It is *not* absorbed: `/b/` appears in
  // two places (rule_0 and rule_2), so its terminal is used more than once.
  assert_eq(
    grammar.pool.node(grammar.variables[1].root),
    Sym(Symbol::terminal(1)),
  )

  // rule_3: seq(non_terminal(1), blank) -> rule_2 decremented after rule_1's removal
  let expected_r3 = {
    let p = grammar.pool
    let (nt, bl) = (non_term(p, 1), p.blank())
    p.seq([nt, bl])
  }
  assert_true(grammar.pool.subtree_eq(grammar.variables[2].root, expected_r3))

  // `/e/` is used in exactly one place (as rule_1's whole body), so rule_1
  // was absorbed into the lexical grammar (and donated its name to the token).
  let lex = lexical_grammar.variables.map(v => {
    (grammar.pool.resolve(v.name), v.kind)
  })
  assert_eq(lex, [
    ("a", Anonymous),
    ("rule_0_token1", Auxiliary),
    ("rule_0_token2", Auxiliary),
    ("rule_1", Named),
  ])
}

///|
test "start_rule_is_token" {
  // The start rule is a bare token. The token is extracted, but the start
  // rule is never absorbed. It stays as a reference to terminal 0.
  let pool = RulePool::new()
  let r0 = str(pool, "hello")
  let grammar = pool_grammar(pool, [{ name: pool.intern("rule_0"), root: r0, }])
  let (_, lexical_grammar) = extract(grammar)
  assert_eq(variable_names(grammar), ["rule_0"])
  assert_eq(
    grammar.pool.node(grammar.variables[0].root),
    Sym(Symbol::terminal(0)),
  )
  let lex = lexical_grammar.variables.map(v => {
    (grammar.pool.resolve(v.name), v.kind)
  })
  assert_eq(lex, [("hello", Anonymous)])
}

///|
test "extracting_extra_symbols" {
  let pool = RulePool::new()
  let r0 = str(pool, "x")
  let comment = pat(pool, "//.*")
  let sep = str(pool, " ")
  let extra_ref = n_sym(pool, "comment")
  let grammar = pool_grammar(pool, [
    { name: pool.intern("rule_0"), root: r0, },
    { name: pool.intern("comment"), root: comment, },
  ])
  grammar.extra_roots = [sep, extra_ref]
  let (ext, _) = extract(grammar)
  assert_eq(ext.extra_symbols, [Symbol::terminal(1)])
}

///|
test "extract_externals" {
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
  let (ext, _) = extract(grammar)
  assert_eq(ext.external_tokens, [
    { name: external_0, kind: Named, corresponding_internal_token: None, },
    {
      name: a,
      kind: Anonymous,
      corresponding_internal_token: Some(Symbol::terminal(0)),
    },
    {
      name: rule_2,
      kind: Named,
      corresponding_internal_token: Some(Symbol::terminal(2)),
    },
  ])
}

///|
test "extraction_on_hidden_terminal" {
  let pool = RulePool::new()
  let r0 = n_sym(pool, "_rule_1")
  let r1 = str(pool, "a")
  let grammar = pool_grammar(pool, [
    { name: pool.intern("rule_0"), root: r0, },
    { name: pool.intern("_rule_1"), root: r1, },
  ])
  let (ext, lexical_grammar) = extract(grammar)
  assert_eq(variable_names(grammar), ["rule_0", "_rule_1"])
  assert_eq(ext.kinds, [Named, Hidden])
  assert_eq(
    grammar.pool.node(grammar.variables[0].root),
    Sym(Symbol::non_terminal(1)),
  )
  assert_eq(
    grammar.pool.node(grammar.variables[1].root),
    Sym(Symbol::terminal(0)),
  )
  let lex = lexical_grammar.variables.map(v => {
    (grammar.pool.resolve(v.name), v.kind)
  })
  assert_eq(lex, [("a", Anonymous)])
}

// prepare_grammar.rs -----------------------------------------------------------

///|
test "validate_indirect_recursion" {
  // a -> b -> a
  let case1 = build_grammar(p => {
    let b_ref = named(p, "b")
    let x = leaf(p, "x")
    let a = p.choice([b_ref, x])
    let a_ref = named(p, "a")
    let b = p.prec(Integer(1), a_ref)
    [{ name: p.intern("a"), root: a, }, { name: p.intern("b"), root: b, }]
  })
  // A direct self-reference is allowed.
  let case2 = build_grammar(p => {
    let a = named(p, "a")
    [{ name: p.intern("a"), root: a, }]
  })
  // b -> c -> d -> b, entered from a non-cycle start rule.
  let case3 = build_grammar(p => {
    let x = leaf(p, "x")
    let c_ref = named(p, "c")
    let d_ref = named(p, "d")
    let b_ref = named(p, "b")
    [
      { name: p.intern("a"), root: x, },
      { name: p.intern("b"), root: c_ref, },
      { name: p.intern("c"), root: d_ref, },
      { name: p.intern("d"), root: b_ref, },
    ]
  })
  // b -> c -> b, through `seq(optional('|'), $.b, repeat(seq('|', $.b)))`
  let case4 = build_grammar(p => {
    let a = {
      let b = named(p, "b")
      let assign = leaf(p, ":=")
      p.seq([b, assign])
    }
    let b = {
      let x = leaf(p, "x")
      let c = named(p, "c")
      p.choice([x, c])
    }
    let c = {
      let pipe = leaf(p, "|")
      let blank = p.blank()
      let leading_pipe = p.choice([pipe, blank])
      let b = named(p, "b")
      let rest = {
        let pipe = leaf(p, "|")
        let b = named(p, "b")
        let item = p.seq([pipe, b])
        let items = p.repeat(item)
        let blank = p.blank()
        p.choice([items, blank])
      }
      p.seq([leading_pipe, b, rest])
    }
    [
      { name: p.intern("a"), root: a, },
      { name: p.intern("b"), root: b, },
      { name: p.intern("c"), root: c, },
    ]
  })
  let err1 = IndirectRecursionError(["a", "b", "a"]).to_string()
  let err3 = IndirectRecursionError(["b", "c", "d", "b"]).to_string()
  let err4 = IndirectRecursionError(["b", "c", "b"]).to_string()
  for
    case in [
      (case1, Some(err1)),
      (case2, None),
      (case3, Some(err3)),
      (case4, Some(err4)),
    ] {
    let (g, expected) = case
    assert_eq(prepare_error(g), expected)
  }
}

///|
/// `source: 'a'` followed by `rules`, with `comment` as the only extra
fn extras_grammar(
  rules : (RulePool) -> Array[(String, RuleId)],
) -> InputGrammar {
  let grammar = build_grammar(p => {
    let source = leaf(p, "a")
    let rules = rules(p)
    [("source", source), ..rules].map(entry => {
      name: p.intern(entry.0),
      root: entry.1,
    })
  })
  let extra = named(grammar.pool, "comment")
  grammar.extra_roots.push(extra)
  grammar
}

///|
test "validate_extras" {
  let cases : Array[(InputGrammar, Bool)] = [
    // A token
    (extras_grammar(p => [("comment", pattern(p, ".*"))]), true),
    // A non-terminal whose only step is a token
    (
      extras_grammar(p => {
        let content = pattern(p, ".*")
        [("comment", p.seq([content]))]
      }),
      true,
    ),
    // A non-terminal with an empty production
    (
      extras_grammar(p => {
        let hash = leaf(p, "#")
        let content = pattern(p, ".*")
        let comment = p.seq([hash, content])
        let blank = p.blank()
        [("comment", p.choice([comment, blank]))]
      }),
      true,
    ),
    // A non-terminal that matches it through another one
    (
      extras_grammar(p => {
        let comment = {
          let hashes = pattern(p, "#*")
          let body = named(p, "_body")
          p.seq([hashes, body])
        }
        let content = pattern(p, ".*")
        [("comment", comment), ("_body", p.seq([content]))]
      }),
      true,
    ),
    // A non-terminal that matches it through rules that reach each other
    (
      extras_grammar(p => {
        let comment = {
          let hashes = pattern(p, "#*")
          let a = named(p, "a")
          let b = named(p, "b")
          let bangs = pattern(p, "!*")
          p.seq([hashes, a, b, bangs])
        }
        let a = {
          let b = named(p, "b")
          let xs = pattern(p, "x*")
          let b_xs = p.seq([b, xs])
          let zs = pattern(p, "z*")
          p.choice([b_xs, zs])
        }
        let b = {
          let a = named(p, "a")
          let ws = pattern(p, "w*")
          p.seq([a, ws])
        }
        [("comment", comment), ("a", a), ("b", b)]
      }),
      true,
    ),
    // A nullable first token is safe when a later step consumes input
    (
      extras_grammar(p => {
        let hashes = pattern(p, "#*")
        let hash = leaf(p, "#")
        [("comment", p.seq([hashes, hash]))]
      }),
      false,
    ),
    // These have to consume the `#`
    (
      extras_grammar(p => {
        let hash = leaf(p, "#")
        let content = pattern(p, ".*")
        let comment = p.seq([hash, content])
        [("comment", p.token(comment))]
      }),
      false,
    ),
    (
      extras_grammar(p => {
        let hash = leaf(p, "#")
        let content = pattern(p, ".*")
        [("comment", p.seq([hash, content]))]
      }),
      false,
    ),
  ]
  for case in cases {
    let (grammar, matches_empty) = case
    let expected = if matches_empty {
      Some(EmptyStringExtraError("comment").to_string())
    } else {
      None
    }
    assert_eq(prepare_error(grammar), expected)
  }
}

///|
test "validate_extras_with_shared_nullable_rules" {
  let grammar = build_grammar(p => {
    let source = leaf(p, "a")
    let first = {
      let hashes = pattern(p, "#*")
      let a = named(p, "a")
      let bang = leaf(p, "!")
      p.seq([hashes, a, bang])
    }
    let second = {
      let ats = pattern(p, "@*")
      let b = named(p, "b")
      p.seq([ats, b])
    }
    let a = {
      let b = named(p, "b")
      let xs = pattern(p, "x*")
      let b_xs = p.seq([b, xs])
      let zs = pattern(p, "z*")
      p.choice([b_xs, zs])
    }
    let b = {
      let a = named(p, "a")
      let ws = pattern(p, "w*")
      p.seq([a, ws])
    }
    [
      ("source", source),
      ("first", first),
      ("second", second),
      ("a", a),
      ("b", b),
    ].map(entry => { name: p.intern(entry.0), root: entry.1, })
  })
  for name in ["first", "second"] {
    let extra = named(grammar.pool, name)
    grammar.extra_roots.push(extra)
  }

  // Checking the first extra reaches the nullable cycle, but its `!` makes it safe.
  // The same memo must still identify the second extra as nullable.
  assert_eq(
    prepare_error(grammar),
    Some(EmptyStringExtraError("second").to_string()),
  )
}

///|
test "nullable_syntactic_tokens_and_anonymous_extras" {
  let grammar = build_grammar(p => {
    let quote = leaf(p, "\"")
    let content = pattern(p, "[^\"]*")
    let source = p.seq([quote, content, quote])
    [{ name: p.intern("source"), root: source, }]
  })
  let whitespace = pattern(grammar.pool, "\\s*")
  grammar.extra_roots.push(whitespace)

  // Both tokens can match empty, but neither is shifted as an extra symbol.
  assert_eq(prepare_error(grammar), None)
}

///|
test "token_body_shared_with_syntax" {
  let grammar = build_grammar(p => {
    let a = leaf(p, "a")
    let b = leaf(p, "b")
    let shared = p.seq([a, b])
    let token = p.token(shared)
    let program = {
      let t = named(p, "t")
      let x = named(p, "x")
      p.seq([t, x])
    }
    [
      { name: p.intern("program"), root: program, },
      { name: p.intern("t"), root: token, },
      { name: p.intern("x"), root: shared, },
    ]
  })
  let prepared = prepare_grammar(grammar, [])
  assert_eq(syntax_summary(prepared), [("program", Named), ("x", Named)])
  assert_eq(lexical_summary(prepared), [
    ("t", Named, 0, 2),
    ("a", Anonymous, 2, 4),
    ("b", Anonymous, 2, 6),
  ])
}

///|
test "token_body_shared_with_syntax_reversed" {
  let grammar = build_grammar(p => {
    let a = leaf(p, "a")
    let b = leaf(p, "b")
    let shared = p.seq([a, b])
    let token = p.token(shared)
    let program = {
      let x = named(p, "x")
      let t = named(p, "t")
      p.seq([x, t])
    }
    [
      { name: p.intern("program"), root: program, },
      { name: p.intern("x"), root: shared, },
      { name: p.intern("t"), root: token, },
    ]
  })
  let prepared = prepare_grammar(grammar, [])
  assert_eq(syntax_summary(prepared), [("program", Named), ("x", Named)])
  assert_eq(lexical_summary(prepared), [
    ("a", Anonymous, 2, 1),
    ("b", Anonymous, 2, 3),
    ("t", Named, 0, 6),
  ])
}

///|
test "separator_body_shared_with_syntax" {
  let pool = RulePool::new()
  let a = leaf(pool, "a")
  let b = leaf(pool, "b")
  let shared = pool.seq([a, b])
  let program = pool.intern("program")
  let grammar = pool_grammar(pool, [{ name: program, root: shared, }])
  grammar.extra_roots = [shared]
  let prepared = prepare_grammar(grammar, [])
  assert_eq(syntax_summary(prepared), [("program", Named)])
  assert_eq(lexical_summary(prepared), [
    ("a", Anonymous, 2, 5),
    ("b", Anonymous, 2, 11),
  ])
  assert_eq(prepared.syntax_grammar.extra_symbols, [])
}

///|
test "shared_extra_symbol_is_renumbered_once" {
  let pool = RulePool::new()
  let target_ref = named(pool, "target")
  let program = {
    let kw = named(pool, "kw")
    let keep = named(pool, "keep")
    pool.seq([kw, keep, target_ref])
  }
  let kw = leaf(pool, "keyword")
  let keep = {
    let k = leaf(pool, "k")
    let e = leaf(pool, "e")
    pool.seq([k, e])
  }
  let target = {
    let t = leaf(pool, "t")
    let g = leaf(pool, "g")
    pool.seq([t, g])
  }
  let grammar = pool_grammar(pool, [
    { name: pool.intern("program"), root: program, },
    { name: pool.intern("kw"), root: kw, },
    { name: pool.intern("keep"), root: keep, },
    { name: pool.intern("target"), root: target, },
  ])
  grammar.extra_roots = [target_ref]
  let prepared = prepare_grammar(grammar, [])
  assert_eq(syntax_summary(prepared), [
    ("program", Named),
    ("keep", Named),
    ("target", Named),
  ])
  assert_eq(lexical_summary(prepared), [
    ("kw", Named, 2, 7),
    ("k", Anonymous, 2, 9),
    ("e", Anonymous, 2, 11),
    ("t", Anonymous, 2, 13),
    ("g", Anonymous, 2, 15),
  ])
  assert_eq(prepared.syntax_grammar.extra_symbols, [Symbol::non_terminal(2)])
}

///|
test "shared_syntax_subtree_is_renumbered_once" {
  let grammar = build_grammar(p => {
    let pair = {
      let thing = named(p, "thing")
      let dash = leaf(p, "-")
      p.seq([thing, dash])
    }
    let item_b = {
      let semicolon = leaf(p, ";")
      p.seq([pair, semicolon])
    }
    let program = {
      let kw = named(p, "kw")
      let item_a = named(p, "item_a")
      let item_b = named(p, "item_b")
      p.seq([kw, item_a, item_b])
    }
    let kw = leaf(p, "keyword")
    let thing = {
      let t = leaf(p, "t")
      let u = leaf(p, "u")
      p.seq([t, u])
    }
    [
      { name: p.intern("program"), root: program, },
      { name: p.intern("kw"), root: kw, },
      { name: p.intern("item_a"), root: pair, },
      { name: p.intern("item_b"), root: item_b, },
      { name: p.intern("thing"), root: thing, },
    ]
  })
  let prepared = prepare_grammar(grammar, [])
  let expected_steps = [
    ProductionStep::pack(
      Symbol::non_terminal(3),
      NoPrecedence,
      None,
      None,
      None,
      0,
    ),
    ProductionStep::pack(Symbol::terminal(1), NoPrecedence, None, None, None, 0),
  ]
  let (start, end) = prepared.syntax_grammar.variable_prod_ids(1)
  assert_eq(end - start, 1)
  let production = prepared.syntax_grammar.production(start)
  assert_eq(production.steps.to_owned(), expected_steps)
  assert_eq(production.dynamic_precedence, 0)
}
