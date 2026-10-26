// Port of `ts_subtree_get_changed_ranges` and its iterator from tree-sitter
// lib/src/get_changed_ranges.c, plus `ts_tree_get_changed_ranges`.

///|
priv struct ChangeIterator {
  stack : Array[TreeCursorEntry]
  language : @language.Language
  mut visible_depth : Int32
  mut in_padding : Bool
  mut prev_external_token : Subtree
}

///|
fn ChangeIterator::new(
  tree : SubtreeSlot,
  language : @language.Language,
) -> ChangeIterator {
  {
    stack: [
      {
        subtree: tree,
        position: length_zero(),
        child_index: 0,
        structural_child_index: 0,
        descendant_index: 0,
      },
    ],
    language,
    visible_depth: 1,
    in_padding: false,
    prev_external_token: Subtree::null(),
  }
}

///|
fn ChangeIterator::done(self : ChangeIterator) -> Bool {
  self.stack.length() == 0
}

///|
fn ChangeIterator::back(self : ChangeIterator) -> TreeCursorEntry {
  self.stack[self.stack.length() - 1]
}

///|
fn ChangeIterator::start_position(self : ChangeIterator) -> Length {
  let entry = self.back()
  if self.in_padding {
    entry.position
  } else {
    length_add(entry.position, entry.subtree.get().padding())
  }
}

///|
fn ChangeIterator::end_position(self : ChangeIterator) -> Length {
  let entry = self.back()
  let result = length_add(entry.position, entry.subtree.get().padding())
  if self.in_padding {
    result
  } else {
    length_add(result, entry.subtree.get().size())
  }
}

///|
fn ChangeIterator::tree_is_visible(self : ChangeIterator) -> Bool {
  let entry = self.back()
  if entry.subtree.get().visible() {
    return true
  }
  if self.stack.length() > 1 {
    let parent = self.stack[self.stack.length() - 2].subtree.get()
    return self.language.alias_at(
        parent.ptr().production_id,
        entry.structural_child_index,
      ) !=
      0
  }
  false
}

///|
/// `iterator_get_visible_state`: `(tree, alias_symbol, start_byte)`.
fn ChangeIterator::get_visible_state(
  self : ChangeIterator,
) -> (Subtree, Int32, UInt32) {
  let mut tree = Subtree::null()
  let mut alias_symbol = 0
  let mut start_byte : UInt32 = 0
  let mut i = self.stack.length() - 1
  if self.in_padding {
    if i == 0 {
      return (tree, alias_symbol, start_byte)
    }
    i -= 1
  }
  while i >= 0 {
    let entry = self.stack[i]
    if i > 0 {
      let parent = self.stack[i - 1].subtree.get()
      alias_symbol = self.language.alias_at(
        parent.ptr().production_id,
        entry.structural_child_index,
      )
    }
    if entry.subtree.get().visible() || alias_symbol != 0 {
      tree = entry.subtree.get()
      start_byte = entry.position.bytes
      break
    }
    i -= 1
  }
  (tree, alias_symbol, start_byte)
}

///|
fn ChangeIterator::ascend(self : ChangeIterator) -> Unit {
  if self.done() {
    return
  }
  if self.tree_is_visible() && !self.in_padding {
    self.visible_depth -= 1
  }
  if self.back().child_index > 0 {
    self.in_padding = false
  }
  ignore(self.stack.pop())
}

