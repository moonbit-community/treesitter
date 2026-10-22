///|
// Frozen C behavior: synthetic lookaheads used to finish nonterminal extras
// must not make context-only tokens eligible for recovery lexing.
test "nonterminal extras do not admit greedy tokens into recovery lexing" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "extra_recovery",
      [
        ("document", Repeat(Choice([Symbol("statement"), Symbol("macro")]))),
        ("statement", Seq([Symbol("word"), Literal(";")])),
        (
          "macro",
          Seq([Literal("$("), Symbol("separator"), Literal("+"), Literal(")")]),
        ),
        ("word", @grammar.pattern("[a-z]+")),
        (
          "comment",
          Seq([Literal("/*"), @grammar.pattern("[^*]+"), Literal("*/")]),
        ),
        ("separator", @grammar.pattern("[^+*?]+")),
      ],
      extras=[@grammar.pattern("\\s+"), Symbol("comment")],
    ),
  )
  assert_false(
    language.recovery_tokens.contains(language.symbol_id("separator").unwrap()),
  )
  let parser = @treesitter.Parser::new(language)
  assert_eq(
    parser.parse_string("a @;").root_node().to_sexp(),
    "(document (statement (word) (ERROR (UNEXPECTED '@'))))",
  )
  assert_false(parser.parse_string("a /* comment */ ;").root_node().has_error())
  assert_false(parser.parse_string("$(anything +)").root_node().has_error())
}
