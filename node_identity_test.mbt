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

///|
test "encoded no-change parses reuse syntax with a distinct tree identity" {
  let parser = @treesitter.Parser::new(arithmetic())
  let cases : Array[(Bytes, @treesitter.InputEncoding)] = [
    (b"1 + 2", Utf8),
    (b"1\x00 \x00+\x00 \x002\x00", Utf16LE),
    (b"\x001\x00 \x00+\x00 \x002", Utf16BE),
    (
      b"1 + 2",
      Custom(@treesitter.InputDecoder::new(input => (input[0].to_int(), 1))),
    ),
  ]
  for (source, encoding) in cases {
    let old = parser.parse_encoded(source, encoding)
    let new = parser.parse_encoded(source, encoding, old_tree=old)
    assert_eq(new.reused_subtrees, 1)
    assert_eq(old.root_node().id(), new.root_node().id())
    assert_true(old.root_node() != new.root_node())
    assert_true(
      old.root_node().child(0).unwrap() != new.root_node().child(0).unwrap(),
    )
    assert_true(new.root_node() == new.walk().node())
    assert_eq(old.root_node().to_sexp(), new.root_node().to_sexp())
  }
}
