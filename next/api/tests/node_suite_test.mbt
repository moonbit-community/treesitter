// Port of tree-sitter crates/cli/src/tests/node_test.rs.
//
// Tests whose grammar needs an external scanner that is not ported yet return
// early with a notice. `JSON_EXAMPLE`, `get_all_nodes` and
// `parse_json_example` are shared with node_test.mbt (`json_example`, ...).

///|
let grammar_with_aliases_and_extras : String =
  #|{
  #|  "name": "aliases_and_extras",
  #|
  #|  "extras": [
  #|    {"type": "PATTERN", "value": "\\s+"},
  #|    {"type": "SYMBOL", "name": "comment"}
  #|  ],
  #|
  #|  "rules": {
  #|    "a": {
  #|      "type": "SEQ",
  #|      "members": [
  #|        {"type": "SYMBOL", "name": "b"},
  #|        {
  #|          "type": "ALIAS",
  #|          "value": "B",
  #|          "named": true,
  #|          "content": {"type": "SYMBOL", "name": "b"}
  #|        },
  #|        {
  #|          "type": "ALIAS",
  #|          "value": "C",
  #|          "named": true,
  #|          "content": {"type": "SYMBOL", "name": "_c"}
  #|        }
  #|      ]
  #|    },
  #|
  #|    "b": {"type": "STRING", "value": "b"},
  #|
  #|    "_c": {"type": "STRING", "value": "c"},
  #|
  #|    "comment": {"type": "STRING", "value": "..."}
  #|  }
  #|}

///|
/// `&source[node.byte_range()]`.
fn source_slice(source : String, range : (Int32, Int32)) -> String {
  let (start, end) = range
  @utf8.decode(utf8(source)[start:end]) catch {
    _ => abort("not a char boundary")
  }
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
  assert_eq(string_node.parent().unwrap(), pair_node)
  assert_eq(null_node.parent().unwrap(), pair_node)
  assert_eq(pair_node.parent().unwrap(), object_node)
  assert_eq(number_node.parent().unwrap(), array_node)
  assert_eq(false_node.parent().unwrap(), array_node)
  assert_eq(object_node.parent().unwrap(), array_node)
  assert_eq(array_node.parent().unwrap(), tree.root_node())
  assert_eq(tree.root_node().parent(), None)
  assert_eq(
    tree.root_node().child_with_descendant(null_node).unwrap(),
    array_node,
  )
  assert_eq(array_node.child_with_descendant(null_node).unwrap(), object_node)
  assert_eq(object_node.child_with_descendant(null_node).unwrap(), pair_node)
  assert_eq(pair_node.child_with_descendant(null_node).unwrap(), null_node)
  assert_eq(null_node.child_with_descendant(null_node), None)
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
  let parser = @api.Parser::new()
  parser.set_language(language)
  let source = "\n        if one:\n            a()\n        elif two:\n            b()\n        elif three:\n            c()\n        elif four:\n            d()\n    "
  let tree = parse(parser, source)
  let node = tree.root_node().child(0).unwrap()
  assert_eq(node.kind(), "if_statement")
  let cursor = tree.walk()
  let alternatives = node.children_by_field_name("alternative", cursor)
  let alternative_texts = alternatives.map(n => {
    source_slice(
      source,
      n.child_by_field_name("condition").unwrap().byte_range(),
    )
  })
  assert_eq(alternative_texts.to_array(), ["two", "three", "four"])
}

///|
async test "node_parent_of_child_by_field_name" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "foo(a().b[0].c.d.e())")
  let call_node = tree
    .root_node()
    .named_child(0)
    .unwrap()
    .named_child(0)
    .unwrap()
  assert_eq(call_node.kind(), "call_expression")

  // Regression test - when a field points to a hidden node (in this case, `_expression`)
  // the hidden node should not be added to the node parent cache.
  assert_eq(
    call_node.child_by_field_name("function").unwrap().parent(),
    Some(call_node),
  )
}

///|
async test "parent_of_zero_width_node" {
  let code = "def dupa(foo):"
  guard get_parsing_language("python") is Some(python) else { return }
  let parser = @api.Parser::new()
  parser.set_language(python)
  let tree = parse(parser, code)
  let root = tree.root_node()
  let function_definition = root.child(0).unwrap()
  let block = function_definition.child(4).unwrap()
  let block_parent = block.parent().unwrap()
  assert_eq(block.to_string(), "(block)")
  assert_eq(block_parent.kind(), "function_definition")
  assert_eq(
    block_parent.to_string(),
    "(function_definition name: (identifier) parameters: (parameters (identifier)) body: (block))",
  )
  assert_eq(root.child_with_descendant(block).unwrap(), function_definition)
  assert_eq(function_definition.child_with_descendant(block).unwrap(), block)
  assert_eq(block.child_with_descendant(block), None)
  let code = "<script></script>"
  guard get_parsing_language("html") is Some(html) else { return }
  parser.set_language(html)
  let tree = parse(parser, code)
  let root = tree.root_node()
  let script_element = root.child(0).unwrap()
  let raw_text = script_element.child(1).unwrap()
  let parent = raw_text.parent().unwrap()
  assert_eq(parent, script_element)
}

