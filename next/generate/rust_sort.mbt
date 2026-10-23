// Port of Rust's `slice::sort_unstable_by` (core::slice::sort::unstable, the
// "ipnsort" of Rust 1.97), specialized to the code paths taken for `Copy`
// element types of at most 8 bytes, such as `usize` and `(u32, u32)`, and
// (`rust_sort_unstable_by_key_large`) for element types of more than 16 bytes
// without interior mutability, such as `(usize, BTreeSet<usize>)`.
//
// Upstream's generator sorts with `sort_unstable*` where elements can tie but
// still be told apart (`reorder_states_by_descending_size`, `ItemKeyMap::new`).
// The order of tied elements is then an artifact of Rust's algorithm, and it
// leaks into the parse table, so it is reproduced exactly here.

///|
priv struct UnstableSorter[T] {
  v : Array[T]
  is_less : (T, T) -> Bool
  /// Elements are `Copy` and at most 8 bytes: small slices are sorted with
  /// sorting networks, and partitioning handles two elements per step.
  /// Otherwise elements are more than 16 bytes: small slices are sorted with
  /// `small_sort_general`, and partitioning handles one element per step.
  small : Bool
}

///|
/// Rust's `v.sort_unstable_by(|a, b| ...)`, with `is_less(a, b)` meaning
/// `compare(a, b) == Less`.
fn[T] rust_sort_unstable_by(
  v : Array[T],
  is_less : (T, T) -> Bool,
  small~ : Bool = true,
) -> Unit {
  let len = v.length()
  if len < 2 {
    return
  }
  let sorter = { v, is_less, small, }
  if len <= 20 {
    sorter.insertion_sort_shift_left(0, len, 1)
    return
  }
  sorter.ipnsort(len)
}

///|
/// Rust's `v.sort_unstable_by_key(key)`.
fn[T, K : Compare] rust_sort_unstable_by_key(
  v : Array[T],
  key : (T) -> K,
) -> Unit {
  rust_sort_unstable_by(v, (a, b) => key(a) < key(b))
}

///|
/// Rust's `v.sort_unstable_by_key(key)` for elements of more than 16 bytes.
fn[T, K : Compare] rust_sort_unstable_by_key_large(
  v : Array[T],
  key : (T) -> K,
) -> Unit {
  rust_sort_unstable_by(v, (a, b) => key(a) < key(b), small=false)
}

///|
fn[T] UnstableSorter::swap(
  self : UnstableSorter[T],
  a : Int32,
  b : Int32,
) -> Unit {
  let tmp = self.v[a]
  self.v[a] = self.v[b]
  self.v[b] = tmp
}

///|
fn[T] UnstableSorter::ipnsort(self : UnstableSorter[T], len : Int32) -> Unit {
  let (run_len, was_reversed) = self.find_existing_run(len)
  if run_len == len {
    if was_reversed {
      self.v.rev_in_place()
    }
    return
  }
  // `2 * (len | 1).ilog2()`
  let limit = 2 * (31 - (len | 1).clz())
  self.quicksort(0, len, None, limit)
}

///|
fn[T] UnstableSorter::find_existing_run(
  self : UnstableSorter[T],
  len : Int32,
) -> (Int32, Bool) {
  if len < 2 {
    return (len, false)
  }
  let v = self.v
  let mut run_len = 2
  let strictly_descending = (self.is_less)(v[1], v[0])
  if strictly_descending {
    while run_len < len && (self.is_less)(v[run_len], v[run_len - 1]) {
      run_len += 1
    }
  } else {
    while run_len < len && !(self.is_less)(v[run_len], v[run_len - 1]) {
      run_len += 1
    }
  }
  (run_len, strictly_descending)
}

