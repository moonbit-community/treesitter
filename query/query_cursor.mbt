// Port of the `TSQueryCursor` in tree-sitter lib/src/query.c.

///|
/// `TSQueryCursorState`: what a progress callback can observe.
pub(all) struct QueryCursorState {
  current_byte_offset : UInt
} derive(Eq, Debug)

///|
/// `TSQueryCursorOptions`.
pub(all) struct QueryCursorOptions {
  progress_callback : ((QueryCursorState) -> Bool)?
}

///|
/// `TSQueryMatch`. `captures` is a view of the match's capture list (upstream
/// returns a pointer to it) that keeps its elements when the cursor moves on.
pub struct QueryMatch {
  id : UInt
  pattern_index : Int
  captures : ArrayView[QueryCapture]
  // The capture list's id and serial, for `CaptureConversionCache`.
  priv capture_list_id : UInt
  priv capture_list_serial : Int
}

///|
let max_range : @runtime.Range = {
  start_point: { row: 0, column: 0 },
  end_point: @runtime.point_max,
  start_byte: 0,
  end_byte: 0xFFFFFFFFU,
}

///|
/// TSQueryCursor - A stateful struct used to execute a query on a tree.
pub struct QueryCursor {
  priv mut query : Query?
  priv mut cursor : @runtime.TreeCursor?
  priv states : Array[QueryState]
  priv finished_states : Array[QueryState]
  // Tracks how much of finished_states is in heap order. Elements at indices
  // < this value satisfy the min-heap property; elements >= this value are
  // newly pushed and need to be sifted into place. Only used by
  // `next_capture`.
  priv mut finished_states_heap_size : Int
  priv capture_list_pool : CaptureListPool
  priv mut depth : UInt
  priv mut max_start_depth : UInt
  priv mut included_range : @runtime.Range
  priv mut containing_range : @runtime.Range
  priv mut next_state_id : UInt
  priv mut next_finished_state_id : UInt
  priv mut query_options : QueryCursorOptions?
  priv mut query_state : QueryCursorState
  priv mut work_count : Int
  priv mut on_visible_node : Bool
  priv mut ascending : Bool
  priv mut halted : Bool
  priv mut did_exceed_match_limit : Bool
}

///|
/// `ts_query_cursor_new`.
pub fn QueryCursor::new() -> QueryCursor {
  {
    query: None,
    cursor: None,
    did_exceed_match_limit: false,
    ascending: false,
    halted: false,
    states: [],
    finished_states: [],
    finished_states_heap_size: 0,
    capture_list_pool: CaptureListPool::new(),
    depth: 0,
    included_range: max_range,
    containing_range: max_range,
    max_start_depth: 0xFFFFFFFFU,
    next_state_id: 0,
    next_finished_state_id: 0,
    query_options: None,
    query_state: { current_byte_offset: 0 },
    work_count: 0,
    on_visible_node: false,
  }
}

///|
fn QueryCursor::q(self : QueryCursor) -> Query {
  self.query.unwrap()
}

///|
fn QueryCursor::tree_cursor(self : QueryCursor) -> @runtime.TreeCursor {
  self.cursor.unwrap()
}

///|
/// `ts_query_cursor_did_exceed_match_limit`.
pub fn QueryCursor::did_exceed_match_limit(self : QueryCursor) -> Bool {
  self.did_exceed_match_limit
}

///|
/// `ts_query_cursor_match_limit`.
pub fn QueryCursor::match_limit(self : QueryCursor) -> UInt {
  self.capture_list_pool.max_capture_list_count
}

///|
/// `ts_query_cursor_set_match_limit`.
pub fn QueryCursor::set_match_limit(self : QueryCursor, limit : UInt) -> Unit {
  self.capture_list_pool.max_capture_list_count = limit
}

///|
/// `ts_query_cursor_exec`.
pub fn QueryCursor::exec(
  self : QueryCursor,
  query : Query,
  node : @runtime.Node,
) -> Unit {
  self.states.clear()
  self.finished_states.clear()
  self.finished_states_heap_size = 0
  match self.cursor {
    Some(cursor) => cursor.reset(node)
    None => self.cursor = Some(@runtime.TreeCursor::new(node))
  }
  self.capture_list_pool.reset()
  self.on_visible_node = true
  self.next_state_id = 0
  self.next_finished_state_id = 0
  self.depth = 0
  self.ascending = false
  self.halted = false
  self.query = Some(query)
  self.did_exceed_match_limit = false
  self.work_count = 0
  self.query_options = None
  self.query_state = { current_byte_offset: 0 }
}

///|
/// `ts_query_cursor_exec_with_options`.
pub fn QueryCursor::exec_with_options(
  self : QueryCursor,
  query : Query,
  node : @runtime.Node,
  query_options : QueryCursorOptions?,
) -> Unit {
  self.exec(query, node)
  if query_options is Some(_) {
    self.query_options = query_options
    self.query_state = { current_byte_offset: 0 }
  }
}

///|
/// `ts_query_cursor_set_byte_range`.
pub fn QueryCursor::set_byte_range(
  self : QueryCursor,
  start_byte : UInt,
  end_byte : UInt,
) -> Bool {
  let end_byte = if end_byte == 0 { 0xFFFFFFFFU } else { end_byte }
  if start_byte > end_byte {
    return false
  }
  self.included_range = { ..self.included_range, start_byte, end_byte }
  true
}

///|
/// `ts_query_cursor_set_point_range`.
pub fn QueryCursor::set_point_range(
  self : QueryCursor,
  start_point : @runtime.Point,
  end_point : @runtime.Point,
) -> Bool {
  let end_point = if end_point.row == 0 && end_point.column == 0 {
    @runtime.point_max
  } else {
    end_point
  }
  if @runtime.point_gt(start_point, end_point) {
    return false
  }
  self.included_range = { ..self.included_range, start_point, end_point }
  true
}