///|
async test "next_sibling_of_zero_width_node" {
  let parser = @api.Parser::new()
  guard get_test_fixture_language("next_sibling_from_zwt") is Some(language) else {
    return
  }
  parser.set_language(language)
  let tree = parse(parser, "abdef")
  let root_node = tree.root_node()
  let missing_c = root_node.child(2).unwrap()
  assert_true(missing_c.is_missing())
  assert_eq(missing_c.kind(), "c")
  let node_d = root_node.child(3).unwrap()
  assert_eq(missing_c.next_sibling().unwrap(), node_d)
  let prev_sibling = node_d.prev_sibling().unwrap()
  assert_eq(prev_sibling, missing_c)
}

///|
async test "first_child_for_offset" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "x10 + 100")
  let sum_node = tree.root_node().child(0).unwrap().child(0).unwrap()
  assert_eq(sum_node.first_child_for_byte(0).unwrap().kind(), "identifier")
  assert_eq(sum_node.first_child_for_byte(1).unwrap().kind(), "identifier")
  assert_eq(sum_node.first_child_for_byte(3).unwrap().kind(), "+")
  assert_eq(sum_node.first_child_for_byte(5).unwrap().kind(), "number")
}

///|
async test "first_named_child_for_offset" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "x10 + 100")
  let sum_node = tree.root_node().child(0).unwrap().child(0).unwrap()
  assert_eq(
    sum_node.first_named_child_for_byte(0).unwrap().kind(),
    "identifier",
  )
  assert_eq(
    sum_node.first_named_child_for_byte(1).unwrap().kind(),
    "identifier",
  )
  assert_eq(sum_node.first_named_child_for_byte(3).unwrap().kind(), "number")
}

///|
async test "node_field_name_for_child" {
  guard get_parsing_language("c") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "int w = x + /* y is special! */ y;")
  let translation_unit_node = tree.root_node()
  let declaration_node = translation_unit_node.named_child(0).unwrap()
  let binary_expression_node = declaration_node
    .child_by_field_name("declarator")
    .unwrap()
    .child_by_field_name("value")
    .unwrap()

  // -------------------
  // left: (identifier)  0
  // operator: "+"       1 <--- (not a named child)
  // (comment)           2 <--- (is an extra)
  // right: (identifier) 3
  // -------------------

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
  guard get_parsing_language("c") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "int w = x + /* y is special! */ y;")
  let translation_unit_node = tree.root_node()
  let declaration_node = translation_unit_node.named_child(0).unwrap()
  let binary_expression_node = declaration_node
    .child_by_field_name("declarator")
    .unwrap()
    .child_by_field_name("value")
    .unwrap()

  // -------------------
  // left: (identifier)  0
  // operator: "+"       _ <--- (not a named child)
  // (comment)           1 <--- (is an extra)
  // right: (identifier) 2
  // -------------------

  assert_eq(binary_expression_node.field_name_for_named_child(0), Some("left"))
  // The comment should not have a field name, as it's just an extra
  assert_eq(binary_expression_node.field_name_for_named_child(1), None)
  // The operator is not a named child, so the named child at index 2 is the right child
  assert_eq(binary_expression_node.field_name_for_named_child(2), Some("right"))
  // Negative test - Not a valid child index
  assert_eq(binary_expression_node.field_name_for_named_child(3), None)
}

///|
async test "node_child_by_field_name_with_extra_hidden_children" {
  guard get_parsing_language("python") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)

  // In the Python grammar, some fields are applied to `suite` nodes,
  // which consist of an invisible `indent` token followed by a block.
  // Check that when searching for a child with a field name, we don't
  // return a hidden child node.
  let tree = parse(parser, "while a:\n  pass")
  let while_node = tree.root_node().child(0).unwrap()
  assert_eq(while_node.kind(), "while_statement")
  assert_eq(
    while_node.child_by_field_name("body").unwrap(),
    while_node.child(3).unwrap(),
  )
}

///|
async test "node_child_by_field_name_through_hidden_nodes" {
  let parser = @api.Parser::new()
  guard get_test_fixture_language("field_lookup_through_hidden_nodes")
    is Some(language) else {
    return
  }
  parser.set_language(language)

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
    assert_eq(
      node
      .child_by_field_name(field_name)
      .map(child => source_slice(source, child.byte_range())),
      expected,
      msg="`\{field_name}` of `\{source}`",
    )
  }
}

