// Tests ported from tree-sitter crates/generate/src/prepare_grammar/flatten_grammar.rs.

///|
struct StepView {
  symbol : Symbol
  prec : Precedence
  assoc : Associativity?
  alias : Alias?
  field : String?
  reserved : Int32
} derive(Eq, Debug)

///|
fn StepView::new(symbol : Symbol) -> StepView {
  {
    symbol,
    prec: NoPrecedence,
    assoc: None,
    alias: None,
    field: None,
    reserved: 0,
  }
}

///|
fn StepView::prec(self : StepView, prec : Precedence) -> StepView {
  { ..self, prec, }
}

///|
fn StepView::assoc(self : StepView, assoc : Associativity?) -> StepView {
  { ..self, assoc, }
}

///|
fn StepView::field(self : StepView, name : String) -> StepView {
  { ..self, field: Some(name), }
}

///|
struct ProdView {
  dyn_prec : Int32
  steps : Array[StepView]
} derive(Eq, Debug)

///|
fn flatten_run(
  g : InputGrammar,
  meta : ExtractedGrammarMeta,
) -> (SyntaxGrammar, StrPool) raise FlattenGrammarError {
  let st = FlattenState::new()
  let out = ProductionStore::new()
  flatten_grammar(g, meta, st, out)
  assemble_syntax_grammar(g, meta, out)
}

///|
fn flatten_named(
  build : (RulePool) -> RuleId,
) -> (SyntaxGrammar, StrPool) raise FlattenGrammarError {
  let pool = RulePool::new()
  let root = build(pool)
  let name = pool.intern("test")
  let pg = pool_grammar(pool, [{ name, root, }])
  let meta = { ..ExtractedGrammarMeta::default(), kinds: [Named], }
  flatten_run(pg, meta)
}

///|
/// Unpack a variable's productions from the pooled output into comparable views.
fn prods(
  grammar : SyntaxGrammar,
  variable : Int32,
  interner : StrPool,
) -> Array[ProdView] {
  let (p_start, p_end) = grammar.var_prods[variable]
  grammar.productions[p_start:p_end]
  .iter()
  .map(p => {
    dyn_prec: p.dynamic_precedence,
    steps: grammar.steps[p.steps_start:p.steps_start + p.steps_len]
    .iter()
    .map(s => {
      symbol: s.symbol,
      prec: s.precedence,
      assoc: s.associativity,
      alias: s.alias,
      field: s.field.map(f => interner.resolve(f)),
      reserved: s.reserved,
    })
    .to_array(),
  })
  .to_array()
}

///|
test "flatten_grammar" {
  let (grammar, interner) = flatten_named(p => {
    let nt1 = non_term(p, 1)
    let nt2 = non_term(p, 2)
    let nt3 = non_term(p, 3)
    let nt4 = non_term(p, 4)
    let nt5 = non_term(p, 5)
    let nt6 = non_term(p, 6)
    let nt7 = non_term(p, 7)
    let inner = {
      let s = p.seq([nt3, nt4])
      p.prec_right(Integer(102), s)
    }
    let choice = p.choice([inner, nt5])
    let pl = {
      let s = p.seq([nt2, choice, nt6])
      p.prec_left(Integer(101), s)
    }
    p.seq([nt1, pl, nt7])
  })
  assert_eq(prods(grammar, 0, interner), [
    {
      dyn_prec: 0,
      steps: [
        StepView::new(Symbol::non_terminal(1)),
        StepView::new(Symbol::non_terminal(2))
        .prec(Integer(101))
        .assoc(Some(Left)),
        StepView::new(Symbol::non_terminal(3))
        .prec(Integer(102))
        .assoc(Some(Right)),
        StepView::new(Symbol::non_terminal(4))
        .prec(Integer(101))
        .assoc(Some(Left)),
        StepView::new(Symbol::non_terminal(6)),
        StepView::new(Symbol::non_terminal(7)),
      ],
    },
    {
      dyn_prec: 0,
      steps: [
        StepView::new(Symbol::non_terminal(1)),
        StepView::new(Symbol::non_terminal(2))
        .prec(Integer(101))
        .assoc(Some(Left)),
        StepView::new(Symbol::non_terminal(5))
        .prec(Integer(101))
        .assoc(Some(Left)),
        StepView::new(Symbol::non_terminal(6)),
        StepView::new(Symbol::non_terminal(7)),
      ],
    },
  ])
}

///|
test "flatten_grammar_with_maximum_dynamic_precedence" {
  let (grammar, interner) = flatten_named(p => {
    let nt1 = non_term(p, 1)
    let nt2 = non_term(p, 2)
    let nt3 = non_term(p, 3)
    let nt4 = non_term(p, 4)
    let nt5 = non_term(p, 5)
    let nt6 = non_term(p, 6)
    let nt7 = non_term(p, 7)
    let inner = {
      let s = p.seq([nt3, nt4])
      p.prec_dynamic(102, s)
    }
    let choice = p.choice([inner, nt5])
    let pd = {
      let s = p.seq([nt2, choice, nt6])
      p.prec_dynamic(101, s)
    }
    p.seq([nt1, pd, nt7])
  })
  assert_eq(prods(grammar, 0, interner), [
    {
      dyn_prec: 102,
      steps: [
        StepView::new(Symbol::non_terminal(1)),
        StepView::new(Symbol::non_terminal(2)),
        StepView::new(Symbol::non_terminal(3)),
        StepView::new(Symbol::non_terminal(4)),
        StepView::new(Symbol::non_terminal(6)),
        StepView::new(Symbol::non_terminal(7)),
      ],
    },
    {
      dyn_prec: 101,
      steps: [
        StepView::new(Symbol::non_terminal(1)),
        StepView::new(Symbol::non_terminal(2)),
        StepView::new(Symbol::non_terminal(5)),
        StepView::new(Symbol::non_terminal(6)),
        StepView::new(Symbol::non_terminal(7)),
      ],
    },
  ])
}

