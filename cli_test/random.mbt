// Port of tree-sitter crates/cli/src/fuzz/random.rs. `usize` is `UInt64`
// (the 64-bit targets); `StdRng` is in std_rng.mbt.

///|
let operators : Array[Char] = [
  '+', '-', '<', '>', '(', ')', '*', '/', '&', '|', '!', ',', '.', '%',
]

///|
pub struct Rand(StdRng)

///|
pub fn Rand::new(seed : UInt64) -> Rand {
  Rand(StdRng::seed_from_u64(seed))
}

///|
pub fn Rand::unsigned(self : Rand, max : UInt64) -> UInt64 {
  self.0.random_range_inclusive_usize(0, max)
}

///|
pub fn Rand::words(self : Rand, max_count : UInt64) -> Array[Byte] {
  let word_count = self.unsigned(max_count)
  let result = Array(capacity=2 * word_count.to_int())
  for i in 0UL..<word_count {
    if i > 0 {
      if self.unsigned(5) == 0 {
        result.push(b'\n')
      } else {
        result.push(b' ')
      }
    }
    if self.unsigned(3) == 0 {
      let index = self.unsigned((operators.length() - 1).to_uint64())
      result.push(operators[index.to_int()].to_int().to_byte())
    } else {
      for _ in 0UL..<self.unsigned(8) {
        result.push(self.0.sample_alphanumeric())
      }
    }
  }
  result
}
