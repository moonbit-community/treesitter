///|
test "supertype queries follow actual hidden reductions" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "categories",
      [
        (
          "document",
          Seq([Symbol("identifier"), Literal(":"), Symbol("expression")]),
        ),
        ("expression", Choice([Symbol("primary"), Symbol("number")])),
        ("primary", Symbol("identifier")),
        ("identifier", @grammar.pattern("[a-z]+")),
        ("number", @grammar.pattern("[0-9]+")),
      ],
      supertypes=["expression", "primary"],
    ),
  )
  let tree = @ts.Parser::new(language).parse_string("name: value")
  assert_eq(tree.root_node().to_sexp(), "(document (identifier) (identifier))")
  assert_eq(tree.root_node().named_child(0).unwrap().supertypes(), [])
  assert_eq(tree.root_node().named_child(1).unwrap().supertypes(), [
    "primary", "expression",
  ])
  for
    source in [
      "(expression) @value", "(expression/identifier) @value", "(primary) @value",
    ] {
    let captures = @query.Query::new(language, source).captures(
      tree.root_node(),
      tree.source,
    )
    assert_eq(captures.map(c => c.node.text(tree.source)), ["value"])
  }
  assert_eq(
    @query.Query::new(language, "(expression/number) @n")
    .captures(tree.root_node(), tree.source)
    .length(),
    0,
  )
  let roundtrip = @language.Language::parse(Json(language).stringify())
  assert_eq(roundtrip, language)
  try @query.Query::new(language, "(identifier/number)") catch {
    InvalidQuery(_, _) => ()
    error => fail("unexpected: \{@debug.Repr(error)}")
  } noraise {
    _ => fail("accepted non-supertype path")
  }
}
