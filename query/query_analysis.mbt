// Port of the query analysis in tree-sitter lib/src/query.c: walking the
// parse table to determine which pattern steps are guaranteed to match.

///|
/// AnalysisStateEntry. `field_id` is a 15-bit field upstream.
priv struct AnalysisStateEntry {
  parse_state : Int
  parent_symbol : Int
  child_index : Int
  field_id : Int
  done : Bool
} derive(Eq)

///|
let empty_analysis_entry : AnalysisStateEntry = {
  parse_state: 0,
  parent_symbol: 0,
  child_index: 0,
  field_id: 0,
  done: false,
}

///|
/// AnalysisState - The state needed for walking the parse table when
/// analyzing a query pattern, to determine at which steps the pattern might
/// fail to match.
priv struct AnalysisState {
  stack : FixedArray[AnalysisStateEntry]
  mut depth : Int
  mut step_index : Int
  root_symbol : Int
}

///|
fn AnalysisState::new(
  step_index : Int,
  entry : AnalysisStateEntry,
  root_symbol : Int,
) -> AnalysisState {
  let stack = FixedArray::make(max_analysis_state_depth, empty_analysis_entry)
  stack[0] = entry
  { stack, depth: 1, step_index, root_symbol }
}

///|
/// A value copy (`AnalysisState next_state = *state`).
fn AnalysisState::copy(self : AnalysisState) -> AnalysisState {
  { ..self, stack: self.stack.copy() }
}

///|
fn AnalysisState::recursion_depth(self : AnalysisState) -> Int {
  let mut result = 0
  for i in 0..<self.depth {
    let symbol = self.stack[i].parent_symbol
    for j in 0..<i {
      if self.stack[j].parent_symbol == symbol {
        result += 1
        break
      }
    }
  }
  result
}

///|
fn analysis_state_compare(left : AnalysisState, other : AnalysisState) -> Int {
  if left.depth < other.depth {
    return 1
  }
  for i in 0..<left.depth {
    if i >= other.depth {
      return -1
    }
    let s1 = left.stack[i]
    let s2 = other.stack[i]
    if s1.child_index < s2.child_index {
      return -1
    }
    if s1.child_index > s2.child_index {
      return 1
    }
    if s1.parent_symbol < s2.parent_symbol {
      return -1
    }
    if s1.parent_symbol > s2.parent_symbol {
      return 1
    }
    if s1.parse_state < s2.parse_state {
      return -1
    }
    if s1.parse_state > s2.parse_state {
      return 1
    }
    if s1.field_id < s2.field_id {
      return -1
    }
    if s1.field_id > s2.field_id {
      return 1
    }
  }
  if left.step_index < other.step_index {
    return -1
  }
  if left.step_index > other.step_index {
    return 1
  }
  0
}

///|
/// The index of `analysis_state__top`.
fn AnalysisState::top_index(self : AnalysisState) -> Int {
  if self.depth == 0 {
    0
  } else {
    self.depth - 1
  }
}

///|
fn AnalysisState::top(self : AnalysisState) -> AnalysisStateEntry {
  self.stack[self.top_index()]
}

///|
fn AnalysisState::has_supertype(self : AnalysisState, symbol : Int) -> Bool {
  for i in 0..<self.depth {
    if self.stack[i].parent_symbol == symbol {
      return true
    }
  }
  false
}

///|
/// Inserts a clone of the item at the appropriate position to maintain
/// ordering in this set, unless it is already present.
fn analysis_state_set_insert_sorted(
  set : Array[AnalysisState],
  item : AnalysisState,
) -> Unit {
  let (index, exists) = search_sorted_with(set, s => {
    analysis_state_compare(s, item)
  })
  if !exists {
    set.insert(index, item.copy())
  }
}

///|
/// Inserts a clone of the item at the end of this list.
fn analysis_state_set_push(
  set : Array[AnalysisState],
  item : AnalysisState,
) -> Unit {
  set.push(item.copy())
}

