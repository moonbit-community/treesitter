// Port of tree-sitter lib/src/node.c.

///|
let ts_node_max_recursive_search_depth : Int32 = 64

///|
/// `TSNode`: `context` holds the start byte, start point and alias; `id` is
/// the subtree slot (`None` for the null node).
pub struct Node {
  priv start_byte : UInt32
  priv start_row : UInt32
  priv start_column : UInt32
  priv alias : Int32
  priv id : SubtreeSlot?
  priv tree : Tree?
}

///|
priv struct NodeChildIterator {
  parent : Subtree
  tree : Tree?
  mut position : Length
  mut child_index : Int32
  mut structural_child_index : Int32
  alias_sequence : Int32?
}

///|
/// `ts_node_new`.
pub fn Node::new(
  tree : Tree?,
  subtree : SubtreeSlot?,
  position : Length,
  alias : Int32,
) -> Node {
  {
    start_byte: position.bytes,
    start_row: position.extent.row,
    start_column: position.extent.column,
    alias,
    id: subtree,
    tree,
  }
}

///|
fn node_null() -> Node {
  Node::new(None, None, length_zero(), 0)
}

///|
pub fn Node::start_byte(self : Node) -> UInt32 {
  self.start_byte
}

///|
pub fn Node::start_point(self : Node) -> Point {
  { row: self.start_row, column: self.start_column, }
}

///|
pub fn Node::alias(self : Node) -> Int32 {
  self.alias
}

///|
pub fn Node::tree(self : Node) -> Tree? {
  self.tree
}

///|
pub fn Node::slot(self : Node) -> SubtreeSlot? {
  self.id
}

///|
/// `ts_node__subtree`.
pub fn Node::subtree(self : Node) -> Subtree {
  self.id.unwrap().get()
}

///|
fn Node::lang(self : Node) -> @language.Language {
  self.tree.unwrap().language
}

///|
pub fn Node::same_id(self : Node, other : Node) -> Bool {
  match (self.id, other.id) {
    (None, None) => true
    (Some(a), Some(b)) => a.same(b)
    _ => false
  }
}

///|
/// `ts_node_id`: a value standing in for the subtree slot's address.
pub fn Node::node_id(self : Node) -> UInt64 {
  match self.id {
    None => 0
    Some(slot) =>
      (slot.owner.to_uint64() << 24) | ((slot.index & 0xFFFFFF).to_uint64() + 1)
  }
}

///|
fn Node::iterate_children(self : Node) -> NodeChildIterator {
  let subtree = self.subtree()
  if subtree.child_count() == 0 {
    return {
      parent: Null,
      tree: self.tree,
      position: length_zero(),
      child_index: 0,
      structural_child_index: 0,
      alias_sequence: None,
    }
  }
  {
    tree: self.tree,
    parent: subtree,
    position: { bytes: self.start_byte(), extent: self.start_point(), },
    child_index: 0,
    structural_child_index: 0,
    alias_sequence: self.lang().alias_sequence(subtree.ptr().production_id),
  }
}

///|
fn NodeChildIterator::copy(self : NodeChildIterator) -> NodeChildIterator {
  { ..self, }
}

///|
fn NodeChildIterator::done(self : NodeChildIterator) -> Bool {
  self.child_index == self.parent.child_count()
}

///|
fn NodeChildIterator::next(self : NodeChildIterator) -> Node? {
  if self.parent.is_null() || self.done() {
    return None
  }
  let slot = self.parent.child_slot(self.child_index)
  let child = slot.get()
  let mut alias_symbol = 0
  if !child.extra() {
    if self.alias_sequence is Some(offset) {
      alias_symbol = self.tree.unwrap().language.alias_sequence_value(
        offset + self.structural_child_index,
      )
    }
    self.structural_child_index += 1
  }
  if self.child_index > 0 {
    self.position = length_add(self.position, child.padding())
  }
  let result = Node::new(self.tree, Some(slot), self.position, alias_symbol)
  self.position = length_add(self.position, child.size())
  self.child_index += 1
  Some(result)
}

