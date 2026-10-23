///|
// Expected coordinates are frozen from ts_point_edit in the pinned C runtime.
test "point edits preserve prefixes and shift multiline suffixes" {
  let edit : @treesitter.InputEdit = {
    start_byte: 2,
    old_end_byte: 8,
    new_end_byte: 4,
    start_point: { row: 0, column: 2, },
    old_end_point: { row: 2, column: 1, },
    new_end_point: { row: 1, column: 1, },
  }
  let cases : Array[(Int32, @treesitter.Point, Int32, @treesitter.Point)] = [
    (1, { row: 0, column: 1, }, 1, { row: 0, column: 1, }),
    (2, { row: 0, column: 2, }, 2, { row: 0, column: 2, }),
    (5, { row: 1, column: 2, }, 4, { row: 1, column: 1, }),
    (8, { row: 2, column: 1, }, 4, { row: 1, column: 1, }),
    (11, { row: 2, column: 4, }, 7, { row: 1, column: 4, }),
    (15, { row: 3, column: 2, }, 11, { row: 2, column: 2, }),
  ]
  for (byte, point, expected_byte, expected_point) in cases {
    assert_eq(point.edited(byte, edit), (expected_point, expected_byte))
  }
}

///|
// Ranges collapse covered endpoints at the edit start, unlike standalone points.
test "range edits collapse replaced endpoints and include boundary insertions" {
  let edit : @treesitter.InputEdit = {
    start_byte: 2,
    old_end_byte: 5,
    new_end_byte: 3,
    start_point: { row: 0, column: 2, },
    old_end_point: { row: 0, column: 5, },
    new_end_point: { row: 0, column: 3, },
  }
  for
    (start, end, expected_start, expected_end) in [
      (0, 1, 0, 1),
      (0, 2, 0, 2),
      (0, 4, 0, 2),
      (3, 4, 2, 2),
      (3, 8, 2, 6),
      (5, 8, 3, 6),
      (2, 2, 2, 2),
    ] {
    let range : @treesitter.Range = {
      start_byte: start,
      end_byte: end,
      start_point: { row: 0, column: start, },
      end_point: { row: 0, column: end, },
    }
    let result = range.edited(edit)
    assert_eq(
      (result.start_byte, result.end_byte),
      (expected_start, expected_end),
    )
    assert_eq(result.start_point, { row: 0, column: expected_start, })
    assert_eq(result.end_point, { row: 0, column: expected_end, })
  }
  let insertion = {
    ..edit,
    old_end_byte: 2,
    old_end_point: edit.start_point,
    new_end_byte: 4,
    new_end_point: { row: 1, column: 1, },
  }
  let prefix : @treesitter.Range = {
    start_byte: 0,
    end_byte: 2,
    start_point: { row: 0, column: 0, },
    end_point: { row: 0, column: 2, },
  }
  let result = prefix.edited(insertion)
  assert_eq(result.end_byte, 4)
  assert_eq(result.end_point, { row: 1, column: 1, })
  let unbounded : @treesitter.Range = {
    ..prefix,
    end_byte: 2147483647,
    end_point: { row: 2147483647, column: 2147483647, },
  }
  assert_eq(unbounded.edited(insertion), unbounded)
}

///|
test "location edits reject invalid coordinates and overflow" {
  let edit : @treesitter.InputEdit = {
    start_byte: 0,
    old_end_byte: 0,
    new_end_byte: 1,
    start_point: { row: 0, column: 0, },
    old_end_point: { row: 0, column: 0, },
    new_end_point: { row: 0, column: 1, },
  }
  for
    (point, byte, edit) in [
      (@treesitter.Point::{ row: 0, column: 0, }, -1, edit),
      ({ row: 0, column: -1, }, 0, edit),
      ({ row: 0, column: 2147483647, }, 2147483647, edit),
      (
        { row: 0, column: 0, },
        0,
        { ..edit, new_end_point: { row: 1, column: -1, }, },
      ),
    ] {
    try point.edited(byte, edit) catch {
      InvalidEdit(_) => ()
    } noraise {
      _ => fail("accepted invalid location edit")
    }
  }
}

///|
test "included ranges use the standalone range edit rules" {
  let language = @generate.generate(
    @grammar.Grammar::new("number_range", [("root", @grammar.pattern("[0-9]+"))]),
  )
  let range : @treesitter.Range = {
    start_byte: 0,
    end_byte: 2,
    start_point: { row: 0, column: 0, },
    end_point: { row: 0, column: 2, },
  }
  let parser = @treesitter.Parser::new(language)
  let tree = parser.parse(b"1 abc", included_ranges=[range])
  tree.edit({
    start_byte: 1,
    old_end_byte: 4,
    new_end_byte: 2,
    start_point: { row: 0, column: 1, },
    old_end_point: { row: 0, column: 4, },
    new_end_point: { row: 0, column: 2, },
  })
  assert_eq(tree.included_ranges(), [
    { ..range, end_byte: 1, end_point: { row: 0, column: 1, }, },
  ])
  let tree = parser.parse(b"1 abc", included_ranges=[range])
  tree.edit({
    start_byte: 2,
    old_end_byte: 2,
    new_end_byte: 4,
    start_point: { row: 0, column: 2, },
    old_end_point: { row: 0, column: 2, },
    new_end_point: { row: 1, column: 1, },
  })
  assert_eq(tree.included_ranges(), [
    { ..range, end_byte: 4, end_point: { row: 1, column: 1, }, },
  ])
}
