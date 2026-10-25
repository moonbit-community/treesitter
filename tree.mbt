// Port of `Tree` from tree-sitter lib/binding_rust/lib.rs.

///|
/// A tree that represents the syntactic structure of a source code file.
pub struct Tree {
  priv raw : @runtime.Tree
  priv language : Language
}

///|
/// The runtime tree wrapped by this tree.
pub fn Tree::raw(self : Tree) -> @runtime.Tree {
  self.raw
}

///|
/// Get the root node of the syntax tree.
pub fn Tree::root_node(self : Tree) -> Node {
  { raw: self.raw.root_node(), language: self.language, }
}

///|
/// Get the root node of the syntax tree, but with its position shifted
/// forward by the given offset.
pub fn Tree::root_node_with_offset(
  self : Tree,
  offset_bytes : Int32,
  offset_extent : Point,
) -> Node {
  {
    raw: self.raw.root_node_with_offset(
      to_u32(offset_bytes),
      offset_extent.to_ts(),
    ),
    language: self.language,
  }
}

///|
/// Get the language that was used to parse the syntax tree.
pub fn Tree::language(self : Tree) -> Language {
  self.language
}

///|
/// Edit the syntax tree to keep it in sync with source code that has been
/// edited.
///
/// You must describe the edit both in terms of byte offsets and in terms of
/// row/column coordinates.
pub fn Tree::edit(self : Tree, edit : InputEdit) -> Unit {
  self.raw.edit(edit.to_ts())
}

///|
/// Create a new [`TreeCursor`] starting from the root of the tree.
pub fn Tree::walk(self : Tree) -> TreeCursor {
  self.root_node().walk()
}

///|
/// Compare this old edited syntax tree to a new syntax tree representing the
/// same document, returning a sequence of ranges whose syntactic structure
/// has changed.
///
/// For this to work correctly, this syntax tree must have been edited such
/// that its ranges match up to the new tree. Generally, you'll want to call
/// this method right after calling one of the [`Parser::parse`] functions.
/// Call it on the old tree that was passed to parse, and pass the new tree
/// that was returned from `parse`.
pub fn Tree::changed_ranges(self : Tree, other : Tree) -> Array[Range] {
  self.raw.changed_ranges(other.raw).map(Range::from_ts)
}

///|
/// Get the included ranges that were used to parse the syntax tree.
pub fn Tree::included_ranges(self : Tree) -> Array[Range] {
  self.raw.included_ranges().map(Range::from_ts)
}

///|
/// A destination for DOT graphs ([`Tree::print_dot_graph`],
/// [`Parser::print_dot_graphs_to`]). Upstream writes the graphs to a file
/// descriptor as bytes, which are not always valid UTF-8: the label of an
/// `UNEXPECTED` character holds its low byte (C's `%c`), and a truncated log
/// message may end inside a character.
///
/// A `Buffer` receives exactly upstream's bytes. A `StringBuilder` receives
/// them decoded as UTF-8, with invalid sequences replaced by U+FFFD.
pub(open) trait DotGraphOutput {
  /// Write one piece of the graph output.
  fn write_dot_graph(Self, Bytes) -> Unit
}

///|
/// Appends the bytes, decoded lossily as UTF-8.
pub impl DotGraphOutput for StringBuilder with fn write_dot_graph(self, bytes) {
  self.write_string(@utf8.decode_lossy(bytes))
}

///|
/// Appends the bytes as they are.
pub impl DotGraphOutput for Buffer with fn write_dot_graph(self, bytes) {
  self.write_bytes(bytes)
}

///|
/// Print a graph of the tree to the given output. The graph is formatted in
/// the DOT language. You may want to pipe this graph directly to a `dot(1)`
/// process in order to generate SVG output.
pub fn[W : DotGraphOutput] Tree::print_dot_graph(
  self : Tree,
  output : W,
) -> Unit {
  let buffer = Buffer()
  self.raw.print_dot_graph(buffer)
  output.write_dot_graph(buffer.to_bytes())
}

///|
/// Create a shallow copy of the syntax tree. This is very fast; the copy can
/// be edited independently of the original.
pub fn Tree::clone(self : Tree) -> Tree {
  { raw: self.raw.copy(), language: self.language, }
}

///|
/// Formats as `{Tree <root node debug text>}`.
pub impl Debug for Tree with fn to_repr(self) {
  Repr::literal("{Tree \{self.root_node().debug_text()}}")
}
