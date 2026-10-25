// Port of tree-sitter crates/cli/src/query.rs.

///|
pub struct QueryFileOptions {
  ordered_captures : Bool
  byte_range : (Int32, Int32)?
  point_range : (@treesitter.Point, @treesitter.Point)?
  containing_byte_range : (Int32, Int32)?
  containing_point_range : (@treesitter.Point, @treesitter.Point)?
  quiet : Bool
  print_time : Bool
  stdin : Bool
}

///|
pub fn QueryFileOptions::default() -> QueryFileOptions {
  {
    ordered_captures: false,
    byte_range: None,
    point_range: None,
    containing_byte_range: None,
    containing_point_range: None,
    quiet: false,
    print_time: false,
    stdin: false,
  }
}

///|
/// `Debug for Duration`.
pub fn format_duration_debug(nanos : Int64) -> String {
  fn fmt(value : Int64, divisor : Int64, unit : String) -> String {
    let int_part = value / divisor
    let mut frac = value % divisor
    if frac == 0L {
      return "\{int_part}\{unit}"
    }
    // Up to 9 significant fractional digits, trailing zeros removed.
    let mut digits = ""
    let mut d = divisor / 10L
    while d > 0L && frac > 0L {
      digits = digits + (frac / d).to_string()
      frac = frac % d
      d = d / 10L
    }
    "\{int_part}.\{digits}\{unit}"
  }
  if nanos >= 1000000000L {
    fmt(nanos, 1000000000L, "s")
  } else if nanos >= 1000000L {
    fmt(nanos, 1000000L, "ms")
  } else if nanos >= 1000L {
    fmt(nanos, 1000L, "µs")
  } else {
    "\{nanos}ns"
  }
}

///|
pub async fn query_file_at_path(
  language : @treesitter.Language,
  path : String,
  name : String,
  query_path : String,
  opts : QueryFileOptions,
  test_summary : TestSummary?,
) -> Unit {
  let stdout = StringBuilder()
  let query_source = @fs.read_file(query_path).text() catch {
    e => raise with_context(e, "Error reading query file \{query_path}")
  }
  let query = @treesitter.Query::new(language, query_source) catch {
    e => raise with_context(e, "Query compilation failed")
  }
  let query_cursor = @treesitter.QueryCursor::new()
  if opts.byte_range is Some((start, end)) {
    ignore(query_cursor.set_byte_range(start, end))
  }
  if opts.point_range is Some((start, end)) {
    ignore(query_cursor.set_point_range(start, end))
  }
  if opts.containing_byte_range is Some((start, end)) {
    ignore(query_cursor.set_containing_byte_range(start, end))
  }
  if opts.containing_point_range is Some((start, end)) {
    ignore(query_cursor.set_containing_point_range(start, end))
  }
  let parser = @treesitter.Parser::new()
  parser.set_language(language)
  let results = []
  let should_test = test_summary is Some(_)
  if !should_test && !opts.stdin {
    stdout.write_string("\{name}\n")
  }
  let source_code = @fs.read_file(path).binary() catch {
    e => raise with_context(e, "Error reading source file \{path}")
  }
  let tree = parser.parse(source_code).unwrap()
  let text = (node : @treesitter.Node) => node.utf8_text(source_code) catch { _ => "" }
  let start = @support.now_ns()
  if opts.ordered_captures {
    let captures = query_cursor.captures(query, tree.root_node(), source_code)
    while captures.next() is Some((mat, capture_index)) {
      let capture = mat.captures()[capture_index]
      let capture_name = query.capture_names()[capture.index]
      if !opts.quiet && !should_test {
        stdout.write_string(
          "    pattern: \{pad_left(mat.pattern_index.to_string(), 2)}, capture: \{capture.index} - \{capture_name}, start: \{capture.node.start_position()}, end: \{capture.node.end_position()}, text: `\{text(capture.node)}`\n",
        )
      }
      if should_test {
        results.push(@query_testing.CaptureInfo::{
          name: capture_name,
          start: @query_testing.to_utf8_point(
            capture.node.start_position(),
            source_code,
          ),
          end: @query_testing.to_utf8_point(
            capture.node.end_position(),
            source_code,
          ),
        })
      }
    }
  } else {
    let matches = query_cursor.matches(query, tree.root_node(), source_code)
    while matches.next() is Some(m) {
      if !opts.quiet && !should_test {
        stdout.write_string("  pattern: \{m.pattern_index}\n")
      }
      for capture in m.captures() {
        let start = capture.node.start_position()
        let end = capture.node.end_position()
        let capture_name = query.capture_names()[capture.index]
        if !opts.quiet && !should_test {
          if end.row == start.row {
            stdout.write_string(
              "    capture: \{capture.index} - \{capture_name}, start: \{start}, end: \{end}, text: `\{text(capture.node)}`\n",
            )
          } else {
            stdout.write_string(
              "    capture: \{capture_name}, start: \{start}, end: \{end}\n",
            )
          }
        }
        if should_test {
          results.push(@query_testing.CaptureInfo::{
            name: capture_name,
            start: @query_testing.to_utf8_point(
              capture.node.start_position(),
              source_code,
            ),
            end: @query_testing.to_utf8_point(
              capture.node.end_position(),
              source_code,
            ),
          })
        }
      }
    }
  }
  if query_cursor.did_exceed_match_limit() {
    @support.print_out(stdout.to_string())
    stdout.reset()
    log_warn("Query exceeded maximum number of in-progress captures!")
  }
  if test_summary is Some(test_summary) {
    let path_name = if opts.stdin {
      "stdin"
    } else {
      @support.file_name(path).unwrap()
    }
    let assertions = @query_testing.parse_position_comments(
      parser, language, source_code,
    )
    match
      (try @query_testing.assert_expected_captures(results, assertions) catch {
        e => Err(e)
      } noraise {
        n => Ok(n)
      }) {
      Ok(assertion_count) =>
        test_summary.query_results.add_case({
          name: path_name,
          info: AssertionTest(
            outcome=AssertionPassed(assertion_count~),
            test_num=test_summary.test_num,
          ),
        })
      Err(e) => {
        test_summary.query_results.add_case({
          name: path_name,
          info: AssertionTest(
            outcome=AssertionFailed(error=error_message(e)),
            test_num=test_summary.test_num,
          ),
        })
        @support.print_out(stdout.to_string())
        raise e
      }
    }
  }
  if opts.print_time {
    stdout.write_string("\{format_duration_debug(@support.now_ns() - start)}\n")
  }
  @support.print_out(stdout.to_string())
}