///|
/// `ts_query_cursor_set_containing_byte_range`.
pub fn QueryCursor::set_containing_byte_range(
  self : QueryCursor,
  start_byte : UInt,
  end_byte : UInt,
) -> Bool {
  let end_byte = if end_byte == 0 { 0xFFFFFFFFU } else { end_byte }
  if start_byte > end_byte {
    return false
  }
  self.containing_range = { ..self.containing_range, start_byte, end_byte }
  true
}

///|
/// `ts_query_cursor_set_containing_point_range`.
pub fn QueryCursor::set_containing_point_range(
  self : QueryCursor,
  start_point : @runtime.Point,
  end_point : @runtime.Point,
) -> Bool {
  let end_point = if end_point.row == 0 && end_point.column == 0 {
    @runtime.point_max
  } else {
    end_point
  }
  if @runtime.point_gt(start_point, end_point) {
    return false
  }
  self.containing_range = { ..self.containing_range, start_point, end_point }
  true
}

///|
/// `ts_query_cursor_set_max_start_depth`.
pub fn QueryCursor::set_max_start_depth(
  self : QueryCursor,
  max_start_depth : UInt,
) -> Unit {
  self.max_start_depth = max_start_depth
}

///|
fn QueryCursor::push_finished_state(self : QueryCursor, state : QueryState) -> Unit {
  state.heap_insert_order = self.next_finished_state_id
  self.next_finished_state_id += 1
  self.finished_states.push(state)
}

///|
fn QueryCursor::heapify_finished_states(self : QueryCursor) -> Unit {
  while self.finished_states_heap_size < self.finished_states.length() {
    finished_state_sift_up(
      self.finished_states,
      self.finished_states_heap_size,
      self.capture_list_pool,
    )
    self.finished_states_heap_size += 1
  }
}

///|
/// The result of `ts_query_cursor__first_in_progress_capture`.
priv struct InProgressCapture {
  state_index : Int
  byte_offset : UInt
  pattern_index : Int
  is_definite : Bool
}

///|
/// Search through all of the in-progress states, and find the captured node
/// that occurs earliest in the document. With `want_definite`, also report
/// whether the capture is definite; otherwise skip states whose next step is
/// guaranteed.
fn QueryCursor::first_in_progress_capture(
  self : QueryCursor,
  want_definite : Bool,
) -> (Bool, InProgressCapture) {
  let mut result = false
  let mut state_index = -1
  let mut byte_offset = 0xFFFFFFFFU
  let mut pattern_index = 0xFFFFFFFF
  let mut is_definite = false
  let mut i = 0
  while i < self.states.length() {
    let state = self.states[i]
    if state.dead {
      i += 1
      continue
    }
    let captures = self.capture_list_pool.get(state.capture_list_id)
    if state.consumed_capture_count >= captures.length() {
      i += 1
      continue
    }
    let node = captures[state.consumed_capture_count].node
    if node.end_byte() <= self.included_range.start_byte ||
      @runtime.point_lte(node.end_point(), self.included_range.start_point) {
      state.set_consumed_capture_count(state.consumed_capture_count + 1)
      continue
    }
    let node_start_byte = node.start_byte()
    if !result ||
      node_start_byte < byte_offset ||
      (node_start_byte == byte_offset && state.pattern_index < pattern_index) {
      let step = self.q().steps[state.step_index]
      if want_definite {
        // We're being a bit conservative here by asserting that the following
        // step is not immediate, because this capture might end up being
        // discarded if the following symbol in the tree isn't the required
        // symbol for this step.
        is_definite = step.root_pattern_guaranteed && !step.is_immediate
      } else if step.root_pattern_guaranteed {
        i += 1
        continue
      }
      result = true
      state_index = i
      byte_offset = node_start_byte
      pattern_index = state.pattern_index
    }
    i += 1
  }
  (result, { state_index, byte_offset, pattern_index, is_definite })
}

///|
/// Determine which node is first in a depth-first traversal.
fn compare_nodes(left : @runtime.Node, right : @runtime.Node) -> Int {
  if !left.same_id(right) {
    let left_start = left.start_byte()
    let right_start = right.start_byte()
    if left_start < right_start {
      return -1
    }
    if left_start > right_start {
      return 1
    }
    let left_node_count = left.end_byte()
    let right_node_count = right.end_byte()
    if left_node_count > right_node_count {
      return -1
    }
    if left_node_count < right_node_count {
      return 1
    }
  }
  0
}

///|
/// Determine if either state contains a superset of the other state's
/// captures: `(left_contains_right, right_contains_left)`.
fn QueryCursor::compare_captures(
  self : QueryCursor,
  left_state : QueryState,
  right_state : QueryState,
) -> (Bool, Bool) {
  let left_captures = self.capture_list_pool.get(left_state.capture_list_id)
  let right_captures = self.capture_list_pool.get(right_state.capture_list_id)
  let mut left_contains_right = true
  let mut right_contains_left = true
  let mut i = 0
  let mut j = 0
  for ;; {
    if i < left_captures.length() {
      if j < right_captures.length() {
        let left = left_captures[i]
        let right = right_captures[j]
        if left.node.same_id(right.node) && left.index == right.index {
          i += 1
          j += 1
        } else {
          match compare_nodes(left.node, right.node) {
            -1 => {
              right_contains_left = false
              i += 1
            }
            1 => {
              left_contains_right = false
              j += 1
            }
            _ => {
              right_contains_left = false
              left_contains_right = false
              i += 1
              j += 1
            }
          }
        }
      } else {
        right_contains_left = false
        break
      }
    } else {
      if j < right_captures.length() {
        left_contains_right = false
      }
      break
    }
  }
  (left_contains_right, right_contains_left)
}

