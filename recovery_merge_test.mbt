///|
// Frozen C trees: recovering across another damaged statement extends the
// preceding ERROR. An intervening comment prevents that stack pop/merge.
test "stack recovery extends adjacent errors without swallowing leading extras" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "adjacent_errors",
      [
        ("document", Repeat(Symbol("statement"))),
        ("statement", Seq([Literal("a"), Symbol("number"), Literal(";")])),
        ("number", @grammar.pattern("[0-9]+")),
        ("comment", @grammar.pattern("//[^\n]*")),
      ],
      extras=[@grammar.pattern("\\s"), Symbol("comment")],
    ),
  )
  let parser = @treesitter.Parser::new(language)
  for
    (input, expected) in [
      (
        "1 a 2 a 3;", "(document (ERROR (number) (number)) (statement (number)))",
      ),
      (
        "1 a 2 @ a 3;", "(document (ERROR (number) (number) (UNEXPECTED '@')) (statement (number)))",
      ),
      (
        "1 a 2 a 3 a 4;", "(document (ERROR (number) (number) (number)) (statement (number)))",
      ),
      (
        "1 //comment\na 2 a 3;", "(document (ERROR (number)) (comment) (statement (number) (MISSING \";\")) (statement (number)))",
      ),
      (
        "//comment\na 2 a 3;", "(document (comment) (statement (number) (MISSING \";\")) (statement (number)))",
      ),
    ] {
    let actual = parser.parse_string(input).root_node().to_sexp()
    assert_eq(actual, expected, msg="\{input}: \{actual}")
  }
}

///|
test "recovery does not reduce EOF-only roots in the middle of input" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "recovery_eof",
      [
        ("document", Repeat(Choice([Symbol("number"), Symbol("bracket")]))),
        ("bracket", Seq([Literal("["), Symbol("number"), Literal("]")])),
        ("number", @grammar.pattern("[0-9]+")),
      ],
      extras=[@grammar.pattern("\\s")],
    ),
  )
  let parser = @treesitter.Parser::new(language)
  assert_eq(
    parser.parse_string("]1]2").root_node().to_sexp(),
    "(document (ERROR) (number) (ERROR) (number))",
  )
}
