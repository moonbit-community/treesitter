///|
// Frozen upstream C outputs: collocated capture names retain their order.
test "root repetition keeps distinct ordered capture paths" {
  assert_eq(
    root_query_output("1 2", "[(number) @a @b (number) @b @a]+"),
    (
      #|0 b:0..1 a:0..1 a:2..3 b:2..3
      #|0 b:0..1 a:0..1 b:2..3 a:2..3
      #|0 a:0..1 b:0..1 a:2..3 b:2..3
      #|0 a:0..1 b:0..1 b:2..3 a:2..3
    ),
  )
  assert_eq(
    root_query_output("1 2", "[(number) @a @b (number) @b]+"),
    (
      #|0 b:0..1 a:2..3 b:2..3
      #|0 b:0..1 b:2..3
      #|0 a:0..1 b:0..1 a:2..3 b:2..3
      #|0 a:0..1 b:0..1 b:2..3
    ),
  )
}

///|
test "long uncaptured repetitions share the final sibling search" {
  let source = Array::make(500, "1").join(" ") + " true"
  assert_eq(
    root_query_output(source, "(document (number)+ (true) @t)"),
    "0 t:1000..1004",
  )
}

///|
test "capture metadata scales with independent query patterns" {
  let language = root_query_language()
  let source = Array::makei(4000, i => "(number) @c\{i}").join("\n")
  let query = @query.Query::new(language, source)
  assert_eq(query.pattern_count(), 4000)
  assert_eq(query.capture_names.length(), 4000)
  for i in 0..<4000 {
    assert_eq(query.capture_quantifier(i, i), Some(One))
  }
  assert_eq(query.capture_quantifier(0, 3999), Some(Zero))
  assert_eq(query.capture_quantifier(3999, 0), Some(Zero))
}
