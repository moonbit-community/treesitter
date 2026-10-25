// Port of serde_json 1.0.154 src/de.rs: `Deserializer<StrRead>` (without
// the `float_roundtrip`, `arbitrary_precision`, `raw_value` and
// `unbounded_depth` features), its `SeqAccess`/`MapAccess`/`MapKey`, and
// `from_str`. Serde's visitors are the closures passed to the
// `deserialize_*` methods (serde.mbt); a visitor method a closure does not
// cover is serde's default, an `invalid_type` error.

///|
/// `serde_json::Deserializer<StrRead>`.
pub struct JsonDeserializer {
  priv read : SliceRead
  priv mut remaining_depth : Int32
}

///|
fn JsonDeserializer::new(read : SliceRead) -> JsonDeserializer {
  { read, remaining_depth: 128, }
}

///|
priv enum ParserNumber {
  F64(Double)
  U64(UInt64)
  I64(Int64)
}

///|
fn ParserNumber::unexpected(self : ParserNumber) -> Unexpected {
  match self {
    F64(x) => Float(x)
    U64(x) => Unsigned(x)
    I64(x) => Signed(x)
  }
}

///|
fn ParserNumber::invalid_type(
  self : ParserNumber,
  exp : String,
) -> SerdeJsonError {
  SerdeJsonError::invalid_type(self.unexpected(), exp)
}

///|
/// The `Deserializer::end` method should be called after a value has been
/// fully deserialized. This allows the `Deserializer` to validate that the
/// input stream is at the end or that it only has trailing whitespace.
fn JsonDeserializer::end(self : JsonDeserializer) -> Unit raise SerdeJsonError {
  if self.parse_whitespace() is Some(_) {
    raise self.peek_error(TrailingCharacters)
  }
}

///|
fn JsonDeserializer::peek(self : JsonDeserializer) -> Byte? {
  self.read.peek()
}

///|
fn JsonDeserializer::peek_or_null(self : JsonDeserializer) -> Byte {
  self.peek().unwrap_or(b'\x00')
}

///|
fn JsonDeserializer::eat_char(self : JsonDeserializer) -> Unit {
  self.read.discard()
}

///|
fn JsonDeserializer::next_char(self : JsonDeserializer) -> Byte? {
  self.read.next()
}

///|
fn JsonDeserializer::next_char_or_null(self : JsonDeserializer) -> Byte {
  self.next_char().unwrap_or(b'\x00')
}

///|
/// Error caused by a byte from next_char().
fn JsonDeserializer::error(
  self : JsonDeserializer,
  reason : ErrorCode,
) -> SerdeJsonError {
  let position = self.read.position()
  SerdeJsonError::syntax(reason, position.line, position.column)
}

///|
/// Error caused by a byte from peek().
fn JsonDeserializer::peek_error(
  self : JsonDeserializer,
  reason : ErrorCode,
) -> SerdeJsonError {
  let position = self.read.peek_position()
  SerdeJsonError::syntax(reason, position.line, position.column)
}

///|
/// Returns the first non-whitespace byte without consuming it, or `None` if
/// EOF is encountered.
fn JsonDeserializer::parse_whitespace(self : JsonDeserializer) -> Byte? {
  for ;; {
    match self.peek() {
      Some(b' ' | b'\n' | b'\t' | b'\r') => self.eat_char()
      other => return other
    }
  }
}

