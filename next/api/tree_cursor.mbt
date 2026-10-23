// Port of `TreeCursor` from tree-sitter lib/binding_rust/lib.rs.

///|
/// A stateful object for walking a syntax [`Tree`] efficiently.
pub struct TreeCursor {
  priv raw : @runtime.TreeCursor
  priv mut language : Language
}

///|
/// Get the tree cursor's current [`Node`].
pub fn TreeCursor::node(self : TreeCursor) -> Node {
  { raw: self.raw.current_node(), language: self.language, }
}

///|
/// Get the numerical field id of this tree cursor's current node.
///
/// See also [`field_name`](TreeCursor::field_name).
pub fn TreeCursor::field_id(self : TreeCursor) -> Int32? {
  match self.raw.current_field_id() {
    0 => None
    id => Some(id)
  }
}

///|
/// Get the field name of this tree cursor's current node.
pub fn TreeCursor::field_name(self : TreeCursor) -> String? {
  self.raw.current_field_name()
}

///|
/// Get the depth of the cursor's current node relative to the original node
/// that the cursor was constructed with.
pub fn TreeCursor::depth(self : TreeCursor) -> Int32 {
  self.raw.current_depth().reinterpret_as_int()
}

///|
/// Get the index of the cursor's current node out of all of the descendants
/// of the original node that the cursor was constructed with.
pub fn TreeCursor::descendant_index(self : TreeCursor) -> Int32 {
  self.raw.current_descendant_index().reinterpret_as_int()
}

///|
/// Move this cursor to the first child of its current node.
///
/// This returns `true` if the cursor successfully moved, and returns `false`
/// if there were no children.
pub fn TreeCursor::goto_first_child(self : TreeCursor) -> Bool {
  self.raw.goto_first_child()
}

///|
/// Move this cursor to the last child of its current node.
///
/// This returns `true` if the cursor successfully moved, and returns `false`
/// if there were no children.
///
/// Note that this function may be slower than
/// [`goto_first_child`](TreeCursor::goto_first_child) because it needs to
/// iterate through all the children to compute the child's position.
pub fn TreeCursor::goto_last_child(self : TreeCursor) -> Bool {
  self.raw.goto_last_child()
}

///|
/// Move this cursor to the parent of its current node.
///
/// This returns `true` if the cursor successfully moved, and returns `false`
/// if there was no parent node (the cursor was already on the root node).
///
/// Note that the node the cursor was constructed with is considered the root
/// of the cursor, and the cursor cannot walk outside this node.
pub fn TreeCursor::goto_parent(self : TreeCursor) -> Bool {
  self.raw.goto_parent()
}

///|
/// Move this cursor to the next sibling of its current node.
///
/// This returns `true` if the cursor successfully moved, and returns `false`
/// if there was no next sibling node.
///
/// Note that the node the cursor was constructed with is considered the root
/// of the cursor, and the cursor cannot walk outside this node.
pub fn TreeCursor::goto_next_sibling(self : TreeCursor) -> Bool {
  self.raw.goto_next_sibling()
}

///|
/// Move the cursor to the node that is the nth descendant of the original
/// node that the cursor was constructed with, where zero represents the
/// original node itself.
pub fn TreeCursor::goto_descendant(
  self : TreeCursor,
  descendant_index : Int32,
) -> Unit {
  self.raw.goto_descendant(descendant_index.reinterpret_as_uint())
}

///|
/// Move this cursor to the previous sibling of its current node.
///
/// This returns `true` if the cursor successfully moved, and returns `false`
/// if there was no previous sibling node.
///
/// Note, that this function may be slower than
/// [`goto_next_sibling`](TreeCursor::goto_next_sibling) due to how node
/// positions are stored. In the worst case, this will need to iterate
/// through all the children up to the previous sibling node to recalculate
/// its position. Also note that the node the cursor was constructed with is
/// considered the root of the cursor, and the cursor cannot walk outside this
/// node.
pub fn TreeCursor::goto_previous_sibling(self : TreeCursor) -> Bool {
  self.raw.goto_previous_sibling()
}

///|
/// Move this cursor to the first child of its current node that contains or
/// starts after the given byte offset.
///
/// This returns the index of the child node if one was found, and returns
/// `None` if no such child was found.
pub fn TreeCursor::goto_first_child_for_byte(
  self : TreeCursor,
  index : Int32,
) -> Int32? {
  let result = self.raw.goto_first_child_for_byte(to_u32(index))
  if result < 0L {
    None
  } else {
    Some(result.to_int())
  }
}

///|
/// Move this cursor to the first child of its current node that contains or
/// starts after the given point.
///
/// This returns the index of the child node if one was found, and returns
/// `None` if no such child was found.
pub fn TreeCursor::goto_first_child_for_point(
  self : TreeCursor,
  point : Point,
) -> Int32? {
  let result = self.raw.goto_first_child_for_point(point.to_ts())
  if result < 0L {
    None
  } else {
    Some(result.to_int())
  }
}

///|
/// Re-initialize this tree cursor to start at the given node.
pub fn TreeCursor::reset(self : TreeCursor, node : Node) -> Unit {
  self.raw.reset(node.raw)
  self.language = node.language
}

///|
/// Re-initialize a tree cursor to the same position as another cursor.
///
/// Unlike [`reset`](TreeCursor::reset), this will not lose parent information
/// and allows reusing already created cursors.
pub fn TreeCursor::reset_to(self : TreeCursor, cursor : TreeCursor) -> Unit {
  self.raw.reset_to(cursor.raw)
  self.language = cursor.language
}

///|
/// Create an independent copy of this cursor at the same position.
pub fn TreeCursor::clone(self : TreeCursor) -> TreeCursor {
  { raw: self.raw.copy(), language: self.language, }
}
