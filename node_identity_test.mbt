///|
// Identity relationships are frozen from ts_node_eq in the pinned C runtime.
test "node identity belongs to a tree and survives location views" {
  let parser = @treesitter.Parser::new(arithmetic())
  let tree = parser.parse_string("1 + 2")
  let root = tree.root_node()
  assert_true(root == tree.root_node())
  assert_true(root == tree.walk().node())
  let shifted = tree.root_node_with_offset(4, { row: 2, column: 3, })
  assert_true(root == shifted)
  assert_true(root.child(0).unwrap() == shifted.child(0).unwrap())
  assert_true(root != root.child(0).unwrap())

  let copied = tree.copy()
  assert_eq(root.id(), copied.root_node().id())
  assert_true(root != copied.root_node())
  assert_true(root.child(0).unwrap() != copied.root_node().child(0).unwrap())
  let reparsed = parser.parse(tree.source, old_tree=tree)
  assert_eq(reparsed.reused_subtrees, 1)
  assert_eq(root.id(), reparsed.root_node().id())
  assert_true(root != reparsed.root_node())

  let unrelated = @treesitter.Parser::new(arithmetic()).parse_string("1 + 2")
  assert_eq(root.id(), unrelated.root_node().id())
  assert_true(root != unrelated.root_node())
  let edit : @treesitter.InputEdit = {
    start_byte: 0,
    old_end_byte: 0,
    new_end_byte: 1,
    start_point: { row: 0, column: 0, },
    old_end_point: { row: 0, column: 0, },
    new_end_point: { row: 0, column: 1, },
  }
  assert_true(root == root.edited(edit))
  tree.edit(edit)
  assert_true(root == tree.root_node())
  assert_true(root != copied.root_node())
}

///|
test "cursor and descendant navigation retain node ownership" {
  let tree = @treesitter.Parser::new(arithmetic()).parse_string("1 + 2 * 3")
  let root = tree.root_node()
  let cursor = tree.walk()
  for index in 0..<root.descendant_count() {
    assert_true(cursor.goto_descendant(index))
    let node = cursor.node()
    assert_true(node == tree.cursor_at(node).unwrap().node())
    assert_true(node == node.walk().node())
    if tree.parent(node) is Some(parent) {
      assert_true(parent.child_with_descendant(node).unwrap() == node)
    }
  }
}