///|
fn[T] UnstableSorter::quicksort(
  self : UnstableSorter[T],
  base : Int32,
  len : Int32,
  ancestor_pivot : T?,
  limit : Int32,
) -> Unit {
  let mut base = base
  let mut len = len
  let mut ancestor_pivot = ancestor_pivot
  let mut limit = limit
  while true {
    // `small_sort_threshold` of `small_sort_network`.
    if len <= 32 {
      if self.small {
        self.small_sort_network(base, len)
      } else {
        self.small_sort_general(base, len)
      }
      return
    }
    if limit == 0 {
      self.heapsort(base, len)
      return
    }
    limit -= 1
    let pivot_pos = self.choose_pivot(base, len)
    if ancestor_pivot is Some(p) && !(self.is_less)(p, self.v[base + pivot_pos]) {
      let is_less = self.is_less
      let num_lt = self.partition(base, len, pivot_pos, (a, b) => !is_less(b, a))
      base = base + num_lt + 1
      len = len - (num_lt + 1)
      ancestor_pivot = None
      continue
    }
    let num_lt = self.partition(base, len, pivot_pos, self.is_less)
    self.quicksort(base, num_lt, ancestor_pivot, limit)
    ancestor_pivot = Some(self.v[base + num_lt])
    base = base + num_lt + 1
    len = len - (num_lt + 1)
  }
}

///|
fn[T] UnstableSorter::partition(
  self : UnstableSorter[T],
  base : Int32,
  len : Int32,
  pivot : Int32,
  is_less : (T, T) -> Bool,
) -> Int32 {
  if len == 0 {
    return 0
  }
  self.swap(base, base + pivot)
  let num_lt = self.partition_lomuto_branchless_cyclic(
    base + 1,
    len - 1,
    self.v[base],
    is_less,
  )
  self.swap(base, base + num_lt)
  num_lt
}

///|
fn[T] UnstableSorter::partition_lomuto_branchless_cyclic(
  self : UnstableSorter[T],
  base : Int32,
  len : Int32,
  pivot : T,
  is_less : (T, T) -> Bool,
) -> Int32 {
  if len == 0 {
    return 0
  }
  let v = self.v
  let gap_value = v[base]
  let mut num_lt = 0
  let mut right = 1
  let mut gap_pos = 0
  fn body(value : T) {
    let right_is_lt = is_less(value, pivot)
    let left = num_lt
    v[base + gap_pos] = v[base + left]
    v[base + left] = value
    gap_pos = right
    if right_is_lt {
      num_lt += 1
    }
    right += 1
  }
  // Elements of at most 16 bytes are processed two at a time.
  if self.small {
    while right < len - 1 {
      body(v[base + right])
      body(v[base + right])
    }
  }
  while true {
    if right == len {
      body(gap_value)
      break
    }
    body(v[base + right])
  }
  num_lt
}

///|
fn[T] UnstableSorter::choose_pivot(
  self : UnstableSorter[T],
  base : Int32,
  len : Int32,
) -> Int32 {
  let len_div_8 = len / 8
  let a = base
  let b = base + len_div_8 * 4
  let c = base + len_div_8 * 7
  let index = if len < 64 {
    self.median3(a, b, c)
  } else {
    self.median3_rec(a, b, c, len_div_8)
  }
  index - base
}

///|
fn[T] UnstableSorter::median3_rec(
  self : UnstableSorter[T],
  a : Int32,
  b : Int32,
  c : Int32,
  n : Int32,
) -> Int32 {
  let mut a = a
  let mut b = b
  let mut c = c
  if n * 8 >= 64 {
    let n8 = n / 8
    a = self.median3_rec(a, a + n8 * 4, a + n8 * 7, n8)
    b = self.median3_rec(b, b + n8 * 4, b + n8 * 7, n8)
    c = self.median3_rec(c, c + n8 * 4, c + n8 * 7, n8)
  }
  self.median3(a, b, c)
}

///|
fn[T] UnstableSorter::median3(
  self : UnstableSorter[T],
  a : Int32,
  b : Int32,
  c : Int32,
) -> Int32 {
  let v = self.v
  let x = (self.is_less)(v[a], v[b])
  let y = (self.is_less)(v[a], v[c])
  if x == y {
    let z = (self.is_less)(v[b], v[c])
    if z != x {
      c
    } else {
      b
    }
  } else {
    a
  }
}

///|
fn[T] UnstableSorter::heapsort(
  self : UnstableSorter[T],
  base : Int32,
  len : Int32,
) -> Unit {
  for i = len + len / 2 - 1; i >= 0; i = i - 1 {
    let sift_idx = if i >= len {
      i - len
    } else {
      self.swap(base, base + i)
      0
    }
    self.sift_down(base, if i < len { i } else { len }, sift_idx)
  }
}

