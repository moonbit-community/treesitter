///|
test "optional groups retain maximal unique completions" {
  // Outputs frozen from upstream, including completions ordered by their final
  // sibling rather than the first captured sibling.
  inspect(
    root_query_output("[1,2,3,4]", "(array ((number)? @n (number)))"),
    content=(
      #|0 n:1..2
      #|0 n:3..4
      #|0 n:5..6
    ),
  )
  inspect(
    root_query_output("[1,2,3,4]", "(array ((number) @n \",\"?)+)"),
    content="0 n:1..2 n:3..4 n:5..6 n:7..8",
  )
  inspect(
    root_query_output("[1,2,3,4]", "(array (number) @a (number) @b)"),
    content=(
      #|0 a:1..2 b:3..4
      #|0 a:1..2 b:5..6
      #|0 a:3..4 b:5..6
      #|0 a:1..2 b:7..8
      #|0 a:3..4 b:7..8
      #|0 a:5..6 b:7..8
    ),
  )
  inspect(
    root_query_output("[1,2,3,4]", "(array [(number) @n (number) @n])"),
    content=(
      #|0 n:1..2
      #|0 n:3..4
      #|0 n:5..6
      #|0 n:7..8
    ),
  )
  inspect(
    root_query_output("[1,2,3,4]", "(array (number) (number))"),
    content="0",
  )
}

///|
test "containing ranges apply to empty optional matches" {
  let language = root_query_language()
  let tree = @ts.Parser::new(language).parse_string("[1,2]")
  for (pattern, counts) in [("(number)? @n", [1, 0]), ("(number)* @n", [0, 1])] {
    let query = @query.Query::new(language, pattern)
    for
      matches in [
        query.matches(
          tree.root_node(),
          tree.source,
          containing_byte_range=(1, 2),
        ),
        query.matches(
          tree.root_node(),
          tree.source,
          containing_point_range=(
            { row: 0, column: 1, },
            { row: 0, column: 2, },
          ),
        ),
      ] {
      assert_eq(matches.map(m => m.captures.length()), counts)
      for matched in matches {
        for capture in matched.captures {
          assert_eq(capture.node.text(tree.source), "1")
        }
      }
    }
  }
  let tree = @ts.Parser::new(language).parse_string("1 2 3")
  let query = @query.Query::new(language, "((number) @a (number) @b)?")
  let matches = query.matches(
    tree.root_node(),
    tree.source,
    containing_byte_range=(2, 5),
  )
  assert_eq(matches.map(m => m.captures.map(c => c.node.text(tree.source))), [
    [],
    ["2", "3"],
    [],
  ])
}

///|
test "nested matches finish at their final descendant traversal event" {
  inspect(
    root_query_output("[[1]]", "(array (array (number) @n)) @a _ @v"),
    content=(
      #|1 v:0..5
      #|1 v:0..5
      #|1 v:0..1
      #|1 v:1..4
      #|1 v:1..2
      #|0 a:0..5 n:2..3
      #|1 v:2..3
      #|1 v:3..4
      #|1 v:4..5
    ),
  )
  inspect(
    root_query_output("[1,2]", "(array (number)+ @n) _ @v"),
    content=(
      #|1 v:0..5
      #|1 v:0..5
      #|1 v:0..1
      #|1 v:1..2
      #|0 n:1..2
      #|1 v:2..3
      #|1 v:3..4
      #|0 n:3..4
      #|1 v:4..5
    ),
  )
}

///|
test "range and start depth limits still finish active descendant matches" {
  let language = root_query_language()
  let tree = @ts.Parser::new(language).parse_string("[[1]]")
  let query = @query.Query::new(
    language, "(document (array (array (number) @n))) (number) @other",
  )
  for
    cursor in [
      query.cursor(tree.root_node(), tree.source, max_start_depth=0),
      query.cursor(
        tree.root_node(),
        tree.source,
        start_byte=0,
        end_byte=1,
        max_start_depth=0,
      ),
    ] {
    let matched = cursor.next_match().unwrap()
    assert_eq(matched.pattern_index, 0)
    assert_eq(matched.captures.map(c => (c.name, c.node.text(tree.source))), [
      ("n", "1"),
    ])
    assert_true(cursor.next_match() is None)
  }
  let captures = query.capture_cursor(
    tree.root_node(),
    tree.source,
    max_start_depth=0,
  )
  let (matched, index) = captures.next_capture().unwrap()
  assert_eq(matched.captures[index].name, "n")
  assert_true(captures.next_capture() is None)
}

///|
test "optional branches wait only while a longer completion remains possible" {
  inspect(
    root_query_output("1 2", "(document (number) @n (array)? @a) _ @v"),
    content=(
      #|1 v:0..3
      #|1 v:0..1
      #|0 n:0..1
      #|1 v:2..3
      #|0 n:2..3
    ),
  )
  inspect(
    root_query_output("[1]", "(array ((number)? @n (number))) _ @v"),
    content=(
      #|1 v:0..3
      #|1 v:0..3
      #|1 v:0..1
      #|1 v:1..2
      #|0
      #|1 v:2..3
    ),
  )
  inspect(
    root_query_output("[1]", "(array (number)? @a (number) @b) _ @v"),
    content=(
      #|1 v:0..3
      #|1 v:0..3
      #|1 v:0..1
      #|0 b:1..2
      #|1 v:1..2
      #|1 v:2..3
    ),
  )
  inspect(
    root_query_output("", "(document (number)? @n) _ @v"),
    content=(
      #|1 v:0..0
      #|0
    ),
  )
}

///|
test "uncaptured separators do not create skipped repetition paths" {
  inspect(
    root_query_output("[1,[2],3]", "(array ((number) @n \",\"?)+)"),
    content=(
      #|0 n:1..2
      #|0 n:4..5
      #|0 n:7..8
    ),
  )
  inspect(
    root_query_output("[]", "(array ((number)?)*) _ @v"),
    content=(
      #|1 v:0..2
      #|1 v:0..2
      #|1 v:0..1
      #|0
      #|1 v:1..2
    ),
  )
}

///|
test "anchored optional paths stop at the first named mismatch" {
  inspect(
    root_query_output("[1,true]", "(array (number) @a . (number)? @b) _ @v"),
    content=(
      #|1 v:0..8
      #|1 v:0..8
      #|1 v:0..1
      #|1 v:1..2
      #|1 v:2..3
      #|0 a:1..2
      #|1 v:3..7
      #|1 v:7..8
    ),
  )
  inspect(
    root_query_output("[1,[2],3]", "(array (number)? @a . (number) @b)"),
    content=(
      #|0 b:1..2
      #|0 b:4..5
    ),
  )
  inspect(
    root_query_output("[1,[2],3]", "(array (number)* @a . (number) @b)"),
    content=(
      #|0 b:1..2
      #|0 b:4..5
    ),
  )
}

///|
test "root groups can restart after an anchored optional prefix fails" {
  // Frozen C outputs: a top-level group has fresh entries at later siblings;
  // a child sequence within the document remains bound to its original root.
  inspect(
    root_query_output("true [1] 2", "((true)* @a . (number) @b)"),
    content=(
      #|0 b:6..7
      #|0 b:9..10
    ),
  )
  inspect(
    root_query_output("true [1] 2", "(document (true)* @a . (number) @b)"),
    content="",
  )
}
