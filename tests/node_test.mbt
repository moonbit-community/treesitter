// Variants of tests of crates/cli/src/tests/node_test.rs (ported in
// node_suite_test.mbt) adapted to grammars whose scanners are ported, further
// node checks, and helpers shared with node_suite_test.mbt.

///|
let json_example : String =
  #|
  #|
  #|[
  #|  123,
  #|  false,
  #|  {
  #|    "x": null
  #|  }
  #|]
  #|

///|
fn find(haystack : String, needle : String) -> Int32 {
  haystack.find(needle).unwrap()
}

///|
async fn parse_json_example() -> @treesitter.Tree? {
  guard get_parsing_language("json") is Some(language) else { return None }
  Some(parse(parser_for(language), json_example))
}

///|
fn get_all_nodes(tree : @treesitter.Tree) -> Array[@treesitter.Node] {
  let result = []
  let mut visited_children = false
  let cursor = tree.walk()
  for ;; {
    if !visited_children {
      result.push(cursor.node())
      if !cursor.goto_first_child() {
        visited_children = true
      }
    } else if cursor.goto_next_sibling() {
      visited_children = false
    } else if !cursor.goto_parent() {
      break
    }
  }
  result
}

///|
/// `node_children_by_field_name`, adapted to the C grammar: the `declarator`
/// children of a declaration with several declarators.
async test "node_children_by_field_name (c)" {
  guard get_parsing_language("c") is Some(language) else { return }
  let source = "int a = 1, b, c = 3;"
  let bytes = utf8(source)
  let tree = parse(parser_for(language), source)
  let node = tree.root_node().child(0).unwrap()
  assert_eq(node.kind(), "declaration")
  let cursor = tree.walk()
  let texts = node
    .children_by_field_name("declarator", cursor)
    .map(n => text(n, bytes))
    .to_array()
  assert_eq(texts, ["a = 1", "b", "c = 3"])
  let id = language.field_id_for_name("declarator").unwrap()
  assert_eq(node.children_by_field_id(id, cursor).count(), 3)
  assert_eq(node.children_by_field_name("type", cursor).count(), 1)
  assert_eq(node.children_by_field_name("no_such_field", cursor).count(), 0)
}

///|
/// `first_child_for_offset` and `first_named_child_for_offset`, adapted to
/// the C grammar.
async test "first_child_for_offset (c)" {
  guard get_parsing_language("c") is Some(language) else { return }
  let tree = parse(parser_for(language), "x10 + 100;")
  let sum_node = tree.root_node().child(0).unwrap().child(0).unwrap()
  assert_eq(sum_node.kind(), "binary_expression")
  assert_eq(sum_node.first_child_for_byte(0).unwrap().kind(), "identifier")
  assert_eq(sum_node.first_child_for_byte(1).unwrap().kind(), "identifier")
  assert_eq(sum_node.first_child_for_byte(3).unwrap().kind(), "+")
  assert_eq(sum_node.first_child_for_byte(5).unwrap().kind(), "number_literal")
  assert_true(sum_node.first_child_for_byte(9) is None)
  assert_eq(
    sum_node.first_named_child_for_byte(0).unwrap().kind(),
    "identifier",
  )
  assert_eq(
    sum_node.first_named_child_for_byte(1).unwrap().kind(),
    "identifier",
  )
  assert_eq(
    sum_node.first_named_child_for_byte(3).unwrap().kind(),
    "number_literal",
  )
}

///|
/// `node_descendant_count`, also checking `descendant_index`.
async test "goto_descendant and descendant_index" {
  guard parse_json_example() is Some(tree) else { return }
  let value_node = tree.root_node()
  let all_nodes = get_all_nodes(tree)
  assert_eq(value_node.descendant_count(), all_nodes.length())
  let cursor = value_node.walk()
  for i, node in all_nodes {
    cursor.goto_descendant(i)
    assert_true(cursor.node() == node, msg="index \{i}")
    assert_eq(cursor.descendant_index(), i)
  }
  for i = all_nodes.length() - 1; i >= 0; i = i - 1 {
    cursor.goto_descendant(i)
    assert_true(cursor.node() == all_nodes[i], msg="rev index \{i}")
  }
}

