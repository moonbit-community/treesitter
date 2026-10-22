///|
test "all upstream rule variants round trip without losing metadata" {
  let leaf : @grammar.Rule = Literal("x")
  let variants : Array[@grammar.Rule] = [
    Blank,
    Eof,
    leaf,
    @grammar.pattern("[a-z]+", flags="i"),
    Symbol("start"),
    Choice([leaf, Blank]),
    Seq([leaf, leaf]),
    Repeat(leaf),
    Repeat1(leaf),
    Token(leaf),
    ImmediateToken(leaf),
    Prec(Integer(3), leaf),
    PrecLeft(Name("sum"), leaf),
    PrecRight(Integer(-2), leaf),
    PrecDynamic(4, leaf),
    Field("value", leaf),
    Alias(leaf, "identifier", named=true),
    Reserved("global", leaf),
  ]
  for rule in variants {
    assert_eq(@grammar.Rule::from_json(Json(rule)), rule)
  }
  let grammar = @grammar.Grammar::new(
    "test",
    [("start", Choice(variants)), ("identifier", @grammar.pattern("[a-z]+"))],
    externals=[Symbol("indent")],
    conflicts=[["start", "identifier"]],
    precedences=[[Literal("sum"), Symbol("start")]],
    inline_rules=["identifier"],
    supertypes=["start"],
    word="identifier",
    reserved={ "global": [leaf] },
  )
  grammar.validate()
  assert_eq(@grammar.Grammar::parse(Json(grammar).stringify()), grammar)
}

///|
test "JSON preserves rule insertion order and explicit empty extras" {
  let source =
    #|{"name":"order","rules":{"z":{"type":"STRING","value":"z"},"a":{"type":"STRING","value":"a"}},"extras":[]}
  let grammar = @grammar.Grammar::parse(source)
  assert_eq(grammar.rules[0].0, "z")
  assert_eq(grammar.rules[1].0, "a")
  assert_eq(grammar.extras.length(), 0)
  assert_eq(@grammar.Grammar::parse(Json(grammar).stringify()), grammar)
}

///|
test "unknown references and duplicate rules produce actionable errors" {
  let invalid = @grammar.Grammar::new("broken", [("start", Symbol("missing"))])
  try invalid.validate() catch {
    @grammar.InvalidGrammar(message) =>
      assert_eq(message, "rules.start: unknown rule 'missing'")
  } noraise {
    _ => fail("expected undefined rule error")
  }
  let duplicate = @grammar.Grammar::new("duplicate", [
    ("x", Blank),
    ("x", Blank),
  ])
  try duplicate.validate() catch {
    @grammar.InvalidGrammar(message) => assert_eq(message, "duplicate rule 'x'")
  } noraise {
    _ => fail("expected duplicate rule error")
  }
}

///|
test "malformed JSON rule values are rejected" {
  let inputs = [
    "{\"type\":\"NOT_A_RULE\"}", "{\"type\":\"STRING\"}", "{\"type\":\"PREC_DYNAMIC\",\"value\":0.5,\"content\":{\"type\":\"BLANK\"}}",
    "{\"type\":\"ALIAS\",\"named\":0,\"value\":\"x\",\"content\":{\"type\":\"BLANK\"}}",
    "{\"type\":\"PATTERN\",\"value\":1}",
  ]
  for source in inputs {
    let value = @json.parse(source)
    try @grammar.Rule::from_json(value) catch {
      @grammar.InvalidGrammar(_) => ()
    } noraise {
      _ => fail("accepted malformed rule: \{source}")
    }
  }
}

///|
test "grammar DSL helpers preserve separator and associativity semantics" {
  let x : @grammar.Rule = Literal("x")
  let comma : @grammar.Rule = Literal(",")
  assert_eq(
    @grammar.sep(x, comma),
    Choice([Seq([x, Repeat(Seq([comma, x]))]), Blank]),
  )
  assert_eq(@grammar.prec_left(x, value=2), PrecLeft(Integer(2), x))
  assert_eq(@grammar.prec_right(x), PrecRight(Integer(0), x))
}
