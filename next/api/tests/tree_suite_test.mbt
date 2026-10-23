// Port of tree-sitter crates/cli/src/tests/tree_test.rs.
//
// Tests whose grammar needs an external scanner that is not ported yet return
// early with a notice.

///|
/// A clone of `tree` edited with `edit` (the `{ let mut tree = tree.clone();
/// tree.edit(...); ... }` blocks of `test_tree_edit`).
fn edited_clone(tree : @api.Tree, edit : @api.InputEdit) -> @api.Tree {
  let tree = tree.clone()
  tree.edit(edit)
  tree
}

///|
async test "tree_edit" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "  abc  !==  def")
  assert_eq(
    tree.root_node().to_sexp(),
    "(program (expression_statement (binary_expression left: (identifier) right: (identifier))))",
  )

  // edit entirely within the tree's padding:
  // resize the padding of the tree and its leftmost descendants.
  {
    let tree = edited_clone(tree, {
      start_byte: 1,
      old_end_byte: 1,
      new_end_byte: 2,
      start_position: @api.Point::new(0, 1),
      old_end_position: @api.Point::new(0, 1),
      new_end_position: @api.Point::new(0, 2),
    })
    let expr = tree.root_node().child(0).unwrap().child(0).unwrap()
    let child1 = expr.child(0).unwrap()
    let child2 = expr.child(1).unwrap()
    assert_true(expr.has_changes())
    assert_eq(expr.start_byte(), 3)
    assert_eq(expr.end_byte(), 16)
    assert_true(child1.has_changes())
    assert_eq(child1.start_byte(), 3)
    assert_eq(child1.end_byte(), 6)
    assert_false(child2.has_changes())
    assert_eq(child2.start_byte(), 8)
    assert_eq(child2.end_byte(), 11)
  }

  // edit starting in the tree's padding but extending into its content:
  // shrink the content to compensate for the expanded padding.
  {
    let tree = edited_clone(tree, {
      start_byte: 1,
      old_end_byte: 4,
      new_end_byte: 5,
      start_position: @api.Point::new(0, 1),
      old_end_position: @api.Point::new(0, 5),
      new_end_position: @api.Point::new(0, 5),
    })
    let expr = tree.root_node().child(0).unwrap().child(0).unwrap()
    let child1 = expr.child(0).unwrap()
    let child2 = expr.child(1).unwrap()
    assert_true(expr.has_changes())
    assert_eq(expr.start_byte(), 5)
    assert_eq(expr.end_byte(), 16)
    assert_true(child1.has_changes())
    assert_eq(child1.start_byte(), 5)
    assert_eq(child1.end_byte(), 6)
    assert_false(child2.has_changes())
    assert_eq(child2.start_byte(), 8)
    assert_eq(child2.end_byte(), 11)
  }

  // insertion at the edge of a tree's padding:
  // expand the tree's padding.
  {
    let tree = edited_clone(tree, {
      start_byte: 2,
      old_end_byte: 2,
      new_end_byte: 4,
      start_position: @api.Point::new(0, 2),
      old_end_position: @api.Point::new(0, 2),
      new_end_position: @api.Point::new(0, 4),
    })
    let expr = tree.root_node().child(0).unwrap().child(0).unwrap()
    let child1 = expr.child(0).unwrap()
    let child2 = expr.child(1).unwrap()
    assert_true(expr.has_changes())
    assert_eq(expr.byte_range(), (4, 17))
    assert_true(child1.has_changes())
    assert_eq(child1.byte_range(), (4, 7))
    assert_false(child2.has_changes())
    assert_eq(child2.byte_range(), (9, 12))
  }

  // replacement starting at the edge of the tree's padding:
  // resize the content and not the padding.
  {
    let tree = edited_clone(tree, {
      start_byte: 2,
      old_end_byte: 2,
      new_end_byte: 4,
      start_position: @api.Point::new(0, 2),
      old_end_position: @api.Point::new(0, 2),
      new_end_position: @api.Point::new(0, 4),
    })
    let expr = tree.root_node().child(0).unwrap().child(0).unwrap()
    let child1 = expr.child(0).unwrap()
    let child2 = expr.child(1).unwrap()
    assert_true(expr.has_changes())
    assert_eq(expr.byte_range(), (4, 17))
    assert_true(child1.has_changes())
    assert_eq(child1.byte_range(), (4, 7))
    assert_false(child2.has_changes())
    assert_eq(child2.byte_range(), (9, 12))
  }

  // deletion that spans more than one child node:
  // shrink subsequent child nodes.
  {
    let tree = edited_clone(tree, {
      start_byte: 1,
      old_end_byte: 11,
      new_end_byte: 4,
      start_position: @api.Point::new(0, 1),
      old_end_position: @api.Point::new(0, 11),
      new_end_position: @api.Point::new(0, 4),
    })
    let expr = tree.root_node().child(0).unwrap().child(0).unwrap()
    let child1 = expr.child(0).unwrap()
    let child2 = expr.child(1).unwrap()
    let child3 = expr.child(2).unwrap()
    assert_true(expr.has_changes())
    assert_eq(expr.byte_range(), (4, 8))
    assert_true(child1.has_changes())
    assert_eq(child1.byte_range(), (4, 4))
    assert_true(child2.has_changes())
    assert_eq(child2.byte_range(), (4, 4))
    assert_true(child3.has_changes())
    assert_eq(child3.byte_range(), (5, 8))
  }

  // insertion at the end of the tree:
  // extend the tree's content.
  {
    let tree = edited_clone(tree, {
      start_byte: 15,
      old_end_byte: 15,
      new_end_byte: 16,
      start_position: @api.Point::new(0, 15),
      old_end_position: @api.Point::new(0, 15),
      new_end_position: @api.Point::new(0, 16),
    })
    let expr = tree.root_node().child(0).unwrap().child(0).unwrap()
    let child1 = expr.child(0).unwrap()
    let child2 = expr.child(1).unwrap()
    let child3 = expr.child(2).unwrap()
    assert_true(expr.has_changes())
    assert_eq(expr.byte_range(), (2, 16))
    assert_false(child1.has_changes())
    assert_eq(child1.byte_range(), (2, 5))
    assert_false(child2.has_changes())
    assert_eq(child2.byte_range(), (7, 10))
    assert_true(child3.has_changes())
    assert_eq(child3.byte_range(), (12, 16))
  }

  // replacement that starts within a token and extends beyond the end of the tree:
  // resize the token and empty out any subsequent child nodes.
  {
    let tree = edited_clone(tree, {
      start_byte: 3,
      old_end_byte: 90,
      new_end_byte: 4,
      start_position: @api.Point::new(0, 3),
      old_end_position: @api.Point::new(0, 90),
      new_end_position: @api.Point::new(0, 4),
    })
    let expr = tree.root_node().child(0).unwrap().child(0).unwrap()
    let child1 = expr.child(0).unwrap()
    let child2 = expr.child(1).unwrap()
    let child3 = expr.child(2).unwrap()
    assert_eq(expr.byte_range(), (2, 4))
    assert_true(expr.has_changes())
    assert_eq(child1.byte_range(), (2, 4))
    assert_true(child1.has_changes())
    assert_eq(child2.byte_range(), (4, 4))
    assert_true(child2.has_changes())
    assert_eq(child3.byte_range(), (4, 4))
    assert_true(child3.has_changes())
  }

  // replacement that starts in whitespace and extends beyond the end of the tree:
  // shift the token's start position and empty out its content.
  let tree = tree
  tree.edit({
    start_byte: 6,
    old_end_byte: 90,
    new_end_byte: 8,
    start_position: @api.Point::new(0, 6),
    old_end_position: @api.Point::new(0, 90),
    new_end_position: @api.Point::new(0, 8),
  })
  let expr = tree.root_node().child(0).unwrap().child(0).unwrap()
  let child1 = expr.child(0).unwrap()
  let child2 = expr.child(1).unwrap()
  let child3 = expr.child(2).unwrap()
  assert_eq(expr.byte_range(), (2, 8))
  assert_true(expr.has_changes())
  assert_eq(child1.byte_range(), (2, 5))
  assert_false(child1.has_changes())
  assert_eq(child2.byte_range(), (8, 8))
  assert_true(child2.has_changes())
  assert_eq(child3.byte_range(), (8, 8))
  assert_true(child3.has_changes())
}

