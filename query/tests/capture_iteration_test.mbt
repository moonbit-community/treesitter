// Regression tests for the cost of iterating over the captures of large
// matches: upstream's `ts_query_cursor_next_capture` returns a pointer to the
// match's capture list, so yielding each of a match's N captures costs O(1),
// not O(N). With 4,000 captures per match, copying the capture list on every
// yield takes seconds for the matches below instead of milliseconds.

///|
/// `arrays` JSON arrays of `count` numbers each, in one array.
fn nested_arrays(arrays : Int32, count : Int32) -> String {
  let array = "[" + "1,".repeat(count - 1) + "1]"
  "[" + [ for _ in 0..<arrays => array ].join(",") + "]"
}

///|
/// One pattern capturing all `count` anchored numbers of an array.
fn anchored_numbers(count : Int32) -> String {
  "(array (array ." + " (number) @n .".repeat(count) + "))"
}

///|
async test "next_capture shares a match's capture list between its captures" {
  guard @fixtures.get_language("json") is Some(json) else { return }
  let (arrays, count) = (20, 4000)
  let source = nested_arrays(arrays, count)
  let parser = @treesitter.Parser::new()
  parser.set_language(json)
  let tree = parser.parse(@utf8.encode(source)).unwrap()
  let query = @query.Query::new(
    json.raw(),
    @utf8.encode(anchored_numbers(count)),
  )
  let cursor = @query.QueryCursor::new()
  cursor.exec(query, tree.root_node().raw())
  let first = cursor.next_capture().unwrap()
  let mut yielded = 1
  let mut ordered = true
  let mut last_start = first.0.captures[first.1].node.start_byte()
  while cursor.next_capture() is Some((m, i)) {
    let start = m.captures[i].node.start_byte()
    if i != yielded % count ||
      m.captures.length() != count ||
      start <= last_start {
      ordered = false
    }
    last_start = start
    yielded += 1
  }
  inspect(yielded, content="80000")
  inspect(ordered, content="true")
  // A match keeps its captures after the cursor has moved on.
  let (m, i) = first
  inspect(i, content="0")
  inspect(m.captures.length(), content="4000")
  inspect(
    m.captures.iter().all(c => c.index == 0 && c.node.start_byte() > 0),
    content="true",
  )
  inspect(m.captures[1].node.start_byte(), content="4")
}

///|
async test "QueryCaptures converts a match's captures once" {
  guard @fixtures.get_language("json") is Some(json) else { return }
  let (arrays, count) = (20, 4000)
  let source = @utf8.encode(nested_arrays(arrays, count))
  let parser = @treesitter.Parser::new()
  parser.set_language(json)
  let tree = parser.parse(source).unwrap()
  let query = @treesitter.Query::new(json, anchored_numbers(count))
  let cursor = @treesitter.QueryCursor::new()
  let captures = cursor.captures(query, tree.root_node(), source)
  let first = captures.next().unwrap()
  let mut yielded = 1
  let mut ordered = true
  let mut last_start = first.0.captures()[first.1].node.start_byte()
  while captures.next() is Some((m, i)) {
    let start = m.captures()[i].node.start_byte()
    if i != yielded % count ||
      m.captures().length() != count ||
      start <= last_start {
      ordered = false
    }
    last_start = start
    yielded += 1
  }
  inspect(yielded, content="80000")
  inspect(ordered, content="true")
  let (m, i) = first
  inspect(i, content="0")
  inspect(m.captures().length(), content="4000")
  inspect(m.captures()[1].node.start_byte(), content="4")
  inspect(m.captures()[3999].node.start_byte(), content="8000")
}
