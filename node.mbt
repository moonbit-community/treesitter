// Port of `Node` from tree-sitter lib/binding_rust/lib.rs. Methods that
// return a possibly-null `TSNode` upstream return `Node?` here.

///|
/// A single node within a syntax [`Tree`].
pub struct Node {
  priv raw : @runtime.Node
  priv language : Language
}

///|
fn Node::wrap(raw : @runtime.Node, language : Language) -> Node? {
  if raw.is_null() {
    None
  } else {
    Some({ raw, language, })
  }
}

///|
/// The runtime node wrapped by this node.
pub fn Node::raw(self : Node) -> @runtime.Node {
  self.raw
}

///|
/// Get a numeric id for this node that is unique.
///
/// Within a given syntax tree, no two nodes have the same id. However:
///
/// - If a new tree is created based on an older tree, and a node from the old
///   tree is reused in the process, then that node will have the same id in
///   both trees.
/// - A node not marked as having changes does not guarantee it was reused.
/// - If a node is marked as having changed in the old tree, it will not be
///   reused.
pub fn Node::id(self : Node) -> UInt64 {
  self.raw.node_id()
}

///|
/// Get this node's type as a numerical id.
pub fn Node::kind_id(self : Node) -> Int32 {
  self.raw.symbol()
}

///|
/// Get the node's type as a numerical id as it appears in the grammar
/// ignoring aliases.
pub fn Node::grammar_id(self : Node) -> Int32 {
  self.raw.grammar_symbol()
}

///|
/// Get this node's type as a string.
pub fn Node::kind(self : Node) -> String {
  self.raw.kind()
}

///|
/// Get this node's symbol name as it appears in the grammar ignoring
/// aliases as a string.
pub fn Node::grammar_name(self : Node) -> String {
  self.raw.grammar_kind()
}

///|
/// Get the [`Language`] that was used to parse this node's syntax tree.
pub fn Node::language(self : Node) -> Language {
  self.language
}

///|
/// Check if this node is *named*.
///
/// Named nodes correspond to named rules in the grammar, whereas *anonymous*
/// nodes correspond to string literals in the grammar.
pub fn Node::is_named(self : Node) -> Bool {
  self.raw.is_named()
}

///|
/// Check if this node is *extra*.
///
/// Extra nodes represent things like comments, which are not required by the
/// grammar, but can appear anywhere.
pub fn Node::is_extra(self : Node) -> Bool {
  self.raw.is_extra()
}

///|
/// Check if this node has been edited.
pub fn Node::has_changes(self : Node) -> Bool {
  self.raw.has_changes()
}

///|
/// Check if this node represents a syntax error or contains any syntax
/// errors anywhere within it.
pub fn Node::has_error(self : Node) -> Bool {
  self.raw.has_error()
}

///|
/// Check if this node represents a syntax error.
///
/// Syntax errors represent parts of the code that could not be incorporated
/// into a valid syntax tree.
pub fn Node::is_error(self : Node) -> Bool {
  self.raw.is_error()
}

///|
/// Get the parse state immediately before this node.
///
/// For a missing node, this is the state from the recovery path that was
/// selected by the parser. It can be used with
/// [`Language::lookahead_iterator`] to inspect the symbols that are valid in
/// that state. This does not necessarily include every symbol that could be
/// recovered by inserting a missing node, because the recovery process can
/// consider multiple stack versions.
pub fn Node::parse_state(self : Node) -> Int32 {
  self.raw.parse_state()
}

///|
/// Get the parse state after this node.
pub fn Node::next_parse_state(self : Node) -> Int32 {
  self.raw.next_parse_state()
}

///|
/// Check if this node is *missing*.
///
/// Missing nodes are inserted by the parser in order to recover from certain
/// kinds of syntax errors.
pub fn Node::is_missing(self : Node) -> Bool {
  self.raw.is_missing()
}

///|
/// Get the byte offset where this node starts.
pub fn Node::start_byte(self : Node) -> Int32 {
  from_u32(self.raw.start_byte())
}

///|
/// Get the byte offset where this node ends.
pub fn Node::end_byte(self : Node) -> Int32 {
  from_u32(self.raw.end_byte())
}

