// Port of regex-syntax 0.8.11 src/hir/interval.rs.
//
// This module contains an *internal* implementation of interval sets.
//
// The primary invariant that interval sets guards is canonical ordering. That
// is, every interval set contains an ordered sequence of intervals where
// no two intervals are overlapping or adjacent. While this invariant is
// occasionally broken within the implementation, it should be impossible for
// callers to observe it.
//
// Since case folding (as implemented below) breaks that invariant, we roll
// that into this API even though it is a little out of place in an otherwise
// generic interval set. (Hence the reason why the `unicode` module is imported
// here.)
//
// Upstream's `Bound` trait (implemented by `char` and `u8`) is folded into
// `Interval` as the static `bound_*` methods; bounds are `Int`s.

///|
pub struct IntervalSet[I] {
  /// A sorted set of non-overlapping ranges.
  priv ranges : Array[I]
  /// While not required at all for correctness, we keep track of whether an
  /// interval set has been case folded or not. This helps us avoid doing
  /// redundant work if, for example, a set has already been cased folded.
  /// And note that whether a set is folded or not is preserved through
  /// all of the pairwise set operations. That is, if both interval sets
  /// have been case folded, then any of difference, union, intersection or
  /// symmetric difference all produce a case folded set.
  ///
  /// Note that when this is true, it *must* be the case that the set is case
  /// folded. But when it's false, the set *may* be case folded.
  ///
  /// Bottom line: this is a performance optimization.
  priv mut folded : Bool
}

///|
/// We implement Eq manually so that we don't consider the set's internal
/// 'folded' property to be part of its identity. The 'folded' property is
/// strictly an optimization.
pub impl[I : Interval] Eq for IntervalSet[I] with fn equal(self, other) {
  self.ranges == other.ranges
}

///|
pub impl[I : Debug] Debug for IntervalSet[I] with fn to_repr(self) {
  Repr(self.ranges)
}

///|
/// Create a new set from a sequence of intervals. Each interval is
/// specified as a pair of bounds, where both bounds are inclusive.
///
/// The given ranges do not need to be in any specific order, and ranges
/// may overlap.
pub fn[I : Interval] IntervalSet::new(intervals : Array[I]) -> IntervalSet[I] {
  let ranges = intervals.copy()
  // An empty set is case folded.
  let folded = ranges.is_empty()
  let set = { ranges, folded, }
  set.canonicalize()
  set
}

///|
/// A copy of this set (Rust `Clone`).
pub fn[I] IntervalSet::copy(self : IntervalSet[I]) -> IntervalSet[I] {
  { ranges: self.ranges.copy(), folded: self.folded, }
}

///|
/// Add a new interval to this set.
pub fn[I : Interval] IntervalSet::push(
  self : IntervalSet[I],
  interval : I,
) -> Unit {
  let i = match self.ranges.binary_search(interval) {
    // Exact match, `interval` is already in the set.
    Ok(_) => return
    Err(i) => i
  }
  // The search finds us the first index where the previous interval
  // start is less than or equal to the new interval start. Since the
  // existing intervals are non-overlapping we only need to try to union
  // this single preceding interval
  let mut interval = interval
  let mut start = i
  if i > 0 {
    let before_i = i - 1
    let before = self.ranges[before_i]
    if interval_union(before, interval) is Some(union) {
      interval = union
      start = before_i
    }
  }
  // `interval` may overlap any number of intervals following the
  // insertion point so will union each of them until we reach the
  // first non-overlapping interval
  let mut end = i
  for after_i in i..<self.ranges.length() {
    let after = self.ranges[after_i]
    guard interval_union(interval, after) is Some(union) else { break }
    interval = union
    end = after_i + 1
  }
  ignore(self.ranges.drain(start, end))
  self.ranges.insert(start, interval)

  // We don't know whether the new interval added here is considered
  // case folded, so we conservatively assume that the entire set is
  // no longer case folded if it was previously.
  self.folded = false
}

///|
/// Return an iterator over all intervals in this set.
///
/// The iterator yields intervals in ascending order.
pub fn[I] IntervalSet::iter(self : IntervalSet[I]) -> Iter[I] {
  self.ranges.iter()
}

///|
/// Return an immutable slice of intervals in this set.
///
/// The sequence returned is in canonical ordering.
pub fn[I] IntervalSet::intervals(self : IntervalSet[I]) -> ArrayView[I] {
  self.ranges[:]
}

///|
/// Expand this interval set such that it contains all case folded
/// characters. For example, if this class consists of the range `a-z`,
/// then applying case folding will result in the class containing both the
/// ranges `a-z` and `A-Z`.
///
/// This returns an error if the necessary case mapping data is not
/// available.
pub fn[I : Interval] IntervalSet::case_fold_simple(
  self : IntervalSet[I],
) -> Unit raise CaseFoldError {
  if self.folded {
    return
  }
  let len = self.ranges.length()
  for i in 0..<len {
    let range = self.ranges[i]
    range.case_fold_simple(self.ranges) catch {
      CaseFoldError as err => {
        self.canonicalize()
        raise err
      }
    }
  }
  self.canonicalize()
  self.folded = true
}

