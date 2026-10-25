// zmij 1.0.23 `Buffer::format` for `f64` (the float formatting of
// serde_json 1.0.154's serializer and error messages): the shortest
// correctly rounded decimal digits, written in fixed notation when the
// decimal exponent is in -5..=15 and as `d.ddde±x` otherwise. The digits
// come from core's Ryu (`Double::to_string`), which picks the same shortest
// representation.

///|
/// The shortest round-trip digits of a positive finite double and the
/// decimal exponent of the first digit.
fn shortest_digits(f : Double) -> (String, Int32) {
  let s = f.to_string()
  let (mantissa, exp) = match s.find("e") {
    Some(i) => {
      let mut j = i + 1
      let negative = s[j] == '-'
      if s[j] == '-' || s[j] == '+' {
        j += 1
      }
      let mut e = 0
      while j < s.length() {
        e = e * 10 + (s[j].to_int() - '0')
        j += 1
      }
      (s[:i].to_owned(), if negative { -e } else { e })
    }
    None => (s, 0)
  }
  let int_len = match mantissa.find(".") {
    Some(i) => i
    None => mantissa.length()
  }
  let all = mantissa.replace(old=".", new="")
  let mut lz = 0
  while lz < all.length() && all[lz] == '0' {
    lz += 1
  }
  let mut end = all.length()
  while end > lz + 1 && all[end - 1] == '0' {
    end -= 1
  }
  (all[lz:end].to_owned(), int_len - 1 - lz + exp)
}

///|
/// `zmij::Buffer::format` of an `f64`.
pub fn zmij_format(f : Double) -> String {
  if f.is_nan() {
    return "NaN"
  }
  if f.is_inf() {
    return if f > 0.0 { "inf" } else { "-inf" }
  }
  let negative = f.reinterpret_as_uint64() >> 63 == 1UL
  let sign = if negative { "-" } else { "" }
  if f == 0.0 {
    return sign + "0.0"
  }
  let (digits, dec_exp) = shortest_digits(f.abs())
  let length = digits.length()
  let sb = StringBuilder()
  sb.write_string(sign)
  if dec_exp >= -5 && dec_exp <= 15 {
    if length - 1 <= dec_exp {
      // 1234e7 -> 12340000000.0
      sb.write_string(digits)
      sb.write_string("0".repeat(dec_exp - (length - 1)))
      sb.write_string(".0")
    } else if 0 <= dec_exp {
      // 1234e-2 -> 12.34
      sb.write_string(digits[:dec_exp + 1].to_owned())
      sb.write_char('.')
      sb.write_string(digits[dec_exp + 1:].to_owned())
    } else {
      // 1234e-6 -> 0.001234
      sb.write_string("0.")
      sb.write_string("0".repeat(-dec_exp - 1))
      sb.write_string(digits)
    }
  } else {
    // 1234e30 -> 1.234e33
    sb.write_string(digits[:1].to_owned())
    if length > 1 {
      sb.write_char('.')
      sb.write_string(digits[1:].to_owned())
    }
    sb.write_char('e')
    sb.write_char(if dec_exp >= 0 { '+' } else { '-' })
    sb.write_string(dec_exp.abs().to_string())
  }
  sb.to_string()
}
