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
