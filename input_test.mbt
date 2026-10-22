///|
test "callback input tolerates split UTF-8 and reports byte points" {
  let language = @generate.generate(
    @grammar.Grammar::new("input", [
      ("root", Repeat(Symbol("word"))),
      ("word", @grammar.pattern("\\p{L}+")),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  let source = b"\xe7\x95\x8c\nalpha"
  let positions = []
  let tree = parser.parse_with((offset, point) => {
    positions.push((offset, point.row, point.column))
    if offset == source.length() {
      b""
    } else {
      source[offset:offset + 1].to_owned()
    }
  })
  assert_eq(
    tree.root_node().to_sexp(),
    parser.parse(source).root_node().to_sexp(),
  )
  assert_eq(positions[3], (3, 0, 3))
  assert_eq(positions[4], (4, 1, 0))
  assert_eq(tree.root_node().named_child(0).unwrap().end_byte(), 3)
  try parser.parse_with((_, _) => b"a", max_input_bytes=2) catch {
    ParseLimit(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("unbounded reader")
  }
}
