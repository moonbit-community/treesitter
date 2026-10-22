///|
test "included ranges skip host text and retain absolute UTF8 locations" {
  let parser = @treesitter.Parser::new(arithmetic())
  let source = b"host\n1 +\nignored\n2\nend"
  let ranges : Array[@treesitter.Range] = [
    {
      start_byte: 5,
      end_byte: 8,
      start_point: { row: 1, column: 0, },
      end_point: { row: 1, column: 3, },
    },
    {
      start_byte: 17,
      end_byte: 18,
      start_point: { row: 3, column: 0, },
      end_point: { row: 3, column: 1, },
    },
  ]
  let tree = parser.parse(source, included_ranges=ranges)
  assert_false(tree.root_node().has_error())
  assert_eq(tree.root_node().start_byte(), 5)
  assert_eq(tree.root_node().end_byte(), 18)
  let right = tree
    .root_node()
    .named_child(0)
    .unwrap()
    .child_by_field_name("right")
    .unwrap()
  assert_eq(right.start_position(), { row: 3, column: 0, })
  assert_eq(right.text(source), "2")
  assert_eq(tree.included_ranges(), ranges)
  let full = parser.parse(source, old_tree=tree)
  assert_eq(full.reused_subtrees, 0)
}

///|
test "included range validation rejects overlapping ranges and wrong points" {
  let parser = @treesitter.Parser::new(arithmetic())
  let bad : @treesitter.Range = {
    start_byte: 0,
    end_byte: 1,
    start_point: { row: 1, column: 0, },
    end_point: { row: 0, column: 1, },
  }
  try parser.parse(b"1", included_ranges=[bad]) catch {
    InvalidRanges(_) => ()
    _ => fail("wrong range error")
  } noraise {
    _ => fail("accepted inconsistent coordinates")
  }
  let range : @treesitter.Range = {
    ..bad,
    start_point: { row: 0, column: 0, },
  }
  try parser.parse(b"1", included_ranges=[range, range]) catch {
    InvalidRanges(_) => ()
    _ => fail("wrong overlap error")
  } noraise {
    _ => fail("accepted overlap")
  }
}

///|
test "one lexical token may cross included ranges" {
  let language = @generate.generate(
    @grammar.Grammar::new("cross", [
      ("root", Symbol("word")),
      ("word", @grammar.pattern("[a-z]+")),
    ]),
  )
  let ranges : Array[@treesitter.Range] = [
    {
      start_byte: 0,
      end_byte: 1,
      start_point: { row: 0, column: 0, },
      end_point: { row: 0, column: 1, },
    },
    {
      start_byte: 3,
      end_byte: 4,
      start_point: { row: 0, column: 3, },
      end_point: { row: 0, column: 4, },
    },
  ]
  let tree = @treesitter.Parser::new(language).parse(
    b"a<>b",
    included_ranges=ranges,
  )
  assert_false(tree.root_node().has_error())
  assert_eq(tree.root_node().named_child_count(), 1)
  assert_eq(tree.root_node().named_child(0).unwrap().end_byte(), 4)
}