///|
/// Get the byte range of source code that this node represents, as
/// `(start, end)`.
pub fn Node::byte_range(self : Node) -> (Int32, Int32) {
  (self.start_byte(), self.end_byte())
}

///|
/// Get the range of source code that this node represents, both in terms of
/// raw bytes and of row/column coordinates.
pub fn Node::range(self : Node) -> Range {
  {
    start_byte: self.start_byte(),
    end_byte: self.end_byte(),
    start_point: self.start_position(),
    end_point: self.end_position(),
  }
}

///|
/// Get this node's start position in terms of rows and columns.
pub fn Node::start_position(self : Node) -> Point {
  Point::from_ts(self.raw.start_point())
}

///|
/// Get this node's end position in terms of rows and columns.
pub fn Node::end_position(self : Node) -> Point {
  Point::from_ts(self.raw.end_point())
}

///|
/// Get the node's child at the given index, where zero represents the first
/// child.
///
/// This method is fairly fast, but its cost is technically log(i), so if you
/// might be iterating over a long list of children, you should use
/// [`Node::children`] instead.
pub fn Node::child(self : Node, i : Int32) -> Node? {
  Node::wrap(self.raw.child(i.reinterpret_as_uint()), self.language)
}

///|
/// Get this node's number of children.
pub fn Node::child_count(self : Node) -> Int32 {
  self.raw.child_count().reinterpret_as_int()
}

///|
/// Get this node's *named* child at the given index.
///
/// This method is fairly fast, but its cost is technically log(i), so if you
/// might be iterating over a long list of children, you should use
/// [`Node::named_children`] instead.
pub fn Node::named_child(self : Node, i : Int32) -> Node? {
  Node::wrap(self.raw.named_child(i.reinterpret_as_uint()), self.language)
}

///|
/// Get this node's number of *named* children.
pub fn Node::named_child_count(self : Node) -> Int32 {
  self.raw.named_child_count().reinterpret_as_int()
}

///|
/// Get the first child with the given field name.
///
/// If multiple children may have the same field name, access them using
/// [`children_by_field_name`](Node::children_by_field_name).
pub fn Node::child_by_field_name(self : Node, field_name : StringView) -> Node? {
  Node::wrap(self.raw.child_by_field_name(field_name), self.language)
}

///|
/// Get this node's child with the given numerical field id.
///
/// See also [`child_by_field_name`](Node::child_by_field_name). You can
/// convert a field name to an id using [`Language::field_id_for_name`].
pub fn Node::child_by_field_id(self : Node, field_id : Int32) -> Node? {
  Node::wrap(self.raw.child_by_field_id(field_id), self.language)
}

///|
/// Get the field name of this node's child at the given index.
pub fn Node::field_name_for_child(self : Node, child_index : Int32) -> String? {
  self.raw.field_name_for_child(child_index.reinterpret_as_uint())
}

///|
/// Get the field name of this node's named child at the given index.
pub fn Node::field_name_for_named_child(
  self : Node,
  named_child_index : Int32,
) -> String? {
  self.raw.field_name_for_named_child(named_child_index.reinterpret_as_uint())
}

///|
/// Iterate over this node's children.
///
/// A [`TreeCursor`] is used to retrieve the children efficiently. Obtain a
/// [`TreeCursor`] by calling [`Tree::walk`] or [`Node::walk`]. To avoid
/// unnecessary allocations, you should reuse the same cursor for subsequent
/// calls to this method.
///
/// If you're walking the tree recursively, you may want to use the
/// [`TreeCursor`] APIs directly instead.
pub fn Node::children(self : Node, cursor : TreeCursor) -> Iter[Node] {
  cursor.reset(self)
  ignore(cursor.goto_first_child())
  let count = self.child_count()
  let mut i = 0
  Iter::new(
    () => {
      if i >= count {
        return None
      }
      i += 1
      let result = cursor.node()
      ignore(cursor.goto_next_sibling())
      Some(result)
    },
    size_hint=count,
  )
}

