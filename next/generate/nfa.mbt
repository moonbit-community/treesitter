// Port of tree-sitter crates/generate/src/nfa.rs.

///|
/// A half-open range of code points `[start, end)`.
pub(all) struct CharRange {
  start : Int
  end : Int
} derive(Eq, Hash, Debug)

///|
/// A set of characters represented as sorted, disjoint, non-adjacent ranges.
pub struct CharacterSet {
  priv ranges : Array[CharRange]
} derive(Eq, Hash)

///|
pub let char_set_end : Int = 0x110000

///|
/// A state in an NFA representing a regular grammar.
pub(all) enum NfaState {
  Advance(chars~ : CharacterSet, state_id~ : Int, is_sep~ : Bool, precedence~ : Int)
  Split(Int, Int)
  Accept(variable_index~ : Int, precedence~ : Int)
} derive(Eq, Debug)

///|
pub(all) struct Nfa {
  states : Array[NfaState]
} derive(Eq, Debug)

///|
pub(all) struct NfaTransition {
  characters : CharacterSet
  is_separator : Bool
  precedence : Int
  states : Array[Int]
} derive(Eq, Debug)

///|
/// Rewrites a set's ranges as they're read in order: once finished, the ranges
/// that were read are replaced by the ones that were kept.
priv struct RangeRewriter {
  ranges : Array[CharRange]
  mut kept : Int
  mut read : Int
}

///|
fn RangeRewriter::new(ranges : Array[CharRange], start : Int) -> RangeRewriter {
  { ranges, kept: start, read: start }
}

///|
fn RangeRewriter::next(self : RangeRewriter) -> CharRange? {
  match self.ranges.get(self.read) {
    Some(range) => {
      self.read += 1
      Some(range)
    }
    None => None
  }
}

///|
fn RangeRewriter::keep(self : RangeRewriter, range : CharRange) -> Unit {
  if self.kept < self.read {
    self.ranges[self.kept] = range
  } else {
    // Splitting a range can keep more ranges than were read.
    self.ranges.insert(self.kept, range)
    self.read += 1
  }
  self.kept += 1
}

///|
fn RangeRewriter::finish(self : RangeRewriter, current : CharRange?) -> Unit {
  if current is Some(range) {
    self.keep(range)
  }
  if self.kept < self.read {
    // Remove the ranges in `kept..read` at once.
    let removed = self.read - self.kept
    let len = self.ranges.length()
    for i in self.read..<len {
      self.ranges[i - removed] = self.ranges[i]
    }
    self.ranges.truncate(len - removed)
  }
}

///|
pub fn CharacterSet::empty() -> CharacterSet {
  { ranges: [] }
}

///|
pub fn CharacterSet::from_char(c : Int) -> CharacterSet {
  { ranges: [{ start: c, end: c + 1 }] }
}

///|
pub fn CharacterSet::from_range(first : Int, last : Int) -> CharacterSet {
  let (first, last) = if first > last { (last, first) } else { (first, last) }
  { ranges: [{ start: first, end: last + 1 }] }
}

///|
pub fn CharacterSet::copy(self : CharacterSet) -> CharacterSet {
  { ranges: self.ranges.copy() }
}

///|
/// The ranges as half-open `[start, end)` pairs.
pub fn CharacterSet::raw_ranges(self : CharacterSet) -> Array[CharRange] {
  self.ranges
}

///|
/// Create a character set containing all characters *not* present in this set.
pub fn CharacterSet::negate(self : CharacterSet) -> CharacterSet {
  let ranges = self.ranges.copy()
  let mut i = 0
  let mut previous_end = 0
  while i < ranges.length() {
    let range = ranges[i]
    let start = previous_end
    previous_end = range.end
    if start < range.start {
      ranges[i] = { start, end: range.start }
      i += 1
    } else {
      ignore(ranges.remove(i))
    }
  }
  if previous_end < char_set_end {
    ranges.push({ start: previous_end, end: char_set_end })
  }
  { ranges, }
}

///|
pub fn CharacterSet::add_char(self : CharacterSet, c : Int) -> CharacterSet {
  let result = self.copy()
  ignore(result.add_int_range(0, c, c + 1))
  result
}

///|
pub fn CharacterSet::add_range(
  self : CharacterSet,
  start : Int,
  end : Int,
) -> CharacterSet {
  let result = self.copy()
  ignore(result.add_int_range(0, start, end + 1))
  result
}

///|
pub fn CharacterSet::add(self : CharacterSet, other : CharacterSet) -> CharacterSet {
  let result = self.copy()
  let mut index = 0
  for range in other.ranges {
    index = result.add_int_range(index, range.start, range.end)
  }
  result
}

///|
/// In-place variants used where upstream mutates through `&mut self`.
pub fn CharacterSet::add_char_in_place(self : CharacterSet, c : Int) -> Unit {
  ignore(self.add_int_range(0, c, c + 1))
}