///|
test "flatten_grammar_with_final_precedence" {
  let (grammar, interner) = flatten_named(p => {
    let nt1 = non_term(p, 1)
    let nt2 = non_term(p, 2)
    let s = p.seq([nt1, nt2])
    p.prec_left(Integer(101), s)
  })
  assert_eq(prods(grammar, 0, interner), [
    {
      dyn_prec: 0,
      steps: [
        StepView::new(Symbol::non_terminal(1))
        .prec(Integer(101))
        .assoc(Some(Left)),
        StepView::new(Symbol::non_terminal(2))
        .prec(Integer(101))
        .assoc(Some(Left)),
      ],
    },
  ])
  let (grammar, interner) = flatten_named(p => {
    let nt1 = non_term(p, 1)
    let s = p.seq([nt1])
    p.prec_left(Integer(101), s)
  })
  assert_eq(prods(grammar, 0, interner), [
    {
      dyn_prec: 0,
      steps: [
        StepView::new(Symbol::non_terminal(1))
        .prec(Integer(101))
        .assoc(Some(Left)),
      ],
    },
  ])
}

///|
test "flatten_grammar_with_field_names" {
  let (grammar, interner) = flatten_named(p => {
    let t1 = term(p, 1)
    let f1 = {
      let n = p.intern("first-thing")
      p.field(n, t1)
    }
    let t2 = term(p, 2)
    let t3 = term(p, 3)
    let f2 = {
      let n = p.intern("second-thing")
      p.field(n, t3)
    }
    let blank = p.blank()
    let choice = p.choice([blank, f2])
    p.seq([f1, t2, choice])
  })
  assert_eq(prods(grammar, 0, interner), [
    {
      dyn_prec: 0,
      steps: [
        StepView::new(Symbol::terminal(1)).field("first-thing"),
        StepView::new(Symbol::terminal(2)),
      ],
    },
    {
      dyn_prec: 0,
      steps: [
        StepView::new(Symbol::terminal(1)).field("first-thing"),
        StepView::new(Symbol::terminal(2)),
        StepView::new(Symbol::terminal(3)).field("second-thing"),
      ],
    },
  ])
}

///|
test "precedence_inherited_through_inner_metadata" {
  // A prec region inherited by an inner symbol that carries _different_ metadata
  // (field).
  let (grammar, interner) = flatten_named(p => {
    let a = term(p, 1)
    let b = term(p, 2)
    let bf = {
      let n = p.intern("f")
      p.field(n, b)
    }
    let s = p.seq([a, bf])
    p.prec(Integer(5), s)
  })
  assert_eq(prods(grammar, 0, interner), [
    {
      dyn_prec: 0,
      steps: [
        StepView::new(Symbol::terminal(1)).prec(Integer(5)),
        StepView::new(Symbol::terminal(2)).prec(Integer(5)).field("f"),
      ],
    },
  ])
}

///|
test "flatten_grammar_with_recursive_inline_variable" {
  let pool = RulePool::new()
  let nt0 = non_term(pool, 0)
  let nt1 = non_term(pool, 1)
  let nt2 = non_term(pool, 2)
  let root = pool.seq([nt0, nt1, nt2])
  let name = pool.intern("test")
  let pg = pool_grammar(pool, [{ name, root, }])
  let meta = {
    ..ExtractedGrammarMeta::default(),
    kinds: [Named],
    inline: [Symbol::non_terminal(0)],
  }
  try flatten_run(pg, meta) catch {
    err => assert_eq(err, RecursiveInline("test"))
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "flatten_grammar_with_unknown_reserved" {
  // Unknown reserved context
  try
    flatten_named(p => {
      let t1 = term(p, 1)
      let ctx = p.intern("nope")
      p.reserved(t1, ctx)
    })
  catch {
    err => assert_eq(err, NoReservedWordSet("nope"))
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "flatten_grammar_with_empty_production" {
  // Empty production in used variable (`a` refs `b`, `b` is empty)
  let pool = RulePool::new()
  let a_root = non_term(pool, 1)
  let b_root = pool.blank()
  let (a, b) = (pool.intern("a"), pool.intern("b"))
  let pg = pool_grammar(pool, [
    { name: a, root: a_root, },
    { name: b, root: b_root, },
  ])
  let meta = { ..ExtractedGrammarMeta::default(), kinds: [Named, Named], }
  try flatten_run(pg, meta) catch {
    err => assert_eq(err, EmptyString("b"))
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "flatten_grammar_with_empty_choice" {
  let (grammar, interner) = flatten_named(p => {
    let prefix = term(p, 1)
    let empty = p.choice([])
    let tail_a = term(p, 2)
    let tail_b = term(p, 3)
    let tail = p.choice([tail_a, tail_b])
    let dead = p.seq([prefix, empty, tail])
    let live = term(p, 4)
    p.choice([dead, live])
  })
  assert_eq(prods(grammar, 0, interner), [
    { dyn_prec: 0, steps: [StepView::new(Symbol::terminal(4))], },
  ])
  let (grammar, interner) = flatten_named(p => p.choice([]))
  assert_eq(prods(grammar, 0, interner), [])
}