///|
/// Order two in-progress states for the longest-match dedup pass. Within a
/// (start_depth, pattern_index) group, states with no captures sort first, as
/// they are a subset of every other state. The rest sort by the start byte of
/// their first capture.
fn QueryCursor::state_precedes(
  self : QueryCursor,
  a : QueryState,
  b : QueryState,
) -> Bool {
  if a.start_depth != b.start_depth {
    return a.start_depth < b.start_depth
  }
  if a.pattern_index != b.pattern_index {
    return a.pattern_index < b.pattern_index
  }
  let a_caps = self.capture_list_pool.get(a.capture_list_id)
  let b_caps = self.capture_list_pool.get(b.capture_list_id)
  if (a_caps.length() == 0) != (b_caps.length() == 0) {
    return a_caps.length() == 0
  }
  if a_caps.length() == 0 {
    return false
  }
  a_caps[0].node.start_byte() < b_caps[0].node.start_byte()
}

///|
/// Stable-sort the in-progress states with the order dictated by
/// `state_precedes` (insertion sort, as upstream).
fn QueryCursor::sort_states_by_capture(self : QueryCursor) -> Unit {
  let states = self.states
  for i in 1..<states.length() {
    // Fast+common path: this state is already ordered after its predecessor,
    // so it does not need to move.
    if !self.state_precedes(states[i], states[i - 1]) {
      continue
    }
    let key = states[i]
    let mut j = i
    for ;; {
      states[j] = states[j - 1]
      j -= 1
      if !(j > 0 && self.state_precedes(key, states[j - 1])) {
        break
      }
    }
    states[j] = key
  }
}

///|
fn QueryCursor::add_state(self : QueryCursor, pattern : PatternEntry) -> Unit {
  let step = self.q().steps[pattern.step_index]
  let start_depth = (self.depth - step.depth.reinterpret_as_uint()).reinterpret_as_int() &
    0xFFFF
  // Keep the states array in ascending order of start_depth and
  // pattern_index, so that it can be processed more efficiently elsewhere.
  let mut index = self.states.length()
  while index > 0 {
    let prev_state = self.states[index - 1]
    if prev_state.start_depth < start_depth {
      break
    }
    if prev_state.start_depth == start_depth {
      // Avoid inserting an unnecessary duplicate state, which would be
      // immediately pruned by the longest-match criteria.
      if prev_state.pattern_index == pattern.pattern_index &&
        prev_state.step_index == pattern.step_index {
        return
      }
      if prev_state.pattern_index <= pattern.pattern_index {
        break
      }
    }
    index -= 1
  }
  self.states.insert(index, {
    id: 0xFFFFFFFFU,
    capture_list_id: capture_list_none,
    heap_insert_order: 0xFFFFFFFFU,
    step_index: pattern.step_index,
    pattern_index: pattern.pattern_index,
    start_depth,
    consumed_capture_count: 0,
    seeking_immediate_match: true,
    has_in_progress_alternatives: false,
    needs_parent: step.depth == 1,
    dead: false,
    skipped_quantifier: false,
  })
}

///|
/// Acquire a capture list for this state. If there are no capture lists left
/// in the pool, this will steal the capture list from another existing state,
/// and mark that other state as 'dead'.
fn QueryCursor::prepare_to_capture(
  self : QueryCursor,
  state : QueryState,
  state_index_to_preserve : Int,
) -> CaptureList? {
  if state.capture_list_id == capture_list_none {
    state.capture_list_id = self.capture_list_pool.acquire()
    // If there are no capture lists left in the pool, then terminate
    // whichever state has captured the earliest node in the document, and
    // steal its capture list.
    if state.capture_list_id == capture_list_none {
      self.did_exceed_match_limit = true
      let (found, first) = self.first_in_progress_capture(false)
      if found && first.state_index != state_index_to_preserve {
        let other_state = self.states[first.state_index]
        state.capture_list_id = other_state.capture_list_id
        other_state.capture_list_id = capture_list_none
        other_state.dead = true
        let list = self.capture_list_pool.get_list(state.capture_list_id)
        list.clear()
        return Some(list)
      } else {
        return None
      }
    }
  }
  Some(self.capture_list_pool.get_list(state.capture_list_id))
}

///|
fn QueryCursor::capture(
  self : QueryCursor,
  state : QueryState,
  step : QueryStep,
  node : @runtime.Node,
) -> Unit {
  if state.dead {
    return
  }
  guard self.prepare_to_capture(state, -1) is Some(capture_list) else {
    state.dead = true
    return
  }
  for j in 0..<max_step_capture_count {
    let capture_id = step.capture_ids[j]
    if capture_id == none {
      break
    }
    capture_list.push({ node, index: capture_id })
  }
}

///|
/// Duplicate the given state (at `state_index`) and insert the newly-created
/// state immediately after it in the `states` array.
fn QueryCursor::copy_state(self : QueryCursor, state_index : Int) -> QueryState? {
  let state = self.states[state_index]
  let copy = state.copy()
  copy.capture_list_id = capture_list_none
  // If the state has captures, copy its capture list.
  if state.capture_list_id != capture_list_none {
    guard self.prepare_to_capture(copy, state_index) is Some(new_captures) else {
      return None
    }
    let old_captures = self.capture_list_pool.get(state.capture_list_id)
    for capture in old_captures {
      new_captures.push(capture)
    }
  }
  self.states.insert(state_index + 1, copy)
  Some(copy)
}

