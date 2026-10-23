// Port of tree-sitter crates/cli/src/tests/test_highlight_test.rs.
//
// `test_highlight_test_with_basic_test` needs the javascript fixture
// language, whose external scanner is not ported yet; it is skipped with a
// notice until it is. Upstream resolves injections through the CLI's test
// loader; here the javascript configuration has no other language available
// for injection (none of its injections occur in the test source).

///|
fn utf8(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
fn assertion(
  row : Int32,
  col : Int32,
  length : Int32,
  negative : Bool,
  name : String,
) -> @query_testing.Assertion {
  @query_testing.Assertion::new(row, col, length, negative, name)
}

///|
fn point(row : Int32, column : Int32) -> @query_testing.Utf8Point {
  @query_testing.Utf8Point::new(row, column)
}

///|
fn h(i : Int32) -> @highlight.Highlight {
  @highlight.Highlight(i)
}

///|
async test "highlight_test_with_basic_test" {
  guard @fixtures.get_language("javascript") is Some(language) else { return }
  guard @fixtures.get_highlight_config("javascript", Some("injections.scm"), [
      "function", "variable", "keyword",
    ])
    is Some(config) else {
    return
  }
  let source = [
    "// hi", "var abc = function(d) {", "  // ^ function", "  //       ^^^ keyword",
    "  return d + e;", "  //     ^ variable", "  //       ^ !variable", "};", "var y̆y̆y̆y̆ = function() {}",
    "  // ^ function", "  //       ^ keyword",
  ].join("\n")
  let assertions = @query_testing.parse_position_comments(
    @api.Parser::new(),
    language,
    utf8(source),
  )
  assert_eq(assertions, [
    assertion(1, 5, 1, false, "function"),
    assertion(1, 11, 3, false, "keyword"),
    assertion(4, 9, 1, false, "variable"),
    assertion(4, 11, 1, true, "variable"),
    assertion(8, 5, 1, false, "function"),
    assertion(8, 11, 1, false, "keyword"),
  ])
  let highlighter = @highlight.Highlighter::new()
  let highlight_positions = @query_testing.get_highlight_positions(
    highlighter,
    config,
    _ => None,
    utf8(source),
  )
  assert_eq(highlight_positions, [
    (point(1, 0), point(1, 3), h(2)), // "var"
    (point(1, 4), point(1, 7), h(0)), // "abc"
    (point(1, 10), point(1, 18), h(2)), // "function"
    (point(1, 19), point(1, 20), h(1)), // "d"
    (point(4, 2), point(4, 8), h(2)), // "return"
    (point(4, 9), point(4, 10), h(1)), // "d"
    (point(4, 13), point(4, 14), h(1)), // "e"
    (point(8, 0), point(8, 3), h(2)), // "var"
    (point(8, 4), point(8, 8), h(0)), // "y̆y̆y̆y̆"
    (point(8, 11), point(8, 19), h(2)), // "function"
  ])
}

///|
/// The `Failure` of a failed `iterate_assertions`.
fn failure(
  result : Result[Int32, @query_testing.QueryTestError],
) -> (Int32, Int32, String, Array[String]) {
  match result {
    Err(
      HighlightFailure(row~, column~, expected_highlight~, actual_highlights~)
    ) => (row, column, expected_highlight, actual_highlights)
    _ => abort("expected a highlight failure")
  }
}

///|
#warnings("-result_error_return")
fn iterate(
  assertions : Array[@query_testing.Assertion],
  highlights : Array[
    (@query_testing.Utf8Point, @query_testing.Utf8Point, @highlight.Highlight),
  ],
  highlight_names : Array[String],
) -> Result[Int32, @query_testing.QueryTestError] {
  Ok(@query_testing.iterate_assertions(assertions, highlights, highlight_names)) catch {
    e => Err(e)
  }
}

///|
test "assertion_with_non_matching_highlight_at_same_position" {
  // Test that an assertion fails when the highlight at the position does not match
  let highlight_names = ["keyword", "variable"]
  let assertions = [assertion(1, 0, 1, false, "keyword")]
  let highlights = [
    (point(1, 0), point(1, 5), h(1)), // "variable" highlight
  ]
  let result = iterate(assertions, highlights, highlight_names)
  assert_true(result is Err(_))
  let (row, column, expected, actual) = failure(result)
  assert_eq(row, 1)
  assert_eq(column, 0)
  assert_eq(expected, "keyword")
  assert_eq(actual, ["variable"])
}

///|
test "assertion_with_exact_matching_highlight" {
  // Test exact match: assertion and highlight have same start and end
  let highlight_names = ["keyword"]
  let assertions = [assertion(0, 5, 3, false, "keyword")]
  let highlights = [(point(0, 5), point(0, 8), h(0))]
  let result = iterate(assertions, highlights, highlight_names)
  assert_eq(result, Ok(1))
}

///|
test "assertion_contained_within_highlight" {
  // Test where assertion is fully contained within a larger highlight
  let highlight_names = ["keyword"]
  let assertions = [assertion(0, 3, 2, false, "keyword")]
  let highlights = [(point(0, 0), point(0, 10), h(0))]
  let result = iterate(assertions, highlights, highlight_names)
  assert_eq(result, Ok(1))
}

///|
test "assertion_overlapping_highlight_start" {
  // Test where assertion starts before highlight but overlaps with it
  let highlight_names = ["keyword"]
  let assertions = [assertion(0, 3, 4, false, "keyword")]
  let highlights = [(point(0, 5), point(0, 10), h(0))]
  let result = iterate(assertions, highlights, highlight_names)
  assert_eq(result, Ok(1))
}

///|
test "assertion_with_no_highlights" {
  // Test that an assertion fails when there are no highlights at all
  let highlight_names = ["keyword"]
  let assertions = [assertion(0, 0, 1, false, "keyword")]
  let result = iterate(assertions, [], highlight_names)
  assert_true(result is Err(_))
  let (row, column, expected, actual) = failure(result)
  assert_eq(row, 0)
  assert_eq(column, 0)
  assert_eq(expected, "keyword")
  assert_eq(actual, [])
}

///|
test "assertion_with_highlight_ending_before" {
  // Test where highlight ends before the assertion starts
  let highlight_names = ["keyword"]
  let assertions = [assertion(0, 10, 1, false, "keyword")]
  let highlights = [(point(0, 0), point(0, 5), h(0))]
  let result = iterate(assertions, highlights, highlight_names)
  assert_true(result is Err(_))
  let (row, column, expected, actual) = failure(result)
  assert_eq(row, 0)
  assert_eq(column, 10)
  assert_eq(expected, "keyword")
  assert_eq(actual, [])
}

///|
test "negative_assertion_with_non_matching_highlight" {
  // Test that a negative assertion passes when the specified highlight is NOT present
  let highlight_names = ["keyword", "variable"]
  let assertions = [assertion(0, 0, 1, true, "keyword")]
  let highlights = [
    (point(0, 0), point(0, 5), h(1)), // "variable" highlight
  ]
  let result = iterate(assertions, highlights, highlight_names)
  assert_eq(result, Ok(1))
}

///|
test "negative_assertion_with_matching_highlight" {
  // Test that a negative assertion fails when the specified highlight IS present
  let highlight_names = ["keyword"]
  let assertions = [assertion(0, 0, 1, true, "keyword")]
  let highlights = [
    (point(0, 0), point(0, 5), h(0)), // "keyword" highlight
  ]
  let result = iterate(assertions, highlights, highlight_names)
  assert_true(result is Err(_))
  let (row, column, expected, actual) = failure(result)
  assert_eq(row, 0)
  assert_eq(column, 0)
  assert_eq(expected, "!keyword")
  assert_eq(actual, ["keyword"])
}

///|
test "multiple_assertions_sequential" {
  // Test multiple assertions in sequence with non-overlapping highlights
  let highlight_names = ["keyword", "variable"]
  let assertions = [
    assertion(0, 0, 3, false, "keyword"),
    assertion(0, 10, 1, false, "variable"),
  ]
  let highlights = [
    (point(0, 0), point(0, 3), h(0)), // "keyword"
    (point(0, 10), point(0, 11), h(1)), // "variable"
  ]
  let result = iterate(assertions, highlights, highlight_names)
  assert_eq(result, Ok(2))
}

///|
test "multiple_highlights_at_same_position" {
  // Test where multiple highlights overlap at the assertion position
  let highlight_names = ["keyword", "variable", "function"]
  let assertions = [assertion(0, 5, 1, false, "variable")]
  let highlights = [
    (point(0, 0), point(0, 10), h(0)), // "keyword" spans entire range
    (point(0, 5), point(0, 8), h(1)), // "variable" at assertion position
    (point(0, 7), point(0, 12), h(2)), // "function" overlaps
  ]
  let result = iterate(assertions, highlights, highlight_names)
  assert_eq(result, Ok(1))
}

///|
test "assertions_across_multiple_rows" {
  // Test assertions on different rows
  let highlight_names = ["keyword", "variable"]
  let assertions = [
    assertion(0, 5, 3, false, "keyword"),
    assertion(2, 10, 1, false, "variable"),
  ]
  let highlights = [
    (point(0, 5), point(0, 8), h(0)), // "keyword" on row 0
    (point(2, 10), point(2, 11), h(1)), // "variable" on row 2
  ]
  let result = iterate(assertions, highlights, highlight_names)
  assert_eq(result, Ok(2))
}

///|
test "assertion_should_not_match_highlight_on_later_row" {
  // Test logic for early exit when highlight is on a later row than the assertion
  let highlight_names = ["keyword"]
  let assertions = [assertion(0, 5, 3, false, "keyword")]
  let highlights = [
    (point(1, 0), point(1, 5), h(0)), // wrong row
  ]
  let result = iterate(assertions, highlights, highlight_names)
  assert_true(result is Err(_))
  let (row, column, expected, actual) = failure(result)
  assert_eq(row, 0)
  assert_eq(column, 7) // end_column
  assert_eq(expected, "keyword")
  assert_eq(actual, [])
}

///|
test "failure messages" {
  let result = iterate(
    [assertion(0, 0, 1, true, "keyword")],
    [(point(0, 0), point(0, 5), h(0)), (point(0, 0), point(0, 5), h(0))],
    ["keyword"],
  )
  guard result is Err(e) else { fail("expected a failure") }
  inspect(
    e,
    content="Failure - row: 0, column: 0, expected highlight '!keyword', actual highlights: 'keyword', 'keyword'",
  )
  let result = iterate([assertion(3, 2, 2, false, "keyword")], [], ["keyword"])
  guard result is Err(e) else { fail("expected a failure") }
  inspect(
    e,
    content="Failure - row: 3, column: 3, expected highlight 'keyword', actual highlights: none.",
  )
}
