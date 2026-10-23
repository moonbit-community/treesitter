// Port of tree-sitter lib/src/stack.h and lib/src/stack.c: the
// graph-structured parse stack.

///|
let max_link_count : Int32 = 8

///|
let max_iterator_count : Int32 = 64

///|
let max_node_pool_size : Int32 = 50

///|
pub type StackVersion = Int32

///|
pub let stack_version_none : Int32 = -1

///|
pub(all) struct StackSlice {
  subtrees : Array[Subtree]
  version : Int32
}

///|
pub(all) struct StackSummaryEntry {
  position : Length
  depth : Int32
  state : Int32
} derive(Eq, Debug)

///|
pub type StackSummary = Array[StackSummaryEntry]

///|
priv struct StackLink {
  node : StackNode
  subtree : Subtree
  is_pending : Bool
}

///|
priv struct StackNode {
  mut state : Int32
  mut position : Length
  /// `links[0..link_count]`; a node rarely gains links after creation, so
  /// the array is replaced rather than grown.
  mut links : FixedArray[StackLink]
  mut ref_count : Int32
  mut error_cost : UInt32
  mut node_count : UInt32
  mut dynamic_precedence : Int32
  /// Stands in for the node's address in dot graphs.
  mut id : Int32
}

///|
priv struct StackIterator {
  mut node : StackNode
  mut subtrees : Array[Subtree]
  mut subtree_count : Int32
  mut is_pending : Bool
}

///|
fn StackIterator::copy(self : StackIterator) -> StackIterator {
  { ..self, }
}

///|
priv enum StackStatus {
  Active
  Paused
  Halted
} derive(Eq)

///|
priv struct StackHead {
  mut node : StackNode
  mut summary : StackSummary?
  mut node_count_at_last_error : UInt32
  mut last_external_token : Subtree
  mut lookahead_when_paused : Subtree
  mut status : StackStatus
}

///|
fn StackHead::copy(self : StackHead) -> StackHead {
  { ..self, }
}

///|
pub struct Stack {
  priv heads : Array[StackHead]
  priv mut slices : Array[StackSlice]
  priv iterators : Array[StackIterator]
  priv base_node : StackNode
  /// Released nodes kept for reuse (`node_pool`), at most
  /// `max_node_pool_size`.
  priv node_pool : Array[StackNode]
  priv mut next_node_id : Int32
}

///|
let stack_action_none : Int32 = 0

///|
let stack_action_stop : Int32 = 1

///|
let stack_action_pop : Int32 = 2

///|
fn stack_node_retain(node : StackNode?) -> Unit {
  if node is Some(node) {
    node.ref_count += 1
  }
}

///|
fn stack_node_release(node : StackNode, pool : Array[StackNode]) -> Unit {
  let mut current = node
  for ;; {
    current.ref_count -= 1
    if current.ref_count > 0 {
      return
    }
    let mut first_predecessor : StackNode? = None
    if current.links.length() > 0 {
      for i = current.links.length() - 1; i > 0; i = i - 1 {
        let link = current.links[i]
        if !link.subtree.is_null() {
          link.subtree.release()
        }
        stack_node_release(link.node, pool)
      }
      let link = current.links[0]
      if !link.subtree.is_null() {
        link.subtree.release()
      }
      first_predecessor = Some(current.links[0].node)
    }
    if pool.length() < max_node_pool_size {
      pool.push(current)
    }
    match first_predecessor {
      Some(predecessor) => current = predecessor
      None => return
    }
  }
}

///|
/// Get the number of nodes in the subtree, for the purpose of measuring how
/// much progress has been made by a given version of the stack.
fn stack_subtree_node_count(subtree : Subtree) -> UInt32 {
  let mut count = subtree.visible_descendant_count()
  if subtree.visible() {
    count += 1
  }
  // Count intermediate error nodes even though they are not visible, because
  // a stack version's node count is used to check whether it has made any
  // progress since the last time it encountered an error.
  if subtree.symbol() == @language.ts_builtin_sym_error_repeat {
    count += 1
  }
  count
}

