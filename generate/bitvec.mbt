// Port of tree-sitter crates/generate/src/bitvec.rs.

///|
/// A growable bit vector backed by 64-bit words.
///
/// `words` stands for upstream's arena region: only the first
/// `words_in_use()` words (`ceil(len / 64)`) are part of the vector, and the
/// words after them are always zero (upstream's invariant
/// `data[words_in_use..capacity] == 0`). Bits of the last word in use beyond
/// `len` are not necessarily zero: upstream's `resize` does not clear them when
/// shrinking within a word, and `insert_all` ORs them in.
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
/// The backing words: the words in use followed by zero words.
pub fn BitVec::words(self : BitVec) -> Array[UInt64] {
  self.words
}

///|
pub fn BitVec::len(self : BitVec) -> Int {
  self.len
}

///|
fn BitVec::words_in_use(self : BitVec) -> Int {
  (self.len + 63) / 64
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
/// Upstream fills whole words: growing within the last word in use leaves
/// the newly exposed bits as they are, and shrinking within it does not clear
/// the truncated bits.
pub fn BitVec::resize(self : BitVec, new_len : Int, val : Bool) -> Unit {
  let new_words = (new_len + 63) / 64
  let old_words = self.words_in_use()
  self.ensure_words(new_words)
  if new_words > old_words {
    let fill : UInt64 = if val { 0UL.lnot() } else { 0 }
    for i in old_words..<new_words {
      self.words[i] = fill
    }
    // When setting bits to true, clear any bits in the last word that fall
    // beyond new_len.
    if val && new_len % 64 != 0 {
      let mask = (1UL << (new_len % 64)) - 1
      self.words[new_words - 1] = self.words[new_words - 1] & mask
    }
  } else if new_words < old_words {
    // Zero out truncated words so stale data is never visible.
    for i in new_words..<old_words {
      self.words[i] = 0
    }
  }
  self.len = new_len
}

///|
pub fn BitVec::last(self : BitVec) -> Bool? {
  if self.len == 0 {
    None
  } else {
    self.get(self.len - 1)
  }
}

///|
pub fn BitVec::pop(self : BitVec) -> Bool? {
  if self.len == 0 {
    return None
  }
  self.len -= 1
  let word_idx = self.len / 64
  let bit_idx = self.len % 64
  let new_words_in_use = self.words_in_use()
  let val = ((self.words[word_idx] >> bit_idx) & 1) != 0
  if val {
    self.words[word_idx] = self.words[word_idx] & (1UL << bit_idx).lnot()
  }
  // Zero out the word if it's no longer in use.
  if word_idx >= new_words_in_use {
    self.words[word_idx] = 0
  }
  Some(val)
}

///|
/// Unsets every bit, keeping the length.
pub fn BitVec::unset_all(self : BitVec) -> Unit {
  for i in 0..<self.words_in_use() {
    self.words[i] = 0
  }
}

///|
/// Word-level OR: self |= other. Returns true if any new bits were set.
pub fn BitVec::insert_all(self : BitVec, other : BitVec) -> Bool {
  let other_words = other.words_in_use()
  if other_words == 0 {
    return false
  }
  // The words after `self.words_in_use()` are zero already.
  self.ensure_words(other_words)
  if other.len > self.len {
    self.len = other.len
  }
  let mut any_new = 0UL
  for i in 0..<other_words {
    let sw = self.words[i]
    let ow = other.words[i]
    any_new = any_new | (ow & sw.lnot())
    self.words[i] = sw | ow
  }
  any_new != 0
}

///|
pub fn BitVec::copy(self : BitVec) -> BitVec {
  let n = self.words_in_use()
  let words = Array::make(n, 0UL)
  for i in 0..<n {
    words[i] = self.words[i]
  }
  { words, len: self.len }
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
