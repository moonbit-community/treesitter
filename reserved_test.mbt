///|
test "reserved words distinguish global and property contexts" {
  let grammar = @grammar.Grammar::new(
    "reserved",
    [
      ("document", Choice([Symbol("declaration"), Symbol("object")])),
      (
        "declaration",
        Seq([
          Literal("var"),
          Symbol("identifier"),
          Literal("="),
          Symbol("identifier"),
          Literal(";"),
        ]),
      ),
      ("object", Seq([Literal("{"), Repeat(Symbol("pair")), Literal("}")])),
      (
        "pair",
        Seq([
          Reserved("property", Symbol("identifier")),
          Literal(":"),
          Symbol("identifier"),
          Literal(";"),
        ]),
      ),
      ("identifier", @grammar.pattern("[a-z]+")),
    ],
    word="identifier",
    reserved={
      "global": [Literal("var"), Literal("if")],
      "property": [Literal("var")],
    },
  )
  let language = @generate.generate(grammar)
  assert_eq(@language.Language::parse(Json(language).stringify()), language)
  let parser = @treesitter.Parser::new(language)
  for source in ["var name = value;", "{if: value;}"] {
    assert_true(!parser.parse_string(source).root_node().has_error())
  }
  for source in ["var if = value;", "{var: value;}"] {
    assert_true(parser.parse_string(source).root_node().has_error())
  }
}

///|
test "reserved contexts propagate through reduction lookahead" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "reserved_reduction",
      [
        (
          "document",
          Seq([Symbol("prefix"), Reserved("property", Symbol("identifier"))]),
        ),
        ("prefix", Seq([Literal("("), Literal(")")])),
        ("identifier", @grammar.pattern("[a-z]+")),
      ],
      word="identifier",
      reserved={ "global": [Literal("if")], "property": [] },
    ),
  )
  let tree = @treesitter.Parser::new(language).parse_string("()if")
  assert_true(!tree.root_node().has_error())
  assert_eq(tree.root_node().to_sexp(), "(document (prefix) (identifier))")
}
