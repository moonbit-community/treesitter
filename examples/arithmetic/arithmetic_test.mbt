///|
test "generated MoonBit factory parses without the compiler package" {
  let language = @arithmetic.language()
  let tree = @ts.Parser::new(language).parse_string("1 + 2")
  assert_false(tree.root_node().has_error())
  assert_eq(
    tree.root_node().child_by_field_name("left").unwrap().text(tree.source),
    "1",
  )
}
