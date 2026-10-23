// Port of the helpers in tree-sitter
// crates/cli/src/tests/helpers/query_helpers.rs.

///|
fn format_capture(
  capture : @api.QueryCapture,
  query : @api.Query,
  source : Bytes,
) -> (String, String) {
  (query.capture_names()[capture.index], text(capture.node, source))
}

///|
fn[T : @api.TextProvider] collect_matches(
  matches : @api.QueryMatches[T],
  query : @api.Query,
  source : String,
) -> Array[(Int32, Array[(String, String)])] {
  let bytes = utf8(source)
  let result = []
  while matches.next() is Some(m) {
    result.push(
      (
        m.pattern_index,
        m.captures().iter().map(c => format_capture(c, query, bytes)).to_array(),
      ),
    )
  }
  result
}

///|
fn[T : @api.TextProvider] collect_captures(
  captures : @api.QueryCaptures[T],
  query : @api.Query,
  source : String,
) -> Array[(String, String)] {
  let bytes = utf8(source)
  let result = []
  while captures.next() is Some((m, i)) {
    result.push(format_capture(m.captures()[i], query, bytes))
  }
  result
}

///|
fn assert_query_matches(
  language : @api.Language,
  query : @api.Query,
  source : String,
  expected : Array[(Int32, Array[(String, String)])],
) -> Unit raise {
  let tree = parse(parser_for(language), source)
  let cursor = @api.QueryCursor::new()
  let matches = cursor.matches(query, tree.root_node(), utf8(source))
  assert_eq(collect_matches(matches, query, source), expected)
  assert_false(cursor.did_exceed_match_limit())
}

///|
/// The error raised by `Query::new`, or a failure.
fn query_error(
  language : @api.Language,
  source : String,
) -> @api.QueryError raise {
  try @api.Query::new(language, source) catch {
    e => e
  } noraise {
    _ => fail("expected `\{source}` to be rejected")
  }
}

///|
/// The `(kind, row, column, offset, message)` of a query error.
fn error_parts(
  e : @api.QueryError,
) -> (@api.QueryErrorKind, Int32, Int32, Int32, String) {
  (e.kind(), e.row(), e.column(), e.offset(), e.message())
}
