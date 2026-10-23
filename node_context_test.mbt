///|
fn context_language() -> @language.Language raise {
  @generate.generate(
    @grammar.Grammar::new("context", [
      (
        "document",
        Seq([Field("left", Symbol("word")), Field("right", Symbol("word"))]),
      ),
      ("word", @grammar.pattern("[a-z]+")),
    ]),
  )
}

///|
fn context_locations(node : @treesitter.Node) -> String {
  let lines = []
  let cursor = node.walk()
  for i in 0..<node.descendant_count() {
    ignore(cursor.goto_descendant(i))
    let n = cursor.node()
    let a = n.start_position()
    let b = n.end_position()
    lines.push(
      "\{n.kind()} \{n.start_byte()}..\{n.end_byte()} \{a.row}:\{a.column}..\{b.row}:\{b.column}",
    )
  }
  lines.join("\n")
}

///|
test "shifted roots and edited handles preserve multiline syntax extents" {
  // Frozen from ts_tree_root_node_with_offset and ts_node_edit in pinned C.
  let language = context_language()
  let tree = @treesitter.Parser::new(language).parse_string("  abc\n def")
  let root = tree.root_node()
  inspect(
    context_locations(root),
    content=(
      #|document 2..10 0:2..1:4
      #|word 2..5 0:2..0:5
      #|word 7..10 1:1..1:4
    ),
  )
  let shifted = tree.root_node_with_offset(11, { row: 3, column: 5, })
  inspect(
    context_locations(shifted),
    content=(
      #|document 13..21 3:7..4:4
      #|word 13..16 3:7..3:10
      #|word 18..21 4:1..4:4
    ),
  )
  let left = shifted.child_by_field_name("left").unwrap()
  assert_eq(left.range(), shifted.named_child(0).unwrap().range())
  assert_eq(
    left.range(),
    shifted
    .child_by_field_id(language.field_id("left").unwrap())
    .unwrap()
    .range(),
  )
  assert_eq(left.range(), shifted.children_by_field_name("left")[0].range())
  assert_eq(left.range(), shifted.named_children()[0].range())
  assert_eq(
    left.range(),
    shifted.descendant_for_byte_range(13, 16).unwrap().range(),
  )
  assert_eq(
    left.range(),
    shifted
    .descendant_for_point_range({ row: 3, column: 7, }, { row: 3, column: 10, })
    .unwrap()
    .range(),
  )
  assert_eq(left.range(), shifted.child_with_descendant(left).unwrap().range())
  assert_eq(left.text(b"...........  abc\n def"), "abc")
  let edit : @treesitter.InputEdit = {
    start_byte: 0,
    old_end_byte: 0,
    new_end_byte: 4,
    start_point: { row: 0, column: 0, },
    old_end_point: { row: 0, column: 0, },
    new_end_point: { row: 1, column: 1, },
  }
  inspect(
    context_locations(root.edited(edit)),
    content=(
      #|document 6..14 1:3..2:4
      #|word 6..9 1:3..1:6
      #|word 11..14 2:1..2:4
    ),
  )
  let moved = shifted.edited(edit)
  assert_eq(moved.start_byte(), 17)
  assert_eq(moved.start_position(), { row: 4, column: 7, })
  assert_eq(moved.child(0).unwrap().end_position(), { row: 4, column: 10, })
  assert_eq(moved.child(1).unwrap().end_position(), { row: 5, column: 4, })
  assert_eq(root.start_byte(), 2)
  assert_eq(tree.root_node().range(), root.range())
  assert_eq(shifted.to_sexp(), root.to_sexp())
  assert_eq(left.id(), root.child(0).unwrap().id())
  assert_false(shifted.has_changes())
}

///|
test "node views reject negative offsets and descendant coordinate overflow" {
  let tree = @treesitter.Parser::new(context_language()).parse_string(
    "abc\n def",
  )
  let cases : Array[(Int32, @treesitter.Point)] = [
    (-1, { row: 0, column: 0, }),
    (0, { row: -1, column: 0, }),
    (2147483647, { row: 0, column: 0, }),
    (0, { row: 2147483647, column: 0, }),
    // The multiline root ends on column four, but the first child also needs
    // its column shifted. Root-only end-point validation would miss this case.
    (0, { row: 0, column: 2147483646, }),
  ]
  for (byte, point) in cases {
    assert_true(
      try {
        ignore(tree.root_node_with_offset(byte, point))
        false
      } catch {
        InvalidEdit(_) => true
      },
    )
  }
  assert_eq(tree.root_node().start_position(), { row: 0, column: 0, })
  let edit : @treesitter.InputEdit = {
    start_byte: 0,
    old_end_byte: 0,
    new_end_byte: 2147483647,
    start_point: { row: 0, column: 0, },
    old_end_point: { row: 0, column: 0, },
    new_end_point: { row: 0, column: 2147483647, },
  }
  assert_true(
    try {
      ignore(tree.root_node().edited(edit))
      false
    } catch {
      InvalidEdit(_) => true
    },
  )
}
