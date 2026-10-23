///|
// A capture following a group belongs to its possible first query steps.
// Quantified steps keep the capture on every repetition, and nullable prefixes
// also expose the following step as an entry. Groups themselves are not nodes.
fn capture_entries(pattern : Pattern, name : String) -> Pattern {
  match pattern {
    Either(items) => Either(items.map(item => capture_entries(item, name)))
    Group(children, trailing) => {
      let children = children.copy()
      for i in 0..<children.length() {
        let child = children[i]
        children[i] = {
          ..child,
          pattern: capture_entries(child.pattern, name),
        }
        if child.min > 0 && !pattern_nullable(child.pattern) {
          break
        }
      }
      Group(children, trailing)
    }
    _ => Capture(pattern, name)
  }
}

///|
fn pattern_nullable(pattern : Pattern) -> Bool {
  match pattern {
    Capture(inner, _) => pattern_nullable(inner)
    Either(items) => items.any(pattern_nullable)
    Group(children, _) =>
      children.all(child => child.min == 0 || pattern_nullable(child.pattern))
    Node(_) => false
  }
}