///|
fn[T] UnstableSorter::sift_down(
  self : UnstableSorter[T],
  base : Int32,
  len : Int32,
  node : Int32,
) -> Unit {
  let v = self.v
  let mut node = node
  while true {
    let mut child = 2 * node + 1
    if child >= len {
      break
    }
    if child + 1 < len && (self.is_less)(v[base + child], v[base + child + 1]) {
      child += 1
    }
    if !(self.is_less)(v[base + node], v[base + child]) {
      break
    }
    self.swap(base + node, base + child)
    node = child
  }
}

///|
fn[T] UnstableSorter::small_sort_network(
  self : UnstableSorter[T],
  base : Int32,
  len : Int32,
) -> Unit {
  if len < 2 {
    return
  }
  let len_div_2 = len / 2
  let no_merge = len < 18
  let mut region_base = base
  let mut region_len = if no_merge { len } else { len_div_2 }
  while true {
    let presorted_len = if region_len >= 13 {
      self.sort13_optimal(region_base)
      13
    } else if region_len >= 9 {
      self.sort9_optimal(region_base)
      9
    } else {
      1
    }
    self.insertion_sort_shift_left(region_base, region_len, presorted_len)
    if no_merge {
      return
    }
    if region_base != base {
      break
    }
    region_base = base + len_div_2
    region_len = len - len_div_2
  }
  let scratch = self.v[base:base + len].to_owned()
  self.bidirectional_merge(base, len, scratch)
  for i in 0..<len {
    self.v[base + i] = scratch[i]
  }
}

///|
/// Merges the two sorted halves of `v[base..base + len]` into `dst`.
fn[T] UnstableSorter::bidirectional_merge(
  self : UnstableSorter[T],
  base : Int32,
  len : Int32,
  dst : Array[T],
) -> Unit {
  let src = self.v
  let len_div_2 = len / 2
  let mut left = base
  let mut right = base + len_div_2
  let mut d = 0
  let mut left_rev = base + len_div_2 - 1
  let mut right_rev = base + len - 1
  let mut d_rev = len - 1
  for _ in 0..<len_div_2 {
    // merge_up
    let is_l = !(self.is_less)(src[right], src[left])
    dst[d] = if is_l { src[left] } else { src[right] }
    if is_l {
      left += 1
    } else {
      right += 1
    }
    d += 1
    // merge_down
    let is_l = !(self.is_less)(src[right_rev], src[left_rev])
    dst[d_rev] = if is_l { src[right_rev] } else { src[left_rev] }
    if is_l {
      right_rev -= 1
    } else {
      left_rev -= 1
    }
    d_rev -= 1
  }
  let left_end = left_rev + 1
  if len % 2 != 0 {
    let left_nonempty = left < left_end
    dst[d] = if left_nonempty { src[left] } else { src[right] }
  }
}

///|
fn[T] UnstableSorter::swap_if_less(
  self : UnstableSorter[T],
  base : Int32,
  a : Int32,
  b : Int32,
) -> Unit {
  if (self.is_less)(self.v[base + b], self.v[base + a]) {
    self.swap(base + a, base + b)
  }
}

///|
fn[T] UnstableSorter::sort9_optimal(
  self : UnstableSorter[T],
  b : Int32,
) -> Unit {
  let pairs = [
    (0, 3),
    (1, 7),
    (2, 5),
    (4, 8),
    (0, 7),
    (2, 4),
    (3, 8),
    (5, 6),
    (0, 2),
    (1, 3),
    (4, 5),
    (7, 8),
    (1, 4),
    (3, 6),
    (5, 7),
    (0, 1),
    (2, 4),
    (3, 5),
    (6, 8),
    (2, 3),
    (4, 5),
    (6, 7),
    (1, 2),
    (3, 4),
    (5, 6),
  ]
  for p in pairs {
    self.swap_if_less(b, p.0, p.1)
  }
}

///|
fn[T] UnstableSorter::sort13_optimal(
  self : UnstableSorter[T],
  b : Int32,
) -> Unit {
  let pairs = [
    (0, 12),
    (1, 10),
    (2, 9),
    (3, 7),
    (5, 11),
    (6, 8),
    (1, 6),
    (2, 3),
    (4, 11),
    (7, 9),
    (8, 10),
    (0, 4),
    (1, 2),
    (3, 6),
    (7, 8),
    (9, 10),
    (11, 12),
    (4, 6),
    (5, 9),
    (8, 11),
    (10, 12),
    (0, 5),
    (3, 8),
    (4, 7),
    (6, 11),
    (9, 10),
    (0, 1),
    (2, 5),
    (6, 9),
    (7, 8),
    (10, 11),
    (1, 3),
    (2, 4),
    (5, 6),
    (9, 10),
    (1, 2),
    (3, 4),
    (5, 7),
    (6, 8),
    (2, 3),
    (4, 5),
    (6, 7),
    (8, 9),
    (3, 4),
    (5, 6),
  ]
  for p in pairs {
    self.swap_if_less(b, p.0, p.1)
  }
}