///|
fn QueryCursor::should_descend(
  self : QueryCursor,
  node_intersects_range : Bool,
) -> Bool {
  if node_intersects_range && self.depth < self.max_start_depth {
    return true
  }
  // If there are in-progress matches whose remaining steps occur deeper in
  // the tree, then descend.
  for state in self.states {
    let next_step = self.q().steps[state.step_index]
    if next_step.depth != pattern_done_marker &&
      (state.start_depth + next_step.depth).reinterpret_as_uint() > self.depth {
      return true
    }
  }
  if self.depth >= self.max_start_depth {
    return false
  }
  // If the current node is hidden, then a non-rooted pattern might match one
  // if its roots inside of this node, and match another of its roots as part
  // of a sibling node, so we may need to descend.
  if !self.on_visible_node {
    // Descending into a repetition node outside of the range can be
    // expensive, because these nodes can have many visible children. Avoid
    // descending into repetition nodes unless we have already determined that
    // this query can match rootless patterns inside of this type of
    // repetition node.
    let subtree = self.tree_cursor().current_subtree()
    if subtree.is_repetition() {
      let (_, exists) = search_sorted_by(
        self.q().repeat_symbols_with_rootless_patterns,
        x => x,
        subtree.symbol(),
      )
      return exists
    }
    return true
  }
  false
}

///|
fn range_intersects(a : @runtime.Range, b : @runtime.Range) -> Bool {
  let is_empty = a.start_byte == a.end_byte
  (a.end_byte > b.start_byte || (is_empty && a.end_byte == b.start_byte)) &&
  (@runtime.point_gt(a.end_point, b.start_point) ||
  (is_empty && @runtime.point_eq(a.end_point, b.start_point))) &&
  a.start_byte < b.end_byte &&
  @runtime.point_lt(a.start_point, b.end_point)
}

///|
fn range_within(a : @runtime.Range, b : @runtime.Range) -> Bool {
  a.start_byte >= b.start_byte &&
  @runtime.point_gte(a.start_point, b.start_point) &&
  a.end_byte <= b.end_byte &&
  @runtime.point_lte(a.end_point, b.end_point)
}

///|
fn node_range(node : @runtime.Node) -> @runtime.Range {
  {
    start_point: node.start_point(),
    end_point: node.end_point(),
    start_byte: node.start_byte(),
    end_byte: node.end_byte(),
  }
}