///|
async test "tree_edit_with_included_ranges" {
  guard get_parsing_language("html") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let source = "<div><% if a %><span>a</span><% else %><span>b</span><% end %></div>"
  let ranges = [(0, 5), (15, 29), (39, 53), (62, 68)]
  parser.set_included_ranges(
    ranges.map(range => {
      let (start, end) = range
      {
        start_byte: start,
        end_byte: end,
        start_point: @api.Point::new(0, start),
        end_point: @api.Point::new(0, end),
      }
    }),
  )
  let tree = parse(parser, source)
  tree.edit({
    start_byte: 29,
    old_end_byte: 53,
    new_end_byte: 29,
    start_position: @api.Point::new(0, 29),
    old_end_position: @api.Point::new(0, 53),
    new_end_position: @api.Point::new(0, 29),
  })
  assert_eq(tree.included_ranges(), [
    {
      start_byte: 0,
      end_byte: 5,
      start_point: @api.Point::new(0, 0),
      end_point: @api.Point::new(0, 5),
    },
    {
      start_byte: 15,
      end_byte: 29,
      start_point: @api.Point::new(0, 15),
      end_point: @api.Point::new(0, 29),
    },
    {
      start_byte: 29,
      end_byte: 29,
      start_point: @api.Point::new(0, 29),
      end_point: @api.Point::new(0, 29),
    },
    {
      start_byte: 38,
      end_byte: 44,
      start_point: @api.Point::new(0, 38),
      end_point: @api.Point::new(0, 44),
    },
  ])
}

