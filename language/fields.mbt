///|
// Field ids are one-based and sorted by Unicode scalar values, matching the
// upstream UTF-8 name table (including names beyond the BMP).
fn collect_field_names(productions : Array[Production]) -> Array[String] {
  let names : Map[String, Unit] = Map([])
  for production in productions {
    for step in production.steps {
      if step.field is Some(name) {
        names[name] = ()
      }
    }
  }
  let sorted = names
    .keys()
    .map(name => (name, name.iter().to_array()))
    .to_array()
  sorted.sort_by((a, b) => {
    for i in 0..<Int32::min(a.1.length(), b.1.length()) {
      let order = a.1[i].compare(b.1[i])
      if order != 0 {
        return order
      }
    }
    a.1.length().compare(b.1.length())
  })
  sorted.map(pair => pair.0)
}

///|
/// Number of distinct field names in the generated language.
pub fn Language::field_count(self : Language) -> Int32 {
  self.field_names.length()
}

///|
/// Resolve a field name to its one-based id. Unknown names return None.
pub fn Language::field_id(self : Language, name : String) -> Int32? {
  self.field_names.search(name).map(i => i + 1)
}

///|
/// Resolve a field id; zero, negative and out-of-range ids return None.
pub fn Language::field_name(self : Language, id : Int32) -> String? {
  if id <= 0 {
    None
  } else {
    self.field_names.get(id - 1)
  }
}
