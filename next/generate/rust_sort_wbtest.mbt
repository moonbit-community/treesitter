///|
/// Permutations of tie-heavy inputs, compared by FNV-1a hash with the output of
/// the same program compiled with Rust 1.97.1 (`v.sort_unstable_by_key`).
test "rust_sort_unstable_by_key matches Rust 1.97" {
  let mut state : UInt64 = 12345
  let buf = StringBuilder()
  let sizes = []
  for n in 0..<200 {
    sizes.push(n)
  }
  for n in [255, 256, 300, 500, 1000, 1500, 3000, 5000] {
    sizes.push(n)
  }
  for n in sizes {
    for modulus in [1U, 2, 3, 7, 50, 1000000] {
      let keys : Array[Int64] = []
      for _ in 0..<n {
        state = state * 6364136223846793005UL + 1442695040888963407UL
        keys.push(
          ((state >> 33).to_uint() % modulus).to_uint64().reinterpret_as_int64(),
        )
      }
      let v = Array::makei(n, i => i)
      rust_sort_unstable_by_key(v, i => -keys[i])
      buf.write_string(v.map(x => x.to_string()).join(" "))
      buf.write_char('\n')
    }
  }
  let mut h : UInt64 = 0xcbf29ce484222325
  let text = buf.to_string()
  for i in 0..<text.length() {
    h = h ^ text[i].to_uint64()
    h = h * 0x100000001b3UL
  }
  inspect(text.length(), content="693420")
  assert_eq(h, 0x7a6af8aebbf3c27bUL)
}