///|
/// Walk the tree, processing patterns until at least one pattern finishes.
/// If one or more patterns finish, return `true` and store their states in the
/// `finished_states` array. Multiple patterns can finish on the same node. If
/// there are no more matches, return `false`.
fn QueryCursor::advance(self : QueryCursor, stop_on_definite_step : Bool) -> Bool {
  let query = self.q()
  let mut did_match = false
  for ;; {
    if self.halted {
      while self.states.pop() is Some(state) {
        self.capture_list_pool.release(state.capture_list_id)
      }
      // The traversal is over until the next `exec`. Upstream's tree cursor
      // does not own the tree, but a MoonBit `TreeCursor` keeps the tree (and
      // its stack of subtrees) alive, so a cursor kept for reuse (as
      // `Highlighter` and `TagsContext` do) must not hold on to it once the
      // pending matches are consumed.
      self.cursor = None
    }
    if did_match || self.halted {
      return did_match
    }
    // Consult the progress callback after a bounded amount of work. Only
    // iterations that do work are charged.
    self.work_count += 1 + self.states.length()
    if self.work_count >= work_per_query_callback_check {
      self.work_count = 0
      if self.query_options is Some(options) &&
        options.progress_callback is Some(callback) {
        self.query_state = {
          current_byte_offset: self.tree_cursor().current_node().start_byte(),
        }
        if callback(self.query_state) {
          // Halt the same way reaching the end of the tree does. The next
          // iteration discards the in-progress states, so only finished
          // matches are returned.
          self.halted = true
          continue
        }
      }
    }
    if self.ascending {
      // Exit the current node.
      if self.on_visible_node {
        // After leaving a node, remove any states that cannot make further
        // progress.
        let mut deleted_count = 0
        let n = self.states.length()
        for i in 0..<n {
          let state = self.states[i]
          let step = query.steps[state.step_index]
          if step.depth == pattern_done_marker &&
            (state.start_depth.reinterpret_as_uint() > self.depth ||
            self.depth == 0) {
            // If a state completed its pattern inside of this node, but was
            // deferred from finishing in order to search for longer matches,
            // mark it as finished.
            self.push_finished_state(state)
            did_match = true
            deleted_count += 1
          } else if step.depth != pattern_done_marker &&
            (state.start_depth + step.depth).reinterpret_as_uint() > self.depth {
            // If a state needed to match something within this node, then
            // remove that state as it has failed to match.
            self.capture_list_pool.release(state.capture_list_id)
            deleted_count += 1
          } else if deleted_count > 0 {
            self.states[i - deleted_count] = state
          }
        }
        self.states.truncate(n - deleted_count)
      }
      // Leave this node by stepping to its next sibling or to its parent.
      match self.tree_cursor().goto_next_sibling_internal() {
        StepVisible => {
          if !self.on_visible_node {
            self.depth += 1
            self.on_visible_node = true
          }
          self.ascending = false
        }
        StepHidden => {
          if self.on_visible_node {
            self.depth -= 1
            self.on_visible_node = false
          }
          self.ascending = false
        }
        StepNone =>
          if self.tree_cursor().goto_parent() {
            self.depth -= 1
          } else {
            self.halted = true
          }
      }
    } else {
      // Enter a new node.
      let cursor = self.tree_cursor()
      let node = cursor.current_node()
      let parent_node = cursor.parent_node()
      let parent_intersects_range = parent_node.is_null() ||
        range_intersects(node_range(parent_node), self.included_range)
      let node_range = node_range(node)
      let node_intersects_range = parent_intersects_range &&
        range_intersects(node_range, self.included_range)
      let node_intersects_containing_range = range_intersects(
        node_range,
        self.containing_range,
      )
      let node_within_containing_range = range_within(
        node_range,
        self.containing_range,
      )
      if node_within_containing_range && self.on_visible_node {
        let symbol = node.symbol()
        let is_named = node.is_named()
        let is_missing = node.is_missing()
        let status = cursor.current_status(8)
        let field_id = status.field_id
        let has_later_siblings = status.has_later_siblings
        let has_later_named_siblings = status.has_later_named_siblings
        let can_have_later_siblings_with_this_field = status.can_have_later_siblings_with_this_field
        let supertypes = status.supertypes
        let supertype_count = supertypes.length()
        let node_is_error = symbol == @language.ts_builtin_sym_error
        let parent_is_error = !parent_node.is_null() &&
          parent_node.symbol() == @language.ts_builtin_sym_error
        // Add new states for any patterns whose root node is a wildcard.
        if !node_is_error {
          for i in 0..<query.wildcard_root_pattern_count {
            let pattern = query.pattern_map[i]
            // If this node matches the first step of the pattern, then add a
            // new state at the start of this pattern.
            let step = query.steps[pattern.step_index]
            let start_depth = self.depth - step.depth.reinterpret_as_uint()
            if (if pattern.is_rooted {
                node_intersects_range
              } else {
                parent_intersects_range && !parent_is_error
              }) &&
              (step.field == 0 || field_id == step.field) &&
              (step.supertype_symbol == 0 || supertype_count > 0) &&
              start_depth <= self.max_start_depth {
              self.add_state(pattern)
            }
          }
        }
        // Add new states for any patterns whose root node matches this node.
        let (found, first_index) = query.pattern_map_search(symbol)
        if found {
          let mut i = first_index
          let mut pattern = query.pattern_map[i]
          let mut step = query.steps[pattern.step_index]
          let start_depth = self.depth - step.depth.reinterpret_as_uint()
          for ;; {
            // If this node matches the first step of the pattern, then add a
            // new state at the start of this pattern.
            if (if pattern.is_rooted {
                node_intersects_range
              } else {
                parent_intersects_range && !parent_is_error
              }) &&
              (step.field == 0 || field_id == step.field) &&
              start_depth <= self.max_start_depth {
              self.add_state(pattern)
            }
            // Advance to the next pattern whose root node matches this node.
            i += 1
            if i == query.pattern_map.length() {
              break
            }
            pattern = query.pattern_map[i]
            step = query.steps[pattern.step_index]
            if step.symbol != symbol {
              break
            }
          }
        }
        // Update all of the in-progress states with current node.
        let mut j = 0
        let mut copy_count = 0
        while j < self.states.length() {
          let state = self.states[j]
          let step = query.steps[state.step_index]
          state.has_in_progress_alternatives = false
          copy_count = 0
          // Check that the node matches all of the criteria for the next step
          // of the pattern.
          if (state.start_depth + step.depth).reinterpret_as_uint() != self.depth {
            j += 1 + copy_count
            continue
          }
          // Determine if this node matches this step of the pattern, and also
          // if this node can have later siblings that match this step of the
          // pattern.
          let mut node_does_match = false
          if step.symbol == wildcard_symbol {
            if step.is_missing {
              node_does_match = is_missing
            } else {
              node_does_match = !node_is_error && (is_named || !step.is_named)
            }
          } else {
            node_does_match = symbol == step.symbol &&
              (!step.is_missing || is_missing)
          }
          let mut later_sibling_can_match = has_later_siblings
          if (step.is_immediate && is_named && !state.skipped_quantifier) ||
            state.seeking_immediate_match {
            later_sibling_can_match = false
          }
          if step.is_last_child && has_later_named_siblings {
            node_does_match = false
          }
          if step.supertype_symbol != 0 {
            let mut has_supertype = false
            for k in 0..<supertype_count {
              if supertypes[k] == step.supertype_symbol {
                has_supertype = true
                break
              }
            }
            if !has_supertype {
              node_does_match = false
            }
          }
          if step.field != 0 {
            if step.field == field_id {
              if !can_have_later_siblings_with_this_field {
                later_sibling_can_match = false
              }
            } else {
              node_does_match = false
            }
          }
          if step.negated_field_list_id != 0 {
            let mut k = step.negated_field_list_id
            for ;; {
              let negated_field_id = query.negated_fields[k]
              if negated_field_id != 0 {
                k += 1
                if !node.child_by_field_id(negated_field_id).is_null() {
                  node_does_match = false
                  break
                }
              } else {
                break
              }
            }
          }
          // Remove states immediately if it is ever clear that they cannot
          // match.
          if !node_does_match {
            if !later_sibling_can_match {
              self.capture_list_pool.release(state.capture_list_id)
              ignore(self.states.remove(j))
              j -= 1
            }
            j += 1 + copy_count
            continue
          }
          // Some patterns can match their root node in multiple ways,
          // capturing different children. If this pattern step could match
          // later children within the same parent, then this query state
          // cannot simply be updated in place. It must be split into two
          // states: one that matches this node, and one which skips over this
          // node, to preserve the possibility of matching later siblings.
          if later_sibling_can_match &&
            (step.contains_captures || query.step_is_fallible(state.step_index)) {
            if self.copy_state(j) is Some(_) {
              copy_count += 1
            }
          }
          // If this pattern started with a wildcard, such that the pattern map
          // actually points to the *second* step of the pattern, then check
          // that the node has a parent, and capture the parent node if
          // necessary.
          if state.needs_parent {
            let parent = cursor.parent_node()
            if parent.is_null() {
              state.dead = true
            } else {
              state.needs_parent = false
              let mut skipped_wildcard_index = state.step_index
              for ;; {
                skipped_wildcard_index -= 1
                let s = query.steps[skipped_wildcard_index]
                if !(s.is_dead_end || s.is_pass_through || s.depth > 0) {
                  break
                }
              }
              let skipped_wildcard_step = query.steps[skipped_wildcard_index]
              if skipped_wildcard_step.capture_ids[0] != none {
                self.capture(state, skipped_wildcard_step, parent)
              }
            }
          }
          // If the current node is captured in this pattern, add it to the
          // capture list.
          if step.capture_ids[0] != none {
            self.capture(state, step, node)
          }
          if state.dead {
            ignore(self.states.remove(j))
            j -= 1
            j += 1 + copy_count
            continue
          }
          // Advance this state to the next step of its pattern
          // (`step_index` is a `uint16_t`).
          state.step_index = (state.step_index + 1) & 0xFFFF
          let next_step = query.steps[state.step_index]
          // For a given step, if the current symbol is the wildcard symbol,
          // `_`, and it is **not** named, meaning it should capture anonymous
          // nodes, **and** the next step is immediate, we reuse the
          // `seeking_immediate_match` flag to indicate that we are looking
          // for an immediate match due to an unnamed wildcard symbol.
          if step.symbol == wildcard_symbol &&
            !step.is_named &&
            next_step.is_immediate {
            state.seeking_immediate_match = true
          } else {
            state.seeking_immediate_match = false
          }
          // The zero-skip's vacuous-anchor exemption only covers the immediate
          // step it lands on. Once the state advances, a later anchor is
          // normal.
          state.skipped_quantifier = false
          if stop_on_definite_step && next_step.root_pattern_guaranteed {
            did_match = true
          }
          // If this state's next step has an alternative step, then copy the
          // state in order to pursue both alternatives. The alternative step
          // itself may have an alternative, so this is an interactive process.
          let mut end_index = j + 1
          let mut k = j
          while k < end_index {
            let child_state = self.states[k]
            let child_step = query.steps[child_state.step_index]
            if child_step.alternative_index != none {
              // A "dead-end" step exists only to add a non-sequential jump
              // into the step sequence, via its alternative index. When a
              // state reaches a dead-end step, it jumps straight to the step's
              // alternative.
              if child_step.is_dead_end {
                child_state.step_index = child_step.alternative_index
                continue
              }
              // A "pass-through" step exists only to add a branch into the
              // step sequence, via its alternative_index. When a state
              // reaches a pass-through step, it splits in order to process the
              // alternative step, and then it advances to the next step.
              let mut revisit = false
              if child_step.is_pass_through {
                child_state.step_index = (child_state.step_index + 1) & 0xFFFF
                revisit = true
              }
              // A `?`/`*` zero-skip past a step that carries a trailing
              // last-child anchor transfers that requirement to the last
              // matched node. The skip is only valid if that node really is
              // the last named child.
              if child_step.alternative_is_skip &&
                child_step.is_last_child &&
                has_later_named_siblings {
                if !revisit {
                  k += 1
                }
                continue
              }
              if self.copy_state(k) is Some(copy) {
                end_index += 1
                copy_count += 1
                copy.step_index = child_step.alternative_index
                if child_step.is_pass_through {
                  copy.seeking_immediate_match = true
                }
                // Taking a `?`/`*` zero-skip means the quantified subpattern
                // matched nothing. How an adjacent anchor behaves then depends
                // on where it sat:
                if child_step.alternative_is_skip {
                  if !child_step.is_immediate {
                    let skip_target = query.steps[child_step.alternative_index]
                    // No leading anchor on the skipped step, so an
                    // immediately-following anchor on the skip target is
                    // vacuous (`Q* . B` with zero `Q` lets `B` match
                    // anywhere).
                    copy.skipped_quantifier = skip_target.depth ==
                      child_step.depth
                  } else if query.steps[child_state.step_index - 1].depth <
                    child_step.depth {
                    // The skipped step was the parent's first child pattern
                    // and carried a leading *boundary* anchor (`(P . Q* Y)`).
                    // Transfer the first-child requirement to the skip target
                    // so it survives the empty run: `Y` must still be the
                    // parent's first named child.
                    copy.seeking_immediate_match = true
                  }
                  // Otherwise the skipped step carried a leading *between*
                  // anchor (`A . Q* ...`): with zero `Q` that adjacency
                  // vanishes, while the skip target's own anchor, if any,
                  // still applies (`A . Q* . B` stays adjacent).
                }
              }
              if revisit {
                continue
              }
            }
            k += 1
          }
          j += 1 + copy_count
        }
        // Order states by capture position so the dedup pass below can stop
        // scanning a group once the remaining states are disjoint from the
        // current one.
        self.sort_states_by_capture()
        let mut j = 0
        while j < self.states.length() {
          let state = self.states[j]
          if state.dead {
            ignore(self.states.remove(j))
            continue
          }
          // Enforce the longest-match criteria. When a query pattern contains
          // optional or repeated nodes, this is necessary to avoid multiple
          // redundant states, where one state has a strict subset of another
          // state's captures.
          let mut did_remove = false
          let mut k = j + 1
          while k < self.states.length() {
            let other_state = self.states[k]
            // Query states are kept in ascending order of start_depth and
            // pattern_index, and in ascending order of first-capture position
            // within each such group. Since the longest-match criteria is only
            // used for deduping matches of the same pattern and root node, we
            // only need to perform pairwise comparisons within a small slice
            // of the states array.
            if other_state.start_depth != state.start_depth ||
              other_state.pattern_index != state.pattern_index {
              break
            }
            // States in a group acquire their first capture in tree-traversal
            // order. Once `other_state`'s captures begin at or after where
            // `state`'s captures end, `other_state` (and every state after it
            // in the group) is disjoint from `state`.
            let state_captures = self.capture_list_pool.get(state.capture_list_id)
            let other_captures = self.capture_list_pool.get(
              other_state.capture_list_id,
            )
            if state_captures.length() > 0 &&
              other_captures.length() > 0 &&
              other_captures[0].node.start_byte() >=
              state_captures[state_captures.length() - 1].node.end_byte() {
              break
            }
            let (left_contains_right, right_contains_left) = self.compare_captures(
              state, other_state,
            )
            if left_contains_right {
              if state.step_index == other_state.step_index &&
                (other_state.seeking_immediate_match ||
                !state.seeking_immediate_match) {
                self.capture_list_pool.release(other_state.capture_list_id)
                ignore(self.states.remove(k))
                continue
              }
              other_state.has_in_progress_alternatives = true
            }
            if right_contains_left {
              if state.step_index == other_state.step_index &&
                (state.seeking_immediate_match ||
                !other_state.seeking_immediate_match) {
                self.capture_list_pool.release(state.capture_list_id)
                ignore(self.states.remove(j))
                did_remove = true
                break
              }
              state.has_in_progress_alternatives = true
            }
            k += 1
          }
          // If the state is at the end of its pattern, remove it from the list
          // of in-progress states and add it to the list of finished states.
          if !did_remove {
            let next_step = query.steps[state.step_index]
            if next_step.depth == pattern_done_marker {
              if !state.has_in_progress_alternatives {
                self.push_finished_state(state)
                let index = self.index_of_state(state)
                ignore(self.states.remove(index))
                did_match = true
                continue
              }
            }
            j += 1
          }
        }
      }
      if node_intersects_containing_range &&
        self.should_descend(node_intersects_range) {
        match cursor.goto_first_child_internal() {
          StepVisible => {
            self.depth += 1
            self.on_visible_node = true
            continue
          }
          StepHidden => {
            self.on_visible_node = false
            continue
          }
          StepNone => ()
        }
      }
      self.ascending = true
    }
  }
}