///|
fn Stack::node_new(
  self : Stack,
  previous_node : StackNode?,
  subtree : Subtree,
  is_pending : Bool,
  state : Int32,
) -> StackNode {
  let id = self.next_node_id
  self.next_node_id += 1
  let node = match self.node_pool.pop() {
    Some(node) => {
      node.state = state
      node.position = length_zero()
      match previous_node {
        Some(previous) =>
          if node.links.length() == 1 {
            node.links[0] = { node: previous, subtree, is_pending }
          } else {
            node.links = [{ node: previous, subtree, is_pending }]
          }
        None => node.links = []
      }
      node.ref_count = 1
      node.error_cost = 0
      node.node_count = 0
      node.dynamic_precedence = 0
      node.id = id
      node
    }
    None => {
      state,
      position: length_zero(),
      links: match previous_node {
        Some(previous) => [{ node: previous, subtree, is_pending }]
        None => []
      },
      ref_count: 1,
      error_cost: 0,
      node_count: 0,
      dynamic_precedence: 0,
      id,
    }
  }
  if previous_node is Some(previous) {
    node.position = previous.position
    node.error_cost = previous.error_cost
    node.dynamic_precedence = previous.dynamic_precedence
    node.node_count = previous.node_count
    if !subtree.is_null() {
      node.error_cost += subtree.error_cost()
      node.position = length_add(node.position, subtree.total_size())
      node.node_count += stack_subtree_node_count(subtree)
      node.dynamic_precedence += subtree.dynamic_precedence()
    }
  } else {
    node.position = length_zero()
    node.error_cost = 0
  }
  node
}

///|
fn stack_subtree_is_equivalent(left : Subtree, right : Subtree) -> Bool {
  if left.ptr_eq(right) {
    return true
  }
  if left.is_null() || right.is_null() {
    return false
  }
  // Symbols must match
  if left.symbol() != right.symbol() {
    return false
  }
  // If both have errors, don't bother keeping both.
  if left.error_cost() > 0 && right.error_cost() > 0 {
    return true
  }
  left.padding().bytes == right.padding().bytes &&
  left.size().bytes == right.size().bytes &&
  left.child_count() == right.child_count() &&
  left.extra() == right.extra() &&
  left.external_scanner_state_eq(right)
}

///|
fn stack_node_add_link(target : StackNode, link : StackLink) -> Unit {
  if physical_equal(link.node, target) {
    return
  }
  for i in 0..<target.links.length() {
    let existing_link = target.links[i]
    if stack_subtree_is_equivalent(existing_link.subtree, link.subtree) {
      // In general, we preserve ambiguities until they are removed from the
      // stack during a pop operation where multiple paths lead to the same
      // node. But in the special case where two links directly connect the
      // same pair of nodes, we can safely remove the ambiguity ahead of time
      // without changing behavior.
      if physical_equal(existing_link.node, link.node) {
        if link.subtree.dynamic_precedence() >
          existing_link.subtree.dynamic_precedence() {
          link.subtree.retain()
          existing_link.subtree.release()
          target.links[i] = { ..existing_link, subtree: link.subtree, }
          target.dynamic_precedence = link.node.dynamic_precedence +
            link.subtree.dynamic_precedence()
        }
        return
      }
      // If the previous nodes are mergeable, merge them recursively.
      if existing_link.node.state == link.node.state &&
        existing_link.node.position.bytes == link.node.position.bytes &&
        existing_link.node.error_cost == link.node.error_cost {
        for j in 0..<link.node.links.length() {
          stack_node_add_link(existing_link.node, link.node.links[j])
        }
        let mut dynamic_precedence = link.node.dynamic_precedence
        if !link.subtree.is_null() {
          dynamic_precedence += link.subtree.dynamic_precedence()
        }
        if dynamic_precedence > target.dynamic_precedence {
          target.dynamic_precedence = dynamic_precedence
        }
        return
      }
    }
  }
  if target.links.length() == max_link_count {
    return
  }
  stack_node_retain(Some(link.node))
  let mut node_count = link.node.node_count
  let mut dynamic_precedence = link.node.dynamic_precedence
  let link_count = target.links.length()
  let links = FixedArray::make(link_count + 1, link)
  links.unsafe_blit(0, target.links, 0, link_count)
  target.links = links
  if !link.subtree.is_null() {
    link.subtree.retain()
    node_count += stack_subtree_node_count(link.subtree)
    dynamic_precedence += link.subtree.dynamic_precedence()
  }
  if node_count > target.node_count {
    target.node_count = node_count
  }
  if dynamic_precedence > target.dynamic_precedence {
    target.dynamic_precedence = dynamic_precedence
  }
}

