///|
test "public aliases and grammar symbols preserve distinct identities" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "symbol_api",
      [
        (
          "document",
          Seq([
            Symbol("word"),
            Alias(Symbol("word"), "name", named=true),
            Alias(Symbol("word"), "name", named=false),
            Symbol("_category"),
          ]),
        ),
        ("_category", Choice([Symbol("_primary"), Symbol("number")])),
        ("_primary", Symbol("word")),
        ("word", @grammar.pattern("[a-z]+")),
        ("number", @grammar.pattern("[0-9]+")),
      ],
      supertypes=["_category", "_primary"],
    ),
  )
  for table in [language, @language.Language::parse(Json(language).stringify())] {
    let tree = @treesitter.Parser::new(table).parse_string("aa bb cc dd")
    // Names and identity relationships frozen from the pinned C runtime.
    let children = tree.root_node().children()
    assert_eq(children.map(n => n.kind()), ["word", "name", "name", "word"])
    assert_eq(children.map(n => n.grammar_kind()), [
      "word", "word", "word", "word",
    ])
    assert_eq(children.map(n => n.symbol() == n.grammar_symbol()), [
      true, false, false, true,
    ])
    assert_eq(children.map(n => n.is_named()), [true, true, false, true])
    for node in children {
      assert_eq(table.symbol_name(node.symbol()), Some(node.kind()))
      assert_eq(
        table.symbol_id(node.kind(), named=node.is_named()),
        Some(node.symbol()),
      )
      assert_eq(node.grammar_symbol(), table.symbol_id("word").unwrap())
    }
    let category = table.symbol_id("_category").unwrap()
    let primary = table.symbol_id("_primary").unwrap()
    assert_eq(table.symbol_type(category), Some(Supertype))
    let subtype_names = table
      .subtypes(category)
      .map(id => table.symbol_name(id).unwrap())
    assert_eq(subtype_names, ["_primary", "number"])
    assert_eq(table.subtypes(primary), [table.symbol_id("word").unwrap()])
    assert_eq(table.subtypes(table.symbol_id("word").unwrap()), [])
    assert_eq(table.subtypes(-1), [])
    assert_eq(table.symbol_type(children[1].symbol()), Some(Regular))
    assert_eq(table.symbol_type(children[2].symbol()), Some(Anonymous))
    assert_eq(table.symbol_id("ERROR"), Some(-1))
    assert_eq(table.symbol_name(-1), Some("ERROR"))
    assert_eq(table.symbol_type(-1), Some(Regular))
    assert_eq(table.symbol_name(table.symbol_count()), None)
    assert_eq(table.symbol_type(-2), None)
    assert_eq(table.symbol_id("absent"), None)
    assert_eq(table.symbol_count(), table.symbols.length() + 2)
  }
}

///|
test "default aliases remain the grammar identity and hidden names are auxiliary" {
  let language = @generate.generate(
    @grammar.Grammar::new("default_identity", [
      (
        "document",
        Seq([Alias(Symbol("word"), "name", named=true), Symbol("_hidden")]),
      ),
      ("word", @grammar.pattern("[a-z]+")),
      ("_hidden", Literal(";")),
    ]),
  )
  let root = @treesitter.Parser::new(language).parse_string("aa;").root_node()
  let name = root.named_child(0).unwrap()
  assert_eq(name.kind(), "name")
  assert_eq(name.grammar_kind(), "name")
  assert_eq(name.symbol(), name.grammar_symbol())
  assert_eq(language.symbol_id("word"), None)
  assert_eq(language.symbol_id("_hidden"), None)
  let hidden = language.symbols.search_by(s => s.name == "_hidden").unwrap()
  assert_eq(language.symbol_type(hidden), Some(Auxiliary))
  assert_eq(language.symbol_name(hidden), Some("_hidden"))
}
