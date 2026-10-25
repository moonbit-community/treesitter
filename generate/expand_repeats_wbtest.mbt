// Tests ported from tree-sitter crates/generate/src/prepare_grammar/expand_repeats.rs.

///|
fn expand(
  pool : RulePool,
  variables : Array[Variable],
  kinds : Array[VariableType],
) -> (InputGrammar, ExtractedGrammarMeta) raise {
  let grammar = pool_grammar(pool, variables)
  let meta = { ..ExtractedGrammarMeta::default(), kinds, }
  expand_repeats(grammar, meta)
  (grammar, meta)
}

///|
test "basic_repeat_expansion" {
  // Repeats nested inside of sequences and choices are expanded.
  let pool = RulePool::new()
  let r0 = {
    let a = term(pool, 10)
    let ch = {
      let r1 = {
        let t = term(pool, 11)
        pool.repeat(t)
      }
      let r2 = {
        let t = term(pool, 12)
        pool.repeat(t)
      }
      pool.choice([r1, r2])
    }
    let b = term(pool, 13)
    pool.seq([a, ch, b])
  }
  let name = pool.intern("rule0")
  let (grammar, meta) = expand(pool, [{ name, root: r0, }], [Named])
  assert_eq(variable_names(grammar), ["rule0", "rule0_repeat1", "rule0_repeat2"])
  assert_eq(meta.kinds, [Named, Auxiliary, Auxiliary])

  // rule0: seq(terminal(10), choice(non_terminal(1), non_terminal(2)), terminal(13))
  let e0 = {
    let pool = grammar.pool
    let (a, b) = (term(pool, 10), term(pool, 13))
    let ch = {
      let (x, y) = (non_term(pool, 1), non_term(pool, 2))
      pool.choice([x, y])
    }
    pool.seq([a, ch, b])
  }
  assert_true(grammar.pool.subtree_eq(grammar.variables[0].root, e0))

  // rule0_repeat1: choice(seq(nt1, nt1), terminal(11))
  let e1 = {
    let p = grammar.pool
    let sq = {
      let (x, y) = (non_term(p, 1), non_term(p, 1))
      p.seq([x, y])
    }
    let t = term(p, 11)
    p.choice([sq, t])
  }
  assert_true(grammar.pool.subtree_eq(grammar.variables[1].root, e1))

  // rule0_repeat2: choice(seq(nt2, nt2), terminal(12))
  let e2 = {
    let p = grammar.pool
    let sq = {
      let (x, y) = (non_term(p, 2), non_term(p, 2))
      p.seq([x, y])
    }
    let t = term(p, 12)
    p.choice([sq, t])
  }
  assert_true(grammar.pool.subtree_eq(grammar.variables[2].root, e2))
}

///|
test "repeat_deduplication" {
  // repeat(terminal(4)) appears in 3 places. Only one aux rule is made
  let pool = RulePool::new()
  let r0 = {
    let s1 = {
      let t = term(pool, 1)
      let r = {
        let x = term(pool, 4)
        pool.repeat(x)
      }
      pool.seq([t, r])
    }
    let s2 = {
      let t = term(pool, 2)
      let r = {
        let x = term(pool, 4)
        pool.repeat(x)
      }
      pool.seq([t, r])
    }
    pool.choice([s1, s2])
  }
  let r1 = {
    let t = term(pool, 3)
    let r = {
      let x = term(pool, 4)
      pool.repeat(x)
    }
    pool.seq([t, r])
  }
  let (n0, n1) = (pool.intern("rule0"), pool.intern("rule1"))
  let variables : Array[Variable] = [
    { name: n0, root: r0, },
    { name: n1, root: r1, },
  ]
  let (g, meta) = expand(pool, variables, [Named, Named])
  assert_eq(variable_names(g), ["rule0", "rule1", "rule0_repeat1"])
  assert_eq(meta.kinds, [Named, Named, Auxiliary])

  // rule0: choice(seq(t1, nt2), sseq(t2, nt2))
  let e0 = {
    let p = g.pool
    let s1 = {
      let (t, n) = (term(p, 1), non_term(p, 2))
      p.seq([t, n])
    }
    let s2 = {
      let (t, n) = (term(p, 2), non_term(p, 2))
      p.seq([t, n])
    }
    p.choice([s1, s2])
  }
  assert_true(g.pool.subtree_eq(g.variables[0].root, e0))
  // rule1: seq(t3, nt2)
  let e1 = {
    let p = g.pool
    let (t, n) = (term(p, 3), non_term(p, 2))
    p.seq([t, n])
  }
  assert_true(g.pool.subtree_eq(g.variables[1].root, e1))
  // rule0_repeat1: choice(seq(nt2, nt2), terminal(4))
  let e2 = {
    let p = g.pool
    let sq = {
      let (x, y) = (non_term(p, 2), non_term(p, 2))
      p.seq([x, y])
    }
    let t = term(p, 4)
    p.choice([sq, t])
  }
  assert_true(g.pool.subtree_eq(g.variables[2].root, e2))
}

