///|
// Frozen C trees. The shared reduction on ':' and ';' is valid only after
// returning to the corresponding caller. Inserting 'x' before the wrong
// delimiter must not survive merely because that first reduction succeeds.
test "compacted reductions require a viable missing-token continuation" {
  let language = @generate.generate(
    @grammar.Grammar::new("missing_continuation", [
      (
        "root",
        Choice([
          Seq([Literal("a"), Symbol("outer"), Literal(":")]),
          Seq([Literal("b"), Symbol("outer"), Literal(";")]),
        ]),
      ),
      ("outer", Symbol("inner")),
      ("inner", Literal("x")),
    ]),
  )
  let colon = language.symbol_id(":", named=false).unwrap()
  let semicolon = language.symbol_id(";", named=false).unwrap()
  assert_true(
    language.states.any(state => {
      state.actions.get(colon) is Some([Reduce(_)]) &&
      state.actions.get(colon) == state.actions.get(semicolon)
    }),
  )
  let parser = @treesitter.Parser::new(language)
  for
    (source, expected) in [
      ("a;", "(ERROR)"),
      ("a:", "(root (outer (MISSING inner)))"),
      ("b;", "(root (outer (MISSING inner)))"),
      ("ax:", "(root (outer (inner)))"),
      ("bx;", "(root (outer (inner)))"),
    ] {
    assert_eq(parser.parse_string(source).root_node().to_sexp(), expected)
  }
}

///|
test "state compaction preserves LR1 reduce-reduce distinctions" {
  let language = @generate.generate(
    @grammar.Grammar::new("lr1", [
      (
        "root",
        Choice([
          Seq([Literal("a"), Symbol("first"), Literal("d")]),
          Seq([Literal("b"), Symbol("first"), Literal("e")]),
          Seq([Literal("a"), Symbol("second"), Literal("e")]),
          Seq([Literal("b"), Symbol("second"), Literal("d")]),
        ]),
      ),
      ("first", Literal("c")),
      ("second", Literal("c")),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  for
    (source, child) in [
      ("acd", "first"),
      ("bce", "first"),
      ("ace", "second"),
      ("bcd", "second"),
    ] {
    let tree = parser.parse_string(source)
    assert_false(tree.root_node().has_error())
    assert_eq(tree.root_node().to_sexp(), "(root (\{child}))")
  }
}

///|
test "state compaction keeps overlapping lexical contexts separate" {
  let language = @generate.generate(
    @grammar.Grammar::new("lexical_contexts", [
      (
        "root",
        Choice([
          Seq([Literal("a"), Symbol("item"), Symbol("word")]),
          Seq([Literal("b"), Symbol("item"), Literal("if")]),
        ]),
      ),
      ("item", Literal("x")),
      ("word", @grammar.pattern("[a-z]+")),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  assert_eq(
    parser.parse_string("axif").root_node().to_sexp(),
    "(root (item) (word))",
  )
  assert_eq(parser.parse_string("bxif").root_node().to_sexp(), "(root (item))")
}
