///|
fn statements() -> @language.Language raise {
  @generate.generate(
    @grammar.Grammar::new("statements", [
      ("document", Repeat(Symbol("statement"))),
      (
        "statement",
        Seq([
          Field("name", Symbol("identifier")),
          Literal("="),
          Field("value", Symbol("number")),
          Literal(";"),
        ]),
      ),
      ("identifier", @grammar.pattern("[a-z]+")),
      ("number", @grammar.pattern("[0-9]+")),
    ]),
  )
}

///|
test "reused reduction lookahead retains shifted trailing comments" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "lookahead_extras",
      [
        ("document", Repeat(Symbol("statement"))),
        (
          "statement",
          Seq([
            Symbol("identifier"),
            Literal("="),
            Symbol("number"),
            Literal(";"),
          ]),
        ),
        ("identifier", @grammar.pattern("[a-z]+")),
        ("number", @grammar.pattern("[0-9]+")),
        ("comment", @grammar.pattern("//[^\n]*")),
      ],
      extras=[@grammar.pattern("\\s"), Symbol("comment")],
    ),
  )
  let parser = @treesitter.Parser::new(language)
  let original = b"a=1;b=2;//note\nc=3;"
  let old = parser.parse(original)
  old.edit({
    start_byte: 0,
    old_end_byte: 0,
    new_end_byte: 1,
    start_point: { row: 0, column: 0, },
    old_end_point: { row: 0, column: 0, },
    new_end_point: { row: 1, column: 0, },
  })
  let source = b"\na=1;b=2;//note\nc=3;"
  let next = parser.parse(source, old_tree=old)
  let fresh = parser.parse(source)
  assert_true(next.reused_subtrees > 0)
  compare_nodes(next.root_node(), fresh.root_node())
  assert_eq(
    next.root_node().to_sexp(),
    "(document (statement (identifier) (number)) (statement (identifier) (number)) (comment) (statement (identifier) (number)))",
  )
  // A change inside the remembered lookahead dependency invalidates reuse.
  next.edit({
    start_byte: 9,
    old_end_byte: 16,
    new_end_byte: 19,
    start_point: { row: 1, column: 8, },
    old_end_point: { row: 2, column: 0, },
    new_end_point: { row: 2, column: 0, },
  })
  let changed = b"\na=1;b=2;//changed\nc=3;"
  compare_nodes(
    parser.parse(changed, old_tree=next).root_node(),
    parser.parse(changed).root_node(),
  )
}

///|
test "incremental parsing reuses suffix subtrees and agrees with a fresh parse" {
  let parser = @treesitter.Parser::new(statements())
  let old = parser.parse_string("a=1; b=2; c=3; d=4;")
  let original = old.copy()
  let unchanged_id = old.root_node().named_child(2).unwrap().id()
  old.edit({
    start_byte: 2,
    old_end_byte: 3,
    new_end_byte: 5,
    start_point: { row: 0, column: 2, },
    old_end_point: { row: 0, column: 3, },
    new_end_point: { row: 0, column: 5, },
  })
  assert_true(old.root_node().has_changes())
  assert_false(original.root_node().has_changes())
  let source = b"a=100; b=2; c=3; d=4;"
  let incremental = parser.parse(source, old_tree=old)
  let fresh = parser.parse(source)
  assert_eq(incremental.root_node().to_sexp(), fresh.root_node().to_sexp())
  assert_eq(incremental.root_node().range(), fresh.root_node().range())
  assert_true(incremental.reused_subtrees > 0)
  assert_true(incremental.parse_steps < fresh.parse_steps)
  assert_eq(incremental.root_node().named_child(2).unwrap().id(), unchanged_id)
  for i in 0..<fresh.root_node().named_child_count() {
    assert_eq(
      incremental.root_node().named_child(i).unwrap().range(),
      fresh.root_node().named_child(i).unwrap().range(),
    )
  }
  assert_true(old.changed_ranges(incremental).is_empty())
}