///|
/// Union this set with the given set, in place.
pub fn[I : Interval] IntervalSet::union(
  self : IntervalSet[I],
  other : IntervalSet[I],
) -> Unit {
  if other.ranges.is_empty() || self.ranges == other.ranges {
    return
  }
  // This could almost certainly be done more efficiently.
  for range in other.ranges {
    self.ranges.push(range)
  }
  self.canonicalize()
  self.folded = self.folded && other.folded
}

///|
/// Intersect this set with the given set, in place.
pub fn[I : Interval] IntervalSet::intersect(
  self : IntervalSet[I],
  other : IntervalSet[I],
) -> Unit {
  if self.ranges.is_empty() {
    return
  }
  if other.ranges.is_empty() {
    self.ranges.clear()
    // An empty set is case folded.
    self.folded = true
    return
  }

  // There should be a way to do this in-place with constant memory,
  // but I couldn't figure out a simple way to do it. So just append
  // the intersection to the end of this range, and then drain it before
  // we're done.
  let drain_end = self.ranges.length()
  let mut a = 0
  let mut b = 0
  while true {
    if interval_intersect(self.ranges[a], other.ranges[b]) is Some(ab) {
      self.ranges.push(ab)
    }
    if self.ranges[a].upper() < other.ranges[b].upper() {
      if a + 1 >= drain_end {
        break
      }
      a += 1
    } else {
      if b + 1 >= other.ranges.length() {
        break
      }
      b += 1
    }
  }
  ignore(self.ranges.drain(0, drain_end))
  self.folded = self.folded && other.folded
}

///|
/// Subtract the given set from this set, in place.
pub fn[I : Interval] IntervalSet::difference(
  self : IntervalSet[I],
  other : IntervalSet[I],
) -> Unit {
  if self.ranges.is_empty() || other.ranges.is_empty() {
    return
  }

  // This algorithm is (to me) surprisingly complex. A search of the
  // interwebs indicate that this is a potentially interesting problem.
  // Folks seem to suggest interval or segment trees, but I'd like to
  // avoid the overhead (both runtime and conceptual) of that.
  //
  // The following is basically my Shitty First Draft. Therefore, in
  // order to grok it, you probably need to read each line carefully.
  // Simplifications are most welcome!
  //
  // Remember, we can assume the canonical format invariant here, which
  // says that all ranges are sorted, not overlapping and not adjacent in
  // each class.
  let drain_end = self.ranges.length()
  let mut a = 0
  let mut b = 0
  while a < drain_end && b < other.ranges.length() {
    // Basically, the easy cases are when neither range overlaps with
    // each other. If the `b` range is less than our current `a`
    // range, then we can skip it and move on.
    if other.ranges[b].upper() < self.ranges[a].lower() {
      b += 1
      continue
    }
    // ... similarly for the `a` range. If it's less than the smallest
    // `b` range, then we can add it as-is.
    if self.ranges[a].upper() < other.ranges[b].lower() {
      let range = self.ranges[a]
      self.ranges.push(range)
      a += 1
      continue
    }
    // Otherwise, we have overlapping ranges.
    guard !interval_is_intersection_empty(self.ranges[a], other.ranges[b]) else {
      abort("assertion failed")
    }

    // This part is tricky and was non-obvious to me without looking
    // at explicit examples (see the tests). The trickiness stems from
    // two things: 1) subtracting a range from another range could
    // yield two ranges and 2) after subtracting a range, it's possible
    // that future ranges can have an impact. The loop below advances
    // the `b` ranges until they can't possible impact the current
    // range.
    //
    // For example, if our `a` range is `a-t` and our next three `b`
    // ranges are `a-c`, `g-i`, `r-t` and `x-z`, then we need to apply
    // subtraction three times before moving on to the next `a` range.
    let mut range = self.ranges[a]
    let mut lost = false
    while b < other.ranges.length() &&
          !interval_is_intersection_empty(range, other.ranges[b]) {
      let old_range = range
      range = match interval_difference(range, other.ranges[b]) {
        (None, None) => {
          // We lost the entire range, so move on to the next
          // without adding this one.
          lost = true
          break
        }
        (Some(range1), None) | (None, Some(range1)) => range1
        (Some(range1), Some(range2)) => {
          self.ranges.push(range1)
          range2
        }
      }
      // It's possible that the `b` range has more to contribute
      // here. In particular, if it is greater than the original
      // range, then it might impact the next `a` range *and* it
      // has impacted the current `a` range as much as possible,
      // so we can quit. We don't bump `b` so that the next `a`
      // range can apply it.
      if other.ranges[b].upper() > old_range.upper() {
        break
      }
      // Otherwise, the next `b` range might apply to the current
      // `a` range.
      b += 1
    }
    if lost {
      a += 1
      continue
    }
    self.ranges.push(range)
    a += 1
  }
  while a < drain_end {
    let range = self.ranges[a]
    self.ranges.push(range)
    a += 1
  }
  ignore(self.ranges.drain(0, drain_end))
  self.folded = self.folded && other.folded
}