///|
/// `state - self->states.contents`.
fn QueryCursor::index_of_state(self : QueryCursor, state : QueryState) -> Int {
  for i, s in self.states {
    if physical_equal(s, state) {
      return i
    }
  }
  abort("state is not in the states array")
}

///|
/// The `TSQueryMatch` of a state: its `capture_count` is a `uint16_t`, so only
/// the first `size & 0xFFFF` captures of the list are exposed.
fn QueryCursor::query_match(
  self : QueryCursor,
  state : QueryState,
) -> QueryMatch {
  let list = self.capture_list_pool.get_list(state.capture_list_id)
  let captures = list.expose()
  {
    id: state.id,
    pattern_index: state.pattern_index,
    captures: captures[:captures.length() & 0xFFFF],
    capture_list_id: state.capture_list_id,
    capture_list_serial: list.serial,
  }
}

///|
/// `ts_query_cursor_next_match`.
pub fn QueryCursor::next_match(self : QueryCursor) -> QueryMatch? {
  if self.finished_states.length() == 0 {
    if !self.advance(false) {
      return None
    }
  }
  if self.finished_states_heap_size > 0 {
    self.heapify_finished_states()
  }
  let mut state_index = 0
  if self.finished_states_heap_size > 0 {
    for i in 1..<self.finished_states.length() {
      let state = self.finished_states[i]
      let earliest_state = self.finished_states[state_index]
      if state.heap_insert_order < earliest_state.heap_insert_order {
        state_index = i
      }
    }
  }
  let state = self.finished_states[state_index]
  if state.id == 0xFFFFFFFFU {
    state.id = self.next_state_id
    self.next_state_id += 1
  }
  let result = self.query_match(state)
  self.capture_list_pool.release(state.capture_list_id)
  if self.finished_states_heap_size > 0 {
    finished_state_erase(self.finished_states, state_index, self.capture_list_pool)
    self.finished_states_heap_size = self.finished_states.length()
  } else {
    ignore(self.finished_states.remove(state_index))
  }
  Some(result)
}