///|
async test "tree_cursor" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(
    parser, "\n                struct Stuff {\n                    a: A,\n                    b: Option<B>,\n                }\n            ",
  )
  let cursor = tree.walk()
  assert_eq(cursor.node().kind(), "source_file")
  assert_true(cursor.goto_first_child())
  assert_eq(cursor.node().kind(), "struct_item")
  assert_true(cursor.goto_first_child())
  assert_eq(cursor.node().kind(), "struct")
  assert_false(cursor.node().is_named())
  assert_true(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "type_identifier")
  assert_true(cursor.node().is_named())
  assert_true(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "field_declaration_list")
  assert_true(cursor.node().is_named())
  assert_true(cursor.goto_last_child())
  assert_eq(cursor.node().kind(), "}")
  assert_false(cursor.node().is_named())
  assert_eq(cursor.node().start_position(), { row: 4, column: 16, })
  assert_true(cursor.goto_previous_sibling())
  assert_eq(cursor.node().kind(), ",")
  assert_false(cursor.node().is_named())
  assert_eq(cursor.node().start_position(), { row: 3, column: 32, })
  assert_true(cursor.goto_previous_sibling())
  assert_eq(cursor.node().kind(), "field_declaration")
  assert_true(cursor.node().is_named())
  assert_eq(cursor.node().start_position(), { row: 3, column: 20, })
  assert_true(cursor.goto_previous_sibling())
  assert_eq(cursor.node().kind(), ",")
  assert_false(cursor.node().is_named())
  assert_eq(cursor.node().start_position(), { row: 2, column: 24, })
  assert_true(cursor.goto_previous_sibling())
  assert_eq(cursor.node().kind(), "field_declaration")
  assert_true(cursor.node().is_named())
  assert_eq(cursor.node().start_position(), { row: 2, column: 20, })
  assert_true(cursor.goto_previous_sibling())
  assert_eq(cursor.node().kind(), "{")
  assert_false(cursor.node().is_named())
  assert_eq(cursor.node().start_position(), { row: 1, column: 29, })
  let copy = tree.walk()
  copy.reset_to(cursor)
  assert_eq(copy.node().kind(), "{")
  assert_false(copy.node().is_named())
  assert_true(copy.goto_parent())
  assert_eq(copy.node().kind(), "field_declaration_list")
  assert_true(copy.node().is_named())
  assert_true(copy.goto_parent())
  assert_eq(copy.node().kind(), "struct_item")
}

///|
async test "tree_cursor_previous_sibling_with_aliases" {
  let parser = @api.Parser::new()
  guard get_test_fixture_language("aliases_in_root") is Some(language) else {
    return
  }
  parser.set_language(language)
  let text = "# comment\n# \nfoo foo"
  let tree = parse(parser, text)
  let cursor = tree.walk()
  assert_eq(cursor.node().kind(), "document")
  ignore(cursor.goto_first_child())
  assert_eq(cursor.node().kind(), "comment")
  assert_true(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "comment")
  assert_true(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "bar")
  assert_true(cursor.goto_previous_sibling())
  assert_eq(cursor.node().kind(), "comment")
  assert_true(cursor.goto_previous_sibling())
  assert_eq(cursor.node().kind(), "comment")
  assert_true(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "comment")
  assert_true(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "bar")
}

