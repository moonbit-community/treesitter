// Port of tree-sitter lib/src/unicode.h (ICU's U8_NEXT / U16_NEXT macros).

///|
pub let ts_decode_error : Int32 = -1

///|
let u8_lead3_t1_bits : FixedArray[Int32] = [
  0x20, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x10,
  0x30, 0x30,
]

///|
let u8_lead4_t1_bits : FixedArray[Int32] = [
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1E, 0x0F, 0x0F, 0x0F, 0x00, 0x00,
  0x00, 0x00,
]

///|
/// `ts_decode_utf8`: ICU `U8_NEXT` with `U_SENTINEL` substitution.
pub fn decode_utf8(string : BytesView) -> (UInt32, Int32) {
  let length = string.length()
  let mut i = 0
  let mut c = string[i].to_int()
  i += 1
  if c < 0x80 {
    return (i.reinterpret_as_uint(), c)
  }
  let mut t = 0
  let ok = if i != length {
    let prefix_ok = if c >= 0xe0 {
      let lead_ok = if c < 0xf0 {
        // U+0800..U+FFFF except surrogates
        c = c & 0xf
        t = string[i].to_int()
        if (u8_lead3_t1_bits[c] & (1 << (t >> 5))) != 0 {
          t = t & 0x3f
          true
        } else {
          false
        }
      } else {
        // U+10000..U+10FFFF
        c = c - 0xf0
        if c <= 4 {
          t = string[i].to_int()
          if (u8_lead4_t1_bits[t >> 4] & (1 << c)) != 0 {
            c = (c << 6) | (t & 0x3f)
            i += 1
            if i != length {
              t = (string[i].to_int() - 0x80) & 0xff
              t <= 0x3f
            } else {
              false
            }
          } else {
            false
          }
        } else {
          false
        }
      }
      // valid second-to-last trail byte
      if lead_ok {
        c = (c << 6) | t
        i += 1
        i != length
      } else {
        false
      }
    } else if c >= 0xc2 {
      // U+0080..U+07FF
      c = c & 0x1f
      true
    } else {
      false
    }
    // last trail byte
    if prefix_ok {
      t = (string[i].to_int() - 0x80) & 0xff
      if t <= 0x3f {
        c = (c << 6) | t
        i += 1
        true
      } else {
        false
      }
    } else {
      false
    }
  } else {
    false
  }
  if !ok {
    c = ts_decode_error
  }
  (i.reinterpret_as_uint(), c)
}

///|
fn utf16_next(string : BytesView, little_endian : Bool) -> (UInt32, Int32) {
  let length = string.length()
  if length < 2 {
    return (length.reinterpret_as_uint(), ts_decode_error)
  }
  let units = length / 2
  fn unit(index : Int32) -> Int32 {
    let a = string[index * 2].to_int()
    let b = string[index * 2 + 1].to_int()
    if little_endian {
      a | (b << 8)
    } else {
      (a << 8) | b
    }
  }

  let mut i = 0
  let mut c = unit(i)
  i += 1
  if (c & 0xfffffc00) == 0xd800 {
    if i != units {
      let c2 = unit(i)
      if (c2 & 0xfffffc00) == 0xdc00 {
        i += 1
        c = (c << 10) + c2 - ((0xd800 << 10) + 0xdc00 - 0x10000)
      }
    }
  }
  ((i * 2).reinterpret_as_uint(), c)
}

///|
/// `ts_decode_utf16_le`.
pub fn decode_utf16_le(string : BytesView) -> (UInt32, Int32) {
  utf16_next(string, true)
}

///|
/// `ts_decode_utf16_be`.
pub fn decode_utf16_be(string : BytesView) -> (UInt32, Int32) {
  utf16_next(string, false)
}
