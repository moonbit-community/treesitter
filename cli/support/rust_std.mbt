// Rust standard library behaviour that shows in the CLI's output: integer
// parsing (`u8::from_str_radix`) and the default panic hook.

///|
/// `u8::from_str_radix(src, radix)` of UTF-8 bytes: `None` for an empty
/// input, an invalid digit or an overflow. A leading `+` is accepted.
pub fn u8_from_str_radix(src : BytesView, radix : Int32) -> Int32? {
  if src.length() == 0 {
    return None
  }
  let digits = match src {
    [b'+' | b'-'] => return None
    [b'+', .. rest] => rest
    _ => src
  }
  let mut result = 0
  for b in digits {
    let c = b.to_int()
    let digit = if c >= '0' && c <= '9' {
      c - '0'
    } else if c >= 'a' && c <= 'z' {
      c - 'a' + 10
    } else if c >= 'A' && c <= 'Z' {
      c - 'A' + 10
    } else {
      return None
    }
    if digit >= radix {
      return None
    }
    result = result * radix + digit
    if result > 255 {
      return None
    }
  }
  Some(result)
}
