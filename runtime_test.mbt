///|
fn arithmetic() -> @language.Language raise {
  let e : @grammar.Rule = Symbol("_expression")
  @generate.generate(
    @grammar.Grammar::new("arithmetic", [
      ("document", e),
      (
        "_expression",
        Choice([
          Symbol("number"),
          Symbol("binary"),
          Seq([Literal("("), e, Literal(")")]),
        ]),
      ),
      (
        "binary",
        Choice([
          @grammar.prec_left(
            Seq([Field("left", e), Literal("+"), Field("right", e)]),
            value=1,
          ),
          @grammar.prec_left(
            Seq([Field("left", e), Literal("*"), Field("right", e)]),
            value=2,
          ),
        ]),
      ),
      ("number", @grammar.pattern("[0-9]+")),
    ]),
  )
}

///|
test "pure runtime parses generated arithmetic tables with fields and precedence" {
  let parser = @treesitter.Parser::new(arithmetic())
  let tree = parser.parse_string("1 + 2 * 3")
  let root = tree.root_node()
  assert_eq(
    root.to_sexp(),
    "(document (binary left: (number) right: (binary left: (number) right: (number))))",
  )
  assert_false(root.has_error())
  let binary = root.named_child(0).unwrap()
  assert_eq(binary.child_by_field_name("left").unwrap().text(tree.source), "1")
  assert_eq(
    binary.child_by_field_name("right").unwrap().text(tree.source),
    "2 * 3",
  )
  assert_eq(root.start_byte(), 0)
  assert_eq(root.end_byte(), 9)
  let left = parser
    .parse_string("1 + 2 + 3")
    .root_node()
    .named_child(0)
    .unwrap()
  assert_eq(left.child_by_field_name("left").unwrap().kind(), "binary")
}

///|
test "runtime preserves Unicode byte positions across lines" {
  let language = @generate.generate(
    @grammar.Grammar::new("words", [
      ("document", Repeat(Symbol("word"))),
      ("word", @grammar.pattern("\\p{L}+")),
    ]),
  )
  let tree = @treesitter.Parser::new(language).parse_string("中文\nαβ")
  let root = tree.root_node()
  assert_eq(root.named_child_count(), 2)
  let first = root.named_child(0).unwrap()
  let second = root.named_child(1).unwrap()
  assert_eq(first.end_byte(), 6)
  assert_eq(second.start_byte(), 7)
  assert_eq(second.start_position(), { row: 1, column: 0, })
  assert_eq(second.end_position(), { row: 1, column: 4, })
  assert_eq(root.descendant_for_byte_range(7, 11).unwrap().kind(), "word")
}

///|
test "aliases, named extras and cursors survive hidden rule flattening" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "aliases",
      [
        (
          "root",
          Seq([Field("first", Symbol("_hidden")), Literal(","), Symbol("word")]),
        ),
        ("_hidden", Alias(Symbol("word"), "name", named=true)),
        ("word", @grammar.pattern("[a-z]+")),
        ("comment", @grammar.pattern("#[^\\n]*")),
      ],
      extras=[@grammar.pattern("\\s"), Symbol("comment")],
    ),
  )
  let tree = @treesitter.Parser::new(language).parse_string("a, #note\nb")
  assert_eq(tree.root_node().to_sexp(), "(root first: (name) (comment) (word))")
  let cursor = tree.walk()
  assert_true(cursor.goto_first_child())
  assert_eq(cursor.field_name(), Some("first"))
  assert_eq(cursor.node().kind(), "name")
  assert_true(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), ",")
  let copy = cursor.copy()
  assert_true(cursor.goto_next_sibling())
  assert_true(cursor.node().is_extra())
  assert_eq(copy.node().kind(), ",")
  assert_true(cursor.goto_parent())
  assert_eq(cursor.depth(), 0)
  assert_true(cursor.goto_last_child())
  assert_eq(cursor.node().text(tree.source), "b")
  assert_false(cursor.goto_next_sibling())
}