///|
fn stack_head_delete(head : StackHead, pool : Array[StackNode]) -> Unit {
  if !head.last_external_token.is_null() {
    head.last_external_token.release()
  }
  if !head.lookahead_when_paused.is_null() {
    head.lookahead_when_paused.release()
  }
  stack_node_release(head.node, pool)
}

///|
fn Stack::add_version(
  self : Stack,
  original_version : Int32,
  node : StackNode,
) -> Int32 {
  let head : StackHead = {
    node,
    summary: None,
    node_count_at_last_error: self.heads[original_version].node_count_at_last_error,
    last_external_token: self.heads[original_version].last_external_token,
    status: Active,
    lookahead_when_paused: Null,
  }
  self.heads.push(head)
  stack_node_retain(Some(node))
  if !head.last_external_token.is_null() {
    head.last_external_token.retain()
  }
  self.heads.length() - 1
}

///|
fn Stack::add_slice(
  self : Stack,
  original_version : Int32,
  node : StackNode,
  subtrees : Array[Subtree],
) -> Unit {
  for i = self.slices.length() - 1; i >= 0; i = i - 1 {
    let version = self.slices[i].version
    if physical_equal(self.heads[version].node, node) {
      self.slices.insert(i + 1, { subtrees, version, })
      return
    }
  }
  let version = self.add_version(original_version, node)
  self.slices.push({ subtrees, version, })
}

///|
fn[P] Stack::iter(
  self : Stack,
  version : Int32,
  callback : (P, StackIterator) -> Int32,
  payload : P,
  goal_subtree_count : Int32,
) -> Array[StackSlice] {
  self.slices = []
  self.iterators.clear()
  let head = self.heads[version]
  let include_subtrees = goal_subtree_count >= 0
  let new_iterator : StackIterator = {
    node: head.node,
    subtrees: if include_subtrees {
      Array(capacity=goal_subtree_count)
    } else {
      []
    },
    subtree_count: 0,
    is_pending: true,
  }
  self.iterators.push(new_iterator)
  while self.iterators.length() > 0 {
    let mut i = 0
    let mut size = self.iterators.length()
    while i < size {
      let iterator = self.iterators[i]
      let node = iterator.node
      let action = callback(payload, iterator)
      let should_pop = (action & stack_action_pop) != 0
      let should_stop = (action & stack_action_stop) != 0 ||
        node.links.length() == 0
      if should_pop {
        let mut subtrees = iterator.subtrees
        if !should_stop {
          subtrees = subtree_array_copy(subtrees)
        }
        subtree_array_reverse(subtrees)
        self.add_slice(version, node, subtrees)
      }
      if should_stop {
        if !should_pop {
          subtree_array_delete(iterator.subtrees)
        }
        ignore(self.iterators.remove(i))
        size -= 1
        continue
      }
      for j in 1..<=node.links.length() {
        let mut next_iterator : StackIterator = iterator
        let mut link = node.links[0]
        if j == node.links.length() {
          link = node.links[0]
          next_iterator = self.iterators[i]
        } else {
          if self.iterators.length() >= max_iterator_count {
            continue
          }
          link = node.links[j]
          let current_iterator = self.iterators[i].copy()
          self.iterators.push(current_iterator)
          next_iterator = current_iterator
          next_iterator.subtrees = subtree_array_copy(next_iterator.subtrees)
        }
        next_iterator.node = link.node
        if !link.subtree.is_null() {
          if include_subtrees {
            next_iterator.subtrees.push(link.subtree)
            link.subtree.retain()
          }
          if !link.subtree.extra() {
            next_iterator.subtree_count += 1
            if !link.is_pending {
              next_iterator.is_pending = false
            }
          }
        } else {
          next_iterator.subtree_count += 1
          next_iterator.is_pending = false
        }
      }
      i += 1
    }
  }
  self.slices
}