///|
async test "node_field_name_for_child_through_hidden_extras" {
  let parser = @api.Parser::new()
  guard get_test_fixture_language("field_lookup_through_hidden_nodes")
    is Some(language) else {
    return
  }
  parser.set_language(language)

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
  assert_eq(string_node.start_byte(), find(json_example, "\"x\""))
  assert_eq(string_node.end_byte(), find(json_example, "\"x\"") + 3)
  assert_eq(string_node.start_position(), @api.Point::new(6, 4))
  assert_eq(string_node.end_position(), @api.Point::new(6, 7))
  assert_eq(null_node.start_byte(), find(json_example, "null"))
  assert_eq(null_node.end_byte(), find(json_example, "null") + 4)
  assert_eq(null_node.start_position(), @api.Point::new(6, 9))
  assert_eq(null_node.end_position(), @api.Point::new(6, 13))
  assert_eq(string_node.parent().unwrap(), pair_node)
  assert_eq(null_node.parent().unwrap(), pair_node)
  assert_eq(pair_node.parent().unwrap(), object_node)
  assert_eq(number_node.parent().unwrap(), array_node)
  assert_eq(false_node.parent().unwrap(), array_node)
  assert_eq(object_node.parent().unwrap(), array_node)
  assert_eq(array_node.parent().unwrap(), tree.root_node())
  assert_eq(tree.root_node().parent(), None)
  assert_eq(
    tree.root_node().child_with_descendant(null_node).unwrap(),
    array_node,
  )
  assert_eq(array_node.child_with_descendant(null_node).unwrap(), object_node)
  assert_eq(object_node.child_with_descendant(null_node).unwrap(), pair_node)
  assert_eq(pair_node.child_with_descendant(null_node).unwrap(), null_node)
  assert_eq(null_node.child_with_descendant(null_node), None)
}

///|
test "node_named_child_with_aliases_and_extras" {
  let parser_code = generate_parser(grammar_with_aliases_and_extras)
  let parser = @api.Parser::new()
  parser.set_language(get_test_language(parser_code))
  let tree = parse(parser, "b ... b ... c")
  let root = tree.root_node()
  assert_eq(root.to_sexp(), "(a (b) (comment) (B) (comment) (C))")
  assert_eq(root.named_child_count(), 5)
  assert_eq(root.named_child(0).unwrap().kind(), "b")
  assert_eq(root.named_child(1).unwrap().kind(), "comment")
  assert_eq(root.named_child(2).unwrap().kind(), "B")
  assert_eq(root.named_child(3).unwrap().kind(), "comment")
  assert_eq(root.named_child(4).unwrap().kind(), "C")
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
    assert_eq(cursor.node(), node, msg="index \{i}")
  }
  for i = all_nodes.length() - 1; i >= 0; i = i - 1 {
    cursor.goto_descendant(i)
    assert_eq(cursor.node(), all_nodes[i], msg="rev index \{i}")
  }
}