///|
async test "tree_cursor_previous_sibling" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let text = "\n    // Hi there\n    // This is fun!\n    // Another one!\n"
  let tree = parse(parser, text)
  let cursor = tree.walk()
  assert_eq(cursor.node().kind(), "source_file")
  assert_true(cursor.goto_last_child())
  assert_eq(cursor.node().kind(), "line_comment")
  assert_eq(cursor.node().utf8_text(utf8(text)), "// Another one!")
  assert_true(cursor.goto_previous_sibling())
  assert_eq(cursor.node().kind(), "line_comment")
  assert_eq(cursor.node().utf8_text(utf8(text)), "// This is fun!")
  assert_true(cursor.goto_previous_sibling())
  assert_eq(cursor.node().kind(), "line_comment")
  assert_eq(cursor.node().utf8_text(utf8(text)), "// Hi there")
  assert_false(cursor.goto_previous_sibling())
}

///|
async test "tree_cursor_fields" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "function /*1*/ bar /*2*/ () {}")
  let cursor = tree.walk()
  assert_eq(cursor.node().kind(), "program")
  ignore(cursor.goto_first_child())
  assert_eq(cursor.node().kind(), "function_declaration")
  assert_eq(cursor.field_name(), None)
  ignore(cursor.goto_first_child())
  assert_eq(cursor.node().kind(), "function")
  assert_eq(cursor.field_name(), None)
  ignore(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "comment")
  assert_eq(cursor.field_name(), None)
  ignore(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "identifier")
  assert_eq(cursor.field_name(), Some("name"))
  ignore(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "comment")
  assert_eq(cursor.field_name(), None)
  ignore(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "formal_parameters")
  assert_eq(cursor.field_name(), Some("parameters"))
}

///|
async test "tree_cursor_child_for_point" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let source = "\n    [\n        one,\n        {\n            two: tree\n        },\n        four, five, six\n    ];"[1:].to_owned()
  let tree = parse(parser, source)
  let c = tree.walk()
  assert_eq(c.node().kind(), "program")
  assert_eq(c.goto_first_child_for_point(@api.Point::new(7, 0)), None)
  assert_eq(c.goto_first_child_for_point(@api.Point::new(6, 7)), None)
  assert_eq(c.node().kind(), "program")

  // descend to expression statement
  assert_eq(c.goto_first_child_for_point(@api.Point::new(6, 5)), Some(0))
  assert_eq(c.node().kind(), "expression_statement")

  // step into ';' and back up
  assert_eq(c.goto_first_child_for_point(@api.Point::new(7, 0)), None)
  assert_eq(c.goto_first_child_for_point(@api.Point::new(6, 6)), None)
  assert_eq(c.goto_first_child_for_point(@api.Point::new(6, 5)), Some(1))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    (";", @api.Point::new(6, 5)),
  )
  assert_true(c.goto_parent())

  // descend into array
  assert_eq(c.goto_first_child_for_point(@api.Point::new(6, 4)), Some(0))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    ("array", @api.Point::new(0, 4)),
  )

  // step into '[' and back up
  assert_eq(c.goto_first_child_for_point(@api.Point::new(0, 4)), Some(0))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    ("[", @api.Point::new(0, 4)),
  )
  assert_true(c.goto_parent())

  // step into identifier 'one' and back up
  assert_eq(c.goto_first_child_for_point(@api.Point::new(1, 0)), Some(1))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    ("identifier", @api.Point::new(1, 8)),
  )
  assert_true(c.goto_parent())
  assert_eq(c.goto_first_child_for_point(@api.Point::new(1, 10)), Some(1))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    ("identifier", @api.Point::new(1, 8)),
  )
  assert_true(c.goto_parent())

  // step into first ',' and back up
  assert_eq(c.goto_first_child_for_point(@api.Point::new(1, 11)), Some(2))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    (",", @api.Point::new(1, 11)),
  )
  assert_true(c.goto_parent())

  // step into identifier 'four' and back up
  assert_eq(c.goto_first_child_for_point(@api.Point::new(5, 0)), Some(5))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    ("identifier", @api.Point::new(5, 8)),
  )
  assert_true(c.goto_parent())
  assert_eq(c.goto_first_child_for_point(@api.Point::new(5, 0)), Some(5))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    ("identifier", @api.Point::new(5, 8)),
  )
  assert_true(c.goto_parent())

  // step into ']' and back up
  assert_eq(c.goto_first_child_for_point(@api.Point::new(6, 0)), Some(10))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    ("]", @api.Point::new(6, 4)),
  )
  assert_true(c.goto_parent())
  assert_eq(c.goto_first_child_for_point(@api.Point::new(6, 0)), Some(10))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    ("]", @api.Point::new(6, 4)),
  )
  assert_true(c.goto_parent())

  // descend into object
  assert_eq(c.goto_first_child_for_point(@api.Point::new(2, 0)), Some(3))
  assert_eq(
    (c.node().kind(), c.node().start_position()),
    ("object", @api.Point::new(2, 8)),
  )
}

