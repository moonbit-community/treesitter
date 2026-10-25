// `rand::rngs::StdRng` and the parts of rand's sampling that the fuzzer
// (`fuzz/random.rs`) and the query tests (`test_query_random`) use: a
// bit-exact port of rand 0.10.3 (the version in the pinned Cargo.lock):
//
// - `StdRng` = chacha20 0.10.2 `ChaCha12Rng` (the "legacy" variant: 64-bit
//   block counter in state words 12-13, 64-bit stream id 0 in words 14-15),
//   buffered by rand_core 0.10.1 `BlockRng` four blocks (64 words) at a
//   time, including how `next_u32`/`next_u64` consume buffered words;
// - `SeedableRng::seed_from_u64` (rand_core 0.10.1: the seed is filled with
//   PCG32 outputs);
// - `random_range(low..high)` and `random_range(low..=high)` for `usize`
//   (`UniformUsize::sample_single[_inclusive]`, which sample through
//   `UniformInt<u32>` when `high <= u32::MAX` and through `UniformInt<u64>`
//   otherwise) and `random_range(low..=high)` for `i32` (`UniformInt<i32>`),
//   all with the default biased Canon's method (the `unbiased` feature is
//   off);
// - `random_bool(p)` (`Bernoulli`);
// - `sample(Alphanumeric)`.

///|
/// Words in a ChaCha block.
const CHACHA_BLOCK_WORDS : Int32 = 16

///|
/// `BUFFER_SIZE`: the `BlockRng` buffer holds `BUF_BLOCKS = 4` blocks.
const CHACHA_BUFFER_SIZE : Int32 = 64

///|
/// `rand::rngs::StdRng`.
pub struct StdRng {
  /// The ChaCha state (`ChaChaCore::state`).
  priv state : FixedArray[UInt32]
  /// `BlockRng::results`.
  priv results : FixedArray[UInt32]
  /// `BlockRng`'s index into `results` (upstream stores it in
  /// `results[0]`, which is only read before it is overwritten).
  priv mut index : Int32
}

///|
/// `pcg32` (rand_core seedable_rng.rs).
fn pcg32(state : Ref[UInt64]) -> UInt32 {
  let mul = 0x5851_F42D_4C95_7F2DUL
  let inc = 0xA176_54E4_6FBE_17F3UL
  // We advance the state first (to get away from the input value,
  // in case it has low Hamming Weight).
  state.val = state.val * mul + inc
  let state = state.val

  // Use PCG output function with to_le to generate x:
  let xorshifted = (((state >> 18) ^ state) >> 27).to_uint()
  let rot = (state >> 59).to_int()
  rotr32(xorshifted, rot)
}

///|
/// `SeedableRng::seed_from_u64` followed by `ChaCha12Rng::from_seed`. Each
/// 4-byte seed chunk is a little-endian PCG32 output, and the key words are
/// read back little-endian, so key word `i` is the `i`-th PCG32 output.
pub fn StdRng::seed_from_u64(seed : UInt64) -> StdRng {
  let pcg_state = Ref(seed)
  let state = FixedArray::make(16, 0U)
  // CONSTANTS
  state[0] = 0x6170_7865U
  state[1] = 0x3320_646eU
  state[2] = 0x7962_2d32U
  state[3] = 0x6b20_6574U
  for i in 0..<8 {
    state[4 + i] = pcg32(pcg_state)
  }
  // words 12-13: block counter 0; words 14-15: the 8-byte zero nonce
  {
    state,
    results: FixedArray::make(CHACHA_BUFFER_SIZE, 0U),
    index: CHACHA_BUFFER_SIZE,
  }
}

///|
fn rotl32(x : UInt32, n : Int32) -> UInt32 {
  (x << n) | (x >> (32 - n))
}

///|
fn rotr32(x : UInt32, n : Int32) -> UInt32 {
  if n == 0 {
    x
  } else {
    (x >> n) | (x << (32 - n))
  }
}

///|
fn quarter_round(
  a : Int32,
  b : Int32,
  c : Int32,
  d : Int32,
  state : FixedArray[UInt32],
) -> Unit {
  state[a] = state[a] + state[b]
  state[d] = rotl32(state[d] ^ state[a], 16)
  state[c] = state[c] + state[d]
  state[b] = rotl32(state[b] ^ state[c], 12)
  state[a] = state[a] + state[b]
  state[d] = rotl32(state[d] ^ state[a], 8)
  state[c] = state[c] + state[d]
  state[b] = rotl32(state[b] ^ state[c], 7)
}