///|
/// Iterate over this node's named children.
///
/// See also [`Node::children`].
pub fn Node::named_children(self : Node, cursor : TreeCursor) -> Iter[Node] {
  cursor.reset(self)
  ignore(cursor.goto_first_child())
  let count = self.named_child_count()
  let mut i = 0
  Iter::new(
    () => {
      if i >= count {
        return None
      }
      i += 1
      while !cursor.node().is_named() {
        if !cursor.goto_next_sibling() {
          break
        }
      }
      let result = cursor.node()
      ignore(cursor.goto_next_sibling())
      Some(result)
    },
    size_hint=count,
  )
}

///|
/// Iterate over this node's children with a given field name.
///
/// See also [`Node::children`].
pub fn Node::children_by_field_name(
  self : Node,
  field_name : StringView,
  cursor : TreeCursor,
) -> Iter[Node] {
  let field_id = self.language.field_id_for_name(field_name)
  let mut done = field_id is None
  if !done {
    cursor.reset(self)
    ignore(cursor.goto_first_child())
  }
  Iter::new(() => {
    if !done {
      while cursor.field_id() != field_id {
        if !cursor.goto_next_sibling() {
          return None
        }
      }
      let result = cursor.node()
      if !cursor.goto_next_sibling() {
        done = true
      }
      return Some(result)
    }
    None
  })
}

///|
/// Iterate over this node's children with a given field id.
///
/// See also [`Node::children_by_field_name`].
pub fn Node::children_by_field_id(
  self : Node,
  field_id : Int32,
  cursor : TreeCursor,
) -> Iter[Node] {
  cursor.reset(self)
  ignore(cursor.goto_first_child())
  let mut done = false
  Iter::new(() => {
    if !done {
      while cursor.field_id() != Some(field_id) {
        if !cursor.goto_next_sibling() {
          return None
        }
      }
      let result = cursor.node()
      if !cursor.goto_next_sibling() {
        done = true
      }
      return Some(result)
    }
    None
  })
}

///|
/// Get this node's immediate parent.
/// Prefer [`child_with_descendant`](Node::child_with_descendant) for
/// iterating over this node's ancestors.
pub fn Node::parent(self : Node) -> Node? {
  Node::wrap(self.raw.parent(), self.language)
}

///|
/// Get the node that contains `descendant`.
///
/// Note that this can return `descendant` itself.
pub fn Node::child_with_descendant(self : Node, descendant : Node) -> Node? {
  Node::wrap(self.raw.child_with_descendant(descendant.raw), self.language)
}

///|
/// Get this node's next sibling.
pub fn Node::next_sibling(self : Node) -> Node? {
  Node::wrap(self.raw.next_sibling(), self.language)
}

///|
/// Get this node's previous sibling.
pub fn Node::prev_sibling(self : Node) -> Node? {
  Node::wrap(self.raw.prev_sibling(), self.language)
}

///|
/// Get this node's next named sibling.
pub fn Node::next_named_sibling(self : Node) -> Node? {
  Node::wrap(self.raw.next_named_sibling(), self.language)
}

///|
/// Get this node's previous named sibling.
pub fn Node::prev_named_sibling(self : Node) -> Node? {
  Node::wrap(self.raw.prev_named_sibling(), self.language)
}

///|
/// Get this node's first child that contains or starts after the given byte
/// offset.
pub fn Node::first_child_for_byte(self : Node, byte : Int32) -> Node? {
  Node::wrap(self.raw.first_child_for_byte(to_u32(byte)), self.language)
}

///|
/// Get this node's first named child that contains or starts after the given
/// byte offset.
pub fn Node::first_named_child_for_byte(self : Node, byte : Int32) -> Node? {
  Node::wrap(self.raw.first_named_child_for_byte(to_u32(byte)), self.language)
}

///|
/// Get the node's number of descendants, including one for the node itself.
pub fn Node::descendant_count(self : Node) -> Int32 {
  self.raw.descendant_count().reinterpret_as_int()
}

///|
/// Get the smallest node within this node that spans the given byte range.
pub fn Node::descendant_for_byte_range(
  self : Node,
  start : Int32,
  end : Int32,
) -> Node? {
  Node::wrap(
    self.raw.descendant_for_byte_range(to_u32(start), to_u32(end)),
    self.language,
  )
}

