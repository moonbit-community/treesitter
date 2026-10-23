///|
/// The generated language used to construct this node.
pub fn Node::language(self : Node) -> @language.Language {
  self.data.language
}

///|
pub fn Node::child_by_field_id(self : Node, id : Int32) -> Node? {
  match self.language().field_name(id) {
    Some(name) => self.child_by_field_name(name)
    None => None
  }
}

///|
pub fn Node::children_by_field_id(self : Node, id : Int32) -> Array[Node] {
  self
  .language()
  .field_name(id)
  .map(name => self.children_by_field_name(name))
  .unwrap_or([])
}

///|
/// The current field's one-based id, or None when the node has no field.
pub fn TreeCursor::field_id(self : TreeCursor) -> Int32? {
  match self.field_name() {
    Some(name) => self.node().language().field_id(name)
    None => None
  }
}
