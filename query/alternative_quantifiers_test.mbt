///|
// Frozen from the pinned upstream C query cursor, including traversal order.
test "quantified alternative branches preserve their entry and completion paths" {
  assert_eq(
    root_query_output("", "[(number)? @n (true) @t] _ @v"),
    (
      #|1 v:0..0
    ),
  )
  assert_eq(
    root_query_output("", "[(true) @t (number)? @n] _ @v"),
    (
      #|1 v:0..0
      #|0
    ),
  )
  assert_eq(
    root_query_output("", "(document [(true) @t (number)? @n]) @x _ @v"),
    (
      #|0 x:0..0
      #|1 v:0..0
    ),
  )
  assert_eq(
    root_query_output("1 2 true 3", "[(number)* @n (true) @t] @x _ @v"),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|1 v:2..3
      #|0 n:0..1 x:0..1 n:2..3 x:2..3
      #|0 t:4..8 x:4..8
      #|1 v:4..8
      #|1 v:9..10
      #|0 n:9..10 x:9..10
    ),
  )
  assert_eq(
    root_query_output("1 2 true 3", "[(true) @t (number)* @n] @x _ @v"),
    (
      #|1 v:0..10
      #|0
      #|1 v:0..1
      #|0
      #|1 v:2..3
      #|0
      #|0 n:0..1 x:0..1 n:2..3 x:2..3
      #|0 t:4..8 x:4..8
      #|1 v:4..8
      #|0
      #|1 v:9..10
      #|0
      #|0 n:9..10 x:9..10
    ),
  )
  assert_eq(
    root_query_output(
      "1 2 true 3", "(document [(true) @t (number)+ @n]) @x _ @v",
    ),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|1 v:2..3
      #|0 x:0..10 t:4..8
      #|0 x:0..10 n:0..1 n:2..3
      #|1 v:4..8
      #|1 v:9..10
      #|0 x:0..10 n:9..10
    ),
  )
  assert_eq(
    root_query_output(
      "1 2 true 3", "(document [(number)+ @n (true) @t]) @x _ @v",
    ),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|1 v:2..3
      #|0 x:0..10 n:0..1 n:2..3
      #|0 x:0..10 t:4..8
      #|1 v:4..8
      #|1 v:9..10
      #|0 x:0..10 n:9..10
    ),
  )
  assert_eq(
    root_query_output("[1,true,2]", "(array [(number)* @n (true) @t]) _ @v"),
    (
      #|1 v:0..10
      #|1 v:0..10
      #|1 v:0..1
      #|1 v:1..2
      #|0 n:1..2
      #|1 v:2..3
      #|0 t:3..7
      #|1 v:3..7
      #|1 v:7..8
      #|1 v:8..9
      #|0 n:8..9
      #|1 v:9..10
    ),
  )
  assert_eq(
    root_query_output("1 true 2", "[(number)? @n] _ @v"),
    (
      #|1 v:0..8
      #|0
      #|0 n:0..1
      #|1 v:0..1
      #|0
      #|1 v:2..6
      #|0
      #|0 n:7..8
      #|1 v:7..8
      #|0
    ),
  )
  assert_eq(
    root_query_output(
      "1 false true 2", "(document [(true) @t (number)+ @n]) @x _ @v",
    ),
    (
      #|1 v:0..14
      #|1 v:0..1
      #|0 x:0..14 n:0..1
      #|1 v:2..7
      #|0 x:0..14 t:8..12
      #|1 v:8..12
      #|1 v:13..14
      #|0 x:0..14 n:13..14
    ),
  )
}

///|
test "capture quantifiers describe source syntax before execution lowering" {
  let language = root_query_language()
  let cases : Array[(String, Array[@query.Quantifier])] = [
    ("((number)+ @n) @g", [OneOrMore, One]),
    ("((number)? @n (true) @t) @g", [ZeroOrOne, One, One]),
    ("[(number)? @x (true) @x]", [ZeroOrOne]),
    ("[(true) @t (number)? @n]", [ZeroOrOne, ZeroOrOne]),
    ("((number) @n (true) @t)+ @g", [OneOrMore, OneOrMore, OneOrMore]),
  ]
  for (source, quantifiers) in cases {
    let query = @query.Query::new(language, source)
    for index, quantifier in quantifiers {
      assert_eq(query.capture_quantifier(0, index), Some(quantifier))
    }
    assert_true(query.disable_pattern(0))
    for index, quantifier in quantifiers {
      assert_eq(query.capture_quantifier(0, index), Some(quantifier))
    }
  }
}

///|
test "repeated branches retain stops needed by following siblings" {
  assert_eq(
    root_query_output("1 2 3", "(document (number)+ @a (number) @b) _ @v"),
    (
      #|1 v:0..5
      #|1 v:0..1
      #|0 a:0..1 b:2..3
      #|1 v:2..3
      #|0 a:0..1 a:2..3 b:4..5
      #|1 v:4..5
    ),
  )
  assert_eq(
    root_query_output(
      "1 2 true 3", "(document [(number)* @a (true) @t] (number) @b) _ @v",
    ),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|0 a:0..1 b:2..3
      #|1 v:2..3
      #|1 v:4..8
      #|0 a:0..1 a:2..3 b:9..10
      #|0 t:4..8 b:9..10
      #|1 v:9..10
    ),
  )
  assert_eq(
    root_query_output(
      "1 2 true 3", "(document [(number)* @a (true) @t] . (number) @b) _ @v",
    ),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|0 a:0..1 b:2..3
      #|1 v:2..3
      #|1 v:4..8
      #|0 t:4..8 b:9..10
      #|1 v:9..10
    ),
  )
  assert_eq(
    root_query_output("1 2 3", "(document ((number)+ @a) (number) @b) _ @v"),
    (
      #|1 v:0..5
      #|1 v:0..1
      #|0 a:0..1 b:2..3
      #|1 v:2..3
      #|0 a:0..1 a:2..3 b:4..5
      #|1 v:4..5
    ),
  )
}