///|
test "expansion_of_nested_repeats" {
  // Nested repeats expand inside out. The inner one becomes `rule0_repeat1` (nt1),
  // and then outer one (now referencing it) becomes rule0_repeat2
  let pool = RulePool::new()
  let r0 = {
    let t10 = term(pool, 10)
    let outer = {
      let t11 = term(pool, 11)
      let inner = {
        let t = term(pool, 12)
        pool.repeat(t)
      }
      let content = pool.seq([t11, inner])
      pool.repeat(content)
    }
    pool.seq([t10, outer])
  }
  let name = pool.intern("rule0")
  let (g, meta) = expand(pool, [{ name, root: r0, }], [Named])
  assert_eq(variable_names(g), ["rule0", "rule0_repeat1", "rule0_repeat2"])
  assert_eq(meta.kinds, [Named, Auxiliary, Auxiliary])

  // rule0: seq(terminal(10), non_terminal(2))
  let e0 = {
    let p = g.pool
    let (t, n) = (term(p, 10), non_term(p, 2))
    p.seq([t, n])
  }
  assert_true(g.pool.subtree_eq(g.variables[0].root, e0))
  // rule0_repeat2 (outer): choice(seq(nt2, nt2), seq(terminal(11), nt1))
  let e2 = {
    let p = g.pool
    let sq1 = {
      let (x, y) = (non_term(p, 2), non_term(p, 2))
      p.seq([x, y])
    }
    let sq2 = {
      let (t, n) = (term(p, 11), non_term(p, 1))
      p.seq([t, n])
    }
    p.choice([sq1, sq2])
  }
  assert_true(g.pool.subtree_eq(g.variables[2].root, e2))
}

///|
test "expansion_of_repeats_at_top_of_hidden_rules" {
  // A hidden rule whos whole body is a repeat becomes its own recursive binary
  // tree (using its own symbol) instead of gaining a separate aux rule, and is
  // reclassified as Axuiliary.
  let pool = RulePool::new()
  let r0 = non_term(pool, 1)
  let r1 = {
    let ch = {
      let (a, b) = (term(pool, 11), term(pool, 12))
      pool.choice([a, b])
    }
    pool.repeat(ch)
  }
  let (n0, n1) = (pool.intern("rule0"), pool.intern("_rule1"))
  let variables : Array[Variable] = [
    { name: n0, root: r0, },
    { name: n1, root: r1, },
  ]
  let (g, meta) = expand(pool, variables, [Named, Hidden])

  // No separate aux rule: _rule1 absorbed during recursion
  assert_eq(variable_names(g), ["rule0", "_rule1"])
  assert_eq(meta.kinds, [Named, Auxiliary])

  // rule0: non_terminal(1) (unchanged)
  assert_eq(g.pool.node(g.variables[0].root), Sym(Symbol::non_terminal(1)))

  // _rule1: choice(seq(nt1, nt1), terminal(11), terminal(12)) (inner choice flattened)
  let e1 = {
    let p = g.pool
    let sq = {
      let (x, y) = (non_term(p, 1), non_term(p, 1))
      p.seq([x, y])
    }
    let (a, b) = (term(p, 11), term(p, 12))
    p.choice([sq, a, b])
  }
  assert_true(g.pool.subtree_eq(g.variables[1].root, e1))
}

///|
test "rejects_repeat_of_eof_helper_rule" {
  // rule0: repeat(non_terminal(1)); rule1: eof()
  let pool = RulePool::new()
  let r0 = {
    let n = non_term(pool, 1)
    pool.repeat(n)
  }
  let r1 = pool.push_node(Eof)
  let (n0, n1) = (pool.intern("rule0"), pool.intern("rule1"))
  let grammar = pool_grammar(pool, [
    { name: n0, root: r0, },
    { name: n1, root: r1, },
  ])
  let meta = { ..ExtractedGrammarMeta::default(), kinds: [Named, Named], }
  try expand_repeats(grammar, meta) catch {
    err => assert_eq(err, ExpandRepeatsError("rule0"))
  } noraise {
    _ => fail("expected an error")
  }
}
