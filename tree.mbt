///|
pub struct Tree {
  priv mut source_ranges : Array[Range]
  priv scanner : ExternalScanner?
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

///|
/// Serialized external-scanner state at the end of the accepted parse.
pub fn Tree::external_scanner_state(self : Tree) -> Bytes {
  self.root.data.scan_after
}