///|
fn JsonDeserializer::peek_invalid_type(
  self : JsonDeserializer,
  exp : String,
) -> SerdeJsonError {
  let err = match self.peek_or_null() {
    b'n' => {
      self.eat_char()
      self.parse_ident(b"ull") catch {
        err => return err
      }
      SerdeJsonError::invalid_type(Unit, exp)
    }
    b't' => {
      self.eat_char()
      self.parse_ident(b"rue") catch {
        err => return err
      }
      SerdeJsonError::invalid_type(Bool(true), exp)
    }
    b'f' => {
      self.eat_char()
      self.parse_ident(b"alse") catch {
        err => return err
      }
      SerdeJsonError::invalid_type(Bool(false), exp)
    }
    b'-' => {
      self.eat_char()
      match (Ok(self.parse_any_number(false)) catch { e => Err(e) }) {
        Ok(n) => n.invalid_type(exp)
        Err(err) => return err
      }
    }
    b'0'..<=b'9' =>
      match (Ok(self.parse_any_number(true)) catch { e => Err(e) }) {
        Ok(n) => n.invalid_type(exp)
        Err(err) => return err
      }
    b'"' => {
      self.eat_char()
      match (Ok(self.read.parse_str()) catch { e => Err(e) }) {
        Ok(s) => SerdeJsonError::invalid_type(Str(s), exp)
        Err(err) => return err
      }
    }
    b'[' => SerdeJsonError::invalid_type(Seq, exp)
    b'{' => SerdeJsonError::invalid_type(Map, exp)
    _ => self.peek_error(ExpectedSomeValue)
  }
  self.fix_position(err)
}

///|
fn JsonDeserializer::fix_position(
  self : JsonDeserializer,
  err : SerdeJsonError,
) -> SerdeJsonError {
  err.fix_position(code => self.error(code))
}

///|
/// Run a `deserialize_*` body; errors without a position get the current
/// one (`Err(err) => Err(self.fix_position(err))`).
fn[T] JsonDeserializer::fixing(
  self : JsonDeserializer,
  body : () -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  body() catch {
    err => raise self.fix_position(err)
  }
}

///|
fn JsonDeserializer::parse_ident(
  self : JsonDeserializer,
  ident : Bytes,
) -> Unit raise SerdeJsonError {
  for expected in ident {
    match self.next_char() {
      None => raise self.error(EofWhileParsingValue)
      Some(next) => if next != expected { raise self.error(ExpectedSomeIdent) }
    }
  }
}

///|
/// `overflow!(a * 10 + b, c)`.
fn overflow_u64(a : UInt64, b : UInt64) -> Bool {
  let c = 0xFFFF_FFFF_FFFF_FFFFUL
  a >= c / 10UL && (a > c / 10UL || b > c % 10UL)
}

///|
fn JsonDeserializer::parse_integer(
  self : JsonDeserializer,
  positive : Bool,
) -> ParserNumber raise SerdeJsonError {
  let next = match self.next_char() {
    Some(b) => b
    None => raise self.error(EofWhileParsingValue)
  }
  match next {
    b'0' =>
      // There can be only one leading '0'.
      match self.peek_or_null() {
        b'0'..<=b'9' => raise self.peek_error(InvalidNumber)
        _ => self.parse_number(positive, 0UL)
      }
    b'1'..<=b'9' => {
      let mut significand = (next - b'0').to_uint64()
      for ;; {
        match self.peek_or_null() {
          b'0'..<=b'9' as c => {
            let digit = (c - b'0').to_uint64()
            // We need to be careful with overflow. If we can, try to keep
            // the number as a `u64` until we grow too large. At that point,
            // switch to parsing the value as a `f64`.
            if overflow_u64(significand, digit) {
              return F64(self.parse_long_integer(positive, significand))
            }
            self.eat_char()
            significand = significand * 10UL + digit
          }
          _ => return self.parse_number(positive, significand)
        }
      }
    }
    _ => raise self.error(InvalidNumber)
  }
}