///|
fn Node::is_relevant(self : Node, include_anonymous : Bool) -> Bool {
  let tree = self.subtree()
  if include_anonymous {
    tree.visible() || self.alias != 0
  } else {
    let alias = self.alias
    if alias != 0 {
      self.lang().symbol_metadata_of(alias).named
    } else {
      tree.visible() && tree.named()
    }
  }
}

///|
fn Node::relevant_child_count(self : Node, include_anonymous : Bool) -> UInt32 {
  let tree = self.subtree()
  if tree.child_count() > 0 {
    if include_anonymous {
      tree.ptr().visible_child_count
    } else {
      tree.ptr().named_child_count
    }
  } else {
    0
  }
}

///|
fn Node::child_impl(
  self : Node,
  child_index : UInt32,
  include_anonymous : Bool,
) -> Node {
  let mut result = self
  let mut child_index = child_index
  let mut did_descend = true
  while did_descend {
    did_descend = false
    let mut index : UInt32 = 0
    let iterator = result.iterate_children()
    while iterator.next() is Some(child) {
      if child.is_relevant(include_anonymous) {
        if index == child_index {
          return child
        }
        index += 1
      } else {
        let grandchild_index = child_index - index
        let grandchild_count = child.relevant_child_count(include_anonymous)
        if grandchild_index < grandchild_count {
          did_descend = true
          result = child
          child_index = grandchild_index
          break
        }
        index += grandchild_count
      }
    }
  }
  node_null()
}

///|
fn subtree_has_trailing_empty_descendant_iterative(
  tree : Subtree,
  other : SubtreeSlot,
) -> Bool {
  let stack : Array[Subtree] = []
  let mut subtree = tree
  for ;; {
    for i = subtree.child_count(); i > 0; i = i - 1 {
      let slot = subtree.child_slot(i - 1)
      let child = slot.get()
      if child.total_bytes() > 0 {
        break
      }
      // Distinct inline leaves can have identical contents; compare their
      // slots.
      if slot.same(other) {
        return true
      }
      if child.child_count() > 0 {
        stack.push(child)
      }
    }
    match stack.pop() {
      Some(next) => subtree = next
      None => break
    }
  }
  false
}

///|
fn subtree_has_trailing_empty_descendant_bounded(
  tree : Subtree,
  other : SubtreeSlot,
  depth : Int32,
  too_deep : Ref[Bool],
) -> Bool {
  for i = tree.child_count(); i > 0; i = i - 1 {
    let slot = tree.child_slot(i - 1)
    let child = slot.get()
    if child.total_bytes() > 0 {
      break
    }
    if slot.same(other) {
      return true
    }
    // A nonmatching leaf cannot contain the target.
    if child.child_count() == 0 {
      continue
    }
    if depth == 0 {
      too_deep.val = true
      return false
    }
    if subtree_has_trailing_empty_descendant_bounded(
        child,
        other,
        depth - 1,
        too_deep,
      ) {
      return true
    }
    if too_deep.val {
      return false
    }
  }
  false
}

///|
fn subtree_has_trailing_empty_descendant(
  tree : Subtree,
  other : SubtreeSlot,
) -> Bool {
  let too_deep = Ref(false)
  let found = subtree_has_trailing_empty_descendant_bounded(
    tree, other, ts_node_max_recursive_search_depth, too_deep,
  )
  if too_deep.val {
    subtree_has_trailing_empty_descendant_iterative(tree, other)
  } else {
    found
  }
}

