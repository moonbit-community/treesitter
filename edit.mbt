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
    edit.start_byte
  } else {
    data.start_byte
  }
  let end_byte = if data.end_byte <= edit.start_byte {
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
    edit.start_point
  } else {
    data.start_point
  }
  let end_point = if data.end_byte <= edit.start_byte {
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
  // A previously selected GLR derivation is not sufficient to reconstruct all
  // competing stacks. Reparse ambiguous tables until a shared parse forest is
  // available; reusing a single winner could change dynamic precedence.
  if !old_tree.language.externals.is_empty() ||
    old_tree.language.states.any(row => {
      row.actions.values().any(actions => actions.length() > 1)
    }) {
    return result
  }
  let mut common = 0
  while common < old_tree.source.length() &&
        common < source.length() &&
        old_tree.source[old_tree.source.length() - common - 1] ==
        source[source.length() - common - 1] {
    common += 1
  }
  let pending = [old_tree.root]
  while pending.pop() is Some(node) {
    if !node.is_extra() &&
      !node.has_changes() &&
      !node.has_error() &&
      !old_tree.language.symbols[node.symbol()].terminal &&
      node.end_byte() > node.start_byte() &&
      node.start_byte() >= 0 &&
      node.end_byte() <= source.length() &&
      node.data.origin_start >= old_tree.source.length() - common &&
      old_tree.source.length() - node.data.origin_start ==
      source.length() - node.start_byte() {
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
fn changed_nodes(old : Node, new : Node, result : Array[Range]) -> Unit {
  if old.kind() != new.kind() ||
    old.is_named() != new.is_named() ||
    old.is_missing() != new.is_missing() ||
    old.start_byte() != new.start_byte() ||
    old.end_byte() != new.end_byte() ||
    old.child_count() != new.child_count() {
    result.push(new.range())
    return
  }
  for i in 0..<new.child_count() {
    if old.field_name_for_child(i) != new.field_name_for_child(i) {
      result.push(new.child(i).unwrap().range())
    } else {
      changed_nodes(old.child(i).unwrap(), new.child(i).unwrap(), result)
    }
  }
}

///|
/// Structural changed ranges in the new tree's coordinate space. Edit the old
/// tree first. Text-only changes preserving node kinds need not change syntax.
pub fn Tree::changed_ranges(self : Tree, new_tree : Tree) -> Array[Range] {
  let ranges = []
  changed_nodes(self.root, new_tree.root, ranges)
  let result : Array[Range] = []
  for range in ranges {
    if result.last() is Some(previous) && range.start_byte <= previous.end_byte {
      result[result.length() - 1] = {
        ..previous,
        end_byte: Int32::max(previous.end_byte, range.end_byte),
        end_point: if previous.end_byte >= range.end_byte {
          previous.end_point
        } else {
          range.end_point
        },
      }
    } else {
      result.push(range)
    }
  }
  result
}
