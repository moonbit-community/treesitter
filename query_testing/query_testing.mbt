// Port of tree-sitter crates/cli/src/query_testing.rs.

///|
let capture_name_regex : @regex.Regex = try! @regex.Regex::new(
  "[\\w_\\-.]+",
  utf8=true,
)

///|
pub(all) struct Utf8Point {
  row : Int32
  column : Int32
} derive(Default, Eq, Hash, Compare, Debug)

///|
pub impl Show for Utf8Point with fn output(self, logger) {
  logger.write_string("(\{self.row}, \{self.column})")
}

///|
pub fn Utf8Point::new(row : Int32, column : Int32) -> Utf8Point {
  { row, column, }
}

///|
/// Convert a point whose column is a byte offset into one whose column counts
/// grapheme clusters.
pub fn to_utf8_point(point : @treesitter.Point, source : BytesView) -> Utf8Point {
  if point.column == 0 {
    return Utf8Point::new(point.row, 0)
  }
  guard nth_line_with_terminator(source, point.row) is Some(line) else {
    abort("called `Option::unwrap()` on a `None` value")
  }
  let mut utf8_column = 0
  for grapheme_end in grapheme_ends_iter(line) {
    utf8_column += 1
    if grapheme_end >= point.column {
      break
    }
  }
  { row: point.row, column: utf8_column, }
}

///|
pub(all) struct CaptureInfo {
  name : String
  start : Utf8Point
  end : Utf8Point
} derive(Eq, Debug)

///|
pub(all) struct Assertion {
  position : Utf8Point
  length : Int32
  negative : Bool
  expected_capture_name : String
} derive(Eq, Debug)

///|
pub fn Assertion::new(
  row : Int32,
  col : Int32,
  length : Int32,
  negative : Bool,
  expected_capture_name : String,
) -> Assertion {
  {
    position: Utf8Point::new(row, col),
    length,
    negative,
    expected_capture_name,
  }
}

///|
/// The errors of the assertion-based query tests (upstream: `anyhow::Error`
/// values and the `Failure` types of test_highlight.rs and test_tags.rs).
pub(all) suberror QueryTestError {
  /// An `anyhow!` error with this message.
  Message(String)
  /// test_highlight.rs's `Failure`.
  HighlightFailure(
    row~ : Int32,
    column~ : Int32,
    expected_highlight~ : String,
    actual_highlights~ : Array[String]
  )
  /// test_tags.rs's `Failure`.
  TagsFailure(
    row~ : Int32,
    column~ : Int32,
    expected_tag~ : String,
    actual_tags~ : Array[String]
  )
  Highlight(@highlight.HighlightError)
  Tags(@tags.TagsError)
} derive(Eq, Debug)

///|
pub impl Show for QueryTestError with fn output(self, logger) {
  match self {
    Message(message) => logger.write_string(message)
    HighlightFailure(row~, column~, expected_highlight~, actual_highlights~) => {
      logger.write_string(
        "Failure - row: \{row}, column: \{column}, expected highlight '\{expected_highlight}', actual highlights: ",
      )
      write_actual(logger, actual_highlights)
    }
    TagsFailure(row~, column~, expected_tag~, actual_tags~) => {
      logger.write_string(
        "Failure - row: \{row}, column: \{column}, expected tag: '\{expected_tag}', actual tag: ",
      )
      write_actual(logger, actual_tags)
    }
    Highlight(e) => logger.write_string(e.to_string())
    Tags(e) => logger.write_string(e.to_string())
  }
}

///|
fn write_actual(logger : &Logger, actual : Array[String]) -> Unit {
  if actual.is_empty() {
    logger.write_string("none.")
  } else {
    for i, name in actual {
      if i > 0 {
        logger.write_string(", ")
      }
      logger.write_string("'\{name}'")
    }
  }
}

///|
/// The characters of valid UTF-8 `bytes` with their byte offsets
/// (`str::char_indices`).
fn char_indices(bytes : BytesView) -> Array[(Int32, Char)] {
  let result = []
  let mut i = 0
  while i < bytes.length() {
    let b0 = bytes[i].to_int()
    let (width, init) = if b0 < 0x80 {
      (1, b0)
    } else if b0 < 0xE0 {
      (2, b0 & 0x1F)
    } else if b0 < 0xF0 {
      (3, b0 & 0x0F)
    } else {
      (4, b0 & 0x07)
    }
    let mut cp = init
    for k in 1..<width {
      cp = (cp << 6) | (bytes[i + k].to_int() & 0x3F)
    }
    result.push((i, cp.unsafe_to_char()))
    i += width
  }
  result
}

///|
/// `char::is_whitespace`: the Unicode `White_Space` property.
fn is_whitespace(c : Char) -> Bool {
  match c.to_int() {
    0x09..<=0x0D | 0x20 | 0x85 | 0xA0 | 0x1680 | 0x2000..<=0x200A => true
    0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000 => true
    _ => false
  }
}

