///|
pub struct Tree {
  priv root : Node
  source : Bytes
  language : @language.Language
}

///|
pub fn Tree::root_node(self : Tree) -> Node {
  self.root
}

///|
pub fn Tree::walk(self : Tree) -> TreeCursor {
  self.root.walk()
}
