///|
pub struct Tree {
  priv mut source_ranges : Array[Range]
  priv mut root : Node
  priv mut edited_length : Int32
  priv mut edited : Bool
  reused_subtrees : Int32
  parse_steps : Int32
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
