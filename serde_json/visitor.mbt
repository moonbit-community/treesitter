// serde's `Visitor` trait as a value: each `visit_*` method is optional, and
// a missing one behaves as serde's provided method (an `invalid type` error
// naming what the visitor expects, or forwarding to a wider method).

///|
/// A serde `Visitor` producing a `T`. `expecting` is its `expecting` text
/// (`"a string"`, `"struct GrammarJSON"`, ...).
pub struct Visitor[T] {
  expecting : String
  visit_bool : ((Bool) -> T raise JsonError)?
  visit_i64 : ((Int64) -> T raise JsonError)?
  visit_u64 : ((UInt64) -> T raise JsonError)?
  visit_f64 : ((Double) -> T raise JsonError)?
  visit_str : ((String) -> T raise JsonError)?
  visit_unit : (() -> T raise JsonError)?
  visit_none : (() -> T raise JsonError)?
  visit_some : ((Deserializer) -> T raise JsonError)?
  visit_seq : ((SeqAccess) -> T raise JsonError)?
  visit_map : ((MapAccess) -> T raise JsonError)?
}

///|
pub fn[T] Visitor::new(
  expecting : String,
  visit_bool? : (Bool) -> T raise JsonError,
  visit_i64? : (Int64) -> T raise JsonError,
  visit_u64? : (UInt64) -> T raise JsonError,
  visit_f64? : (Double) -> T raise JsonError,
  visit_str? : (String) -> T raise JsonError,
  visit_unit? : () -> T raise JsonError,
  visit_none? : () -> T raise JsonError,
  visit_some? : (Deserializer) -> T raise JsonError,
  visit_seq? : (SeqAccess) -> T raise JsonError,
  visit_map? : (MapAccess) -> T raise JsonError,
) -> Visitor[T] {
  {
    expecting,
    visit_bool,
    visit_i64,
    visit_u64,
    visit_f64,
    visit_str,
    visit_unit,
    visit_none,
    visit_some,
    visit_seq,
    visit_map,
  }
}

///|
fn[T] Visitor::bool(self : Visitor[T], v : Bool) -> T raise JsonError {
  match self.visit_bool {
    Some(f) => f(v)
    None => raise invalid_type(Unexpected::Bool(v), self.expecting)
  }
}

///|
fn[T] Visitor::i64(self : Visitor[T], v : Int64) -> T raise JsonError {
  match self.visit_i64 {
    Some(f) => f(v)
    None => raise invalid_type(Unexpected::Signed(v), self.expecting)
  }
}

///|
fn[T] Visitor::u64(self : Visitor[T], v : UInt64) -> T raise JsonError {
  match self.visit_u64 {
    Some(f) => f(v)
    None => raise invalid_type(Unexpected::Unsigned(v), self.expecting)
  }
}

///|
fn[T] Visitor::f64(self : Visitor[T], v : Double) -> T raise JsonError {
  match self.visit_f64 {
    Some(f) => f(v)
    None => raise invalid_type(Unexpected::Float(v), self.expecting)
  }
}

///|
fn[T] Visitor::str(self : Visitor[T], v : String) -> T raise JsonError {
  match self.visit_str {
    Some(f) => f(v)
    None => raise invalid_type(Unexpected::Str(v), self.expecting)
  }
}

///|
fn[T] Visitor::unit(self : Visitor[T]) -> T raise JsonError {
  match self.visit_unit {
    Some(f) => f()
    None => raise invalid_type(Unexpected::Unit, self.expecting)
  }
}

///|
fn[T] Visitor::none(self : Visitor[T]) -> T raise JsonError {
  match self.visit_none {
    Some(f) => f()
    None => raise invalid_type(Unexpected::Option, self.expecting)
  }
}

///|
fn[T] Visitor::some(self : Visitor[T], de : Deserializer) -> T raise JsonError {
  match self.visit_some {
    Some(f) => f(de)
    None => raise invalid_type(Unexpected::Option, self.expecting)
  }
}

///|
fn[T] Visitor::seq(self : Visitor[T], seq : SeqAccess) -> T raise JsonError {
  match self.visit_seq {
    Some(f) => f(seq)
    None => raise invalid_type(Unexpected::Seq, self.expecting)
  }
}

///|
fn[T] Visitor::map(self : Visitor[T], map : MapAccess) -> T raise JsonError {
  match self.visit_map {
    Some(f) => f(map)
    None => raise invalid_type(Unexpected::Map, self.expecting)
  }
}

// serde's visitors for primitive types ----------------------------------------

///|
/// `String::deserialize`'s visitor.
pub let string_visitor : Visitor[String] = Visitor::new("a string", visit_str=s => {
  visit_string(s)
})

///|
fn visit_string(s : String) -> String {
  s
}

///|
/// `bool::deserialize`'s visitor.
pub let bool_visitor : Visitor[Bool] = Visitor::new("a boolean", visit_bool=b => {
  visit_bool(b)
})

///|
fn visit_bool(b : Bool) -> Bool {
  b
}

///|
/// `i32::deserialize`'s visitor.
pub let i32_visitor : Visitor[Int32] = Visitor::new(
  "i32",
  visit_i64=v => {
    if v >= -2147483648L && v <= 2147483647L {
      v.to_int()
    } else {
      raise invalid_value(Unexpected::Signed(v), "i32")
    }
  },
  visit_u64=v => {
    if v <= 2147483647UL {
      v.to_int()
    } else {
      raise invalid_value(Unexpected::Unsigned(v), "i32")
    }
  },
)

///|
/// `u64::deserialize`'s visitor.
pub let u64_visitor : Visitor[UInt64] = Visitor::new(
  "u64",
  visit_i64=v => {
    if v >= 0L {
      v.reinterpret_as_uint64()
    } else {
      raise invalid_value(Unexpected::Signed(v), "u64")
    }
  },
  visit_u64=v => v,
)

///|
/// `String::deserialize`.
pub fn Deserializer::deserialize_string(
  self : Deserializer,
) -> String raise JsonError {
  self.deserialize_str(string_visitor)
}

///|
/// `Option::<T>::deserialize`, with `T::deserialize` as `some`.
pub fn[T] Deserializer::deserialize_option_with(
  self : Deserializer,
  some : (Deserializer) -> T raise JsonError,
) -> T? raise JsonError {
  self.deserialize_option(
    Visitor::new("option", visit_none=() => None, visit_unit=() => None, visit_some=de => {
      Some(some(de))
    }),
  )
}

///|
/// `Vec::<T>::deserialize`, with `T::deserialize` as `element`.
pub fn[T] Deserializer::deserialize_vec(
  self : Deserializer,
  element : (Deserializer) -> T raise JsonError,
) -> Array[T] raise JsonError {
  self.deserialize_seq(
    Visitor::new("a sequence", visit_seq=seq => {
      let values = []
      while seq.next_element(element) is Some(value) {
        values.push(value)
      }
      values
    }),
  )
}