///|
test "error recovery inserts missing tokens and retains skipped input" {
  let language = @generate.generate(
    @grammar.Grammar::new("paren", [
      ("root", Seq([Literal("("), Symbol("word"), Literal(")")])),
      ("word", @grammar.pattern("[a-z]+")),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  let missing = parser.parse_string("(hello").root_node()
  assert_true(missing.has_error())
  assert_true(missing.child(2).unwrap().is_missing())
  assert_eq(missing.child(2).unwrap().start_byte(), 6)
  let unexpected = parser.parse_string("(@hello)").root_node()
  assert_true(unexpected.has_error())
  assert_eq(unexpected.to_sexp(), "(root (ERROR (UNEXPECTED '@')) (word))")
}

///|
test "GLR selects the derivation with higher dynamic precedence" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "dynamic",
      [
        ("root", Choice([Symbol("a"), Symbol("b")])),
        ("a", PrecDynamic(1, Literal("x"))),
        ("b", PrecDynamic(2, Literal("x"))),
      ],
      conflicts=[["a", "b"]],
    ),
  )
  let tree = @treesitter.Parser::new(language).parse_string("x")
  assert_eq(tree.root_node().to_sexp(), "(root (b))")
}

///|
test "cancellation and resource limits fail explicitly" {
  let parser = @treesitter.Parser::new(arithmetic())
  try parser.parse(b"1", cancelled=() => true) catch {
    Cancelled => ()
    e => fail("unexpected error: \{@debug.Repr(e)}")
  } noraise {
    _ => fail("ignored cancellation")
  }
  try parser.parse(b"1 + 2", max_steps=1) catch {
    ParseLimit(_) => ()
    e => fail("unexpected error: \{@debug.Repr(e)}")
  } noraise {
    _ => fail("ignored work limit")
  }
}

///|
test "word extraction prevents contextual keywords matching identifier prefixes" {
  let grammar = @grammar.Grammar::new(
    "keywords",
    [
      ("root", Seq([Literal("if"), Symbol("identifier")])),
      ("identifier", @grammar.pattern("[a-z]+")),
    ],
    word="identifier",
  )
  let parser = @treesitter.Parser::new(@generate.generate(grammar))
  assert_false(parser.parse_string("if name").root_node().has_error())
  assert_true(parser.parse_string("iffy").root_node().has_error())
}

///|
test "named precedence preserves operator grouping" {
  let expr : @grammar.Rule = Symbol("expression")
  let grammar = @grammar.Grammar::new(
    "named",
    [
      ("root", expr),
      (
        "expression",
        Choice([Symbol("sum"), Symbol("product"), Symbol("number")]),
      ),
      ("sum", PrecLeft(Name("sum"), Seq([expr, Literal("+"), expr]))),
      ("product", PrecLeft(Name("product"), Seq([expr, Literal("*"), expr]))),
      ("number", @grammar.pattern("[0-9]+")),
    ],
    precedences=[[Literal("product"), Literal("sum")]],
  )
  let parser = @treesitter.Parser::new(@generate.generate(grammar))
  assert_eq(
    parser.parse_string("1+2*3").root_node().to_sexp(),
    "(root (expression (sum (expression (number)) (expression (product (expression (number)) (expression (number)))))))",
  )
}

///|
test "dynamic precedence selects maximum magnitude inside each production" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "dynamic_metadata",
      [
        ("document", Choice([Symbol("a"), Symbol("b")])),
        (
          "a",
          Seq([
            PrecDynamic(1, Literal("x")),
            PrecDynamic(1, Literal("y")),
            PrecDynamic(1, Literal("z")),
          ]),
        ),
        ("b", PrecDynamic(2, Seq([Literal("x"), Literal("y"), Literal("z")]))),
      ],
      conflicts=[["a", "b"]],
    ),
  )
  assert_eq(
    @treesitter.Parser::new(language).parse_string("xyz").root_node().to_sexp(),
    "(document (b))",
  )
}

///|
test "separator-only extras remain invisible" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "anonymous_extras",
      [
        ("document", Repeat(Symbol("word"))),
        ("word", @grammar.pattern("[a-z]+")),
      ],
      extras=[Literal(";"), @grammar.pattern("\\s")],
    ),
  )
  let root = @treesitter.Parser::new(language).parse_string("a ; b").root_node()
  assert_eq(root.children().map(n => n.kind()), ["word", "word"])
}

///|
test "static precedence ends at a non-final annotated region" {
  let language = @generate.generate(
    @grammar.Grammar::new("region", [
      ("document", Choice([Symbol("a"), Seq([Symbol("b"), Literal("y")])])),
      ("a", Seq([Prec(Integer(2), Literal("x")), Literal("y")])),
      ("b", Prec(Integer(1), Seq([Literal("x")]))),
    ]),
  )
  assert_eq(
    @treesitter.Parser::new(language).parse_string("xy").root_node().to_sexp(),
    "(document (b))",
  )
}
