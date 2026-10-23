///|
// Start exactly at this sibling, then extend a quantified root through adjacent
// siblings. Each alternative retains its own captures; only maximal runs survive.
fn match_root_run(
  pattern : Pattern,
  parent : @ts.Node,
  index : Int32,
  budget : Budget,
  node_in_range~ : Bool = true,
) -> Array[(Array[Capture], Int32)] raise QueryError {
  let result = []
  let entry = root_entry_pattern(pattern, include_rooted=node_in_range)
  let continuations_by_index : Map[Int32, Array[(Completion, Int32)]] = Map([])
  for first in match_at(entry, parent, index, budget, retain_stops=true) {
    if first.1 <= index {
      continue
    }
    let pending = [(first.0.captures, first.1, 1)]
    let mut best_count = 0
    let best = []
    let frontiers : Map[Int32, Array[(Array[Capture], Int32)]] = Map([])
    while pending.pop() is Some((captures, next, count)) {
      budget.tick()
      if !retain_root_path(frontiers, next, captures, count, budget) {
        continue
      }
      if count > best_count {
        best_count = count
        best.clear()
      }
      if count == best_count {
        best.push((captures, next))
      }
      if next < parent.child_count() {
        let continuations = match continuations_by_index.get(next) {
          Some(matches) => matches
          None => {
            let matches = match_at(
              pattern,
              parent,
              next,
              budget,
              retain_stops=true,
            )
            continuations_by_index[next] = matches
            matches
          }
        }
        for i = continuations.length() - 1; i >= 0; i = i - 1 {
          let (additional, after) = continuations[i]
          if after > next {
            pending.push((captures + additional.captures, after, count + 1))
          }
        }
      }
    }
    result.append(best)
  }
  let seen : Map[(Int32, String), Unit] = Map([])
  result.filter(run => {
    let key = (run.1, capture_key(run.0))
    if seen.contains(key) {
      false
    } else {
      seen[key] = ()
      true
    }
  })
}

///|
fn capture_key(captures : Array[Capture]) -> String {
  captures.map(c => "\{c.name.length()}:\{c.name}:\{c.node.id()};").join("")
}

///|
// At the execution root there is no sibling list. Group alternatives are
// entered later through its children, not by matching against those children
// here as if the parent itself were a group repetition.
fn root_node_entries(pattern : Pattern) -> Pattern {
  match pattern {
    Group(_, _) => Either([])
    Either(items) => Either(items.map(root_node_entries))
    Capture(inner, name) => Capture(root_node_entries(inner), name)
    Node(_) => pattern
  }
}

///|
fn root_is_group(pattern : Pattern) -> Bool {
  match pattern {
    Capture(inner, _) => root_is_group(inner)
    Group(_, _) => true
    _ => false
  }
}

///|
// Root alternatives enter through the pattern map in reverse source order;
// subsequent alternatives inside an active match retain source order.
fn root_entry_pattern(
  pattern : Pattern,
  include_rooted~ : Bool = true,
) -> Pattern {
  match pattern {
    Capture(inner, name) =>
      Capture(root_entry_pattern(inner, include_rooted~), name)
    Either(items) =>
      if include_rooted {
        Either(items.rev())
      } else {
        // Every branch except the final one ends at an alternation jump.
        // Upstream marks those entry points as rooted even when the enclosing
        // pattern repeats. Only the final branch can start outside the range.
        Either(
          items
          .last()
          .map(p => [root_entry_pattern(p, include_rooted=false)])
          .unwrap_or([]),
        )
      }
    _ => pattern
  }
}

///|
fn match_root_at(
  pattern : Pattern,
  parent : @ts.Node,
  index : Int32,
  budget : Budget,
) -> Array[(Array[Capture], Int32)] raise QueryError {
  match_at(root_entry_pattern(pattern), parent, index, budget).map(m => {
    (m.0.captures, m.1)
  })
}

///|
fn root_delayed(pattern : Pattern) -> Bool {
  match pattern {
    Capture(inner, _) => root_delayed(inner)
    Group(children, _) =>
      children
      .last()
      .map(c => c.max is None || root_delayed(c.pattern))
      .unwrap_or(false)
    _ => false
  }
}

///|
fn captures_contain(outer : Array[Capture], inner : Array[Capture]) -> Bool {
  let counts : Map[(String, Int32), Int32] = Map([])
  for capture in outer {
    let key = (capture.name, capture.node.id())
    counts[key] = counts.get(key).unwrap_or(0) + 1
  }
  for capture in inner {
    let key = (capture.name, capture.node.id())
    let count = counts.get(key).unwrap_or(0)
    if count == 0 {
      return false
    }
    counts[key] = count - 1
  }
  true
}

///|
// A completed repetition can retain a partial following group. Its completed
// captures remain pending through the matched prefix of that group.
fn root_prefix_end(
  pattern : Pattern,
  parent : @ts.Node,
  index : Int32,
  budget : Budget,
) -> Int32 raise QueryError {
  if index >= parent.child_count() {
    return index
  }
  match pattern {
    Capture(inner, _) => root_prefix_end(inner, parent, index, budget)
    Group(children, _) => {
      let mut end = index
      for count in 1..<=children.length() {
        let prefixes = match_children(
          children[:count].to_owned(),
          false,
          parent,
          0,
          index,
          Completion::at(parent),
          budget,
          strict_start=true,
        )
        if prefixes.is_empty() {
          break
        }
        end = prefixes.fold(init=end, (a, b) => Int32::max(a, b.1))
      }
      end
    }
    _ => index
  }
}

///|
fn match_root_groups(
  pattern : QueryPattern,
  parent : @ts.Node,
  budget : Budget,
) -> Array[(Array[Capture], Int32)] raise QueryError {
  let candidates = []
  for index in 0..<parent.child_count() {
    let matches = if pattern.max is None {
      match_root_run(pattern.pattern, parent, index, budget)
    } else {
      match_root_at(pattern.pattern, parent, index, budget)
    }
    for (captures, after) in matches {
      if after > index {
        let finish = if pattern.max is None {
          root_prefix_end(pattern.pattern, parent, after, budget)
        } else {
          after
        }
        candidates.push((captures, finish))
      }
    }
  }
  let results = []
  if !candidates.is_empty() && candidates.all(c => c.0.is_empty()) {
    return [([], candidates.fold(init=0, (end, c) => Int32::max(end, c.1)))]
  }
  for i, candidate in candidates {
    let mut contained = false
    for j, other in candidates {
      budget.tick()
      if j != i &&
        captures_contain(other.0, candidate.0) &&
        (other.0.length() > candidate.0.length() || j < i) {
        contained = true
        break
      }
    }
    if !contained {
      results.push(candidate)
    }
  }
  results
}