///|
/// `ts_stack_new`.
pub fn Stack::new() -> Stack {
  let self : Stack = {
    heads: [],
    slices: [],
    iterators: [],
    node_pool: [],
    base_node: {
      state: 1,
      position: length_zero(),
      links: [],
      ref_count: 1,
      error_cost: 0,
      node_count: 0,
      dynamic_precedence: 0,
      id: 0,
    },
    next_node_id: 1,
  }
  self.clear()
  self
}

///|
pub fn Stack::version_count(self : Stack) -> Int32 {
  self.heads.length()
}

///|
pub fn Stack::halted_version_count(self : Stack) -> Int32 {
  let mut count = 0
  for head in self.heads {
    if head.status == Halted {
      count += 1
    }
  }
  count
}

///|
pub fn Stack::state(self : Stack, version : Int32) -> Int32 {
  self.heads[version].node.state
}

///|
pub fn Stack::position(self : Stack, version : Int32) -> Length {
  self.heads[version].node.position
}

///|
pub fn Stack::last_external_token(self : Stack, version : Int32) -> Subtree {
  self.heads[version].last_external_token
}

///|
pub fn Stack::set_last_external_token(
  self : Stack,
  version : Int32,
  token : Subtree,
) -> Unit {
  let head = self.heads[version]
  if !token.is_null() {
    token.retain()
  }
  if !head.last_external_token.is_null() {
    head.last_external_token.release()
  }
  head.last_external_token = token
}

///|
pub fn Stack::error_cost(self : Stack, version : Int32) -> UInt32 {
  let head = self.heads[version]
  let mut result = head.node.error_cost
  if head.status == Paused ||
    (
      head.node.state == error_state &&
      (head.node.links.is_empty() || head.node.links[0].subtree.is_null())
    ) {
    result += error_cost_per_recovery
  }
  result
}

///|
pub fn Stack::node_count_since_error(self : Stack, version : Int32) -> UInt32 {
  let head = self.heads[version]
  if head.node.node_count < head.node_count_at_last_error {
    head.node_count_at_last_error = head.node.node_count
  }
  head.node.node_count - head.node_count_at_last_error
}

///|
pub fn Stack::push(
  self : Stack,
  version : Int32,
  subtree : Subtree,
  pending : Bool,
  state : Int32,
) -> Unit {
  let head = self.heads[version]
  let new_node = self.node_new(Some(head.node), subtree, pending, state)
  if subtree.is_null() {
    head.node_count_at_last_error = new_node.node_count
  }
  head.node = new_node
}

///|
fn pop_count_callback(goal_subtree_count : Int32, iterator : StackIterator) -> Int32 {
  if iterator.subtree_count == goal_subtree_count {
    stack_action_pop | stack_action_stop
  } else {
    stack_action_none
  }
}

///|
pub fn Stack::pop_count(
  self : Stack,
  version : Int32,
  count : Int32,
) -> Array[StackSlice] {
  self.iter(version, pop_count_callback, count, count)
}

///|
fn pop_pending_callback(_payload : Unit, iterator : StackIterator) -> Int32 {
  if iterator.subtree_count >= 1 {
    if iterator.is_pending {
      stack_action_pop | stack_action_stop
    } else {
      stack_action_stop
    }
  } else {
    stack_action_none
  }
}

