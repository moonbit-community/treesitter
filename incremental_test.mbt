///|
fn statements() -> @language.Language raise {
  @generate.generate(
    @grammar.Grammar::new("statements", [
      ("document", Repeat(Symbol("statement"))),
      (
        "statement",
        Seq([
          Field("name", Symbol("identifier")),
          Literal("="),
          Field("value", Symbol("number")),
          Literal(";"),
        ]),
      ),
      ("identifier", @grammar.pattern("[a-z]+")),
      ("number", @grammar.pattern("[0-9]+")),
    ]),
  )
}

///|
test "incremental parsing reuses suffix subtrees and agrees with a fresh parse" {
  let parser = @treesitter.Parser::new(statements())
  let old = parser.parse_string("a=1; b=2; c=3; d=4;")
  let original = old.copy()
  let unchanged_id = old.root_node().named_child(2).unwrap().id()
  old.edit({
    start_byte: 2,
    old_end_byte: 3,
    new_end_byte: 5,
    start_point: { row: 0, column: 2, },
    old_end_point: { row: 0, column: 3, },
    new_end_point: { row: 0, column: 5, },
  })
  assert_true(old.root_node().has_changes())
  assert_false(original.root_node().has_changes())
  let source = b"a=100; b=2; c=3; d=4;"
  let incremental = parser.parse(source, old_tree=old)
  let fresh = parser.parse(source)
  assert_eq(incremental.root_node().to_sexp(), fresh.root_node().to_sexp())
  assert_eq(incremental.root_node().range(), fresh.root_node().range())
  assert_true(incremental.reused_subtrees > 0)
  assert_true(incremental.parse_steps < fresh.parse_steps)
  assert_eq(incremental.root_node().named_child(2).unwrap().id(), unchanged_id)
  for i in 0..<fresh.root_node().named_child_count() {
    assert_eq(
      incremental.root_node().named_child(i).unwrap().range(),
      fresh.root_node().named_child(i).unwrap().range(),
    )
  }
  assert_true(old.changed_ranges(incremental).is_empty())
}

///|
test "successive edits preserve byte and point positions in reused nodes" {
  let parser = @treesitter.Parser::new(statements())
  let mut tree = parser.parse_string("a=1;\nb=2;\nc=3;")
  tree.edit({
    start_byte: 2,
    old_end_byte: 3,
    new_end_byte: 5,
    start_point: { row: 0, column: 2, },
    old_end_point: { row: 0, column: 3, },
    new_end_point: { row: 1, column: 2, },
  })
  let source = b"a=\n10;\nb=2;\nc=3;"
  tree = parser.parse(source, old_tree=tree)
  let fresh = parser.parse(source)
  assert_eq(tree.root_node().to_sexp(), fresh.root_node().to_sexp())
  assert_eq(
    tree.root_node().named_child(2).unwrap().range(),
    fresh.root_node().named_child(2).unwrap().range(),
  )
  tree.edit({
    start_byte: 4,
    old_end_byte: 5,
    new_end_byte: 6,
    start_point: { row: 1, column: 1, },
    old_end_point: { row: 1, column: 2, },
    new_end_point: { row: 1, column: 3, },
  })
  let second = parser.parse(b"a=\n100;\nb=2;\nc=3;", old_tree=tree)
  let fresh = parser.parse(b"a=\n100;\nb=2;\nc=3;")
  assert_eq(second.root_node().to_sexp(), fresh.root_node().to_sexp())
  assert_eq(
    second.root_node().named_child(2).unwrap().range(),
    fresh.root_node().named_child(2).unwrap().range(),
  )
  assert_true(second.reused_subtrees > 0)
}

///|
test "reuse checks source content and language identity" {
  let language = statements()
  let parser = @treesitter.Parser::new(language)
  let old = parser.parse(b"a=1; b=2;")
  let same = parser.parse(b"a=1; b=2;", old_tree=old)
  assert_eq(same.parse_steps, 0)
  assert_eq(same.reused_subtrees, 1)
  let changed_without_edit = parser.parse(b"a=123; b=2;", old_tree=old)
  assert_eq(changed_without_edit.reused_subtrees, 0)
  let other = @treesitter.Parser::new(statements()).parse(
    b"a=1; b=2;",
    old_tree=old,
  )
  assert_eq(other.reused_subtrees, 0)
}