///|
async test "descendant_count_single_node_tree" {
  guard get_parsing_language("embedded-template") is Some(language) else {
    return
  }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "hello")
  let nodes = get_all_nodes(tree)
  assert_eq(nodes.length(), 2)
  assert_eq(tree.root_node().descendant_count(), 2)
  let cursor = tree.root_node().walk()
  cursor.goto_descendant(0)
  assert_eq(cursor.depth(), 0)
  assert_eq(cursor.node(), nodes[0])
  cursor.goto_descendant(1)
  assert_eq(cursor.depth(), 1)
  assert_eq(cursor.node(), nodes[1])
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
  assert_eq(colon_node.end_byte(), colon_index + 1)
  assert_eq(colon_node.start_position(), @api.Point::new(6, 7))
  assert_eq(colon_node.end_position(), @api.Point::new(6, 8))

  // The given point is between two adjacent leaf nodes - byte query
  let colon_index = find(json_example, ":")
  let colon_node = array_node
    .descendant_for_byte_range(colon_index, colon_index)
    .unwrap()
  assert_eq(colon_node.kind(), ":")
  assert_eq(colon_node.start_byte(), colon_index)
  assert_eq(colon_node.end_byte(), colon_index + 1)
  assert_eq(colon_node.start_position(), @api.Point::new(6, 7))
  assert_eq(colon_node.end_position(), @api.Point::new(6, 8))

  // The given point is between two adjacent leaf nodes - point query
  let colon_node = array_node
    .descendant_for_point_range(@api.Point::new(6, 7), @api.Point::new(6, 7))
    .unwrap()
  assert_eq(colon_node.kind(), ":")
  assert_eq(colon_node.start_byte(), colon_index)
  assert_eq(colon_node.end_byte(), colon_index + 1)
  assert_eq(colon_node.start_position(), @api.Point::new(6, 7))
  assert_eq(colon_node.end_position(), @api.Point::new(6, 8))

  // Leaf node starts at the lower bound, ends after the upper bound - byte query
  let string_index = find(json_example, "\"x\"")
  let string_node = array_node
    .descendant_for_byte_range(string_index, string_index + 2)
    .unwrap()
  assert_eq(string_node.kind(), "string")
  assert_eq(string_node.start_byte(), string_index)
  assert_eq(string_node.end_byte(), string_index + 3)
  assert_eq(string_node.start_position(), @api.Point::new(6, 4))
  assert_eq(string_node.end_position(), @api.Point::new(6, 7))

  // Leaf node starts at the lower bound, ends after the upper bound - point query
  let string_node = array_node
    .descendant_for_point_range(@api.Point::new(6, 4), @api.Point::new(6, 6))
    .unwrap()
  assert_eq(string_node.kind(), "string")
  assert_eq(string_node.start_byte(), string_index)
  assert_eq(string_node.end_byte(), string_index + 3)
  assert_eq(string_node.start_position(), @api.Point::new(6, 4))
  assert_eq(string_node.end_position(), @api.Point::new(6, 7))

  // Leaf node starts before the lower bound, ends at the upper bound - byte query
  let null_index = find(json_example, "null")
  let null_node = array_node
    .descendant_for_byte_range(null_index + 1, null_index + 4)
    .unwrap()
  assert_eq(null_node.kind(), "null")
  assert_eq(null_node.start_byte(), null_index)
  assert_eq(null_node.end_byte(), null_index + 4)
  assert_eq(null_node.start_position(), @api.Point::new(6, 9))
  assert_eq(null_node.end_position(), @api.Point::new(6, 13))

  // Leaf node starts before the lower bound, ends at the upper bound - point query
  let null_node = array_node
    .descendant_for_point_range(@api.Point::new(6, 11), @api.Point::new(6, 13))
    .unwrap()
  assert_eq(null_node.kind(), "null")
  assert_eq(null_node.start_byte(), null_index)
  assert_eq(null_node.end_byte(), null_index + 4)
  assert_eq(null_node.start_position(), @api.Point::new(6, 9))
  assert_eq(null_node.end_position(), @api.Point::new(6, 13))

  // The bounds span multiple leaf nodes - return the smallest node that does span it.
  let pair_node = array_node
    .descendant_for_byte_range(string_index + 2, string_index + 4)
    .unwrap()
  assert_eq(pair_node.kind(), "pair")
  assert_eq(pair_node.start_byte(), string_index)
  assert_eq(pair_node.end_byte(), string_index + 9)
  assert_eq(pair_node.start_position(), @api.Point::new(6, 4))
  assert_eq(pair_node.end_position(), @api.Point::new(6, 13))
  assert_eq(colon_node.parent(), Some(pair_node))

  // no leaf spans the given range - return the smallest node that does span it.
  let pair_node = array_node
    .named_descendant_for_point_range(
      @api.Point::new(6, 6),
      @api.Point::new(6, 8),
    )
    .unwrap()
  assert_eq(pair_node.kind(), "pair")
  assert_eq(pair_node.start_byte(), string_index)
  assert_eq(pair_node.end_byte(), string_index + 9)
  assert_eq(pair_node.start_position(), @api.Point::new(6, 4))
  assert_eq(pair_node.end_position(), @api.Point::new(6, 13))

  // Zero-width token
  {
    let code = "<script></script>"
    guard get_parsing_language("html") is Some(html) else { return }
    let parser = @api.Parser::new()
    parser.set_language(html)
    let tree = parse(parser, code)
    let root = tree.root_node()
    let child = root
      .named_descendant_for_point_range(
        @api.Point::new(0, 8),
        @api.Point::new(0, 8),
      )
      .unwrap()
    assert_eq(child.kind(), "raw_text")
    let child2 = root.named_descendant_for_byte_range(8, 8).unwrap()
    assert_eq(child2.kind(), "raw_text")
    assert_eq(child, child2)
  }

  // Negative test, start > end
  assert_eq(array_node.descendant_for_byte_range(1, 0), None)
  assert_eq(
    array_node.descendant_for_point_range(
      @api.Point::new(6, 8),
      @api.Point::new(6, 7),
    ),
    None,
  )
}

