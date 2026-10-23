///|
priv struct ChangeEntry {
  node : Node
  index : Int32
  padding_start : Int32
  trailing : Bool
}

///|
priv struct ChangeCursor {
  stack : Array[ChangeEntry]
  mut padding : Bool
}

///|
fn ChangeCursor::new(node : Node) -> ChangeCursor {
  {
    stack: [{ node, index: 0, padding_start: 0, trailing: false, }],
    padding: false,
  }
}

///|
fn ChangeCursor::depth(self : ChangeCursor) -> Int32 {
  self.stack.length() - (if self.padding { 1 } else { 0 })
}

///|
fn ChangeCursor::end(self : ChangeCursor) -> Int32 {
  let entry = self.stack.last().unwrap()
  if self.padding && !entry.trailing {
    entry.node.start_byte()
  } else {
    entry.node.end_byte()
  }
}

///|
fn ChangeCursor::visible(self : ChangeCursor) -> Node? {
  self.stack.get(self.depth() - 1).map(e => e.node)
}

///|
fn ChangeCursor::descend(self : ChangeCursor, position : Int32) -> Bool {
  if self.padding {
    return false
  }
  let entry = self.stack.last().unwrap()
  let mut left = entry.padding_start
  for index, child in entry.node.children() {
    if child.end_byte() > position {
      self.stack.push({
        node: child,
        index,
        padding_start: left,
        trailing: false,
      })
      self.padding = child.start_byte() > position
      return true
    }
    left = child.end_byte()
  }
  if entry.node.child_count() > 0 &&
    entry.node.end_byte() > position &&
    left < entry.node.end_byte() {
    // A parent's trailing padding has no child node to carry its extent.
    // Represent it explicitly so it can align with the other cursor's padding.
    self.stack.push({
      node: entry.node,
      index: entry.node.child_count(),
      padding_start: left,
      trailing: true,
    })
    self.padding = true
    return true
  }
  false
}

///|
fn ChangeCursor::ascend(self : ChangeCursor) -> Unit {
  if self.stack.pop() is Some(entry) && entry.index > 0 {
    self.padding = false
  }
}

///|
fn ChangeCursor::advance(self : ChangeCursor) -> Unit {
  if self.padding {
    self.padding = false
    if self.stack.last().unwrap().trailing {
      ignore(self.stack.pop())
    } else {
      return
    }
  }
  while self.stack.pop() is Some(entry) {
    guard self.stack.last() is Some(parent) else { return }
    if parent.node.child(entry.index + 1) is Some(node) {
      self.stack.push({
        node,
        index: entry.index + 1,
        padding_start: entry.node.end_byte(),
        trailing: false,
      })
      self.padding = node.start_byte() > entry.node.end_byte()
      return
    }
    if entry.node.end_byte() < parent.node.end_byte() {
      self.stack.push({
        node: parent.node,
        index: parent.node.child_count(),
        padding_start: entry.node.end_byte(),
        trailing: true,
      })
      self.padding = true
      return
    }
  }
}

///|
priv enum ChangeComparison {
  Matches
  MayDiffer
  Differs
}

///|
fn compare_changes(old : ChangeCursor, new : ChangeCursor) -> ChangeComparison {
  match (old.visible(), new.visible()) {
    (None, None) => Matches
    (Some(a), Some(b)) => {
      if a.grammar_symbol() != b.grammar_symbol() ||
        a.kind() != b.kind() ||
        a.is_named() != b.is_named() {
        return Differs
      }
      if a.has_changes() ||
        a.is_error() ||
        a.is_missing() != b.is_missing() ||
        a.start_byte() != b.start_byte() ||
        a.end_byte() != b.end_byte() ||
        a.data.error_cost != b.data.error_cost ||
        a.data.scan_before != b.data.scan_before {
        return MayDiffer
      }
      // Separate fresh parses can have equal spans but different descendants.
      // Identity is a sufficient shortcut, otherwise inspect their structure.
      if a.id() == b.id() && physical_equal(a.data, b.data) {
        Matches
      } else {
        MayDiffer
      }
    }
    _ => Differs
  }
}

///|
/// Syntactic changed ranges in the new coordinate space. Edit the old tree
/// first; text-only changes that preserve syntax do not produce changed ranges.
pub fn Tree::changed_ranges(self : Tree, new_tree : Tree) -> Array[Range] {
  let old = ChangeCursor::new(self.root)
  let new = ChangeCursor::new(new_tree.root)
  let ranges : Array[(Int32, Int32)] = []
  fn add(start, end) {
    if start >= end {
      return
    }
    if ranges.last() is Some((previous_start, previous_end)) &&
      start <= previous_end {
      ranges[ranges.length() - 1] = (
        previous_start,
        Int32::max(previous_end, end),
      )
    } else {
      ranges.push((start, end))
    }
  }
  let mut position = Int32::max(
    self.root.start_byte(),
    new_tree.root.start_byte(),
  )
  add(Int32::min(self.root.start_byte(), new_tree.root.start_byte()), position)
  while !old.stack.is_empty() && !new.stack.is_empty() {
    let mut changed = false
    let next = match compare_changes(old, new) {
      Matches => old.end()
      Differs => {
        changed = true
        Int32::min(old.end(), new.end())
      }
      MayDiffer =>
        if old.descend(position) {
          if new.descend(position) {
            position
          } else {
            changed = true
            old.end()
          }
        } else if new.descend(position) {
          changed = true
          new.end()
        } else {
          Int32::min(old.end(), new.end())
        }
    }
    while !old.stack.is_empty() && old.end() <= next {
      old.advance()
    }
    while !new.stack.is_empty() && new.end() <= next {
      new.advance()
    }
    while old.depth() > new.depth() {
      old.ascend()
    }
    while new.depth() > old.depth() {
      new.ascend()
    }
    if changed {
      add(position, next)
    }
    position = next
  }
  add(
    Int32::min(self.root.end_byte(), new_tree.root.end_byte()),
    Int32::max(self.root.end_byte(), new_tree.root.end_byte()),
  )
  let lines = input_lines(new_tree.source, new_tree.encoding())
  fn position_at(offset) {
    if offset > new_tree.source.length() && offset == self.root.end_byte() {
      self.root.end_position()
    } else {
      point_at(lines, offset)
    }
  }
  ranges.map(r => {
    start_byte: r.0,
    end_byte: r.1,
    start_point: position_at(r.0),
    end_point: position_at(r.1),
  })
}
