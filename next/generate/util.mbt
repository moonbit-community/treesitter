///|
/// A stable merge sort, matching Rust's `sort_by`/`sort_by_key` semantics for
/// equal elements (MoonBit's `Array::sort_by` is unstable).
pub fn[T] stable_sort_by(array : Array[T], cmp : (T, T) -> Int) -> Unit {
  let n = array.length()
  if n < 2 {
    return
  }
  let buffer = array.copy()
  let mut width = 1
  while width < n {
    let mut lo = 0
    while lo < n {
      let mid = if lo + width < n { lo + width } else { n }
      let hi = if lo + 2 * width < n { lo + 2 * width } else { n }
      let mut i = lo
      let mut j = mid
      let mut k = lo
      while i < mid && j < hi {
        if cmp(array[j], array[i]) < 0 {
          buffer[k] = array[j]
          j += 1
        } else {
          buffer[k] = array[i]
          i += 1
        }
        k += 1
      }
      while i < mid {
        buffer[k] = array[i]
        i += 1
        k += 1
      }
      while j < hi {
        buffer[k] = array[j]
        j += 1
        k += 1
      }
      lo = hi
    }
    for idx in 0..<n {
      array[idx] = buffer[idx]
    }
    width *= 2
  }
}

///|
pub fn[T, K : Compare] stable_sort_by_key(array : Array[T], key : (T) -> K) -> Unit {
  stable_sort_by(array, (a, b) => key(a).compare(key(b)))
}

///|
/// Rust's `Vec::dedup`: remove consecutive equal elements.
pub fn[T : Eq] dedup(array : Array[T]) -> Unit {
  if array.length() < 2 {
    return
  }
  let mut w = 1
  for r in 1..<array.length() {
    if array[r] != array[w - 1] {
      array[w] = array[r]
      w += 1
    }
  }
  array.truncate(w)
}
