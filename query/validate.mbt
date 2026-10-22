///|
fn schema_entry(
  schema : Array[Json],
  kind : String,
  named : Bool?,
) -> Map[String, Json]? {
  for entry in schema {
    if entry is Object(object) &&
      object.get("type") == Some(Json(kind)) &&
      (named is None || object.get("named") == Some(Json(named.unwrap()))) {
      return Some(object)
    }
  }
  None
}

///|
fn schema_types(info : Json?) -> Array[Json] {
  match info {
    Some(Object(object)) =>
      match object.get("types") {
        Some(Array(types)) => types
        _ => []
      }
    _ => []
  }
}

///|
fn allows_kind(
  schema : Array[Json],
  types : Array[Json],
  pattern : Pattern,
  visited : Array[String],
) -> Bool {
  match pattern {
    Capture(inner, _) => allows_kind(schema, types, inner, visited)
    Either(items) => items.any(p => allows_kind(schema, types, p, visited))
    Group(_, _) => true
    Node(node) => {
      guard node.kind is Some(kind) else { return true }
      if kind == "ERROR" || node.missing {
        return true
      }
      for item in types {
        if item is Object(object) && object.get("type") is Some(String(name)) {
          if name == kind &&
            (
              node.named is None ||
              object.get("named") == Some(Json(node.named.unwrap()))
            ) {
            return true
          }
          if !visited.contains(name) &&
            schema_entry(schema, name, None) is Some(entry) &&
            entry.get("subtypes") is Some(Array(subtypes)) &&
            allows_kind(schema, subtypes, pattern, visited + [name]) {
            return true
          }
        }
      }
      false
    }
  }
}

///|
fn validate_structure(
  schema : Array[Json],
  pattern : Pattern,
  offset : Int32,
) -> Unit raise QueryError {
  match pattern {
    Capture(inner, _) => validate_structure(schema, inner, offset)
    Either(items) =>
      for item in items {
        validate_structure(schema, item, offset)
      }
    Group(children, _) =>
      for child in children {
        validate_structure(schema, child.pattern, offset)
      }
    Node(node) => {
      let entry = match node.kind {
        Some(kind) => schema_entry(schema, kind, node.named)
        None => None
      }
      for child in node.children {
        validate_structure(schema, child.pattern, offset)
        if entry is Some(entry) && !entry.contains("subtypes") {
          let fields = match entry.get("fields") {
            Some(Object(fields)) => fields
            _ => Map([])
          }
          if child.field is Some(field) {
            if !fields.contains(field) ||
              !allows_kind(
                schema,
                schema_types(fields.get(field)),
                child.pattern,
                [],
              ) {
              raise InvalidQuery(
                offset,
                "impossible child for field '\{field}'",
              )
            }
          } else {
            let types = schema_types(entry.get("children")).copy()
            for extra in schema {
              if extra is Object(object) &&
                object.get("extra") == Some(Json(true)) {
                types.push(extra)
              }
            }
            for info in fields.values() {
              types.append(schema_types(Some(info)))
            }
            // Anonymous tokens are omitted from node-types' unfielded children.
            // Validate named constraints only; punctuation order is handled by
            // the query matcher against the concrete tree.
            if named_constraint(child.pattern) &&
              !allows_kind(schema, types, child.pattern, []) {
              raise InvalidQuery(
                offset,
                "impossible named child for '\{node.kind.unwrap()}'",
              )
            }
          }
        }
      }
    }
  }
}

///|
fn named_constraint(pattern : Pattern) -> Bool {
  match pattern {
    Capture(inner, _) => named_constraint(inner)
    Node(node) => node.named == Some(true) && node.kind is Some(_)
    Either(items) => items.all(named_constraint)
    Group(_, _) => false
  }
}
