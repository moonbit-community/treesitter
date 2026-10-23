///|
// The first case mirrors upstream test_query_alternation_with_outer_quantifier
// (crates/cli/src/tests/query_test.rs), using the small JSON-shaped grammar.
// Outputs are frozen from the pinned C runtime.
test "outer repetition keeps nullable group continuations and coalesces paths" {
  assert_eq(
    root_query_output("1 2 3 true", "([(number) (true)] (_)?)+ @capture _ @v"),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|1 v:2..3
      #|1 v:4..5
      #|1 v:6..10
      #|0 capture:0..1 capture:2..3 capture:4..5 capture:6..10
    ),
  )
  assert_eq(
    root_query_output("1 2 true 3", "[(number)+ @x (true) @x]+ _ @v"),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|1 v:2..3
      #|1 v:4..8
      #|1 v:9..10
      #|0 x:0..1 x:2..3 x:4..8 x:9..10
    ),
  )
  assert_eq(
    root_query_output("true 1 false 2", "[(number)* @x (true) @x]+ _ @v"),
    (
      #|1 v:0..14
      #|1 v:0..4
      #|1 v:5..6
      #|0 x:0..4 x:5..6
      #|1 v:7..12
      #|1 v:13..14
      #|0 x:13..14
    ),
  )
}

///|
test "nested root repetitions avoid enumerating equivalent partitions" {
  let language = root_query_language()
  let tree = @ts.Parser::new(language).parse_string(
    Array::make(80, "1").join(" "),
  )
  for
    source in [
      "((number)+ @n)+", "[(number)+ @n (true)]+", "([(number) (true)] (_)?)+ @n",
    ] {
    let query = @query.Query::new(language, source)
    let matches = query.matches(tree.root_node(), tree.source)
    assert_eq(matches.length(), 1)
    let captures = matches[0].captures
    assert_eq(captures.length(), 80)
    for index, capture in captures {
      assert_eq(capture.name, "n")
      assert_eq(capture.node.start_byte(), index * 2)
      assert_eq(capture.node.end_byte(), index * 2 + 1)
    }
  }
}