///|
/// `ts_query_cursor_remove_match`.
pub fn QueryCursor::remove_match(self : QueryCursor, match_id : UInt) -> Unit {
  if self.finished_states_heap_size > 0 {
    self.heapify_finished_states()
  }
  for i, state in self.finished_states {
    if state.id == match_id {
      self.capture_list_pool.release(state.capture_list_id)
      if self.finished_states_heap_size > 0 {
        finished_state_erase(self.finished_states, i, self.capture_list_pool)
        self.finished_states_heap_size = self.finished_states.length()
      } else {
        ignore(self.finished_states.remove(i))
      }
      return
    }
  }
  // Remove unfinished query states as well to prevent future captures for a
  // match being removed.
  for i, state in self.states {
    if state.id == match_id {
      self.capture_list_pool.release(state.capture_list_id)
      ignore(self.states.remove(i))
      return
    }
  }
}

///|
/// `ts_query_cursor_next_capture`: the match and the index of the capture.
pub fn QueryCursor::next_capture(self : QueryCursor) -> (QueryMatch, Int)? {
  // The goal here is to return captures in order, even though they may not be
  // discovered in order, because patterns can overlap. Search for matches
  // until there is a finished capture that is before any unfinished capture.
  for ;; {
    // Sift any newly pushed finished states into the heap.
    self.heapify_finished_states()
    // First, find the earliest capture in an unfinished match.
    let (found_unfinished_state, first_unfinished) = self.first_in_progress_capture(
      true,
    )
    let first_unfinished_state_is_definite = found_unfinished_state &&
      first_unfinished.is_definite
    // Then find the earliest capture in a finished match. The finished_states
    // array is maintained as a min-heap, so the earliest is always at index 0.
    // Clean up fully-consumed and out-of-range states from the heap root
    // first.
    let mut first_finished_state : QueryState? = None
    let mut first_finished_capture_byte = first_unfinished.byte_offset
    let mut first_finished_pattern_index = first_unfinished.pattern_index
    while self.finished_states.length() > 0 {
      let state = self.finished_states[0]
      let captures = self.capture_list_pool.get(state.capture_list_id)
      // Remove states whose captures are all consumed.
      if state.consumed_capture_count >= captures.length() {
        self.capture_list_pool.release(state.capture_list_id)
        finished_state_pop(self.finished_states, self.capture_list_pool)
        self.finished_states_heap_size = self.finished_states.length()
        continue
      }
      let node = captures[state.consumed_capture_count].node
      let node_precedes_range = node.end_byte() <=
        self.included_range.start_byte ||
        @runtime.point_lte(node.end_point(), self.included_range.start_point)
      let node_follows_range = node.start_byte() >=
        self.included_range.end_byte ||
        @runtime.point_gte(node.start_point(), self.included_range.end_point)
      let node_outside_of_range = node_precedes_range || node_follows_range
      // Skip captures that are outside of the cursor's range.
      if node_outside_of_range {
        state.set_consumed_capture_count(state.consumed_capture_count + 1)
        finished_state_sift_down(self.finished_states, 0, self.capture_list_pool)
        continue
      }
      let node_start_byte = node.start_byte()
      if node_start_byte < first_finished_capture_byte ||
        (node_start_byte == first_finished_capture_byte &&
        state.pattern_index < first_finished_pattern_index) {
        first_finished_state = Some(state)
        first_finished_capture_byte = node_start_byte
        first_finished_pattern_index = state.pattern_index
      }
      break
    }
    // If there is finished capture that is clearly before any unfinished
    // capture, then return its match, and its capture index. Internally record
    // the fact that the capture has been 'consumed'.
    let state = match first_finished_state {
      Some(state) => Some(state)
      None =>
        if first_unfinished_state_is_definite {
          Some(self.states[first_unfinished.state_index])
        } else {
          None
        }
    }
    if state is Some(state) {
      if state.id == 0xFFFFFFFFU {
        state.id = self.next_state_id
        self.next_state_id += 1
      }
      let result = self.query_match(state)
      let capture_index = state.consumed_capture_count
      state.set_consumed_capture_count(state.consumed_capture_count + 1)
      // If this state is in the finished_states heap, its sort key has
      // changed (next capture is now later in the document). Restore heap
      // order.
      if first_finished_state is Some(first) && physical_equal(first, state) {
        finished_state_sift_down(self.finished_states, 0, self.capture_list_pool)
      }
      return Some((result, capture_index))
    }
    if self.capture_list_pool.is_empty() && found_unfinished_state {
      self.capture_list_pool.release(
        self.states[first_unfinished.state_index].capture_list_id,
      )
      ignore(self.states.remove(first_unfinished.state_index))
    }
    // If there are no finished matches that are ready to be returned, then
    // continue finding more matches.
    if !self.advance(true) && self.finished_states.length() == 0 {
      return None
    }
  }
}