///|
pub fn CharacterSet::add_range_in_place(
  self : CharacterSet,
  start : Int,
  end : Int,
) -> Unit {
  ignore(self.add_int_range(0, start, end + 1))
}

///|
pub fn CharacterSet::add_in_place(
  self : CharacterSet,
  other : CharacterSet,
) -> Unit {
  let mut index = 0
  for range in other.ranges {
    index = self.add_int_range(index, range.start, range.end)
  }
}

///|
pub fn CharacterSet::assign(self : CharacterSet, other : CharacterSet) -> Unit {
  self.ranges.clear()
  for range in other.ranges {
    self.ranges.push(range)
  }
}

///|
fn CharacterSet::add_int_range(
  self : CharacterSet,
  i : Int,
  start : Int,
  end : Int,
) -> Int {
  let ranges = self.ranges
  // Regex character classes provide sorted, disjoint ranges.
  match ranges.last() {
    None => {
      ranges.push({ start, end })
      return 0
    }
    Some(last) if last.end < start => {
      let index = ranges.length()
      ranges.push({ start, end })
      return index
    }
    _ => ()
  }
  let mut i = i
  while i < ranges.length() {
    let range = ranges[i]
    if range.start > end {
      ranges.insert(i, { start, end })
      return i
    }
    if range.end >= start {
      ranges[i] = {
        start: if range.start < start { range.start } else { start },
        end: if range.end > end { range.end } else { end },
      }
      // Join this range with the next range if needed.
      while i + 1 < ranges.length() && ranges[i + 1].start <= ranges[i].end {
        let next_end = ranges[i + 1].end
        if next_end > ranges[i].end {
          ranges[i] = { start: ranges[i].start, end: next_end }
        }
        ignore(ranges.remove(i + 1))
      }
      return i
    }
    i += 1
  }
  ranges.push({ start, end })
  i
}

///|
pub fn CharacterSet::does_intersect(
  self : CharacterSet,
  other : CharacterSet,
) -> Bool {
  self.first_overlap(other) is Some(_)
}

///|
/// The indices of the first range in `self` and in `other` that overlap.
fn CharacterSet::first_overlap(
  self : CharacterSet,
  other : CharacterSet,
) -> (Int, Int)? {
  let mut left_index = 0
  let mut right_index = 0
  while left_index < self.ranges.length() &&
        right_index < other.ranges.length() {
    let left = self.ranges[left_index]
    let right = other.ranges[right_index]
    if left.end <= right.start {
      left_index += 1
    } else if left.start >= right.end {
      right_index += 1
    } else {
      return Some((left_index, right_index))
    }
  }
  None
}

///|
/// Get the set of characters that are present in both this set and the other
/// set. Remove those common characters from both of the operands.
pub fn CharacterSet::remove_intersection(
  self : CharacterSet,
  other : CharacterSet,
) -> CharacterSet {
  guard self.first_overlap(other) is Some((left_start, right_start)) else {
    return CharacterSet::empty()
  }
  let intersection : Array[CharRange] = []
  let left = RangeRewriter::new(self.ranges, left_start)
  let right = RangeRewriter::new(other.ranges, right_start)
  let mut left_range = left.next()
  let mut right_range = right.next()
  while left_range is Some(l0) && right_range is Some(r0) {
    let mut l = l0
    let mut r = r0
    if l.end <= r.start {
      left.keep(l)
      left_range = left.next()
    } else if r.end <= l.start {
      right.keep(r)
      right_range = right.next()
    } else {
      // Up to the later start, the characters are only in the range that
      // starts first, so that part stays in its set.
      if l.start < r.start {
        left.keep({ start: l.start, end: r.start })
        l = { start: r.start, end: l.end }
      } else if r.start < l.start {
        right.keep({ start: r.start, end: l.start })
        r = { start: l.start, end: r.end }
      }
      // Both ranges now start together, and up to the earlier end the
      // characters are in both sets.
      let end = if l.end < r.end { l.end } else { r.end }
      intersection.push({ start: l.start, end })
      l = { start: end, end: l.end }
      r = { start: end, end: r.end }
      left_range = Some(l)
      right_range = Some(r)
      if l.start == l.end {
        left_range = left.next()
      }
      if r.start == r.end {
        right_range = right.next()
      }
    }
  }
  left.finish(left_range)
  right.finish(right_range)
  { ranges: intersection }
}

///|
/// Every character in `self` that is not present in `other`.
pub fn CharacterSet::difference(
  self : CharacterSet,
  other : CharacterSet,
) -> CharacterSet {
  let result = self.copy()
  ignore(result.remove_intersection(other.copy()))
  result
}

