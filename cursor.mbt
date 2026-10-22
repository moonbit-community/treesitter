///|
pub struct TreeCursor {
  priv mut current : Node
  priv parents : Array[(Node, Int32)]
}

///|
pub fn Node::walk(self : Node) -> TreeCursor {
  { current: self, parents: [], }
}

///|
pub fn TreeCursor::node(self : TreeCursor) -> Node {
  self.current
}

///|
pub fn TreeCursor::depth(self : TreeCursor) -> Int32 {
  self.parents.length()
}

///|
pub fn TreeCursor::field_name(self : TreeCursor) -> String? {
  match self.parents.last() {
    Some((parent, index)) => parent.field_name_for_child(index)
    None => None
  }
}

///|
pub fn TreeCursor::goto_first_child(self : TreeCursor) -> Bool {
  match self.current.child(0) {
    Some(child) => {
      self.parents.push((self.current, 0))
      self.current = child
      true
    }
    None => false
  }
}

///|
pub fn TreeCursor::goto_last_child(self : TreeCursor) -> Bool {
  let index = self.current.child_count() - 1
  match self.current.child(index) {
    Some(child) => {
      self.parents.push((self.current, index))
      self.current = child
      true
    }
    None => false
  }
}

///|
pub fn TreeCursor::goto_parent(self : TreeCursor) -> Bool {
  match self.parents.pop() {
    Some((parent, _)) => {
      self.current = parent
      true
    }
    None => false
  }
}

///|
fn TreeCursor::sibling(self : TreeCursor, delta : Int32) -> Bool {
  match self.parents.last() {
    Some((parent, index)) =>
      match parent.child(index + delta) {
        Some(sibling) => {
          self.parents[self.parents.length() - 1] = (parent, index + delta)
          self.current = sibling
          true
        }
        None => false
      }
    None => false
  }
}

///|
pub fn TreeCursor::goto_next_sibling(self : TreeCursor) -> Bool {
  self.sibling(1)
}

///|
pub fn TreeCursor::goto_previous_sibling(self : TreeCursor) -> Bool {
  self.sibling(-1)
}

///|
pub fn TreeCursor::reset(self : TreeCursor, node : Node) -> Unit {
  self.current = node
  self.parents.clear()
}

///|
pub fn TreeCursor::copy(self : TreeCursor) -> TreeCursor {
  { current: self.current, parents: self.parents.copy(), }
}

///|
pub fn TreeCursor::goto_first_child_for_byte(
  self : TreeCursor,
  byte : Int32,
) -> Int32? {
  for i, child in self.current.children() {
    if child.end_byte() > byte {
      self.parents.push((self.current, i))
      self.current = child
      return Some(i)
    }
  }
  None
}