///|
/// Converts the captures of the matches that [`QueryCursor::next_capture`]
/// returns (for the Rust binding's `QueryMatch`), sharing the conversion
/// between the captures of one match: upstream hands out a pointer to the
/// match's capture list for each of its captures, so iterating over the
/// captures of a match must not convert the whole list for each of them.
/// Like the views it returns, a cache belongs to one cursor.
pub struct CaptureConversionCache[T] {
  priv convert : (QueryCapture) -> T
  priv lists : Array[ConvertedCaptureList[T]?]
}

///|
/// The converted captures of the capture list with a given id and serial.
/// Like `CaptureList`, it only writes past its size, so views of it keep
/// their elements.
priv struct ConvertedCaptureList[T] {
  mut serial : Int
  mut items : FixedArray[T]
  mut size : Int
}

///|
/// Append `item`, growing the storage to at least `capacity` if it is full.
fn[T] ConvertedCaptureList::push(
  self : ConvertedCaptureList[T],
  item : T,
  capacity : Int,
) -> Unit {
  if self.size == self.items.length() {
    let items = FixedArray::make(
      if capacity > self.size * 2 {
        capacity
      } else {
        self.size * 2
      },
      item,
    )
    self.items.blit_to(items, len=self.size)
    self.items = items
  }
  self.items[self.size] = item
  self.size += 1
}

///|
/// Create an empty cache of the conversions of captures with `convert`.
pub fn[T] CaptureConversionCache::new(
  convert : (QueryCapture) -> T,
) -> CaptureConversionCache[T] {
  { convert, lists: [] }
}

///|
/// The converted captures of `m`, reusing the conversions of earlier calls
/// for the same capture list (a capture list only grows until it is cleared).
pub fn[T] CaptureConversionCache::convert(
  self : CaptureConversionCache[T],
  m : QueryMatch,
) -> ArrayView[T] {
  let count = m.captures.length()
  if count == 0 {
    return []
  }
  let id = m.capture_list_id.reinterpret_as_int()
  while self.lists.length() <= id {
    self.lists.push(None)
  }
  let list = match self.lists[id] {
    Some(list) => {
      if list.serial != m.capture_list_serial {
        // Views of the previous contents keep their storage.
        list.serial = m.capture_list_serial
        list.items = []
        list.size = 0
      }
      list
    }
    None => {
      let list = { serial: m.capture_list_serial, items: [], size: 0 }
      self.lists[id] = Some(list)
      list
    }
  }
  while list.size < count {
    list.push((self.convert)(m.captures[list.size]), count)
  }
  list.items[0:count]
}

///|
/// Drop all cached conversions.
pub fn[T] CaptureConversionCache::clear(
  self : CaptureConversionCache[T],
) -> Unit {
  self.lists.clear()
}
