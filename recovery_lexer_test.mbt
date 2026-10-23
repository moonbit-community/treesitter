///|
// Frozen from the pinned C generator/runtime: a token valid only between
// delimiters must not swallow the rest of a malformed source during recovery.
test "recovery vocabulary excludes context content and keeps extras" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "recovery_fixture",
      [
        (
          "document",
          Repeat(Choice([Symbol("word"), Symbol("string"), Literal(";")])),
        ),
        ("word", @grammar.pattern("[a-z]+")),
        ("string", Seq([Literal("`"), Symbol("content"), Literal("`")])),
        ("content", Token(@grammar.prec(1, @grammar.pattern("[^`]+")))),
        ("comment", Token(Seq([Literal("//"), @grammar.pattern("[^\\n]*")]))),
      ],
      extras=[@grammar.pattern("\\s"), Symbol("comment")],
      word="word",
    ),
  )
  assert_false(
    language.recovery_tokens.contains(language.symbol_id("content").unwrap()),
  )
  assert_true(
    language.recovery_tokens.contains(language.symbol_id("word").unwrap()),
  )
  assert_true(
    language.recovery_tokens.contains(language.symbol_id("comment").unwrap()),
  )
  for table in [language, @language.Language::parse(Json(language).stringify())] {
    let parser = @treesitter.Parser::new(table)
    assert_eq(
      parser.parse_string("! hello //comment\nworld").root_node().to_sexp(),
      "(document (ERROR (UNEXPECTED '!')) (word) (comment) (word))",
    )
    assert_eq(
      parser.parse_string("`anything ; goes here` ; word").root_node().to_sexp(),
      "(document (string (content)) (word))",
    )
  }
}

///|
test "legacy tables retain recovery tokens and invalid recovery symbols fail" {
  let language = arithmetic()
  let value = Json(language)
  guard value is Object(object) else { fail("expected object") }
  ignore(object.remove("recovery_tokens"))
  let legacy = @language.Language::from_json(value)
  assert_eq(legacy.recovery_tokens, legacy.tokens.map(token => token.symbol))
  object["recovery_tokens"] = Json([language.start_symbol])
  try @language.Language::from_json(value) catch {
    _ => ()
  } noraise {
    _ => fail("accepted a nonterminal recovery symbol")
  }
}

///|
test "stack recovery leaves trailing comments outside the error subtree" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "trailing_fixture",
      [
        ("document", Repeat(Choice([Symbol("member"), Symbol("conditional")]))),
        (
          "member",
          Seq([Symbol("identifier"), Literal("."), Literal("end"), Literal(";")]),
        ),
        (
          "conditional",
          Seq([Literal("if"), Symbol("identifier"), Literal(";")]),
        ),
        ("identifier", @grammar.pattern("[a-z]+")),
        ("comment", @grammar.pattern("//[^\\n]*")),
      ],
      extras=[@grammar.pattern("\\s"), Symbol("comment")],
      word="identifier",
      reserved={ "global": [Literal("if")] },
    ),
  )
  let tree = @treesitter.Parser::new(language).parse_string(
    "a. //comment\nif b;",
  )
  assert_eq(
    tree.root_node().to_sexp(),
    "(document (ERROR (identifier)) (comment) (conditional (identifier)))",
  )
  let error = tree.root_node().named_child(0).unwrap()
  assert_eq((error.start_byte(), error.end_byte()), (0, 2))
}

///|
test "weighted error lexing restarts after a partial token" {
  let language = @generate.generate(
    @grammar.Grammar::new("weighted_error", [
      ("document", Repeat(Symbol("word"))),
      ("word", Token(Seq([@grammar.prec(1, Literal("a")), Literal("b")]))),
    ]),
  )
  assert_true(language.tokens.any(t => t.lexer.has_precedence()))
  let parser = @treesitter.Parser::new(language)
  // Frozen from the pinned generator and C runtime.
  for
    (source, expected) in [
      ("@ ab", "(document (ERROR (UNEXPECTED '@')) (word))"),
      ("@ aXab", "(document (ERROR (UNEXPECTED '@')) (word))"),
      ("@ a", "(document (ERROR (UNEXPECTED '@')))"),
    ] {
    assert_eq(parser.parse_string(source).root_node().to_sexp(), expected)
  }
  let mut checks = 0
  assert_true(
    try {
      ignore(
        parser.parse(b"@ aXab", cancelled=() => {
          checks += 1
          checks > 4
        }),
      )
      false
    } catch {
      Cancelled => true
      _ => false
    },
  )
  assert_true(parser.has_pending_parse())
  assert_eq(
    parser.resume_parse().root_node().to_sexp(),
    "(document (ERROR (UNEXPECTED '@')) (word))",
  )
}