///|
priv struct QueryAnalysis {
  mut states : Array[AnalysisState]
  mut next_states : Array[AnalysisState]
  mut deeper_states : Array[AnalysisState]
  final_step_indices : Array[Int]
  finished_parent_symbols : Array[Int]
  mut did_abort : Bool
}

///|
fn QueryAnalysis::new() -> QueryAnalysis {
  {
    states: [],
    next_states: [],
    deeper_states: [],
    final_step_indices: [],
    finished_parent_symbols: [],
    did_abort: false,
  }
}

///|
/// AnalysisSubgraphNode. `child_index` is a 7-bit field upstream, so it is
/// kept truncated to 7 bits.
priv struct AnalysisSubgraphNode {
  state : Int
  production_id : Int
  child_index : Int
  done : Bool
}

///|
fn subgraph_node(
  state : Int,
  production_id : Int,
  child_index : Int,
  done : Bool,
) -> AnalysisSubgraphNode {
  { state, production_id, child_index: child_index & 0x7F, done }
}

///|
fn analysis_subgraph_node_compare(
  left : AnalysisSubgraphNode,
  other : AnalysisSubgraphNode,
) -> Int {
  if left.state < other.state {
    return -1
  }
  if left.state > other.state {
    return 1
  }
  if left.child_index < other.child_index {
    return -1
  }
  if left.child_index > other.child_index {
    return 1
  }
  if !left.done && other.done {
    return -1
  }
  if left.done && !other.done {
    return 1
  }
  if left.production_id < other.production_id {
    return -1
  }
  if left.production_id > other.production_id {
    return 1
  }
  0
}

///|
/// AnalysisSubgraph - A subset of the states in the parse table that are used
/// in constructing nodes with a certain symbol.
priv struct AnalysisSubgraph {
  symbol : Int
  start_states : Array[Int]
  nodes : Array[AnalysisSubgraphNode]
}