///|
pub fn Stack::pop_pending(self : Stack, version : Int32) -> Array[StackSlice] {
  let pop = self.iter(version, pop_pending_callback, (), 0)
  if pop.length() > 0 {
    self.renumber_version(pop[0].version, version)
    pop[0] = { ..pop[0], version, }
  }
  pop
}

///|
fn pop_error_callback(found_error : Ref[Bool], iterator : StackIterator) -> Int32 {
  if iterator.subtrees.length() > 0 {
    if !found_error.val && iterator.subtrees[0].is_error() {
      found_error.val = true
      stack_action_pop | stack_action_stop
    } else {
      stack_action_stop
    }
  } else {
    stack_action_none
  }
}

///|
pub fn Stack::pop_error(self : Stack, version : Int32) -> Array[Subtree] {
  let node = self.heads[version].node
  for i in 0..<node.links.length() {
    if !node.links[i].subtree.is_null() && node.links[i].subtree.is_error() {
      let found_error = Ref(false)
      let pop = self.iter(version, pop_error_callback, found_error, 1)
      if pop.length() > 0 {
        self.renumber_version(pop[0].version, version)
        return pop[0].subtrees
      }
      break
    }
  }
  []
}

///|
fn pop_all_callback(_payload : Unit, iterator : StackIterator) -> Int32 {
  if iterator.node.links.length() == 0 {
    stack_action_pop
  } else {
    stack_action_none
  }
}

///|
pub fn Stack::pop_all(self : Stack, version : Int32) -> Array[StackSlice] {
  self.iter(version, pop_all_callback, (), 0)
}

///|
pub fn Stack::record_summary(
  self : Stack,
  version : Int32,
  max_depth : Int32,
) -> Unit {
  let summary : StackSummary = []
  ignore(
    self.iter(
      version,
      (_, iterator) => {
        let state = iterator.node.state
        let depth = iterator.subtree_count
        if depth > max_depth {
          return stack_action_stop
        }
        for i = summary.length() - 1; i >= 0; i = i - 1 {
          let entry = summary[i]
          if entry.depth < depth {
            break
          }
          if entry.depth == depth && entry.state == state {
            return stack_action_none
          }
        }
        summary.push({ position: iterator.node.position, depth, state, })
        stack_action_none
      },
      (),
      -1,
    ),
  )
  self.heads[version].summary = Some(summary)
}

///|
pub fn Stack::get_summary(self : Stack, version : Int32) -> StackSummary? {
  self.heads[version].summary
}

///|
pub fn Stack::dynamic_precedence(self : Stack, version : Int32) -> Int32 {
  self.heads[version].node.dynamic_precedence
}

///|
pub fn Stack::has_advanced_since_error(self : Stack, version : Int32) -> Bool {
  let head = self.heads[version]
  let mut node = head.node
  if node.error_cost == 0 {
    return true
  }
  for ;; {
    if node.links.length() > 0 {
      let subtree = node.links[0].subtree
      if !subtree.is_null() {
        if subtree.total_bytes() > 0 {
          return true
        } else if node.node_count > head.node_count_at_last_error &&
          subtree.error_cost() == 0 {
          node = node.links[0].node
          continue
        }
      }
    }
    break
  }
  false
}

///|
pub fn Stack::remove_version(self : Stack, version : Int32) -> Unit {
  stack_head_delete(self.heads[version], self.node_pool)
  ignore(self.heads.remove(version))
}

///|
pub fn Stack::renumber_version(self : Stack, v1 : Int32, v2 : Int32) -> Unit {
  if v1 == v2 {
    return
  }
  let source_head = self.heads[v1]
  let target_head = self.heads[v2]
  if target_head.summary is Some(_) && source_head.summary is None {
    source_head.summary = target_head.summary
    target_head.summary = None
  }
  stack_head_delete(target_head, self.node_pool)
  // `*target_head = *source_head` followed by erasing `v1`: the source head
  // record is moved rather than copied, since nothing else refers to it.
  self.heads[v2] = source_head
  ignore(self.heads.remove(v1))
}

