///|
test "GLR ties preserve grammar order through hidden reductions" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "ambiguous_statement",
      [
        (
          "document",
          Seq([
            Literal("{"),
            Choice([Symbol("statement"), Symbol("_empty")]),
            Literal("}"),
          ]),
        ),
        ("statement", Seq([Symbol("_expression"), Literal(";")])),
        ("_expression", Symbol("identifier")),
        (
          "_empty",
          Seq([
            Alias(Symbol("identifier"), "type_identifier", named=true),
            Literal(";"),
          ]),
        ),
        ("identifier", @grammar.pattern("[a-z]+")),
      ],
      conflicts=[["_expression", "_empty"]],
    ),
  )
  inspect(
    @treesitter.Parser::new(language)
    .parse_string("{foo;}")
    .root_node()
    .to_sexp(),
    content="(document (statement (identifier)))",
  )
}

///|
test "equivalent live links retain the first derivation before shifting" {
  // Frozen from the pinned C runtime, including the inner await/call ambiguity.
  let language = @generate.generate(
    @grammar.Grammar::new(
      "ambiguity_fixture",
      [
        ("document", Symbol("expression")),
        ("expression", Choice([Symbol("primary"), Symbol("await_expression")])),
        (
          "primary",
          Choice([
            Symbol("call"),
            Symbol("parenthesized"),
            Alias(Literal("await"), "identifier", named=true),
          ]),
        ),
        ("await_expression", Seq([Literal("await"), Symbol("expression")])),
        ("call", Seq([Symbol("primary"), Symbol("arguments")])),
        (
          "parenthesized",
          Seq([Literal("("), Symbol("expression"), Literal(")")]),
        ),
        ("arguments", Seq([Literal("("), Symbol("expression"), Literal(")")])),
      ],
      conflicts=[["primary", "await_expression"]],
      extras=[],
    ),
  )
  let parser = @treesitter.Parser::new(language)
  assert_eq(
    parser.parse_string("await(await(await))").root_node().to_sexp(),
    "(document (expression (primary (call (primary (identifier)) (arguments (expression (await_expression (expression (primary (parenthesized (expression (primary (identifier)))))))))))))",
  )
}

///|
test "missing token recovery prefers the first extracted viable token" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "missing_order",
      [
        ("document", Seq([Symbol("statement"), Symbol("word")])),
        (
          "statement",
          Seq([Symbol("word"), Choice([Literal(";"), Symbol("_semicolon")])]),
        ),
        ("word", Literal("x")),
      ],
      externals=[Symbol("_semicolon")],
    ),
  )
  let parser = @treesitter.Parser::new(
    language,
    scanner=@treesitter.ExternalScanner::new((_, _, _) => None),
  )
  assert_eq(
    parser.parse_string("x x").root_node().to_sexp(),
    "(document (statement (word) (MISSING \";\")) (word))",
  )
}
