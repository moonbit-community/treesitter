///|
// JSON's document rule accepts a sequence of values. Keep this fixture small
// while preserving the public grammar's trees for these number/array inputs.
fn root_query_language() -> @language.Language raise {
  @generate.generate(
    @grammar.Grammar::new("query_roots", [
      ("document", Repeat(Symbol("_value"))),
      (
        "_value",
        Choice([
          Symbol("number"),
          Symbol("array"),
          Symbol("true"),
          Symbol("false"),
        ]),
      ),
      ("number", @grammar.pattern("[0-9]+")),
      ("true", Literal("true")),
      ("false", Literal("false")),
      (
        "array",
        Seq([
          Literal("["),
          Choice([
            Blank,
            Seq([
              Symbol("_value"),
              Repeat(Seq([Literal(","), Symbol("_value")])),
            ]),
          ]),
          Literal("]"),
        ]),
      ),
    ]),
  )
}

///|
fn root_query_output(
  source : String,
  pattern : String,
  start~ : Int32 = 0,
  end~ : Int32 = 0,
) -> String raise {
  let language = root_query_language()
  let tree = @ts.Parser::new(language).parse_string(source)
  assert_false(tree.root_node().has_error())
  let query = @query.Query::new(language, pattern)
  query
  .matches(tree.root_node(), tree.source, start_byte=start, end_byte=end)
  .map(m => {
    m.pattern_index.to_string() +
    m.captures
    .map(c => " \{c.name}:\{c.node.start_byte()}..\{c.node.end_byte()}")
    .join("")
  })
  .join("\n")
}

///|
test "root quantifier metadata and capture cursor order" {
  let language = root_query_language()
  let tree = @ts.Parser::new(language).parse_string("1 2 3")
  let query = @query.Query::new(
    language, "(number)+ @n (number)? @maybe (number)* @many",
  )
  assert_eq(query.capture_quantifier(0, 0), Some(OneOrMore))
  assert_eq(query.capture_quantifier(1, 1), Some(ZeroOrOne))
  assert_eq(query.capture_quantifier(2, 2), Some(ZeroOrMore))
  let cursor = query.capture_cursor(tree.root_node(), tree.source)
  let captures = []
  while cursor.next_capture() is Some((matched, index)) {
    let capture = matched.captures[index]
    captures.push((capture.name, capture.node.start_byte()))
  }
  assert_eq(captures, [
    ("n", 0),
    ("maybe", 0),
    ("many", 0),
    ("n", 2),
    ("maybe", 2),
    ("many", 2),
    ("n", 4),
    ("maybe", 4),
    ("many", 4),
  ])
  let ranged = query.capture_cursor(
    tree.root_node(),
    tree.source,
    start_byte=3,
    end_byte=5,
  )
  let names = []
  while ranged.next_capture() is Some((matched, index)) {
    let capture = matched.captures[index]
    assert_eq(capture.node.start_byte(), 4)
    names.push(capture.name)
  }
  assert_eq(names, ["n", "maybe", "many"])
}

