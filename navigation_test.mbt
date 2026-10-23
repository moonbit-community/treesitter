///|
test "point navigation preorder seeking and tree-relative parents" {
  let tree = @treesitter.Parser::new(arithmetic()).parse_string("1 + 2 * 3")
  let root = tree.root_node()
  let cursor = tree.walk()
  for i in 0..<root.descendant_count() {
    assert_true(cursor.goto_descendant(i))
    assert_eq(cursor.descendant_index(), i)
    let other = tree.cursor_at(cursor.node()).unwrap()
    assert_eq(other.descendant_index(), i)
  }
  let last = cursor.node()
  assert_false(cursor.goto_descendant(root.descendant_count()))
  assert_eq(cursor.node().id(), last.id())
  let two = root
    .descendant_for_point_range({ row: 0, column: 4, }, { row: 0, column: 5, })
    .unwrap()
  assert_eq(two.text(tree.source), "2")
  assert_eq(tree.parent(two).unwrap().kind(), "binary")
  assert_eq(tree.next_sibling(two, named=true).unwrap().text(tree.source), "3")
  assert_true(tree.previous_sibling(two, named=true) is None)
  assert_true(tree.parent(root) is None)
  let other = @treesitter.Parser::new(arithmetic()).parse_string("1 + 2 * 3")
  assert_true(tree.cursor_at(other.root_node()) is None)
}

///|
test "descendant child lookup checks identity through hidden and missing nodes" {
  let tree = @treesitter.Parser::new(arithmetic()).parse_string("1 + 2 * 3")
  let root = tree.root_node()
  let cursor = tree.walk()
  for i in 1..<root.descendant_count() {
    assert_true(cursor.goto_descendant(i))
    let descendant = cursor.node()
    let mut ancestor = descendant
    while tree.parent(ancestor) is Some(parent) {
      assert_eq(
        parent.child_with_descendant(descendant).unwrap().id(),
        ancestor.id(),
      )
      ancestor = parent
    }
  }
  assert_true(root.child_with_descendant(root) is None)
  let unrelated = @treesitter.Parser::new(arithmetic()).parse_string(
    "1 + 2 * 3",
  )
  assert_true(
    root.child_with_descendant(unrelated.root_node().child(0).unwrap()) is None,
  )
  let copied = tree.copy()
  assert_eq(
    copied
    .root_node()
    .child_with_descendant(root.child(0).unwrap())
    .unwrap()
    .id(),
    root.child(0).unwrap().id(),
  )
  let language = @generate.generate(
    @grammar.Grammar::new("missing_descendant", [
      ("root", Symbol("_hidden")),
      ("_hidden", Seq([Literal("("), Symbol("word"), Literal(")")])),
      ("word", @grammar.pattern("[a-z]+")),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  let root = parser.parse_string("(hello").root_node()
  let missing = root.child(2).unwrap()
  assert_true(missing.is_missing())
  assert_eq(root.child_with_descendant(missing).unwrap().id(), missing.id())
  assert_true(missing.child_with_descendant(missing) is None)
  let other = parser.parse_string("(hello").root_node().child(2).unwrap()
  assert_eq(other.range(), missing.range())
  assert_true(root.child_with_descendant(other) is None)
}