///|
pub fn Stack::swap_versions(self : Stack, v1 : Int32, v2 : Int32) -> Unit {
  let temporary_head = self.heads[v1]
  self.heads[v1] = self.heads[v2]
  self.heads[v2] = temporary_head
}

///|
pub fn Stack::copy_version(self : Stack, version : Int32) -> Int32 {
  let head = self.heads[version].copy()
  self.heads.push(head)
  stack_node_retain(Some(head.node))
  if !head.last_external_token.is_null() {
    head.last_external_token.retain()
  }
  head.summary = None
  self.heads.length() - 1
}

///|
pub fn Stack::merge(self : Stack, version1 : Int32, version2 : Int32) -> Bool {
  if !self.can_merge(version1, version2) {
    return false
  }
  let head1 = self.heads[version1]
  let head2 = self.heads[version2]
  for i in 0..<head2.node.links.length() {
    stack_node_add_link(head1.node, head2.node.links[i])
  }
  if head1.node.state == error_state {
    head1.node_count_at_last_error = head1.node.node_count
  }
  self.remove_version(version2)
  true
}

///|
pub fn Stack::can_merge(
  self : Stack,
  version1 : Int32,
  version2 : Int32,
) -> Bool {
  let head1 = self.heads[version1]
  let head2 = self.heads[version2]
  head1.status == Active &&
  head2.status == Active &&
  head1.node.state == head2.node.state &&
  head1.node.position.bytes == head2.node.position.bytes &&
  head1.node.error_cost == head2.node.error_cost &&
  head1.last_external_token.external_scanner_state_eq(head2.last_external_token)
}

///|
pub fn Stack::halt(self : Stack, version : Int32) -> Unit {
  self.heads[version].status = Halted
}

///|
pub fn Stack::pause(self : Stack, version : Int32, lookahead : Subtree) -> Unit {
  let head = self.heads[version]
  head.status = Paused
  head.lookahead_when_paused = lookahead
  head.node_count_at_last_error = head.node.node_count
}

///|
pub fn Stack::is_active(self : Stack, version : Int32) -> Bool {
  self.heads[version].status == Active
}

///|
pub fn Stack::is_halted(self : Stack, version : Int32) -> Bool {
  self.heads[version].status == Halted
}

///|
pub fn Stack::is_paused(self : Stack, version : Int32) -> Bool {
  self.heads[version].status == Paused
}

///|
pub fn Stack::resume(self : Stack, version : Int32) -> Subtree {
  let head = self.heads[version]
  let result = head.lookahead_when_paused
  head.status = Active
  head.lookahead_when_paused = Null
  result
}

///|
pub fn Stack::clear(self : Stack) -> Unit {
  stack_node_retain(Some(self.base_node))
  for head in self.heads {
    stack_head_delete(head, self.node_pool)
  }
  self.heads.clear()
  self.heads.push({
    node: self.base_node,
    summary: None,
    node_count_at_last_error: 0,
    status: Active,
    last_external_token: Null,
    lookahead_when_paused: Null,
  })
}