///|
async test "node_edit" {
  let code = utf8(json_example).to_array()
  guard parse_json_example() is Some(tree) else { return }
  let mut tree = tree
  let rand = @cli_test.Rand::new(0)
  for _ in 0..<10 {
    let nodes_before = get_all_nodes(tree)
    let edit = @cli_test.get_random_edit(rand, code)
    let tree2 = tree.clone()
    let edit = @cli_test.perform_edit(tree2, code, edit)
    let nodes_before = nodes_before.map(node => node.edit(edit))
    let nodes_after = get_all_nodes(tree2)
    for i, node in nodes_before {
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
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "  if (a) b")
  let node = tree.root_node_with_offset(6, @api.Point::new(2, 2))
  assert_eq(node.byte_range(), (8, 16))
  assert_eq(node.start_position(), @api.Point::new(2, 4))
  assert_eq(node.end_position(), @api.Point::new(2, 12))
  let child = node.child(0).unwrap().child(2).unwrap()
  assert_eq(child.kind(), "expression_statement")
  assert_eq(child.byte_range(), (15, 16))
  assert_eq(child.start_position(), @api.Point::new(2, 11))
  assert_eq(child.end_position(), @api.Point::new(2, 12))
  let cursor = node.walk()
  ignore(cursor.goto_first_child())
  ignore(cursor.goto_first_child())
  ignore(cursor.goto_next_sibling())
  let child = cursor.node()
  assert_eq(child.kind(), "parenthesized_expression")
  assert_eq(child.byte_range(), (11, 14))
  assert_eq(child.start_position(), @api.Point::new(2, 7))
  assert_eq(child.end_position(), @api.Point::new(2, 10))
}

///|
async test "node_is_extra" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "foo(/* hi */);")
  let root_node = tree.root_node()
  let comment_node = root_node.descendant_for_byte_range(7, 7).unwrap()
  assert_eq(root_node.kind(), "program")
  assert_eq(comment_node.kind(), "comment")
  assert_false(root_node.is_extra())
  assert_true(comment_node.is_extra())
}

///|
async test "node_is_error" {
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "foo(")
  let root_node = tree.root_node()
  assert_eq(root_node.kind(), "program")
  assert_true(root_node.has_error())
  let child = root_node.child(0).unwrap()
  assert_eq(child.kind(), "ERROR")
  assert_true(child.is_error())
}

///|
async test "node_has_error" {
  guard get_parsing_language("json") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "!")
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
  let (point, byte) = edit.edit_point(@api.Point::new(0, 8), 8)
  assert_eq(point, @api.Point::new(0, 13))
  assert_eq(byte, 13)

  // Point before edit
  let (point, byte) = edit.edit_point(@api.Point::new(0, 2), 2)
  assert_eq(point, @api.Point::new(0, 2))
  assert_eq(byte, 2)

  // Point at edit start
  let (point, byte) = edit.edit_point(@api.Point::new(0, 5), 5)
  assert_eq(point, @api.Point::new(0, 10))
  assert_eq(byte, 10)
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
  guard get_parsing_language("javascript") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, "if (a) b")
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
test "node_field_names" {
  // - "x": This isn't used in the test, but prevents `_hidden_rule1` from being eliminated as a
  //   unit reduction.
  // - "_hidden_rule1": Fields pointing to hidden nodes with a single child resolve to the child.
  // - "_hidden_rule2": Fields within hidden nodes can be referenced through the parent node.
  let parser_code = generate_parser(
    (
      #|
      #|        {
      #|            "name": "test_grammar_with_fields",
      #|            "extras": [
      #|                {"type": "PATTERN", "value": "\\s+"}
      #|            ],
      #|            "rules": {
      #|                "rule_a": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        {
      #|                            "type": "FIELD",
      #|                            "name": "field_1",
      #|                            "content": {"type": "STRING", "value": "child-0"}
      #|                        },
      #|                        {
      #|                            "type": "CHOICE",
      #|                            "members": [
      #|                                {"type": "STRING", "value": "child-1"},
      #|                                {"type": "BLANK"},
      #|
      #|                                {
      #|                                    "type": "ALIAS",
      #|                                    "value": "x",
      #|                                    "named": true,
      #|                                    "content": {
      #|                                        "type": "SYMBOL",
      #|                                        "name": "_hidden_rule1"
      #|                                    }
      #|                                }
      #|                            ]
      #|                        },
      #|                        {
      #|                            "type": "FIELD",
      #|                            "name": "field_2",
      #|                            "content": {"type": "SYMBOL", "name": "_hidden_rule1"}
      #|                        },
      #|                        {"type": "SYMBOL", "name": "_hidden_rule2"}
      #|                    ]
      #|                },
      #|
      #|                "_hidden_rule1": {
      #|                    "type": "CHOICE",
      #|                    "members": [
      #|                        {"type": "STRING", "value": "child-2"},
      #|                        {"type": "STRING", "value": "child-2.5"}
      #|                    ]
      #|                },
      #|
      #|                "_hidden_rule2": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        {"type": "STRING", "value": "child-3"},
      #|                        {
      #|                            "type": "FIELD",
      #|                            "name": "field_3",
      #|                            "content": {"type": "STRING", "value": "child-4"}
      #|                        }
      #|                    ]
      #|                }
      #|            }
      #|        }
      #|
    ),
  )
  let parser = @api.Parser::new()
  let language = get_test_language(parser_code)
  parser.set_language(language)
  let tree = parse(parser, "child-0 child-1 child-2 child-3 child-4")
  let root_node = tree.root_node()
  assert_eq(root_node.child_by_field_name("field_1"), root_node.child(0))
  assert_eq(root_node.child_by_field_name("field_2"), root_node.child(2))
  assert_eq(root_node.child_by_field_name("field_3"), root_node.child(4))
  assert_eq(root_node.child(0).unwrap().child_by_field_name("field_1"), None)
  assert_eq(root_node.child_by_field_name("not_a_real_field"), None)
  let cursor = root_node.walk()
  assert_eq(cursor.field_name(), None)
  ignore(cursor.goto_first_child())
  assert_eq(cursor.node().kind(), "child-0")
  assert_eq(cursor.field_name(), Some("field_1"))
  ignore(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "child-1")
  assert_eq(cursor.field_name(), None)
  ignore(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "child-2")
  assert_eq(cursor.field_name(), Some("field_2"))
  ignore(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "child-3")
  assert_eq(cursor.field_name(), None)
  ignore(cursor.goto_next_sibling())
  assert_eq(cursor.node().kind(), "child-4")
  assert_eq(cursor.field_name(), Some("field_3"))
}

