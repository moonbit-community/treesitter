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
  assert_eq(tags[0].line_range, (0, 9))
  assert_eq(tags[0].utf16_column_range, (0, 1))
}

///|
test "tag columns distinguish UTF-8 bytes from UTF-16 units on multiple lines" {
  let language = @generate.generate(
    @grammar.Grammar::new("unicode_tags", [
      ("document", Seq([Literal("😀"), Repeat(Symbol("binding"))])),
      ("binding", Seq([Symbol("identifier"), Literal(";")])),
      ("identifier", @grammar.pattern("[a-z❤😀]+")),
    ]),
  )
  let tree = @ts.Parser::new(language).parse_string("😀 a❤; b😀;\r\n\tc;")
  assert_false(tree.root_node().has_error())
  let config = @tags.Configuration::new(
    language, "(binding (identifier) @name) @definition.variable",
  )
  let tags = config.generate(tree)
  assert_eq(tags.map(t => t.name), ["a❤", "b😀", "c"])
  assert_eq(tags.map(t => t.line_range), [(0, 17), (0, 17), (20, 22)])
  assert_eq(tags.map(t => t.utf16_column_range), [(3, 5), (7, 10), (1, 2)])
  assert_eq(tags.map(t => t.name_range.start_byte), [5, 11, 20])
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

///|
test "earlier tag pattern wins competing classifications for the same name" {
  let language = @generate.generate(
    @grammar.Grammar::new("one_word", [
      ("root", Symbol("word")),
      ("word", @grammar.pattern("[a-z]+")),
    ]),
  )
  let tree = @ts.Parser::new(language).parse_string("name")
  let config = @tags.Configuration::new(
    language, "(word) @name @definition.function\n(word) @name @reference.call",
  )
  let tags = config.generate(tree)
  assert_eq(tags.length(), 1)
  assert_true(tags[0].is_definition)
  assert_eq(tags[0].syntax_type, "function")
}

///|
// JavaScript's shipped tag query captures the member name and argument list
// separately. Upstream extends the tag range to include both captures.
test "tag ranges include names outside the syntax capture" {
  let language = @generate.generate(
    @grammar.Grammar::new("member_call", [
      (
        "call",
        Seq([
          Symbol("identifier"),
          Literal("."),
          Symbol("identifier"),
          Symbol("arguments"),
        ]),
      ),
      ("identifier", @grammar.pattern("[a-z]+")),
      ("arguments", Seq([Literal("("), Literal(")")])),
    ]),
  )
  let tree = @ts.Parser::new(language).parse_string("object.method()")
  let config = @tags.Configuration::new(
    language, "((call (identifier) . (identifier) @name (arguments) @reference.call) (#consumer-directive! @name))",
  )
  let tags = config.generate(tree)
  assert_eq(tags.length(), 1)
  assert_eq(tags[0].name, "method")
  assert_eq((tags[0].range.start_byte, tags[0].range.end_byte), (7, 15))
  assert_eq(
    (tags[0].name_range.start_byte, tags[0].name_range.end_byte),
    (7, 13),
  )
  assert_eq(tags[0].range.start_point, tags[0].name_range.start_point)
}
