///|
fn aliased_statement(
  prefix : String,
  rule : @grammar.Rule,
  name : String,
  named~ : Bool = true,
) -> @grammar.Rule {
  Seq([Literal(prefix), Alias(rule, name, named~), Literal(";")])
}

///|
test "default aliases use grammar order for ties and precede inlining" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "alias_tie",
      [
        (
          "document",
          Repeat(
            Choice([
              aliased_statement("a", Symbol("word"), "first"),
              aliased_statement("b", Symbol("word"), "second"),
            ]),
          ),
        ),
        ("word", @grammar.pattern("[x-z]+")),
      ],
      extras=[@grammar.pattern("\\s")],
    ),
  )
  assert_eq(
    @treesitter.Parser::new(language)
    .parse_string("x a y; b z;")
    .root_node()
    .to_sexp(),
    "(document (ERROR (first)) (first) (second))",
  )
  let inlined = @generate.generate(
    @grammar.Grammar::new(
      "inline_alias",
      [
        (
          "document",
          Repeat(
            Seq([Alias(Symbol("_word"), "name", named=true), Literal(";")]),
          ),
        ),
        ("_word", Symbol("word")),
        ("word", @grammar.pattern("[a-z]+")),
      ],
      extras=[@grammar.pattern("\\s")],
      inline_rules=["_word"],
    ),
  )
  assert_eq(
    @treesitter.Parser::new(inlined)
    .parse_string("foo foo;")
    .root_node()
    .to_sexp(),
    "(document (ERROR (word)) (name))",
  )
}

///|
// Expected trees and token identities frozen from the pinned C generator and
// runtime. Default aliases also apply before a successful parent reduction.
test "default aliases preserve token identities in recovery" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "default_alias",
      [
        ("document", Repeat(Symbol("statement"))),
        (
          "statement",
          Choice([
            aliased_statement("a", Symbol("number"), "first"),
            aliased_statement("b", Symbol("number"), "common"),
            aliased_statement("c", Symbol("number"), "common"),
            aliased_statement("d", @grammar.pattern("x+"), "x", named=false),
            aliased_statement("e", Symbol("box"), "wrapped"),
            aliased_statement("f", Symbol("mixed"), "renamed"),
            Seq([Literal("g"), Symbol("mixed"), Literal(";")]),
            aliased_statement("h", Symbol("comment"), "note"),
          ]),
        ),
        ("number", @grammar.pattern("[0-9]+")),
        ("box", Seq([Literal("{"), Literal("}")])),
        ("mixed", @grammar.pattern("m+")),
        ("comment", @grammar.pattern("//[^\n]*")),
      ],
      extras=[@grammar.pattern("\\s"), Symbol("comment")],
    ),
  )
  for table in [language, @language.Language::parse(Json(language).stringify())] {
    let parser = @treesitter.Parser::new(table)
    for
      (input, expected) in [
        (
          "42 a 1; b 2; c 3;", "(document (ERROR (common)) (statement (first)) (statement (common)) (statement (common)))",
        ),
        ("x a 1;", "(document (ERROR) (statement (first)))"),
        (
          "e {} @ a 1;", "(document (statement (wrapped) (ERROR (UNEXPECTED '@') (common))))",
        ),
        (
          "m f m; g m;", "(document (ERROR (mixed)) (statement (renamed)) (statement (mixed)))",
        ),
        ("// hello\na 1;", "(document (comment) (statement (first)))"),
        ("d xx;", "(document (statement))"),
      ] {
      assert_eq(
        parser.parse_string(input).root_node().to_sexp(),
        expected,
        msg=input,
      )
    }
    let error = parser
      .parse_string("x a 1;")
      .root_node()
      .named_child(0)
      .unwrap()
    let token = error.child(0).unwrap()
    assert_eq(token.kind(), "x")
    assert_false(token.is_named())
    assert_eq((token.start_byte(), token.end_byte()), (0, 1))
  }
}