///|
pub fn CharacterSet::symmetric_difference(
  self : CharacterSet,
  other : CharacterSet,
) -> CharacterSet {
  let a = self.copy()
  let b = other.copy()
  ignore(a.remove_intersection(b))
  a.add(b)
}

///|
/// Every code point in the set, including surrogates.
pub fn CharacterSet::char_codes(self : CharacterSet) -> Array[Int] {
  let result = []
  for range in self.ranges {
    for c in range.start..<range.end {
      result.push(c)
    }
  }
  result
}

///|
fn is_scalar(c : Int) -> Bool {
  c >= 0 && c < 0x110000 && !(c >= 0xD800 && c <= 0xDFFF)
}

///|
/// Every Unicode scalar value in the set.
pub fn CharacterSet::chars(self : CharacterSet) -> Array[Int] {
  self.char_codes().filter(is_scalar)
}

///|
pub fn CharacterSet::range_count(self : CharacterSet) -> Int {
  self.ranges.length()
}

///|
/// Inclusive scalar-value ranges, skipping ranges that contain no scalar values.
pub fn CharacterSet::ranges(self : CharacterSet) -> Array[(Int, Int)] {
  let result = []
  for range in self.ranges {
    let mut start = range.start
    while start < range.end && !is_scalar(start) {
      start += 1
    }
    if start >= range.end {
      continue
    }
    let mut end = range.end - 1
    while end >= range.start && !is_scalar(end) {
      end -= 1
    }
    result.push((start, end))
  }
  result
}

///|
pub fn CharacterSet::is_empty(self : CharacterSet) -> Bool {
  self.ranges.is_empty()
}

///|
/// Get a reduced list of character ranges, assuming that a given set of
/// characters can be safely ignored.
pub fn CharacterSet::simplify_ignoring(
  self : CharacterSet,
  ruled_out_characters : CharacterSet,
) -> CharacterSet {
  let result = []
  let mut prev_range : CharRange? = None
  let items : Array[CharRange?] = self.ranges.map(r => Some(r))
  items.push(None)
  for item in items {
    if item is Some(range) {
      if ruled_out_characters.contains_codepoint_range(range.start, range.end) {
        continue
      }
      if prev_range is Some(prev) &&
        ruled_out_characters.contains_codepoint_range(prev.end, range.start) {
        prev_range = Some({ start: prev.start, end: range.end })
        continue
      }
    }
    if prev_range is Some(prev) {
      result.push(prev)
    }
    prev_range = item
  }
  { ranges: result }
}

///|
/// Whether the half-open range `[start, end)` is entirely inside one range.
pub fn CharacterSet::contains_codepoint_range(
  self : CharacterSet,
  start : Int,
  end : Int,
) -> Bool {
  // Binary search mirroring upstream's `binary_search_by`: the position of
  // the first range whose end is past `start`.
  let mut lo = 0
  let mut hi = self.ranges.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let probe = self.ranges[mid]
    if probe.end <= start {
      lo = mid + 1
    } else if probe.start > start {
      hi = mid
    } else {
      lo = mid
      break
    }
  }
  match self.ranges.get(lo) {
    Some(range) => range.start <= start && range.end >= end
    None => false
  }
}

///|
pub fn CharacterSet::contains(self : CharacterSet, c : Int) -> Bool {
  self.contains_codepoint_range(c, c + 1)
}

///|
pub impl Compare for CharacterSet with compare(self, other) {
  let mut self_count = 0
  for range in self.ranges {
    self_count += range.end - range.start
  }
  let mut other_count = 0
  for range in other.ranges {
    other_count += range.end - range.start
  }
  let count_cmp = self_count.compare(other_count)
  if count_cmp != 0 {
    return count_cmp
  }
  let n = if self.ranges.length() < other.ranges.length() {
    self.ranges.length()
  } else {
    other.ranges.length()
  }
  for i in 0..<n {
    let left_range = self.ranges[i]
    let right_range = other.ranges[i]
    let cmp = (left_range.end - left_range.start).compare(
      right_range.end - right_range.start,
    )
    if cmp != 0 {
      return cmp
    }
    // Ranges of equal length compare elementwise, i.e. by their starts.
    let cmp = left_range.start.compare(right_range.start)
    if cmp != 0 {
      return cmp
    }
  }
  0
}

///|
pub impl Debug for CharacterSet with to_repr(self) {
  @debug.Repr(self.ranges.map(r => (r.start, r.end)))
}

///|
pub fn Nfa::new() -> Nfa {
  { states: [] }
}

///|
pub fn Nfa::last_state_id(self : Nfa) -> Int {
  if self.states.is_empty() {
    abort("empty NFA")
  }
  self.states.length() - 1
}

///|
pub struct NfaCursor {
  mut state_ids : Array[Int]
  priv nfa : Nfa
}