///|
fn Node::prev_sibling_impl(self : Node, include_anonymous : Bool) -> Node {
  let self_subtree = self.subtree()
  let self_is_empty = self_subtree.total_bytes() == 0
  let target_end_byte = self.end_byte()
  let mut node = self.parent()
  let mut earlier_node = node_null()
  let mut earlier_node_is_relevant = false
  while !node.is_null() {
    let mut earlier_child = node_null()
    let mut earlier_child_is_relevant = false
    let mut found_child_containing_target = false
    let mut child = node_null()
    let iterator = node.iterate_children()
    while iterator.next() is Some(next) {
      child = next
      if child.same_id(self) {
        break
      }
      if iterator.position.bytes > target_end_byte {
        found_child_containing_target = true
        break
      }
      if iterator.position.bytes == target_end_byte &&
        (
          !self_is_empty ||
          subtree_has_trailing_empty_descendant(
            child.subtree(),
            self.id.unwrap(),
          )
        ) {
        found_child_containing_target = true
        break
      }
      if child.is_relevant(include_anonymous) {
        earlier_child = child
        earlier_child_is_relevant = true
      } else if child.relevant_child_count(include_anonymous) > 0 {
        earlier_child = child
        earlier_child_is_relevant = false
      }
    }
    if found_child_containing_target {
      if !earlier_child.is_null() {
        earlier_node = earlier_child
        earlier_node_is_relevant = earlier_child_is_relevant
      }
      node = child
    } else if earlier_child_is_relevant {
      return earlier_child
    } else if !earlier_child.is_null() {
      node = earlier_child
    } else if earlier_node_is_relevant {
      return earlier_node
    } else {
      node = earlier_node
      earlier_node = node_null()
      earlier_node_is_relevant = false
    }
  }
  node_null()
}

///|
fn Node::next_sibling_impl(self : Node, include_anonymous : Bool) -> Node {
  let target_end_byte = self.end_byte()
  let mut node = self.parent()
  let mut later_node = node_null()
  let mut later_node_is_relevant = false
  while !node.is_null() {
    let mut later_child = node_null()
    let mut later_child_is_relevant = false
    let mut child_containing_target = node_null()
    let iterator = node.iterate_children()
    while iterator.next() is Some(child) {
      if iterator.position.bytes <= target_end_byte {
        continue
      }
      let start_byte = self.start_byte()
      let child_start_byte = child.start_byte()
      let is_empty = start_byte == target_end_byte
      let contains_target = if is_empty {
        child_start_byte < start_byte
      } else {
        child_start_byte <= start_byte
      }
      if contains_target {
        if !child.subtree().ptr_eq(self.subtree()) {
          child_containing_target = child
        }
      } else if child.is_relevant(include_anonymous) {
        later_child = child
        later_child_is_relevant = true
        break
      } else if child.relevant_child_count(include_anonymous) > 0 {
        later_child = child
        later_child_is_relevant = false
        break
      }
    }
    if !child_containing_target.is_null() {
      if !later_child.is_null() {
        later_node = later_child
        later_node_is_relevant = later_child_is_relevant
      }
      node = child_containing_target
    } else if later_child_is_relevant {
      return later_child
    } else if !later_child.is_null() {
      node = later_child
    } else if later_node_is_relevant {
      return later_node
    } else {
      node = later_node
    }
  }
  node_null()
}

///|
fn Node::first_child_for_byte_impl(
  self : Node,
  goal : UInt32,
  include_anonymous : Bool,
) -> Node {
  let mut node = self
  let mut did_descend = true
  let mut last_iterator : NodeChildIterator? = None
  while did_descend {
    did_descend = false
    let mut iterator = node.iterate_children()
    // loop:
    for ;; {
      while iterator.next() is Some(child) {
        if child.end_byte() > goal {
          if child.is_relevant(include_anonymous) {
            return child
          } else if child.child_count() > 0 {
            if iterator.child_index < child.subtree().child_count() {
              last_iterator = Some(iterator.copy())
            }
            did_descend = true
            node = child
            break
          }
        }
      }
      if !did_descend && last_iterator is Some(saved) {
        iterator = saved
        last_iterator = None
        continue
      }
      break
    }
  }
  node_null()
}