///|
/// `root_node_with_offset`, adapted to the JSON grammar.
async test "root_node_with_offset (json)" {
  guard get_parsing_language("json") is Some(language) else { return }
  let tree = parse(parser_for(language), "  [1, 2]")
  let node = tree.root_node_with_offset(6, @treesitter.Point::new(2, 2))
  assert_eq(node.byte_range(), (8, 14))
  assert_eq(node.start_position(), @treesitter.Point::new(2, 4))
  assert_eq(node.end_position(), @treesitter.Point::new(2, 10))
  let child = node.child(0).unwrap().child(3).unwrap()
  assert_eq(child.kind(), "number")
  assert_eq(child.byte_range(), (12, 13))
  assert_eq(child.start_position(), @treesitter.Point::new(2, 8))
  let cursor = node.walk()
  assert_true(cursor.goto_first_child())
  assert_true(cursor.goto_first_child())
  assert_true(cursor.goto_next_sibling())
  let child = cursor.node()
  assert_eq(child.kind(), "number")
  assert_eq(child.byte_range(), (9, 10))
  assert_eq(child.end_position(), @treesitter.Point::new(2, 6))
}

///|
async test "node_is_extra (c)" {
  guard get_parsing_language("c") is Some(language) else { return }
  let tree = parse(parser_for(language), "int x /* hi */;")
  let root_node = tree.root_node()
  let comment_node = root_node.descendant_for_byte_range(7, 7).unwrap()
  assert_eq(root_node.kind(), "translation_unit")
  assert_eq(comment_node.kind(), "comment")
  assert_false(root_node.is_extra())
  assert_true(comment_node.is_extra())
}

///|
async test "node_is_error (json)" {
  guard get_parsing_language("json") is Some(language) else { return }
  let tree = parse(parser_for(language), "[1,")
  let root_node = tree.root_node()
  assert_eq(root_node.kind(), "document")
  assert_true(root_node.has_error())
  let child = root_node.child(0).unwrap()
  assert_eq(child.kind(), "ERROR")
  assert_true(child.is_error())
}

///|
async test "node_sexp (c)" {
  guard get_parsing_language("c") is Some(language) else { return }
  let tree = parse(parser_for(language), "if (a) b;")
  let root_node = tree.root_node()
  let if_node = root_node.descendant_for_byte_range(0, 0).unwrap()
  let paren_node = root_node.descendant_for_byte_range(3, 3).unwrap()
  let identifier_node = root_node.descendant_for_byte_range(4, 4).unwrap()
  assert_eq(if_node.kind(), "if")
  assert_eq(if_node.to_sexp(), "(\"if\")")
  assert_eq(paren_node.kind(), "(")
  assert_eq(paren_node.to_sexp(), "(\"(\")")
  assert_eq(identifier_node.kind(), "identifier")
  assert_eq(identifier_node.to_sexp(), "(identifier)")
}

///|
async test "node Debug, Display, Eq and Hash" {
  guard parse_json_example() is Some(tree) else { return }
  let root = tree.root_node()
  let array_node = root.child(0).unwrap()
  inspect(@debug.to_string(array_node), content="{Node array (2, 0) - (8, 1)}")
  inspect(
    @debug.to_string(tree),
    content="{Tree {Node document (2, 0) - (9, 0)}}",
  )
  inspect(array_node.child(1).unwrap(), content="(number)")
  inspect(
    root,
    content=(
      #|(document (array (number) (false) (object (pair key: (string (string_content)) value: (null)))))
    ),
  )
  inspect(
    @treesitter.format_sexp(root.to_sexp(), 0),
    content=(
      #|(document
      #|  (array
      #|    (number)
      #|    (false)
      #|    (object
      #|      (pair
      #|        key: (string
      #|          (string_content))
      #|        value: (null)))))
    ),
  )
  // Nodes for the same subtree compare and hash equal; others do not.
  let again = tree.root_node().child(0).unwrap()
  assert_true(again == array_node)
  assert_eq(again.id(), array_node.id())
  let set : @hashset.HashSet[@treesitter.Node] = @hashset.HashSet([])
  set.add(array_node)
  set.add(again)
  set.add(root)
  assert_eq(set.length(), 2)
  assert_true(array_node != root)
  assert_true(array_node.language() == tree.language())
  assert_eq(array_node.range().start_byte, array_node.start_byte())
  assert_eq(
    array_node.utf8_text(utf8(json_example)),
    "[\n  123,\n  false,\n  {\n    \"x\": null\n  }\n]",
  )
}