///|
/// Parse the given source code, finding all of the comments that contain
/// highlighting assertions. Return a vector of (position, expected highlight
/// name) pairs.
pub fn parse_position_comments(
  parser : @treesitter.Parser,
  language : @treesitter.Language,
  source : Bytes,
) -> Array[Assertion] raise QueryTestError {
  let result : Array[Assertion] = []
  let assertion_ranges : Array[(@treesitter.Point, @treesitter.Point)] = []

  // Parse the code.
  try! parser.set_included_ranges([])
  try! parser.set_language(language)
  guard parser.parse(source) is Some(tree) else {
    abort("called `Option::unwrap()` on a `None` value")
  }

  // Walk the tree, finding comment nodes that contain assertions.
  let mut ascending = false
  let cursor = tree.root_node().walk()
  for ;; {
    if ascending {
      let node = cursor.node()

      // Find every comment node.
      if node.kind().to_lower().contains("comment") &&
        has_utf8_text(node, source) {
        let text = source[node.start_byte():node.end_byte()]
        let mut position = node.start_position()
        if position.row > 0 {
          // Find the arrow character ("^" or "<-") in the comment. A left arrow
          // refers to the column where the comment node starts. An up arrow refers
          // to its own column.
          let mut has_left_caret = false
          let mut has_arrow = false
          let mut negative = false
          let mut arrow_end = 0
          let mut arrow_count = 1
          for pair in char_indices(text) {
            let (i, c) = pair
            arrow_end = i + 1
            if c == '-' && has_left_caret {
              has_arrow = true
              break
            }
            if c == '^' {
              has_arrow = true
              position = { ..position, column: position.column + i, }
              // Continue counting remaining arrows and update their end column
              for rest in char_indices(text[arrow_end:]) {
                let (_, c) = rest
                if c != '^' {
                  arrow_end += arrow_count - 1
                  break
                }
                arrow_count += 1
              }
              break
            }
            has_left_caret = c == '<'
          }

          // find any ! after arrows but before capture name
          if has_arrow {
            for pair in char_indices(text[arrow_end:]) {
              let (i, c) = pair
              if c == '!' {
                negative = true
                arrow_end += i + 1
                break
              } else if !is_whitespace(c) {
                break
              }
            }
          }

          // If the comment node contains an arrow and a highlight name, record the
          // highlight name and the position.
          //
          // Upstream evaluates `&text[arrow_end..]` even when there is no arrow,
          // which panics when the comment ends with a multi-byte character.
          if arrow_end < text.length() &&
            (text[arrow_end].to_int() & 0xC0) == 0x80 {
            abort("byte index \{arrow_end} is not a char boundary")
          }
          if has_arrow && capture_name_regex.find(text[arrow_end:]) is Some(mat) {
            assertion_ranges.push((node.start_position(), node.end_position()))
            let name = text[arrow_end + mat.0:arrow_end + mat.1]
            result.push({
              position: to_utf8_point(position, source),
              length: arrow_count,
              negative,
              expected_capture_name: @utf8.decode_lossy(name),
            })
          }
        }
      }

      // Continue walking the tree.
      if cursor.goto_next_sibling() {
        ascending = false
      } else if !cursor.goto_parent() {
        break
      }
    } else if !cursor.goto_first_child() {
      ascending = true
    }
  }

  // Adjust the row number in each assertion's position to refer to the line of
  // code *above* the assertion. There can be multiple lines of assertion comments and empty
  // lines, so the positions may have to be decremented by more than one row.
  let mut i = 0
  let lines = lines_with_terminator(source)
  for index, assertion in result {
    let original_position = assertion.position
    let mut assertion = assertion
    for ;; {
      let row = assertion.position.row
      let on_assertion_line = assertion_ranges[i:]
        .iter()
        .any(range => range.0.row == row)
      let on_empty_line = lines[row].length() <= assertion.position.column
      if on_assertion_line || on_empty_line {
        if row > 0 {
          assertion = {
            ..assertion,
            position: { ..assertion.position, row: row - 1, },
          }
        } else {
          raise Message(
            "Error: could not find a line that corresponds to the assertion `\{assertion.expected_capture_name}` located at \{original_position}",
          )
        }
      } else {
        while i < assertion_ranges.length() &&
              assertion_ranges[i].0.row < assertion.position.row {
          i += 1
        }
        break
      }
    }
    result[index] = assertion
  }

  // The assertions can end up out of order due to the line adjustments.
  //
  // Upstream uses `sort_unstable_by_key`; ties (several assertions at one
  // position) are kept in order here, which is what Rust's unstable sort does
  // for slices of up to 20 elements (insertion sort).
  stable_sort_by_position(result)
  result
}

///|
/// `column + length - 1` in `usize` arithmetic, which wraps in the release
/// CLI: a zero-length assertion at column 0 ends at `usize::MAX`
/// (`0x7FFFFFFF` here).
fn assertion_end_column(column : Int, length : Int) -> Int {
  let end = column + length
  if end == 0 {
    0x7FFFFFFF
  } else {
    end - 1
  }
}

///|
pub fn assert_expected_captures(
  infos : ArrayView[CaptureInfo],
  assertions : ArrayView[Assertion],
) -> Int32 raise QueryTestError {
  for assertion in assertions {
    let found = infos
      .iter()
      .find_first(p => {
        let assertion_end = Utf8Point::new(
          assertion.position.row,
          assertion_end_column(assertion.position.column, assertion.length),
        )
        assertion.position >= p.start && assertion_end < p.end
      })
    if found is Some(found) {
      if assertion.expected_capture_name != found.name && found.name != "name" {
        raise Message(
          "Assertion failed: at \{found.start}, found \{found.name}, expected \{assertion.expected_capture_name}",
        )
      }
    } else {
      raise Message(
        "Assertion failed: could not match \{assertion.expected_capture_name} at row \{assertion.position.row}, column \{assertion_end_column(assertion.position.column, assertion.length)}",
      )
    }
  }
  assertions.length()
}

///|
/// Whether `node.utf8_text(source)` succeeds.
fn has_utf8_text(node : @treesitter.Node, source : Bytes) -> Bool {
  try node.utf8_text(source) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
/// Sort assertions by position, keeping assertions at equal positions in
/// order (insertion sort).
fn stable_sort_by_position(assertions : Array[Assertion]) -> Unit {
  for i in 1..<assertions.length() {
    let item = assertions[i]
    let mut j = i
    while j > 0 && assertions[j - 1].position > item.position {
      assertions[j] = assertions[j - 1]
      j -= 1
    }
    assertions[j] = item
  }
}
