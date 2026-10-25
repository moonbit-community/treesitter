// serde_json 1.0.154's `Value` (with the `preserve_order` feature, so objects
// keep their insertion order and a repeated key replaces the value in place,
// like `IndexMap::insert`) and its `Deserialize` impl (value/de.rs).

///|
/// `serde_json::Number`.
pub(all) enum Number {
  PosInt(UInt64)
  NegInt(Int64)
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
/// `ValueVisitor`.
fn value_visitor() -> Visitor[Value] {
  Visitor::new(
    "any valid JSON value",
    visit_bool=b => Bool(b),
    visit_i64=i => {
      Number(if i < 0L { NegInt(i) } else { PosInt(i.reinterpret_as_uint64()) })
    },
    visit_u64=u => Number(PosInt(u)),
    // `Number::from_f64`, which only fails for non-finite values.
    visit_f64=f => {
      if f.is_nan() || f.is_inf() {
        Null
      } else {
        Number(Float(f))
      }
    },
    visit_str=s => String(s),
    visit_unit=() => Null,
    visit_none=() => Null,
    visit_some=de => de.deserialize_value(),
    visit_seq=seq => {
      let vec = []
      while seq.next_element(de => de.deserialize_value()) is Some(elem) {
        vec.push(elem)
      }
      Array(vec)
    },
    visit_map=map => {
      let values : Map[String, Value] = Map([])
      while map.next_key(key => key) is Some(key) {
        values[key] = map.next_value(de => de.deserialize_value())
      }
      Object(values)
    },
  )
}

///|
/// `Value::deserialize`.
pub fn Deserializer::deserialize_value(
  self : Deserializer,
) -> Value raise JsonError {
  self.deserialize_any(value_visitor())
}

///|
/// `Map::<String, Value>::deserialize`: an object (`deserialize_map`).
pub fn Deserializer::deserialize_value_map(
  self : Deserializer,
) -> Map[String, Value] raise JsonError {
  self.deserialize_map(
    Visitor::new("a map", visit_unit=() => Map([]), visit_map=map => {
      let values : Map[String, Value] = Map([])
      while map.next_key(key => key) is Some(key) {
        values[key] = map.next_value(de => de.deserialize_value())
      }
      values
    }),
  )
}

///|
/// `Value::unexpected`.
pub fn Value::unexpected(self : Value) -> Unexpected {
  match self {
    Null => Unexpected::Unit
    Bool(b) => Unexpected::Bool(b)
    Number(PosInt(u)) => Unexpected::Unsigned(u)
    Number(NegInt(i)) => Unexpected::Signed(i)
    Number(Float(f)) => Unexpected::Float(f)
    String(s) => Unexpected::Str(s)
    Array(_) => Unexpected::Seq
    Object(_) => Unexpected::Map
  }
}

///|
/// The serde `Content` a `Value` deserializes to (`deserialize_any` with
/// serde's `ContentVisitor`).
pub fn Value::to_content(self : Value) -> Content {
  match self {
    Null => Unit
    Bool(b) => Bool(b)
    Number(PosInt(u)) => U64(u)
    Number(NegInt(i)) => I64(i)
    Number(Float(f)) => F64(f)
    String(s) => String(s)
    Array(values) => Seq(values.map(Value::to_content))
    Object(map) => {
      let pairs = []
      for key, value in map {
        pairs.push((Content::String(key), value.to_content()))
      }
      Map(pairs)
    }
  }
}