///|
fn ChangeIterator::descend(
  self : ChangeIterator,
  goal_position : UInt32,
) -> Bool {
  if self.in_padding {
    return false
  }
  let mut did_descend = true
  while did_descend {
    did_descend = false
    let entry = self.back()
    let parent = entry.subtree.get()
    let mut position = entry.position
    let mut structural_child_index = 0
    for i in 0..<parent.child_count() {
      let slot = parent.child_slot(i)
      let child = slot.get()
      let child_left = length_add(position, child.padding())
      let child_right = length_add(child_left, child.size())
      if child_right.bytes > goal_position {
        self.stack.push({
          subtree: slot,
          position,
          child_index: i,
          structural_child_index,
          descendant_index: 0,
        })
        if self.tree_is_visible() {
          if child_left.bytes > goal_position {
            self.in_padding = true
          } else {
            self.visible_depth += 1
          }
          return true
        }
        did_descend = true
        break
      }
      position = child_right
      if !child.extra() {
        structural_child_index += 1
      }
      let last_external_token = child.last_external_token()
      if !last_external_token.is_null() {
        self.prev_external_token = last_external_token
      }
    }
  }
  false
}

///|
fn ChangeIterator::advance(self : ChangeIterator) -> Unit {
  if self.in_padding {
    self.in_padding = false
    if self.tree_is_visible() {
      self.visible_depth += 1
    } else {
      ignore(self.descend(0))
    }
    return
  }
  for ;; {
    if self.tree_is_visible() {
      self.visible_depth -= 1
    }
    let entry = self.stack.pop().unwrap()
    if self.done() {
      return
    }
    let parent = self.back().subtree.get()
    let child_index = entry.child_index + 1
    let entry_subtree = entry.subtree.get()
    let last_external_token = entry_subtree.last_external_token()
    if !last_external_token.is_null() {
      self.prev_external_token = last_external_token
    }
    if parent.child_count() > child_index {
      let position = length_add(entry.position, entry_subtree.total_size())
      let mut structural_child_index = entry.structural_child_index
      if !entry_subtree.extra() {
        structural_child_index += 1
      }
      let next_slot = parent.child_slot(child_index)
      self.stack.push({
        subtree: next_slot,
        position,
        child_index,
        structural_child_index,
        descendant_index: 0,
      })
      if self.tree_is_visible() {
        if next_slot.get().padding().bytes > 0 {
          self.in_padding = true
        } else {
          self.visible_depth += 1
        }
      } else {
        ignore(self.descend(0))
      }
      break
    }
  }
}

///|
priv enum IteratorComparison {
  Differs
  MayDiffer
  Matches
} derive(Eq)

///|
fn iterator_compare(
  old_iter : ChangeIterator,
  new_iter : ChangeIterator,
) -> IteratorComparison {
  let (old_tree, old_alias_symbol, old_start) = old_iter.get_visible_state()
  let (new_tree, new_alias_symbol, new_start) = new_iter.get_visible_state()
  if old_tree.is_null() && new_tree.is_null() {
    return Matches
  }
  if old_tree.is_null() || new_tree.is_null() {
    return Differs
  }
  let old_symbol = old_tree.symbol()
  let new_symbol = new_tree.symbol()
  if old_alias_symbol != new_alias_symbol || old_symbol != new_symbol {
    return Differs
  }
  let old_size = old_tree.size().bytes
  let new_size = new_tree.size().bytes
  let old_state = old_tree.parse_state()
  let new_state = new_tree.parse_state()
  let old_has_external_tokens = old_tree.has_external_tokens()
  let new_has_external_tokens = new_tree.has_external_tokens()
  let old_error_cost = old_tree.error_cost()
  let new_error_cost = new_tree.error_cost()
  if old_start != new_start ||
    old_symbol == @language.ts_builtin_sym_error ||
    old_size != new_size ||
    old_state == ts_tree_state_none ||
    new_state == ts_tree_state_none ||
    (old_state == error_state) != (new_state == error_state) ||
    old_error_cost != new_error_cost ||
    old_has_external_tokens != new_has_external_tokens ||
    old_tree.has_changes() ||
    (
      old_has_external_tokens &&
      !old_iter.prev_external_token.external_scanner_state_eq(
        new_iter.prev_external_token,
      )
    ) {
    return MayDiffer
  }
  Matches
}

