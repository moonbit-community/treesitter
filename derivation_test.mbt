///|
test "GLR ties preserve grammar order through hidden reductions" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "ambiguous_statement",
      [
        (
          "document",
          Seq([
            Literal("{"),
            Choice([Symbol("statement"), Symbol("_empty")]),
            Literal("}"),
          ]),
        ),
        ("statement", Seq([Symbol("_expression"), Literal(";")])),
        ("_expression", Symbol("identifier")),
        (
          "_empty",
          Seq([
            Alias(Symbol("identifier"), "type_identifier", named=true),
            Literal(";"),
          ]),
        ),
        ("identifier", @grammar.pattern("[a-z]+")),
      ],
      conflicts=[["_expression", "_empty"]],
    ),
  )
  inspect(
    @treesitter.Parser::new(language)
    .parse_string("{foo;}")
    .root_node()
    .to_sexp(),
    content="(document (statement (identifier)))",
  )
}
