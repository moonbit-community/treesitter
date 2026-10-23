// Port of tree-sitter crates/cli/src/fuzz/corpus_test.rs (renamed because
// moon treats `*_test.mbt` files as tests).

///|
priv struct SizeCheckFrame {
  node : @api.Node
  end_byte : Int32
  end_point : @api.Point
  child_count : Int32
  mut child_index : Int32
  mut last_child_end_byte : Int32
  mut last_child_end_point : @api.Point
  mut some_child_has_changes : Bool
  mut actual_named_child_count : Int32
}

///|
fn SizeCheckFrame::new(
  node : @api.Node,
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
  tree : @api.Tree,
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
  old_tree : @api.Tree,
  new_tree : @api.Tree,
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
  parser : @api.Parser,
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
        ranges.push(@api.Range::{
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
/// `input[from..].windows(2).position(|win| win == needle).map(|i| from + i)`
/// (the delimiters are two bytes long).
fn find_window(input : BytesView, from : Int32, needle : Bytes) -> Int32? {
  let n = needle.length()
  let mut i = from
  while i + n <= input.length() {
    let mut matched = true
    for j in 0..<n {
      if input[i + j] != needle[j] {
        matched = false
        break
      }
    }
    if matched {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn point_for_offset(text : BytesView, offset : Int32) -> @api.Point {
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
/// A parser that logs when `TREE_SITTER_LOG` is set. (`TREE_SITTER_LOG_GRAPHS`
/// writes the debug graphs to standard output instead of a `log.html` file.)
pub fn get_parser() -> @api.Parser {
  let parser = @api.Parser::new()
  if log_enabled() {
    parser.set_logger(
      Some((log_type, msg) => {
        if log_type == @api.LogType::Lex {
          println("  \{msg}")
        } else {
          println(msg)
        }
      }),
    )
  }
  if log_graph_enabled() {
    parser.print_dot_graphs(graph => println(graph))
  }
  parser
}
