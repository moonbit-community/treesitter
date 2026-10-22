///|
/// Canonical disjoint inclusive ranges of Unicode scalar values.
pub struct CharSet {
  ranges : Array[(Int32, Int32)]
} derive(Debug, Eq)

///|
pub extend CharSet with Eq::{equal, not_equal}

///|
pub extend CharSet with @debug.Debug::{to_repr}

///|
pub fn CharSet::new(ranges : Array[(Int32, Int32)]) -> CharSet {
  let sorted = ranges.copy()
  sorted.sort_by((a, b) => a.0.compare(b.0))
  let result : Array[(Int32, Int32)] = []
  for (lo, hi) in sorted {
    let lo = Int32::max(lo, 0)
    let hi = Int32::min(hi, 0x10ffff)
    if lo <= hi {
      if result.last() is Some((prev_lo, prev_hi)) && lo <= prev_hi + 1 {
        result[result.length() - 1] = (prev_lo, Int32::max(hi, prev_hi))
      } else {
        result.push((lo, hi))
      }
    }
  }
  // Surrogate code points are not input characters.
  let scalars : Array[(Int32, Int32)] = []
  for (lo, hi) in result {
    if lo < 0xd800 {
      scalars.push((lo, Int32::min(hi, 0xd7ff)))
    }
    if hi > 0xdfff {
      scalars.push((Int32::max(lo, 0xe000), hi))
    }
  }
  { ranges: scalars, }
}

///|
pub fn CharSet::contains(self : CharSet, codepoint : Int32) -> Bool {
  for lo = 0, hi = self.ranges.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let (start, end) = self.ranges[mid]
    if codepoint < start {
      continue lo, mid
    }
    if codepoint > end {
      continue mid + 1, hi
    }
    return true
  }
  false
}

///|
pub fn CharSet::union(self : CharSet, other : CharSet) -> CharSet {
  CharSet::new(self.ranges + other.ranges)
}

///|
pub fn CharSet::complement(self : CharSet) -> CharSet {
  let ranges = []
  let mut start = 0
  for (lo, hi) in self.ranges {
    if start < lo {
      ranges.push((start, lo - 1))
    }
    start = hi + 1
  }
  if start <= 0x10ffff {
    ranges.push((start, 0x10ffff))
  }
  CharSet::new(ranges)
}

///|
fn CharSet::case_fold(self : CharSet) -> CharSet {
  let ranges = self.ranges.copy()
  for (from, to) in unicode_folds {
    if self.contains(from) {
      ranges.push((to, to))
    }
  }
  CharSet::new(ranges)
}

///|
pub fn CharSet::intersection(self : CharSet, other : CharSet) -> CharSet {
  let ranges = []
  let mut a = 0
  let mut b = 0
  while a < self.ranges.length() && b < other.ranges.length() {
    let (alo, ahi) = self.ranges[a]
    let (blo, bhi) = other.ranges[b]
    let lo = Int32::max(alo, blo)
    let hi = Int32::min(ahi, bhi)
    if lo <= hi {
      ranges.push((lo, hi))
    }
    if ahi < bhi {
      a += 1
    } else {
      b += 1
    }
  }
  { ranges, }
}

///|
pub fn CharSet::difference(self : CharSet, other : CharSet) -> CharSet {
  self.intersection(other.complement())
}

///|
pub fn CharSet::symmetric_difference(
  self : CharSet,
  other : CharSet,
) -> CharSet {
  self.difference(other).union(other.difference(self))
}
