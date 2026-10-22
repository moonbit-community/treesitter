///|
test "shared lexical definitions retain named syntax wrappers" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "shared_token",
      [
        (
          "document",
          Choice([
            Seq([Symbol("import"), Literal("(")]),
            Seq([Literal("import"), Symbol("identifier")]),
          ]),
        ),
        ("import", Token(Literal("import"))),
        ("identifier", @grammar.pattern("[a-z]+")),
      ],
      word="identifier",
    ),
  )
  let parser = @treesitter.Parser::new(language)
  assert_eq(
    parser.parse_string("import name").root_node().to_sexp(),
    "(document (identifier))",
  )
  assert_eq(
    parser.parse_string("import(").root_node().to_sexp(),
    "(document (import))",
  )
  assert_eq(
    language.tokens
    .filter(t => language.symbols[t.symbol].name == "import")
    .length(),
    1,
  )
}

///|
test "duplicate named patterns share a token and preserve both wrappers" {
  let language = @generate.generate(
    @grammar.Grammar::new("shared_pattern", [
      ("document", Seq([Symbol("first"), Literal(":"), Symbol("second")])),
      ("first", @grammar.pattern("[a-z]+")),
      ("second", @grammar.pattern("[a-z]+")),
    ]),
  )
  assert_eq(
    @treesitter.Parser::new(language)
    .parse_string("left:right")
    .root_node()
    .to_sexp(),
    "(document (first) (second))",
  )
}