///|
pub fn NfaCursor::new(nfa : Nfa, states : Array[Int]) -> NfaCursor {
  let result = { nfa, state_ids: [] }
  result.add_states(states)
  result
}

///|
pub fn NfaCursor::state_ids(self : NfaCursor) -> Array[Int] {
  self.state_ids
}

///|
pub fn NfaCursor::reset(self : NfaCursor, states : Array[Int]) -> Unit {
  self.state_ids = []
  self.add_states(states)
}

///|
pub fn NfaCursor::force_reset(self : NfaCursor, states : Array[Int]) -> Unit {
  self.state_ids = states
}

///|
pub fn NfaCursor::transition_chars(
  self : NfaCursor,
) -> Array[(CharacterSet, Bool)] {
  self.raw_transitions().map(t => (t.0, t.1))
}

///|
pub fn NfaCursor::transitions(self : NfaCursor) -> Array[NfaTransition] {
  group_transitions(self.raw_transitions())
}

///|
/// Like `transitions` but also returns whether any raw NFA transition is a
/// separator.
pub fn NfaCursor::transitions_and_any_sep(
  self : NfaCursor,
) -> (Array[NfaTransition], Bool) {
  let raw = self.raw_transitions()
  let any_sep = raw.iter().any(t => t.1)
  (group_transitions(raw), any_sep)
}

///|
fn NfaCursor::raw_transitions(
  self : NfaCursor,
) -> Array[(CharacterSet, Bool, Int, Int)] {
  let result = []
  for id in self.state_ids {
    if self.nfa.states[id] is Advance(chars~, state_id~, precedence~, is_sep~) {
      result.push((chars, is_sep, precedence, state_id))
    }
  }
  result
}

///|
fn group_transitions(
  iter : Array[(CharacterSet, Bool, Int, Int)],
) -> Array[NfaTransition] {
  let result : Array[NfaTransition] = []
  for item in iter {
    let (input_chars, is_sep, prec, state) = item
    let chars = input_chars.copy()
    let mut i = 0
    while i < result.length() && !chars.is_empty() {
      let intersection = result[i].characters.remove_intersection(chars)
      if !intersection.is_empty() {
        let chars_is_empty = result[i].characters.is_empty()
        let intersection_states = result[i].states.copy()
        match intersection_states.binary_search(state) {
          Ok(_) => ()
          Err(j) => intersection_states.insert(j, state)
        }
        let intersection_transition = {
          characters: intersection,
          is_separator: result[i].is_separator && is_sep,
          precedence: if result[i].precedence > prec {
            result[i].precedence
          } else {
            prec
          },
          states: intersection_states,
        }
        if chars_is_empty {
          result[i] = intersection_transition
        } else {
          // Push to the tail; the final sort makes mid-loop ordering irrelevant.
          result.push(intersection_transition)
        }
      }
      i += 1
    }
    if !chars.is_empty() {
      result.push({
        characters: chars,
        precedence: prec,
        states: [state],
        is_separator: is_sep,
      })
    }
  }
  let mut i = 0
  while i < result.length() {
    for j in 0..<i {
      if result[j].states == result[i].states &&
        result[j].is_separator == result[i].is_separator &&
        result[j].precedence == result[i].precedence {
        result[j] = {
          ..result[j],
          characters: result[j].characters.add(result[i].characters),
        }
        ignore(swap_remove(result, i))
        i -= 1
        break
      }
    }
    i += 1
  }
  // Characters of the grouped transitions are disjoint, so this ordering is total.
  result.sort_by((a, b) => a.characters.compare(b.characters))
  result
}

///|
/// Rust's `Vec::swap_remove`.
pub fn[T] swap_remove(array : Array[T], index : Int) -> T {
  let last = array.length() - 1
  let value = array[index]
  if index != last {
    array[index] = array[last]
  }
  ignore(array.pop())
  value
}

///|
pub fn NfaCursor::completions(self : NfaCursor) -> Array[(Int, Int)] {
  let result = []
  for state_id in self.state_ids {
    if self.nfa.states[state_id] is Accept(variable_index~, precedence~) {
      result.push((variable_index, precedence))
    }
  }
  result
}

///|
pub fn NfaCursor::add_states(
  self : NfaCursor,
  new_state_ids : Array[Int],
) -> Unit {
  let mut i = 0
  while i < new_state_ids.length() {
    let state_id = new_state_ids[i]
    match self.nfa.states[state_id] {
      Split(left, right) => {
        let has_left = new_state_ids.contains(left)
        let has_right = new_state_ids.contains(right)
        if !has_left {
          new_state_ids.push(left)
        }
        if !has_right {
          new_state_ids.push(right)
        }
      }
      _ =>
        match self.state_ids.binary_search(state_id) {
          Ok(_) => ()
          Err(j) => self.state_ids.insert(j, state_id)
        }
    }
    i += 1
  }
}
