// The parts of serde 1.0.229 that the CLI's `#[derive(Deserialize)]` types
// use, over the two deserializers serde_json provides: its text
// deserializer (`from_str`, serde_json_de.mbt) and `Value`'s
// (`from_value`, src/value/de.rs, ported here). A serde `Visitor` is
// represented by the closures passed to `Deserializer::deserialize_*`; the
// visitor methods those closures do not cover are serde's defaults, which
// fail with `invalid_type`. The `Deserialize` impls of the std types
// (`String`, `PathBuf`, `bool`, `u8`, `Option`, `Vec`, `BTreeMap`) are
// ported from serde_core src/de/impls.rs; derived struct visitors use
// `SeqAccess::next_field`, `StructField` and `deserialize_struct` the way
// serde_derive's `visit_seq` and `visit_map` do.

///|
/// A `serde::Deserializer`: `&mut serde_json::Deserializer<StrRead>` or a
/// `serde_json::Value`.
pub enum Deserializer {
  FromJson(JsonDeserializer)
  FromValue(Value)
}

///|
/// `serde::de::SeqAccess` of either deserializer.
pub struct SeqAccess {
  priv de : JsonDeserializer?
  priv first : Ref[Bool]
  priv items : Array[Value]
  priv mut pos : Int32
}

///|
fn SeqAccess::json(de : JsonDeserializer) -> SeqAccess {
  { de: Some(de), first: Ref(true), items: [], pos: 0, }
}

///|
/// `serde_json::value::de::SeqDeserializer`.
fn SeqAccess::value(items : Array[Value]) -> SeqAccess {
  { de: None, first: Ref(true), items, pos: 0, }
}

///|
/// `SeqAccess::next_element`, deserializing the element with `f`.
pub fn[T] SeqAccess::next_element(
  self : SeqAccess,
  f : (Deserializer) -> T raise SerdeJsonError,
) -> T? raise SerdeJsonError {
  match self.de {
    Some(de) =>
      if de.has_next_element(self.first) {
        Some(f(FromJson(de)))
      } else {
        None
      }
    None =>
      if self.pos < self.items.length() {
        let value = self.items[self.pos]
        self.pos += 1
        Some(f(FromValue(value)))
      } else {
        None
      }
  }
}

///|
/// A field of a derived `visit_seq`: the next element, or (when the
/// sequence ends) `invalid_length(index, &expecting)`.
pub fn[T] SeqAccess::next_field(
  self : SeqAccess,
  f : (Deserializer) -> T raise SerdeJsonError,
  index : Int32,
  expecting : String,
) -> T raise SerdeJsonError {
  match self.next_element(f) {
    Some(value) => value
    None => raise SerdeJsonError::invalid_length(index, expecting)
  }
}

///|
/// `serde::de::MapAccess` of either deserializer.
pub struct MapAccess {
  priv de : JsonDeserializer?
  priv first : Ref[Bool]
  priv entries : Array[(String, Value)]
  priv mut pos : Int32
  priv mut value : Value?
}

///|
fn MapAccess::json(de : JsonDeserializer) -> MapAccess {
  { de: Some(de), first: Ref(true), entries: [], pos: 0, value: None, }
}

///|
/// `serde_json::value::de::MapDeserializer`.
fn MapAccess::value(map : Map[String, Value]) -> MapAccess {
  { de: None, first: Ref(true), entries: map.to_array(), pos: 0, value: None, }
}

///|
/// `MapAccess::next_key` with a `String` or field-identifier seed: the key.
pub fn MapAccess::next_key(self : MapAccess) -> String? raise SerdeJsonError {
  match self.de {
    Some(de) =>
      if de.has_next_key(self.first) {
        Some(de.deserialize_key())
      } else {
        None
      }
    None =>
      if self.pos < self.entries.length() {
        let (key, value) = self.entries[self.pos]
        self.pos += 1
        self.value = Some(value)
        Some(key)
      } else {
        None
      }
  }
}

///|
/// `MapAccess::next_value`, deserializing the value with `f`.
pub fn[T] MapAccess::next_value(
  self : MapAccess,
  f : (Deserializer) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  match self.de {
    Some(de) => {
      de.parse_object_colon()
      f(FromJson(de))
    }
    None =>
      match self.value {
        Some(value) => {
          self.value = None
          f(FromValue(value))
        }
        None => raise SerdeJsonError::custom("value is missing")
      }
  }
}

///|
/// `MapAccess::next_value::<IgnoredAny>`.
pub fn MapAccess::next_value_ignored(
  self : MapAccess,
) -> Unit raise SerdeJsonError {
  self.next_value(Deserializer::deserialize_ignored_any)
}

