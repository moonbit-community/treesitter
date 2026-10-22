///|
test "UTF-16 input preserves byte ranges and decodes node text" {
  let language = @generate.generate(
    @grammar.Grammar::new("unicode_input", [
      ("document", Repeat(Symbol("word"))),
      ("word", @grammar.pattern("[^ \\r\\n]+")),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  let little : Bytes = [0x61, 0, 0x0a, 0, 0x3d, 0xd8, 0, 0xde, 0x62, 0]
  let big : Bytes = [0, 0x61, 0, 0x0a, 0xd8, 0x3d, 0xde, 0, 0, 0x62]
  for (input, encoding) in [(little, @treesitter.Utf16LE), (big, Utf16BE)] {
    let tree = parser.parse_encoded(input, encoding)
    assert_eq(tree.encoding(), encoding)
    assert_eq(tree.root_node().to_sexp(), "(document (word) (word))")
    let word = tree.root_node().named_child(1).unwrap()
    assert_eq(word.start_byte(), 4)
    assert_eq(word.end_byte(), 10)
    assert_eq(word.start_position(), { row: 1, column: 0, })
    assert_eq(word.end_position(), { row: 1, column: 6, })
    assert_eq(word.text(input), "😀b")
    assert_eq(tree.text(0, input.length()), "a\n😀b")
  }
}

///|
test "UTF-16 malformed surrogates and odd final bytes make progress" {
  let parser = @treesitter.Parser::new(
    @generate.generate(
      @grammar.Grammar::new(
        "invalid_utf16",
        [
          ("document", Repeat(Symbol("scalar"))),
          ("scalar", @grammar.pattern(".")),
        ],
        extras=[],
      ),
    ),
  )
  let input : Bytes = [0, 0xd8, 0x61, 0, 0, 0xdc, 0xff]
  let tree = parser.parse_encoded(input, Utf16LE)
  assert_eq(tree.root_node().named_child_count(), 4)
  assert_eq(tree.text(0, input.length()), "�a��")
  assert_eq(tree.root_node().end_byte(), 7)
}

///|
test "UTF-16 scanner columns and included scalar boundaries use original input" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "utf16_scan",
      [("document", Seq([Symbol("word"), Symbol("end")]))],
      externals=[Symbol("word"), Symbol("end")],
      extras=[],
    ),
  )
  let scanner = @treesitter.ExternalScanner::new((input, valid, state) => {
    if valid[0] {
      if input.get_column() != 1 || input.lookahead() != 0x1f600 {
        return None
      }
      input.advance()
      Some({ token: 0, state: b"done", })
    } else if valid[1] && input.eof() && state == b"done" {
      Some({ token: 1, state: b"end", })
    } else {
      None
    }
  })
  let parser = @treesitter.Parser::new(language, scanner~)
  let source : Bytes = [0x78, 0, 0x3d, 0xd8, 0, 0xde]
  let tree = parser.parse_encoded(source, Utf16LE, included_ranges=[
    {
      start_byte: 2,
      end_byte: 6,
      start_point: { row: 0, column: 2, },
      end_point: { row: 0, column: 6, },
    },
  ])
  assert_eq(tree.root_node().start_byte(), 2)
  assert_eq(tree.root_node().child(0).unwrap().text(source), "😀")
}
