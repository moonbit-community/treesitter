// Port of tree-sitter lib/src/tree_cursor.h and lib/src/tree_cursor.c.

///|
pub(all) struct TreeCursorEntry {
  subtree : SubtreeSlot
  position : Length
  child_index : Int32
  structural_child_index : Int32
  descendant_index : UInt32
}

///|
pub struct TreeCursor {
  priv mut tree : Tree?
  priv mut stack : Array[TreeCursorEntry]
  priv mut root_alias_symbol : Int32
}

///|
pub(all) enum TreeCursorStep {
  StepNone
  StepHidden
  StepVisible
} derive(Eq, Debug)

///|
priv struct CursorChildIterator {
  parent : Subtree
  tree : Tree?
  mut position : Length
  mut child_index : Int32
  mut structural_child_index : Int32
  mut descendant_index : UInt32
  alias_sequence : Int32?
}

///|
fn TreeCursor::language(self : TreeCursor) -> @language.Language {
  self.tree.unwrap().language
}

///|
fn TreeCursor::is_entry_visible(self : TreeCursor, index : Int32) -> Bool {
  let entry = self.stack[index]
  let subtree = entry.subtree.get()
  if index == 0 || subtree.visible() {
    true
  } else if !subtree.extra() {
    let parent_entry = self.stack[index - 1]
    self
    .language()
    .alias_at(
      parent_entry.subtree.get().ptr().production_id,
      entry.structural_child_index,
    ) !=
    0
  } else {
    false
  }
}

///|
fn TreeCursor::iterate_children(self : TreeCursor) -> CursorChildIterator {
  let last_entry = self.stack[self.stack.length() - 1]
  let subtree = last_entry.subtree.get()
  if subtree.child_count() == 0 {
    return {
      parent: Null,
      tree: self.tree,
      position: length_zero(),
      child_index: 0,
      structural_child_index: 0,
      descendant_index: 0,
      alias_sequence: None,
    }
  }
  let alias_sequence = self
    .language()
    .alias_sequence(subtree.ptr().production_id)
  let mut descendant_index = last_entry.descendant_index
  if self.is_entry_visible(self.stack.length() - 1) {
    descendant_index += 1
  }
  {
    tree: self.tree,
    parent: subtree,
    position: last_entry.position,
    child_index: 0,
    structural_child_index: 0,
    descendant_index,
    alias_sequence,
  }
}

///|
/// `ts_tree_cursor_child_iterator_next`: the next entry and its visibility.
fn CursorChildIterator::next(
  self : CursorChildIterator,
) -> (TreeCursorEntry, Bool)? {
  if self.parent.is_null() || self.child_index == self.parent.child_count() {
    return None
  }
  let slot = self.parent.child_slot(self.child_index)
  let child = slot.get()
  let result : TreeCursorEntry = {
    subtree: slot,
    position: self.position,
    child_index: self.child_index,
    structural_child_index: self.structural_child_index,
    descendant_index: self.descendant_index,
  }
  let mut visible = child.visible()
  let extra = child.extra()
  if !extra {
    if self.alias_sequence is Some(offset) {
      let language = self.tree.unwrap().language
      if language.alias_sequence_value(offset + self.structural_child_index) !=
        0 {
        visible = true
      }
    }
    self.structural_child_index += 1
  }
  self.descendant_index += child.visible_descendant_count()
  if visible {
    self.descendant_index += 1
  }
  self.position = length_add(self.position, child.size())
  self.child_index += 1
  if self.child_index < self.parent.child_count() {
    let next_child = self.parent.children()[self.child_index]
    self.position = length_add(self.position, next_child.padding())
  }
  Some((result, visible))
}

///|
/// Return a position that, when `b` is added to it, yields `a`. This can
/// only be computed if `b` has zero rows. Otherwise, this function returns
/// `length_undefined`, and the caller needs to recompute the position some
/// other way.
fn length_backtrack(a : Length, b : Length) -> Length {
  if length_is_undefined(a) || b.extent.row != 0 {
    return length_undefined
  }
  {
    bytes: a.bytes - b.bytes,
    extent: { row: a.extent.row, column: a.extent.column - b.extent.column, },
  }
}