///|
async test "tree_node_equality" {
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "struct A {}")
  let node1 = tree.root_node()
  let node2 = tree.root_node()
  assert_eq(node1, node2)
  assert_eq(node1.child(0).unwrap(), node2.child(0).unwrap())
  assert_not_eq(node1.child(0).unwrap(), node2)
}

///|
/// `index_of` of tree_test.rs.
fn index_of(text : Array[Byte], substring : String) -> Int32 {
  byte_find(@utf8.decode_lossy(Bytes::from_array(text)), substring)
}

///|
/// `range_of` of tree_test.rs.
fn range_of(text : Array[Byte], substring : String) -> @api.Range {
  let start_byte = index_of(text, substring)
  let end_byte = start_byte + utf8(substring).length()
  {
    start_byte,
    end_byte,
    start_point: @api.Point::new(0, start_byte),
    end_point: @api.Point::new(0, end_byte),
  }
}

///|
/// `get_changed_ranges` of tree_test.rs: apply `edit`, reparse, and return
/// the changed ranges along with the new tree (which replaces `*tree`
/// upstream).
fn get_changed_ranges(
  parser : @api.Parser,
  tree : Ref[@api.Tree],
  source_code : Array[Byte],
  edit : @cli_test.Edit,
) -> Array[@api.Range] raise {
  ignore(@cli_test.perform_edit(tree.val, source_code, edit))
  let new_tree = parser
    .parse(Bytes::from_array(source_code), old_tree=tree.val)
    .unwrap()
  let result = tree.val.changed_ranges(new_tree)
  tree.val = new_tree
  result
}

///|
async test "get_changed_ranges" {
  let source_code = utf8("{a: null};\n").to_array()
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parser.parse(Bytes::from_array(source_code)).unwrap()
  assert_eq(
    tree.root_node().to_sexp(),
    "(program (expression_statement (object (pair key: (property_identifier) value: (null)))))",
  )

  // Updating one token
  {
    let tree = Ref(tree.clone())
    let source_code = source_code.copy()

    // Replace `null` with `nothing` - that token has changed syntax
    let edit = edit(index_of(source_code, "ull"), 3, "othing")
    let inverse_edit = @cli_test.invert_edit(source_code, edit)
    let ranges = get_changed_ranges(parser, tree, source_code, edit)
    assert_eq(ranges, [range_of(source_code, "nothing")])

    // Replace `nothing` with `null` - that token has changed syntax
    let ranges = get_changed_ranges(parser, tree, source_code, inverse_edit)
    assert_eq(ranges, [range_of(source_code, "null")])
  }

  // Changing only leading whitespace
  {
    let tree = Ref(tree.clone())
    let source_code = source_code.copy()

    // Insert leading newline - no changed ranges
    let edit = edit(0, 0, "\n")
    let inverse_edit = @cli_test.invert_edit(source_code, edit)
    let ranges = get_changed_ranges(parser, tree, source_code, edit)
    assert_eq(ranges, [])

    // Remove leading newline - no changed ranges
    let ranges = get_changed_ranges(parser, tree, source_code, inverse_edit)
    assert_eq(ranges, [])
  }

  // Inserting elements
  {
    let tree = Ref(tree.clone())
    let source_code = source_code.copy()

    // Insert a key-value pair before the `}` - those tokens are changed
    let edit1 = edit(index_of(source_code, "}"), 0, ", b: false")
    let inverse_edit1 = @cli_test.invert_edit(source_code, edit1)
    let ranges = get_changed_ranges(parser, tree, source_code, edit1)
    assert_eq(ranges, [range_of(source_code, ", b: false")])
    let edit2 = edit(index_of(source_code, ", b"), 0, ", c: 1")
    let inverse_edit2 = @cli_test.invert_edit(source_code, edit2)
    let ranges = get_changed_ranges(parser, tree, source_code, edit2)
    assert_eq(ranges, [range_of(source_code, ", c: 1")])

    // Remove the middle pair
    let ranges = get_changed_ranges(parser, tree, source_code, inverse_edit2)
    assert_eq(ranges, [])

    // Remove the second pair
    let ranges = get_changed_ranges(parser, tree, source_code, inverse_edit1)
    assert_eq(ranges, [])
  }

  // Wrapping elements in larger expressions
  let tree = Ref(tree)
  let source_code = source_code.copy()

  // Replace `null` with the binary expression `b === null`
  let edit1 = edit(index_of(source_code, "null"), 0, "b === ")
  let inverse_edit1 = @cli_test.invert_edit(source_code, edit1)
  let ranges = get_changed_ranges(parser, tree, source_code, edit1)
  assert_eq(ranges, [range_of(source_code, "b === null")])

  // Undo
  let ranges = get_changed_ranges(parser, tree, source_code, inverse_edit1)
  assert_eq(ranges, [range_of(source_code, "null")])
}

