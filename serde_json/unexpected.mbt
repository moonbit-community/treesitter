// serde_core 1.0.229's `de::Unexpected` and its `Display`, as serde_json's
// `JsonUnexpected` overrides it (`null` for the unit value, floats formatted
// by the zmij 1.0.23 crate), plus the Rust formatting both rely on.

///|
/// `serde::de::Unexpected`: the kind of value a visitor did not expect.
pub(all) enum Unexpected {
  Bool(Bool)
  Unsigned(UInt64)
  Signed(Int64)
  Float(Double)
  Char(Char)
  Str(String)
  Bytes
  Unit
  Option
  NewtypeStruct
  Seq
  Map
  Enum
  UnitVariant
  NewtypeVariant
  TupleVariant
  StructVariant
  Other(String)
} derive(Eq, Debug)

///|
/// `JsonUnexpected`'s `Display`.
pub fn Unexpected::json_display(self : Unexpected) -> String {
  match self {
    Unit => "null"
    Float(value) => "floating point `\{zmij_format(value)}`"
    unexp => unexp.to_string()
  }
}

///|
/// serde's `Display for Unexpected`.
pub impl Show for Unexpected with fn output(self, logger) {
  logger.write_string(
    match self {
      Bool(b) => "boolean `\{b}`"
      Unsigned(i) => "integer `\{i}`"
      Signed(i) => "integer `\{i}`"
      Float(f) => "floating point `\{with_decimal_point(f)}`"
      Char(c) => "character `\{c}`"
      Str(s) => "string \{rust_debug_str(s)}"
      Bytes => "byte array"
      Unit => "unit value"
      Option => "Option value"
      NewtypeStruct => "newtype struct"
      Seq => "sequence"
      Map => "map"
      Enum => "enum"
      UnitVariant => "unit variant"
      NewtypeVariant => "newtype variant"
      TupleVariant => "tuple variant"
      StructVariant => "struct variant"
      Other(other) => other
    },
  )
}

///|
/// serde's `WithDecimalPoint`: Rust's `Display` of an `f64`, with `.0`
/// appended to a finite value printed without a decimal point. (Only
/// `Unexpected`'s own `Display` uses it; serde_json prints floats with zmij.)
fn with_decimal_point(f : Double) -> String {
  let s = rust_display_f64(f)
  if f.is_nan() || f.is_inf() || s.contains(".") {
    s
  } else {
    s + ".0"
  }
}

///|
/// Rust's `Display` of an `f64`: the shortest round-trip digits, never in
/// exponent notation.
fn rust_display_f64(f : Double) -> String {
  if f.is_nan() {
    return "NaN"
  }
  if f.is_inf() {
    return if f > 0.0 { "inf" } else { "-inf" }
  }
  let (negative, digits, exp) = shortest_decimal(f)
  let sb = StringBuilder()
  if negative {
    sb.write_char('-')
  }
  let n = digits.length()
  if digits == "0" {
    sb.write_char('0')
  } else if exp >= n - 1 {
    sb.write_string(digits)
    for _ in 0..<(exp - (n - 1)) {
      sb.write_char('0')
    }
  } else if exp >= 0 {
    sb.write_string(digits[:exp + 1].to_owned())
    sb.write_char('.')
    sb.write_string(digits[exp + 1:].to_owned())
  } else {
    sb.write_string("0.")
    for _ in 0..<(-exp - 1) {
      sb.write_char('0')
    }
    sb.write_string(digits)
  }
  sb.to_string()
}

