///|
priv enum WalkEvent {
  Enter(@ts.Node, Int32, @ts.Node?, Int32)
  Leave(@ts.Node)
}

///|
fn WalkEvent::node(self : WalkEvent) -> @ts.Node {
  match self {
    Enter(node, _, _, _) | Leave(node) => node
  }
}

///|
/// A lazy depth-first query execution. Work and cancellation limits cover the
/// whole cursor lifetime; stopping iteration avoids visiting remaining nodes.
pub struct Cursor {
  priv query : Query
  priv source : Bytes
  priv nodes : Array[WalkEvent]
  priv ready : Map[Int32, Array[(Int32, Array[Capture])]]
  priv deferred : Map[Int32, Array[(Int32, Array[Capture])]]
  priv root_runs : Map[(Int32, Int32), Int32]
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
  priv mut next_id : Int32
  priv property : (String, String?, @ts.Node?) -> Bool
  priv predicate : ((String, Array[Argument], Array[Capture], Bytes) -> Bool)?
}

///|
/// Execute lazily within intersecting byte/point ranges. Optional containing
/// ranges additionally require every matched node (even an uncaptured root)
/// to lie fully inside them. A zero end byte or point denotes an unbounded end.
pub fn Query::cursor(
  self : Query,
  root : @ts.Node,
  source : Bytes,
  start_byte~ : Int32 = 0,
  end_byte~ : Int32 = 2147483647,
  containing_byte_range? : (Int32, Int32),
  containing_point_range? : (@ts.Point, @ts.Point),
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
    nodes: [Enter(root, 0, None, 0)],
    ready: Map([]),
    deferred: Map([]),
    root_runs: Map([]),
    pending: [],
    pending_index: 0,
    budget: {
      steps: 0,
      limit: max_steps,
      cancelled,
      containing_byte_range: containing_byte_range.map(range => {
        (range.0, if range.1 == 0 { 2147483647 } else { range.1 })
      }),
      containing_point_range: containing_point_range.map(range => {
        (
          range.0,
          if range.1 == { row: 0, column: 0, } {
            { row: 2147483647, column: 2147483647, }
          } else {
            range.1
          },
        )
      }),
    },
    start_byte,
    end_byte: if end_byte == 0 {
      2147483647
    } else {
      end_byte
    },
    start_point,
    end_point: if end_point == Some({ row: 0, column: 0, }) {
      None
    } else {
      end_point
    },
    max_depth: max_start_depth,
    max_matches,
    match_count: 0,
    next_id: 0,
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
    let (node, depth, parent, index) = match self.nodes.pop() {
      None => return None
      Some(Leave(node)) => {
        for pattern_index in 0..<self.query.patterns.length() {
          self.root_runs.remove((pattern_index, node.id()))
        }
        if self.deferred.get(node.id()) is Some(matches) {
          self.deferred.remove(node.id())
          for (pattern_index, captures) in matches {
            self.enqueue(pattern_index, captures)
          }
        }
        continue
      }
      Some(Enter(node, depth, parent, index)) => (node, depth, parent, index)
    }
    self.budget.tick()
    self.nodes.push(Leave(node))
    let parent_in_range = parent.map(p => self.intersects(p)).unwrap_or(true)
    let node_in_range = parent_in_range && self.intersects(node)
    if !node_in_range &&
      !parent_in_range &&
      self.ready.is_empty() &&
      self.deferred.is_empty() {
      continue
    }
    for pattern_index, pattern in self.query.patterns {
      if self.query.disabled_patterns.contains(pattern_index) {
        continue
      }
      if self.ready.get(node.id()) is Some(matches) {
        for (index, captures) in matches {
          if index == pattern_index {
            self.enqueue(pattern_index, captures)
          }
        }
      }
      if depth > self.max_depth {
        continue
      }
      if (pattern.max is None || pattern.min == 0) &&
        root_is_group(pattern.pattern) {
        if node_in_range && depth < self.max_depth {
          for (captures, after) in match_root_groups(pattern, node, self.budget) {
            let last = node.child(after - 1).unwrap().id()
            let target = if pattern.max is None ||
              root_delayed(pattern.pattern) ||
              captures.is_empty() {
              self.deferred
            } else {
              self.ready
            }
            if !target.contains(last) {
              target[last] = []
            }
            target[last].push((pattern_index, captures))
          }
        }
      } else if pattern.max is None {
        if !parent_in_range {
          continue
        }
        let matches = if parent is Some(parent) {
          let key = (pattern_index, parent.id())
          if index < self.root_runs.get(key).unwrap_or(0) {
            []
          } else {
            let runs = match_root_run(
              pattern.pattern,
              parent,
              index,
              self.budget,
              node_in_range~,
            )
            for (_, after) in runs {
              self.root_runs[key] = Int32::max(
                self.root_runs.get(key).unwrap_or(0),
                after,
              )
            }
            runs.map(run => (run.0, parent.child(run.1 - 1).unwrap().id()))
          }
        } else {
          match_pattern(root_entry_pattern(pattern.pattern), node, self.budget).map(c => {
              (c.captures, node.id())
            },
          )
        }
        for (captures, last) in matches {
          if parent is None && node.child_count() == 0 {
            self.enqueue(pattern_index, captures)
            if pattern.min == 0 {
              // Upstream reports both captured paths for zero-or-more at a
              // leaf execution root, before its separate empty match.
              self.enqueue(pattern_index, captures)
            }
            continue
          }
          if !self.deferred.contains(last) {
            self.deferred[last] = []
          }
          self.deferred[last].push((pattern_index, captures))
        }
      } else {
        if !node_in_range {
          continue
        }
        let matches = match_pattern(
          root_entry_pattern(pattern.pattern),
          node,
          self.budget,
        )
        for completed in matches {
          let finish = completed.finish.id()
          if finish == node.id() && !completed.delayed {
            self.enqueue(pattern_index, completed.captures)
          } else {
            let target = if completed.delayed {
              self.deferred
            } else {
              self.ready
            }
            if !target.contains(finish) {
              target[finish] = []
            }
            target[finish].push((pattern_index, completed.captures))
          }
        }
      }
    }
    self.ready.remove(node.id())
    // Zero-occurrence matches finish after the node's concrete matches, even
    // when the optional pattern also matched this node.
    for pattern_index, pattern in self.query.patterns {
      if depth <= self.max_depth &&
        pattern.min == 0 &&
        self.budget.contains(node) &&
        parent_in_range &&
        (
          pattern.max is None ||
          root_is_group(pattern.pattern) ||
          node.end_byte() > self.start_byte ||
          (
            node.start_byte() == node.end_byte() &&
            node.end_byte() == self.start_byte
          )
        ) &&
        !self.query.disabled_patterns.contains(pattern_index) {
        self.enqueue(pattern_index, [])
      }
    }
    if depth < self.max_depth ||
      !self.ready.is_empty() ||
      !self.deferred.is_empty() {
      for i = node.child_count() - 1; i >= 0; i = i - 1 {
        self.nodes.push(Enter(node.child(i).unwrap(), depth + 1, Some(node), i))
      }
    }
  }
}

///|
fn Cursor::enqueue(
  self : Cursor,
  pattern_index : Int32,
  captures : Array[Capture],
) -> Unit raise QueryError {
  if self.query.disabled_patterns.contains(pattern_index) {
    return
  }
  let pattern = self.query.patterns[pattern_index]

  if !predicates_match(
      pattern.predicates,
      captures,
      self.source,
      self.budget,
      self.property,
      self.predicate,
    ) {
    return
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
  self.pending.push({
    id: self.next_id,
    pattern_index,
    captures: captures.filter(c => {
      !self.query.disabled_captures.contains(c.name)
    }),
    properties,
    directives,
  })
  self.next_id += 1
}

///|
fn Cursor::intersects(self : Cursor, node : @ts.Node) -> Bool {
  let empty = node.start_byte() == node.end_byte()
  (
    node.end_byte() > self.start_byte ||
    (empty && node.end_byte() == self.start_byte)
  ) &&
  node.start_byte() < self.end_byte &&
  self.start_point
  .map(point => {
    node.end_position() > point || (empty && node.end_position() == point)
  })
  .unwrap_or(true) &&
  self.end_point.map(point => node.start_position() < point).unwrap_or(true)
}