///|
/// Walk the subgraph for this non-terminal, tracking all of the possible
/// sequences of progress within the pattern.
fn Query::perform_analysis(
  self : Query,
  subgraphs : Array[AnalysisSubgraph],
  analysis : QueryAnalysis,
) -> Unit {
  let language = self.language
  let mut recursion_depth_limit = 0
  let mut prev_final_step_count = 0
  analysis.final_step_indices.clear()
  analysis.finished_parent_symbols.clear()
  let mut iteration = 0
  for ;; {
    if iteration == max_analysis_iteration_count {
      analysis.did_abort = true
      break
    }
    iteration += 1
    // If no further progress can be made within the current recursion depth
    // limit, then bump the depth limit by one, and continue to process the
    // states the exceeded the limit. But only allow this if progress has
    // been made since the last time the depth limit was increased.
    if analysis.states.length() == 0 {
      if analysis.deeper_states.length() > 0 &&
        analysis.final_step_indices.length() > prev_final_step_count {
        prev_final_step_count = analysis.final_step_indices.length()
        recursion_depth_limit += 1
        let states = analysis.states
        analysis.states = analysis.deeper_states
        analysis.deeper_states = states
        continue
      }
      break
    }
    analysis.next_states.clear()
    let mut j = 0
    while j < analysis.states.length() {
      let state = analysis.states[j]
      // For efficiency, it's important to avoid processing the same analysis
      // state more than once. To achieve this, keep the states in order of
      // ascending position within their hypothetical syntax trees. In each
      // iteration of this loop, start by advancing the states that have made
      // the least progress. Avoid advancing states that have already made
      // more progress.
      if analysis.next_states.length() > 0 {
        let comparison = analysis_state_compare(
          state,
          analysis.next_states[analysis.next_states.length() - 1],
        )
        if comparison == 0 {
          analysis_state_set_insert_sorted(analysis.next_states, state)
          j += 1
          continue
        } else if comparison > 0 {
          while j < analysis.states.length() {
            analysis_state_set_push(analysis.next_states, analysis.states[j])
            j += 1
          }
          break
        }
      }
      let top = state.top()
      let parse_state = top.parse_state
      let parent_symbol = top.parent_symbol
      let parent_field_id = top.field_id
      let child_index = top.child_index
      let step = self.steps[state.step_index]
      let (subgraph_index, exists) = search_sorted_by(
        subgraphs,
        s => s.symbol,
        parent_symbol,
      )
      if !exists {
        j += 1
        continue
      }
      let subgraph = subgraphs[subgraph_index]
      // Follow every possible path in the parse table, but only visit states
      // that are part of the subgraph for the current symbol.
      let lookahead_iterator = language.lookaheads(parse_state)
      while lookahead_iterator.next() {
        let sym = lookahead_iterator.current_symbol()
        let mut successor_state = parse_state
        let mut successor_child_index = child_index & 0x7F
        let actions = lookahead_iterator.actions()
        if actions.length() > 0 {
          match actions[actions.length() - 1] {
            Shift(state=shift_state, extra~, ..) =>
              if !extra {
                successor_state = shift_state
                successor_child_index = (successor_child_index + 1) & 0x7F
              }
            _ => continue
          }
        } else if lookahead_iterator.next_state() != 0 {
          successor_state = lookahead_iterator.next_state()
          successor_child_index = (successor_child_index + 1) & 0x7F
        } else {
          continue
        }
        let successor = subgraph_node(
          successor_state, 0, successor_child_index, false,
        )
        let (found_index, _) = search_sorted_with(subgraph.nodes, n => {
          analysis_subgraph_node_compare(n, successor)
        })
        let mut node_index = found_index
        while node_index < subgraph.nodes.length() {
          let node = subgraph.nodes[node_index]
          node_index += 1
          if node.state != successor.state ||
            node.child_index != successor.child_index {
            break
          }
          // Use the subgraph to determine what alias and field will
          // eventually be applied to this child node.
          let alias = language.alias_at(node.production_id, child_index)
          let visible_symbol = if alias != 0 {
            alias
          } else if language.symbol_metadata[sym].visible {
            language.public_symbol_map[sym]
          } else {
            0
          }
          let mut field_id = parent_field_id
          if field_id == 0 {
            let (field_map, field_map_end) = language.field_map(
              node.production_id,
            )
            for m in field_map..<field_map_end {
              let map = language.field_map_entries[m]
              if !map.inherited && map.child_index == child_index {
                field_id = map.field_id
                break
              }
            }
          }
          // Create a new state that has advanced past this hypothetical
          // subtree.
          let next_state = state.copy()
          let mut top_index = next_state.top_index()
          next_state.stack[top_index] = {
            ..next_state.stack[top_index],
            child_index: successor.child_index,
            parse_state: successor.state,
            done: if node.done { true } else { next_state.stack[top_index].done },
          }
          // Determine if this hypothetical child node would match the current
          // step of the query pattern.
          let mut does_match = false
          if step.symbol == @language.ts_builtin_sym_error {
            // ERROR nodes can appear anywhere, so if the step is looking for
            // an ERROR node, consider it potentially matchable.
            does_match = true
          } else if visible_symbol != 0 {
            does_match = true
            if step.symbol == wildcard_symbol {
              if step.is_named && !language.symbol_metadata[visible_symbol].named {
                does_match = false
              }
            } else if step.symbol != visible_symbol {
              does_match = false
            }
            if step.field != 0 && step.field != field_id {
              does_match = false
            }
            if step.supertype_symbol != 0 &&
              !state.has_supertype(step.supertype_symbol) {
              does_match = false
            }
          } else if sym >= language.token_count {
            // If this child is hidden, then descend into it and walk through
            // its children. If the top entry of the stack is at the end of its
            // rule, then that entry can be replaced. Otherwise, push a new
            // entry onto the stack.
            if !next_state.stack[top_index].done {
              if next_state.depth + 1 >= max_analysis_state_depth {
                analysis.did_abort = true
                continue
              }
              next_state.depth += 1
              top_index = next_state.top_index()
            }
            next_state.stack[top_index] = {
              parse_state,
              parent_symbol: sym,
              child_index: 0,
              field_id: field_id & 0x7FFF,
              done: false,
            }
            if next_state.recursion_depth() > recursion_depth_limit {
              analysis_state_set_insert_sorted(analysis.deeper_states, next_state)
              continue
            }
          }
          // Pop from the stack when this state reached the end of its current
          // syntax node.
          while next_state.depth > 0 && next_state.stack[top_index].done {
            next_state.depth -= 1
            top_index = next_state.top_index()
          }
          // If this hypothetical child did match the current step of the
          // query pattern, then advance to the next step at the current depth.
          // This involves skipping over any descendant steps of the current
          // child.
          let mut next_step = step
          if does_match {
            for ;; {
              next_state.step_index += 1
              next_step = self.steps[next_state.step_index]
              if next_step.depth == pattern_done_marker ||
                next_step.depth <= step.depth {
                break
              }
            }
          } else if successor.state == parse_state {
            continue
          }
          for ;; {
            // Skip pass-through states. Although these states have
            // alternatives, they are only used to implement repetitions, and
            // query analysis does not need to process repetitions in order to
            // determine whether steps are possible and definite.
            if next_step.is_pass_through {
              next_state.step_index += 1
              next_step = self.steps[next_state.step_index]
              continue
            }
            // If the pattern is finished or hypothetical parent node is
            // complete, then record that matching can terminate at this step
            // of the pattern. Otherwise, add this state to the list of states
            // to process on the next iteration.
            if !next_step.is_dead_end {
              let did_finish_pattern = self.steps[next_state.step_index].depth !=
                step.depth
              if did_finish_pattern {
                insert_sorted_int(
                  analysis.finished_parent_symbols,
                  state.root_symbol,
                )
              } else if next_state.depth == 0 {
                insert_sorted_int(
                  analysis.final_step_indices,
                  next_state.step_index,
                )
              } else {
                analysis_state_set_insert_sorted(analysis.next_states, next_state)
              }
            }
            // If the state has advanced to a step with an alternative step,
            // then add another state at that alternative step. This process is
            // simpler than the process of actually matching a pattern during
            // query execution, because for the purposes of query analysis,
            // there is no need to process repetitions.
            if does_match &&
              next_step.alternative_index != none &&
              next_step.alternative_index > next_state.step_index {
              next_state.step_index = next_step.alternative_index
              next_step = self.steps[next_state.step_index]
            } else {
              break
            }
          }
        }
      }
      j += 1
    }
    let states = analysis.states
    analysis.states = analysis.next_states
    analysis.next_states = states
  }
}

