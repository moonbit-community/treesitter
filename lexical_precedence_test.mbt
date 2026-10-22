///|
test "inner lexical precedence competes at the transition boundary" {
  let grammar = @grammar.Grammar::new(
    "lexical_scopes",
    [
      ("document", Choice([Symbol("a"), Seq([Symbol("b"), Literal("y")])])),
      (
        "a",
        Token(
          @grammar.prec(2, Seq([Literal("x"), @grammar.prec(-1, Literal("y"))])),
        ),
      ),
      ("b", Token(@grammar.prec(1, Literal("x")))),
    ],
    extras=[],
  )
  let language = @generate.generate(grammar)
  for
    language in [
      language,
      @language.Language::parse(Json(language).stringify()),
    ] {
    assert_eq(
      @treesitter.Parser::new(language).parse_string("xy").root_node().to_sexp(),
      "(document (b))",
    )
  }
}

///|
test "inner lexical precedence can extend past a higher completion" {
  let grammar = @grammar.Grammar::new(
    "lexical_scopes",
    [
      ("document", Choice([Symbol("a"), Seq([Symbol("b"), Literal("y")])])),
      ("a", Token(Seq([Literal("x"), @grammar.prec(2, Literal("y"))]))),
      ("b", Token(@grammar.prec(1, Literal("x")))),
    ],
    extras=[],
  )
  let language = @generate.generate(grammar)
  assert_eq(
    @treesitter.Parser::new(language).parse_string("xy").root_node().to_sexp(),
    "(document (a))",
  )
}

///|
// Upstream implicit precedence is 2 for a literal plus 1 for immediate.
// It breaks equal-length ties after explicit precedence and longest match.
test "literal tokens outrank immediate patterns at equal length" {
  let language = @generate.generate(
    @grammar.Grammar::new("implicit_lexical", [
      ("document", Choice([Symbol("literal"), Symbol("pattern")])),
      ("literal", Literal("x")),
      ("pattern", ImmediateToken(@grammar.pattern("[a-z]+"))),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  assert_eq(
    parser.parse_string("x").root_node().to_sexp(),
    "(document (literal))",
  )
  assert_eq(
    parser.parse_string("xy").root_node().to_sexp(),
    "(document (pattern))",
  )
}
