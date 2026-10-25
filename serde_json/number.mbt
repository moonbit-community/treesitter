// Port of the number parsing of serde_json 1.0.154 src/de.rs (without the
// `float_roundtrip` and `arbitrary_precision` features).

///|
/// `ParserNumber`: a JSON number as serde_json classifies it. A `-` integer
/// is `I64` when it is negative and fits, and otherwise (`-0` among them) an
/// `F64`; a positive one is `U64` when it fits, and otherwise an `F64`.
pub(all) enum ParserNumber {
  F64(Double)
  U64(UInt64)
  I64(Int64)
} derive(Eq, Debug)

///|
fn[T] ParserNumber::visit(
  self : ParserNumber,
  visitor : Visitor[T],
) -> T raise JsonError {
  match self {
    F64(x) => visitor.f64(x)
    U64(x) => visitor.u64(x)
    I64(x) => visitor.i64(x)
  }
}

///|
fn ParserNumber::invalid_type(
  self : ParserNumber,
  expected : String,
) -> JsonError {
  match self {
    F64(x) => invalid_type(Unexpected::Float(x), expected)
    U64(x) => invalid_type(Unexpected::Unsigned(x), expected)
    I64(x) => invalid_type(Unexpected::Signed(x), expected)
  }
}

///|
/// `overflow!(a * 10 + b, u64::MAX)`.
fn overflows_u64(a : UInt64, b : UInt64) -> Bool {
  let c = 0xFFFFFFFFFFFFFFFFUL
  a >= c / 10 && (a > c / 10 || b > c % 10)
}

///|
/// `overflow!(a * 10 + b, i32::MAX)`.
fn overflows_i32(a : Int32, b : Int32) -> Bool {
  let c = 2147483647
  a >= c / 10 && (a > c / 10 || b > c % 10)
}

///|
fn Deserializer::parse_any_number(
  self : Deserializer,
  positive : Bool,
) -> ParserNumber raise JsonError {
  self.parse_integer(positive)
}

///|
fn Deserializer::parse_integer(
  self : Deserializer,
  positive : Bool,
) -> ParserNumber raise JsonError {
  guard self.next_char() is Some(next) else {
    raise self.error(EofWhileParsingValue)
  }
  match next {
    b'0' =>
      // There can be only one leading '0'.
      match self.peek_or_null() {
        b'0'..<=b'9' => raise self.peek_error(InvalidNumber)
        _ => self.parse_number(positive, 0)
      }
    b'1'..<=b'9' => {
      let mut significand = (next.to_int() - '0'.to_int()).to_uint64()
      for ;; {
        match self.peek_or_null() {
          b'0'..<=b'9' as c => {
            let digit = (c.to_int() - '0'.to_int()).to_uint64()
            // We need to be careful with overflow. If we can, try to keep
            // the number as a `u64` until we grow too large. At that point,
            // switch to parsing the value as a `f64`.
            if overflows_u64(significand, digit) {
              return F64(self.parse_long_integer(positive, significand))
            }
            self.eat_char()
            significand = significand * 10 + digit
          }
          _ => return self.parse_number(positive, significand)
        }
      }
    }
    _ => raise self.error(InvalidNumber)
  }
}

///|
fn Deserializer::parse_number(
  self : Deserializer,
  positive : Bool,
  significand : UInt64,
) -> ParserNumber raise JsonError {
  match self.peek_or_null() {
    b'.' => F64(self.parse_decimal(positive, significand, 0))
    b'e' | b'E' => F64(self.parse_exponent(positive, significand, 0))
    _ =>
      if positive {
        U64(significand)
      } else {
        let neg = -significand.reinterpret_as_int64()
        // Convert into a float if we underflow, or on `-0`.
        if neg >= 0L {
          F64(-significand.to_double())
        } else {
          I64(neg)
        }
      }
  }
}

///|
fn Deserializer::parse_decimal(
  self : Deserializer,
  positive : Bool,
  significand : UInt64,
  exponent_before_decimal_point : Int32,
) -> Double raise JsonError {
  self.eat_char()
  let mut significand = significand
  let mut exponent_after_decimal_point = 0
  while self.peek_or_null() is (b'0'..<=b'9' as c) {
    let digit = (c.to_int() - '0'.to_int()).to_uint64()
    if overflows_u64(significand, digit) {
      let exponent = exponent_before_decimal_point +
        exponent_after_decimal_point
      return self.parse_decimal_overflow(positive, significand, exponent)
    }
    self.eat_char()
    significand = significand * 10 + digit
    exponent_after_decimal_point -= 1
  }
  // Error if there is not at least one digit after the decimal point.
  if exponent_after_decimal_point == 0 {
    match self.peek() {
      Some(_) => raise self.peek_error(InvalidNumber)
      None => raise self.peek_error(EofWhileParsingValue)
    }
  }
  let exponent = exponent_before_decimal_point + exponent_after_decimal_point
  match self.peek_or_null() {
    b'e' | b'E' => self.parse_exponent(positive, significand, exponent)
    _ => self.f64_from_parts(positive, significand, exponent)
  }
}