///|
fn JsonDeserializer::parse_number(
  self : JsonDeserializer,
  positive : Bool,
  significand : UInt64,
) -> ParserNumber raise SerdeJsonError {
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
fn JsonDeserializer::parse_decimal(
  self : JsonDeserializer,
  positive : Bool,
  significand : UInt64,
  exponent_before_decimal_point : Int32,
) -> Double raise SerdeJsonError {
  self.eat_char()
  let mut significand = significand
  let mut exponent_after_decimal_point = 0
  while self.peek_or_null() is (b'0'..<=b'9' as c) {
    let digit = (c - b'0').to_uint64()
    if overflow_u64(significand, digit) {
      let exponent = exponent_before_decimal_point +
        exponent_after_decimal_point
      return self.parse_decimal_overflow(positive, significand, exponent)
    }
    self.eat_char()
    significand = significand * 10UL + digit
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
/// `i32::saturating_add`.
fn saturating_add_i32(a : Int32, b : Int32) -> Int32 {
  let r = a.to_int64() + b.to_int64()
  if r > 0x7FFFFFFFL {
    0x7FFFFFFF
  } else if r < -0x80000000L {
    -0x80000000
  } else {
    r.to_int()
  }
}

///|
fn JsonDeserializer::parse_exponent(
  self : JsonDeserializer,
  positive : Bool,
  significand : UInt64,
  starting_exp : Int32,
) -> Double raise SerdeJsonError {
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
  let next = match self.next_char() {
    Some(b) => b
    None => raise self.error(EofWhileParsingValue)
  }
  // Make sure a digit follows the exponent place.
  let mut exp = match next {
    b'0'..<=b'9' => (next - b'0').to_int()
    _ => raise self.error(InvalidNumber)
  }
  while self.peek_or_null() is (b'0'..<=b'9' as c) {
    self.eat_char()
    let digit = (c - b'0').to_int()
    // `overflow!(exp * 10 + digit, i32::MAX)`.
    let max = 0x7FFFFFFF
    if exp >= max / 10 && (exp > max / 10 || digit > max % 10) {
      let zero_significand = significand == 0UL
      return self.parse_exponent_overflow(
        positive, zero_significand, positive_exp,
      )
    }
    exp = exp * 10 + digit
  }
  let final_exp = if positive_exp {
    saturating_add_i32(starting_exp, exp)
  } else {
    saturating_add_i32(starting_exp, -exp)
  }
  self.f64_from_parts(positive, significand, final_exp)
}

///|
/// `POW10`: `1e0` to `1e308`.
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

///|
fn JsonDeserializer::f64_from_parts(
  self : JsonDeserializer,
  positive : Bool,
  significand : UInt64,
  exponent : Int32,
) -> Double raise SerdeJsonError {
  let mut f = significand.to_double()
  let mut exponent = exponent
  for ;; {
    // `POW10.get(exponent.wrapping_abs() as usize)`.
    let index = if exponent == -0x80000000 { -1 } else { exponent.abs() }
    if index >= 0 && index < pow10.length() {
      let pow = pow10[index]
      if exponent >= 0 {
        f *= pow
        if f.is_inf() {
          raise self.error(NumberOutOfRange)
        }
      } else {
        f /= pow
      }
      break
    } else {
      if f == 0.0 {
        break
      }
      if exponent >= 0 {
        raise self.error(NumberOutOfRange)
      }
      f /= 1.0e308
      exponent += 308
    }
  }
  if positive {
    f
  } else {
    -f
  }
}

///|
fn JsonDeserializer::parse_long_integer(
  self : JsonDeserializer,
  positive : Bool,
  significand : UInt64,
) -> Double raise SerdeJsonError {
  let mut exponent = 0
  for ;; {
    match self.peek_or_null() {
      b'0'..<=b'9' => {
        self.eat_char()
        // This could overflow... if your integer is gigabytes long. Ignore
        // that possibility.
        exponent += 1
      }
      b'.' => return self.parse_decimal(positive, significand, exponent)
      b'e' | b'E' => return self.parse_exponent(positive, significand, exponent)
      _ => return self.f64_from_parts(positive, significand, exponent)
    }
  }
}

///|
fn JsonDeserializer::parse_decimal_overflow(
  self : JsonDeserializer,
  positive : Bool,
  significand : UInt64,
  exponent : Int32,
) -> Double raise SerdeJsonError {
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
fn JsonDeserializer::parse_exponent_overflow(
  self : JsonDeserializer,
  positive : Bool,
  zero_significand : Bool,
  positive_exp : Bool,
) -> Double raise SerdeJsonError {
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
fn JsonDeserializer::parse_any_number(
  self : JsonDeserializer,
  positive : Bool,
) -> ParserNumber raise SerdeJsonError {
  self.parse_integer(positive)
}

///|
fn JsonDeserializer::parse_object_colon(
  self : JsonDeserializer,
) -> Unit raise SerdeJsonError {
  match self.parse_whitespace() {
    Some(b':') => self.eat_char()
    Some(_) => raise self.peek_error(ExpectedColon)
    None => raise self.peek_error(EofWhileParsingObject)
  }
}

///|
fn JsonDeserializer::end_seq(
  self : JsonDeserializer,
) -> Unit raise SerdeJsonError {
  match self.parse_whitespace() {
    Some(b']') => self.eat_char()
    Some(b',') => {
      self.eat_char()
      match self.parse_whitespace() {
        Some(b']') => raise self.peek_error(TrailingComma)
        _ => raise self.peek_error(TrailingCharacters)
      }
    }
    Some(_) => raise self.peek_error(TrailingCharacters)
    None => raise self.peek_error(EofWhileParsingList)
  }
}

///|
fn JsonDeserializer::end_map(
  self : JsonDeserializer,
) -> Unit raise SerdeJsonError {
  match self.parse_whitespace() {
    Some(b'}') => self.eat_char()
    Some(b',') => raise self.peek_error(TrailingComma)
    Some(_) => raise self.peek_error(TrailingCharacters)
    None => raise self.peek_error(EofWhileParsingObject)
  }
}

///|
fn JsonDeserializer::ignore_value(
  self : JsonDeserializer,
) -> Unit raise SerdeJsonError {
  let scratch : Array[Byte] = []
  let mut enclosing : Byte? = None
  for ;; {
    let peek = match self.parse_whitespace() {
      Some(b) => b
      None => raise self.peek_error(EofWhileParsingValue)
    }
    let frame = match peek {
      b'n' => {
        self.eat_char()
        self.parse_ident(b"ull")
        None
      }
      b't' => {
        self.eat_char()
        self.parse_ident(b"rue")
        None
      }
      b'f' => {
        self.eat_char()
        self.parse_ident(b"alse")
        None
      }
      b'-' => {
        self.eat_char()
        self.ignore_integer()
        None
      }
      b'0'..<=b'9' => {
        self.ignore_integer()
        None
      }
      b'"' => {
        self.eat_char()
        self.read.ignore_str()
        None
      }
      b'[' | b'{' => {
        if enclosing is Some(e) {
          scratch.push(e)
        }
        enclosing = None
        self.eat_char()
        Some(peek)
      }
      _ => raise self.peek_error(ExpectedSomeValue)
    }
    let (accept_comma, frame) = match frame {
      Some(frame) => (false, frame)
      None =>
        match enclosing {
          Some(frame) => {
            enclosing = None
            (true, frame)
          }
          None =>
            match scratch.pop() {
              Some(frame) => (true, frame)
              None => return
            }
        }
    }
    let mut accept_comma = accept_comma
    let mut frame = frame
    for ;; {
      match self.parse_whitespace() {
        Some(b',') if accept_comma => {
          self.eat_char()
          break
        }
        Some(b']') if frame == b'[' => ()
        Some(b'}') if frame == b'{' => ()
        Some(_) =>
          if accept_comma {
            raise self.peek_error(
              if frame == b'[' {
                ExpectedListCommaOrEnd
              } else {
                ExpectedObjectCommaOrEnd
              },
            )
          } else {
            break
          }
        None =>
          raise self.peek_error(
            if frame == b'[' {
              EofWhileParsingList
            } else {
              EofWhileParsingObject
            },
          )
      }
      self.eat_char()
      frame = match scratch.pop() {
        Some(frame) => frame
        None => return
      }
      accept_comma = true
    }
    if frame == b'{' {
      match self.parse_whitespace() {
        Some(b'"') => self.eat_char()
        Some(_) => raise self.peek_error(KeyMustBeAString)
        None => raise self.peek_error(EofWhileParsingObject)
      }
      self.read.ignore_str()
      match self.parse_whitespace() {
        Some(b':') => self.eat_char()
        Some(_) => raise self.peek_error(ExpectedColon)
        None => raise self.peek_error(EofWhileParsingObject)
      }
    }
    enclosing = Some(frame)
  }
}

///|
fn JsonDeserializer::ignore_integer(
  self : JsonDeserializer,
) -> Unit raise SerdeJsonError {
  match self.next_char_or_null() {
    b'0' =>
      // There can be only one leading '0'.
      if self.peek_or_null() is (b'0'..<=b'9') {
        raise self.peek_error(InvalidNumber)
      }
    b'1'..<=b'9' =>
      while self.peek_or_null() is (b'0'..<=b'9') {
        self.eat_char()
      }
    _ => raise self.error(InvalidNumber)
  }
  match self.peek_or_null() {
    b'.' => self.ignore_decimal()
    b'e' | b'E' => self.ignore_exponent()
    _ => ()
  }
}

///|
fn JsonDeserializer::ignore_decimal(
  self : JsonDeserializer,
) -> Unit raise SerdeJsonError {
  self.eat_char()
  let mut at_least_one_digit = false
  while self.peek_or_null() is (b'0'..<=b'9') {
    self.eat_char()
    at_least_one_digit = true
  }
  if !at_least_one_digit {
    raise self.peek_error(InvalidNumber)
  }
  match self.peek_or_null() {
    b'e' | b'E' => self.ignore_exponent()
    _ => ()
  }
}

///|
fn JsonDeserializer::ignore_exponent(
  self : JsonDeserializer,
) -> Unit raise SerdeJsonError {
  self.eat_char()
  match self.peek_or_null() {
    b'+' | b'-' => self.eat_char()
    _ => ()
  }
  // Make sure a digit follows the exponent place.
  match self.next_char_or_null() {
    b'0'..<=b'9' => ()
    _ => raise self.error(InvalidNumber)
  }
  while self.peek_or_null() is (b'0'..<=b'9') {
    self.eat_char()
  }
}

///|
/// `check_recursion!` around `self.eat_char(); visitor.visit_seq(...)`,
/// followed by `end_seq` (the `b'['` arm of `deserialize_any`,
/// `deserialize_seq` and `deserialize_struct`).
fn[T] JsonDeserializer::visit_seq_brackets(
  self : JsonDeserializer,
  visit_seq : (SeqAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  self.remaining_depth -= 1
  if self.remaining_depth == 0 {
    raise self.peek_error(RecursionLimitExceeded)
  }
  self.eat_char()
  let ret : Result[T, SerdeJsonError] = Ok(visit_seq(SeqAccess::json(self))) catch {
    err => Err(err)
  }
  self.remaining_depth += 1
  let end : Result[Unit, SerdeJsonError] = Ok(self.end_seq()) catch {
    err => Err(err)
  }
  match (ret, end) {
    (Ok(ret), Ok(_)) => ret
    (Err(err), _) | (_, Err(err)) => raise err
  }
}

///|
/// The `b'{'` arm of `deserialize_any`, `deserialize_map` and
/// `deserialize_struct`.
fn[T] JsonDeserializer::visit_map_braces(
  self : JsonDeserializer,
  visit_map : (MapAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  self.remaining_depth -= 1
  if self.remaining_depth == 0 {
    raise self.peek_error(RecursionLimitExceeded)
  }
  self.eat_char()
  let ret : Result[T, SerdeJsonError] = Ok(visit_map(MapAccess::json(self))) catch {
    err => Err(err)
  }
  self.remaining_depth += 1
  let end : Result[Unit, SerdeJsonError] = Ok(self.end_map()) catch {
    err => Err(err)
  }
  match (ret, end) {
    (Ok(ret), Ok(_)) => ret
    (Err(err), _) | (_, Err(err)) => raise err
  }
}

///|
/// The first non-whitespace byte of the next value
/// (`EofWhileParsingValue` at the end of the input).
fn JsonDeserializer::peek_value(
  self : JsonDeserializer,
) -> Byte raise SerdeJsonError {
  match self.parse_whitespace() {
    Some(b) => b
    None => raise self.peek_error(EofWhileParsingValue)
  }
}

///|
/// `deserialize_any` with serde_json's `ValueVisitor`
/// (`Value::deserialize`).
fn JsonDeserializer::deserialize_value(
  self : JsonDeserializer,
) -> Value raise SerdeJsonError {
  let peek = self.peek_value()
  self.fixing(() => {
    match peek {
      b'n' => {
        self.eat_char()
        self.parse_ident(b"ull")
        Null
      }
      b't' => {
        self.eat_char()
        self.parse_ident(b"rue")
        Bool(true)
      }
      b'f' => {
        self.eat_char()
        self.parse_ident(b"alse")
        Bool(false)
      }
      b'-' => {
        self.eat_char()
        parser_number_value(self.parse_any_number(false))
      }
      b'0'..<=b'9' => parser_number_value(self.parse_any_number(true))
      b'"' => {
        self.eat_char()
        String(self.read.parse_str())
      }
      b'[' =>
        self.visit_seq_brackets(seq => {
          let vec = []
          while seq.next_element(Deserializer::deserialize_value) is Some(elem) {
            vec.push(elem)
          }
          Array(vec)
        })
      b'{' =>
        self.visit_map_braces(map => {
          let values : Map[String, Value] = Map([])
          while map.next_key() is Some(key) {
            values[key] = map.next_value(Deserializer::deserialize_value)
          }
          Object(values)
        })
      _ => raise self.peek_error(ExpectedSomeValue)
    }
  })
}

///|
/// `ParserNumber::visit` with `ValueVisitor`.
fn parser_number_value(n : ParserNumber) -> Value {
  match n {
    F64(x) =>
      match Number::from_f64(x) {
        Some(n) => Number(n)
        None => Null
      }
    U64(x) => Number(PosInt(x))
    I64(x) => Number(Number::from_i64(x))
  }
}

///|
/// `deserialize_str` (also `deserialize_string` and
/// `deserialize_identifier`) with a visitor accepting strings.
fn[T] JsonDeserializer::deserialize_str(
  self : JsonDeserializer,
  exp : String,
  visit_str : (String) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  let peek = self.peek_value()
  self.fixing(() => {
    match peek {
      b'"' => {
        self.eat_char()
        visit_str(self.read.parse_str())
      }
      _ => raise self.peek_invalid_type(exp)
    }
  })
}

///|
/// `deserialize_bool` with `BoolVisitor`.
fn JsonDeserializer::deserialize_bool(
  self : JsonDeserializer,
  exp : String,
) -> Bool raise SerdeJsonError {
  let peek = self.peek_value()
  self.fixing(() => {
    match peek {
      b't' => {
        self.eat_char()
        self.parse_ident(b"rue")
        true
      }
      b'f' => {
        self.eat_char()
        self.parse_ident(b"alse")
        false
      }
      _ => raise self.peek_invalid_type(exp)
    }
  })
}

///|
/// `deserialize_number` with a primitive unsigned visitor.
fn JsonDeserializer::deserialize_unsigned(
  self : JsonDeserializer,
  exp : String,
  max : UInt64,
) -> UInt64 raise SerdeJsonError {
  let peek = self.peek_value()
  self.fixing(() => {
    match peek {
      b'-' => {
        self.eat_char()
        visit_unsigned(self.parse_integer(false).unexpected(), exp, max)
      }
      b'0'..<=b'9' =>
        visit_unsigned(self.parse_integer(true).unexpected(), exp, max)
      _ => raise self.peek_invalid_type(exp)
    }
  })
}

///|
fn[T] JsonDeserializer::deserialize_option(
  self : JsonDeserializer,
  visit_some : (Deserializer) -> T raise SerdeJsonError,
) -> T? raise SerdeJsonError {
  match self.parse_whitespace() {
    Some(b'n') => {
      self.eat_char()
      self.parse_ident(b"ull")
      None
    }
    _ => Some(visit_some(FromJson(self)))
  }
}

///|
fn[T] JsonDeserializer::deserialize_seq(
  self : JsonDeserializer,
  exp : String,
  visit_seq : (SeqAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  let peek = self.peek_value()
  self.fixing(() => {
    match peek {
      b'[' => self.visit_seq_brackets(visit_seq)
      _ => raise self.peek_invalid_type(exp)
    }
  })
}

///|
fn[T] JsonDeserializer::deserialize_map(
  self : JsonDeserializer,
  exp : String,
  visit_map : (MapAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  let peek = self.peek_value()
  self.fixing(() => {
    match peek {
      b'{' => self.visit_map_braces(visit_map)
      _ => raise self.peek_invalid_type(exp)
    }
  })
}

///|
fn[T] JsonDeserializer::deserialize_struct(
  self : JsonDeserializer,
  exp : String,
  visit_seq : (SeqAccess) -> T raise SerdeJsonError,
  visit_map : (MapAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  let peek = self.peek_value()
  self.fixing(() => {
    match peek {
      b'[' => self.visit_seq_brackets(visit_seq)
      b'{' => self.visit_map_braces(visit_map)
      _ => raise self.peek_invalid_type(exp)
    }
  })
}

///|
/// `SeqAccess::next_element_seed`'s `has_next_element`.
fn JsonDeserializer::has_next_element(
  self : JsonDeserializer,
  first : Ref[Bool],
) -> Bool raise SerdeJsonError {
  let peek = match self.parse_whitespace() {
    Some(b) => b
    None => raise self.peek_error(EofWhileParsingList)
  }
  if peek == b']' {
    false
  } else if first.val {
    first.val = false
    true
  } else if peek == b',' {
    self.eat_char()
    match self.parse_whitespace() {
      Some(b']') => raise self.peek_error(TrailingComma)
      Some(_) => true
      None => raise self.peek_error(EofWhileParsingValue)
    }
  } else {
    raise self.peek_error(ExpectedListCommaOrEnd)
  }
}

///|
/// `MapAccess::next_key_seed`'s `has_next_key`.
fn JsonDeserializer::has_next_key(
  self : JsonDeserializer,
  first : Ref[Bool],
) -> Bool raise SerdeJsonError {
  let peek = match self.parse_whitespace() {
    Some(b) => b
    None => raise self.peek_error(EofWhileParsingObject)
  }
  if peek == b'}' {
    false
  } else if first.val {
    first.val = false
    if peek == b'"' {
      true
    } else {
      raise self.peek_error(KeyMustBeAString)
    }
  } else if peek == b',' {
    self.eat_char()
    match self.parse_whitespace() {
      Some(b'"') => true
      Some(b'}') => raise self.peek_error(TrailingComma)
      Some(_) => raise self.peek_error(KeyMustBeAString)
      None => raise self.peek_error(EofWhileParsingValue)
    }
  } else {
    raise self.peek_error(ExpectedObjectCommaOrEnd)
  }
}

///|
/// `MapKey::deserialize_any` with a string or field-identifier visitor.
fn JsonDeserializer::deserialize_key(
  self : JsonDeserializer,
) -> String raise SerdeJsonError {
  self.eat_char()
  self.read.parse_str()
}

///|
/// `serde_json::from_str` with the deserialization `f` (`from_trait`).
pub fn[T] from_str_with(
  s : String,
  f : (Deserializer) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  let de = JsonDeserializer::new(SliceRead::new(@utf8.encode(s)))
  let value = f(FromJson(de))
  // Make sure the whole stream has been consumed.
  de.end()
  value
}

///|
/// `serde_json::from_str::<Value>`.
pub fn from_str(s : String) -> Value raise SerdeJsonError {
  from_str_with(s, Deserializer::deserialize_value)
}
