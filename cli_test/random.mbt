// Port of tree-sitter crates/cli/src/fuzz/random.rs.
//
// Upstream draws from `rand::rngs::StdRng` (ChaCha12) seeded with
// `seed_from_u64`. That generator is a dependency, not Tree-sitter code, so
// it is replaced by SplitMix64: the same seed gives a deterministic edit
// sequence here, but not the sequence upstream produces for that seed.

///|
let operators : Array[Char] = [
  '+', '-', '<', '>', '(', ')', '*', '/', '&', '|', '!', ',', '.', '%',
]

///|
let alphanumeric : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

///|
pub struct Rand {
  priv mut state : UInt64
}

///|
pub fn Rand::new(seed : Int32) -> Rand {
  { state: seed.to_int64().reinterpret_as_uint64(), }
}

///|
fn Rand::next_u64(self : Rand) -> UInt64 {
  self.state = self.state + 0x9E3779B97F4A7C15UL
  let mut z = self.state
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
}

///|
/// A uniformly distributed integer in `0..=max`.
pub fn Rand::unsigned(self : Rand, max : Int32) -> Int32 {
  let range = max.to_uint64() + 1UL
  // Rejection sampling to avoid modulo bias.
  let limit = 0UL - (0UL - range) % range // = range * floor(2^64 / range)
  for ;; {
    let x = self.next_u64()
    if limit == 0UL || x < limit {
      return (x % range).to_int()
    }
  }
}

///|
pub fn Rand::words(self : Rand, max_count : Int32) -> Array[Byte] {
  let word_count = self.unsigned(max_count)
  let result = Array(capacity=2 * word_count)
  for i in 0..<word_count {
    if i > 0 {
      if self.unsigned(5) == 0 {
        result.push(b'\n')
      } else {
        result.push(b' ')
      }
    }
    if self.unsigned(3) == 0 {
      let index = self.unsigned(operators.length() - 1)
      result.push(operators[index].to_int().to_byte())
    } else {
      for _ in 0..<self.unsigned(8) {
        result.push(
          alphanumeric[self.unsigned(alphanumeric.length() - 1)].to_byte(),
        )
      }
    }
  }
  result
}
