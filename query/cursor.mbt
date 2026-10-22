///|
/// A lazy depth-first query execution. Work and cancellation limits cover the
/// whole cursor lifetime; stopping iteration avoids visiting remaining nodes.
pub struct Cursor {
  priv query : Query
  priv source : Bytes
  priv nodes : Array[(@ts.Node, Int32)]
  priv mut pending : Array[Match]
  priv mut pending_index : Int32
  priv budget : Budget
  priv start_byte : Int32
  priv end_byte : Int32
  priv start_point : @ts.Point?
  priv end_point : @ts.Point?
  priv max_depth : Int32
  priv max_matches : Int32
  priv mut match_count : Int32
  priv property : (String, String?, @ts.Node?) -> Bool
  priv predicate : ((String, Array[Argument], Array[Capture], Bytes) -> Bool)?
}

///|
pub fn Query::cursor(
  self : Query,
  root : @ts.Node,
  source : Bytes,
  start_byte~ : Int32 = 0,
  end_byte~ : Int32 = 2147483647,
  start_point? : @ts.Point,
  end_point? : @ts.Point,
  max_start_depth~ : Int32 = 2147483647,
  max_steps~ : Int32 = 100000,
  max_matches~ : Int32 = 10000,
  cancelled~ : () -> Bool = () => false,
  property~ : (String, String?, @ts.Node?) -> Bool = (_, _, _) => false,
  predicate? : (String, Array[Argument], Array[Capture], Bytes) -> Bool,
) -> Cursor {
  {
    query: self,
    source,
    nodes: [(root, 0)],
    pending: [],
    pending_index: 0,
    budget: { steps: 0, limit: max_steps, cancelled, },
    start_byte,
    end_byte,
    start_point,
    end_point,
    max_depth: max_start_depth,
    max_matches,
    match_count: 0,
    property,
    predicate,
  }
}

///|
pub fn Cursor::next_match(self : Cursor) -> Match? raise QueryError {
  self.budget.tick()
  for ;; {
    if self.pending_index < self.pending.length() {
      if self.match_count >= self.max_matches {
        raise MatchLimit
      }
      let matched = self.pending[self.pending_index]
      self.pending_index += 1
      self.match_count += 1
      return Some(matched)
    }
    self.pending = []
    self.pending_index = 0
    guard self.nodes.pop() is Some((node, depth)) else { return None }
    self.budget.tick()
    if node.end_byte() < self.start_byte ||
      node.start_byte() >= self.end_byte ||
      (self.start_point is Some(point) && node.end_position() < point) ||
      (self.end_point is Some(point) && node.start_position() >= point) {
      continue
    }
    if depth < self.max_depth {
      for i = node.child_count() - 1; i >= 0; i = i - 1 {
        self.nodes.push((node.child(i).unwrap(), depth + 1))
      }
    }
    for pattern_index, pattern in self.query.patterns {
      for captures in match_pattern(pattern.pattern, node, self.budget) {
        if !predicates_match(
            pattern.predicates,
            captures,
            self.source,
            self.budget,
            self.property,
            self.predicate,
          ) {
          continue
        }
        let properties : Map[String, String] = Map([])
        for predicate in pattern.predicates {
          if predicate.name == "#set!" && predicate.args[0] is Text(key) {
            properties[key] = match predicate.args.get(1) {
              Some(Text(value)) => value
              _ => ""
            }
          }
        }
        let directives = pattern.predicates
          .filter(p => p.name.has_suffix("!") && p.name != "#set!")
          .map(p => Directive::{ name: p.name, args: p.args.copy(), })
        self.pending.push({ pattern_index, captures, properties, directives, })
      }
    }
  }
}
