// Port of tree-sitter crates/cli/src/tests/node_test.rs (the tests that do
// not need a grammar generated at test time).

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
async fn parse_json_example() -> @api.Tree? {
  guard get_parsing_language("json") is Some(language) else { return None }
  Some(parse(parser_for(language), json_example))
}

///|
fn get_all_nodes(tree : @api.Tree) -> Array[@api.Node] {
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
async test "node_child" {
  guard parse_json_example() is Some(tree) else { return }
  let array_node = tree.root_node().child(0).unwrap()
  assert_eq(array_node.kind(), "array")
  assert_eq(array_node.named_child_count(), 3)
  assert_eq(array_node.start_byte(), find(json_example, "["))
  assert_eq(array_node.end_byte(), find(json_example, "]") + 1)
  assert_eq(array_node.start_position(), @api.Point::new(2, 0))
  assert_eq(array_node.end_position(), @api.Point::new(8, 1))
  assert_eq(array_node.child_count(), 7)
  let left_bracket_node = array_node.child(0).unwrap()
  let number_node = array_node.child(1).unwrap()
  let comma_node1 = array_node.child(2).unwrap()
  let false_node = array_node.child(3).unwrap()
  let comma_node2 = array_node.child(4).unwrap()
  let object_node = array_node.child(5).unwrap()
  let right_bracket_node = array_node.child(6).unwrap()
  assert_eq(left_bracket_node.kind(), "[")
  assert_eq(number_node.kind(), "number")
  assert_eq(comma_node1.kind(), ",")
  assert_eq(false_node.kind(), "false")
  assert_eq(comma_node2.kind(), ",")
  assert_eq(object_node.kind(), "object")
  assert_eq(right_bracket_node.kind(), "]")
  assert_false(left_bracket_node.is_named())
  assert_true(number_node.is_named())
  assert_false(comma_node1.is_named())
  assert_true(false_node.is_named())
  assert_false(comma_node2.is_named())
  assert_true(object_node.is_named())
  assert_false(right_bracket_node.is_named())
  assert_eq(number_node.start_byte(), find(json_example, "123"))
  assert_eq(number_node.end_byte(), find(json_example, "123") + 3)
  assert_eq(number_node.start_position(), @api.Point::new(3, 2))
  assert_eq(number_node.end_position(), @api.Point::new(3, 5))
  assert_eq(false_node.start_byte(), find(json_example, "false"))
  assert_eq(false_node.end_byte(), find(json_example, "false") + 5)
  assert_eq(false_node.start_position(), @api.Point::new(4, 2))
  assert_eq(false_node.end_position(), @api.Point::new(4, 7))
  assert_eq(object_node.start_byte(), find(json_example, "{"))
  assert_eq(object_node.start_position(), @api.Point::new(5, 2))
  assert_eq(object_node.end_position(), @api.Point::new(7, 3))
  assert_eq(object_node.child_count(), 3)
  let left_brace_node = object_node.child(0).unwrap()
  let pair_node = object_node.child(1).unwrap()
  let right_brace_node = object_node.child(2).unwrap()
  assert_eq(left_brace_node.kind(), "{")
  assert_eq(pair_node.kind(), "pair")
  assert_eq(right_brace_node.kind(), "}")
  assert_false(left_brace_node.is_named())
  assert_true(pair_node.is_named())
  assert_false(right_brace_node.is_named())
  assert_eq(pair_node.start_byte(), find(json_example, "\"x\""))
  assert_eq(pair_node.end_byte(), find(json_example, "null") + 4)
  assert_eq(pair_node.start_position(), @api.Point::new(6, 4))
  assert_eq(pair_node.end_position(), @api.Point::new(6, 13))
  assert_eq(pair_node.child_count(), 3)
  let string_node = pair_node.child(0).unwrap()
  let colon_node = pair_node.child(1).unwrap()
  let null_node = pair_node.child(2).unwrap()
  assert_eq(string_node.kind(), "string")
  assert_eq(colon_node.kind(), ":")
  assert_eq(null_node.kind(), "null")
  assert_true(string_node.is_named())
  assert_false(colon_node.is_named())
  assert_true(null_node.is_named())
  assert_eq(string_node.start_byte(), find(json_example, "\"x\""))
  assert_eq(string_node.end_byte(), find(json_example, "\"x\"") + 3)
  assert_eq(string_node.start_position(), @api.Point::new(6, 4))
  assert_eq(string_node.end_position(), @api.Point::new(6, 7))
  assert_eq(null_node.start_byte(), find(json_example, "null"))
  assert_eq(null_node.end_byte(), find(json_example, "null") + 4)
  assert_eq(null_node.start_position(), @api.Point::new(6, 9))
  assert_eq(null_node.end_position(), @api.Point::new(6, 13))
  assert_true(string_node.parent().unwrap() == pair_node)
  assert_true(null_node.parent().unwrap() == pair_node)
  assert_true(pair_node.parent().unwrap() == object_node)
  assert_true(number_node.parent().unwrap() == array_node)
  assert_true(false_node.parent().unwrap() == array_node)
  assert_true(object_node.parent().unwrap() == array_node)
  assert_true(array_node.parent().unwrap() == tree.root_node())
  assert_true(tree.root_node().parent() is None)
  assert_true(
    tree.root_node().child_with_descendant(null_node).unwrap() == array_node,
  )
  assert_true(
    array_node.child_with_descendant(null_node).unwrap() == object_node,
  )
  assert_true(
    object_node.child_with_descendant(null_node).unwrap() == pair_node,
  )
  assert_true(pair_node.child_with_descendant(null_node).unwrap() == null_node)
  assert_true(null_node.child_with_descendant(null_node) is None)
}

///|
async test "node_children" {
  guard parse_json_example() is Some(tree) else { return }
  let cursor = tree.walk()
  let array_node = tree.root_node().child(0).unwrap()
  assert_eq(array_node.children(cursor).map(n => n.kind()).to_array(), [
    "[", "number", ",", "false", ",", "object", "]",
  ])
  assert_eq(array_node.named_children(cursor).map(n => n.kind()).to_array(), [
    "number", "false", "object",
  ])
  let object_node = array_node
    .named_children(cursor)
    .find_first(n => n.kind() == "object")
    .unwrap()
  assert_eq(object_node.children(cursor).map(n => n.kind()).to_array(), [
    "{", "pair", "}",
  ])
}

///|
async test "node_children_by_field_name" {
  guard get_parsing_language("python") is Some(language) else { return }
  let source =
    #|
    #|        if one:
    #|            a()
    #|        elif two:
    #|            b()
    #|        elif three:
    #|            c()
    #|        elif four:
    #|            d()
    #|
  let bytes = utf8(source)
  let tree = parse(parser_for(language), source)
  let node = tree.root_node().child(0).unwrap()
  assert_eq(node.kind(), "if_statement")
  let cursor = tree.walk()
  let alternative_texts = node
    .children_by_field_name("alternative", cursor)
    .map(n => text(n.child_by_field_name("condition").unwrap(), bytes))
    .to_array()
  assert_eq(alternative_texts, ["two", "three", "four"])
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
async test "node_parent_of_child_by_field_name" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let tree = parse(parser_for(language), "foo(a().b[0].c.d.e())")
  let call_node = tree
    .root_node()
    .named_child(0)
    .unwrap()
    .named_child(0)
    .unwrap()
  assert_eq(call_node.kind(), "call_expression")
  // Regression test - when a field points to a hidden node (in this case,
  // `_expression`) the hidden node should not be added to the node parent
  // cache.
  assert_true(
    call_node.child_by_field_name("function").unwrap().parent() ==
    Some(call_node),
  )
}

///|
async test "next_sibling_of_zero_width_node" {
  guard get_parsing_language("next_sibling_from_zwt") is Some(language) else {
    return
  }
  let tree = parse(parser_for(language), "abdef")
  let root_node = tree.root_node()
  let missing_c = root_node.child(2).unwrap()
  assert_true(missing_c.is_missing())
  assert_eq(missing_c.kind(), "c")
  let node_d = root_node.child(3).unwrap()
  assert_true(missing_c.next_sibling().unwrap() == node_d)
  let prev_sibling = node_d.prev_sibling().unwrap()
  assert_true(prev_sibling == missing_c)
}

///|
async test "first_child_for_offset" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let tree = parse(parser_for(language), "x10 + 100")
  let sum_node = tree.root_node().child(0).unwrap().child(0).unwrap()
  assert_eq(sum_node.first_child_for_byte(0).unwrap().kind(), "identifier")
  assert_eq(sum_node.first_child_for_byte(1).unwrap().kind(), "identifier")
  assert_eq(sum_node.first_child_for_byte(3).unwrap().kind(), "+")
  assert_eq(sum_node.first_child_for_byte(5).unwrap().kind(), "number")
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
async fn binary_expression_with_comment() -> @api.Node? {
  guard get_parsing_language("c") is Some(language) else { return None }
  let tree = parse(parser_for(language), "int w = x + /* y is special! */ y;")
  let translation_unit_node = tree.root_node()
  let declaration_node = translation_unit_node.named_child(0).unwrap()
  Some(
    declaration_node
    .child_by_field_name("declarator")
    .unwrap()
    .child_by_field_name("value")
    .unwrap(),
  )
}

///|
async test "node_field_name_for_child" {
  guard binary_expression_with_comment() is Some(binary_expression_node) else {
    return
  }
  // left: (identifier)  0
  // operator: "+"       1 <--- (not a named child)
  // (comment)           2 <--- (is an extra)
  // right: (identifier) 3
  assert_eq(binary_expression_node.field_name_for_child(0), Some("left"))
  assert_eq(binary_expression_node.field_name_for_child(1), Some("operator"))
  // The comment should not have a field name, as it's just an extra
  assert_eq(binary_expression_node.field_name_for_child(2), None)
  assert_eq(binary_expression_node.field_name_for_child(3), Some("right"))
  // Negative test - Not a valid child index
  assert_eq(binary_expression_node.field_name_for_child(4), None)
}

///|
async test "node_field_name_for_named_child" {
  guard binary_expression_with_comment() is Some(binary_expression_node) else {
    return
  }
  // left: (identifier)  0
  // operator: "+"       _ <--- (not a named child)
  // (comment)           1 <--- (is an extra)
  // right: (identifier) 2
  assert_eq(binary_expression_node.field_name_for_named_child(0), Some("left"))
  // The comment should not have a field name, as it's just an extra
  assert_eq(binary_expression_node.field_name_for_named_child(1), None)
  // The operator is not a named child, so the named child at index 2 is the
  // right child
  assert_eq(binary_expression_node.field_name_for_named_child(2), Some("right"))
  // Negative test - Not a valid child index
  assert_eq(binary_expression_node.field_name_for_named_child(3), None)
}

///|
async test "node_child_by_field_name_through_hidden_nodes" {
  guard get_parsing_language("field_lookup_through_hidden_nodes")
    is Some(language) else {
    return
  }
  let parser = parser_for(language)
  // The first child that the tree cursor gives each field, if any.
  for
    case in [
      ("[a]", "spread", None),
      ("[a, ...b]", "spread", Some("...b")),
      ("let a = b;", "outer", Some("=")),
      ("let a // c\n= b;", "outer", Some("=")),
      ("let a @x = b;", "outer", Some("x")),
      ("shadow a;", "outer", None),
      ("alias ...a;", "spread", None),
      ("pair ...a, b;", "spread", None),
      ("pair ...a, ...b;", "spread", Some("...b")),
      ("multi a a = b;", "outer", Some("=")),
      ("restore a;", "outer", Some("a")),
      ("back a b;", "outer", Some("b")),
      ("maybe none end;", "outer", None),
      ("maybe a end;", "outer", Some("a")),
      ("order a b c;", "outer", Some("c")),
      ("skip a b c;", "outer", Some("c")),
      ("sum a + b + c;", "left", Some("a")),
    ] {
    let (source, field_name, expected) = case
    let tree = parse(parser, source)
    let node = tree.root_node().named_child(0).unwrap()
    let actual = match node.child_by_field_name(field_name) {
      Some(child) => Some(child.utf8_text(utf8(source)))
      None => None
    }
    assert_eq(actual, expected, msg="`\{field_name}` of `\{source}`")
  }
}

///|
async test "node_field_name_for_child_through_hidden_extras" {
  guard get_parsing_language("field_lookup_through_hidden_nodes")
    is Some(language) else {
    return
  }
  let parser = parser_for(language)
  // The tree cursor gives the nodes inside a hidden extra only the fields set
  // inside it, not the field of the child before it or of a rule around it.
  // An empty string stands for no field.
  for
    case in [
      (
        "let a @x = b;",
        ["", "inner", "", "outer", "outer", "outer", ""],
        ["inner", "outer", "outer"],
      ),
      (
        "let a #y = b;",
        ["", "inner", "", "", "outer", "outer", ""],
        ["inner", "", "outer"],
      ),
    ] {
    let (source, fields, named_fields) = case
    let tree = parse(parser, source)
    let binding = tree.root_node().named_child(0).unwrap()
    let actual = Array::makei(binding.child_count(), i => {
      binding.field_name_for_child(i).unwrap_or("")
    })
    assert_eq(actual, fields, msg="`\{source}`")
    let actual = Array::makei(binding.named_child_count(), i => {
      binding.field_name_for_named_child(i).unwrap_or("")
    })
    assert_eq(actual, named_fields, msg="named children of `\{source}`")
  }
}

///|
async test "node_named_child" {
  guard parse_json_example() is Some(tree) else { return }
  let array_node = tree.root_node().child(0).unwrap()
  let number_node = array_node.named_child(0).unwrap()
  let false_node = array_node.named_child(1).unwrap()
  let object_node = array_node.named_child(2).unwrap()
  assert_eq(number_node.kind(), "number")
  assert_eq(number_node.start_byte(), find(json_example, "123"))
  assert_eq(number_node.end_byte(), find(json_example, "123") + 3)
  assert_eq(number_node.start_position(), @api.Point::new(3, 2))
  assert_eq(number_node.end_position(), @api.Point::new(3, 5))
  assert_eq(false_node.kind(), "false")
  assert_eq(false_node.start_byte(), find(json_example, "false"))
  assert_eq(false_node.end_byte(), find(json_example, "false") + 5)
  assert_eq(false_node.start_position(), @api.Point::new(4, 2))
  assert_eq(false_node.end_position(), @api.Point::new(4, 7))
  assert_eq(object_node.kind(), "object")
  assert_eq(object_node.start_byte(), find(json_example, "{"))
  assert_eq(object_node.start_position(), @api.Point::new(5, 2))
  assert_eq(object_node.end_position(), @api.Point::new(7, 3))
  assert_eq(object_node.named_child_count(), 1)
  let pair_node = object_node.named_child(0).unwrap()
  assert_eq(pair_node.kind(), "pair")
  assert_eq(pair_node.start_byte(), find(json_example, "\"x\""))
  assert_eq(pair_node.end_byte(), find(json_example, "null") + 4)
  assert_eq(pair_node.start_position(), @api.Point::new(6, 4))
  assert_eq(pair_node.end_position(), @api.Point::new(6, 13))
  let string_node = pair_node.named_child(0).unwrap()
  let null_node = pair_node.named_child(1).unwrap()
  assert_eq(string_node.kind(), "string")
  assert_eq(null_node.kind(), "null")
  assert_true(pair_node.named_child(2) is None)
  assert_true(string_node.parent().unwrap() == pair_node)
  assert_true(null_node.parent().unwrap() == pair_node)
  assert_true(array_node.parent().unwrap() == tree.root_node())
  assert_true(tree.root_node().parent() is None)
}

///|
async test "node_is_named_but_aliased_as_anonymous" {
  guard get_parsing_language("named_rule_aliased_as_anonymous")
    is Some(language) else {
    return
  }
  let tree = parse(parser_for(language), "B C B")
  let root_node = tree.root_node()
  assert_false(root_node.has_error())
  assert_eq(root_node.child_count(), 3)
  assert_eq(root_node.named_child_count(), 2)
  let aliased = root_node.child(0).unwrap()
  assert_false(aliased.is_named())
  assert_eq(aliased.kind(), "the-alias")
  assert_eq(root_node.named_child(0).unwrap().kind(), "c")
}

///|
async test "node_descendant_count" {
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
async test "descendant_count_single_node_tree" {
  guard get_parsing_language("embedded-template") is Some(language) else {
    return
  }
  let tree = parse(parser_for(language), "hello")
  let nodes = get_all_nodes(tree)
  assert_eq(nodes.length(), 2)
  assert_eq(tree.root_node().descendant_count(), 2)
  let cursor = tree.root_node().walk()
  cursor.goto_descendant(0)
  assert_eq(cursor.depth(), 0)
  assert_true(cursor.node() == nodes[0])
  cursor.goto_descendant(1)
  assert_eq(cursor.depth(), 1)
  assert_true(cursor.node() == nodes[1])
}

///|
async test "node_descendant_for_range" {
  guard parse_json_example() is Some(tree) else { return }
  let array_node = tree.root_node()
  // Leaf node exactly matches the given bounds - byte query
  let colon_index = find(json_example, ":")
  let colon_node = array_node
    .descendant_for_byte_range(colon_index, colon_index + 1)
    .unwrap()
  assert_eq(colon_node.kind(), ":")
  assert_eq(colon_node.start_byte(), colon_index)
  assert_eq(colon_node.end_byte(), colon_index + 1)
  assert_eq(colon_node.start_position(), @api.Point::new(6, 7))
  assert_eq(colon_node.end_position(), @api.Point::new(6, 8))
  // Leaf node exactly matches the given bounds - point query
  let colon_node = array_node
    .descendant_for_point_range(@api.Point::new(6, 7), @api.Point::new(6, 8))
    .unwrap()
  assert_eq(colon_node.kind(), ":")
  assert_eq(colon_node.start_byte(), colon_index)
  // The given point is between two adjacent leaf nodes - byte query
  let colon_node = array_node
    .descendant_for_byte_range(colon_index, colon_index)
    .unwrap()
  assert_eq(colon_node.kind(), ":")
  assert_eq(colon_node.end_byte(), colon_index + 1)
  // The given point is between two adjacent leaf nodes - point query
  let colon_node = array_node
    .descendant_for_point_range(@api.Point::new(6, 7), @api.Point::new(6, 7))
    .unwrap()
  assert_eq(colon_node.kind(), ":")
  assert_eq(colon_node.end_position(), @api.Point::new(6, 8))
  // Leaf node starts at the lower bound, ends after the upper bound - byte
  // query
  let string_index = find(json_example, "\"x\"")
  let string_node = array_node
    .descendant_for_byte_range(string_index, string_index + 2)
    .unwrap()
  assert_eq(string_node.kind(), "string")
  assert_eq(string_node.start_byte(), string_index)
  assert_eq(string_node.end_byte(), string_index + 3)
  // Leaf node starts at the lower bound, ends after the upper bound - point
  // query
  let string_node = array_node
    .descendant_for_point_range(@api.Point::new(6, 4), @api.Point::new(6, 6))
    .unwrap()
  assert_eq(string_node.kind(), "string")
  assert_eq(string_node.end_position(), @api.Point::new(6, 7))
  // Leaf node starts before the lower bound, ends at the upper bound - byte
  // query
  let null_index = find(json_example, "null")
  let null_node = array_node
    .descendant_for_byte_range(null_index + 1, null_index + 4)
    .unwrap()
  assert_eq(null_node.kind(), "null")
  assert_eq(null_node.start_byte(), null_index)
  // Leaf node starts before the lower bound, ends at the upper bound - point
  // query
  let null_node = array_node
    .descendant_for_point_range(@api.Point::new(6, 11), @api.Point::new(6, 13))
    .unwrap()
  assert_eq(null_node.kind(), "null")
  assert_eq(null_node.start_position(), @api.Point::new(6, 9))
  // The bounds span multiple leaf nodes - return the smallest node that does
  // span it.
  let pair_node = array_node
    .descendant_for_byte_range(string_index + 2, string_index + 4)
    .unwrap()
  assert_eq(pair_node.kind(), "pair")
  assert_eq(pair_node.start_byte(), string_index)
  assert_eq(pair_node.end_byte(), string_index + 9)
  assert_true(colon_node.parent() == Some(pair_node))
  // no leaf spans the given range - return the smallest node that does span
  // it.
  let pair_node = array_node
    .named_descendant_for_point_range(
      @api.Point::new(6, 6),
      @api.Point::new(6, 8),
    )
    .unwrap()
  assert_eq(pair_node.kind(), "pair")
  assert_eq(pair_node.end_position(), @api.Point::new(6, 13))
  // Negative test, start > end
  assert_true(array_node.descendant_for_byte_range(1, 0) is None)
  assert_true(
    array_node.descendant_for_point_range(
      @api.Point::new(6, 8),
      @api.Point::new(6, 7),
    )
    is None,
  )
}

///|
/// A deterministic pseudo-random generator (upstream's tests use their own
/// `Rand` too).
priv struct Rand {
  mut state : UInt64
}

///|
fn Rand::unsigned(self : Rand, max : Int32) -> Int32 {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  ((self.state >> 33).to_int() & 0x7FFFFFFF) % max
}

///|
async test "node_edit" {
  guard parse_json_example() is Some(tree) else { return }
  let code = utf8(json_example).to_array()
  let mut tree = tree
  let rand : Rand = { state: 0, }
  for _ in 0..<10 {
    let nodes_before = get_all_nodes(tree)
    // A random edit (upstream's `get_random_edit`): delete a few bytes and
    // insert a few spaces or digits.
    let position = rand.unsigned(code.length())
    let deleted = rand.unsigned(3).min(code.length() - position)
    let inserted = if rand.unsigned(2) == 0 { "  " } else { "1" }
    let tree2 = tree.clone()
    let edit = perform_edit(tree2, code, position, deleted, inserted)
    let edited = nodes_before.map(node => node.edit(edit))
    let nodes_after = get_all_nodes(tree2)
    for i, node in edited {
      assert_eq(
        (node.kind(), node.start_byte(), node.start_position()),
        (
          nodes_after[i].kind(),
          nodes_after[i].start_byte(),
          nodes_after[i].start_position(),
        ),
      )
    }
    tree = tree2
  }
}

///|
async test "root_node_with_offset" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let tree = parse(parser_for(language), "  if (a) b")
  let node = tree.root_node_with_offset(6, @api.Point::new(2, 2))
  assert_eq(node.byte_range(), (8, 16))
  assert_eq(node.start_position(), @api.Point::new(2, 4))
  assert_eq(node.end_position(), @api.Point::new(2, 12))
  let child = node.child(0).unwrap().child(2).unwrap()
  assert_eq(child.kind(), "expression_statement")
  assert_eq(child.byte_range(), (15, 16))
}

///|
/// `root_node_with_offset`, adapted to the JSON grammar.
async test "root_node_with_offset (json)" {
  guard get_parsing_language("json") is Some(language) else { return }
  let tree = parse(parser_for(language), "  [1, 2]")
  let node = tree.root_node_with_offset(6, @api.Point::new(2, 2))
  assert_eq(node.byte_range(), (8, 14))
  assert_eq(node.start_position(), @api.Point::new(2, 4))
  assert_eq(node.end_position(), @api.Point::new(2, 10))
  let child = node.child(0).unwrap().child(3).unwrap()
  assert_eq(child.kind(), "number")
  assert_eq(child.byte_range(), (12, 13))
  assert_eq(child.start_position(), @api.Point::new(2, 8))
  let cursor = node.walk()
  assert_true(cursor.goto_first_child())
  assert_true(cursor.goto_first_child())
  assert_true(cursor.goto_next_sibling())
  let child = cursor.node()
  assert_eq(child.kind(), "number")
  assert_eq(child.byte_range(), (9, 10))
  assert_eq(child.end_position(), @api.Point::new(2, 6))
}

///|
async test "node_is_extra" {
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
async test "node_is_error" {
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
async test "node_has_error" {
  guard get_parsing_language("json") is Some(language) else { return }
  let tree = parse(parser_for(language), "!")
  let root = tree.root_node()
  assert_true(root.has_error())
  let error = root.child(0).unwrap()
  assert_true(error.is_error())
  assert_true(error.has_error())
  let terminal_error = error.child(0).unwrap()
  assert_true(terminal_error.is_error())
  assert_eq(terminal_error.child_count(), 0)
  assert_true(terminal_error.has_error())
}

///|
test "edit_point" {
  let edit : @api.InputEdit = {
    start_byte: 5,
    old_end_byte: 5,
    new_end_byte: 10,
    start_position: @api.Point::new(0, 5),
    old_end_position: @api.Point::new(0, 5),
    new_end_position: @api.Point::new(0, 10),
  }
  // Point after edit
  assert_eq(
    edit.edit_point(@api.Point::new(0, 8), 8),
    (@api.Point::new(0, 13), 13),
  )
  // Point before edit
  assert_eq(
    edit.edit_point(@api.Point::new(0, 2), 2),
    (@api.Point::new(0, 2), 2),
  )
  // Point at edit start
  assert_eq(
    edit.edit_point(@api.Point::new(0, 5), 5),
    (@api.Point::new(0, 10), 10),
  )
}

///|
test "edit_range" {
  let edit : @api.InputEdit = {
    start_byte: 10,
    old_end_byte: 15,
    new_end_byte: 20,
    start_position: @api.Point::new(1, 0),
    old_end_position: @api.Point::new(1, 5),
    new_end_position: @api.Point::new(2, 0),
  }
  // Range after edit
  let range = edit.edit_range({
    start_byte: 20,
    end_byte: 25,
    start_point: @api.Point::new(2, 0),
    end_point: @api.Point::new(2, 5),
  })
  assert_eq(range.start_byte, 25)
  assert_eq(range.end_byte, 30)
  assert_eq(range.start_point, @api.Point::new(3, 0))
  assert_eq(range.end_point, @api.Point::new(3, 5))
  // Range before edit
  let range = edit.edit_range({
    start_byte: 5,
    end_byte: 8,
    start_point: @api.Point::new(0, 5),
    end_point: @api.Point::new(0, 8),
  })
  assert_eq(range.start_byte, 5)
  assert_eq(range.end_byte, 8)
  assert_eq(range.start_point, @api.Point::new(0, 5))
  assert_eq(range.end_point, @api.Point::new(0, 8))
  // Range overlapping edit
  let range = edit.edit_range({
    start_byte: 8,
    end_byte: 12,
    start_point: @api.Point::new(0, 8),
    end_point: @api.Point::new(1, 2),
  })
  assert_eq(range.start_byte, 8)
  assert_eq(range.end_byte, 10)
  assert_eq(range.start_point, @api.Point::new(0, 8))
  assert_eq(range.end_point, @api.Point::new(1, 0))
}

///|
async test "node_sexp" {
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
    @api.format_sexp(root.to_sexp(), 0),
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
  let set : @hashset.HashSet[@api.Node] = @hashset.HashSet([])
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
