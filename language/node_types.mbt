///|
priv struct ShapeField {
  types : Array[(String, Bool)]
  min : Int32
  max : Int32
} derive(Eq)

///|
priv struct Shape {
  all : ShapeField
  loose : ShapeField
  named : ShapeField
  fields : Map[String, ShapeField]
} derive(Eq)

///|
fn empty_field() -> ShapeField {
  { types: [], min: 0, max: 0, }
}

///|
fn empty_shape() -> Shape {
  {
    all: empty_field(),
    loose: empty_field(),
    named: empty_field(),
    fields: Map([]),
  }
}

///|
fn type_order(a : (String, Bool), b : (String, Bool)) -> Int32 {
  let order = name_order(a.0, b.0)
  if order == 0 {
    a.1.compare(b.1)
  } else {
    order
  }
}

///|
fn combine_field(a : ShapeField, b : ShapeField, sequence : Bool) -> ShapeField {
  let types = a.types.copy()
  for item in b.types {
    if !types.contains(item) {
      types.push(item)
    }
  }
  types.sort_by(type_order)
  {
    types,
    min: if sequence {
      Int32::min(2, a.min + b.min)
    } else {
      Int32::min(a.min, b.min)
    },
    max: if sequence {
      Int32::min(2, a.max + b.max)
    } else {
      Int32::max(a.max, b.max)
    },
  }
}

///|
fn combine_shape(a : Shape, b : Shape, sequence : Bool) -> Shape {
  let fields : Map[String, ShapeField] = Map([])
  for (name, field) in a.fields {
    fields[name] = combine_field(
      field,
      b.fields.get(name).unwrap_or(empty_field()),
      sequence,
    )
  }
  for (name, field) in b.fields {
    if !fields.contains(name) {
      fields[name] = combine_field(empty_field(), field, sequence)
    }
  }
  {
    all: combine_field(a.all, b.all, sequence),
    loose: combine_field(a.loose, b.loose, sequence),
    named: combine_field(a.named, b.named, sequence),
    fields,
  }
}

///|
fn leaf_shape(identity : (String, Bool), field : String?) -> Shape {
  let one : ShapeField = { types: [identity], min: 1, max: 1, }
  let fields : Map[String, ShapeField] = Map([])
  if field is Some(name) {
    fields[name] = one
  }
  {
    all: one,
    loose: if field is None {
      one
    } else {
      empty_field()
    },
    named: if field is None && identity.1 {
      one
    } else {
      empty_field()
    },
    fields,
  }
}

///|
fn inherited_shape(child : Shape, field : String?) -> Shape {
  guard field is Some(name) else { return child }
  let fields = child.fields.copy()
  fields[name] = combine_field(
    fields.get(name).unwrap_or(empty_field()),
    child.all,
    true,
  )
  { ..child, loose: empty_field(), named: empty_field(), fields, }
}

///|
fn Language::shapes(self : Language) -> Array[Shape?] {
  let shapes : Array[Shape?] = Array::make(self.symbols.length(), None)
  // Only evaluate a production once its hidden dependencies have a summary.
  // Productive recursive rules acquire their first summary from a base case.
  // Counts saturate at two; subsequent iterations monotonically widen the set
  // of types and cardinalities until recursive repetitions reach a fixed point.
  let mut changed = true
  while changed {
    changed = false
    for production in self.productions {
      let mut value = empty_shape()
      let mut ready = true
      for step in production.steps {
        let symbol = self.symbols[step.symbol]
        let child = if step.rename is Some(identity) {
          leaf_shape(identity, step.field)
        } else if symbol.visible || self.supertypes.contains(step.symbol) {
          let leaf = leaf_shape((symbol.name, symbol.named), step.field)
          if self.supertypes.contains(step.symbol) &&
            shapes[step.symbol] is Some(shape) {
            let fields = shape.fields.copy()
            for (name, info) in leaf.fields {
              fields[name] = combine_field(
                fields.get(name).unwrap_or(empty_field()),
                info,
                true,
              )
            }
            { ..leaf, fields, }
          } else {
            leaf
          }
        } else if symbol.terminal {
          empty_shape()
        } else if shapes[step.symbol] is Some(shape) {
          inherited_shape(shape, step.field)
        } else {
          ready = false
          break
        }
        value = combine_shape(value, child, true)
      }
      if ready {
        let next = match shapes[production.lhs] {
          Some(old) => combine_shape(old, value, false)
          None => value
        }
        if shapes[production.lhs] != Some(next) {
          shapes[production.lhs] = Some(next)
          changed = true
        }
      }
    }
  }
  shapes
}

///|
fn type_json(identity : (String, Bool)) -> Json {
  Json::object({ "type": Json(identity.0), "named": Json(identity.1) })
}