///|
/// `ts_tree_cursor_child_iterator_previous`.
fn CursorChildIterator::previous(
  self : CursorChildIterator,
) -> (TreeCursorEntry, Bool)? {
  // This is mostly a reverse `next` taking into account unsigned underflow.
  // Upstream compares `(int8_t)child_index == -1`, so the index is truncated
  // to 8 bits here too.
  if self.parent.is_null() || (self.child_index & 0xFF) == 0xFF {
    return None
  }
  let slot = self.parent.child_slot(self.child_index)
  let child = slot.get()
  let result : TreeCursorEntry = {
    subtree: slot,
    position: self.position,
    child_index: self.child_index,
    structural_child_index: self.structural_child_index,
    descendant_index: 0,
  }
  let mut visible = child.visible()
  let extra = child.extra()
  self.position = length_backtrack(self.position, child.padding())
  self.child_index -= 1
  if !extra && self.alias_sequence is Some(offset) {
    let language = self.tree.unwrap().language
    if language.alias_sequence_value(offset + self.structural_child_index) != 0 {
      visible = true
    }
    if self.structural_child_index > 0 {
      self.structural_child_index -= 1
    }
  }
  // unsigned can underflow so compare it to child_count
  if self.child_index >= 0 && self.child_index < self.parent.child_count() {
    let previous_child = self.parent.children()[self.child_index]
    let size = previous_child.size()
    self.position = length_backtrack(self.position, size)
  }
  Some((result, visible))
}

///|
/// `ts_tree_cursor_new`.
pub fn TreeCursor::new(node : Node) -> TreeCursor {
  let cursor = { tree: None, stack: [], root_alias_symbol: 0, }
  cursor.init(node)
  cursor
}

///|
/// `ts_tree_cursor_reset`.
pub fn TreeCursor::reset(self : TreeCursor, node : Node) -> Unit {
  self.init(node)
}

///|
/// `ts_tree_cursor_init`.
fn TreeCursor::init(self : TreeCursor, node : Node) -> Unit {
  self.tree = node.tree
  self.root_alias_symbol = node.alias
  self.stack = [
    {
      subtree: node.id.unwrap(),
      position: { bytes: node.start_byte(), extent: node.start_point(), },
      child_index: 0,
      structural_child_index: 0,
      descendant_index: 0,
    },
  ]
}

///|
pub fn TreeCursor::goto_first_child_internal(
  self : TreeCursor,
) -> TreeCursorStep {
  let iterator = self.iterate_children()
  while iterator.next() is Some((entry, visible)) {
    if visible {
      self.stack.push(entry)
      return StepVisible
    }
    if entry.subtree.get().visible_child_count() > 0 {
      self.stack.push(entry)
      return StepHidden
    }
  }
  StepNone
}

///|
/// `ts_tree_cursor_goto_first_child`.
pub fn TreeCursor::goto_first_child(self : TreeCursor) -> Bool {
  for ;; {
    match self.goto_first_child_internal() {
      StepHidden => continue
      StepVisible => return true
      StepNone => return false
    }
  }
}

///|
pub fn TreeCursor::goto_last_child_internal(
  self : TreeCursor,
) -> TreeCursorStep {
  let iterator = self.iterate_children()
  if iterator.parent.is_null() || iterator.parent.child_count() == 0 {
    return StepNone
  }
  let mut last_entry : TreeCursorEntry? = None
  let mut last_step = StepNone
  while iterator.next() is Some((entry, visible)) {
    if visible {
      last_entry = Some(entry)
      last_step = StepVisible
    } else if entry.subtree.get().visible_child_count() > 0 {
      last_entry = Some(entry)
      last_step = StepHidden
    }
  }
  if last_entry is Some(entry) {
    self.stack.push(entry)
    return last_step
  }
  StepNone
}

///|
/// `ts_tree_cursor_goto_last_child`.
pub fn TreeCursor::goto_last_child(self : TreeCursor) -> Bool {
  for ;; {
    match self.goto_last_child_internal() {
      StepHidden => continue
      StepVisible => return true
      StepNone => return false
    }
  }
}

