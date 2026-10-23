// The random number generator of `test_query_random`: rand's `StdRng`
// (`StdRng::seed_from_u64`, `random_range`, `random_bool`).
//
// PLACEHOLDER: backed by core's ChaCha8 `@random.Rand`, so the patterns
// drawn for a seed differ from upstream's (the test's assertion, naive
// matching == query matching, holds for any pattern).

///|
priv struct StdRng {
  rand : @random.Rand
}

///|
fn StdRng::seed_from_u64(seed : UInt64) -> StdRng {
  let bytes = FixedArray::make(32, b'\x00')
  for i in 0..<8 {
    bytes[i] = (seed >> (8 * i)).to_byte()
  }
  { rand: @random.Rand::chacha8(seed=Bytes::from_array(bytes[:])), }
}

///|
/// `random_range(low..high)` for `usize`.
fn StdRng::random_range_usize(
  self : StdRng,
  low : Int32,
  high : Int32,
) -> Int32 {
  guard low < high else { abort("cannot sample empty range") }
  low + self.rand.int(limit=high - low)
}

///|
/// `random_range(low..=high)` for `i32`.
fn StdRng::random_range_inclusive_i32(
  self : StdRng,
  low : Int32,
  high : Int32,
) -> Int32 {
  guard low <= high else { abort("cannot sample empty range") }
  low + self.rand.int(limit=high - low + 1)
}

///|
/// `random_bool(p)`.
fn StdRng::random_bool(self : StdRng, p : Double) -> Bool {
  self.rand.double() < p
}
