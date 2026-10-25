// Port of tree-sitter crates/cli/src/test_highlight.rs.
//
// `test_highlights` (the directory walk that resolves languages through the
// loader and records results in the CLI's `TestSummary`) is not ported; the
// loader's role is played by the parameters `highlight_names` (the
// recognized highlight names) and `injection_callback`.

///|
pub fn iterate_assertions(
  assertions : ArrayView[Assertion],
  highlights : ArrayView[(Utf8Point, Utf8Point, @highlight.Highlight)],
  highlight_names : ArrayView[String],
) -> Int32 raise QueryTestError {
  // Iterate through all of the highlighting assertions, checking each one against the
  // actual highlights.
  let mut i = 0
  let actual_highlights : Array[String] = []
  for assertion in assertions {
    let {
      position,
      length,
      negative,
      expected_capture_name: expected_highlight,
    } = assertion
    // Iterate through all of the highlights that start at or before this assertion's
    // position, looking for one that matches the assertion.
    actual_highlights.clear()
    let mut passed = false
    let end_column = position.column + length - 1
    for highlight in highlights[i:] {
      // The assertions are ordered by position, so skip past all of the highlights that
      // end at or before this assertion's position.
      if highlight.1 <= position {
        i += 1
        continue
      }
      if highlight.0.row > position.row ||
        (highlight.0.row == position.row && highlight.0.column > end_column) {
        break
      }

      // If the highlight matches the assertion, or if the highlight doesn't
      // match the assertion but it's negative, this test passes. Otherwise,
      // add this highlight to the list of actual highlights that span the
      // assertion's position, in order to generate an error message in the event
      // of a failure.
      let highlight_name = highlight_names[highlight.2.0]
      if (highlight_name == expected_highlight) == negative {
        actual_highlights.push(highlight_name)
      } else {
        passed = true
        break
      }
    }
    if !passed {
      let expected = StringBuilder()
      if negative {
        expected.write_char('!')
      }
      expected.write_string(expected_highlight)
      raise HighlightFailure(
        row=position.row,
        column=end_column,
        expected_highlight=expected.to_string(),
        actual_highlights=actual_highlights.copy(),
      )
    }
  }
  assertions.length()
}

///|
pub fn test_highlight(
  highlighter : @highlight.Highlighter,
  highlight_config : @highlight.HighlightConfiguration,
  highlight_names : ArrayView[String],
  injection_callback : (String) -> @highlight.HighlightConfiguration?,
  source : Bytes,
) -> Int32 raise QueryTestError {
  // Highlight the file, and parse out all of the highlighting assertions.
  let highlights = get_highlight_positions(
    highlighter, highlight_config, injection_callback, source,
  )
  let assertions = parse_position_comments(
    highlighter.parser(),
    highlight_config.language,
    source,
  )
  iterate_assertions(assertions, highlights, highlight_names)
}

///|
pub fn get_highlight_positions(
  highlighter : @highlight.Highlighter,
  highlight_config : @highlight.HighlightConfiguration,
  injection_callback : (String) -> @highlight.HighlightConfiguration?,
  source : Bytes,
) -> Array[(Utf8Point, Utf8Point, @highlight.Highlight)] raise QueryTestError {
  let mut row = 0
  let mut column = 0
  let mut byte_offset = 0
  let mut was_newline = false
  let result = []
  let highlight_stack = []
  // `String::from_utf8_lossy(source)`
  let source = @utf8.encode(lossy_utf8(source))
  let char_indices = char_indices(source)
  let mut next_char = 0
  let events = highlighter.highlight(
    highlight_config, source, injection_callback,
  ) catch {
    e => raise Highlight(e)
  }
  while events.next() is Some(event) {
    match event {
      Err(e) => raise Highlight(e)
      Ok(HighlightStart(h)) => highlight_stack.push(h)
      Ok(HighlightEnd) => ignore(highlight_stack.pop())
      Ok(Source(start~, end~)) => {
        let mut start_position = @treesitter.Point::new(row, column)
        while byte_offset < end {
          if byte_offset <= start {
            start_position = @treesitter.Point::new(row, column)
          }
          if char_indices.get(next_char) is Some((i, c)) {
            next_char += 1
            if was_newline {
              row += 1
              column = 0
            } else {
              column += i - byte_offset
            }
            was_newline = c == '\n'
            byte_offset = i
          } else {
            break
          }
        }
        if highlight_stack.last() is Some(highlight) {
          let utf8_start_position = to_utf8_point(start_position, source)
          let utf8_end_position = to_utf8_point(
            @treesitter.Point::new(row, column),
            source,
          )
          result.push((utf8_start_position, utf8_end_position, highlight))
        }
      }
    }
  }
  result
}

///|
/// `String::from_utf8_lossy`.
fn lossy_utf8(bytes : BytesView) -> String {
  let out = StringBuilder()
  let chunks = @treesitter.LossyUtf8::new(bytes)
  while chunks.next() is Some(chunk) {
    out.write_string(chunk)
  }
  out.to_string()
}
