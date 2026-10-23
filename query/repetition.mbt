///|
// A required, unanchored final child can be matched once and shared by every
// stop of the preceding repetition. Rescanning the same suffix at each stop
// makes an uncaptured prefix quadratic even when it has only one completion.
fn terminal_followers(
  children : Array[Child],
  pi : Int32,
  trailing_anchor : Bool,
  parent : @ts.Node,
  from : Int32,
  budget : Budget,
) -> Array[(Int32, Completion, Int32)]? raise QueryError {
  guard !trailing_anchor && pi + 2 == children.length() else { return None }
  let spec = children[pi + 1]
  guard spec.min == 1 &&
    spec.max == Some(1) &&
    !spec.anchor &&
    !pattern_nullable(spec.pattern) &&
    pattern_has_captures(spec.pattern) else {
    return None
  }
  let matches = []
  for index in from..<parent.child_count() {
    budget.tick()
    if spec.field is None || spec.field == parent.field_name_for_child(index) {
      for (completed, after) in match_at(spec.pattern, parent, index, budget) {
        matches.push((index, completed, after))
      }
    }
  }
  Some(matches)
}
