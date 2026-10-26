// Port of tree-sitter crates/cli/src/fuzz/corpus_test.rs (renamed because
// moon treats `*_test.mbt` files as tests).

///|
priv struct SizeCheckFrame {
  node : @treesitter.Node
  end_byte : Int32
  end_point : @treesitter.Point
  child_count : Int32
  mut child_index : Int32
  mut last_child_end_byte : Int32
  mut last_child_end_point : @treesitter.Point
  mut some_child_has_changes : Bool
  mut actual_named_child_count : Int32
}

///|
fn SizeCheckFrame::new(
  node : @treesitter.Node,
  line_offsets : Array[Int32],
) -> SizeCheckFrame raise {
  let start_byte = node.start_byte()
  let end_byte = node.end_byte()
  let start_point = node.start_position()
  let end_point = node.end_position()
  assert_true(start_byte <= end_byte)
  assert_true(start_point <= end_point)
  assert_eq(start_byte, line_offsets[start_point.row] + start_point.column)
  assert_eq(end_byte, line_offsets[end_point.row] + end_point.column)
  {
    node,
    end_byte,
    end_point,
    child_count: node.child_count(),
    child_index: 0,
    last_child_end_byte: start_byte,
    last_child_end_point: start_point,
    some_child_has_changes: false,
    actual_named_child_count: 0,
  }
}

///|
/// Check that the sizes and positions of the nodes of `tree` are consistent
/// with each other and with `input`.
pub fn check_consistent_sizes(
  tree : @treesitter.Tree,
  input : BytesView,
) -> Unit raise {
  let line_offsets = [0]
  for i, c in input {
    if c == b'\n' {
      line_offsets.push(i + 1)
    }
  }
  let stack : Array[SizeCheckFrame] = [
    SizeCheckFrame::new(tree.root_node(), line_offsets),
  ]
  while stack.last() is Some(top) {
    if top.child_index < top.child_count {
      let i = top.child_index
      let child = top.node.child(i).unwrap()
      assert_true(child.start_byte() >= top.last_child_end_byte)
      assert_true(child.start_position() >= top.last_child_end_point)
      if child.has_changes() {
        top.some_child_has_changes = true
      }
      if child.is_named() {
        top.actual_named_child_count += 1
      }
      top.last_child_end_byte = child.end_byte()
      top.last_child_end_point = child.end_position()
      top.child_index += 1
      stack.push(SizeCheckFrame::new(child, line_offsets))
      continue
    }
    let frame = stack.pop().unwrap()
    assert_eq(frame.actual_named_child_count, frame.node.named_child_count())
    if frame.child_count > 0 {
      assert_true(frame.end_byte >= frame.last_child_end_byte)
      assert_true(frame.end_point >= frame.last_child_end_point)
    }
    if frame.some_child_has_changes {
      assert_true(frame.node.has_changes())
    }
  }
}

///|
/// Check that the syntax changes between `old_tree` and `new_tree` lie within
/// the trees' changed ranges.
pub fn check_changed_ranges(
  old_tree : @treesitter.Tree,
  new_tree : @treesitter.Tree,
  input : BytesView,
) -> Result[Unit, String] {
  let changed_ranges = old_tree.changed_ranges(new_tree)
  let old_scope_sequence = ScopeSequence::new(old_tree)
  let new_scope_sequence = ScopeSequence::new(new_tree)
  let old_range = old_tree.root_node().range()
  let new_range = new_tree.root_node().range()
  let byte_range_end = if old_range.end_byte > new_range.end_byte {
    old_range.end_byte
  } else {
    new_range.end_byte
  }
  let point_range_end = if old_range.end_point > new_range.end_point {
    old_range.end_point
  } else {
    new_range.end_point
  }
  for range in changed_ranges {
    if range.end_byte > byte_range_end || range.end_point > point_range_end {
      return Err(
        "changed range extends outside of the old and new trees \{debug_range(range)}",
      )
    }
  }
  old_scope_sequence.check_changes(new_scope_sequence, input, changed_ranges)
}

///|
/// Restrict `parser` to the text between the template `delimiters` of
/// `input`, or to the whole text when there are none.
pub fn set_included_ranges(
  parser : @treesitter.Parser,
  input : BytesView,
  delimiters : (String, String)?,
) -> Unit raise {
  match delimiters {
    Some((start, end)) => {
      let start = @utf8.encode(start)
      let end = @utf8.encode(end)
      let ranges = []
      let mut ix = 0
      while ix < input.length() {
        guard find_window(input, ix, start) is Some(start_ix) else { break }
        let start_ix = start_ix + start.length()
        let end_ix = match find_window(input, start_ix, end) {
          Some(ix) => ix
          None => input.length()
        }
        ix = end_ix
        ranges.push(@treesitter.Range::{
          start_byte: start_ix,
          end_byte: end_ix,
          start_point: point_for_offset(input, start_ix),
          end_point: point_for_offset(input, end_ix),
        })
      }
      parser.set_included_ranges(ranges)
    }
    None => parser.set_included_ranges([])
  }
}

///|
/// `input[from..].windows(2).position(|win| win == needle).map(|i| from + i)`:
/// the windows are always two bytes wide, so a delimiter of another length
/// never matches.
fn find_window(input : BytesView, from : Int32, needle : Bytes) -> Int32? {
  if needle.length() != 2 {
    return None
  }
  let mut i = from
  while i + 2 <= input.length() {
    if input[i] == needle[0] && input[i + 1] == needle[1] {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn point_for_offset(text : BytesView, offset : Int32) -> @treesitter.Point {
  let mut row = 0
  let mut column = 0
  for byte in text[:offset] {
    if byte == b'\n' {
      row += 1
      column = 0
    } else {
      column += 1
    }
  }
  { row, column, }
}

///|
/// `util::LogSession` (cli/support/log_session.mbt).
pub using @support {type LogSession}

///|
/// End the log session (`Drop for LogSession`), if there is one.
pub async fn end_log_session(session : LogSession?) -> Unit {
  if session is Some(session) {
    session.close()
  }
}

///|
/// A parser that logs to standard error when `TREE_SITTER_LOG` is set, and
/// whose debug graphs go to a `log_filename` log session (stored in
/// `session`) when `TREE_SITTER_LOG_GRAPHS` is set.
pub async fn get_parser(
  session : Ref[LogSession?],
  log_filename : String,
) -> @treesitter.Parser {
  let parser = @treesitter.Parser::new()
  if log_enabled() {
    parser.set_logger(
      Some((log_type, msg) => {
        if log_type == @treesitter.LogType::Lex {
          @support.print_err("  \{msg}\n")
        } else {
          @support.print_err("\{msg}\n")
        }
      }),
    )
  }
  if log_graph_enabled() {
    let log_session = @support.log_graphs(parser, log_filename, false) catch {
      e => {
        // `.unwrap()` of the `anyhow::Error` (`Debug`: the context, then its
        // cause).
        let message = match e {
          @support.DotSpawnError(e) =>
            "Failed to run the `dot` command. Check that graphviz is installed.\n\nCaused by:\n    \{@support.io_error_message(e)}"
          e => @support.io_error_message(e)
        }
        @support.rust_panic(
          "called `Result::unwrap()` on an `Err` value: \{message}",
          "crates/cli/src/fuzz/corpus_test.rs:173:76",
        )
      }
    }
    session.val = Some(log_session)
  }
  parser
}
