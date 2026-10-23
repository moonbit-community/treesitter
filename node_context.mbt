///|
// Location views share syntax data. The context maps raw source coordinates to
// the displayed position, adding a column delta only on the origin's first row.
priv struct NodeContext {
  byte_delta : Int32
  origin : Point
  position : Point
}

///|
fn NodeContext::point(self : NodeContext, point : Point) -> Point {
  {
    row: self.position.row + (point.row - self.origin.row),
    column: if point.row == self.origin.row {
      self.position.column + (point.column - self.origin.column)
    } else {
      point.column
    },
  }
}

///|
fn Node::contextual_child(self : Node, child : Node) -> Node {
  match self.context {
    Some(_) => { ..child, context: self.context, }
    None => child
  }
}

///|
fn Node::with_context(
  self : Node,
  context : NodeContext,
) -> Node raise EditError {
  // Validate before exposing a view: infallible navigation must never overflow
  // at a descendant whose first-row column exceeds the root's final column.
  let pending = [self]
  while pending.pop() is Some(node) {
    for
      (point, byte) in [
        (node.data.start_point, node.data.start_byte),
        (node.data.end_point, node.data.end_byte),
      ] {
      let byte = byte.to_int64() + context.byte_delta.to_int64()
      let row = point.row.to_int64() +
        context.position.row.to_int64() -
        context.origin.row.to_int64()
      let column = if point.row == context.origin.row {
        point.column.to_int64() +
        context.position.column.to_int64() -
        context.origin.column.to_int64()
      } else {
        point.column.to_int64()
      }
      if byte < 0L ||
        row < 0L ||
        column < 0L ||
        byte > 2147483647L ||
        row > 2147483647L ||
        column > 2147483647L {
        raise InvalidEdit("node view exceeds portable coordinate limit")
      }
    }
    pending.append(node.data.children.entries().map(c => c.1))
  }
  { ..self, context: Some(context), }
}

///|
/// Return a location view shifted forward by a byte offset and a point extent.
/// The syntax data and node identities are shared; the original tree is unchanged.
/// Columns shift only on source row zero. Invalid offsets and overflow raise
/// EditError. Validation visits the subtree; child navigation shares its data.
pub fn Tree::root_node_with_offset(
  self : Tree,
  offset_bytes : Int32,
  offset_extent : Point,
) -> Node raise EditError {
  validate_point(offset_extent, offset_bytes)
  self.root.with_context({
    byte_delta: offset_bytes,
    origin: { row: 0, column: 0, },
    position: offset_extent,
  })
}

///|
/// Relocate a retained node handle after an edit, preserving its syntax and size.
/// Use Tree::edit to edit the tree's contents; this method only adjusts the
/// retained handle's starting location, as ts_node_edit does. The returned view
/// and its children retain their identities, and the original handle is unchanged.
pub fn Node::edited(self : Node, edit : InputEdit) -> Node raise EditError {
  let (position, byte) = self.start_position().edited(self.start_byte(), edit)
  if position == self.start_position() && byte == self.start_byte() {
    return self
  }
  self.with_context({
    byte_delta: byte - self.data.start_byte,
    origin: self.data.start_point,
    position,
  })
}