///|
fn field_json(
  field : ShapeField,
  supertypes : Array[((String, Bool), Array[(String, Bool)])],
) -> Json {
  let mut types = field.types.copy()
  for (supertype, subtypes) in supertypes {
    if !subtypes.is_empty() && subtypes.all(t => types.contains(t)) {
      types = types.filter(t => !subtypes.contains(t))
      if !types.contains(supertype) {
        types.push(supertype)
      }
    }
  }
  types.sort_by(type_order)
  Json::object({
    "multiple": Json(field.max > 1),
    "required": Json(field.min > 0),
    "types": Json(types.map(type_json)),
  })
}

///|
/// Describe visible node identities, fields, child cardinalities, aliases and
/// abstract supertypes in Tree-sitter's node-types.json interchange format.
pub fn Language::node_types(self : Language) -> Json {
  let shapes = self.shapes()
  let appearances : Map[(String, Bool), Array[Int32]] = Map([])
  fn add(identity : (String, Bool), id : Int32) {
    match appearances.get(identity) {
      Some(ids) => if !ids.contains(id) { ids.push(id) }
      None => appearances[identity] = [id]
    }
  }
  let root = self.symbols[self.start_symbol]
  add((root.name, root.named), self.start_symbol)
  let reachable : Map[Int32, Bool] = Map([(self.start_symbol, true)])
  for id in self.extras {
    reachable[id] = true
  }
  let mut changed = true
  while changed {
    changed = false
    for production in self.productions {
      if !reachable.contains(production.lhs) {
        continue
      }
      for step in production.steps {
        if !reachable.contains(step.symbol) {
          reachable[step.symbol] = true
          changed = true
        }
      }
    }
  }
  for production in self.productions {
    if !reachable.contains(production.lhs) {
      continue
    }
    for step in production.steps {
      let symbol = self.symbols[step.symbol]
      if step.rename is Some(identity) {
        add(identity, step.symbol)
      } else if symbol.visible || self.supertypes.contains(step.symbol) {
        add((symbol.name, symbol.named), step.symbol)
      }
    }
  }
  for id in self.extras {
    let symbol = self.symbols[id]
    if symbol.visible {
      add((symbol.name, symbol.named), id)
    }
  }
  // Lexical tokens extracted before an unreachable EOF alternative is
  // removed still belong to the generated language's public token inventory.
  for token in self.tokens {
    let symbol = self.symbols[token.symbol]
    if token.literal &&
      symbol.visible &&
      !symbol.named &&
      !self.productions.any(p => p.steps.any(s => s.symbol == token.symbol)) {
      add((symbol.name, symbol.named), token.symbol)
    }
  }
  let subtypes = self.supertypes.map(id => {
    let symbol = self.symbols[id]
    ((symbol.name, symbol.named), shapes[id].unwrap_or(empty_shape()).all.types)
  })
  // Process child supertypes before their parents when collapsing unions.
  let ordered : Array[((String, Bool), Array[(String, Bool)])] = []
  let pending = subtypes.copy()
  while !pending.is_empty() {
    let mut index = 0
    for i, pair in pending {
      if !pair.1.any(t => pending.any(other => other.0 == t)) {
        index = i
        break
      }
    }
    ordered.push(pending.remove(index))
  }
  let result : Array[(Int32, (String, Bool), Json)] = []
  for (identity, ids) in appearances {
    let json : Map[String, Json] = {
      "type": Json(identity.0),
      "named": Json(identity.1),
    }
    let supertype = subtypes.iter().find_first(p => p.0 == identity)
    let mut category = 2
    if supertype is Some((_, types)) {
      json["subtypes"] = Json(types.map(type_json))
      category = 0
    } else {
      let mut combined : Shape? = None
      let mut structured = false
      for id in ids {
        if !self.symbols[id].terminal {
          structured = true
        }
        let shape = shapes[id].unwrap_or(empty_shape())
        combined = Some(
          match combined {
            Some(old) => combine_shape(old, shape, false)
            None => shape
          },
        )
      }
      if structured {
        category = 1
        let shape = combined.unwrap_or(empty_shape())
        let fields : Map[String, Json] = Map([])
        let names = shape.fields.keys().to_array()
        names.sort_by(name_order)
        for name in names {
          let field = shape.fields[name]
          if !field.types.is_empty() {
            fields[name] = field_json(field, ordered)
          }
        }
        json["fields"] = Json::object(fields)
        if !shape.named.types.is_empty() {
          json["children"] = field_json(shape.named, ordered)
        }
      }
    }
    if ids.contains(self.start_symbol) && identity == (root.name, root.named) {
      json["root"] = Json(true)
    }
    if ids.any(id => self.extras.contains(id)) {
      json["extra"] = Json(true)
    }
    result.push((category, identity, Json::object(json)))
  }
  result.sort_by((a, b) => {
    let order = a.0.compare(b.0)
    if order == 0 {
      type_order(a.1, b.1)
    } else {
      order
    }
  })
  Json(result.map(row => row.2))
}

///|
fn name_order(a : String, b : String) -> Int32 {
  let left = a.iter().to_array()
  let right = b.iter().to_array()
  for i in 0..<Int32::min(left.length(), right.length()) {
    let order = left[i].compare(right[i])
    if order != 0 {
      return order
    }
  }
  left.length().compare(right.length())
}
