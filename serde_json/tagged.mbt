// Internally tagged enums (`#[serde(tag = "...")]`): serde's
// `TaggedContentVisitor`, which finds the tag and buffers the rest of the
// value as `Content`, over the three deserializers it can run on.

///|
/// The variant identifier of an enum whose variants are `variants`
/// (serde_derive's `__FieldVisitor` for variants).
fn variant_by_name(
  name : String,
  variants : Array[String],
) -> Int32 raise JsonError {
  match variants.search(name) {
    Some(i) => i
    None => raise unknown_variant(name, variants)
  }
}

///|
fn variant_by_index(
  index : UInt64,
  variants : Array[String],
) -> Int32 raise JsonError {
  if index < variants.length().to_uint64() {
    index.to_int()
  } else {
    raise invalid_value(
      Unexpected::Unsigned(index),
      "variant index 0 <= i < \{variants.length()}",
    )
  }
}

///|
/// The visitor of a variant identifier.
fn variant_visitor(variants : Array[String]) -> Visitor[Int32] {
  Visitor::new(
    "variant identifier",
    visit_str=s => variant_by_name(s, variants),
    visit_u64=u => variant_by_index(u, variants),
  )
}

///|
/// `Deserializer::deserialize_any` with a `TaggedContentVisitor`: the index
/// of the variant named by the `tag` field (or by the first element of a
/// sequence) and the other fields (or elements) as `Content`. `expecting` is
/// `"internally tagged enum Name"`.
pub fn Deserializer::deserialize_internally_tagged(
  self : Deserializer,
  tag : String,
  expecting : String,
  variants : Array[String],
) -> (Int32, Content) raise JsonError {
  self.deserialize_any(
    Visitor::new(
      expecting,
      visit_seq=seq => {
        let variant = match
          seq.next_element(de => de.deserialize_str(variant_visitor(variants))) {
          Some(variant) => variant
          None => raise missing_field(tag)
        }
        let rest = []
        while seq.next_element(de => de.deserialize_content()) is Some(e) {
          rest.push(e)
        }
        (variant, Content::Seq(rest))
      },
      visit_map=map => {
        let mut variant : Int32? = None
        let pairs = []
        while map.next_key(key => key) is Some(key) {
          if key == tag {
            if variant is Some(_) {
              raise duplicate_field(tag)
            }
            variant = Some(
              map.next_value(de => de.deserialize_str(variant_visitor(variants))),
            )
          } else {
            pairs.push(
              (
                Content::String(key),
                map.next_value(de => de.deserialize_content()),
              ),
            )
          }
        }
        match variant {
          Some(variant) => (variant, Content::Map(pairs))
          None => raise missing_field(tag)
        }
      },
    ),
  )
}

///|
/// `ContentDeserializer::deserialize_identifier` with a variant identifier
/// visitor.
fn Content::deserialize_variant(
  self : Content,
  variants : Array[String],
) -> Int32 raise JsonError {
  match self {
    String(s) => variant_by_name(s, variants)
    U64(u) => variant_by_index(u, variants)
    _ => raise invalid_type(self.unexpected(), "variant identifier")
  }
}

///|
/// `ContentDeserializer::deserialize_any` with a `TaggedContentVisitor`.
pub fn Content::deserialize_internally_tagged(
  self : Content,
  tag : String,
  expecting : String,
  variants : Array[String],
) -> (Int32, Content) raise JsonError {
  match self {
    Map(pairs) => {
      let mut variant : Int32? = None
      let rest = []
      for pair in pairs {
        let (key, value) = pair
        if key is String(name) && name == tag {
          if variant is Some(_) {
            raise duplicate_field(tag)
          }
          variant = Some(value.deserialize_variant(variants))
        } else {
          rest.push((key, value))
        }
      }
      match variant {
        Some(variant) => (variant, Map(rest))
        None => raise missing_field(tag)
      }
    }
    Seq(items) => {
      guard items.get(0) is Some(first) else { raise missing_field(tag) }
      let variant = first.deserialize_variant(variants)
      (variant, Seq(items[1:].to_owned()))
    }
    _ => raise invalid_type(self.unexpected(), expecting)
  }
}

///|
/// `Value::deserialize_identifier` (`deserialize_string`) with a variant
/// identifier visitor.
fn Value::deserialize_variant(
  self : Value,
  variants : Array[String],
) -> Int32 raise JsonError {
  match self {
    String(s) => variant_by_name(s, variants)
    _ => raise invalid_type(self.unexpected(), "variant identifier")
  }
}

///|
/// `Value::deserialize_any` with a `TaggedContentVisitor` (what
/// `serde_json::from_value` does for an internally tagged enum).
pub fn Value::deserialize_internally_tagged(
  self : Value,
  tag : String,
  expecting : String,
  variants : Array[String],
) -> (Int32, Content) raise JsonError {
  match self {
    Object(map) => {
      let mut variant : Int32? = None
      let rest = []
      for key, value in map {
        if key == tag {
          variant = Some(value.deserialize_variant(variants))
        } else {
          rest.push((Content::String(key), value.to_content()))
        }
      }
      match variant {
        Some(variant) => (variant, Content::Map(rest))
        None => raise missing_field(tag)
      }
    }
    Array(values) => {
      guard values.get(0) is Some(first) else { raise missing_field(tag) }
      let variant = first.deserialize_variant(variants)
      (
        variant,
        Content::Seq(values[1:].iter().map(Value::to_content).collect()),
      )
    }
    _ => raise invalid_type(self.unexpected(), expecting)
  }
}
