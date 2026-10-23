// Port of tree-sitter lib/src/tree.h, lib/src/tree.c and lib/src/point.c.

///|
/// A `const Subtree *`: a slot in a parent's children array (or a tree's
/// root). Upstream compares these pointers to tell nodes apart, so slots are
/// compared by array identity and index.
pub(all) struct SubtreeSlot {
  array : Array[Subtree]
  index : Int32
  /// The address of the slot's owner (parent subtree or tree), used to form
  /// node ids.
  owner : Int32
}

///|
pub fn SubtreeSlot::get(self : SubtreeSlot) -> Subtree {
  self.array[self.index]
}

///|
pub fn SubtreeSlot::same(self : SubtreeSlot, other : SubtreeSlot) -> Bool {
  physical_equal(self.array, other.array) && self.index == other.index
}

///|
/// The slot of a parent's `index`th child.
pub fn Subtree::child_slot(self : Subtree, index : Int32) -> SubtreeSlot {
  let data = self.ptr()
  { array: data.children, index, owner: data.address, }
}

///|
pub struct Tree {
  /// `root`, stored in a slot so that nodes can point at it.
  priv root_slot : Array[Subtree]
  language : @language.Language
  priv included_ranges : Array[Range]
  priv address : Int32
}

///|
/// `ts_tree_new`.
pub fn Tree::new(
  root : Subtree,
  language : @language.Language,
  included_ranges : Array[Range],
) -> Tree {
  {
    root_slot: [root],
    language,
    included_ranges: included_ranges.copy(),
    address: fresh_address(),
  }
}

///|
pub fn Tree::root(self : Tree) -> Subtree {
  self.root_slot[0]
}

///|
fn Tree::root_ref(self : Tree) -> SubtreeSlot {
  { array: self.root_slot, index: 0, owner: self.address, }
}

///|
/// `ts_tree_copy`.
pub fn Tree::copy(self : Tree) -> Tree {
  self.root().retain()
  Tree::new(self.root(), self.language, self.included_ranges)
}

///|
/// `ts_tree_delete`: release this tree's reference to its syntax.
pub fn Tree::delete(self : Tree) -> Unit {
  self.root().release()
}

///|
/// `ts_tree_root_node`.
pub fn Tree::root_node(self : Tree) -> Node {
  Node::new(Some(self), Some(self.root_ref()), self.root().padding(), 0)
}

///|
/// `ts_tree_root_node_with_offset`.
pub fn Tree::root_node_with_offset(
  self : Tree,
  offset_bytes : UInt32,
  offset_extent : Point,
) -> Node {
  let offset : Length = { bytes: offset_bytes, extent: offset_extent, }
  Node::new(
    Some(self),
    Some(self.root_ref()),
    length_add(offset, self.root().padding()),
    0,
  )
}

///|
/// `ts_tree_language`.
pub fn Tree::language(self : Tree) -> @language.Language {
  self.language
}

///|
/// `ts_tree_edit`.
pub fn Tree::edit(self : Tree, edit : InputEdit) -> Unit {
  for i in 0..<self.included_ranges.length() {
    self.included_ranges[i] = self.included_ranges[i].edit(edit)
  }
  self.root_slot[0] = self.root().edit(edit)
}

///|
/// `ts_tree_included_ranges`.
pub fn Tree::included_ranges(self : Tree) -> Array[Range] {
  self.included_ranges.copy()
}

///|
fn Tree::included_ranges_ref(self : Tree) -> Array[Range] {
  self.included_ranges
}

///|
/// `ts_tree_print_dot_graph`.
pub fn Tree::print_dot_graph(self : Tree, f : StringBuilder) -> Unit {
  self.root().print_dot_graph(self.language, f)
}

///|
/// `ts_point_edit`.
pub fn point_edit(
  point : Point,
  byte : UInt32,
  edit : InputEdit,
) -> (Point, UInt32) {
  let mut start_byte = byte
  let mut start_point = point
  if start_byte >= edit.old_end_byte {
    start_byte = edit.new_end_byte + (start_byte - edit.old_end_byte)
    start_point = point_add(
      edit.new_end_point,
      point_sub(start_point, edit.old_end_point),
    )
  } else if start_byte > edit.start_byte {
    start_byte = edit.new_end_byte
    start_point = edit.new_end_point
  }
  (start_point, start_byte)
}