///|
/// `serde_json::value::de::visit_array`.
fn[T] visit_array(
  array : Array[Value],
  visit_seq : (SeqAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  let len = array.length()
  let deserializer = SeqAccess::value(array)
  let seq = visit_seq(deserializer)
  let remaining = len - deserializer.pos
  if remaining == 0 {
    seq
  } else {
    raise SerdeJsonError::invalid_length(len, "fewer elements in array")
  }
}

///|
/// `Deserializer for Map<String, Value>`'s `deserialize_any`.
fn[T] visit_object(
  object : Map[String, Value],
  visit_map : (MapAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  let len = object.length()
  let deserializer = MapAccess::value(object)
  let map = visit_map(deserializer)
  let remaining = len - deserializer.pos
  if remaining == 0 {
    map
  } else {
    raise SerdeJsonError::invalid_length(len, "fewer elements in map")
  }
}

///|
/// `Value::deserialize` (`deserialize_any` with `ValueVisitor`). Also the
/// buffering of untagged enums (`Content`), which keeps the same data.
pub fn Deserializer::deserialize_value(
  self : Deserializer,
) -> Value raise SerdeJsonError {
  match self {
    FromJson(de) => de.deserialize_value()
    FromValue(value) => value
  }
}

///|
/// `deserialize_ignored_any` with `IgnoredAny`.
pub fn Deserializer::deserialize_ignored_any(
  self : Deserializer,
) -> Unit raise SerdeJsonError {
  match self {
    FromJson(de) => de.ignore_value()
    FromValue(_) => ()
  }
}

///|
/// `deserialize_str`/`deserialize_string` with a visitor that accepts
/// strings (`visit_str`) and expects `exp`.
pub fn[T] Deserializer::deserialize_str(
  self : Deserializer,
  exp : String,
  visit_str : (String) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  match self {
    FromJson(de) => de.deserialize_str(exp, visit_str)
    FromValue(String(s)) => visit_str(s)
    FromValue(value) =>
      raise SerdeJsonError::invalid_type(value.unexpected(), exp)
  }
}

///|
/// `bool::deserialize` (`deserialize_bool` with `BoolVisitor`).
pub fn Deserializer::deserialize_bool(
  self : Deserializer,
) -> Bool raise SerdeJsonError {
  let exp = "a boolean"
  match self {
    FromJson(de) => de.deserialize_bool(exp)
    FromValue(Bool(b)) => b
    FromValue(value) =>
      raise SerdeJsonError::invalid_type(value.unexpected(), exp)
  }
}

///|
/// The `visit_u64`/`visit_i64`/`visit_f64` of a primitive unsigned integer
/// visitor whose maximum is `max` (`uint_to_self!`, `int_to_uint!`; floats
/// are an invalid type).
fn visit_unsigned(
  n : Unexpected,
  exp : String,
  max : UInt64,
) -> UInt64 raise SerdeJsonError {
  match n {
    Unsigned(v) =>
      if v <= max {
        v
      } else {
        raise SerdeJsonError::invalid_value(n, exp)
      }
    Signed(v) =>
      if v >= 0L && v.reinterpret_as_uint64() <= max {
        v.reinterpret_as_uint64()
      } else {
        raise SerdeJsonError::invalid_value(n, exp)
      }
    _ => raise SerdeJsonError::invalid_type(n, exp)
  }
}

///|
/// `u8::deserialize`.
pub fn Deserializer::deserialize_u8(
  self : Deserializer,
) -> Byte raise SerdeJsonError {
  let exp = "u8"
  let max = 255UL
  let v = match self {
    FromJson(de) => de.deserialize_unsigned(exp, max)
    FromValue(Number(n)) => visit_unsigned(n.unexpected(), exp, max)
    FromValue(value) =>
      raise SerdeJsonError::invalid_type(value.unexpected(), exp)
  }
  v.to_byte()
}

///|
/// `Option::<T>::deserialize` (`deserialize_option` with `OptionVisitor`),
/// deserializing the inner value with `visit_some`.
pub fn[T] Deserializer::deserialize_option(
  self : Deserializer,
  visit_some : (Deserializer) -> T raise SerdeJsonError,
) -> T? raise SerdeJsonError {
  match self {
    FromJson(de) => de.deserialize_option(visit_some)
    FromValue(Null) => None
    FromValue(_) => Some(visit_some(self))
  }
}

///|
/// `deserialize_seq` with a visitor that accepts sequences.
pub fn[T] Deserializer::deserialize_seq(
  self : Deserializer,
  exp : String,
  visit_seq : (SeqAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  match self {
    FromJson(de) => de.deserialize_seq(exp, visit_seq)
    FromValue(Array(items)) => visit_array(items, visit_seq)
    FromValue(value) =>
      raise SerdeJsonError::invalid_type(value.unexpected(), exp)
  }
}

///|
/// `deserialize_tuple_struct` (both deserializers forward it to
/// `deserialize_seq`).
pub fn[T] Deserializer::deserialize_tuple_struct(
  self : Deserializer,
  exp : String,
  visit_seq : (SeqAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  self.deserialize_seq(exp, visit_seq)
}

///|
/// `deserialize_map` with a visitor that accepts maps.
pub fn[T] Deserializer::deserialize_map(
  self : Deserializer,
  exp : String,
  visit_map : (MapAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  match self {
    FromJson(de) => de.deserialize_map(exp, visit_map)
    FromValue(Object(object)) => visit_object(object, visit_map)
    FromValue(value) =>
      raise SerdeJsonError::invalid_type(value.unexpected(), exp)
  }
}

///|
/// `deserialize_struct` with a derived struct visitor (expecting `exp`,
/// e.g. `"struct Grammar"`).
pub fn[T] Deserializer::deserialize_struct(
  self : Deserializer,
  exp : String,
  visit_seq : (SeqAccess) -> T raise SerdeJsonError,
  visit_map : (MapAccess) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  match self {
    FromJson(de) => de.deserialize_struct(exp, visit_seq, visit_map)
    FromValue(Array(items)) => visit_array(items, visit_seq)
    FromValue(Object(object)) => visit_object(object, visit_map)
    FromValue(value) =>
      raise SerdeJsonError::invalid_type(value.unexpected(), exp)
  }
}

///|
/// `serde_json::from_value` with the deserialization `f`.
pub fn[T] from_value(
  value : Value,
  f : (Deserializer) -> T raise SerdeJsonError,
) -> T raise SerdeJsonError {
  f(FromValue(value))
}

///|
/// `String::deserialize`.
pub fn deserialize_string(de : Deserializer) -> String raise SerdeJsonError {
  de.deserialize_str("a string", s => s)
}

///|
/// `PathBuf::deserialize`.
pub fn deserialize_path_buf(de : Deserializer) -> String raise SerdeJsonError {
  de.deserialize_str("path string", s => s)
}

///|
/// `Vec::<T>::deserialize`, deserializing the elements with `f`.
pub fn[T] deserialize_vec(
  de : Deserializer,
  f : (Deserializer) -> T raise SerdeJsonError,
) -> Array[T] raise SerdeJsonError {
  de.deserialize_seq("a sequence", seq => {
    let values = []
    while seq.next_element(f) is Some(value) {
      values.push(value)
    }
    values
  })
}

///|
/// `BTreeMap::<String, Value>::deserialize`: the entries in key order.
pub fn deserialize_btree_map(
  de : Deserializer,
) -> Array[(String, Value)] raise SerdeJsonError {
  de.deserialize_map("a map", map => {
    let values : Map[String, Value] = Map([])
    while map.next_key() is Some(key) {
      values[key] = map.next_value(Deserializer::deserialize_value)
    }
    let entries = values.to_array()
    entries.sort_by((a, b) => compare_str(a.0, b.0))
    entries
  })
}

///|
/// Rust's `Ord for str`: the order of the UTF-8 bytes.
pub fn compare_str(a : String, b : String) -> Int32 {
  let x = @utf8.encode(a)
  let y = @utf8.encode(b)
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<n {
    let c = x[i].compare(y[i])
    if c != 0 {
      return c
    }
  }
  x.length().compare(y.length())
}

///|
/// The `Option<T>` slot of a field in a derived `visit_map`.
pub struct StructField[T] {
  priv name : String
  priv mut value : T?
}

///|
/// A field named `name` (its deserialize name).
pub fn[T] StructField::new(name : String) -> StructField[T] {
  { name, value: None, }
}

///|
/// The arm of a derived `visit_map` for this field's key: `duplicate_field`
/// if it was already seen, otherwise `next_value` with `f`.
pub fn[T] StructField::next_value(
  self : StructField[T],
  map : MapAccess,
  f : (Deserializer) -> T raise SerdeJsonError,
) -> Unit raise SerdeJsonError {
  if self.value is Some(_) {
    raise SerdeJsonError::duplicate_field(self.name)
  }
  self.value = Some(map.next_value(f))
}

///|
/// The value of a field without a default (`missing_field` when absent).
pub fn[T] StructField::required(
  self : StructField[T],
) -> T raise SerdeJsonError {
  match self.value {
    Some(value) => value
    None => raise SerdeJsonError::missing_field(self.name)
  }
}

///|
/// The value of an `Option` field: an absent field deserializes as `None`
/// (`missing_field` uses `deserialize_option`).
pub fn[T] StructField::optional(self : StructField[T?]) -> T? {
  match self.value {
    Some(value) => value
    None => None
  }
}

///|
/// The value of a field with `#[serde(default)]`.
pub fn[T] StructField::or_default(self : StructField[T], default : T) -> T {
  match self.value {
    Some(value) => value
    None => default
  }
}
