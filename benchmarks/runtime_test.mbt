///|
test "JSON fresh parse scaling" (bench : @bench.T) {
  let parser = @ts.Parser::new(@json_language.language())
  for size in [100, 1000] {
    let source = @utf8.encode(
      "[" + Array::make(size, "{\"value\":0}").join(",") + "]",
    )
    assert_false(parser.parse(source).root_node().has_error())
    bench.bench(name="\{size} objects (\{source.length()} bytes)", count=10, () => {
      bench.keep(try! parser.parse(source))
    })
  }
}

///|
test "JSON incremental edit versus fresh parse" (bench : @bench.T) {
  let parser = @ts.Parser::new(@json_language.language())
  let rest = Array::make(99, "{\"value\":0}").join(",")
  let old = parser.parse_string("[{\"value\":0}," + rest + "]")
  let source = @utf8.encode("[{\"value\":1}," + rest + "]")
  let edit : @ts.InputEdit = {
    start_byte: 10,
    old_end_byte: 11,
    new_end_byte: 11,
    start_point: { row: 0, column: 10, },
    old_end_point: { row: 0, column: 11, },
    new_end_point: { row: 0, column: 11, },
  }
  let edited = old.copy()
  edited.edit(edit)
  let next = parser.parse(source, old_tree=edited)
  assert_true(next.reused_subtrees > 0)
  assert_eq(
    next.root_node().to_sexp(),
    parser.parse(source).root_node().to_sexp(),
  )
  bench.bench(name="fresh", count=20, () => {
    bench.keep(try! parser.parse(source))
  })
  bench.bench(name="edit and reuse", count=20, () => {
    let previous = old.copy()
    try! previous.edit(edit)
    bench.keep(try! parser.parse(source, old_tree=previous))
  })
}
