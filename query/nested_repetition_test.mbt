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
