///|
// Equivalent ways to partition a sibling sequence must not expand repeatedly.
// At the same continuation position, a path with at least as many repetitions
// and a superset of captures dominates the shorter path. Distinct capture
// alternatives remain separate. Charge comparisons to the cursor work budget.
fn retain_root_path(
  frontiers : Map[Int32, Array[(Array[Capture], Int32)]],
  next : Int32,
  captures : Array[Capture],
  count : Int32,
  budget : Budget,
) -> Bool raise QueryError {
  let paths = frontiers.get(next).unwrap_or([])
  for (existing, repetitions) in paths {
    budget.tick()
    if repetitions >= count && captures_include_sequence(existing, captures) {
      return false
    }
  }
  let retained = []
  for (existing, repetitions) in paths {
    budget.tick()
    if count < repetitions || !captures_include_sequence(captures, existing) {
      retained.push((existing, repetitions))
    }
  }
  retained.push((captures, count))
  frontiers[next] = retained
  true
}

///|
// Align captures in depth-first node order, as the upstream cursor does.
// Different names on the same node are distinct paths; do not skip one name
// to find a later name on that node, even if the capture multisets overlap.
fn captures_include_sequence(
  outer : Array[Capture],
  inner : Array[Capture],
) -> Bool {
  let mut index = 0
  for capture in outer {
    guard inner.get(index) is Some(wanted) else { return true }
    if capture.name == wanted.name && capture.node.id() == wanted.node.id() {
      index += 1
    } else if capture.node.start_byte() < wanted.node.start_byte() ||
      (
        capture.node.start_byte() == wanted.node.start_byte() &&
        capture.node.end_byte() > wanted.node.end_byte()
      ) {
      continue
    } else {
      return false
    }
  }
  index == inner.length()
}