///|
/// Get the smallest named node within this node that spans the given byte
/// range.
pub fn Node::named_descendant_for_byte_range(
  self : Node,
  start : Int32,
  end : Int32,
) -> Node? {
  Node::wrap(
    self.raw.named_descendant_for_byte_range(to_u32(start), to_u32(end)),
    self.language,
  )
}

///|
/// Get the smallest node within this node that spans the given point range.
pub fn Node::descendant_for_point_range(
  self : Node,
  start : Point,
  end : Point,
) -> Node? {
  Node::wrap(
    self.raw.descendant_for_point_range(start.to_ts(), end.to_ts()),
    self.language,
  )
}

///|
/// Get the smallest named node within this node that spans the given point
/// range.
pub fn Node::named_descendant_for_point_range(
  self : Node,
  start : Point,
  end : Point,
) -> Node? {
  Node::wrap(
    self.raw.named_descendant_for_point_range(start.to_ts(), end.to_ts()),
    self.language,
  )
}

///|
/// Get an S-expression representing the node.
pub fn Node::to_sexp(self : Node) -> String {
  self.raw.to_sexp()
}

///|
/// Rust's `core::str::Utf8Error`, raised by [`Node::utf8_text`].
pub using @hir {type Utf8Error}

///|
/// The text of this node in `source`, decoded as UTF-8. Raises Rust's
/// `Utf8Error` when the bytes are not valid UTF-8; aborts, as Rust's slice
/// indexing panics, when the node's range is not within `source`.
pub fn Node::utf8_text(
  self : Node,
  source : BytesView,
) -> String raise @hir.Utf8Error {
  let text = source.exact_view(start=self.start_byte(), end=self.end_byte())
  String::from_array(@hir.from_utf8(text))
}

///|
/// The text of this node in UTF-16 `source` (node offsets are in bytes,
/// i.e. twice the code unit offsets).
pub fn Node::utf16_text(
  self : Node,
  source : ArrayView[UInt16],
) -> ArrayView[UInt16] {
  source.exact_view(start=self.start_byte() / 2, end=self.end_byte() / 2)
}

///|
/// Create a new [`TreeCursor`] starting from this node.
///
/// Note that the given node is considered the root of the cursor, and the
/// cursor cannot walk outside this node.
pub fn Node::walk(self : Node) -> TreeCursor {
  { raw: @runtime.TreeCursor::new(self.raw), language: self.language, }
}

///|
/// Edit this node to keep it in-sync with source code that has been edited,
/// returning the edited node (upstream mutates the `Copy` node in place).
///
/// This function is only rarely needed. When you edit a syntax tree with the
/// [`Tree::edit`] method, all of the nodes that you retrieve from the tree
/// afterward will already reflect the edit. You only need to use
/// [`Node::edit`] when you have a specific [`Node`] instance that you want to
/// keep and continue to use after an edit.
pub fn Node::edit(self : Node, edit : InputEdit) -> Node {
  { raw: self.raw.edit(edit.to_ts()), language: self.language, }
}

///|
/// Nodes are equal when they have the same id.
pub impl Eq for Node with fn equal(self, other) {
  self.raw.same_id(other.raw)
}

///|
/// Hashes the id and the context (start position and alias).
pub impl Hash for Node with fn hash_combine(self, hasher) {
  hasher.combine_uint64(self.raw.node_id())
  hasher.combine_uint(self.raw.start_byte())
  hasher.combine_uint(self.raw.start_point().row)
  hasher.combine_uint(self.raw.start_point().column)
  hasher.combine_int(self.raw.alias())
}

///|
/// The text of upstream's `Debug` impl: `{Node kind (row, column) - (row,
/// column)}`.
fn Node::debug_text(self : Node) -> String {
  "{Node \{self.kind()} \{self.start_position()} - \{self.end_position()}}"
}

///|
/// Formats as `{Node kind (row, column) - (row, column)}`.
pub impl Debug for Node with fn to_repr(self) {
  Repr::literal(self.debug_text())
}

///|
/// Formats as the node's S-expression (upstream's `Display`).
pub impl Show for Node with fn output(self, logger) {
  logger.write_string(self.to_sexp())
}
