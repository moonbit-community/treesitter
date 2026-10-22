///|
/// Decode one Unicode scalar. EOF has width zero; malformed input advances by
/// one byte, preserving byte-addressable source locations and guaranteeing progress.
pub fn decode(input : Bytes, offset : Int32) -> (Int32, Int32) {
  if offset < 0 || offset >= input.length() {
    return (0, 0)
  }
  let b0 = input[offset].to_int()
  if b0 < 128 {
    return (b0, 1)
  }
  let size = if b0 >= 0xc2 && b0 <= 0xdf {
    2
  } else if b0 >= 0xe0 && b0 <= 0xef {
    3
  } else if b0 >= 0xf0 && b0 <= 0xf4 {
    4
  } else {
    return (0xfffd, 1)
  }
  if offset + size > input.length() {
    return (0xfffd, 1)
  }
  let mut cp = b0 & (0x7f >> size)
  for i in 1..<size {
    let b = input[offset + i].to_int()
    if b < 0x80 || b > 0xbf {
      return (0xfffd, 1)
    }
    cp = (cp << 6) | (b & 0x3f)
  }
  if (size == 2 && cp < 0x80) ||
    (size == 3 && cp < 0x800) ||
    (size == 4 && cp < 0x10000) ||
    cp > 0x10ffff ||
    (cp >= 0xd800 && cp <= 0xdfff) {
    (0xfffd, 1)
  } else {
    (cp, size)
  }
}
