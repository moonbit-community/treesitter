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

///|
/// Starting value for `hash_mix`.
const HASH_SEED : UInt = 0x165667B1

///|
/// Mixes `input` into a hash accumulator without `Hasher`'s allocation, for
/// hot `Hash::hash` overrides. Hash values never reach the output: MoonBit's
/// `Map` iterates in insertion order whatever the hashes are.
fn hash_mix(acc : UInt, input : Int) -> UInt {
  let x = acc + input.reinterpret_as_uint() * 0xC2B2AE3DU
  ((x << 17) | (x >> 15)) * 0x27D4EB2FU
}

///|
/// Finishes a `hash_mix` accumulator.
fn hash_finish(acc : UInt) -> Int {
  let mut acc = acc
  acc = acc ^ (acc >> 15)
  acc *= 0x85EBCA77U
  acc = acc ^ (acc >> 13)
  acc *= 0xC2B2AE3DU
  acc = acc ^ (acc >> 16)
  acc.reinterpret_as_int()
}
