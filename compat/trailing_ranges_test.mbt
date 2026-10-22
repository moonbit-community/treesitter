///|
// Frozen from the pinned C runtime and JSON grammar. Trailing skipped input is
// part of the root extent, but is padding rather than a changed syntax node.
test "root extents and changed ranges include trailing padding" {
  let parser = @ts.Parser::new(upstream_json_language())
  let cases : Array[
    (String, String, Int32, Int32, Int32, Array[(Int32, Int32)]),
  ] = [
    ("1 2 3", "1 2  ", 4, 5, 5, [(4, 5)]),
    ("1 2 3", "1 2 ", 3, 5, 4, []),
    ("1 2 3", "1 ", 2, 5, 2, []),
    ("[1,2", "[ ", 1, 4, 2, [(0, 2)]),
  ]
  for (before, after, start, old_end, new_end, expected) in cases {
    let old = parser.parse_string(before)
    old.edit({
      start_byte: start,
      old_end_byte: old_end,
      new_end_byte: new_end,
      start_point: { row: 0, column: start, },
      old_end_point: { row: 0, column: old_end, },
      new_end_point: { row: 0, column: new_end, },
    })
    let tree = parser.parse(@utf8.encode(after), old_tree=old)
    assert_eq(tree.root_node().end_byte(), after.length(), msg=after)
    assert_eq(
      old.changed_ranges(tree).map(r => (r.start_byte, r.end_byte)),
      expected,
      msg=after,
    )
    assert_eq(
      tree.root_node().range(),
      parser.parse_string(after).root_node().range(),
    )
  }
  let tree = parser.parse_string("1  \n\n")
  assert_eq(tree.root_node().end_byte(), 5)
  assert_eq(tree.root_node().end_position(), { row: 2, column: 0, })
  assert_eq(tree.root_node().named_child(0).unwrap().end_byte(), 1)
}