///|
fn TreeCursor::goto_first_child_for_byte_and_point(
  self : TreeCursor,
  goal_byte : UInt32,
  goal_point : Point,
) -> Int64 {
  let initial_size = self.stack.length()
  let mut visible_child_index : UInt32 = 0
  let mut did_descend = true
  while did_descend {
    did_descend = false
    let iterator = self.iterate_children()
    while iterator.next() is Some((entry, visible)) {
      let subtree = entry.subtree.get()
      let entry_end = length_add(entry.position, subtree.size())
      let at_goal = entry_end.bytes > goal_byte &&
        point_gt(entry_end.extent, goal_point)
      let visible_child_count = subtree.visible_child_count()
      if at_goal {
        if visible {
          self.stack.push(entry)
          return visible_child_index.to_int64()
        }
        if visible_child_count > 0 {
          self.stack.push(entry)
          did_descend = true
          break
        }
      } else if visible {
        visible_child_index += 1
      } else {
        visible_child_index += visible_child_count
      }
    }
  }
  self.stack.truncate(initial_size)
  -1
}

///|
/// `ts_tree_cursor_goto_first_child_for_byte`.
pub fn TreeCursor::goto_first_child_for_byte(
  self : TreeCursor,
  goal_byte : UInt32,
) -> Int64 {
  self.goto_first_child_for_byte_and_point(goal_byte, point_zero)
}

///|
/// `ts_tree_cursor_goto_first_child_for_point`.
pub fn TreeCursor::goto_first_child_for_point(
  self : TreeCursor,
  goal_point : Point,
) -> Int64 {
  self.goto_first_child_for_byte_and_point(0, goal_point)
}

///|
fn TreeCursor::goto_sibling_internal(
  self : TreeCursor,
  forward : Bool,
) -> TreeCursorStep {
  let initial_size = self.stack.length()
  // Upstream restores `stack.size = initial_size` on failure, which brings
  // back the popped entries that are still in the buffer.
  let popped : Array[TreeCursorEntry] = []
  while self.stack.length() > 1 {
    let entry = self.stack.pop().unwrap()
    popped.push(entry)
    let iterator = self.iterate_children()
    iterator.child_index = entry.child_index
    iterator.structural_child_index = entry.structural_child_index
    iterator.position = entry.position
    iterator.descendant_index = entry.descendant_index
    let advance = () => {
      if forward {
        iterator.next()
      } else {
        iterator.previous()
      }
    }
    let mut visible = false
    if advance() is Some((_, v)) {
      visible = v
    }
    if visible && self.stack.length() + 1 < initial_size {
      break
    }
    while advance() is Some((entry, visible)) {
      if visible {
        self.stack.push(entry)
        return StepVisible
      }
      if entry.subtree.get().visible_child_count() > 0 {
        self.stack.push(entry)
        return StepHidden
      }
    }
  }
  while popped.pop() is Some(entry) {
    self.stack.push(entry)
  }
  ignore(initial_size)
  StepNone
}

///|
pub fn TreeCursor::goto_next_sibling_internal(
  self : TreeCursor,
) -> TreeCursorStep {
  self.goto_sibling_internal(true)
}

///|
/// `ts_tree_cursor_goto_next_sibling`.
pub fn TreeCursor::goto_next_sibling(self : TreeCursor) -> Bool {
  match self.goto_next_sibling_internal() {
    StepHidden => {
      ignore(self.goto_first_child())
      true
    }
    StepVisible => true
    StepNone => false
  }
}