///|
test "successive edits preserve byte and point positions in reused nodes" {
  let parser = @treesitter.Parser::new(statements())
  let mut tree = parser.parse_string("a=1;\nb=2;\nc=3;")
  tree.edit({
    start_byte: 2,
    old_end_byte: 3,
    new_end_byte: 5,
    start_point: { row: 0, column: 2, },
    old_end_point: { row: 0, column: 3, },
    new_end_point: { row: 1, column: 2, },
  })
  let source = b"a=\n10;\nb=2;\nc=3;"
  tree = parser.parse(source, old_tree=tree)
  let fresh = parser.parse(source)
  assert_eq(tree.root_node().to_sexp(), fresh.root_node().to_sexp())
  assert_eq(
    tree.root_node().named_child(2).unwrap().range(),
    fresh.root_node().named_child(2).unwrap().range(),
  )
  tree.edit({
    start_byte: 4,
    old_end_byte: 5,
    new_end_byte: 6,
    start_point: { row: 1, column: 1, },
    old_end_point: { row: 1, column: 2, },
    new_end_point: { row: 1, column: 3, },
  })
  let second = parser.parse(b"a=\n100;\nb=2;\nc=3;", old_tree=tree)
  let fresh = parser.parse(b"a=\n100;\nb=2;\nc=3;")
  assert_eq(second.root_node().to_sexp(), fresh.root_node().to_sexp())
  assert_eq(
    second.root_node().named_child(2).unwrap().range(),
    fresh.root_node().named_child(2).unwrap().range(),
  )
  assert_true(second.reused_subtrees > 0)
}

///|
test "reuse checks source content and language identity" {
  let language = statements()
  let parser = @treesitter.Parser::new(language)
  let old = parser.parse(b"a=1; b=2;")
  let same = parser.parse(b"a=1; b=2;", old_tree=old)
  assert_eq(same.parse_steps, 0)
  assert_eq(same.reused_subtrees, 1)
  let changed_without_edit = parser.parse(b"a=123; b=2;", old_tree=old)
  assert_eq(changed_without_edit.reused_subtrees, 0)
  let other = @treesitter.Parser::new(statements()).parse(
    b"a=1; b=2;",
    old_tree=old,
  )
  assert_eq(other.reused_subtrees, 0)
}

///|
fn compare_nodes(
  actual : @treesitter.Node,
  expected : @treesitter.Node,
) -> Unit raise {
  assert_eq(actual.kind(), expected.kind())
  assert_eq(actual.range(), expected.range())
  assert_eq(actual.is_named(), expected.is_named())
  assert_eq(actual.is_missing(), expected.is_missing())
  assert_eq(actual.is_extra(), expected.is_extra())
  assert_eq(actual.child_count(), expected.child_count())
  for i in 0..<actual.child_count() {
    assert_eq(actual.field_name_for_child(i), expected.field_name_for_child(i))
    compare_nodes(actual.child(i).unwrap(), expected.child(i).unwrap())
  }
}

///|
test "forty successive growth and shrink edits match every fresh node" {
  let parser = @treesitter.Parser::new(statements())
  let mut tree = parser.parse_string("a=1; b=2; c=3;")
  let mut length = 1
  for i in 1..<=40 {
    let number = if i % 2 == 0 { "7" } else { "\{i * 123}" }
    tree.edit({
      start_byte: 2,
      old_end_byte: 2 + length,
      new_end_byte: 2 + number.length(),
      start_point: { row: 0, column: 2, },
      old_end_point: { row: 0, column: 2 + length, },
      new_end_point: { row: 0, column: 2 + number.length(), },
    })
    let source = @utf8.encode("a=\{number}; b=2; c=3;")
    let next = parser.parse(source, old_tree=tree)
    compare_nodes(next.root_node(), parser.parse(source).root_node())
    assert_true(next.reused_subtrees > 0)
    tree = next
    length = number.length()
  }
}

///|
test "inserting into an empty root preserves a valid edited range" {
  let language = @generate.generate(
    @grammar.Grammar::new("empty_edit", [("root", Repeat(Literal("a")))]),
  )
  let parser = @treesitter.Parser::new(language)
  let tree = parser.parse_string("")
  tree.edit({
    start_byte: 0,
    old_end_byte: 0,
    new_end_byte: 1,
    start_point: { row: 0, column: 0, },
    old_end_point: { row: 0, column: 0, },
    new_end_point: { row: 0, column: 1, },
  })
  assert_eq(tree.root_node().start_byte(), 1)
  assert_eq(tree.root_node().end_byte(), 1)
  assert_eq(
    parser.parse(b"a", old_tree=tree).root_node().to_sexp(),
    parser.parse(b"a").root_node().to_sexp(),
  )
}

///|
test "incremental parsing reuses prefixes outside lexical lookahead dependencies" {
  let parser = @treesitter.Parser::new(statements())
  let tree = parser.parse(b"a=1; b=2; c=3; d=4;")
  let first_id = tree.root_node().child(0).unwrap().id()
  tree.edit({
    start_byte: 17,
    old_end_byte: 18,
    new_end_byte: 20,
    start_point: { row: 0, column: 17, },
    old_end_point: { row: 0, column: 18, },
    new_end_point: { row: 0, column: 20, },
  })
  let source = b"a=1; b=2; c=3; d=400;"
  let next = parser.parse(source, old_tree=tree)
  let fresh = parser.parse(source)
  compare_nodes(next.root_node(), fresh.root_node())
  assert_eq(next.root_node().child(0).unwrap().id(), first_id)
  assert_true(next.reused_subtrees > 0)
  assert_true(next.parse_steps < fresh.parse_steps)
}

