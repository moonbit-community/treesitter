///|
/// Captures in source order. The cursor advances the match traversal only until
/// no unseen match can precede the next capture. Each result retains its match
/// and capture index so predicate/directive metadata remains available.
pub struct CaptureCursor {
  priv cursor : Cursor
  priv pending : Array[(Match, Int32)]
  priv mut exhausted : Bool
}

///|
pub fn Query::capture_cursor(
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
) -> CaptureCursor {
  {
    cursor: self.cursor(
      root,
      source,
      start_byte~,
      end_byte~,
      start_point?,
      end_point?,
      max_start_depth~,
      max_steps~,
      max_matches~,
      cancelled~,
      property~,
      predicate?,
    ),
    pending: [],
    exhausted: false,
  }
}

///|
fn capture_order(a : (Match, Int32), b : (Match, Int32)) -> Int32 {
  let left = a.0.captures[a.1].node
  let right = b.0.captures[b.1].node
  let start = left.start_byte().compare(right.start_byte())
  if start != 0 {
    return start
  }
  let end = right.end_byte().compare(left.end_byte())
  if end != 0 {
    return end
  }
  let pattern = a.0.pattern_index.compare(b.0.pattern_index)
  if pattern != 0 {
    return pattern
  }
  a.1.compare(b.1)
}

///|
pub fn CaptureCursor::next_capture(
  self : CaptureCursor,
) -> (Match, Int32)? raise QueryError {
  self.cursor.budget.tick()
  for ;; {
    if !self.pending.is_empty() {
      self.pending.sort_by(capture_order)
      let start = self.pending[0].0.captures[self.pending[0].1].node.start_byte()
      let pending_matches = self.cursor.pending_index <
        self.cursor.pending.length()
      let remaining_before = self.cursor.nodes.last() is Some((node, _)) &&
        node.start_byte() <= start
      if self.exhausted || (!pending_matches && !remaining_before) {
        return Some(self.pending.remove(0))
      }
    } else if self.exhausted {
      return None
    }
    match self.cursor.next_match() {
      Some(matched) =>
        for index in 0..<matched.captures.length() {
          let node = matched.captures[index].node
          if node.end_byte() < self.cursor.start_byte ||
            node.start_byte() >= self.cursor.end_byte ||
            (
              self.cursor.start_point is Some(point) &&
              node.end_position() < point
            ) ||
            (
              self.cursor.end_point is Some(point) &&
              node.start_position() >= point
            ) {
            continue
          }
          self.pending.push((matched, index))
        }
      None => self.exhausted = true
    }
  }
}