///|
pub fn TreeCursor::goto_previous_sibling_internal(
  self : TreeCursor,
) -> TreeCursorStep {
  // Since subtracting across row loses column information, we may have to
  // restore it.
  let step = self.goto_sibling_internal(false)
  if step == StepNone {
    return step
  }
  // If length is already valid, there's no need to recompute it.
  let last = self.stack[self.stack.length() - 1]
  if !length_is_undefined(last.position) {
    return step
  }
  // Restore position from the parent node.
  let parent = self.stack[self.stack.length() - 2]
  let mut position = parent.position
  let child_index = last.child_index
  let children = parent.subtree.get().children()
  if child_index > 0 {
    // Skip first child padding since its position should match the position
    // of the parent.
    position = length_add(position, children[0].size())
    for i in 1..<child_index {
      position = length_add(position, children[i].total_size())
    }
    position = length_add(position, children[child_index].padding())
  }
  self.stack[self.stack.length() - 1] = { ..last, position, }
  step
}

///|
/// `ts_tree_cursor_goto_previous_sibling`.
pub fn TreeCursor::goto_previous_sibling(self : TreeCursor) -> Bool {
  match self.goto_previous_sibling_internal() {
    StepHidden => {
      ignore(self.goto_last_child())
      true
    }
    StepVisible => true
    StepNone => false
  }
}

///|
/// `ts_tree_cursor_goto_parent`.
pub fn TreeCursor::goto_parent(self : TreeCursor) -> Bool {
  for i = self.stack.length() - 2; i >= 0; i = i - 1 {
    if self.is_entry_visible(i) {
      self.stack.truncate(i + 1)
      return true
    }
  }
  false
}

///|
/// `ts_tree_cursor_goto_descendant`.
pub fn TreeCursor::goto_descendant(
  self : TreeCursor,
  goal_descendant_index : UInt32,
) -> Unit {
  // Ascend to the lowest ancestor that contains the goal node.
  for ;; {
    let i = self.stack.length() - 1
    let entry = self.stack[i]
    let next_descendant_index = entry.descendant_index +
      (if self.is_entry_visible(i) { 1 } else { 0 }) +
      entry.subtree.get().visible_descendant_count()
    if entry.descendant_index <= goal_descendant_index &&
      next_descendant_index > goal_descendant_index {
      break
    } else if self.stack.length() <= 1 {
      return
    } else {
      ignore(self.stack.pop())
    }
  }
  // Descend to the goal node.
  let mut did_descend = true
  while did_descend {
    did_descend = false
    let iterator = self.iterate_children()
    if iterator.descendant_index > goal_descendant_index {
      return
    }
    while iterator.next() is Some((entry, visible)) {
      if iterator.descendant_index > goal_descendant_index {
        self.stack.push(entry)
        if visible && entry.descendant_index == goal_descendant_index {
          return
        } else {
          did_descend = true
          break
        }
      }
    }
  }
}

///|
/// `ts_tree_cursor_current_descendant_index`.
pub fn TreeCursor::current_descendant_index(self : TreeCursor) -> UInt32 {
  self.stack[self.stack.length() - 1].descendant_index
}

///|
/// `ts_tree_cursor_current_node`.
pub fn TreeCursor::current_node(self : TreeCursor) -> Node {
  let last_entry = self.stack[self.stack.length() - 1]
  let is_extra = last_entry.subtree.get().extra()
  let mut alias_symbol = if is_extra { 0 } else { self.root_alias_symbol }
  if self.stack.length() > 1 && !is_extra {
    let parent_entry = self.stack[self.stack.length() - 2]
    alias_symbol = self
      .language()
      .alias_at(
        parent_entry.subtree.get().ptr().production_id,
        last_entry.structural_child_index,
      )
  }
  Node::new(
    self.tree,
    Some(last_entry.subtree),
    last_entry.position,
    alias_symbol,
  )
}

///|
pub fn TreeCursor::current_subtree(self : TreeCursor) -> Subtree {
  self.stack[self.stack.length() - 1].subtree.get()
}

///|
pub fn TreeCursor::entries(self : TreeCursor) -> Array[TreeCursorEntry] {
  self.stack
}

///|
/// The result of `ts_tree_cursor_current_status`.
pub(all) struct CursorStatus {
  field_id : Int32
  has_later_siblings : Bool
  has_later_named_siblings : Bool
  can_have_later_siblings_with_this_field : Bool
  supertypes : Array[Int32]
}

