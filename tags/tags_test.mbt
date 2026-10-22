///|
test "tags distinguish definitions and references with source ranges" {
  let language = @generate.generate(
    @grammar.Grammar::new("bindings", [
      ("document", Repeat(Symbol("binding"))),
      (
        "binding",
        Seq([
          Field("name", Symbol("identifier")),
          Literal("="),
          Field("value", Symbol("identifier")),
          Literal(";"),
        ]),
      ),
      ("identifier", @grammar.pattern("[a-z]+")),
    ]),
  )
  let tree = @ts.Parser::new(language).parse_string("a=b; c=d;")
  let config = @tags.Configuration::new(
    language, "(binding name: (identifier) @name) @definition.variable\n(binding value: (identifier) @name @reference.variable)",
  )
  let tags = config.generate(tree)
  assert_eq(tags.length(), 4)
  assert_eq(tags.filter(t => t.is_definition).map(t => t.name), ["a", "c"])
  assert_eq(tags.filter(t => !t.is_definition).map(t => t.name), ["b", "d"])
  assert_eq(tags[0].syntax_type, "variable")
  assert_eq(tags[0].name_range.start_byte, 0)
  assert_eq(tags[0].range.end_byte, 4)
}

///|
test "documentation groups strip prefixes and select adjacent comments" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "documented",
      [
        ("document", Repeat(Symbol("declaration"))),
        (
          "declaration",
          Seq([Literal("let"), Symbol("identifier"), Literal(";")]),
        ),
        ("identifier", @grammar.pattern("[a-z]+")),
        ("comment", @grammar.pattern("//[^\\n]*")),
      ],
      extras=[@grammar.pattern("\\s"), Symbol("comment")],
    ),
  )
  let tree = @ts.Parser::new(language).parse_string(
    "// unrelated\n\n// first\n// second\nlet x;",
  )
  let config = @tags.Configuration::new(
    language,
    (
      #|((comment)* @doc . (declaration (identifier) @name) @definition.variable
      #|  (#select-adjacent! @doc @definition.variable)
      #|  (#strip! @doc "^//\\s*"))
    ),
  )
  let tags = config.generate(tree)
  assert_eq(tags.length(), 1)
  assert_eq(tags[0].docs, Some("first\nsecond"))
}