///|
fn Node::descendant_for_byte_range_impl(
  self : Node,
  range_start : UInt32,
  range_end : UInt32,
  include_anonymous : Bool,
) -> Node {
  if range_start > range_end {
    return node_null()
  }
  let mut node = self
  let mut last_visible_node = self
  let mut did_descend = true
  while did_descend {
    did_descend = false
    let iterator = node.iterate_children()
    while iterator.next() is Some(child) {
      let node_end = iterator.position.bytes
      // The end of this node must extend far enough forward to touch the end
      // of the range
      if node_end < range_end {
        continue
      }
      // ...and exceed the start of the range, unless the node itself is
      // empty, in which case it must at least be equal to the start of the
      // range.
      let is_empty = child.start_byte() == node_end
      if (if is_empty {
          node_end < range_start
        } else {
          node_end <= range_start
        }) {
        continue
      }
      // The start of this node must extend far enough backward to touch the
      // start of the range.
      if range_start < child.start_byte() {
        break
      }
      node = child
      if node.is_relevant(include_anonymous) {
        last_visible_node = node
      }
      did_descend = true
      break
    }
  }
  last_visible_node
}

///|
fn Node::descendant_for_point_range_impl(
  self : Node,
  range_start : Point,
  range_end : Point,
  include_anonymous : Bool,
) -> Node {
  if point_gt(range_start, range_end) {
    return node_null()
  }
  let mut node = self
  let mut last_visible_node = self
  let mut did_descend = true
  while did_descend {
    did_descend = false
    let iterator = node.iterate_children()
    while iterator.next() is Some(child) {
      let node_end = iterator.position.extent
      // The end of this node must extend far enough forward to touch the end
      // of the range
      if point_lt(node_end, range_end) {
        continue
      }
      // ...and exceed the start of the range, unless the node itself is
      // empty, in which case it must at least be equal to the start of the
      // range.
      let is_empty = point_eq(child.start_point(), node_end)
      if (if is_empty {
          point_lt(node_end, range_start)
        } else {
          point_lte(node_end, range_start)
        }) {
        continue
      }
      // The start of this node must extend far enough backward to touch the
      // start of the range.
      if point_lt(range_start, child.start_point()) {
        break
      }
      node = child
      if node.is_relevant(include_anonymous) {
        last_visible_node = node
      }
      did_descend = true
      break
    }
  }
  last_visible_node
}

// TSNode - public

///|
pub fn Node::end_byte(self : Node) -> UInt32 {
  self.start_byte() + self.subtree().size().bytes
}

///|
pub fn Node::end_point(self : Node) -> Point {
  point_add(self.start_point(), self.subtree().size().extent)
}

///|
/// `ts_node_symbol`.
pub fn Node::symbol(self : Node) -> Int32 {
  let mut symbol = self.alias
  if symbol == 0 {
    symbol = self.subtree().symbol()
  }
  self.lang().public_symbol(symbol)
}

///|
/// `ts_node_type`.
pub fn Node::kind(self : Node) -> String {
  let mut symbol = self.alias
  if symbol == 0 {
    symbol = self.subtree().symbol()
  }
  self.lang().symbol_name(symbol).unwrap_or("")
}

///|
/// `ts_node_language`.
pub fn Node::language(self : Node) -> @language.Language {
  self.lang()
}

///|
/// `ts_node_grammar_symbol`.
pub fn Node::grammar_symbol(self : Node) -> Int32 {
  self.subtree().symbol()
}

///|
/// `ts_node_grammar_type`.
pub fn Node::grammar_kind(self : Node) -> String {
  self.lang().symbol_name(self.subtree().symbol()).unwrap_or("")
}

///|
/// `ts_node_string`.
pub fn Node::to_sexp(self : Node) -> String {
  let alias_symbol = self.alias
  self
  .subtree()
  .to_sexp(
    alias_symbol,
    self.lang().symbol_metadata_of(alias_symbol).visible,
    self.lang(),
    false,
  )
}