///|
/// `ts_tree_cursor_current_status`: facts about the current node that are
/// needed when executing tree queries. `can_have_later_siblings_with_this_field`
/// is never false when a later sibling has the current node's field, but can
/// be true when none does.
pub fn TreeCursor::current_status(
  self : TreeCursor,
  max_supertypes : Int32,
) -> CursorStatus {
  let language = self.language()
  let mut field_id = 0
  let supertypes = []
  let mut has_later_siblings = false
  let mut has_later_named_siblings = false
  let mut can_have_later_siblings_with_this_field = false
  // A later sibling with no field of its own may inherit one further up.
  let mut later_sibling_without_field = false
  // Walk up the tree, visiting the current node and its invisible ancestors,
  // because fields can refer to nodes through invisible *wrapper* nodes.
  let mut i = self.stack.length() - 1
  while i > 0 {
    let entry = self.stack[i]
    let parent_entry = self.stack[i - 1]
    let parent_subtree = parent_entry.subtree.get()
    let entry_subtree = entry.subtree.get()
    let alias_sequence = language.alias_sequence(
      parent_subtree.ptr().production_id,
    )
    let subtree_symbol = (subtree : Subtree, structural_child_index : Int32) => {
      match alias_sequence {
        Some(offset) if !subtree.extra() &&
          language.alias_sequence_value(offset + structural_child_index) != 0 =>
          language.alias_sequence_value(offset + structural_child_index)
        _ => subtree.symbol()
      }
    }
    // Stop walking up when a visible ancestor is found.
    let entry_symbol = subtree_symbol(
      entry_subtree,
      entry.structural_child_index,
    )
    let entry_metadata = language.symbol_metadata_of(entry_symbol)
    if i != self.stack.length() - 1 && entry_metadata.visible {
      break
    }
    // Record any supertypes
    if entry_metadata.supertype && supertypes.length() < max_supertypes {
      supertypes.push(entry_symbol)
    }
    let (field_map, field_map_end) = language.field_map(
      parent_subtree.ptr().production_id,
    )
    let mut find_later_sibling_without_field = false
    if !entry_subtree.extra() {
      // Look for a field name associated with this entry.
      let mut entry_field_id = 0
      for m in field_map..<field_map_end {
        let map = language.field_map_entries[m]
        if !map.inherited && map.child_index == entry.structural_child_index {
          entry_field_id = map.field_id
          break
        }
      }
      if entry_field_id != 0 {
        if field_id == 0 {
          field_id = entry_field_id
          // A field found on this entry may also belong to any later sibling
          // found below. Those were scanned before the field was known, so
          // assume they do.
          if has_later_siblings {
            can_have_later_siblings_with_this_field = true
          }
        } else if later_sibling_without_field && entry_field_id == field_id {
          can_have_later_siblings_with_this_field = true
        }
        later_sibling_without_field = false
      }
      // Determine if the current node can have later siblings with the same
      // field name.
      if field_id != 0 {
        for m in field_map..<field_map_end {
          let map = language.field_map_entries[m]
          if map.field_id == field_id &&
            map.child_index > entry.structural_child_index {
            can_have_later_siblings_with_this_field = true
            break
          }
        }
      }
      // A fieldless later sibling may inherit a field from its hidden parent.
      find_later_sibling_without_field = field_id != 0 &&
        !can_have_later_siblings_with_this_field &&
        !later_sibling_without_field &&
        !self.is_entry_visible(i - 1)
    }
    // Determine if the current node has later siblings. A later *anonymous*
    // sibling settles `has_later_siblings` but says nothing about later
    // *named* siblings. When needed, also look for one with no field of its
    // own.
    if !has_later_named_siblings || find_later_sibling_without_field {
      let sibling_count = parent_subtree.child_count()
      let mut structural_child_index = entry.structural_child_index
      if !entry_subtree.extra() {
        structural_child_index += 1
      }
      for j in (entry.child_index + 1)..<sibling_count {
        let sibling = parent_subtree.children()[j]
        let sibling_metadata = language.symbol_metadata_of(
          subtree_symbol(sibling, structural_child_index),
        )
        let mut is_visible = sibling_metadata.visible
        let mut is_named = sibling_metadata.named
        if !is_visible && sibling.visible_child_count() > 0 {
          is_visible = true
          is_named = sibling.ptr().named_child_count > 0
        }
        if is_visible {
          has_later_siblings = true
          if is_named {
            has_later_named_siblings = true
          }
          if find_later_sibling_without_field {
            let mut has_field = false
            if !sibling.extra() {
              for m in field_map..<field_map_end {
                let map = language.field_map_entries[m]
                if !map.inherited && map.child_index == structural_child_index {
                  has_field = true
                  break
                }
              }
            }
            if !has_field {
              later_sibling_without_field = true
              find_later_sibling_without_field = false
            }
          }
        }
        if has_later_named_siblings && !find_later_sibling_without_field {
          break
        }
        if !sibling.extra() {
          structural_child_index += 1
        }
      }
    }
    i -= 1
  }
  {
    field_id,
    has_later_siblings,
    has_later_named_siblings,
    can_have_later_siblings_with_this_field,
    supertypes,
  }
}