///|
fn[T] UnstableSorter::insert_tail(
  self : UnstableSorter[T],
  begin : Int32,
  tail : Int32,
) -> Unit {
  let v = self.v
  let mut sift = tail - 1
  if !(self.is_less)(v[tail], v[sift]) {
    return
  }
  let tmp = v[tail]
  let mut dst = tail
  while true {
    v[dst] = v[sift]
    dst = sift
    if sift == begin {
      break
    }
    sift -= 1
    if !(self.is_less)(tmp, v[sift]) {
      break
    }
  }
  v[dst] = tmp
}

///|
fn[T] UnstableSorter::insertion_sort_shift_left(
  self : UnstableSorter[T],
  base : Int32,
  len : Int32,
  offset : Int32,
) -> Unit {
  for tail in (base + offset)..<(base + len) {
    self.insert_tail(base, tail)
  }
}

///|
/// `small_sort_general_with_scratch` for elements of more than 16 bytes.
fn[T] UnstableSorter::small_sort_general(
  self : UnstableSorter[T],
  base : Int32,
  len : Int32,
) -> Unit {
  if len < 2 {
    return
  }
  let v = self.v
  let len_div_2 = len / 2
  let scratch = v[base:base + len].to_owned()
  let presorted_len = if len >= 8 {
    self.sort4_stable(base, scratch, 0)
    self.sort4_stable(base + len_div_2, scratch, len_div_2)
    4
  } else {
    scratch[0] = v[base]
    scratch[len_div_2] = v[base + len_div_2]
    1
  }
  for offset in [0, len_div_2] {
    let desired_len = if offset == 0 { len_div_2 } else { len - len_div_2 }
    for i in presorted_len..<desired_len {
      scratch[offset + i] = v[base + offset + i]
      // `insert_tail` within `scratch[offset..]`.
      let tail = offset + i
      let mut sift = tail - 1
      if (self.is_less)(scratch[tail], scratch[sift]) {
        let tmp = scratch[tail]
        let mut dst = tail
        while true {
          scratch[dst] = scratch[sift]
          dst = sift
          if sift == offset {
            break
          }
          sift -= 1
          if !(self.is_less)(tmp, scratch[sift]) {
            break
          }
        }
        scratch[dst] = tmp
      }
    }
  }
  // Merge `scratch` back into `v[base..base + len]`.
  let merged = scratch.copy()
  let sorter = { v: scratch, is_less: self.is_less, small: self.small, }
  sorter.bidirectional_merge(0, len, merged)
  for i in 0..<len {
    v[base + i] = merged[i]
  }
}

///|
/// `sort4_stable`: sorts `v[base..base + 4]` into `dst[at..at + 4]`.
fn[T] UnstableSorter::sort4_stable(
  self : UnstableSorter[T],
  base : Int32,
  dst : Array[T],
  at : Int32,
) -> Unit {
  let v = self.v
  let is_less = self.is_less
  let c1 = is_less(v[base + 1], v[base])
  let c2 = is_less(v[base + 3], v[base + 2])
  let a = base + (if c1 { 1 } else { 0 })
  let b = base + (if c1 { 0 } else { 1 })
  let c = base + 2 + (if c2 { 1 } else { 0 })
  let d = base + 2 + (if c2 { 0 } else { 1 })
  let c3 = is_less(v[c], v[a])
  let c4 = is_less(v[d], v[b])
  let min = if c3 { c } else { a }
  let max = if c4 { b } else { d }
  let unknown_left = if c3 { a } else if c4 { c } else { b }
  let unknown_right = if c4 { d } else if c3 { b } else { c }
  let c5 = is_less(v[unknown_right], v[unknown_left])
  let lo = if c5 { unknown_right } else { unknown_left }
  let hi = if c5 { unknown_left } else { unknown_right }
  dst[at] = v[min]
  dst[at + 1] = v[lo]
  dst[at + 2] = v[hi]
  dst[at + 3] = v[max]
}
