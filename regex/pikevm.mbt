// Breadth-first simulation of the NFA (a Pike VM without capture slots).
//
// Code point classes consume up to four bytes at once, so threads are kept
// in one sparse set per pending position; positions are processed in
// increasing order, which preserves lockstep semantics.

///|
let slot_count : Int32 = 5

///|
priv struct Sim {
  program : Program
  haystack : BytesView
  /// The consuming states pending at each position, by `position % 5`.
  lists : FixedArray[Array[Int32]]
  /// `stamps[slot][state] == position` iff the state is in that set.
  stamps : FixedArray[FixedArray[Int32]]
  stack : Array[Int32]
}

///|
/// Add `state` and its epsilon closure at `pos`. Returns true when the
/// closure reaches the match state.
fn Sim::add(self : Sim, pos : Int32, state : Int32) -> Bool {
  let slot = pos % slot_count
  let stamps = self.stamps[slot]
  let list = self.lists[slot]
  self.stack.push(state)
  while self.stack.pop() is Some(s) {
    if stamps[s] == pos {
      continue
    }
    stamps[s] = pos
    match self.program.states[s] {
      Match => {
        self.stack.clear()
        return true
      }
      Fail => ()
      Split(targets) =>
        for i = targets.length() - 1; i >= 0; i = i - 1 {
          self.stack.push(targets[i])
        }
      Look(look, next) =>
        if look_matches(look, self.haystack, pos) {
          self.stack.push(next)
        }
      ByteRange(_) | ByteClass(_) | CodePointClass(_) => list.push(s)
    }
  }
  false
}

///|
/// The end of a match of a search of `haystack` starting at `from` (whose
/// assertions see all of `haystack`), or -1 if there is none. With `any`,
/// this is the end of the first match found; otherwise it is the smallest
/// match end (the offset of an earliest search, `Input::earliest`).
fn Program::earliest_end(
  self : Program,
  haystack : BytesView,
  from : Int32,
  any~ : Bool,
) -> Int32 {
  let n = self.states.length()
  let sim : Sim = {
    program: self,
    haystack,
    lists: FixedArray::makei(slot_count, _ => []),
    stamps: FixedArray::makei(slot_count, _ => FixedArray::make(n, -1)),
    stack: [],
  }
  let len = haystack.length()
  // The smallest match end found so far. A match ending at `end` is found
  // while processing a position before `end` (a code point class reaches
  // several bytes ahead) or when a thread starts at `end`, so once `pos`
  // reaches `best`, no smaller end can be found.
  let mut best = -1
  // Record a match ending at `end`; true when the search is over.
  let found = (end : Int32) => {
    if best < 0 || end < best {
      best = end
    }
    any
  }
  for pos in from..<=len {
    if best >= 0 && best <= pos {
      return best
    }
    if pos == from || !self.anchored {
      if sim.add(pos, self.start) && found(pos) {
        return best
      }
    }
    let list = sim.lists[pos % slot_count]
    if self.anchored && list.length() == 0 {
      // No thread survives and none can start later; the pending lists of
      // later positions are still drained below.
      let mut alive = false
      for slot in sim.lists {
        if slot.length() > 0 {
          alive = true
          break
        }
      }
      if !alive {
        return best
      }
    }
    for i = 0; i < list.length(); i = i + 1 {
      match self.states[list[i]] {
        ByteRange(lo, hi, next) =>
          if pos < len {
            let b = haystack[pos].to_int()
            if b >= lo && b <= hi && sim.add(pos + 1, next) && found(pos + 1) {
              return best
            }
          }
        ByteClass(ranges, next) =>
          if pos < len &&
            ranges_contain(ranges, haystack[pos].to_int()) &&
            sim.add(pos + 1, next) &&
            found(pos + 1) {
            return best
          }
        CodePointClass(ranges, next) => {
          let (cp, width) = decode_utf8(haystack, pos)
          if cp >= 0 &&
            ranges_contain(ranges, cp) &&
            sim.add(pos + width, next) &&
            found(pos + width) {
            return best
          }
        }
        _ => ()
      }
    }
    list.clear()
  }
  best
}

///|
/// Whether `value` lies in one of the sorted, flattened inclusive ranges.
fn ranges_contain(ranges : FixedArray[Int32], value : Int32) -> Bool {
  let mut lo = 0
  let mut hi = ranges.length() / 2
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if value < ranges[2 * mid] {
      hi = mid
    } else if value > ranges[2 * mid + 1] {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Decode the well-formed UTF-8 scalar value starting at `pos`, returning
/// `(code point, width)`, or `(-1, 0)` when there is none (end of input,
/// a stray or invalid byte, an overlong form, a surrogate or a value above
/// U+10FFFF).
fn decode_utf8(bytes : BytesView, pos : Int32) -> (Int32, Int32) {
  let len = bytes.length()
  if pos >= len {
    return (-1, 0)
  }
  let b0 = bytes[pos].to_int()
  if b0 < 0x80 {
    return (b0, 1)
  }
  let (width, init, min) = if b0 >= 0xC2 && b0 <= 0xDF {
    (2, b0 & 0x1F, 0x80)
  } else if b0 >= 0xE0 && b0 <= 0xEF {
    (3, b0 & 0x0F, 0x800)
  } else if b0 >= 0xF0 && b0 <= 0xF4 {
    (4, b0 & 0x07, 0x10000)
  } else {
    return (-1, 0)
  }
  if pos + width > len {
    return (-1, 0)
  }
  let mut cp = init
  for i in 1..<width {
    let b = bytes[pos + i].to_int()
    if (b & 0xC0) != 0x80 {
      return (-1, 0)
    }
    cp = (cp << 6) | (b & 0x3F)
  }
  if cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
    return (-1, 0)
  }
  (cp, width)
}
