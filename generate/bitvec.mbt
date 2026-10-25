// Port of tree-sitter crates/generate/src/bitvec.rs.

///|
/// A growable bit vector backed by 64-bit words.
pub struct BitVec {
  priv words : Array[UInt64]
  priv mut len : Int
}

///|
pub fn BitVec::new() -> BitVec {
  { words: [], len: 0 }
}

///|
pub fn BitVec::with_capacity(_n_bits : Int) -> BitVec {
  { words: [], len: 0 }
}

///|
pub fn BitVec::words(self : BitVec) -> Array[UInt64] {
  self.words
}

///|
pub fn BitVec::len(self : BitVec) -> Int {
  self.len
}

///|
pub fn BitVec::get(self : BitVec, index : Int) -> Bool? {
  if index < self.len {
    Some(((self.words[index / 64] >> (index % 64)) & 1) != 0)
  } else {
    None
  }
}

///|
pub fn BitVec::at(self : BitVec, index : Int) -> Bool {
  ((self.words[index / 64] >> (index % 64)) & 1) != 0
}

///|
pub fn BitVec::set(self : BitVec, index : Int, val : Bool) -> Unit {
  let mask = 1UL << (index % 64)
  if val {
    self.words[index / 64] = self.words[index / 64] | mask
  } else {
    self.words[index / 64] = self.words[index / 64] & mask.lnot()
  }
}

///|
fn BitVec::ensure_words(self : BitVec, n_words : Int) -> Unit {
  while self.words.length() < n_words {
    self.words.push(0)
  }
}

///|
pub fn BitVec::resize(self : BitVec, new_len : Int, val : Bool) -> Unit {
  let n_words = (new_len + 63) / 64
  if new_len > self.len {
    self.ensure_words(n_words)
    for i in self.len..<new_len {
      self.set(i, val)
    }
  } else {
    for i in new_len..<self.len {
      self.set(i, false)
    }
  }
  self.len = new_len
}

///|
pub fn BitVec::last(self : BitVec) -> Bool? {
  if self.len == 0 {
    None
  } else {
    Some(self.at(self.len - 1))
  }
}

///|
pub fn BitVec::pop(self : BitVec) -> Bool? {
  if self.len == 0 {
    None
  } else {
    let value = self.at(self.len - 1)
    self.set(self.len - 1, false)
    self.len -= 1
    Some(value)
  }
}

///|
pub fn BitVec::unset_all(self : BitVec) -> Unit {
  for i in 0..<self.words.length() {
    self.words[i] = 0
  }
}

///|
/// Union `other` into `self`, growing as needed. Returns whether any bit changed.
pub fn BitVec::insert_all(self : BitVec, other : BitVec) -> Bool {
  if other.len > self.len {
    self.ensure_words((other.len + 63) / 64)
    self.len = other.len
  }
  let mut changed = false
  for i, w in other.words {
    let old = self.words[i]
    let new = old | w
    if new != old {
      self.words[i] = new
      changed = true
    }
  }
  changed
}

///|
pub fn BitVec::copy(self : BitVec) -> BitVec {
  { words: self.words.copy(), len: self.len }
}

///|
fn BitVec::effective_words(self : BitVec) -> Int {
  let mut n = self.words.length()
  while n > 0 && self.words[n - 1] == 0 {
    n -= 1
  }
  n
}

///|
pub impl Eq for BitVec with equal(self, other) {
  let n = self.effective_words()
  if n != other.effective_words() {
    return false
  }
  for i in 0..<n {
    if self.words[i] != other.words[i] {
      return false
    }
  }
  true
}

///|
pub impl Hash for BitVec with hash_combine(self, hasher) {
  let n = self.effective_words()
  hasher.combine_int(n)
  for i in 0..<n {
    hasher.combine_uint64(self.words[i])
  }
}

///|
/// Upstream ordering: compare words from the lowest index; within the first
/// differing word, the side that owns the lowest differing bit is greater.
pub impl Compare for BitVec with compare(self, other) {
  let max_len = if self.words.length() > other.words.length() {
    self.words.length()
  } else {
    other.words.length()
  }
  for i in 0..<max_len {
    let aw = self.words.get(i).unwrap_or(0)
    let bw = other.words.get(i).unwrap_or(0)
    if aw != bw {
      let first_diff = (aw ^ bw).ctz()
      return if ((aw >> first_diff) & 1) != 0 { 1 } else { -1 }
    }
  }
  0
}

///|
pub impl Debug for BitVec with to_repr(self) {
  @debug.Repr(set_bits(self.words))
}

///|
/// Indices of set bits, in increasing order.
pub fn set_bits(words : Array[UInt64]) -> Array[Int] {
  let result = []
  for wi, word in words {
    let mut w = word
    while w != 0 {
      let bit = w.ctz()
      w = w & (w - 1)
      result.push(wi * 64 + bit)
    }
  }
  result
}
