///|
test "field ids follow sorted names through hidden rules and serialization" {
  let grammar = @grammar.Grammar::new("fields", [
    ("document", Symbol("_pair")),
    (
      "_pair",
      Seq([
        Field("zeta", Literal("a")),
        Field("alpha", Literal("b")),
        Field("zeta", Literal("c")),
        Field("\u{1F600}", Literal("d")),
        Field("\u{E000}", Literal("e")),
      ]),
    ),
  ])
  let language = @generate.generate(grammar)
  assert_eq(language.field_count(), 4)
  assert_eq(language.field_id("alpha"), Some(1))
  assert_eq(language.field_id("zeta"), Some(2))
  assert_eq(language.field_id("\u{E000}"), Some(3))
  assert_eq(language.field_id("\u{1F600}"), Some(4))
  assert_eq(language.field_id("absent"), None)
  assert_eq(language.field_name(-2147483648), None)
  assert_eq(language.field_name(0), None)
  assert_eq(language.field_name(5), None)
  let restored = @language.Language::parse(Json(language).stringify())
  for i in 1..<=4 {
    assert_eq(restored.field_name(i), language.field_name(i))
  }
  let tree = @treesitter.Parser::new(restored).parse_string("abcde")
  let root = tree.root_node()
  assert_eq(root.language().name, "fields")
  assert_eq(root.child_by_field_id(1).unwrap().kind(), "b")
  assert_true(root.child_by_field_id(0) is None)
  assert_eq(root.children_by_field_id(2).map(n => n.kind()), ["a", "c"])
  assert_eq(root.children_by_field_id(9).length(), 0)
  let cursor = root.walk()
  assert_eq(cursor.field_id(), None)
  assert_true(cursor.goto_first_child())
  assert_eq(cursor.field_id(), Some(2))
  assert_true(cursor.goto_next_sibling())
  assert_eq(cursor.field_id(), Some(1))
  let copy = tree.copy()
  assert_eq(copy.root_node().language().field_name(2), Some("zeta"))
}
