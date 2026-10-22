///|
test "anonymous regexes compete in grammar extraction order" {
  let language = @generate.generate(
    @grammar.Grammar::new("directives", [
      ("document", Choice([Symbol("include"), Symbol("generic")])),
      (
        "include",
        Alias(@grammar.pattern("#[ \\t]*include"), "#include", named=false),
      ),
      ("generic", @grammar.pattern("#[ \\t]*[a-z]+")),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  inspect(
    parser.parse_string("#include").root_node().to_sexp(),
    content="(document (include))",
  )
  inspect(
    parser.parse_string("#other").root_node().to_sexp(),
    content="(document (generic))",
  )
}

///|
test "immediate tokens restart after named extras" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "immediate_after_comment",
      [
        ("document", Seq([Literal("x"), ImmediateToken(Literal("\n"))])),
        (
          "comment",
          Token(Seq([Literal("/*"), @grammar.pattern("[^*]*"), Literal("*/")])),
        ),
      ],
      extras=[@grammar.pattern("[ \\t\\n]"), Symbol("comment")],
    ),
  )
  let parser = @treesitter.Parser::new(language)
  for source in ["x/*a*/\n", "x /*a\nb*/\n"] {
    let tree = parser.parse_string(source)
    assert_false(tree.root_node().has_error())
    inspect(tree.root_node().to_sexp(), content="(document (comment))")
  }
  assert_true(parser.parse_string("x \n").root_node().has_error())
}