///|
fn Deserializer::parse_exponent(
  self : Deserializer,
  positive : Bool,
  significand : UInt64,
  starting_exp : Int32,
) -> Double raise JsonError {
  self.eat_char()
  let positive_exp = match self.peek_or_null() {
    b'+' => {
      self.eat_char()
      true
    }
    b'-' => {
      self.eat_char()
      false
    }
    _ => true
  }
  guard self.next_char() is Some(next) else {
    raise self.error(EofWhileParsingValue)
  }
  // Make sure a digit follows the exponent place.
  let mut exp = match next {
    b'0'..<=b'9' => next.to_int() - '0'.to_int()
    _ => raise self.error(InvalidNumber)
  }
  while self.peek_or_null() is (b'0'..<=b'9' as c) {
    self.eat_char()
    let digit = c.to_int() - '0'.to_int()
    if overflows_i32(exp, digit) {
      let zero_significand = significand == 0
      return self.parse_exponent_overflow(
        positive, zero_significand, positive_exp,
      )
    }
    exp = exp * 10 + digit
  }
  let final_exp = if positive_exp {
    saturating_add(starting_exp, exp)
  } else {
    saturating_sub(starting_exp, exp)
  }
  self.f64_from_parts(positive, significand, final_exp)
}

///|
fn saturating_add(a : Int32, b : Int32) -> Int32 {
  let r = a.to_int64() + b.to_int64()
  if r > 2147483647L {
    2147483647
  } else if r < -2147483648L {
    -2147483648
  } else {
    r.to_int()
  }
}

///|
fn saturating_sub(a : Int32, b : Int32) -> Int32 {
  let r = a.to_int64() - b.to_int64()
  if r > 2147483647L {
    2147483647
  } else if r < -2147483648L {
    -2147483648
  } else {
    r.to_int()
  }
}

///|
/// `f64_from_parts` without `float_roundtrip`: the significand scaled by
/// powers of ten, which is not always correctly rounded.
fn Deserializer::f64_from_parts(
  self : Deserializer,
  positive : Bool,
  significand : UInt64,
  exponent : Int32,
) -> Double raise JsonError {
  let mut f = significand.to_double()
  let mut exponent = exponent
  for ;; {
    // `exponent.wrapping_abs() as usize`
    let index = if exponent == -2147483648 { -1 } else { exponent.abs() }
    if index >= 0 && index < pow10.length() {
      let pow = pow10[index]
      if exponent >= 0 {
        f = f * pow
        if f.is_inf() {
          raise self.error(NumberOutOfRange)
        }
      } else {
        f = f / pow
      }
      break
    }
    if f == 0.0 {
      break
    }
    if exponent >= 0 {
      raise self.error(NumberOutOfRange)
    }
    f = f / 1.0e308
    exponent += 308
  }
  if positive {
    f
  } else {
    -f
  }
}

///|
/// `parse_long_integer` without `float_roundtrip`: the digits that do not fit
/// the significand only scale it.
fn Deserializer::parse_long_integer(
  self : Deserializer,
  positive : Bool,
  significand : UInt64,
) -> Double raise JsonError {
  let mut exponent = 0
  for ;; {
    match self.peek_or_null() {
      b'0'..<=b'9' => {
        self.eat_char()
        // This could overflow... if your integer is gigabytes long.
        // Ignore that possibility.
        exponent += 1
      }
      b'.' => return self.parse_decimal(positive, significand, exponent)
      b'e' | b'E' => return self.parse_exponent(positive, significand, exponent)
      _ => return self.f64_from_parts(positive, significand, exponent)
    }
  }
}

///|
/// `parse_decimal_overflow` without `float_roundtrip`: the remaining digits
/// are ignored.
fn Deserializer::parse_decimal_overflow(
  self : Deserializer,
  positive : Bool,
  significand : UInt64,
  exponent : Int32,
) -> Double raise JsonError {
  // The next multiply/add would overflow, so just ignore all further
  // digits.
  while self.peek_or_null() is (b'0'..<=b'9') {
    self.eat_char()
  }
  match self.peek_or_null() {
    b'e' | b'E' => self.parse_exponent(positive, significand, exponent)
    _ => self.f64_from_parts(positive, significand, exponent)
  }
}

///|
fn Deserializer::parse_exponent_overflow(
  self : Deserializer,
  positive : Bool,
  zero_significand : Bool,
  positive_exp : Bool,
) -> Double raise JsonError {
  // Error instead of +/- infinity.
  if !zero_significand && positive_exp {
    raise self.error(NumberOutOfRange)
  }
  while self.peek_or_null() is (b'0'..<=b'9') {
    self.eat_char()
  }
  if positive {
    0.0
  } else {
    -0.0
  }
}