///|
test "lookahead and EOF changes invalidate otherwise unchanged prefix nodes" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "lookahead_dependency",
      [
        (
          "document",
          Seq([Symbol("head"), Choice([Literal("b"), Literal("bc")])]),
        ),
        ("head", Seq([Literal("a")])),
      ],
      extras=[],
    ),
  )
  let parser = @treesitter.Parser::new(language)
  let old = parser.parse(b"ab")
  old.edit({
    start_byte: 2,
    old_end_byte: 2,
    new_end_byte: 3,
    start_point: { row: 0, column: 2, },
    old_end_point: { row: 0, column: 2, },
    new_end_point: { row: 0, column: 3, },
  })
  let next = parser.parse(b"abc", old_tree=old)
  compare_nodes(next.root_node(), parser.parse(b"abc").root_node())
  assert_eq(next.root_node().child(1).unwrap().kind(), "bc")
}

///|
test "failed long-token lookahead invalidates a distant prefix after an edit" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "failed_lookahead",
      [
        (
          "document",
          Seq([
            Symbol("head"),
            Repeat(Literal("b")),
            Choice([Literal("x"), Literal("y"), Blank]),
          ]),
        ),
        ("head", Choice([Literal("a"), Token(Literal("abbbx"))])),
      ],
      extras=[],
    ),
  )
  let parser = @treesitter.Parser::new(language)
  let old = parser.parse(b"abbby")
  old.edit({
    start_byte: 4,
    old_end_byte: 5,
    new_end_byte: 5,
    start_point: { row: 0, column: 4, },
    old_end_point: { row: 0, column: 5, },
    new_end_point: { row: 0, column: 5, },
  })
  let next = parser.parse(b"abbbx", old_tree=old)
  compare_nodes(next.root_node(), parser.parse(b"abbbx").root_node())
  assert_eq(
    next.root_node().child(0).unwrap().child(0).unwrap().kind(),
    "abbbx",
  )
}

///|
test "deterministic regions of ambiguous languages can be reused" {
  let language = @generate.generate(
    @grammar.Grammar::new(
      "glr_list",
      [
        ("document", Repeat(Symbol("statement"))),
        ("statement", Seq([Symbol("expression"), Literal(";")])),
        ("expression", Choice([Symbol("number"), Symbol("binary")])),
        (
          "binary",
          Seq([Symbol("expression"), Literal("+"), Symbol("expression")]),
        ),
        ("number", @grammar.pattern("[0-9]+")),
      ],
      conflicts=[["binary"]],
    ),
  )
  let parser = @treesitter.Parser::new(language)
  let old_source = "1;2;3;4+5+6;7;8;9;"
  let old = parser.parse_string(old_source)
  old.edit({
    start_byte: 0,
    old_end_byte: 1,
    new_end_byte: 1,
    start_point: { row: 0, column: 0, },
    old_end_point: { row: 0, column: 1, },
    new_end_point: { row: 0, column: 1, },
  })
  let source = b"0;2;3;4+5+6;7;8;9;"
  let next = parser.parse(source, old_tree=old)
  let fresh = parser.parse(source)
  assert_eq(next.root_node().to_sexp(), fresh.root_node().to_sexp())
  assert_true(next.reused_subtrees > 0)
  assert_true(next.parse_steps < fresh.parse_steps)
  let mut tree = next
  let mut source = source
  let mut random = 17U
  for _ in 0..<160 {
    random = random * 1664525U + 1013904223U
    let position = (random % source.length().reinterpret_as_uint()).reinterpret_as_int()
    let bytes = source.to_array()
    bytes[position] = [b'1', b'2', b'+', b';'][(random >> 16).reinterpret_as_int() %
      4]
    let changed = Bytes::from_array(bytes)
    tree.edit({
      start_byte: position,
      old_end_byte: position + 1,
      new_end_byte: position + 1,
      start_point: { row: 0, column: position, },
      old_end_point: { row: 0, column: position + 1, },
      new_end_point: { row: 0, column: position + 1, },
    })
    let fresh = parser.parse(changed) catch {
      e => fail("fresh \{changed}: \{Repr(e)}")
    }
    let incremental = parser.parse(changed, old_tree=tree) catch {
      e => fail("incremental \{changed} failed: \{Repr(e)}")
    }
    compare_nodes(incremental.root_node(), fresh.root_node())
    tree = incremental
    source = changed
  }
}
