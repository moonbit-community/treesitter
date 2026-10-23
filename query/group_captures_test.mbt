///|
// Expected captures and completion order are frozen from the pinned C runtime.
test "group captures belong to concrete entry steps" {
  assert_eq(
    root_query_output("1 2 true 3", "((number) @n (true) @t) @g _ @v"),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|1 v:2..3
      #|0 n:0..1 g:0..1 t:4..8
      #|0 n:2..3 g:2..3 t:4..8
      #|1 v:4..8
      #|1 v:9..10
    ),
  )
  assert_eq(
    root_query_output("1 2 true 3", "((number)+ @n) @g _ @v"),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|1 v:2..3
      #|0 n:0..1 g:0..1 n:2..3 g:2..3
      #|1 v:4..8
      #|1 v:9..10
      #|0 n:9..10 g:9..10
    ),
  )
  assert_eq(
    root_query_output("1 2 true 3", "((number)? @n (true) @t) @g @h _ @v"),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|1 v:2..3
      #|0 n:0..1 g:0..1 h:0..1 t:4..8 g:4..8 h:4..8
      #|0 n:2..3 g:2..3 h:2..3 t:4..8 g:4..8 h:4..8
      #|1 v:4..8
      #|1 v:9..10
    ),
  )
  assert_eq(
    root_query_output(
      "[1,true,2]", "[(number) @n ((true) @t (number) @n)] @x _ @v",
    ),
    (
      #|1 v:0..10
      #|1 v:0..10
      #|1 v:0..1
      #|0 n:1..2 x:1..2
      #|1 v:1..2
      #|1 v:2..3
      #|1 v:3..7
      #|1 v:7..8
      #|0 t:3..7 x:3..7 n:8..9
      #|0 n:8..9 x:8..9
      #|1 v:8..9
      #|1 v:9..10
    ),
  )
  assert_eq(
    root_query_output("1 2 true 3", "((number)* @n (true) @t) @g _ @v"),
    (
      #|1 v:0..10
      #|1 v:0..1
      #|1 v:2..3
      #|0 n:0..1 g:0..1 n:2..3 g:2..3 t:4..8 g:4..8
      #|1 v:4..8
      #|1 v:9..10
    ),
  )
}

///|
test "group capture reaches past a nested nullable prefix" {
  assert_eq(
    root_query_output("true", "(((number)? @n) (true) @t) @g _ @v"),
    (
      #|1 v:0..4
      #|0 t:0..4 g:0..4
      #|1 v:0..4
    ),
  )
}
