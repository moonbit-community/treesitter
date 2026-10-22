///|
/// Number of times a capture can occur in one match of a query pattern.
pub(all) enum Quantifier {
  Zero
  ZeroOrOne
  ZeroOrMore
  One
  OneOrMore
} derive(Eq, Debug)

///|
pub extend Quantifier with Eq::{equal, not_equal}

///|
pub extend Quantifier with Debug::{to_repr}

///|
// Bounds are saturated: a minimum of 1 means positive, and a maximum of 2
// means potentially multiple. This implements upstream's add/join/mul algebra.
fn capture_bounds(pattern : Pattern, name : String) -> (Int32, Int32) {
  match pattern {
    Capture(inner, capture) => {
      let (min, max) = capture_bounds(inner, name)
      if capture == name {
        (1, Int32::min(2, max + 1))
      } else {
        (min, max)
      }
    }
    Either(alternatives) => {
      let mut min = 1
      let mut max = 0
      for alternative in alternatives {
        let (a, b) = capture_bounds(alternative, name)
        min = Int32::min(min, a)
        max = Int32::max(max, b)
      }
      (min, max)
    }
    Node(node) => child_capture_bounds(node.children, name)
    Group(children, _) => child_capture_bounds(children, name)
  }
}

///|
fn child_capture_bounds(
  children : Array[Child],
  name : String,
) -> (Int32, Int32) {
  let mut min = 0
  let mut max = 0
  for child in children {
    let (a, b) = capture_bounds(child.pattern, name)
    min = Int32::min(1, min + a * child.min)
    max = Int32::min(2, max + b * child.max.unwrap_or(2))
  }
  (min, max)
}

///|
/// Inspect a capture by its index in `capture_names`. Returns None for an invalid
/// pattern or capture index; Zero means the capture belongs to another pattern.
/// Disabling a capture or pattern does not change the compiled metadata.
pub fn Query::capture_quantifier(
  self : Query,
  pattern_index : Int32,
  capture_index : Int32,
) -> Quantifier? {
  guard self.patterns.get(pattern_index) is Some(pattern) else { return None }
  guard self.capture_names.get(capture_index) is Some(name) else { return None }
  Some(
    match capture_bounds(pattern.pattern, name) {
      (_, 0) => Zero
      (0, 1) => ZeroOrOne
      (0, _) => ZeroOrMore
      (_, 1) => One
      _ => OneOrMore
    },
  )
}

///|
/// Inspect predicates and directives in source order, including custom names.
/// The returned arrays are independent of the compiled query.
pub fn Query::predicates(
  self : Query,
  pattern_index : Int32,
) -> Array[Directive]? {
  self.patterns
  .get(pattern_index)
  .map(pattern => {
    pattern.predicates.map(p => { name: p.name, args: p.args.copy(), })
  })
}
