///|
pub(all) struct InputEdit {
  start_byte : Int32
  old_end_byte : Int32
  new_end_byte : Int32
  start_point : Point
  old_end_point : Point
  new_end_point : Point
} derive(Debug, Eq)

///|
pub extend InputEdit with Eq::{equal, not_equal}

///|
pub extend InputEdit with @debug.Debug::{to_repr}

///|
pub suberror EditError {
  InvalidEdit(String)
} derive(Debug)

///|
pub extend EditError with @debug.Debug::{to_repr}

///|
fn shift_point(point : Point, edit : InputEdit) -> Point {
  if point < edit.old_end_point {
    edit.new_end_point
  } else {
    {
      row: point.row + edit.new_end_point.row - edit.old_end_point.row,
      column: if point.row == edit.old_end_point.row {
        edit.new_end_point.column + point.column - edit.old_end_point.column
      } else {
        point.column
      },
    }
  }
}

///|
fn edit_node(node : Node, edit : InputEdit) -> Node {
  let data = node.data
  if data.end_byte < edit.start_byte {
    return node
  }
  let delta = edit.new_end_byte - edit.old_end_byte
  let changed = data.changed ||
    (data.start_byte <= edit.old_end_byte && data.end_byte >= edit.start_byte)
  let start_byte = if data.start_byte >= edit.old_end_byte {
    data.start_byte + delta
  } else if data.start_byte > edit.start_byte {
    // The replacement belongs to the first affected content or its padding.
    // Later nodes covered by the deletion collapse at the replacement's end.
    edit.new_end_byte
  } else {
    data.start_byte
  }
  let end_byte = if data.end_byte < edit.start_byte ||
    (data.end_byte == edit.start_byte && edit.old_end_byte != edit.start_byte) {
    data.end_byte
  } else if data.end_byte >= edit.old_end_byte {
    data.end_byte + delta
  } else {
    edit.new_end_byte
  }
  let end_byte = Int32::max(start_byte, end_byte)
  let start_point = if data.start_byte >= edit.old_end_byte {
    shift_point(data.start_point, edit)
  } else if data.start_byte > edit.start_byte {
    edit.new_end_point
  } else {
    data.start_point
  }
  let end_point = if data.end_byte < edit.start_byte ||
    (data.end_byte == edit.start_byte && edit.old_end_byte != edit.start_byte) {
    data.end_point
  } else if data.end_byte >= edit.old_end_byte {
    shift_point(data.end_point, edit)
  } else {
    edit.new_end_point
  }
  let end_point = if end_point < start_point { start_point } else { end_point }
  {
    data: {
      ..data,
      changed,
      start_byte,
      end_byte,
      start_point,
      end_point,
      children: child_entries(
        data.children.entries().map(c => (c.0, edit_node(c.1, edit))),
      ),
    },
  }
}

///|
/// Adjust node locations and invalidate intersecting nodes. The old source is
/// retained for verifying reuse against the next input. Existing node handles
/// retain their old positions because trees use persistent nodes.
pub fn Tree::edit(self : Tree, edit : InputEdit) -> Unit raise EditError {
  if edit.start_byte < 0 ||
    edit.old_end_byte < edit.start_byte ||
    edit.new_end_byte < edit.start_byte ||
    edit.old_end_byte > self.edited_length ||
    edit.start_point.row < 0 ||
    edit.start_point.column < 0 ||
    edit.old_end_point < edit.start_point ||
    edit.new_end_point < edit.start_point {
    raise InvalidEdit("invalid byte or point bounds")
  }
  self.root = edit_node(self.root, edit)
  self.source_ranges = self.source_ranges.map(r => edited_range(r, edit))
  self.edited_length += edit.new_end_byte - edit.old_end_byte
  self.edited = true
}

///|
pub fn Node::has_changes(self : Node) -> Bool {
  self.data.changed
}

///|
pub fn Tree::copy(self : Tree) -> Tree {
  {
    root: self.root,
    source: self.source,
    language: self.language,
    edited_length: self.edited_length,
    edited: self.edited,
    reused_subtrees: self.reused_subtrees,
    parse_steps: self.parse_steps,
    source_ranges: self.source_ranges.copy(),
    scanner: self.scanner,
  }
}

///|
fn reset_origin(node : Node) -> Node {
  if node.data.origin_start == node.start_byte() &&
    node.data.origin_end == node.end_byte() {
    return node
  }
  {
    data: {
      ..node.data,
      dependency_end: node.data.dependency_end +
      node.start_byte() -
      node.data.origin_start,
      origin_start: node.start_byte(),
      origin_end: node.end_byte(),
      children: child_entries(
        node.data.children.entries().map(c => (c.0, reset_origin(c.1))),
      ),
    },
  }
}

///|
fn reuse_candidates(
  old_tree : Tree,
  source : Bytes,
) -> Map[(Int32, Int32), Node] {
  let result : Map[(Int32, Int32), Node] = Map([])
  // Reuse deterministic subtrees only. Ambiguous reductions and nodes built
  // while another stack competes retain their fragility in the old tree.
  let old_lines = line_starts(old_tree.source)
  let new_lines = line_starts(source)
  let pending = [old_tree.root]
  while pending.pop() is Some(node) {
    if !node.data.fragile &&
      !node.is_extra() &&
      !node.has_changes() &&
      !node.has_error() &&
      !old_tree.language.symbols[node.symbol()].terminal &&
      node.end_byte() > node.start_byte() &&
      node.start_byte() >= 0 &&
      node.end_byte() <= source.length() &&
      same_dependency(old_tree.source, source, node) &&
      (
        old_tree.language.externals.is_empty() ||
        (
          scalar_column(old_tree.source, node.data.origin_start, old_lines) ==
          scalar_column(source, node.start_byte(), new_lines) &&
          (node.data.origin_start == 0) == (node.start_byte() == 0)
        )
      ) {
      let key = (node.start_byte(), node.parse_state())
      if result.get(key) is Some(previous) &&
        previous.end_byte() >= node.end_byte() {
        continue
      }
      result[key] = node
    }
    pending.append(node.children())
  }
  result
}

///|
fn same_dependency(old : Bytes, current : Bytes, node : Node) -> Bool {
  let origin = node.data.origin_start
  let inspected_eof = node.data.dependency_end > old.length()
  let old_end = Int32::min(old.length(), node.data.dependency_end)
  let end = node.start_byte() + old_end - origin
  if origin < 0 ||
    old_end < origin ||
    end > current.length() ||
    (inspected_eof && end != current.length()) {
    return false
  }
  old[origin:old_end] == current[node.start_byte():end]
}