///|
/// `ts_query__analyze_patterns`: returns `None` if all patterns are valid,
/// or the byte offset of an impossible pattern step.
fn Query::analyze_patterns(self : Query) -> UInt? {
  let language = self.language
  let non_rooted_pattern_start_steps : Array[Int] = []
  for i, pattern in self.pattern_map {
    if !pattern.is_rooted {
      let step = self.steps[pattern.step_index]
      if step.symbol != wildcard_symbol {
        non_rooted_pattern_start_steps.push(i)
      }
    }
  }
  // Walk forward through all of the steps in the query, computing some basic
  // information about each step. Mark all of the steps that contain captures,
  // and record the indices of all of the steps that have child steps.
  let parent_step_indices : Array[Int] = []
  for i in 0..<self.steps.length() {
    let step = self.steps[i]
    if step.depth == pattern_done_marker {
      step.parent_pattern_guaranteed = true
      step.root_pattern_guaranteed = true
      continue
    }
    let mut has_children = false
    let is_wildcard = step.symbol == wildcard_symbol
    step.contains_captures = step.capture_ids[0] != none
    for j in (i + 1)..<self.steps.length() {
      let next_step = self.steps[j]
      if next_step.depth == pattern_done_marker || next_step.depth <= step.depth {
        break
      }
      if next_step.capture_ids[0] != none {
        step.contains_captures = true
      }
      if !is_wildcard {
        next_step.root_pattern_guaranteed = true
        next_step.parent_pattern_guaranteed = true
      }
      has_children = true
    }
    if has_children {
      if !is_wildcard {
        parent_step_indices.push(i)
      } else if step.supertype_symbol != 0 &&
        language.abi_version >= @language.language_version_with_reserved_words {
        // Look at the child steps to see if any aren't valid subtypes for
        // this supertype.
        let subtypes = language.subtypes(step.supertype_symbol)
        for j in (i + 1)..<self.steps.length() {
          let child_step = self.steps[j]
          if child_step.depth == pattern_done_marker ||
            child_step.depth <= step.depth {
            break
          }
          if child_step.depth == step.depth + 1 &&
            child_step.symbol != wildcard_symbol {
            let is_valid_subtype = subtypes.iter().any(s => s == child_step.symbol)
            if !is_valid_subtype {
              for step_offset in self.step_offsets {
                if step_offset.step_index >= j {
                  return Some(step_offset.byte_offset)
                }
              }
            }
          }
        }
      }
    }
  }
  // For every parent symbol in the query, initialize an 'analysis subgraph'.
  // This subgraph lists all of the states in the parse table that are
  // directly involved in building subtrees for this symbol.
  //
  // In addition to the parent symbols in the query, construct subgraphs for
  // all of the hidden symbols in the grammar, because these might occur
  // within one of the parent nodes, such that their children appear to belong
  // to the parent.
  let subgraphs : Array[AnalysisSubgraph] = []
  let insert_subgraph = (symbol : Int) => {
    let (index, exists) = search_sorted_by(subgraphs, s => s.symbol, symbol)
    if !exists {
      subgraphs.insert(index, { symbol, start_states: [], nodes: [] })
    }
  }
  for parent_step_index in parent_step_indices {
    insert_subgraph(self.steps[parent_step_index].symbol)
  }
  for sym in (language.token_count & 0xFFFF)..<(language.symbol_count & 0xFFFF) {
    if !language.symbol_metadata_of(sym).visible {
      insert_subgraph(sym)
    }
  }
  // Scan the parse table to find the data needed to populate these
  // subgraphs. Collect three things during this scan:
  //   1) All of the parse states where one of these symbols can start.
  //   2) All of the parse states where one of these symbols can end, along
  //      with information about the node that would be created.
  //   3) A list of predecessor states for each state.
  let predecessor_map = StatePredecessorMap::new(language)
  for state in 1..<(language.state_count & 0xFFFF) {
    let lookahead_iterator = language.lookaheads(state)
    while lookahead_iterator.next() {
      let actions = lookahead_iterator.actions()
      if actions.length() > 0 {
        for action in actions {
          match action {
            Reduce(symbol~, child_count~, production_id~, ..) =>
              for alias in language.aliases_for_symbol(symbol) {
                let (subgraph_index, exists) = search_sorted_by(
                  subgraphs,
                  s => s.symbol,
                  alias,
                )
                if exists {
                  let subgraph = subgraphs[subgraph_index]
                  if subgraph.nodes.length() == 0 ||
                    subgraph.nodes[subgraph.nodes.length() - 1].state != state {
                    subgraph.nodes.push(
                      subgraph_node(state, production_id, child_count, true),
                    )
                  }
                }
              }
            Shift(state=next_state, extra=false, ..) =>
              predecessor_map.add(next_state, state)
            _ => ()
          }
        }
      } else if lookahead_iterator.next_state() != 0 {
        if lookahead_iterator.next_state() != state {
          predecessor_map.add(lookahead_iterator.next_state(), state)
        }
        if language.state_is_primary(state) {
          for alias in language.aliases_for_symbol(
            lookahead_iterator.current_symbol(),
          ) {
            let (subgraph_index, exists) = search_sorted_by(
              subgraphs,
              s => s.symbol,
              alias,
            )
            if exists {
              let subgraph = subgraphs[subgraph_index]
              if subgraph.start_states.length() == 0 ||
                subgraph.start_states[subgraph.start_states.length() - 1] !=
                state {
                subgraph.start_states.push(state)
              }
            }
          }
        }
      }
    }
  }
  // For each subgraph, compute the preceding states by walking backward from
  // the end states using the predecessor map.
  let mut i = 0
  while i < subgraphs.length() {
    let subgraph = subgraphs[i]
    if subgraph.nodes.length() == 0 {
      ignore(subgraphs.remove(i))
      continue
    }
    let next_nodes = subgraph.nodes.copy()
    while next_nodes.pop() is Some(node) {
      if node.child_index > 1 {
        for predecessor in predecessor_map.get(node.state) {
          let predecessor_node = subgraph_node(
            predecessor,
            node.production_id,
            node.child_index - 1,
            false,
          )
          let (index, exists) = search_sorted_with(subgraph.nodes, n => {
            analysis_subgraph_node_compare(n, predecessor_node)
          })
          if !exists {
            subgraph.nodes.insert(index, predecessor_node)
            next_nodes.push(predecessor_node)
          }
        }
      }
    }
    i += 1
  }
  // For each non-terminal pattern, determine if the pattern can successfully
  // match, and identify all of the possible children within the pattern
  // where matching could fail.
  let analysis = QueryAnalysis::new()
  for parent_step_index in parent_step_indices {
    let parent_depth = self.steps[parent_step_index].depth
    let parent_symbol = self.steps[parent_step_index].symbol
    if parent_symbol == @language.ts_builtin_sym_error {
      continue
    }
    // Find the subgraph that corresponds to this pattern's root symbol. If
    // the pattern's root symbol is a terminal, then return an error.
    let (subgraph_index, exists) = search_sorted_by(
      subgraphs,
      s => s.symbol,
      parent_symbol,
    )
    if !exists {
      let first_child_step_index = parent_step_index + 1
      let (j, _) = search_sorted_by(
        self.step_offsets,
        o => o.step_index,
        first_child_step_index,
      )
      return Some(self.step_offsets[j].byte_offset)
    }
    // Initialize an analysis state at every parse state in the table where
    // this parent symbol can occur.
    let subgraph = subgraphs[subgraph_index]
    analysis.states.clear()
    analysis.deeper_states.clear()
    for parse_state in subgraph.start_states {
      analysis_state_set_push(
        analysis.states,
        AnalysisState::new(
          parent_step_index + 1,
          { parse_state, parent_symbol, child_index: 0, field_id: 0, done: false },
          parent_symbol,
        ),
      )
    }
    analysis.did_abort = false
    self.perform_analysis(subgraphs, analysis)
    // If this pattern could not be fully analyzed, then every step should be
    // considered fallible.
    if analysis.did_abort {
      for j in (parent_step_index + 1)..<self.steps.length() {
        let step = self.steps[j]
        if step.depth <= parent_depth || step.depth == pattern_done_marker {
          break
        }
        if !step.is_dead_end {
          step.parent_pattern_guaranteed = false
          step.root_pattern_guaranteed = false
        }
      }
      continue
    }
    // If this pattern cannot match, store the pattern index so that it can
    // be returned to the caller.
    if analysis.finished_parent_symbols.length() == 0 {
      let impossible_step_index = if analysis.final_step_indices.length() > 0 {
        analysis.final_step_indices[analysis.final_step_indices.length() - 1]
      } else {
        // If there isn't a final step, then that means the parent step itself
        // is unreachable.
        parent_step_index
      }
      let (found, _) = search_sorted_by(
        self.step_offsets,
        o => o.step_index,
        impossible_step_index,
      )
      let j = if found >= self.step_offsets.length() {
        self.step_offsets.length() - 1
      } else {
        found
      }
      return Some(self.step_offsets[j].byte_offset)
    }
    // Mark as fallible any step where a match terminated. Later, this
    // property will be propagated to all of the step's predecessors.
    for final_step_index in analysis.final_step_indices {
      let step = self.steps[final_step_index]
      if step.depth != pattern_done_marker &&
        step.depth > parent_depth &&
        !step.is_dead_end {
        step.parent_pattern_guaranteed = false
        step.root_pattern_guaranteed = false
      }
    }
  }
  // Mark as indefinite any step with captures that are used in predicates.
  let predicate_capture_ids : Array[Int] = []
  for pattern in self.patterns {
    // Gather all of the captures that are used in predicates for this
    // pattern.
    predicate_capture_ids.clear()
    let start = pattern.predicate_steps.offset
    for j in start..<(start + pattern.predicate_steps.length) {
      let step = self.predicate_steps[j]
      if step.type_ == Capture {
        insert_sorted_int(predicate_capture_ids, step.value_id)
      }
    }
    // Find all of the steps that have these captures.
    let start = pattern.steps.offset
    for j in start..<(start + pattern.steps.length) {
      let step = self.steps[j]
      for k in 0..<max_step_capture_count {
        let capture_id = step.capture_ids[k]
        if capture_id == none {
          break
        }
        let (_, exists) = search_sorted_by(predicate_capture_ids, x => x, capture_id)
        if exists {
          step.root_pattern_guaranteed = false
          break
        }
      }
    }
  }
  // Propagate fallibility. If a pattern is fallible at a given step, then it
  // is fallible at all of its preceding steps.
  let mut done = self.steps.length() == 0
  while !done {
    done = true
    for i = self.steps.length() - 1; i > 0; i = i - 1 {
      let mut step = self.steps[i]
      if step.depth == pattern_done_marker {
        continue
      }
      // Determine if this step is definite or has definite alternatives.
      let mut parent_pattern_guaranteed = false
      for ;; {
        if step.root_pattern_guaranteed {
          parent_pattern_guaranteed = true
          break
        }
        if step.alternative_index == none || step.alternative_index < i {
          break
        }
        step = self.steps[step.alternative_index]
      }
      // If not, mark its predecessor as indefinite.
      if !parent_pattern_guaranteed {
        let prev_step = self.steps[i - 1]
        if !prev_step.is_dead_end &&
          prev_step.depth != pattern_done_marker &&
          prev_step.root_pattern_guaranteed {
          prev_step.root_pattern_guaranteed = false
          done = false
        }
      }
    }
  }
  // Determine which repetition symbols in this language have the possibility
  // of matching non-rooted patterns in this query. These repetition symbols
  // prevent certain optimizations with range restrictions.
  analysis.did_abort = false
  for pattern_entry_index in non_rooted_pattern_start_steps {
    let pattern_entry = self.pattern_map[pattern_entry_index]
    analysis.states.clear()
    analysis.deeper_states.clear()
    for subgraph in subgraphs {
      let metadata = language.symbol_metadata_of(subgraph.symbol)
      if metadata.visible || metadata.named {
        continue
      }
      for parse_state in subgraph.start_states {
        analysis_state_set_push(
          analysis.states,
          AnalysisState::new(
            pattern_entry.step_index,
            {
              parse_state,
              parent_symbol: subgraph.symbol,
              child_index: 0,
              field_id: 0,
              done: false,
            },
            subgraph.symbol,
          ),
        )
      }
    }
    self.perform_analysis(subgraphs, analysis)
    if analysis.finished_parent_symbols.length() > 0 {
      self.patterns[pattern_entry.pattern_index].is_non_local = true
    }
    for symbol in analysis.finished_parent_symbols {
      insert_sorted_int(self.repeat_symbols_with_rootless_patterns, symbol)
    }
  }
  None
}