///|
/// `ts_subtree_get_changed_ranges`.
pub fn subtree_get_changed_ranges(
  old_tree : SubtreeSlot,
  new_tree : SubtreeSlot,
  language : @language.Language,
  included_range_differences : Array[Range],
) -> Array[Range] {
  let results : Array[Range] = []
  let old_iter = ChangeIterator::new(old_tree, language)
  let new_iter = ChangeIterator::new(new_tree, language)
  let mut included_range_difference_index = 0
  let mut position = old_iter.start_position()
  let mut next_position = new_iter.start_position()
  if position.bytes < next_position.bytes {
    range_array_add(results, position, next_position)
    position = next_position
  } else if position.bytes > next_position.bytes {
    range_array_add(results, next_position, position)
    next_position = position
  }
  for ;; {
    // Compare the old and new subtrees.
    let mut comparison = iterator_compare(old_iter, new_iter)
    // Even if the two subtrees appear to be identical, they could differ
    // internally if they contain a range of text that was previously
    // excluded from the parse, and is now included, or vice-versa.
    if comparison == Matches &&
      range_array_intersects(
        included_range_differences,
        included_range_difference_index,
        position.bytes,
        old_iter.end_position().bytes,
      ) {
      comparison = MayDiffer
    }
    let mut is_changed = false
    match comparison {
      // If the subtrees are definitely identical, move to the end of both
      // subtrees.
      Matches => next_position = old_iter.end_position()
      // If the subtrees might differ internally, descend into both subtrees,
      // finding the first child that spans the current position.
      MayDiffer =>
        if old_iter.descend(position.bytes) {
          if !new_iter.descend(position.bytes) {
            is_changed = true
            next_position = old_iter.end_position()
          }
        } else if new_iter.descend(position.bytes) {
          is_changed = true
          next_position = new_iter.end_position()
        } else {
          next_position = length_min(
            old_iter.end_position(),
            new_iter.end_position(),
          )
        }
      // If the subtrees are different, record a change and then move to the
      // end of both subtrees.
      Differs => {
        is_changed = true
        next_position = length_min(
          old_iter.end_position(),
          new_iter.end_position(),
        )
      }
    }
    // Ensure that both iterators are caught up to the current position.
    while !old_iter.done() &&
          old_iter.end_position().bytes <= next_position.bytes {
      old_iter.advance()
    }
    while !new_iter.done() &&
          new_iter.end_position().bytes <= next_position.bytes {
      new_iter.advance()
    }
    // Ensure that both iterators are at the same depth in the tree.
    while old_iter.visible_depth > new_iter.visible_depth {
      old_iter.ascend()
    }
    while new_iter.visible_depth > old_iter.visible_depth {
      new_iter.ascend()
    }
    if is_changed {
      range_array_add(results, position, next_position)
    }
    position = next_position
    // Keep track of the current position in the included range differences
    // array in order to avoid scanning the entire array on each iteration.
    while included_range_difference_index < included_range_differences.length() {
      let range = included_range_differences[included_range_difference_index]
      if range.end_byte <= position.bytes {
        included_range_difference_index += 1
      } else {
        break
      }
    }
    if old_iter.done() || new_iter.done() {
      break
    }
  }
  let old_size = old_tree.get().total_size()
  let new_size = new_tree.get().total_size()
  if old_size.bytes < new_size.bytes {
    range_array_add(results, old_size, new_size)
  } else if new_size.bytes < old_size.bytes {
    range_array_add(results, new_size, old_size)
  }
  results
}

///|
/// `ts_tree_get_changed_ranges`.
pub fn Tree::changed_ranges(old_tree : Tree, new_tree : Tree) -> Array[Range] {
  let included_range_differences = []
  range_array_get_changed_ranges(
    old_tree.included_ranges,
    new_tree.included_ranges,
    included_range_differences,
  )
  subtree_get_changed_ranges(
    old_tree.root_ref(),
    new_tree.root_ref(),
    old_tree.language,
    included_range_differences,
  )
}
