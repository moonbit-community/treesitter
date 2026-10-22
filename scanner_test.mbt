///|
fn quoted_scanner() -> @treesitter.ExternalScanner {
  @treesitter.ExternalScanner::new((input, valid, state) => {
    if valid[0] && input.lookahead() == 39 {
      input.advance()
      return Some({ token: 0, state: b"quote", })
    }
    if valid[1] && state == b"quote" {
      while !input.eof() && input.lookahead() != 39 {
        input.advance()
      }
      input.mark_end()
      // Look past the token without consuming the closing delimiter.
      if !input.eof() {
        input.advance()
      }
      return Some({ token: 1, state, })
    }
    if valid[2] && state == b"quote" && input.lookahead() == 39 {
      input.advance()
      return Some({ token: 2, state: b"closed", })
    }
    None
  })
}

///|
fn quoted_language() -> @language.Language raise {
  @generate.generate(
    @grammar.Grammar::new(
      "quoted",
      [("document", Seq([Symbol("open"), Symbol("content"), Symbol("close")]))],
      externals=[Symbol("open"), Symbol("content"), Symbol("close")],
      extras=[],
    ),
  )
}

///|
test "external scanner snapshots delimiters mark_end and language roundtrip" {
  let language = quoted_language()
  assert_eq(@language.Language::parse(Json(language).stringify()), language)
  let parser = @treesitter.Parser::new(language, scanner=quoted_scanner())
  let tree = parser.parse(b"'abc'")
  assert_eq(tree.root_node().to_sexp(), "(document (open) (content) (close))")
  assert_eq(tree.root_node().named_child(1).unwrap().text(tree.source), "abc")
  assert_eq(tree.external_scanner_state(), b"closed")
  tree.edit({
    start_byte: 1,
    old_end_byte: 4,
    new_end_byte: 5,
    start_point: { row: 0, column: 1, },
    old_end_point: { row: 0, column: 4, },
    new_end_point: { row: 0, column: 5, },
  })
  let next = parser.parse(b"'abcd'", old_tree=tree)
  assert_eq(
    next.root_node().to_sexp(),
    parser.parse(b"'abcd'").root_node().to_sexp(),
  )
  assert_eq(next.reused_subtrees, 0)
  assert_eq(next.external_scanner_state(), b"closed")
}

///|
test "external scanner zero width tokens progress through serialized state" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "zero_width",
      [
        ("document", Seq([Symbol("open"), Symbol("word"), Symbol("close")])),
        ("word", @grammar.pattern("[a-z]+")),
      ],
      externals=[Symbol("open"), Symbol("close")],
      extras=[],
    ),
  )
  let scanner = @treesitter.ExternalScanner::new((input, valid, state) => {
    if valid[0] && state == b"" {
      Some({ token: 0, state: b"open", })
    } else if valid[1] && state == b"open" && input.eof() {
      Some({ token: 1, state: b"closed", })
    } else {
      None
    }
  })
  let tree = @treesitter.Parser::new(language, scanner~).parse(b"word")
  assert_true(!tree.root_node().has_error())
  assert_eq(tree.root_node().child(0).unwrap().start_byte(), 0)
  assert_eq(tree.root_node().child(0).unwrap().end_byte(), 0)
  assert_eq(tree.root_node().child(2).unwrap().start_byte(), 4)
  assert_eq(tree.external_scanner_state(), b"closed")
}

///|
test "scanner rejection restores cursor and invalid result is diagnosed" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "fallback",
      [("document", Symbol("word")), ("word", Literal("abc"))],
      externals=[Symbol("word")],
      extras=[],
    ),
  )
  let scanner = @treesitter.ExternalScanner::new((input, _, _) => {
    while !input.eof() {
      input.advance()
    }
    None
  })
  let tree = @treesitter.Parser::new(language, scanner~).parse(b"abc")
  assert_true(!tree.root_node().has_error())
  for
    scanner in [
      None,
      Some(
        @treesitter.ExternalScanner::new((_, _, _) => {
          Some({ token: 9, state: b"", })
        }),
      ),
    ] {
    try @treesitter.Parser::new(language, scanner?).parse(b"abc") catch {
      @treesitter.ScannerError(_) => ()
      error => fail("unexpected: \{error}")
    } noraise {
      _ => fail("accepted missing or invalid scanner")
    }
  }
}

///|
test "scanner coordinates use Unicode columns and original included ranges" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "columns",
      [("document", Symbol("word"))],
      externals=[Symbol("word")],
      extras=[],
    ),
  )
  let observations = []
  let scanner = @treesitter.ExternalScanner::new((input, valid, state) => {
    if !valid[0] || input.eof() {
      return None
    }
    while !input.eof() {
      observations.push(
        (input.get_column(), input.is_at_included_range_start()),
      )
      input.advance()
    }
    Some({ token: 0, state, })
  })
  let tree = @treesitter.Parser::new(language, scanner~).parse(
    @utf8.encode("é:a<>b"),
    included_ranges=[
      {
        start_byte: 3,
        end_byte: 4,
        start_point: { row: 0, column: 3, },
        end_point: { row: 0, column: 4, },
      },
      {
        start_byte: 6,
        end_byte: 7,
        start_point: { row: 0, column: 6, },
        end_point: { row: 0, column: 7, },
      },
    ],
  )
  assert_eq(observations, [(2, true), (5, true)])
  assert_eq(tree.root_node().start_byte(), 3)
  assert_eq(tree.root_node().end_byte(), 7)
}