///|
/// `ts_stack_print_dot_graph`. Node addresses are replaced by stable ids.
pub fn Stack::print_dot_graph(
  self : Stack,
  language : @language.Language,
  f : StringBuilder,
) -> Bool {
  f.write_string("digraph stack {\n")
  f.write_string("rankdir=\"RL\";\n")
  f.write_string("edge [arrowhead=none]\n")
  let visited_nodes : Array[StackNode] = []
  self.iterators.clear()
  for i, head in self.heads {
    if head.status == Halted {
      continue
    }
    f.write_string("node_head_\{i} [shape=none, label=\"\"]\n")
    f.write_string("node_head_\{i} -> node_\{head.node.id} [")
    if head.status == Paused {
      f.write_string("color=red ")
    }
    f.write_string(
      "label=\{i}, fontcolor=blue, weight=10000, labeltooltip=\"node_count: \{self.node_count_since_error(i)}\nerror_cost: \{self.error_cost(i)}",
    )
    if head.summary is Some(summary) {
      f.write_string("\nsummary:")
      for entry in summary {
        f.write_string(" \{entry.state}")
      }
    }
    if !head.last_external_token.is_null() {
      let state = head.last_external_token.ptr().external_scanner_state
      f.write_string("\nexternal_scanner_state:")
      for byte in state {
        f.write_string(" \{hex2(byte)}")
      }
    }
    f.write_string("\"]\n")
    self.iterators.push({
      node: head.node,
      subtrees: [],
      subtree_count: 0,
      is_pending: false,
    })
  }
  let mut all_iterators_done = false
  while !all_iterators_done {
    all_iterators_done = true
    let mut i = 0
    while i < self.iterators.length() {
      let iterator = self.iterators[i].copy()
      let node = iterator.node
      if visited_nodes.iter().any(n => physical_equal(n, node)) {
        i += 1
        continue
      }
      all_iterators_done = false
      f.write_string("node_\{node.id} [")
      if node.state == error_state {
        f.write_string("label=\"?\"")
      } else if node.links.length() == 1 &&
        !node.links[0].subtree.is_null() &&
        node.links[0].subtree.extra() {
        f.write_string("shape=point margin=0 label=\"\"")
      } else {
        f.write_string("label=\"\{node.state}\"")
      }
      f.write_string(
        " tooltip=\"position: \{node.position.extent.row + 1},\{node.position.extent.column}\nnode_count:\{node.node_count}\nerror_cost: \{node.error_cost}\ndynamic_precedence: \{node.dynamic_precedence}\"];\n",
      )
      for j, link in node.links {
        f.write_string("node_\{node.id} -> node_\{link.node.id} [")
        if link.is_pending {
          f.write_string("style=dashed ")
        }
        if !link.subtree.is_null() && link.subtree.extra() {
          f.write_string("fontcolor=gray ")
        }
        if link.subtree.is_null() {
          f.write_string("color=red")
        } else {
          f.write_string("label=\"")
          let quoted = link.subtree.visible() && !link.subtree.named()
          if quoted {
            f.write_string("'")
          }
          write_symbol_as_dot_string(language, f, link.subtree.symbol())
          if quoted {
            f.write_string("'")
          }
          f.write_string("\"")
          f.write_string(
            "labeltooltip=\"error_cost: \{link.subtree.error_cost()}\ndynamic_precedence: \{link.subtree.dynamic_precedence()}\"",
          )
        }
        f.write_string("];\n")
        if j == 0 {
          self.iterators[i].node = link.node
        } else {
          let next = iterator.copy()
          next.node = link.node
          self.iterators.push(next)
        }
      }
      visited_nodes.push(node)
      i += 1
    }
  }
  f.write_string("}\n")
  true
}

///|
/// `%2X` formatting of a (signed) `char`.
fn hex2(byte : Byte) -> String {
  let value = byte.to_int()
  // `data[j]` is a `char`, sign-extended when passed to printf.
  let value = if value >= 128 { value - 256 } else { value }
  let unsigned = value.reinterpret_as_uint()
  let digits = "0123456789ABCDEF"
  let buf = StringBuilder()
  let mut started = false
  for shift = 28; shift >= 0; shift = shift - 4 {
    let d = ((unsigned >> shift) & 0xF).reinterpret_as_int()
    if d != 0 || started || shift == 0 {
      started = true
      buf.write_char(digits.get_char(d).unwrap())
    }
  }
  let s = buf.to_string()
  if s.length() < 2 {
    " " + s
  } else {
    s
  }
}

///|
/// `ts_language_write_symbol_as_dot_string`.
pub fn write_symbol_as_dot_string(
  language : @language.Language,
  f : StringBuilder,
  symbol : Int32,
) -> Unit {
  let name = language.symbol_name(symbol).unwrap_or("")
  for chr in name {
    match chr {
      '"' | '\\' => {
        f.write_char('\\')
        f.write_char(chr)
      }
      '\n' => f.write_string("\\n")
      '\t' => f.write_string("\\t")
      _ => f.write_char(chr)
    }
  }
}
