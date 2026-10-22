///|
test "mbtx generated JSON language parses nesting escapes and Unicode" {
  let parser = @ts.Parser::new(@json.language())
  for
    source in [
      "{}", "[]", "true", "null", "false", "-2.5e+3", "{\"文\": [0, 1, {\"escaped\": \"\\\"\\u4e2d\\n\"}]}",
    ] {
    let tree = parser.parse_string(source)
    assert_false(tree.root_node().has_error(), msg=source)
    assert_eq(tree.root_node().text(tree.source), source)
  }
  let tree = parser.parse_string("{\"a\": 12}")
  let pair = tree.root_node().named_child(0).unwrap().named_child(0).unwrap()
  assert_eq(pair.child_by_field_name("key").unwrap().text(tree.source), "\"a\"")
  assert_eq(pair.child_by_field_name("value").unwrap().text(tree.source), "12")
}

///|
test "JSON language recovers visibly from invalid input" {
  let parser = @ts.Parser::new(@json.language())
  for source in ["[1,]", "{\"a\" 12}", "01", "[true false]"] {
    assert_true(parser.parse_string(source).root_node().has_error(), msg=source)
  }
}
