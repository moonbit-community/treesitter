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