///|
/// Compute the symmetric difference of the two sets, in place.
///
/// This computes the symmetric difference of two interval sets. This
/// removes all elements in this set that are also in the given set,
/// but also adds all elements from the given set that aren't in this
/// set. That is, the set will contain all elements in either set,
/// but will not contain any elements that are in both sets.
pub fn[I : Interval] IntervalSet::symmetric_difference(
  self : IntervalSet[I],
  other : IntervalSet[I],
) -> Unit {
  // TODO(burntsushi): Fix this so that it amortizes allocation.
  let intersection = self.copy()
  intersection.intersect(other)
  self.union(other)
  self.difference(intersection)
}

///|
/// Negate this interval set.
///
/// For all `x` where `x` is any element, if `x` was in this set, then it
/// will not be in this set after negation.
pub fn[I : Interval] IntervalSet::negate(self : IntervalSet[I]) -> Unit {
  if self.ranges.is_empty() {
    let (min, max) = (I::bound_min_value(), I::bound_max_value())
    self.ranges.push(I::create(min, max))
    // The set containing everything must case folded.
    self.folded = true
    return
  }

  // There should be a way to do this in-place with constant memory,
  // but I couldn't figure out a simple way to do it. So just append
  // the negation to the end of this range, and then drain it before
  // we're done.
  let drain_end = self.ranges.length()

  // We do checked arithmetic below because of the canonical ordering
  // invariant.
  if self.ranges[0].lower() > I::bound_min_value() {
    let upper = I::bound_decrement(self.ranges[0].lower())
    self.ranges.push(I::create(I::bound_min_value(), upper))
  }
  for i in 1..<drain_end {
    let lower = I::bound_increment(self.ranges[i - 1].upper())
    let upper = I::bound_decrement(self.ranges[i].lower())
    self.ranges.push(I::create(lower, upper))
  }
  if self.ranges[drain_end - 1].upper() < I::bound_max_value() {
    let lower = I::bound_increment(self.ranges[drain_end - 1].upper())
    self.ranges.push(I::create(lower, I::bound_max_value()))
  }
  ignore(self.ranges.drain(0, drain_end))
  // We don't need to update whether this set is folded or not, because
  // it is conservatively preserved through negation. Namely, if a set
  // is not folded, then it is possible that its negation is folded, for
  // example, [^☃]. But we're fine with assuming that the set is not
  // folded in that case. (`folded` permits false negatives but not false
  // positives.)
  //
  // But what about when a set is folded, is its negation also
  // necessarily folded? Yes. Because if a set is folded, then for every
  // character in the set, it necessarily included its equivalence class
  // of case folded characters. Negating it in turn means that all
  // equivalence classes in the set are negated, and any equivalence
  // class that was previously not in the set is now entirely in the set.
}

///|
/// Converts this set into a canonical ordering.
fn[I : Interval] IntervalSet::canonicalize(self : IntervalSet[I]) -> Unit {
  if self.is_canonical() {
    return
  }
  self.ranges.sort()
  guard !self.ranges.is_empty() else { abort("assertion failed") }

  // Is there a way to do this in-place with constant memory? I couldn't
  // figure out a way to do it. So just append the canonicalization to
  // the end of this range, and then drain it before we're done.
  let drain_end = self.ranges.length()
  for oldi in 0..<drain_end {
    // If we've added at least one new range, then check if we can
    // merge this range in the previously added range.
    if self.ranges.length() > drain_end {
      let last = self.ranges.length() - 1
      if interval_union(self.ranges[last], self.ranges[oldi]) is Some(union) {
        self.ranges[last] = union
        continue
      }
    }
    let range = self.ranges[oldi]
    self.ranges.push(range)
  }
  ignore(self.ranges.drain(0, drain_end))
}

///|
/// Returns true if and only if this class is in a canonical ordering.
fn[I : Interval] IntervalSet::is_canonical(self : IntervalSet[I]) -> Bool {
  for i in 1..<self.ranges.length() {
    let (p0, p1) = (self.ranges[i - 1], self.ranges[i])
    if p0 >= p1 {
      return false
    }
    if interval_is_contiguous(p0, p1) {
      return false
    }
  }
  true
}

