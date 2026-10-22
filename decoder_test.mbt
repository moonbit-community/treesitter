///|
test "custom decoders preserve input bytes while decoding node text and points" {
  let decoder = @treesitter.InputDecoder::new(input => (input[0].to_int(), 1))
  let encoding = @treesitter.InputEncoding::Custom(decoder)
  let language = @generate.generate(
    @grammar.Grammar::new("latin1", [
      ("document", Repeat(Symbol("word"))),
      ("word", @grammar.pattern("[\\p{L}]+")),
    ]),
  )
  let parser = @treesitter.Parser::new(language)
  let source = b"caf\xe9\n\xe0"
  let tree = parser.parse_encoded(source, encoding)
  assert_eq(tree.root_node().to_sexp(), "(document (word) (word))")
  assert_eq(tree.root_node().named_child(0).unwrap().text(source), "café")
  assert_eq(tree.text(5, 6), "à")
  assert_eq(tree.root_node().named_child(1).unwrap().start_position(), {
    row: 1,
    column: 0,
  })
  assert_eq(tree.point_at(6), { row: 1, column: 1, })
  assert_eq(
    parser.parse_encoded(source, encoding, old_tree=tree).reused_subtrees,
    1,
  )
  let different = @treesitter.Custom(
    @treesitter.InputDecoder::new(input => (input[0].to_int(), 1)),
  )
  assert_eq(
    parser.parse_encoded(source, different, old_tree=tree).reused_subtrees,
    0,
  )
}

///|
test "custom decoders handle variable byte lengths and malformed returns" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "custom",
      [
        ("document", Repeat(Symbol("scalar"))),
        ("scalar", @grammar.pattern(".")),
      ],
      extras=[],
    ),
  )
  let encoding = @treesitter.Custom(
    @treesitter.InputDecoder::new(input => {
      match input[0].to_int() {
        1 => (0x1f600, 2)
        2 => (0x110000, 1)
        3 => (65, 0)
        _ => (input[0].to_int(), 1)
      }
    }),
  )
  let source = b"\x01\x00\x02\x03\x01"
  let tree = @treesitter.Parser::new(language).parse_encoded(source, encoding)
  assert_eq(
    tree.root_node().children().map(n => (n.start_byte(), n.end_byte())),
    [(0, 2), (2, 3), (3, 4), (4, 5)],
  )
  assert_eq(tree.text(0, 5), "😀���")
}

///|
test "custom decoding supplies scanner columns in Unicode scalars" {
  let decoder = @treesitter.InputDecoder::new(input => {
    if input[0] == 1 {
      (0x1f600, 2)
    } else {
      (input[0].to_int(), 1)
    }
  })
  let language = @generate.generate(
    @grammar.Grammar::new(
      "custom_scanner",
      [("document", Repeat(Symbol("scalar")))],
      externals=[Symbol("scalar")],
      extras=[],
    ),
  )
  let columns : Array[Int32] = []
  let scanner = @treesitter.ExternalScanner::new((input, valid, _) => {
    if !valid[0] || input.eof() {
      return None
    }
    columns.push(input.get_column())
    input.advance()
    Some({ token: 0, state: b"", })
  })
  let tree = @treesitter.Parser::new(language, scanner~).parse_encoded(
    b"\x01\x00x",
    Custom(decoder),
  )
  assert_eq(
    tree.root_node().children().map(n => (n.start_byte(), n.end_byte())),
    [(0, 2), (2, 3)],
  )
  assert_true(columns.contains(0))
  assert_true(columns.contains(1))
}
