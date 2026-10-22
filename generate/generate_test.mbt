///|
test "canonical tables support nullable start and recursive productions" {
  let grammar = @grammar.Grammar::new("list", [
    ("document", Repeat(Symbol("item"))),
    ("item", @grammar.pattern("[a-z]+")),
  ])
  let first = @generate.generate(grammar)
  let second = @generate.generate(grammar)
  assert_eq(first, second)
  first.validate()
  assert_true(first.states.length() > 3)
  assert_true(first.lookahead(0).contains(0))
  assert_eq(first.lookahead(-1), [])
}

///|
test "undeclared conflicts fail while declared GLR conflicts remain" {
  let expr : @grammar.Rule = Symbol("expression")
  let rules : Array[(String, @grammar.Rule)] = [
    ("expression", Choice([Seq([expr, Literal("+"), expr]), Literal("1")])),
  ]
  let grammar = @grammar.Grammar::new("ambiguous", rules)
  try @generate.generate(grammar) catch {
    @generate.Conflict(_, token, rules) => {
      assert_eq(token, "+")
      assert_eq(rules, ["expression"])
    }
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("accepted undeclared ambiguity")
  }
  let declared = @generate.generate(
    @grammar.Grammar::new("ambiguous", rules, conflicts=[["expression"]]),
  )
  assert_true(
    declared.states.any(state => {
      state.actions.values().any(actions => actions.length() > 1)
    }),
  )
}

///|
test "static precedence resolves expression conflicts" {
  let expr : @grammar.Rule = Symbol("expression")
  let grammar = @grammar.Grammar::new("arithmetic", [
    (
      "expression",
      Choice([
        @grammar.prec_left(Seq([expr, Literal("+"), expr]), value=1),
        @grammar.prec_left(Seq([expr, Literal("*"), expr]), value=2),
        Literal("1"),
      ]),
    ),
  ])
  let language = @generate.generate(grammar)
  assert_true(
    language.states.all(state => {
      state.actions.values().all(actions => actions.length() == 1)
    }),
  )
}

///|
test "nonproductive and nullable repeated grammars fail" {
  let grammars = [
    @grammar.Grammar::new("cycle", [("start", Symbol("start"))]),
    @grammar.Grammar::new("empty", [("start", Repeat(Blank))]),
    @grammar.Grammar::new("token", [("start", @grammar.pattern("a*"))]),
  ]
  for grammar in grammars {
    try @generate.generate(grammar) catch {
      @generate.InvalidGrammar(_) => ()
      e => fail("unexpected error: \{e}")
    } noraise {
      _ => fail("accepted invalid grammar")
    }
  }
}

///|
test "supertypes reject terminal and multiple visible children" {
  for rule in [@grammar.pattern("[a-z]+"), Seq([Symbol("a"), Symbol("a")])] {
    let grammar = @grammar.Grammar::new(
      "invalid",
      [
        ("document", Symbol("category")),
        ("category", rule),
        ("a", Literal("a")),
      ],
      supertypes=["category"],
    )
    try @generate.generate(grammar) catch {
      @generate.InvalidGrammar(_) => ()
      error => fail("unexpected: \{error}")
    } noraise {
      _ => fail("accepted invalid supertype")
    }
  }
}
