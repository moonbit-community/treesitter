///|
test "outer inline aliases and fields override the inlined rule metadata" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "inline_metadata",
      [
        (
          "document",
          Field("outer", Alias(Symbol("_inline"), "outer_name", named=true)),
        ),
        (
          "_inline",
          Seq([
            Field("inner", Alias(Symbol("word"), "inner_name", named=true)),
            Symbol("word"),
          ]),
        ),
        ("word", @grammar.pattern("[a-z]+")),
      ],
      inline_rules=["_inline"],
    ),
  )
  let root = @treesitter.Parser::new(language)
    .parse_string("one two")
    .root_node()
  assert_eq(
    root.to_sexp(fields=true),
    "(document outer: (outer_name) outer: (outer_name))",
  )
}

///|
test "inlined supertypes retain inline behavior without supertype metadata" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "inline_supertype",
      [
        ("document", Symbol("_type")),
        ("_type", Choice([Symbol("name"), Symbol("number")])),
        ("name", @grammar.pattern("[a-z]+")),
        ("number", @grammar.pattern("[0-9]+")),
      ],
      inline_rules=["_type"],
      supertypes=["_type"],
    ),
  )
  assert_eq(language.supertypes.length(), 0)
  assert_eq(
    @treesitter.Parser::new(language).parse_string("name").root_node().to_sexp(),
    "(document (name))",
  )
}
