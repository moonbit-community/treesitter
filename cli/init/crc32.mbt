// `crc32fast::hash` (CRC-32/ISO-HDLC, the zlib/PNG checksum), used by
// init.rs for the `build.zig.zon` fingerprint.

///|
let crc32_table : FixedArray[UInt32] = {
  let table = FixedArray::make(256, 0U)
  for n in 0..<256 {
    let mut c = n.reinterpret_as_uint()
    for _ in 0..<8 {
      c = if (c & 1) != 0 { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
    }
    table[n] = c
  }
  table
}

///|
/// `crc32fast::hash`.
fn crc32(data : BytesView) -> UInt32 {
  let mut crc = 0xFFFFFFFFU
  for b in data {
    crc = crc32_table[((crc ^ b.to_uint()) & 0xFF).reinterpret_as_int()] ^
      (crc >> 8)
  }
  crc ^ 0xFFFFFFFFU
}