///|
/// `Generator::generate` (the `soft` backend's `gen_ks_blocks`; the SIMD
/// backends produce the same key stream): four ChaCha12 blocks, advancing
/// the 64-bit block counter after each.
fn StdRng::generate(self : StdRng) -> Unit {
  for block in 0..<4 {
    let res = self.state.copy()
    // ChaCha12: R12::COUNT = 6 double rounds
    for _ in 0..<6 {
      // column rounds
      quarter_round(0, 4, 8, 12, res)
      quarter_round(1, 5, 9, 13, res)
      quarter_round(2, 6, 10, 14, res)
      quarter_round(3, 7, 11, 15, res)
      // diagonal rounds
      quarter_round(0, 5, 10, 15, res)
      quarter_round(1, 6, 11, 12, res)
      quarter_round(2, 7, 8, 13, res)
      quarter_round(3, 4, 9, 14, res)
    }
    for i in 0..<16 {
      res[i] = res[i] + self.state[i]
    }
    let ctr = ((self.state[13].to_uint64() << 32) | self.state[12].to_uint64()) +
      1
    self.state[12] = ctr.to_uint()
    self.state[13] = (ctr >> 32).to_uint()
    for i in 0..<CHACHA_BLOCK_WORDS {
      self.results[block * CHACHA_BLOCK_WORDS + i] = res[i]
    }
  }
}

///|
/// `next_u32` (`BlockRng::next_word`).
pub fn StdRng::next_u32(self : StdRng) -> UInt32 {
  let mut index = self.index
  if index >= CHACHA_BUFFER_SIZE {
    self.generate()
    index = 0
  }
  let value = self.results[index]
  self.index = index + 1
  value
}

///|
/// `next_u64` (`BlockRng::next_u64_from_u32`).
pub fn StdRng::next_u64(self : StdRng) -> UInt64 {
  let n = CHACHA_BUFFER_SIZE
  let index = self.index
  let mut new_index = 0
  let mut lo = 0U
  let mut hi = 0U
  if index < n - 1 {
    lo = self.results[index]
    hi = self.results[index + 1]
    new_index = index + 2
  } else {
    lo = self.results[n - 1]
    self.generate()
    hi = self.results[0]
    new_index = 1
    if index >= n {
      lo = hi
      hi = self.results[1]
      new_index = 2
    }
  }
  self.index = new_index
  (hi.to_uint64() << 32) | lo.to_uint64()
}

///|
/// `UniformInt<u32>::sample_single_inclusive` (biased Canon's method) for
/// `low <= high`, on the bit patterns of `low` and `high`.
fn StdRng::sample_single_inclusive_u32(
  self : StdRng,
  low : UInt32,
  high : UInt32,
) -> UInt32 {
  let range = high - low + 1
  if range == 0 {
    // Range is MAX+1 (unrepresentable), so we need a special case
    return self.next_u32()
  }
  // generate a sample using a sensible integer type
  let wide = self.next_u32().to_uint64() * range.to_uint64()
  let mut result = (wide >> 32).to_uint()
  let lo_order = wide.to_uint()
  // if the sample is biased...
  if lo_order > 0U - range {
    // ...generate a new sample to reduce bias...
    let new_hi_order = ((self.next_u32().to_uint64() * range.to_uint64()) >> 32).to_uint()
    // ... incrementing result on overflow
    let is_overflow = lo_order + new_hi_order < lo_order
    if is_overflow {
      result += 1
    }
  }
  low + result
}

///|
/// `u64::wmul` (`WideningMultiply` through `u128`): the high and low
/// halves of the 128-bit product `a * b`.
fn wmul_u64(a : UInt64, b : UInt64) -> (UInt64, UInt64) {
  let mask = 0xFFFF_FFFFUL
  let a_lo = a & mask
  let a_hi = a >> 32
  let b_lo = b & mask
  let b_hi = b >> 32
  let lo_lo = a_lo * b_lo
  let hi_lo = a_hi * b_lo
  let lo_hi = a_lo * b_hi
  let hi_hi = a_hi * b_hi
  // the middle column, with the carry out of the low 64 bits
  let cross = (lo_lo >> 32) + (hi_lo & mask) + lo_hi
  let hi = hi_hi + (hi_lo >> 32) + (cross >> 32)
  let lo = (cross << 32) | (lo_lo & mask)
  (hi, lo)
}