///|
async test "consistency_with_mid_codepoint_edit" {
  guard get_parsing_language("php_php") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let source_code = b"\n<?php\n\n<<<'\xE5\xAD\x97\xE6\xBC\xA2'\n  T\n\xE5\xAD\x97\xE6\xBC\xA2;".to_array()
  let tree = parser.parse(Bytes::from_array(source_code)).unwrap()
  let edit : @cli_test.Edit = {
    position: 17,
    deleted_length: 0,
    inserted_text: [46],
  }
  ignore(@cli_test.perform_edit(tree, source_code, edit))
  let tree2 = parser
    .parse(Bytes::from_array(source_code), old_tree=tree)
    .unwrap()
  let inverted = @cli_test.invert_edit(source_code, edit)
  ignore(@cli_test.perform_edit(tree2, source_code, inverted))
  let tree3 = parser
    .parse(Bytes::from_array(source_code), old_tree=tree2)
    .unwrap()
  assert_eq(tree3.root_node().to_sexp(), tree.root_node().to_sexp())
}

///|
async test "tree_cursor_on_aliased_root_with_extra_child" {
  let source =
    #|
    #|fn main() {
    #|    C/* hi */::<D>::E;
    #|}
    #|
  guard get_parsing_language("rust") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, source)
  let function = tree.root_node().child(0).unwrap()
  let block = function.child(3).unwrap()
  let expression_statement = block.child(1).unwrap()
  let scoped_identifier = expression_statement.child(0).unwrap()
  let generic_type = scoped_identifier.child(0).unwrap()
  assert_eq(generic_type.kind(), "generic_type")
  let cursor = generic_type.walk()
  assert_true(cursor.goto_first_child())
  assert_eq(cursor.node().kind(), "type_identifier")
  assert_true(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "block_comment")
}

// Regression test for an incremental reparse bug where an external
// scanner's choice depends on lexer->eof() (and thus on the parser's
// current included ranges). The cached token at byte 0 was emitted when
// the included range stopped just after the opener. Widening the range
// to include a later matching delimiter must invalidate that cached
// token so the scanner re-runs and emits the open form instead of the
// unclosed form.

///|
async test "reuse_invalidates_scanner_token_when_included_range_expands" {
  guard get_test_fixture_language("external_lookahead_eof_boundary")
    is Some(language) else {
    return
  }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let source = "``"
  parser.set_included_ranges([
    {
      start_byte: 0,
      end_byte: 1,
      start_point: @api.Point::new(0, 0),
      end_point: @api.Point::new(0, 1),
    },
  ])
  let tree1 = parse(parser, source)
  assert_eq(tree1.root_node().to_sexp(), "(document (unclosed_delim))")
  parser.set_included_ranges([
    {
      start_byte: 0,
      end_byte: 2,
      start_point: @api.Point::new(0, 0),
      end_point: @api.Point::new(0, 2),
    },
  ])
  let tree2 = parser.parse(utf8(source), old_tree=tree1).unwrap()
  assert_eq(
    tree2.root_node().to_sexp(),
    "(document (span (open_delim) (close_delim)))",
  )
}
