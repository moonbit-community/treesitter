// Port of tree-sitter lib/src/reusable_node.h and lib/src/reduce_action.h.

///|
priv struct ReusableStackEntry {
  tree : Subtree
  child_index : Int32
  byte_offset : UInt32
}

///|
priv struct ReusableNode {
  stack : Array[ReusableStackEntry]
  mut last_external_token : Subtree
}

///|
fn ReusableNode::new() -> ReusableNode {
  { stack: [], last_external_token: Null, }
}

///|
fn ReusableNode::clear(self : ReusableNode) -> Unit {
  self.stack.clear()
  self.last_external_token = Null
}

///|
/// The value written over vacated slots by `release_scratch`.
let reusable_stack_entry_none : ReusableStackEntry = {
  tree: Null,
  child_index: 0,
  byte_offset: 0,
}

///|
/// `clear`, also overwriting the slots that popped entries leave in the
/// array's spare capacity on native targets, so that an idle parser does not
/// keep the previous tree alive (upstream's stale pointers do not own it).
fn ReusableNode::release_scratch(self : ReusableNode) -> Unit {
  self.clear()
  self.stack.release_unused(placeholder=reusable_stack_entry_none)
}

///|
fn ReusableNode::tree(self : ReusableNode) -> Subtree {
  if self.stack.length() > 0 {
    self.stack[self.stack.length() - 1].tree
  } else {
    Null
  }
}

///|
fn ReusableNode::byte_offset(self : ReusableNode) -> UInt32 {
  if self.stack.length() > 0 {
    self.stack[self.stack.length() - 1].byte_offset
  } else {
    0xFFFFFFFFU
  }
}

///|
fn ReusableNode::advance(self : ReusableNode) -> Unit {
  let last_entry = self.stack[self.stack.length() - 1]
  let byte_offset = last_entry.byte_offset + last_entry.tree.total_bytes()
  if last_entry.tree.has_external_tokens() {
    self.last_external_token = last_entry.tree.last_external_token()
  }
  let mut tree = Subtree::Null
  let mut next_index = 0
  for ;; {
    let popped_entry = self.stack.pop().unwrap()
    next_index = popped_entry.child_index + 1
    if self.stack.length() == 0 {
      return
    }
    tree = self.stack[self.stack.length() - 1].tree
    if !(tree.child_count() <= next_index) {
      break
    }
  }
  self.stack.push({
    tree: tree.children()[next_index],
    child_index: next_index,
    byte_offset,
  })
}

///|
fn ReusableNode::descend(self : ReusableNode) -> Bool {
  let last_entry = self.stack[self.stack.length() - 1]
  if last_entry.tree.child_count() > 0 {
    self.stack.push({
      tree: last_entry.tree.children()[0],
      child_index: 0,
      byte_offset: last_entry.byte_offset,
    })
    true
  } else {
    false
  }
}

///|
fn ReusableNode::advance_past_leaf(self : ReusableNode) -> Unit {
  while self.descend() {

  }
  self.advance()
}

///|
fn ReusableNode::reset(self : ReusableNode, tree : Subtree) -> Unit {
  self.clear()
  self.stack.push({ tree, child_index: 0, byte_offset: 0, })
  // Never reuse the root node, because it has a non-standard internal
  // structure due to transformations that are applied when it is accepted:
  // adding the EOF child and any extra children.
  if !self.descend() {
    self.clear()
  }
}

///|
priv struct ReduceAction {
  count : Int32
  symbol : Int32
  dynamic_precedence : Int32
  production_id : Int32
}

///|
fn reduce_action_set_add(
  set : Array[ReduceAction],
  new_action : ReduceAction,
) -> Unit {
  for action in set {
    if action.symbol == new_action.symbol && action.count == new_action.count {
      return
    }
  }
  set.push(new_action)
}