///|
/// `ts_node_eq`.
pub impl Eq for Node with fn equal(self, other) {
  let same_tree = match (self.tree, other.tree) {
    (None, None) => true
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
  same_tree && self.same_id(other)
}

///|
/// `ts_node_is_null`.
pub fn Node::is_null(self : Node) -> Bool {
  self.id is None
}

///|
pub fn Node::is_extra(self : Node) -> Bool {
  self.subtree().extra()
}

///|
pub fn Node::is_named(self : Node) -> Bool {
  let alias = self.alias
  if alias != 0 {
    self.lang().symbol_metadata_of(alias).named
  } else {
    self.subtree().named()
  }
}

///|
pub fn Node::is_missing(self : Node) -> Bool {
  self.subtree().missing()
}

///|
pub fn Node::has_changes(self : Node) -> Bool {
  self.subtree().has_changes()
}

///|
pub fn Node::has_error(self : Node) -> Bool {
  self.is_error() || self.subtree().error_cost() > 0
}

///|
pub fn Node::is_error(self : Node) -> Bool {
  self.symbol() == @language.ts_builtin_sym_error
}

///|
pub fn Node::descendant_count(self : Node) -> UInt32 {
  self.subtree().visible_descendant_count() + 1
}

///|
pub fn Node::parse_state(self : Node) -> Int32 {
  self.subtree().parse_state()
}

///|
pub fn Node::next_parse_state(self : Node) -> Int32 {
  let language = self.lang()
  let state = self.parse_state()
  if state == ts_tree_state_none {
    return ts_tree_state_none
  }
  let symbol = self.grammar_symbol()
  language.next_state(state, symbol)
}

///|
/// `ts_node_parent`.
pub fn Node::parent(self : Node) -> Node {
  let mut node = self.tree.unwrap().root_node()
  if node.same_id(self) {
    return node_null()
  }
  for ;; {
    let next_node = node.child_with_descendant(self)
    if next_node.same_id(self) || next_node.is_null() {
      break
    }
    node = next_node
  }
  node
}

///|
priv struct DescendantSearchFrame {
  child : Node
  iterator : NodeChildIterator
}

///|
fn Node::child_with_empty_descendant_iterative(
  self : Node,
  descendant : Node,
) -> Node {
  let target_byte = descendant.start_byte()
  let stack : Array[DescendantSearchFrame] = []
  let mut iterator = self.iterate_children()
  let mut child = node_null()
  let mut result = node_null()
  // `scan`, `resume`, `no_descendant`, `found` and `done` labels from C.
  let mut resume = false
  let mut found = false
  for ;; {
    if resume {
      resume = false
      // resume:
      if !(iterator.position.bytes <= target_byte || child.child_count() == 0) {
        if child.is_relevant(true) {
          result = child
          found = true
          break
        }
        iterator = child.iterate_children()
      }
    }
    // scan:
    let mut descended = false
    let mut no_descendant = false
    while iterator.next() is Some(next) {
      child = next
      if child.start_byte() > target_byte {
        no_descendant = true
        break
      }
      if child.same_id(descendant) {
        result = child
        found = true
        break
      }
      if iterator.position.bytes >= target_byte && child.child_count() > 0 {
        stack.push({ child, iterator: iterator.copy(), })
        iterator = child.iterate_children()
        descended = true
        break
      }
      // resume:
      if iterator.position.bytes <= target_byte || child.child_count() == 0 {
        continue
      }
      if child.is_relevant(true) {
        result = child
        found = true
        break
      }
      iterator = child.iterate_children()
      descended = true
      break
    }
    if found {
      break
    }
    if descended {
      continue
    }
    ignore(no_descendant)
    // no_descendant:
    match stack.pop() {
      Some(frame) => {
        child = frame.child
        iterator = frame.iterator
        resume = true
      }
      None => return result
    }
  }
  // found:
  while stack.pop() is Some(frame) {
    if frame.child.is_relevant(true) {
      result = frame.child
    }
  }
  result
}

///|
fn Node::child_with_empty_descendant_bounded(
  self : Node,
  descendant : Node,
  depth : Int32,
  too_deep : Ref[Bool],
) -> Node {
  let target_byte = descendant.start_byte()
  let mut node = self
  for ;; {
    let iterator = node.iterate_children()
    for ;; {
      match iterator.next() {
        Some(next) if next.start_byte() <= target_byte => node = next
        _ => return node_null()
      }
      if node.same_id(descendant) {
        return node
      }
      if iterator.position.bytes >= target_byte && node.child_count() > 0 {
        if depth == 0 {
          too_deep.val = true
          return node_null()
        }
        let child = node.child_with_empty_descendant_bounded(
          descendant,
          depth - 1,
          too_deep,
        )
        if too_deep.val {
          return node_null()
        }
        if !child.is_null() {
          return if node.is_relevant(true) { node } else { child }
        }
      }
      if !(iterator.position.bytes <= target_byte || node.child_count() == 0) {
        break
      }
    }
    if node.is_relevant(true) {
      break
    }
  }
  node
}

///|
/// `ts_node_child_with_descendant`.
pub fn Node::child_with_descendant(self : Node, descendant : Node) -> Node {
  let start_byte = descendant.start_byte()
  let end_byte = descendant.end_byte()
  if start_byte == end_byte {
    let too_deep = Ref(false)
    let child = self.child_with_empty_descendant_bounded(
      descendant, ts_node_max_recursive_search_depth, too_deep,
    )
    return if too_deep.val {
      self.child_with_empty_descendant_iterative(descendant)
    } else {
      child
    }
  }
  let mut node = self
  for ;; {
    let iter = node.iterate_children()
    for ;; {
      match iter.next() {
        Some(next) if next.start_byte() <= start_byte => node = next
        _ => return node_null()
      }
      if node.same_id(descendant) {
        return node
      }
      if !(iter.position.bytes < end_byte || node.child_count() == 0) {
        break
      }
    }
    if node.is_relevant(true) {
      break
    }
  }
  node
}

///|
/// `ts_node_child`.
pub fn Node::child(self : Node, child_index : UInt32) -> Node {
  self.child_impl(child_index, true)
}

///|
/// `ts_node_named_child`.
pub fn Node::named_child(self : Node, child_index : UInt32) -> Node {
  self.child_impl(child_index, false)
}

///|
/// Follow a hidden node's first matching child without saving a traversal
/// stack. A different field blocks this field unless the child can contain it
/// explicitly. Returns `None` if resolving that case, a hidden extra, or
/// backtracking needs a cursor; otherwise `Some(result)` (possibly null).
fn Node::first_child_with_inherited_field(
  self : Node,
  field_id : Int32,
) -> Node? {
  let language = self.lang()
  let mut node = self
  let mut needs_backtracking = false
  for ;; {
    let iterator = node.iterate_children()
    let (field_map, field_map_end) = language.field_map(
      node.subtree().ptr().production_id,
    )
    let mut did_descend = false
    while iterator.next() is Some(child) {
      let visible = child.is_relevant(true)
      if !visible && child.child_count() == 0 {
        continue
      }
      // An extra has no field of its own, but a hidden one can hold fields.
      if child.subtree().extra() {
        if visible {
          continue
        }
        return None
      }
      let mut own_field_id = 0
      for m in field_map..<field_map_end {
        let map = language.field_map_entries[m]
        if !map.inherited &&
          map.child_index == iterator.structural_child_index - 1 {
          own_field_id = map.field_id
          break
        }
      }
      if own_field_id != 0 && own_field_id != field_id {
        if visible {
          continue
        }
        let (child_field_map, child_field_map_end) = language.field_map(
          child.subtree().ptr().production_id,
        )
        for m in child_field_map..<child_field_map_end {
          if language.field_map_entries[m].field_id == field_id {
            return None
          }
        }
        continue
      }
      if visible {
        return Some(child)
      }
      needs_backtracking = needs_backtracking || !iterator.done()
      node = child
      did_descend = true
      break
    }
    if !did_descend {
      return if needs_backtracking { None } else { Some(node_null()) }
    }
  }
}

///|
priv struct FieldSearchFrame {
  node : Node
  iterator : NodeChildIterator
  field_map : Int32
  field_map_end : Int32
}

///|
priv enum FieldSearchStep {
  Descend
  Scan
  NotFound
}

///|
/// `ts_node_child_by_field_id`.
pub fn Node::child_by_field_id(self : Node, field_id : Int32) -> Node {
  if field_id == 0 {
    return node_null()
  }
  let language = self.lang()
  let stack : Array[FieldSearchFrame] = []
  let mut node = self
  let mut iterator = node.iterate_children()
  let mut field_map = 0
  let mut field_map_end = 0
  let mut step = Descend
  for ;; {
    match step {
      Descend => {
        // descend:
        if node.child_count() == 0 {
          step = NotFound
          continue
        }
        let (start, end) = language.field_map(
          node.subtree().ptr().production_id,
        )
        field_map = start
        field_map_end = end
        if field_map == field_map_end {
          step = NotFound
          continue
        }
        // The field mappings are sorted by their field id. Scan all the
        // mappings to find the ones for the given field id.
        let mut exhausted = false
        while language.field_map_entries[field_map].field_id < field_id {
          field_map += 1
          if field_map == field_map_end {
            exhausted = true
            break
          }
        }
        if !exhausted {
          while language.field_map_entries[field_map_end - 1].field_id >
                field_id {
            field_map_end -= 1
            if field_map == field_map_end {
              exhausted = true
              break
            }
          }
        }
        if exhausted {
          step = NotFound
          continue
        }
        iterator = node.iterate_children()
        step = Scan
      }
      Scan => {
        // scan:
        step = NotFound
        while iterator.next() is Some(child) {
          if child.subtree().extra() {
            continue
          }
          let index = iterator.structural_child_index - 1
          let map = language.field_map_entries[field_map]
          if index < map.child_index {
            continue
          }
          // Hidden nodes' fields are "inherited" by their visible parent.
          if map.inherited {
            // An alias can make this child visible, keeping its fields inside
            // it.
            if child.is_relevant(true) {
              field_map += 1
              if field_map == field_map_end {
                break
              }
              continue
            }
            // If this is the *last* possible child node for this field, then
            // perform a tail call to avoid recursion.
            if field_map + 1 == field_map_end {
              node = child
              step = Descend
              break
            } else {
              // Otherwise, descend into this child, but if it doesn't contain
              // the field, continue searching subsequent children.
              stack.push({
                node,
                iterator: iterator.copy(),
                field_map,
                field_map_end,
              })
              node = child
              step = Descend
              break
            }
          } else if child.is_relevant(true) {
            return child
          } else if child.child_count() > 0 {
            // A field on a hidden child can be overridden by fields inside it.
            // Use the cursor's field resolution to find the first matching
            // child.
            match child.first_child_with_inherited_field(field_id) {
              Some(first) => {
                if !first.is_null() {
                  return first
                }
                field_map += 1
                while field_map < field_map_end &&
                      language.field_map_entries[field_map].child_index == index {
                  field_map += 1
                }
                if field_map == field_map_end {
                  break
                }
                continue
              }
              None => {
                let cursor = TreeCursor::new(node)
                let mut result = node_null()
                if cursor.goto_first_child() {
                  for ;; {
                    if cursor.current_field_id() == field_id {
                      result = cursor.current_node()
                      break
                    }
                    if !cursor.goto_next_sibling() {
                      break
                    }
                  }
                }
                if !result.is_null() {
                  return result
                }
                break
              }
            }
          } else {
            // Otherwise, continue searching subsequent children.
            field_map += 1
            if field_map == field_map_end {
              break
            }
          }
        }
      }
      NotFound =>
        // not_found:
        match stack.pop() {
          Some(frame) => {
            node = frame.node
            iterator = frame.iterator
            field_map = frame.field_map + 1
            field_map_end = frame.field_map_end
            step = if field_map == field_map_end { NotFound } else { Scan }
          }
          None => return node_null()
        }
    }
  }
}

///|
fn Node::field_name_from_language(
  self : Node,
  structural_child_index : Int32,
) -> String? {
  let language = self.lang()
  let (field_map, field_map_end) = language.field_map(
    self.subtree().ptr().production_id,
  )
  for m in field_map..<field_map_end {
    let map = language.field_map_entries[m]
    if !map.inherited && map.child_index == structural_child_index {
      return Some(language.field_names[map.field_id])
    }
  }
  None
}

///|
fn Node::field_name_for_child_impl(
  self : Node,
  child_index : UInt32,
  include_anonymous : Bool,
) -> String? {
  let mut result = self
  let mut child_index = child_index
  let mut did_descend = true
  let mut inherited_field_name : String? = None
  while did_descend {
    did_descend = false
    let mut index : UInt32 = 0
    let iterator = result.iterate_children()
    while iterator.next() is Some(child) {
      if child.is_relevant(include_anonymous) {
        if index == child_index {
          if child.is_extra() {
            return None
          }
          let field_name = result.field_name_from_language(
            iterator.structural_child_index - 1,
          )
          if field_name is Some(_) {
            return field_name
          }
          return inherited_field_name
        }
        index += 1
      } else {
        let grandchild_index = child_index - index
        let grandchild_count = child.relevant_child_count(include_anonymous)
        if grandchild_index < grandchild_count {
          // An extra takes no structural index, and the cursor gives the
          // nodes inside one no field from outside it.
          if child.is_extra() {
            inherited_field_name = None
          } else {
            let field_name = result.field_name_from_language(
              iterator.structural_child_index - 1,
            )
            if field_name is Some(_) {
              inherited_field_name = field_name
            }
          }
          did_descend = true
          result = child
          child_index = grandchild_index
          break
        }
        index += grandchild_count
      }
    }
  }
  None
}

///|
/// `ts_node_field_name_for_child`.
pub fn Node::field_name_for_child(self : Node, child_index : UInt32) -> String? {
  self.field_name_for_child_impl(child_index, true)
}

///|
/// `ts_node_field_name_for_named_child`.
pub fn Node::field_name_for_named_child(
  self : Node,
  named_child_index : UInt32,
) -> String? {
  self.field_name_for_child_impl(named_child_index, false)
}

///|
/// `ts_node_child_by_field_name`.
pub fn Node::child_by_field_name(self : Node, name : StringView) -> Node {
  let field_id = self.lang().field_id_for_name(name)
  self.child_by_field_id(field_id)
}

///|
pub fn Node::child_count(self : Node) -> UInt32 {
  let tree = self.subtree()
  if tree.child_count() > 0 {
    tree.ptr().visible_child_count
  } else {
    0
  }
}

///|
pub fn Node::named_child_count(self : Node) -> UInt32 {
  let tree = self.subtree()
  if tree.child_count() > 0 {
    tree.ptr().named_child_count
  } else {
    0
  }
}

///|
pub fn Node::next_sibling(self : Node) -> Node {
  self.next_sibling_impl(true)
}

///|
pub fn Node::next_named_sibling(self : Node) -> Node {
  self.next_sibling_impl(false)
}

///|
pub fn Node::prev_sibling(self : Node) -> Node {
  self.prev_sibling_impl(true)
}

///|
pub fn Node::prev_named_sibling(self : Node) -> Node {
  self.prev_sibling_impl(false)
}

///|
pub fn Node::first_child_for_byte(self : Node, byte : UInt32) -> Node {
  self.first_child_for_byte_impl(byte, true)
}

///|
pub fn Node::first_named_child_for_byte(self : Node, byte : UInt32) -> Node {
  self.first_child_for_byte_impl(byte, false)
}

///|
pub fn Node::descendant_for_byte_range(
  self : Node,
  start : UInt32,
  end : UInt32,
) -> Node {
  self.descendant_for_byte_range_impl(start, end, true)
}

///|
pub fn Node::named_descendant_for_byte_range(
  self : Node,
  start : UInt32,
  end : UInt32,
) -> Node {
  self.descendant_for_byte_range_impl(start, end, false)
}

///|
pub fn Node::descendant_for_point_range(
  self : Node,
  start : Point,
  end : Point,
) -> Node {
  self.descendant_for_point_range_impl(start, end, true)
}

///|
pub fn Node::named_descendant_for_point_range(
  self : Node,
  start : Point,
  end : Point,
) -> Node {
  self.descendant_for_point_range_impl(start, end, false)
}

///|
/// `ts_node_edit`: returns the edited node.
pub fn Node::edit(self : Node, edit : InputEdit) -> Node {
  let (start_point, start_byte) = point_edit(
    self.start_point(),
    self.start_byte(),
    edit,
  )
  {
    ..self,
    start_byte,
    start_row: start_point.row,
    start_column: start_point.column,
  }
}
