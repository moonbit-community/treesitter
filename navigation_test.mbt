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