///|
/// `ts_tree_cursor_current_depth`.
pub fn TreeCursor::current_depth(self : TreeCursor) -> UInt32 {
  let mut depth : UInt32 = 0
  for i in 1..<self.stack.length() {
    if self.is_entry_visible(i) {
      depth += 1
    }
  }
  depth
}

///|
/// `ts_tree_cursor_parent_node`.
pub fn TreeCursor::parent_node(self : TreeCursor) -> Node {
  for i = self.stack.length() - 2; i >= 0; i = i - 1 {
    let entry = self.stack[i]
    let mut is_visible = true
    let mut alias_symbol = 0
    if i > 0 {
      let parent_entry = self.stack[i - 1]
      alias_symbol = self
        .language()
        .alias_at(
          parent_entry.subtree.get().ptr().production_id,
          entry.structural_child_index,
        )
      is_visible = alias_symbol != 0 || entry.subtree.get().visible()
    }
    if is_visible {
      return Node::new(
        self.tree,
        Some(entry.subtree),
        entry.position,
        alias_symbol,
      )
    }
  }
  Node::new(None, None, length_zero(), 0)
}

///|
/// `ts_tree_cursor_current_field_id`.
pub fn TreeCursor::current_field_id(self : TreeCursor) -> Int32 {
  let language = self.language()
  // Walk up the tree, visiting the current node and its invisible ancestors.
  let mut i = self.stack.length() - 1
  while i > 0 {
    let entry = self.stack[i]
    let parent_entry = self.stack[i - 1]
    // Stop walking up when another visible node is found.
    if i != self.stack.length() - 1 && self.is_entry_visible(i) {
      break
    }
    if entry.subtree.get().extra() {
      break
    }
    let (field_map, field_map_end) = language.field_map(
      parent_entry.subtree.get().ptr().production_id,
    )
    for m in field_map..<field_map_end {
      let map = language.field_map_entries[m]
      if !map.inherited && map.child_index == entry.structural_child_index {
        return map.field_id
      }
    }
    i -= 1
  }
  0
}

///|
/// `ts_tree_cursor_current_field_name`.
pub fn TreeCursor::current_field_name(self : TreeCursor) -> String? {
  let id = self.current_field_id()
  if id != 0 {
    // `field_names[id]` is a C string.
    self.language().field_name_for_id(id)
  } else {
    None
  }
}

///|
/// `ts_tree_cursor_copy`.
pub fn TreeCursor::copy(self : TreeCursor) -> TreeCursor {
  {
    tree: self.tree,
    stack: self.stack.copy(),
    root_alias_symbol: self.root_alias_symbol,
  }
}

///|
/// `ts_tree_cursor_reset_to`.
pub fn TreeCursor::reset_to(self : TreeCursor, src : TreeCursor) -> Unit {
  self.tree = src.tree
  self.root_alias_symbol = src.root_alias_symbol
  self.stack = src.stack.copy()
}

///|
pub fn TreeCursor::tree(self : TreeCursor) -> Tree? {
  self.tree
}
