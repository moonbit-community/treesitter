// Regression tests for the C integer widths that lib/src/query.c truncates
// to: `uint16_t` step indices, pattern-map entries, capture ids and capture
// counts. The expected values come from the pinned upstream C library
// (ts_query_new / ts_query_cursor_next_match over the fixture JSON grammar).
// Capture ids beyond 65535 are tested in query_wbtest.mbt: compiling more
// than 65536 capture names takes too long for a test.

///|
/// A wildcard-rooted pattern with `k` children: `k + 2` steps (with its DONE
/// step) that never match the inputs below and are not analyzed.
fn padding(k : Int32) -> String {
  "(_" + " (number)".repeat(k) + ")\n"
}

///|
fn compile(
  language : @treesitter.Language,
  source : String,
) -> @query.Query raise @query.QueryError {
  @query.Query::new(language.raw(), @utf8.encode(source))
}

///|
/// `pattern_index:capture_count` of every match of `query` in `source`.
fn matches(
  language : @treesitter.Language,
  query : @query.Query,
  source : String,
) -> Array[String] raise {
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let tree = parser.parse(@utf8.encode(source)).unwrap()
  let cursor = @query.QueryCursor::new()
  cursor.exec(query, tree.root_node().raw())
  let result = []
  while cursor.next_match() is Some(m) {
    result.push("\{m.pattern_index}:\{m.captures.length()}")
  }
  result
}

///|
fn json_array(count : Int32) -> String {
  "[" + "1,".repeat(count - 1) + "1]"
}

///|
async test "match capture counts are uint16_t" {
  guard @fixtures.get_language("json") is Some(json) else { return }
  // One match of 21846 anchored children, the first with `first` captures and
  // the others with three each.
  let source = json_array(21846)
  let query = (first : String) => {
    compile(
      json,
      "(array . (number) " +
      first +
      " ." +
      " (number) @a @b @c .".repeat(21845) +
      ")",
    )
  }
  debug_inspect(matches(json, query(""), source), content="[\"0:65535\"]")
  debug_inspect(matches(json, query("@a"), source), content="[\"0:0\"]")
  debug_inspect(matches(json, query("@a @b"), source), content="[\"0:1\"]")
}

///|
async test "execution step indices are uint16_t" {
  guard @fixtures.get_language("json") is Some(json) else { return }
  // `(string)` is step 65535: advancing past it wraps to step 0 instead of
  // reaching its DONE step.
  let wrapped = compile(json, padding(65533) + "(string) @s")
  debug_inspect(matches(json, wrapped, "\"x\""), content="[]")
  let plain = compile(json, padding(65532) + "(string) @s")
  debug_inspect(matches(json, plain, "\"x\""), content="[\"1:1\"]")
}

///|
async test "analysis step indices are uint16_t" {
  guard @fixtures.get_language("json") is Some(json) else { return }
  // The impossible `(array (pair))` starts at step 65536, so its parent step
  // index narrows to 0 (and its pattern-map entry runs pattern 0's steps).
  let narrowed_parent = compile(
    json,
    "(array (number) (number))\n" + padding(65530) + "(array (pair))\n",
  )
  debug_inspect(
    matches(json, narrowed_parent, "[1, 2]"),
    content="[\"0:0\", \"2:0\"]",
  )
  // The impossible `(pair)` child is step 65536: analysis wraps from step
  // 65535 to step 0 and records a finished pattern.
  let wrapped_child = compile(
    json,
    padding(65532) + "(array (number) (pair))\n",
  )
  debug_inspect(matches(json, wrapped_child, "[1, 2]"), content="[]")
  // Without wrapping, both patterns are impossible.
  let rejected = try {
    ignore(compile(json, padding(65531) + "(array (number) (pair))\n"))
    false
  } catch {
    _ => true
  }
  inspect(rejected, content="true")
}

///|
async test "negated fields attach to a uint16_t step index" {
  guard @fixtures.get_language("json") is Some(json) else { return }
  // `!value` is attached to step 65536 & 0xFFFF = 0, `(pair) @first`. The
  // last pattern's entry also narrows to step 0.
  let query = compile(
    json,
    "(pair) @first\n" + padding(65532) + "(pair !value) @last\n",
  )
  debug_inspect(matches(json, query, "{\"a\": 1}"), content="[]")
}