///|
test "root repetitions obey cursor limits cancellation and disabled patterns" {
  let language = root_query_language()
  let tree = @ts.Parser::new(language).parse_string("1 2 3")
  let query = @query.Query::new(language, "(number)+ @n _ @v")
  let cursor = query.cursor(tree.root_node(), tree.source)
  assert_eq(cursor.next_match().unwrap().pattern_index, 1)
  assert_eq(cursor.next_match().unwrap().pattern_index, 1)
  assert_true(query.disable_pattern(0))
  while cursor.next_match() is Some(matched) {
    assert_eq(matched.pattern_index, 1)
  }
  let repeated = @query.Query::new(language, "(number)+ @n")
  assert_true(
    repeated
    .cursor(tree.root_node(), tree.source, max_start_depth=0)
    .next_match()
    is None,
  )
  try
    repeated
    .cursor(tree.root_node(), tree.source, cancelled=() => true)
    .next_match()
  catch {
    Cancelled => ()
    _ => fail("unexpected query error")
  } noraise {
    _ => fail("ignored cancellation")
  }
  try repeated.matches(tree.root_node(), tree.source, max_steps=2) catch {
    MatchLimit => ()
    _ => fail("unexpected query error")
  } noraise {
    _ => fail("ignored work limit")
  }
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "root repetitions complete after descendants" {
  inspect(
    root_query_output("1 2 3", "(number)+ @n _ @v"),
    content=(
      #|1 v:0..5
      #|1 v:0..1
      #|1 v:2..3
      #|1 v:4..5
      #|0 n:0..1 n:2..3 n:4..5
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "optional roots emit concrete and empty matches" {
  inspect(
    root_query_output("[1,2]", "(number)? @n _ @v"),
    content=(
      #|1 v:0..5
      #|0
      #|1 v:0..5
      #|0
      #|1 v:0..1
      #|0
      #|0 n:1..2
      #|1 v:1..2
      #|0
      #|1 v:2..3
      #|0
      #|0 n:3..4
      #|1 v:3..4
      #|0
      #|1 v:4..5
      #|0
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "zero or more roots stop at concrete separators" {
  inspect(
    root_query_output("[1,2]", "(number)* @n _ @v"),
    content=(
      #|1 v:0..5
      #|0
      #|1 v:0..5
      #|0
      #|1 v:0..1
      #|0
      #|1 v:1..2
      #|0
      #|0 n:1..2
      #|1 v:2..3
      #|0
      #|1 v:3..4
      #|0
      #|0 n:3..4
      #|1 v:4..5
      #|0
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "nested repeated roots finish from inner to outer" {
  inspect(
    root_query_output("[[1],[2]]", "(array)+ @a _ @v"),
    content=(
      #|1 v:0..9
      #|1 v:0..9
      #|1 v:0..1
      #|1 v:1..4
      #|1 v:1..2
      #|1 v:2..3
      #|1 v:3..4
      #|0 a:1..4
      #|1 v:4..5
      #|1 v:5..8
      #|1 v:5..6
      #|1 v:6..7
      #|1 v:7..8
      #|0 a:5..8
      #|1 v:8..9
      #|0 a:0..9
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "root alternatives retain all capture paths" {
  inspect(
    root_query_output("1 2", "[(number) @a (number) @b]+ _ @v"),
    content=(
      #|1 v:0..3
      #|1 v:0..1
      #|1 v:2..3
      #|0 b:0..1 a:2..3
      #|0 b:0..1 b:2..3
      #|0 a:0..1 a:2..3
      #|0 a:0..1 b:2..3
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "root groups retain maximal overlapping capture sequences" {
  inspect(
    root_query_output("1 2 3 4 5", "((number) @a (number) @b)+ _ @v"),
    content=(
      #|1 v:0..9
      #|1 v:0..1
      #|1 v:2..3
      #|1 v:4..5
      #|1 v:6..7
      #|1 v:8..9
      #|0 a:0..1 b:2..3 a:4..5 b:6..7
      #|0 a:0..1 b:2..3 a:4..5 b:8..9
      #|0 a:0..1 b:4..5 a:6..7 b:8..9
      #|0 a:2..3 b:4..5 a:6..7 b:8..9
      #|0 a:2..3 b:6..7
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "optional root groups capture the first sibling" {
  inspect(
    root_query_output("[1,2,3]", "((number) @a (number) @b)? @group _ @v"),
    content=(
      #|1 v:0..7
      #|0
      #|1 v:0..7
      #|0
      #|1 v:0..1
      #|0
      #|1 v:1..2
      #|0
      #|1 v:2..3
      #|0
      #|0 a:1..2 group:1..2 b:3..4
      #|1 v:3..4
      #|0
      #|1 v:4..5
      #|0
      #|0 a:1..2 group:1..2 b:5..6
      #|0 a:3..4 group:3..4 b:5..6
      #|1 v:5..6
      #|0
      #|1 v:6..7
      #|0
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "root groups without captures coalesce at their final boundary" {
  inspect(
    root_query_output("1 2 true 3 4", "((number) (number))+ _ @v"),
    content=(
      #|1 v:0..12
      #|1 v:0..1
      #|1 v:2..3
      #|1 v:4..8
      #|1 v:9..10
      #|1 v:11..12
      #|0
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "optional repeated groups finish after their last node" {
  inspect(
    root_query_output("1 2 3", "((number)+ @n)? _ @v"),
    content=(
      #|1 v:0..5
      #|0
      #|1 v:0..1
      #|0
      #|1 v:2..3
      #|0
      #|1 v:4..5
      #|0
      #|0 n:0..1 n:2..3 n:4..5
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "repeated roots include siblings outside an intersecting range" {
  inspect(
    root_query_output("1 2 3 4 5", "(number)+ @n _ @v", start=3, end=5),
    content=(
      #|1 v:0..9
      #|1 v:4..5
      #|0 n:0..1 n:2..3 n:4..5 n:6..7 n:8..9
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "optional roots skip nodes before the byte range" {
  inspect(
    root_query_output("1 2 3 4 5", "(number)? @n _ @v", start=3, end=5),
    content=(
      #|1 v:0..9
      #|0
      #|0 n:4..5
      #|1 v:4..5
      #|0
      #|0
      #|0
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "empty execution root preserves upstream repeated matches" {
  inspect(
    root_query_output("", "(document)+ @root _ @v"),
    content=(
      #|0 root:0..0
      #|1 v:0..0
    ),
  )
}

///|
// Frozen against the pinned upstream C query cursor and JSON grammar.
test "empty execution root preserves upstream optional paths" {
  inspect(
    root_query_output("", "(document)* @root _ @v"),
    content=(
      #|0 root:0..0
      #|0 root:0..0
      #|1 v:0..0
      #|0
    ),
  )
}
