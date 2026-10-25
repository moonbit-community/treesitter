// Rust 1.97.1 `std::hash::DefaultHasher` (SipHash-1-3 with zero keys,
// `core/src/hash/sip.rs`) and `impl Hash for Path` (Unix, `std/src/path.rs`),
// which `load_language_at_path_with_name` uses to name the compilation lock
// of an output path.

///|
/// `DefaultHasher::new()`. SipHash consumes the written bytes as one stream,
/// so they are buffered and compressed by `finish`.
priv struct DefaultHasher {
  bytes : Array[Byte]
}

///|
fn DefaultHasher::new() -> DefaultHasher {
  { bytes: [], }
}

///|
fn DefaultHasher::write(self : DefaultHasher, bytes : BytesView) -> Unit {
  for b in bytes {
    self.bytes.push(b)
  }
}

///|
/// `Hasher::write_usize`: the native-endian (little-endian) bytes of a
/// 64-bit `usize`.
fn DefaultHasher::write_usize(self : DefaultHasher, n : UInt64) -> Unit {
  for i in 0..<8 {
    self.bytes.push((n >> (8 * i)).to_byte())
  }
}

///|
fn rotl(x : UInt64, b : Int32) -> UInt64 {
  (x << b) | (x >> (64 - b))
}

///|
/// `Hasher::finish` of `SipHasher13`.
fn DefaultHasher::finish(self : DefaultHasher) -> UInt64 {
  // `Sip13Rounds`: one compression round and three finalization rounds.
  fn compress(v : FixedArray[UInt64]) -> Unit {
    v[0] = v[0] + v[1]
    v[1] = rotl(v[1], 13)
    v[1] = v[1] ^ v[0]
    v[0] = rotl(v[0], 32)
    v[2] = v[2] + v[3]
    v[3] = rotl(v[3], 16)
    v[3] = v[3] ^ v[2]
    v[0] = v[0] + v[3]
    v[3] = rotl(v[3], 21)
    v[3] = v[3] ^ v[0]
    v[2] = v[2] + v[1]
    v[1] = rotl(v[1], 17)
    v[1] = v[1] ^ v[2]
    v[2] = rotl(v[2], 32)
  }
  // `State` with k0 = k1 = 0.
  let v : FixedArray[UInt64] = [
    0x736f6d6570736575UL, 0x646f72616e646f6dUL, 0x6c7967656e657261UL, 0x7465646279746573UL,
  ]
  let length = self.bytes.length()
  let word = (start : Int32, count : Int32) => {
    let mut m = 0UL
    for i in 0..<count {
      m = m | (self.bytes[start + i].to_uint64() << (8 * i))
    }
    m
  }
  let full = length / 8 * 8
  for start = 0; start < full; start = start + 8 {
    let m = word(start, 8)
    v[3] = v[3] ^ m
    compress(v) // c_rounds: 1
    v[0] = v[0] ^ m
  }
  let b = ((length.to_uint64() & 0xffUL) << 56) | word(full, length - full)
  v[3] = v[3] ^ b
  compress(v)
  v[0] = v[0] ^ b
  v[2] = v[2] ^ 0xffUL
  // d_rounds: 3
  compress(v)
  compress(v)
  compress(v)
  v[0] ^ v[1] ^ v[2] ^ v[3]
}

///|
/// `impl Hash for Path` on Unix: the bytes of each component, skipping
/// separators and `.` components after a separator (which `components()`
/// would normalize away), then a `usize` mixing the component lengths so
/// that `foo/bar` and `foobar` differ.
fn hash_path(path : String, h : DefaultHasher) -> Unit {
  let bytes = @support.utf8(path)
  let is_sep_byte = (b : Byte) => b == b'/'
  let mut component_start = 0
  let mut chunk_bits = 0UL
  for i in 0..<bytes.length() {
    if is_sep_byte(bytes[i]) {
      if i > component_start {
        let to_hash = bytes[component_start:i]
        chunk_bits = chunk_bits + to_hash.length().to_uint64()
        chunk_bits = (chunk_bits >> 2) | (chunk_bits << 62)
        h.write(to_hash)
      }
      // skip over separator and optionally a following CurDir item
      // since components() would normalize these away.
      component_start = i + 1
      let tail = bytes[component_start:]
      component_start += match tail {
        [b'.'] => 1
        [b'.', sep, ..] if is_sep_byte(sep) => 1
        _ => 0
      }
    }
  }
  if component_start < bytes.length() {
    let to_hash = bytes[component_start:]
    chunk_bits = chunk_bits + to_hash.length().to_uint64()
    chunk_bits = (chunk_bits >> 2) | (chunk_bits << 62)
    h.write(to_hash)
  }
  h.write_usize(chunk_bits)
}

///|
/// `{:x}` of the `DefaultHasher` hash of a `Path`.
fn path_hash_hex(path : String) -> String {
  let hasher = DefaultHasher::new()
  hash_path(path, hasher)
  hasher.finish().to_string(radix=16)
}