///|
/// An inclusive interval with bounds of type `Int` (upstream `Interval`,
/// with `Interval::Bound` fixed to code points / byte values).
pub(open) trait Interval: Eq + Compare {
  fn lower(Self) -> Int32
  fn upper(Self) -> Int32
  /// Create a new interval, ordering the bounds.
  fn create(Int32, Int32) -> Self
  fn case_fold_simple(Self, Array[Self]) -> Unit raise CaseFoldError
  /// `Bound::min_value`.
  fn bound_min_value() -> Int32
  /// `Bound::max_value`.
  fn bound_max_value() -> Int32
  /// `Bound::increment`.
  fn bound_increment(Int32) -> Int32
  /// `Bound::decrement`.
  fn bound_decrement(Int32) -> Int32
}

///|
/// Union the given overlapping range into this range.
///
/// If the two ranges aren't contiguous, then this returns `None`.
fn[I : Interval] interval_union(this : I, other : I) -> I? {
  if !interval_is_contiguous(this, other) {
    return None
  }
  let lower = @cmp.minimum(this.lower(), other.lower())
  let upper = @cmp.maximum(this.upper(), other.upper())
  Some(I::create(lower, upper))
}

///|
/// Intersect this range with the given range and return the result.
///
/// If the intersection is empty, then this returns `None`.
fn[I : Interval] interval_intersect(this : I, other : I) -> I? {
  let lower = @cmp.maximum(this.lower(), other.lower())
  let upper = @cmp.minimum(this.upper(), other.upper())
  if lower <= upper {
    Some(I::create(lower, upper))
  } else {
    None
  }
}

///|
/// Subtract the given range from this range and return the resulting
/// ranges.
///
/// If subtraction would result in an empty range, then no ranges are
/// returned.
fn[I : Interval] interval_difference(this : I, other : I) -> (I?, I?) {
  if interval_is_subset(this, other) {
    return (None, None)
  }
  if interval_is_intersection_empty(this, other) {
    return (Some(this), None)
  }
  let add_lower = other.lower() > this.lower()
  let add_upper = other.upper() < this.upper()
  // We know this because !this.is_subset(other) and the ranges have
  // a non-empty intersection.
  guard add_lower || add_upper else { abort("assertion failed") }
  let mut ret0 = None
  let mut ret1 = None
  if add_lower {
    let upper = I::bound_decrement(other.lower())
    ret0 = Some(I::create(this.lower(), upper))
  }
  if add_upper {
    let lower = I::bound_increment(other.upper())
    let range = I::create(lower, this.upper())
    if ret0 is None {
      ret0 = Some(range)
    } else {
      ret1 = Some(range)
    }
  }
  (ret0, ret1)
}

///|
/// Returns true if and only if the two ranges are contiguous. Two ranges
/// are contiguous if and only if the ranges are either overlapping or
/// adjacent.
fn[I : Interval] interval_is_contiguous(this : I, other : I) -> Bool {
  let lower1 = this.lower()
  let upper1 = this.upper()
  let lower2 = other.lower()
  let upper2 = other.upper()
  @cmp.maximum(lower1, lower2) <= @cmp.minimum(upper1, upper2) + 1
}

///|
/// Returns true if and only if the intersection of this range and the
/// other range is empty.
fn[I : Interval] interval_is_intersection_empty(this : I, other : I) -> Bool {
  let (lower1, upper1) = (this.lower(), this.upper())
  let (lower2, upper2) = (other.lower(), other.upper())
  @cmp.maximum(lower1, lower2) > @cmp.minimum(upper1, upper2)
}

///|
/// Returns true if and only if this range is a subset of the other range.
fn[I : Interval] interval_is_subset(this : I, other : I) -> Bool {
  let (lower1, upper1) = (this.lower(), this.upper())
  let (lower2, upper2) = (other.lower(), other.upper())
  lower2 <= lower1 && lower1 <= upper2 && lower2 <= upper1 && upper1 <= upper2
}

///|
/// `Bound for char`: increment skipping the surrogate block.
fn char_increment(c : Int32) -> Int32 {
  match c {
    0xD7FF => 0xE000
    c => {
      guard c + 1 <= 0x10FFFF else { abort("char overflow") }
      c + 1
    }
  }
}

///|
/// `Bound for char`: decrement skipping the surrogate block.
fn char_decrement(c : Int32) -> Int32 {
  match c {
    0xE000 => 0xD7FF
    c => {
      guard c - 1 >= 0 else { abort("char underflow") }
      c - 1
    }
  }
}

///|
/// `Bound for u8`.
fn byte_increment(b : Int32) -> Int32 {
  guard b + 1 <= 0xFF else { abort("u8 overflow") }
  b + 1
}

///|
/// `Bound for u8`.
fn byte_decrement(b : Int32) -> Int32 {
  guard b - 1 >= 0 else { abort("u8 underflow") }
  b - 1
}