///|
/// The sign, the shortest round-trip significant digits (`"0"` for zero) and
/// the decimal exponent `e` of a finite `f`, so that `|f|` is `d.ddd × 10^e`.
fn shortest_decimal(f : Double) -> (Bool, String, Int32) {
  let negative = f.reinterpret_as_uint64() >> 63 != 0
  if f == 0.0 {
    return (negative, "0", 0)
  }
  // `Double::to_string` prints the shortest round-trip digits, either as a
  // plain decimal or as `d.ddde±x`.
  let text = f.abs().to_string()
  let (mantissa, exp10) = match text.find("e") {
    Some(i) => {
      let exponent = text[i + 1:].to_owned()
      let exponent = if exponent.has_prefix("+") {
        exponent[1:].to_owned()
      } else {
        exponent
      }
      (text[:i].to_owned(), parse_decimal_int(exponent))
    }
    None => (text, 0)
  }
  // Collect the digits and the position of the decimal point.
  let sb = StringBuilder()
  let mut point = -1
  let mut count = 0
  for c in mantissa {
    if c == '.' {
      point = count
    } else {
      sb.write_char(c)
      count += 1
    }
  }
  if point < 0 {
    point = count
  }
  let all = sb.to_string()
  // Strip leading zeros (moving the point) and trailing zeros.
  let mut start = 0
  while start < all.length() - 1 && all[start] == '0' {
    start += 1
  }
  let mut end = all.length()
  while end > start + 1 && all[end - 1] == '0' {
    end -= 1
  }
  let digits = all[start:end].to_owned()
  (negative, digits, point - start - 1 + exp10)
}

///|
fn parse_decimal_int(s : String) -> Int32 {
  let mut negative = false
  let mut value = 0
  for c in s {
    if c == '-' {
      negative = true
    } else {
      value = value * 10 + (c.to_int() - '0'.to_int())
    }
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
/// `zmij::Buffer::format` of an `f64`: the shortest round-trip digits, in
/// fixed notation for decimal exponents -5..=15 (`1.0`, `0.00001`,
/// `1000000000000000.0`) and as `d.ddde±x` otherwise (`1e+16`, `1e-6`).
pub fn zmij_format(f : Double) -> String {
  if f.is_nan() {
    return "NaN"
  }
  if f.is_inf() {
    return if f > 0.0 { "inf" } else { "-inf" }
  }
  let (negative, digits, exp) = shortest_decimal(f)
  let sb = StringBuilder()
  if negative {
    sb.write_char('-')
  }
  if digits == "0" {
    sb.write_string("0.0")
    return sb.to_string()
  }
  let n = digits.length()
  if exp >= -5 && exp <= 15 {
    if n - 1 <= exp {
      // 1234e7 -> 12340000000.0
      sb.write_string(digits)
      for _ in 0..<(exp - (n - 1)) {
        sb.write_char('0')
      }
      sb.write_string(".0")
    } else if exp >= 0 {
      // 1234e-2 -> 12.34
      sb.write_string(digits[:exp + 1].to_owned())
      sb.write_char('.')
      sb.write_string(digits[exp + 1:].to_owned())
    } else {
      // 1234e-6 -> 0.001234
      sb.write_string("0.")
      for _ in 0..<(-exp - 1) {
        sb.write_char('0')
      }
      sb.write_string(digits)
    }
    return sb.to_string()
  }
  // 1234e30 -> 1.234e+33
  sb.write_string(digits[:1].to_owned())
  if n > 1 {
    sb.write_char('.')
    sb.write_string(digits[1:].to_owned())
  }
  sb.write_char('e')
  sb.write_char(if exp >= 0 { '+' } else { '-' })
  sb.write_string(exp.abs().to_string())
  sb.to_string()
}

///|
/// Rust's `<str as Debug>::fmt`.
pub fn rust_debug_str(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '\u{0}' => sb.write_string("\\0")
      '\t' => sb.write_string("\\t")
      '\r' => sb.write_string("\\r")
      '\n' => sb.write_string("\\n")
      '\\' => sb.write_string("\\\\")
      '"' => sb.write_string("\\\"")
      c =>
        if rust_debug_escapes(c) {
          sb.write_string("\\u{")
          sb.write_string(c.to_int().to_string(radix=16))
          sb.write_char('}')
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// Whether `<str as Debug>::fmt` writes `c` as a `\u{...}` escape (it is
/// not printable, or it is a grapheme extender).
fn rust_debug_escapes(c : Char) -> Bool {
  let cp = c.to_int()
  if cp >= 0x20 && cp < 0x7f {
    return false
  }
  let ranges = rust_debug_escaped_ranges
  let mut lo = 0
  let mut hi = ranges.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let (start, end) = ranges[mid]
    if cp < start {
      hi = mid
    } else if cp > end {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}
