///|
// Child alternatives start in source order. A capture on their shared parent
// gives them the same first-capture position, preserving this order when a
// repeated path and another branch finish on the same traversal event.
fn compare_branch_order(a : Array[Int32], b : Array[Int32]) -> Int32 {
  for i in 0..<Int32::min(a.length(), b.length()) {
    let order = a[i].compare(b[i])
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}

///|
// A sibling group has a fresh root at each sibling. Only co-completing paths
// compete for longest captures; separate runs may each emit an empty match.
fn maximal_group_captures(
  candidates : Array[Completion],
  budget : Budget,
) -> Array[Completion] raise QueryError {
  let events : Map[(Int32, Bool), Array[Completion]] = Map([])
  for candidate in candidates {
    budget.tick()
    let key = (candidate.finish.id(), candidate.delayed)
    if !events.contains(key) {
      events[key] = []
    }
    events[key].push(candidate)
  }
  let result = []
  for _, candidates in events {
    result.append(maximal_captures(candidates, budget))
  }
  result
}
