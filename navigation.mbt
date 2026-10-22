///|
/// Count visible nodes in this subtree, including this node.
pub fn Node::descendant_count(self : Node) -> Int32 {
  let work = [self]
  let mut count = 0
  while work.pop() is Some(node) {
    count += 1
    work.append(node.children())
  }
  count
}

///|
pub fn Node::descendant_for_point_range(
  self : Node,
  start : Point,
  end : Point,
  named~ : Bool = false,
) -> Node? {
  if start < self.start_position() || end > self.end_position() || end < start {
    return None
  }
  for child in self.children() {
    if child.start_position() <= start &&
      child.end_position() >= end &&
      (
        child.end_position() > start ||
        child.start_position() == child.end_position()
      ) {
      if child.descendant_for_point_range(start, end, named~) is Some(found) {
        return Some(found)
      }
    }
  }
  if !named || self.is_named() {
    Some(self)
  } else {
    None
  }
}

///|
pub fn Node::field_name_for_named_child(self : Node, index : Int32) -> String? {
  let mut current = 0
  for i, child in self.children() {
    if child.is_named() {
      if current == index {
        return self.field_name_for_child(i)
      }
      current += 1
    }
  }
  None
}

///|
pub fn Node::first_child_for_byte(
  self : Node,
  byte : Int32,
  named~ : Bool = false,
) -> Node? {
  for child in self.children() {
    if child.end_byte() > byte && (!named || child.is_named()) {
      return Some(child)
    }
  }
  None
}

///|
pub fn TreeCursor::goto_first_child_for_point(
  self : TreeCursor,
  point : Point,
) -> Int32? {
  for i, child in self.current.children() {
    if child.end_position() > point {
      self.parents.push((self.current, i))
      self.current = child
      return Some(i)
    }
  }
  None
}

///|
pub fn TreeCursor::descendant_index(self : TreeCursor) -> Int32 {
  let mut index = 0
  for (parent, child_index) in self.parents {
    index += 1
    for i in 0..<child_index {
      index += parent.child(i).unwrap().descendant_count()
    }
  }
  index
}

///|
/// Seek in preorder from the cursor's original root; failure preserves position.
pub fn TreeCursor::goto_descendant(self : TreeCursor, index : Int32) -> Bool {
  if index < 0 {
    return false
  }
  let root = self.parents.get(0).map(p => p.0).unwrap_or(self.current)
  if index >= root.descendant_count() {
    return false
  }
  self.reset(root)
  let mut remaining = index
  while remaining > 0 {
    remaining -= 1
    for i, child in self.current.children() {
      let count = child.descendant_count()
      if remaining < count {
        self.parents.push((self.current, i))
        self.current = child
        break
      }
      remaining -= count
    }
  }
  true
}

///|
pub fn TreeCursor::reset_to(self : TreeCursor, other : TreeCursor) -> Unit {
  let parents = other.parents.copy()
  self.current = other.current
  self.parents.clear()
  self.parents.append(parents)
}

///|
/// Locate a node in this persistent tree. Unrelated nodes are never matched by
/// a numeric id alone, since parsers may independently allocate the same id.
pub fn Tree::cursor_at(self : Tree, target : Node) -> TreeCursor? {
  let cursor = self.walk()
  for ;; {
    if physical_equal(cursor.current.data, target.data) {
      return Some(cursor)
    }
    if cursor.goto_first_child() {
      continue
    }
    while !cursor.goto_next_sibling() {
      if !cursor.goto_parent() {
        return None
      }
    }
  }
}

///|
pub fn Tree::parent(self : Tree, node : Node) -> Node? {
  guard self.cursor_at(node) is Some(cursor) && cursor.goto_parent() else {
    return None
  }
  Some(cursor.node())
}

///|
pub fn Tree::next_sibling(
  self : Tree,
  node : Node,
  named~ : Bool = false,
) -> Node? {
  guard self.cursor_at(node) is Some(cursor) else { return None }
  while cursor.goto_next_sibling() {
    if !named || cursor.node().is_named() {
      return Some(cursor.node())
    }
  }
  None
}

///|
pub fn Tree::previous_sibling(
  self : Tree,
  node : Node,
  named~ : Bool = false,
) -> Node? {
  guard self.cursor_at(node) is Some(cursor) else { return None }
  while cursor.goto_previous_sibling() {
    if !named || cursor.node().is_named() {
      return Some(cursor.node())
    }
  }
  None
}
