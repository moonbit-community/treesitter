// serde 1.0.229's private `Content` (a buffered value, which internally
// tagged and untagged enums deserialize from) and its `ContentDeserializer`
// (src/private/de.rs), for the content a JSON document produces. Errors
// raised here have no position: serde_json gives them the position of the
// enclosing `deserialize_*` call of the streaming deserializer, if any.

///|
/// `serde::__private::de::Content`, for JSON input.
pub(all) enum Content {
  Bool(Bool)
  U64(UInt64)
  I64(Int64)
  F64(Double)
  String(String)
  Unit
  Seq(Array[Content])
  Map(Array[(Content, Content)])
} derive(Eq, Debug)

///|
/// `content_unexpected`.
pub fn Content::unexpected(self : Content) -> Unexpected {
  match self {
    Bool(b) => Unexpected::Bool(b)
    U64(n) => Unexpected::Unsigned(n)
    I64(n) => Unexpected::Signed(n)
    F64(f) => Unexpected::Float(f)
    String(s) => Unexpected::Str(s)
    Unit => Unexpected::Unit
    Seq(_) => Unexpected::Seq
    Map(_) => Unexpected::Map
  }
}

///|
/// `ContentVisitor`.
fn content_visitor() -> Visitor[Content] {
  Visitor::new(
    "any value",
    visit_bool=b => Bool(b),
    visit_i64=i => I64(i),
    visit_u64=u => U64(u),
    visit_f64=f => F64(f),
    visit_str=s => String(s),
    visit_unit=() => Unit,
    visit_seq=seq => {
      let vec = []
      while seq.next_element(de => de.deserialize_content()) is Some(e) {
        vec.push(e)
      }
      Seq(vec)
    },
    visit_map=map => {
      let vec = []
      while map.next_key(key => Content::String(key)) is Some(key) {
        vec.push((key, map.next_value(de => de.deserialize_content())))
      }
      Map(vec)
    },
  )
}

///|
/// `Content::deserialize` (`__deserialize_content`, i.e. `deserialize_any`
/// with `ContentVisitor`).
pub fn Deserializer::deserialize_content(
  self : Deserializer,
) -> Content raise JsonError {
  self.deserialize_any(content_visitor())
}

// ContentDeserializer ----------------------------------------------------------

///|
/// `ContentDeserializer::deserialize_string` with `String`'s visitor.
pub fn Content::deserialize_string(self : Content) -> String raise JsonError {
  match self {
    String(s) => s
    _ => raise invalid_type(self.unexpected(), "a string")
  }
}

///|
/// `ContentDeserializer::deserialize_bool` with `bool`'s visitor.
pub fn Content::deserialize_bool(self : Content) -> Bool raise JsonError {
  match self {
    Bool(b) => b
    _ => raise invalid_type(self.unexpected(), "a boolean")
  }
}

///|
/// `ContentDeserializer::deserialize_integer` with `i32`'s visitor.
pub fn Content::deserialize_i32(self : Content) -> Int32 raise JsonError {
  match self {
    U64(v) => i32_visitor.u64(v)
    I64(v) => i32_visitor.i64(v)
    _ => raise invalid_type(self.unexpected(), "i32")
  }
}

///|
/// `ContentDeserializer::deserialize_option` with `Option<T>`'s visitor:
/// `null` is `None`, anything else is deserialized by `some`.
pub fn[T] Content::deserialize_option(
  self : Content,
  some : (Content) -> T raise JsonError,
) -> T? raise JsonError {
  match self {
    Unit => None
    _ => Some(some(self))
  }
}

///|
/// `ContentDeserializer::deserialize_seq` with `Vec<T>`'s visitor.
pub fn[T] Content::deserialize_vec(
  self : Content,
  element : (Content) -> T raise JsonError,
) -> Array[T] raise JsonError {
  match self {
    Seq(items) => items.map(element)
    _ => raise invalid_type(self.unexpected(), "a sequence")
  }
}

///|
/// The field index of a struct field key (serde_derive's field identifier
/// visitor through `ContentDeserializer::deserialize_identifier`), or -1 for
/// an unknown field, which is ignored.
fn Content::field_index(
  self : Content,
  fields : Array[String],
) -> Int32 raise JsonError {
  match self {
    String(s) =>
      match fields.search(s) {
        Some(i) => i
        None => -1
      }
    U64(v) => if v < fields.length().to_uint64() { v.to_int() } else { -1 }
    _ => raise invalid_type(self.unexpected(), "field identifier")
  }
}

///|
/// serde_derive's visitor of a struct (or struct variant) whose `expecting`
/// text is `expecting` and whose fields are `fields`, through
/// `ContentDeserializer::deserialize_any`.
///
/// From a map, `deserialize_field(i, value)` is called for each known field
/// in document order (a repeated field is a `duplicate field` error) and
/// unknown fields are ignored; from a sequence, it is called for each field
/// in declaration order (too few elements is an `invalid length` error, and
/// so are left-over elements, once the value is built). `finish(present)`
/// then builds the value; `present[i]` tells whether field `i` was seen, and
/// it is responsible for the `missing field` errors (in field order).
pub fn[T] Content::deserialize_struct(
  self : Content,
  expecting : String,
  fields : Array[String],
  deserialize_field : (Int32, Content) -> Unit raise JsonError,
  finish : (Array[Bool]) -> T raise JsonError,
) -> T raise JsonError {
  let n = fields.length()
  match self {
    Map(pairs) => {
      let present = Array::make(n, false)
      for pair in pairs {
        let (key, value) = pair
        let i = key.field_index(fields)
        if i >= 0 {
          if present[i] {
            raise duplicate_field(fields[i])
          }
          present[i] = true
          deserialize_field(i, value)
        }
      }
      finish(present)
    }
    Seq(items) => {
      let seq_expecting = if n == 1 {
        "\{expecting} with 1 element"
      } else {
        "\{expecting} with \{n} elements"
      }
      for i in 0..<n {
        if i >= items.length() {
          raise invalid_length(i, seq_expecting)
        }
        deserialize_field(i, items[i])
      }
      let value = finish(Array::make(n, true))
      // `SeqDeserializer::end`.
      if items.length() > n {
        raise invalid_length(items.length(), expected_in_seq(n))
      }
      value
    }
    _ => raise invalid_type(self.unexpected(), expecting)
  }
}

///|
/// serde's `InternallyTaggedUnitVisitor` through
/// `ContentDeserializer::deserialize_any`: the content of a unit variant of
/// an internally tagged enum. A map may hold any other fields; a sequence
/// must be empty.
pub fn Content::deserialize_internally_tagged_unit(
  self : Content,
  type_name : String,
  variant_name : String,
) -> Unit raise JsonError {
  match self {
    Map(_) => ()
    Seq(items) =>
      // `visit_seq` consumes nothing; `SeqDeserializer::end` then rejects
      // the remaining elements.
      if items.length() > 0 {
        raise invalid_length(items.length(), expected_in_seq(0))
      }
    _ =>
      raise invalid_type(
        self.unexpected(),
        "unit variant \{type_name}::\{variant_name}",
      )
  }
}

///|
/// serde_derive's untagged-enum error.
pub fn untagged_mismatch(type_name : String) -> JsonError {
  JsonError::custom(
    "data did not match any variant of untagged enum \{type_name}",
  )
}