///|
test "node_field_calls_in_language_without_fields" {
  let parser_code = generate_parser(
    (
      #|
      #|        {
      #|            "name": "test_grammar_with_no_fields",
      #|            "extras": [
      #|                {"type": "PATTERN", "value": "\\s+"}
      #|            ],
      #|            "rules": {
      #|                "a": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        {
      #|                            "type": "STRING",
      #|                            "value": "b"
      #|                        },
      #|                        {
      #|                            "type": "STRING",
      #|                            "value": "c"
      #|                        },
      #|                        {
      #|                            "type": "STRING",
      #|                            "value": "d"
      #|                        }
      #|                    ]
      #|                }
      #|            }
      #|        }
      #|
    ),
  )
  let parser = @api.Parser::new()
  let language = get_test_language(parser_code)
  parser.set_language(language)
  let tree = parse(parser, "b c d")
  let root_node = tree.root_node()
  assert_eq(root_node.kind(), "a")
  assert_eq(root_node.child_by_field_name("something"), None)
  let cursor = root_node.walk()
  assert_eq(cursor.field_name(), None)
  assert_true(cursor.goto_first_child())
  assert_eq(cursor.field_name(), None)
}

///|
async test "node_is_named_but_aliased_as_anonymous" {
  guard load_test_grammar_json("named_rule_aliased_as_anonymous")
    is Some(grammar_json) else {
    return
  }
  let parser_code = generate_parser(grammar_json)
  let parser = @api.Parser::new()
  let language = get_test_language(parser_code)
  parser.set_language(language)
  let tree = parse(parser, "B C B")
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
async test "node_numeric_symbols_respect_simple_aliases" {
  guard get_parsing_language("python") is Some(python) else { return }
  let parser = @api.Parser::new()
  parser.set_language(python)

  // Example 1:
  // Python argument lists can contain "splat" arguments, which are not allowed
  // within other expressions. This includes `parenthesized_list_splat` nodes
  // like `(*b)`. These `parenthesized_list_splat` nodes are aliased as
  // `parenthesized_expression`. Their numeric `symbol`, aka `kind_id` should
  // match that of a normal `parenthesized_expression`.
  let tree = parse(parser, "(a((*b)))")
  let root = tree.root_node()
  assert_eq(
    root.to_sexp(),
    "(module (expression_statement (parenthesized_expression (call function: (identifier) arguments: (argument_list (parenthesized_expression (list_splat (identifier))))))))",
  )
  let outer_expr_node = root.child(0).unwrap().child(0).unwrap()
  assert_eq(outer_expr_node.kind(), "parenthesized_expression")
  let inner_expr_node = outer_expr_node
    .named_child(0)
    .unwrap()
    .child_by_field_name("arguments")
    .unwrap()
    .named_child(0)
    .unwrap()
  assert_eq(inner_expr_node.kind(), "parenthesized_expression")
  assert_eq(inner_expr_node.kind_id(), outer_expr_node.kind_id())

  // Example 2:
  // Ruby handles the unary (negative) and binary (minus) `-` operators using two
  // different tokens. One or more of these is an external token that's
  // aliased as `-`. Their numeric kind ids should match.
  guard get_parsing_language("ruby") is Some(ruby) else { return }
  parser.set_language(ruby)
  let tree = parse(parser, "-a - b")
  let root = tree.root_node()
  assert_eq(
    root.to_sexp(),
    "(program (binary left: (unary operand: (identifier)) right: (identifier)))",
  )
  let binary_node = root.child(0).unwrap()
  assert_eq(binary_node.kind(), "binary")
  let unary_minus_node = binary_node
    .child_by_field_name("left")
    .unwrap()
    .child(0)
    .unwrap()
  assert_eq(unary_minus_node.kind(), "-")
  let binary_minus_node = binary_node.child_by_field_name("operator").unwrap()
  assert_eq(binary_minus_node.kind(), "-")
  assert_eq(unary_minus_node.kind_id(), binary_minus_node.kind_id())
}

///|
async test "hidden_zero_width_node_with_visible_child" {
  let code =
    #|
    #|class Foo {
    #|  std::
    #|private:
    #|  std::string s;
    #|};
    #|
  guard get_parsing_language("cpp") is Some(language) else { return }
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parse(parser, code)
  let root = tree.root_node()
  let class_specifier = root.child(0).unwrap()
  let field_decl_list = class_specifier.child_by_field_name("body").unwrap()
  let field_decl = field_decl_list.named_child(0).unwrap()
  let field_ident = field_decl.child_by_field_name("declarator").unwrap()
  assert_eq(field_decl.child_with_descendant(field_ident).unwrap(), field_ident)
}

///|
fn parse_deeply_nested_tree(depth : Int32) -> @api.Tree raise {
  let parser_code = generate_parser(
    (
      #|{
      #|            "name": "deeply_nested",
      #|            "rules": {
      #|                "document": {"type": "SYMBOL", "name": "expression"},
      #|                "expression": {
      #|                    "type": "CHOICE",
      #|                    "members": [
      #|                        {"type": "STRING", "value": "x"},
      #|                        {
      #|                            "type": "SEQ",
      #|                            "members": [
      #|                                {"type": "STRING", "value": "("},
      #|                                {"type": "SYMBOL", "name": "expression"},
      #|                                {"type": "STRING", "value": ")"}
      #|                            ]
      #|                        }
      #|                    ]
      #|                }
      #|            }
      #|        }
    ),
  )
  let language = get_test_language(parser_code)
  let source = "(".repeat(depth) + "x" + ")".repeat(depth)
  let parser = @api.Parser::new()
  parser.set_language(language)
  parse(parser, source)
}

///|
fn collapse_deeply_nested_tree(tree : @api.Tree, depth : Int32) -> Unit {
  let old_end_byte = depth * 2 + 1
  tree.edit({
    start_byte: 0,
    old_end_byte,
    new_end_byte: 0,
    start_position: @api.Point::new(0, 0),
    old_end_position: @api.Point::new(0, old_end_byte),
    new_end_position: @api.Point::new(0, 0),
  })
}

///|
test "deeply_nested_dot_graph_does_not_overflow_stack" {
  let tree = parse_deeply_nested_tree(100_000)
  // (Upstream writes to /dev/null.)
  let file = StringBuilder()
  tree.print_dot_graph(file)
}

///|
test "previous_sibling_of_identical_zero_width_leaves" {
  for depth in [3, 63, 64, 65, 66] {
    let tree = parse_deeply_nested_tree(depth)
    collapse_deeply_nested_tree(tree, depth)
    let expression = tree.root_node().named_child(0).unwrap()
    let inner_expression = expression.named_child(0).unwrap()
    let closing_parenthesis = expression
      .child(expression.child_count() - 1)
      .unwrap()

    // Different closing parentheses can share inline data after the edit.
    assert_eq(
      closing_parenthesis.prev_sibling(),
      Some(inner_expression),
      msg="depth \{depth}",
    )
    assert_eq(
      closing_parenthesis.prev_named_sibling(),
      Some(inner_expression),
      msg="depth \{depth}",
    )
  }
}

///|
test "previous_sibling_of_zero_width_nodes_in_hidden_rules" {
  let parser_code = generate_parser(
    (
      #|{
      #|            "name": "deeply_nested_hidden_siblings",
      #|            "rules": {
      #|                "document": {"type": "SYMBOL", "name": "_expression"},
      #|                "_expression": {
      #|                    "type": "CHOICE",
      #|                    "members": [
      #|                        {"type": "STRING", "value": "x"},
      #|                        {
      #|                            "type": "SEQ",
      #|                            "members": [
      #|                                {"type": "STRING", "value": "("},
      #|                                {"type": "SYMBOL", "name": "_expression"},
      #|                                {"type": "STRING", "value": ")"}
      #|                            ]
      #|                        }
      #|                    ]
      #|                }
      #|            }
      #|        }
    ),
  )
  let language = get_test_language(parser_code)
  let parser = @api.Parser::new()
  parser.set_language(language)
  for depth in [3, 63, 64, 65, 66, 128] {
    let source = "(".repeat(depth) + "x" + ")".repeat(depth)
    let tree = parse(parser, source)
    collapse_deeply_nested_tree(tree, depth)
    let root = tree.root_node()
    let x_index = depth
    let opening_parenthesis = root.child(x_index - 1).unwrap()
    let x = root.child(x_index).unwrap()
    let first_closing_parenthesis = root.child(x_index + 1).unwrap()
    let last_closing_parenthesis = root.child(root.child_count() - 1).unwrap()
    let previous_closing_parenthesis = root
      .child(root.child_count() - 2)
      .unwrap()
    assert_eq(x.prev_sibling(), Some(opening_parenthesis), msg="depth \{depth}")
    assert_eq(
      first_closing_parenthesis.prev_sibling(),
      Some(x),
      msg="depth \{depth}",
    )
    assert_eq(
      last_closing_parenthesis.prev_sibling(),
      Some(previous_closing_parenthesis),
      msg="depth \{depth}",
    )
  }
}

///|
test "deeply_nested_node_searches_do_not_overflow_stack" {
  let depth = 100_000
  let tree = parse_deeply_nested_tree(depth)
  collapse_deeply_nested_tree(tree, depth)
  let root = tree.root_node()
  let expression = root.named_child(0).unwrap()
  let mut descendant = expression
  while descendant.named_child(0) is Some(child) {
    descendant = child
  }
  let inner_expression = expression.named_child(0).unwrap()
  let closing_parenthesis = expression
    .child(expression.child_count() - 1)
    .unwrap()
  assert_eq(root.child_with_descendant(descendant), Some(expression))
  assert_eq(closing_parenthesis.kind(), ")")
  assert_eq(closing_parenthesis.prev_sibling(), Some(inner_expression))
  assert_eq(closing_parenthesis.prev_named_sibling(), Some(inner_expression))
}

///|
test "deeply_nested_trailing_empty_descendant_search" {
  let parser_code = generate_parser(
    (
      #|{
      #|            "name": "deeply_nested_with_marker",
      #|            "rules": {
      #|                "document": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        {"type": "SYMBOL", "name": "expression"},
      #|                        {"type": "SYMBOL", "name": "marker"}
      #|                    ]
      #|                },
      #|                "expression": {
      #|                    "type": "CHOICE",
      #|                    "members": [
      #|                        {"type": "STRING", "value": "x"},
      #|                        {
      #|                            "type": "SEQ",
      #|                            "members": [
      #|                                {"type": "STRING", "value": "("},
      #|                                {"type": "SYMBOL", "name": "expression"},
      #|                                {"type": "STRING", "value": ")"}
      #|                            ]
      #|                        }
      #|                    ]
      #|                },
      #|                "marker": {
      #|                    "type": "SEQ",
      #|                    "members": [
      #|                        {"type": "STRING", "value": "a"},
      #|                        {"type": "STRING", "value": "b"}
      #|                    ]
      #|                }
      #|            }
      #|        }
    ),
  )
  let language = get_test_language(parser_code)
  let parser = @api.Parser::new()
  parser.set_language(language)
  for depth in [63, 64, 65, 100_000] {
    let source = "(".repeat(depth) + "x" + ")".repeat(depth) + "ab"
    let tree = parse(parser, source)
    tree.edit({
      start_byte: 0,
      old_end_byte: source.length(),
      new_end_byte: 0,
      start_position: @api.Point::new(0, 0),
      old_end_position: @api.Point::new(0, source.length()),
      new_end_position: @api.Point::new(0, 0),
    })
    let root = tree.root_node()
    let expression = root.named_child(0).unwrap()
    let marker = root.named_child(1).unwrap()

    // A non-leaf marker forces the search through the preceding empty subtree.
    assert_eq(marker.child_count(), 2)
    assert_eq(marker.prev_sibling(), Some(expression), msg="depth \{depth}")
  }
}

///|
test "deeply_nested_field_search_does_not_overflow_stack" {
  let parser_code = generate_parser(
    (
      #|{
      #|            "name": "deeply_nested_fields",
      #|            "rules": {
      #|                "document": {"type": "SYMBOL", "name": "_nested"},
      #|                "_nested": {
      #|                    "type": "CHOICE",
      #|                    "members": [
      #|                        {
      #|                            "type": "FIELD",
      #|                            "name": "target",
      #|                            "content": {"type": "STRING", "value": "x"}
      #|                        },
      #|                        {
      #|                            "type": "SEQ",
      #|                            "members": [
      #|                                {"type": "STRING", "value": "("},
      #|                                {"type": "SYMBOL", "name": "_nested"},
      #|                                {"type": "STRING", "value": ")"},
      #|                                {
      #|                                    "type": "FIELD",
      #|                                    "name": "target",
      #|                                    "content": {"type": "STRING", "value": "z"}
      #|                                }
      #|                            ]
      #|                        }
      #|                    ]
      #|                }
      #|            }
      #|        }
    ),
  )
  let language = get_test_language(parser_code)
  let depth = 100_000
  let source = "(".repeat(depth) + "x" + ")z".repeat(depth)
  let parser = @api.Parser::new()
  parser.set_language(language)
  let tree = parser.parse(utf8(source)).unwrap()
  let target = tree.root_node().child_by_field_name("target").unwrap()
  assert_eq(source_slice(source, target.byte_range()), "x")
}
