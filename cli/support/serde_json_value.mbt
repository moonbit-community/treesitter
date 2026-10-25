// Port of serde_json 1.0.154 src/value/mod.rs and src/number.rs (without
// `arbitrary_precision`): `Value` keeps serde_json's three number
// representations, and objects keep their insertion order
// (`preserve_order`).

///|
/// `serde_json::Number`.
pub(all) enum Number {
  PosInt(UInt64)
  /// Always less than zero.
  NegInt(Int64)
  /// Always finite.
  Float(Double)
} derive(Eq, Debug)

///|
/// `serde_json::Value`.
pub(all) enum Value {
  Null
  Bool(Bool)
  Number(Number)
  String(String)
  Array(Array[Value])
  Object(Map[String, Value])
} derive(Eq, Debug)

///|
/// `Number::as_u64`.
pub fn Number::as_u64(self : Number) -> UInt64? {
  match self {
    PosInt(n) => Some(n)
    NegInt(_) | Float(_) => None
  }
}

///|
/// `From<i64> for Number`.
pub fn Number::from_i64(i : Int64) -> Number {
  if i < 0L {
    NegInt(i)
  } else {
    PosInt(i.reinterpret_as_uint64())
  }
}

///|
/// `Number::from_f64`: `None` for infinite and NaN values.
pub fn Number::from_f64(f : Double) -> Number? {
  if f.is_nan() || f.is_inf() {
    None
  } else {
    Some(Float(f))
  }
}

///|
/// `Number::unexpected`.
fn Number::unexpected(self : Number) -> Unexpected {
  match self {
    PosInt(u) => Unsigned(u)
    NegInt(i) => Signed(i)
    Float(f) => Float(f)
  }
}

///|
/// `Display for Number` (and the serializer): integers with `itoa`, floats
/// with `zmij`.
pub impl Show for Number with fn output(self, logger) {
  match self {
    PosInt(u) => logger.write_string(u.to_string())
    NegInt(i) => logger.write_string(i.to_string())
    Float(f) => logger.write_string(zmij_format(f))
  }
}

///|
/// `Value::unexpected`.
fn Value::unexpected(self : Value) -> Unexpected {
  match self {
    Null => Unit
    Bool(b) => Bool(b)
    Number(n) => n.unexpected()
    String(s) => Str(s)
    Array(_) => Seq
    Object(_) => Map
  }
}

///|
/// The value as a core `Json`, with each number's serde_json text as its
/// `repr`, so that `to_string`/`to_string_pretty` print it as serde_json
/// does.
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Number(PosInt(u)) => Json::number(u.to_double(), repr=u.to_string())
    Number(NegInt(i)) => Json::number(i.to_double(), repr=i.to_string())
    Number(Float(f)) => Json::number(f, repr=zmij_format(f))
    String(s) => Json::string(s)
    Array(items) => Json::array(items.map(Value::to_json))
    Object(map) => {
      let out : Map[String, Json] = Map([])
      for k, v in map {
        out[k] = v.to_json()
      }
      Json::object(out)
    }
  }
}

///|
/// `serde_json::to_value` of a core `Json` built by a serializer: a number
/// with a `repr` keeps the kind that `repr` spells, other integral numbers
/// become integers (as serde serializes Rust integers) and the rest floats.
pub fn Value::from_json(json : Json) -> Value {
  match json {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(n, repr~) => {
      if repr is Some(r) {
        if (Some(from_str(r)) catch { _ => None }) is Some(Number(number)) {
          return Number(number)
        }
      }
      if n == n.floor() && n >= 0.0 && n < 18446744073709551616.0 {
        Number(PosInt(n.to_uint64()))
      } else if n == n.floor() && n < 0.0 && n >= -9223372036854775808.0 {
        Number(NegInt(n.to_int64()))
      } else {
        match Number::from_f64(n) {
          Some(number) => Number(number)
          None => Null
        }
      }
    }
    String(s) => String(s)
    Array(items) => Array(items.map(Value::from_json))
    Object(map) => {
      let out : Map[String, Value] = Map([])
      for k, v in map {
        out[k] = Value::from_json(v)
      }
      Object(out)
    }
  }
}

///|
/// `serde_json::to_string_pretty` of a `Value`.
pub fn Value::to_string_pretty(self : Value) -> String {
  to_string_pretty(self.to_json())
}
