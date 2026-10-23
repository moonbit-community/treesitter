// Port of tree-sitter lib/src/tree.h and lib/src/tree.c.

///|
pub struct Tree {
  mut root : Subtree
  language : @language.Language
  included_ranges : Array[Range]
}

///|
/// `ts_tree_new`.
pub fn Tree::new(
  root : Subtree,
  language : @language.Language,
  included_ranges : Array[Range],
) -> Tree {
  { root, language, included_ranges: included_ranges.copy(), }
}

///|
/// `ts_tree_copy`.
pub fn Tree::copy(self : Tree) -> Tree {
  self.root.retain()
  Tree::new(self.root, self.language, self.included_ranges)
}

///|
/// `ts_tree_delete`: release this tree's reference to its syntax.
pub fn Tree::delete(self : Tree) -> Unit {
  self.root.release()
}

///|
pub fn Tree::root(self : Tree) -> Subtree {
  self.root
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
  self.root = self.root.edit(edit)
}

///|
/// `ts_tree_included_ranges`.
pub fn Tree::included_ranges(self : Tree) -> Array[Range] {
  self.included_ranges.copy()
}