///|
/// `UniformInt<u64>::sample_single_inclusive` (biased Canon's method) for
/// `low <= high`.
fn StdRng::sample_single_inclusive_u64(
  self : StdRng,
  low : UInt64,
  high : UInt64,
) -> UInt64 {
  let range = high - low + 1
  if range == 0 {
    // Range is MAX+1 (unrepresentable), so we need a special case
    return self.next_u64()
  }
  // generate a sample using a sensible integer type
  let (hi_order, lo_order) = wmul_u64(self.next_u64(), range)
  let mut result = hi_order
  // if the sample is biased...
  if lo_order > 0UL - range {
    // ...generate a new sample to reduce bias...
    let (new_hi_order, _) = wmul_u64(self.next_u64(), range)
    // ... incrementing result on overflow
    let is_overflow = lo_order + new_hi_order < lo_order
    if is_overflow {
      result += 1
    }
  }
  low + result
}

///|
/// `random_range(low..=high)` for `usize` on a 64-bit target
/// (`UniformUsize::sample_single_inclusive`).
pub fn StdRng::random_range_inclusive_usize(
  self : StdRng,
  low : UInt64,
  high : UInt64,
) -> UInt64 {
  guard low <= high else { abort("cannot sample empty range") }
  if high > 0xFFFF_FFFFUL {
    return self.sample_single_inclusive_u64(low, high)
  }
  self.sample_single_inclusive_u32(low.to_uint(), high.to_uint()).to_uint64()
}

///|
/// `GEN_ASCII_STR_CHARSET`.
let gen_ascii_str_charset : Bytes = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

///|
/// `sample(Alphanumeric)` (`Distribution<u8> for Alphanumeric`).
pub fn StdRng::sample_alphanumeric(self : StdRng) -> Byte {
  let range = 26U + 26 + 10
  // We can pick from 62 characters. This is so close to a power of 2, 64,
  // that we can do better than `Uniform`. Use a simple bitshift and
  // rejection sampling. We do not use a bitmask, because for small RNGs
  // the most significant bits are usually of higher quality.
  for ;; {
    let var_ = self.next_u32() >> (32 - 6)
    if var_ < range {
      return gen_ascii_str_charset[var_.reinterpret_as_int()]
    }
  }
}

///|
/// `random_range(low..high)` for `usize` (`UniformUsize::sample_single`;
/// `high` always fits in `u32` here).
pub fn StdRng::random_range_usize(
  self : StdRng,
  low : Int32,
  high : Int32,
) -> Int32 {
  guard low >= 0 && low < high else { abort("cannot sample empty range") }
  // UniformInt::<u32>::sample_single(low, high) = ..._inclusive(low, high - 1)
  self
  .sample_single_inclusive_u32(
    low.reinterpret_as_uint(),
    (high - 1).reinterpret_as_uint(),
  )
  .reinterpret_as_int()
}

///|
/// `random_range(low..=high)` for `i32` (`UniformInt<i32>`, sampled as
/// `u32`).
pub fn StdRng::random_range_inclusive_i32(
  self : StdRng,
  low : Int32,
  high : Int32,
) -> Int32 {
  guard low <= high else { abort("cannot sample empty range") }
  self
  .sample_single_inclusive_u32(
    low.reinterpret_as_uint(),
    high.reinterpret_as_uint(),
  )
  .reinterpret_as_int()
}

///|
/// `random_bool(p)` (`Bernoulli::new(p)` then `sample`).
pub fn StdRng::random_bool(self : StdRng, p : Double) -> Bool {
  // SCALE = 2^64
  let scale = 2.0 * 9223372036854775808.0
  guard p >= 0.0 && p <= 1.0 else {
    abort("p=\{p} is outside range [0.0, 1.0]")
  }
  if p == 1.0 {
    // ALWAYS_TRUE
    return true
  }
  let p_int = (p * scale).to_uint64()
  self.next_u64() < p_int
}