///|
/// `POW10`: 1e0 to 1e308.
let pow10 : FixedArray[Double] = [
  1.0e0, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7, 1.0e8, 1.0e9, 1.0e10, 1.0e11,
  1.0e12, 1.0e13, 1.0e14, 1.0e15, 1.0e16, 1.0e17, 1.0e18, 1.0e19, 1.0e20, 1.0e21,
  1.0e22, 1.0e23, 1.0e24, 1.0e25, 1.0e26, 1.0e27, 1.0e28, 1.0e29, 1.0e30, 1.0e31,
  1.0e32, 1.0e33, 1.0e34, 1.0e35, 1.0e36, 1.0e37, 1.0e38, 1.0e39, 1.0e40, 1.0e41,
  1.0e42, 1.0e43, 1.0e44, 1.0e45, 1.0e46, 1.0e47, 1.0e48, 1.0e49, 1.0e50, 1.0e51,
  1.0e52, 1.0e53, 1.0e54, 1.0e55, 1.0e56, 1.0e57, 1.0e58, 1.0e59, 1.0e60, 1.0e61,
  1.0e62, 1.0e63, 1.0e64, 1.0e65, 1.0e66, 1.0e67, 1.0e68, 1.0e69, 1.0e70, 1.0e71,
  1.0e72, 1.0e73, 1.0e74, 1.0e75, 1.0e76, 1.0e77, 1.0e78, 1.0e79, 1.0e80, 1.0e81,
  1.0e82, 1.0e83, 1.0e84, 1.0e85, 1.0e86, 1.0e87, 1.0e88, 1.0e89, 1.0e90, 1.0e91,
  1.0e92, 1.0e93, 1.0e94, 1.0e95, 1.0e96, 1.0e97, 1.0e98, 1.0e99, 1.0e100, 1.0e101,
  1.0e102, 1.0e103, 1.0e104, 1.0e105, 1.0e106, 1.0e107, 1.0e108, 1.0e109, 1.0e110,
  1.0e111, 1.0e112, 1.0e113, 1.0e114, 1.0e115, 1.0e116, 1.0e117, 1.0e118, 1.0e119,
  1.0e120, 1.0e121, 1.0e122, 1.0e123, 1.0e124, 1.0e125, 1.0e126, 1.0e127, 1.0e128,
  1.0e129, 1.0e130, 1.0e131, 1.0e132, 1.0e133, 1.0e134, 1.0e135, 1.0e136, 1.0e137,
  1.0e138, 1.0e139, 1.0e140, 1.0e141, 1.0e142, 1.0e143, 1.0e144, 1.0e145, 1.0e146,
  1.0e147, 1.0e148, 1.0e149, 1.0e150, 1.0e151, 1.0e152, 1.0e153, 1.0e154, 1.0e155,
  1.0e156, 1.0e157, 1.0e158, 1.0e159, 1.0e160, 1.0e161, 1.0e162, 1.0e163, 1.0e164,
  1.0e165, 1.0e166, 1.0e167, 1.0e168, 1.0e169, 1.0e170, 1.0e171, 1.0e172, 1.0e173,
  1.0e174, 1.0e175, 1.0e176, 1.0e177, 1.0e178, 1.0e179, 1.0e180, 1.0e181, 1.0e182,
  1.0e183, 1.0e184, 1.0e185, 1.0e186, 1.0e187, 1.0e188, 1.0e189, 1.0e190, 1.0e191,
  1.0e192, 1.0e193, 1.0e194, 1.0e195, 1.0e196, 1.0e197, 1.0e198, 1.0e199, 1.0e200,
  1.0e201, 1.0e202, 1.0e203, 1.0e204, 1.0e205, 1.0e206, 1.0e207, 1.0e208, 1.0e209,
  1.0e210, 1.0e211, 1.0e212, 1.0e213, 1.0e214, 1.0e215, 1.0e216, 1.0e217, 1.0e218,
  1.0e219, 1.0e220, 1.0e221, 1.0e222, 1.0e223, 1.0e224, 1.0e225, 1.0e226, 1.0e227,
  1.0e228, 1.0e229, 1.0e230, 1.0e231, 1.0e232, 1.0e233, 1.0e234, 1.0e235, 1.0e236,
  1.0e237, 1.0e238, 1.0e239, 1.0e240, 1.0e241, 1.0e242, 1.0e243, 1.0e244, 1.0e245,
  1.0e246, 1.0e247, 1.0e248, 1.0e249, 1.0e250, 1.0e251, 1.0e252, 1.0e253, 1.0e254,
  1.0e255, 1.0e256, 1.0e257, 1.0e258, 1.0e259, 1.0e260, 1.0e261, 1.0e262, 1.0e263,
  1.0e264, 1.0e265, 1.0e266, 1.0e267, 1.0e268, 1.0e269, 1.0e270, 1.0e271, 1.0e272,
  1.0e273, 1.0e274, 1.0e275, 1.0e276, 1.0e277, 1.0e278, 1.0e279, 1.0e280, 1.0e281,
  1.0e282, 1.0e283, 1.0e284, 1.0e285, 1.0e286, 1.0e287, 1.0e288, 1.0e289, 1.0e290,
  1.0e291, 1.0e292, 1.0e293, 1.0e294, 1.0e295, 1.0e296, 1.0e297, 1.0e298, 1.0e299,
  1.0e300, 1.0e301, 1.0e302, 1.0e303, 1.0e304, 1.0e305, 1.0e306, 1.0e307, 1.0e308,
]
